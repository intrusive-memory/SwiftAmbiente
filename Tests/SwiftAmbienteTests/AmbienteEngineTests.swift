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

@Suite("AmbienteEngine — procedural fallback", .serialized)
struct AmbienteEngineTests {

  /// Snapshots and restores `ACERVO_MODELS_DIR` around `body`, pointing it at
  /// a freshly created empty temp directory for the duration of the call.
  /// Mirrors `AmbienteModelManagerTests.withTempAcervoModelsDirectory`.
  private func withTempAcervoModelsDirectory<R>(
    _ body: () async throws -> R
  ) async rethrows -> R {
    let key = Acervo.modelsDirectoryOverrideVariable
    let previous = ProcessInfo.processInfo.environment[key]
    let tempPath = FileManager.default.temporaryDirectory
      .appendingPathComponent("AmbienteEngineTests-\(UUID().uuidString)", isDirectory: true)
      .path
    try? FileManager.default.createDirectory(
      atPath: tempPath, withIntermediateDirectories: true)
    setenv(key, tempPath, 1)
    defer {
      if let previous {
        setenv(key, previous, 1)
      } else {
        unsetenv(key)
      }
      try? FileManager.default.removeItem(atPath: tempPath)
    }
    return try await body()
  }

  @Test("resolveGenerator returns the procedural generator when no model is installed")
  func resolveGeneratorFallsBackToProceduralWhenModelAbsent() async throws {
    try await withTempAcervoModelsDirectory {
      let engine = AmbienteEngine()
      let generator = await engine.resolveGenerator(model: .smallSFX)
      #expect(generator.generatorId == "procedural")
    }
  }
}
