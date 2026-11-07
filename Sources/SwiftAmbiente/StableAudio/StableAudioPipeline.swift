//
//  StableAudioPipeline.swift
//  SwiftAmbiente
//
//  Sortie 9 (OPERATION PHANTOM FOLEY, WU2): the full text → waveform → WAV
//  pipeline: T5Gemma (S7) → DiT ping-pong sampler (S8) → SAME-S decoder (S9) →
//  patched-pretransform unpatch → trim → interleave → `WAVWriter`.
//
//  Reference: optimized/mlx/scripts/sa3_mlx.py steps "── 4. Decode ──" and
//  "── 5. Unpatch + save WAV ──": the `[1, 2, T_lat·4096]` waveform is trimmed to
//  exactly `round(seconds · 44100)` samples and written as 16-bit PCM stereo at
//  44.1 kHz.
//
//  SCOPE: this is NOT the `AmbienteGenerator` conformance (Sortie 10). It is the
//  composable pipeline that conformance will wrap.
//

import Foundation
import MLX

/// Text → 44.1 kHz stereo audio, end to end.
///
/// Not `Sendable`: retains `MLXArray`-backed submodules. Build and run within a
/// single concurrency domain.
public final class StableAudioPipeline {
  public let latentGenerator: StableAudioLatentGenerator
  public let decoder: StableAudioSAMESDecoder

  init(latentGenerator: StableAudioLatentGenerator, decoder: StableAudioSAMESDecoder) {
    self.latentGenerator = latentGenerator
    self.decoder = decoder
  }

  /// Load every component from an Acervo-resolved SFX model directory, sharing a
  /// single safetensors weight map between the DiT and the SAME-S decoder.
  public static func load(fromModelDirectory modelDir: URL) throws -> StableAudioPipeline {
    let assets = try StableAudioModelAssets.load(fromModelDirectory: modelDir)
    let gen = try StableAudioLatentGenerator.load(assets: assets, modelDirectory: modelDir)
    let decoder = try StableAudioSAMESDecoder.load(from: assets.weights)
    return StableAudioPipeline(latentGenerator: gen, decoder: decoder)
  }

  /// Decode a DiT latent `(1, 256, T_lat)` to a channels-first FP32 waveform
  /// `(1, 2, T_lat·4096)` (SAME-S decode dispatch + unpatch).
  public func decodeToWaveform(_ latent: MLXArray) -> MLXArray {
    let patches = decoder.decode(latent)
    let audio = StableAudioSAMESDecoder.unpatch(patches)
    MLX.eval(audio)
    return audio
  }

  /// Number of output frames for a duration: `round(seconds · sampleRate)`,
  /// matching the reference's trim.
  public static func requestedFrames(forSeconds seconds: Double) -> Int {
    Int((seconds * Double(StableAudioLatentGenerator.sampleRate)).rounded())
  }

  /// Trim a `(1, channels, N)` waveform to `frames` and interleave it
  /// (`L,R,L,R,…`) as `[Float]`, the layout `WAVWriter` consumes.
  public static func interleave(_ waveform: MLXArray, frames: Int) -> [Float] {
    let n = min(frames, waveform.shape[2])
    let trimmed = waveform[0, 0..., ..<n]  // (channels, n)
    return trimmed.transposed(1, 0).asType(.float32).asArray(Float.self)
  }

  /// Generate interleaved stereo samples (un-clipped FP32; `WAVWriter` clamps to
  /// `[-1, 1]` when encoding, as the reference's `save_wav` does).
  public func generateSamples(
    prompt: String, settings: GenerationSettings,
    apg: Float = StableAudioLatentGenerator.defaultAPG
  ) -> [Float] {
    let latent = latentGenerator.generateLatent(prompt: prompt, settings: settings, apg: apg)
    let waveform = decodeToWaveform(latent)
    return Self.interleave(
      waveform, frames: Self.requestedFrames(forSeconds: settings.durationSeconds))
  }

  /// Generate a complete 16-bit PCM WAV for `config` (default
  /// ``AmbienteConfig/default``: 44.1 kHz stereo).
  public func generateWAV(
    prompt: String, settings: GenerationSettings, config: AmbienteConfig = .default,
    apg: Float = StableAudioLatentGenerator.defaultAPG
  ) -> Data {
    precondition(
      config.sampleRate == StableAudioLatentGenerator.sampleRate
        && config.channelCount == StableAudioSAMESDecoder.audioChannels,
      "Stable Audio renders 44.1 kHz stereo; config requests "
        + "\(config.sampleRate) Hz × \(config.channelCount) ch")
    let samples = generateSamples(prompt: prompt, settings: settings, apg: apg)
    return WAVWriter.encode(
      samples: samples, sampleRate: config.sampleRate, channels: config.channelCount)
  }
}
