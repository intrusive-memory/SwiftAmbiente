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
  /// - Important: Not yet implemented. The MLX Stable Audio 3 Small port does not
  ///   exist as a Swift library; until it does, callers should fall back to
  ///   ``ProceduralAmbienteGenerator``. See
  ///   `REQUIREMENTS-stable-audio-integration.md` for the integration plan.
  public func loadGenerator(_ repo: StableAudioModelRepo) async throws -> any AmbienteGenerator {
    // TODO(stable-audio): construct and return the MLX Stable Audio generator.
    // TODO(acervo): wire on-demand download via `Acervo.ensureComponentReady` /
    //   `withComponentAccess` (mirroring VoxAltaModelManager's v2 access
    //   pattern). Directory resolution and installation checks above already
    //   delegate to SwiftAcervo.
    throw AmbienteError.modelNotAvailable(
      "\(repo.rawValue) — MLX Stable Audio backend is not yet wired. "
        + "Use ProceduralAmbienteGenerator for now.")
  }
}
