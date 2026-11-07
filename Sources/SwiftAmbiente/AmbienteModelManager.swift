//
//  AmbienteModelManager.swift
//  SwiftAmbiente
//
//  Resolves where generation models live on disk and (eventually) loads the MLX
//  Stable Audio backend. Today it only resolves the shared-models directory and
//  reports that no ML model is installed; the procedural generator needs no
//  model. Directory resolution and installation checks delegate entirely to
//  SwiftAcervo — see `StableAudioModelRepo.swift` for the Acervo component
//  registration this manager triggers at init.
//

import Foundation
import SwiftAcervo

/// Resolves model storage and loads generation backends.
///
/// Directory resolution and installation checks delegate to SwiftAcervo
/// (`Acervo.sharedModelsDirectory`, `Acervo.isModelAvailable(_:)`), mirroring
/// the pattern established by `VoxAltaModelManager` in SwiftVoxAlta.
public actor AmbienteModelManager {
  private let config: AmbienteConfig

  public init(config: AmbienteConfig = .default) {
    self.config = config
    // Trigger lazy registration of the Stable Audio ComponentDescriptors.
    _ = registerStableAudioComponents
  }

  /// The directory under which shared models are stored.
  ///
  /// Delegates entirely to `Acervo.sharedModelsDirectory` (App Group
  /// resolution, including whatever test/CLI override mechanism SwiftAcervo
  /// itself supports — see `Acervo.modelsDirectoryOverrideVariable`).
  public nonisolated var sharedModelsDirectory: URL {
    Acervo.sharedModelsDirectory
  }

  /// The expected on-disk directory for a given model repo.
  ///
  /// Mirrors SwiftAcervo's `{org}_{repo}` slug convention via
  /// `Acervo.slugify(_:)`.
  public nonisolated func modelDirectory(for repo: StableAudioModelRepo) -> URL {
    sharedModelsDirectory.appendingPathComponent(
      Acervo.slugify(repo.rawValue), isDirectory: true)
  }

  /// Whether the given model appears to be installed.
  ///
  /// Delegates to `Acervo.isModelAvailable(_:)`, which anchors against the
  /// model's cached CDN manifest and verifies every declared file is present
  /// at the recorded size (`config.json` is one of those declared files, so
  /// the ecosystem's "model is valid" contract still holds).
  public func isModelInstalled(_ repo: StableAudioModelRepo) -> Bool {
    Acervo.isModelAvailable(repo.rawValue)
  }

  /// Load the MLX Stable Audio generator for the given model.
  ///
  /// Downloads the model on first use via Acervo's on-demand component
  /// access pattern (mirroring `VoxAltaModelManager`'s v2 access pattern:
  /// `Acervo.ensureComponentReady` followed by
  /// `AcervoManager.shared.withComponentAccess` for file-presence/checksum
  /// validation), then hands off to the WU2 construction seam below.
  ///
  /// - Returns: a ``StableAudioGenerator`` bound to the verified model directory.
  /// - Throws: ``AmbienteError/modelNotAvailable(_:)`` when the model cannot be
  ///   prepared; callers fall back to ``ProceduralAmbienteGenerator``.
  public func loadGenerator(_ repo: StableAudioModelRepo) async throws -> any AmbienteGenerator {
    let componentId = repo.componentId

    do {
      // Step 1: Ensure the model's files are downloaded via the Acervo
      // Component Registry (downloads on first use; no-ops if the component
      // is already present and verified).
      try await Acervo.ensureComponentReady(componentId)

      // Step 2: Validate file presence and checksums via the v2 access
      // pattern. `withComponentAccess`'s closure is synchronous, so it is
      // used purely to trigger SwiftAcervo's validation on entry — mirrors
      // `VoxAltaModelManager._loadModelWithComponentValidation`.
      try await AcervoManager.shared.withComponentAccess(componentId) { @Sendable _ in
        ()
      }
    } catch let error as AcervoError {
      throw Self.mapAcervoError(error, repo: repo)
    } catch {
      throw AmbienteError.modelNotAvailable(
        "\(repo.rawValue) — failed to prepare model: \(error.localizedDescription)")
    }

    // Model is downloaded and verified: hand off to the Stable Audio generator.
    // Weights load lazily on its first `generate` call.
    let generator = StableAudioGenerator(
      modelDirectory: modelDirectory(for: repo), config: config)
    guard await generator.isAvailable() else {
      throw AmbienteError.modelNotAvailable(
        "\(repo.rawValue) — config.json / model.safetensors missing from "
          + modelDirectory(for: repo).path)
    }
    return generator
  }

  /// Maps a SwiftAcervo error surfaced during `ensureComponentReady` /
  /// `withComponentAccess` onto an `AmbienteError` with an actionable,
  /// model-scoped message. Mirrors the `AcervoError` switch in
  /// `VoxAltaModelManager._loadModelWithComponentValidation`.
  private static func mapAcervoError(
    _ error: AcervoError, repo: StableAudioModelRepo
  ) -> AmbienteError {
    switch error {
    case .integrityCheckFailed(let file, let expected, let actual):
      return .modelNotAvailable(
        "\(repo.rawValue) — file '\(file)' failed SHA-256 verification "
          + "(expected \(expected), got \(actual)); re-download required")
    case .downloadSizeMismatch(let fileName, let expected, let actual):
      return .modelNotAvailable(
        "\(repo.rawValue) — file '\(fileName)' size mismatch "
          + "(expected \(expected) bytes, got \(actual) bytes)")
    case .manifestDownloadFailed(let statusCode):
      return .modelNotAvailable(
        "\(repo.rawValue) — CDN manifest download failed (HTTP \(statusCode))")
    case .manifestFetchFailed(let slug, let status):
      return .modelNotAvailable(
        "\(repo.rawValue) — CDN manifest fetch failed for slug '\(slug)' (HTTP \(status))")
    case .manifestIntegrityFailed(let expected, let actual):
      return .modelNotAvailable(
        "\(repo.rawValue) — CDN manifest checksum mismatch "
          + "(expected \(expected), got \(actual)); CDN copy may be corrupt")
    case .modelNotFound(let id):
      return .modelNotAvailable("Model '\(id)' not found on CDN")
    case .componentNotRegistered(let id):
      return .modelNotAvailable(
        "Unknown component '\(id)' (internal bug: forgot to register?)")
    case .componentNotDownloaded(let id):
      return .modelNotAvailable("Component '\(id)' is not yet downloaded")
    case .componentNotHydrated(let id):
      return .modelNotAvailable("Component '\(id)' needs hydration before sync inspection")
    case .componentFileNotFound(let component, let file):
      return .modelNotAvailable("File '\(file)' not found in component '\(component)'")
    case .offlineModeActive:
      return .modelNotAvailable(
        "ACERVO_OFFLINE=1 — refusing CDN fetch; model not present locally")
    default:
      return .generationFailed(
        "SwiftAcervo error preparing \(repo.rawValue): \(error.localizedDescription)")
    }
  }
}
