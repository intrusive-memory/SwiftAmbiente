//
//  AmbienteModelManager.swift
//  SwiftAmbiente
//
//  Resolves where generation models live on disk and (eventually) loads the MLX
//  Stable Audio backend. Today it only resolves the shared-models directory and
//  reports that no ML model is installed; the procedural generator needs no
//  model. The SwiftAcervo integration point is documented inline.
//

import Foundation
import SwiftAcervo

/// Resolves model storage and loads generation backends.
///
/// The directory convention matches the rest of the intrusive-memory ecosystem:
/// `~/Library/SharedModels/<org>_<repo>/`, overridable via `ACERVO_MODELS_DIR`.
/// SwiftAcervo will own this resolution once wired (see
/// `REQUIREMENTS-stable-audio-integration.md`); the env/default fallback here is
/// deliberately API-free so the package builds without the dependency.
public actor AmbienteModelManager {
  private let config: AmbienteConfig

  public init(config: AmbienteConfig = .default) {
    self.config = config
  }

  /// The directory under which shared models are stored.
  ///
  /// Resolution order:
  /// 1. `ACERVO_MODELS_DIR` environment variable, if set.
  /// 2. `~/Library/SharedModels` (the ecosystem default).
  public nonisolated var sharedModelsDirectory: URL {
    if let override = ProcessInfo.processInfo.environment["ACERVO_MODELS_DIR"],
      !override.isEmpty
    {
      return URL(fileURLWithPath: override, isDirectory: true)
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent("Library/SharedModels", isDirectory: true)
  }

  /// The expected on-disk directory for a given model repo.
  ///
  /// Mirrors SwiftAcervo's `{org}_{repo}` slug convention.
  public nonisolated func modelDirectory(for repo: StableAudioModelRepo) -> URL {
    let slug = repo.rawValue.replacingOccurrences(of: "/", with: "_")
    return sharedModelsDirectory.appendingPathComponent(slug, isDirectory: true)
  }

  /// Whether the given model appears to be installed.
  ///
  /// Presence of `config.json` is the ecosystem's "model is valid" marker.
  public func isModelInstalled(_ repo: StableAudioModelRepo) -> Bool {
    let configJSON = modelDirectory(for: repo).appendingPathComponent("config.json")
    return FileManager.default.fileExists(atPath: configJSON.path)
  }

  /// Load the MLX Stable Audio generator for the given model.
  ///
  /// - Important: Not yet implemented. The MLX Stable Audio 3 Small port does not
  ///   exist as a Swift library; until it does, callers should fall back to
  ///   ``ProceduralAmbienteGenerator``. See
  ///   `REQUIREMENTS-stable-audio-integration.md` for the integration plan.
  public func loadGenerator(_ repo: StableAudioModelRepo) async throws -> any AmbienteGenerator {
    // TODO(stable-audio): construct and return the MLX Stable Audio generator.
    // TODO(acervo): replace the env/default directory resolution above with
    //   SwiftAcervo's `Acervo.sharedModelsDirectory` and on-demand download.
    throw AmbienteError.modelNotAvailable(
      "\(repo.rawValue) — MLX Stable Audio backend is not yet wired. "
        + "Use ProceduralAmbienteGenerator for now.")
  }
}
