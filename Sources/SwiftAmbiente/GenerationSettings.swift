//
//  GenerationSettings.swift
//  SwiftAmbiente
//
//  Sampling / synthesis parameters for ambient-bed generation.
//

import Foundation

/// Parameters controlling a single ambient-bed generation pass.
///
/// `steps` and `cfgScale` map onto Stable Audio's diffusion sampler and are
/// ignored by ``ProceduralAmbienteGenerator``; `durationSeconds` and `seed`
/// are honoured by every backend so output is reproducible across engines.
public struct GenerationSettings: Codable, Sendable {
  /// Target length of the generated bed, in seconds.
  public let durationSeconds: Double

  /// Number of diffusion sampler steps (Stable Audio backend only).
  public let steps: Int

  /// Classifier-free guidance scale (Stable Audio backend only).
  public let cfgScale: Double

  /// Deterministic seed. `nil` uses ``GenerationSettings/defaultSeed``.
  public let seed: UInt64?

  public init(
    durationSeconds: Double = 30.0,
    steps: Int = 8,
    cfgScale: Double = 1.0,
    seed: UInt64? = nil
  ) {
    self.durationSeconds = durationSeconds
    self.steps = steps
    self.cfgScale = cfgScale
    self.seed = seed
  }

  /// Fixed fallback seed so generation is reproducible when none is supplied.
  public static let defaultSeed: UInt64 = 0x5EED_A11C_E0FF_EE42

  /// The seed actually used for sampling (`seed` if set, else ``defaultSeed``).
  public var resolvedSeed: UInt64 { seed ?? Self.defaultSeed }

  /// Default settings: a 30-second bed, fast 8-step sampling.
  public static let `default` = GenerationSettings()
}
