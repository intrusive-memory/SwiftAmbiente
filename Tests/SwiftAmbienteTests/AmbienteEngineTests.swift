//
//  AmbienteEngineTests.swift
//  SwiftAmbienteTests
//
//  Verifies `AmbienteEngine.resolveGenerator` preserves the procedural
//  fallback behavior: when no Stable Audio model is installed (or Acervo's
//  `ensureComponentReady`/`withComponentAccess` calls in `loadGenerator`
//  can't complete — e.g. no network in CI), the engine must still return
//  `ProceduralAmbienteGenerator` rather than throwing or hanging.
//
//  Mirrors `AmbienteModelManagerTests`'s `ACERVO_MODELS_DIR` override pattern
//  and its `.serialized` suite (a prior sortie hit a race on the global env
//  var when suites ran in parallel).
//

import Foundation
import SwiftAcervo
import Testing

@testable import SwiftAmbiente

@Suite("AmbienteEngine — procedural fallback", .acervoEnvironment, .serialized)
struct AmbienteEngineTests {

  // `withTempAcervoModelsDirectory` (shared, cross-suite-serialized via
  // `AcervoModelsDirectoryGate`) lives in
  // AcervoModelsDirectoryTestSupport.swift. Mirrors
  // `AmbienteModelManagerTests`'s use of the same shared helper.

  @Test("resolveGenerator returns the procedural generator when no model is installed")
  func resolveGeneratorFallsBackToProceduralWhenModelAbsent() async throws {
    try await withTempAcervoModelsDirectory(prefix: "AmbienteEngineTests") { _ in
      let engine = AmbienteEngine()
      let generator = await engine.resolveGenerator(model: .smallSFX)
      #expect(generator.generatorId == "procedural")
    }
  }

  @Test(
    "resolveGenerator returns the stable-audio backend when the model is installed",
    .enabled(if: StableAudioModelFixture.isPresent))
  func resolveGeneratorReturnsStableAudioWhenModelInstalled() async throws {
    try await withResolvedAcervoModelsDirectory { modelDir in
      // The product descriptor is bare and hydrates from the CDN manifest on
      // first use, which would need the network (and a published model). Pre-
      // hydrate it from the staged model's own manifest.json so the
      // ensure/withComponentAccess flow runs entirely against local files.
      try Self.hydrateComponentFromLocalManifest(modelDir: modelDir)

      let engine = AmbienteEngine()
      let generator = await engine.resolveGenerator(model: .smallSFX)
      #expect(generator.generatorId == "stable-audio")
      #expect(await generator.isAvailable())
    }
  }

  /// Registers a pre-hydrated descriptor (explicit `files:`) built from the
  /// local `manifest.json`, replacing the bare product descriptor.
  private static func hydrateComponentFromLocalManifest(modelDir: URL) throws {
    struct Entry: Decodable {
      let path: String
      let sizeBytes: Int64
      let sha256: String
    }
    struct Manifest: Decodable { let files: [Entry] }
    let data = try Data(contentsOf: modelDir.appendingPathComponent("manifest.json"))
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)
    let repo = StableAudioModelRepo.smallSFX
    Acervo.register(
      ComponentDescriptor(
        id: repo.componentId, type: .backbone, displayName: "Stable Audio 3 Small — SFX",
        repoId: repo.rawValue,
        files: manifest.files.map {
          ComponentFile(relativePath: $0.path, expectedSizeBytes: $0.sizeBytes, sha256: $0.sha256)
        },
        estimatedSizeBytes: manifest.files.reduce(0) { $0 + $1.sizeBytes },
        minimumMemoryBytes: 1_500_000_000))
  }
}
