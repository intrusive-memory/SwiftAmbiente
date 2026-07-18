//
//  StableAudioLatentGenerator.swift
//  SwiftAmbiente
//
//  Sortie 8 (OPERATION PHANTOM FOLEY, WU2): composes S6 (config/assets), S7
//  (T5Gemma conditioning), and the S8 DiT + flow-matching ping-pong sampler into
//  a deterministic *latent* for a prompt + `GenerationSettings`.
//
//  Reference: the driver sequence in
//    Stability-AI/stable-audio-3 → optimized/mlx/scripts/sa3_mlx.py
//      (T_lat derivation · conditioning assembly · CFG model_fn · noise seeding ·
//       sample_flow_pingpong invocation)
//
//  SCOPE (S8 boundary): stops at the latent `(1, io_channels, T_lat)`. Decoding
//  that latent to a 44.1 kHz stereo waveform (the SAME-S decoder) is Sortie 9 and
//  is NOT done here.
//

import Foundation
import MLX
import MLXRandom

/// End-to-end latent generator: prompt + settings → DiT latent.
///
/// Not `Sendable`: retains `MLXArray`-backed submodules. Build and run within a
/// single concurrency domain.
public final class StableAudioLatentGenerator {
  /// Output sample rate the latent grid is derived against.
  public static let sampleRate = 44100
  /// Audio samples represented by one latent position
  /// (`PatchedPretransform downsample × SAME 16× expansion`).
  public static let samplesPerLatent = 4096

  public let config: StableAudioModelConfig
  let dit: StableAudioDiT
  let conditioner: StableAudioConditioner
  let textConditioner: T5GemmaTextConditioner

  init(
    config: StableAudioModelConfig, dit: StableAudioDiT,
    conditioner: StableAudioConditioner, textConditioner: T5GemmaTextConditioner
  ) {
    self.config = config
    self.dit = dit
    self.conditioner = conditioner
    self.textConditioner = textConditioner
  }

  /// Load every component from an Acervo-resolved SFX model directory.
  public static func load(fromModelDirectory modelDir: URL) throws -> StableAudioLatentGenerator {
    let assets = try StableAudioModelAssets.load(fromModelDirectory: modelDir)
    let dit = try StableAudioDiT.load(weights: assets.weights, modelConfig: assets.config)
    let conditioner = try StableAudioConditioner.load(from: assets.weights)
    let textConditioner = try T5GemmaTextConditioner.load(fromModelDirectory: modelDir)
    return StableAudioLatentGenerator(
      config: assets.config, dit: dit, conditioner: conditioner,
      textConditioner: textConditioner)
  }

  /// Latent length for a duration, matching the reference's decoder-independent
  /// natural-ceil: `T_lat = max(1, ceil(seconds · sampleRate / samplesPerLatent))`.
  public static func latentLength(forSeconds seconds: Double) -> Int {
    let raw = seconds * Double(sampleRate) / Double(samplesPerLatent)
    return max(1, Int(ceil(raw)))
  }

  /// Generate a diffusion latent for a prompt + settings.
  ///
  /// Deterministic in `settings.resolvedSeed`: the initial noise is drawn with
  /// `key(seed)` and the sampler with `key(seed + 1)`, exactly as the reference,
  /// so the same seed reproduces the same latent and different seeds diverge.
  ///
  /// - Returns: an evaluated `(1, io_channels, T_lat)` fp16 latent.
  public func generateLatent(prompt: String, settings: GenerationSettings) -> MLXArray {
    let dtype: DType = .float16
    let ioChannels = config.ioChannels
    let tLat = Self.latentLength(forSeconds: settings.durationSeconds)
    let seed = settings.resolvedSeed

    // ── Conditioning ──
    let maxLen = 256
    let cond = textConditioner.encode([prompt], maxLen: maxLen)
    let assembled = conditioner.assemble(
      embeds: cond.embeddings, mask: cond.mask,
      seconds: Float(settings.durationSeconds), dtype: dtype)
    let crossAttn = assembled.crossAttn      // (1, S+1, 768)
    let globalCond = assembled.globalCond    // (1, 768)

    let cfg = Float(settings.cfgScale)
    let useCFG = cfg != 1.0
    // Uncond branch uses zero embeddings when no negative prompt (matches upstream).
    let nullCrossAttn: MLXArray? = useCFG ? MLXArray.zeros(crossAttn.shape, dtype: dtype) : nil

    // ── Schedule + initial noise ──
    let sigmas = StableAudioFlowSampler.buildPingpongSchedule(
      steps: settings.steps, sigmaMax: 1.0, useLogsnrShift: true)
    let noise = MLXRandom.normal(
      [1, ioChannels, tLat], dtype: dtype, key: MLXRandom.key(seed))
    MLX.eval(noise)

    // ── CFG-composed velocity function ──
    let dit = self.dit
    func modelFn(_ x: MLXArray, _ t: MLXArray) -> MLXArray {
      if !useCFG {
        return dit(x, t: t, crossAttnCond: crossAttn, globalCond: globalCond)
      }
      // Batched CFG: one forward over cat([x, x]) on the batch dim.
      let x2 = MLX.concatenated([x, x], axis: 0)
      let t2 = MLX.concatenated([t, t], axis: 0)
      let cross2 = MLX.concatenated([crossAttn, nullCrossAttn!], axis: 0)
      let global2 = MLX.concatenated([globalCond, globalCond], axis: 0)
      let vBatched = dit(x2, t: t2, crossAttnCond: cross2, globalCond: global2)
      let parts = vBatched.split(parts: 2, axis: 0)
      let condV = parts[0], uncondV = parts[1]

      // rf_denoiser: denoised = x − σ·v, with σ = t. fp32 throughout.
      let sigma = t.reshaped([t.shape[0], 1, 1]).asType(.float32)
      let x32 = x.asType(.float32)
      let condD = x32 - condV.asType(.float32) * sigma
      let uncondD = x32 - uncondV.asType(.float32) * sigma
      let diff = condD - uncondD  // apg ≤ 0 → plain CFG (no APG projection)
      let cfgD = condD + (cfg - 1.0) * diff
      let cfgV = (x32 - cfgD) / sigma
      return cfgV.asType(x.dtype)
    }

    // ── Sample ──
    let latent = StableAudioFlowSampler.sampleFlowPingpong(
      x: noise, sigmas: sigmas, seed: seed &+ 1, modelFn: modelFn)
    MLX.eval(latent)
    return latent
  }
}
