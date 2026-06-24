//
//  ProceduralAmbienteGenerator.swift
//  SwiftAmbiente
//
//  Interim, dependency-free generation backend. Produces a usable atmospheric
//  bed from filtered noise so the library is functional before the MLX Stable
//  Audio backend lands. This is NOT a neural model — it is a deterministic DSP
//  fallback that honours the duration / seed contract of ``AmbienteGenerator``.
//

import Foundation

/// A deterministic, ML-free atmospheric generator built from seeded, filtered
/// noise with a slow amplitude drift. Good enough to rough in a background bed
/// (room tone, wind, rain-ish texture); it does not interpret the prompt
/// semantically — the prompt only perturbs the seed so distinct prompts yield
/// distinct (but reproducible) textures.
///
/// Replace at the call site with the MLX Stable Audio generator once available;
/// both conform to ``AmbienteGenerator``.
public struct ProceduralAmbienteGenerator: AmbienteGenerator {
  public let generatorId = "procedural"
  public let displayName = "Procedural (filtered noise — interim)"

  /// Output contract (sample rate / channels) this generator honours.
  public let config: AmbienteConfig

  public init(config: AmbienteConfig = .default) {
    self.config = config
  }

  public func isAvailable() async -> Bool { true }

  public func generate(prompt: String, settings: GenerationSettings) async throws -> Data {
    guard settings.durationSeconds > 0 else {
      throw AmbienteError.invalidDuration(settings.durationSeconds)
    }

    let sampleRate = config.sampleRate
    let channels = max(1, config.channelCount)
    let frameCount = Int((settings.durationSeconds * Double(sampleRate)).rounded())
    guard frameCount > 0 else {
      throw AmbienteError.invalidDuration(settings.durationSeconds)
    }

    // Mix the prompt into the seed so different prompts diverge deterministically.
    var rng = SplitMix64(seed: settings.resolvedSeed &+ Self.promptSalt(prompt))

    var samples = [Float]()
    samples.reserveCapacity(frameCount * channels)

    // Per-channel brown-noise integrators (leaky) decorrelated for stereo width.
    var brown = [Float](repeating: 0, count: channels)
    let leak: Float = 0.985
    let lfoRate = 0.07  // Hz — slow amplitude drift.

    for frame in 0..<frameCount {
      let t = Double(frame) / Double(sampleRate)
      // Slow swell keeps the bed from feeling static.
      let envelope = Float(0.55 + 0.25 * sin(2.0 * Double.pi * lfoRate * t))
      for ch in 0..<channels {
        let white = rng.nextUnitFloat()  // [-1, 1]
        brown[ch] = leak * brown[ch] + 0.08 * white
        let value = max(-1.0, min(1.0, brown[ch] * 6.0)) * envelope * 0.6
        samples.append(value)
      }
    }

    let data = WAVWriter.encode(samples: samples, sampleRate: sampleRate, channels: channels)
    guard data.count > 44 else {
      throw AmbienteError.generationFailed("encoder produced an empty buffer")
    }
    return data
  }

  /// Stable, order-independent hash of the prompt used to perturb the seed.
  private static func promptSalt(_ prompt: String) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325  // FNV-1a offset basis
    for byte in prompt.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01B3  // FNV prime
    }
    return hash
  }
}

/// SplitMix64 PRNG — small, fast, and seedable for reproducible output.
private struct SplitMix64 {
  private var state: UInt64

  init(seed: UInt64) { self.state = seed }

  mutating func next() -> UInt64 {
    state = state &+ 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// Uniform Float in `[-1, 1]`.
  mutating func nextUnitFloat() -> Float {
    // Top 24 bits → [0, 1), then map to [-1, 1].
    let bits = next() >> 40  // 24 bits
    let unit = Float(bits) / Float(1 << 24)
    return unit * 2.0 - 1.0
  }
}
