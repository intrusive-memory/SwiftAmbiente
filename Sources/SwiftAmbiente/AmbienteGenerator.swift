//
//  AmbienteGenerator.swift
//  SwiftAmbiente
//
//  The generation backend abstraction. SwiftAmbiente ships a procedural
//  implementation today and will add an MLX Stable Audio implementation once the
//  port lands; both conform to this protocol so the CLI and host app never
//  depend on a concrete engine.
//

import Foundation

/// A backend that renders an atmospheric / foley audio bed from a text prompt.
///
/// Conformers return WAV data (interleaved, matching the supplied
/// ``AmbienteConfig`` sample rate and channel count). The default shipping
/// conformer is ``ProceduralAmbienteGenerator``; the planned ML conformer is a
/// Stable Audio 3 Small SFX engine (see
/// `REQUIREMENTS-stable-audio-integration.md`).
public protocol AmbienteGenerator: Sendable {
  /// Stable identifier for the backend (e.g. `"procedural"`, `"stable-audio"`).
  var generatorId: String { get }

  /// Human-readable backend name for UI / logs.
  var displayName: String { get }

  /// Whether the backend is ready to generate (model present, etc.).
  func isAvailable() async -> Bool

  /// Render an ambient bed for `prompt` and return WAV audio data.
  ///
  /// - Parameters:
  ///   - prompt: Free-form description of the atmosphere ("rain on a tin roof,
  ///     distant thunder").
  ///   - settings: Duration, sampling, and seed parameters.
  /// - Returns: WAV audio data honouring the generator's ``AmbienteConfig``.
  /// - Throws: ``AmbienteError`` on invalid input or backend failure.
  func generate(prompt: String, settings: GenerationSettings) async throws -> Data
}
