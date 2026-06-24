//
//  AmbienteEngine.swift
//  SwiftAmbiente
//
//  High-level entry point that picks a generation backend and renders a bed.
//  Prefers the MLX Stable Audio backend when installed, otherwise falls back to
//  the procedural generator so a result is always produced.
//

import Foundation

/// Front door for ambient-bed generation.
///
/// ```swift
/// let engine = AmbienteEngine()
/// let wav = try await engine.render(prompt: "rain on a tin roof", duration: 20)
/// try wav.write(to: url)
/// ```
public struct AmbienteEngine: Sendable {
  private let config: AmbienteConfig
  private let modelManager: AmbienteModelManager

  public init(config: AmbienteConfig = .default) {
    self.config = config
    self.modelManager = AmbienteModelManager(config: config)
  }

  /// Resolve the best available backend.
  ///
  /// Returns the MLX Stable Audio generator when its model is installed and
  /// loadable; otherwise returns ``ProceduralAmbienteGenerator``. Backend
  /// selection is logged to stderr so callers know which engine ran.
  public func resolveGenerator(model repo: StableAudioModelRepo = .smallSFX) async
    -> any AmbienteGenerator
  {
    if await modelManager.isModelInstalled(repo) {
      if let ml = try? await modelManager.loadGenerator(repo) {
        return ml
      }
    }
    FileHandle.standardError.write(
      Data(
        "[AmbienteEngine] Stable Audio backend unavailable — using procedural generator.\n".utf8))
    return ProceduralAmbienteGenerator(config: config)
  }

  /// Render an ambient bed and return WAV data.
  ///
  /// - Parameters:
  ///   - prompt: Free-form atmosphere description.
  ///   - duration: Length in seconds.
  ///   - seed: Optional reproducibility seed.
  ///   - model: Which Stable Audio variant to prefer (default SFX).
  public func render(
    prompt: String,
    duration: Double,
    seed: UInt64? = nil,
    model repo: StableAudioModelRepo = .smallSFX
  ) async throws -> Data {
    let generator = await resolveGenerator(model: repo)
    let settings = GenerationSettings(durationSeconds: duration, seed: seed)
    return try await generator.generate(prompt: prompt, settings: settings)
  }
}
