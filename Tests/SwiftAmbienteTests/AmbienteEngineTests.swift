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
}
