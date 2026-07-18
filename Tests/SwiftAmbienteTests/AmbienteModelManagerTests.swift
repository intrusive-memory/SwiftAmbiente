//
//  AmbienteModelManagerTests.swift
//  SwiftAmbienteTests
//
//  Verifies AmbienteModelManager's directory resolution and installation
//  checks delegate to SwiftAcervo rather than any hand-rolled env/default
//  resolution. Mirrors the `ACERVO_MODELS_DIR` override mechanism SwiftAcervo
//  itself uses in `AcervoPathTests` (SwiftAcervoTests) and that SwiftVoxAlta's
//  test suite relies on for pointing Acervo at an isolated temp directory.
//

import Foundation
import SwiftAcervo
import Testing

@testable import SwiftAmbiente

@Suite("AmbienteModelManager — Acervo delegation", .acervoEnvironment, .serialized)
struct AmbienteModelManagerTests {

  // `withTempAcervoModelsDirectory` (shared, cross-suite-serialized via
  // `AcervoModelsDirectoryGate`) lives in
  // AcervoModelsDirectoryTestSupport.swift. Hands `body` the raw path
  // string rather than a `URL` so callers can reconstruct the expected
  // `URL` exactly the way SwiftAcervo does internally
  // (`URL(fileURLWithPath:isDirectory:)`), matching the convention in
  // SwiftAcervo's own `AcervoPathTests`.

  @Test("isModelInstalled returns false for an absent model, delegating to Acervo")
  func isModelInstalledFalseForAbsentModel() async throws {
    try await withTempAcervoModelsDirectory(prefix: "AmbienteModelManagerTests") { tempPath in
      // sharedModelsDirectory must reflect the ACERVO_MODELS_DIR override —
      // proof that directory resolution now goes through Acervo, not a
      // hand-rolled ~/Library/SharedModels default.
      let expectedSharedDir = URL(fileURLWithPath: tempPath, isDirectory: true)
      let manager = AmbienteModelManager()
      #expect(await manager.sharedModelsDirectory == expectedSharedDir)

      // No model files exist under the override, so Acervo must report the
      // model unavailable — no hand-rolled fallback should report otherwise.
      let installed = await manager.isModelInstalled(.smallSFX)
      #expect(installed == false)
    }
  }

  @Test("modelDirectory(for:) resolves under the Acervo-provided shared directory")
  func modelDirectoryResolvesUnderAcervoOverride() async throws {
    try await withTempAcervoModelsDirectory(prefix: "AmbienteModelManagerTests") { tempPath in
      let manager = AmbienteModelManager()
      let dir = await manager.modelDirectory(for: .smallSFX)
      let expected = URL(fileURLWithPath: tempPath, isDirectory: true)
        .appendingPathComponent(
          Acervo.slugify(StableAudioModelRepo.smallSFX.rawValue), isDirectory: true)
      #expect(dir == expected)
    }
  }
}
