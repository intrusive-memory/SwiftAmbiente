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
  /// The reference CLI's default `--apg` (adaptive projected guidance). The S4
  /// golden fixture was captured with this value.
  public static let defaultAPG: Float = 1.0

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
    try load(
      assets: StableAudioModelAssets.load(fromModelDirectory: modelDir), modelDirectory: modelDir)
  }

  /// Build from already-loaded assets (lets the S9 pipeline share one weight map
  /// between the DiT and the SAME-S decoder).
  static func load(assets: StableAudioModelAssets, modelDirectory modelDir: URL) throws
    -> StableAudioLatentGenerator
  {
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
  /// - Parameter apg: adaptive projected guidance strength, matching the
  ///   reference's `--apg` (default ``defaultAPG`` = 1.0, the value the golden
  ///   fixture was captured with). `≤ 0` gives plain CFG; `≥ 1` uses only the
  ///   component of the guidance difference orthogonal to the conditional
  ///   prediction; values in between blend the two. Ignored when `cfgScale == 1`.
  /// - Parameter onStep: optional per-step observer (step index, latent).
  /// - Returns: an evaluated `(1, io_channels, T_lat)` fp16 latent.
  public func generateLatent(
    prompt: String, settings: GenerationSettings,
    apg: Float = StableAudioLatentGenerator.defaultAPG,
    onStep: ((Int, MLXArray) -> Void)? = nil
  ) -> MLXArray {
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
    let crossAttn = assembled.crossAttn  // (1, S+1, 768)
    let globalCond = assembled.globalCond  // (1, 768)

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
      let condV = parts[0]
      let uncondV = parts[1]

      // rf_denoiser: denoised = x − σ·v, with σ = t. fp32 throughout.
      let sigma = t.reshaped([t.shape[0], 1, 1]).asType(.float32)
      let x32 = x.asType(.float32)
      let condD = x32 - condV.asType(.float32) * sigma
      let uncondD = x32 - uncondV.asType(.float32) * sigma
      let diff = condD - uncondD
      let cfgDiff: MLXArray
      if apg <= 0.0 {
        cfgDiff = diff  // plain CFG
      } else {
        // APG: project diff onto the direction orthogonal to cond_d (per sample,
        // over (C, T)). fp32 throughout, exactly as the reference.
        let norm = MLX.sqrt((condD * condD).sum(axes: [-2, -1], keepDims: true))
        let unit = condD / MLX.maximum(norm, MLXArray(Float(1e-8)))
        let parallel = (diff * unit).sum(axes: [-2, -1], keepDims: true) * unit
        let diffOrth = diff - parallel
        cfgDiff = apg >= 1.0 ? diffOrth : (apg * diffOrth + (1.0 - apg) * diff)
      }
      let cfgD = condD + (cfg - 1.0) * cfgDiff
      let cfgV = (x32 - cfgD) / sigma
      return cfgV.asType(x.dtype)
    }

    // ── Sample ──
    let latent = StableAudioFlowSampler.sampleFlowPingpong(
      x: noise, sigmas: sigmas, seed: seed &+ 1, modelFn: modelFn, onStep: onStep)
    MLX.eval(latent)
    return latent
  }
}
