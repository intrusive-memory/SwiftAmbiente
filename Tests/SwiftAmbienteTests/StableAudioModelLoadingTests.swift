//
//  StableAudioModelLoadingTests.swift
//  SwiftAmbienteTests
//
//  Sortie 6 (OPERATION PHANTOM FOLEY, WU2): model-gated verification that
//  `StableAudioModelConfig` parses the real `model_config.json` and that the
//  safetensors weight map loads with the expected tensor shapes.
//
//  GATING: these tests only run when a real Stable Audio 3 Small SFX model is
//  resolvable on disk (its `model_config.json` + `model.safetensors` exist under
//  the resolved models directory). On CI runners without the model they SKIP
//  cleanly via `@Test(.enabled(if:))` — no failure, no hang.
//
//  The resolved models directory is read from `ACERVO_MODELS_DIR` or, when
//  `xcodebuild test` does not forward the parent shell env to the xctest runner
//  (Xcode 26+), from `TEST_RUNNER_ACERVO_MODELS_DIR` (the prefix xcodebuild
//  strips and forwards into the test host). Point either at the staging root
//  (e.g. `/tmp/acervo-staging`) to make the gate open.
//
//  ENV SAFETY: any mutation of the process-global `ACERVO_MODELS_DIR` runs under
//  the shared `AcervoModelsDirectoryGate` (from AcervoModelsDirectoryTestSupport)
//  so it is serialized against every other suite that touches that variable —
//  the same cross-suite race fix commit e0712c9 established. The gate is only
//  needed for MUTATION; `@Test(.enabled(if:))` merely READS env and so needs no
//  lock.
//

import Foundation
import MLX
import SwiftAcervo
import Testing

@testable import SwiftAmbiente

/// Resolves whether a real Stable Audio SFX model is present, and where.
enum StableAudioModelFixture {
  /// The Acervo slug directory name for the SFX model
  /// (`stabilityai_stable-audio-3-small-sfx`).
  static var slug: String { Acervo.slugify(StableAudioModelRepo.smallSFX.rawValue) }

  /// The candidate shared-models directory, read from the ambient environment.
  ///
  /// `TEST_RUNNER_ACERVO_MODELS_DIR` takes precedence: it is the immutable,
  /// externally-forwarded value (xcodebuild strips the `TEST_RUNNER_` prefix
  /// when injecting into the test host, since the parent shell env does not
  /// reach the runner on Xcode 26+). Preferring it makes the gate race-free
  /// against sibling suites that transiently `setenv`/restore the mutable
  /// `ACERVO_MODELS_DIR` (which is only ever pointed at empty temp dirs).
  /// Falls back to `ACERVO_MODELS_DIR`. Returns `nil` when neither is set.
  static var candidateModelsDirectory: String? {
    let env = ProcessInfo.processInfo.environment
    return env["TEST_RUNNER_ACERVO_MODELS_DIR"] ?? env["ACERVO_MODELS_DIR"]
  }

  /// The resolved model directory (`<models>/<slug>`), or `nil` when no
  /// candidate models directory is configured.
  static var modelDirectory: URL? {
    guard let root = candidateModelsDirectory else { return nil }
    return URL(fileURLWithPath: root, isDirectory: true)
      .appendingPathComponent(slug, isDirectory: true)
  }

  /// Whether the model's config + weights both exist on disk. This is the
  /// gate condition — read-only, no env mutation, safe to evaluate outside the
  /// serialized gate.
  static var isPresent: Bool {
    guard let dir = modelDirectory else { return false }
    let fm = FileManager.default
    let config = dir.appendingPathComponent(
      StableAudioModelConfig.configFileName, isDirectory: false)
    let weights = dir.appendingPathComponent(
      StableAudioModelAssets.weightsFileName, isDirectory: false)
    return fm.fileExists(atPath: config.path) && fm.fileExists(atPath: weights.path)
  }
}

@Suite("Stable Audio model config + asset loading", .acervoEnvironment, .serialized, .serializedOnGPU)
struct StableAudioModelLoadingTests {

  @Test(
    "model_config.json parses: 44.1 kHz stereo + DiT hyperparameters",
    .enabled(if: StableAudioModelFixture.isPresent))
  func parsesModelConfig() async throws {
    try await withResolvedAcervoModelsDirectory { modelDir in
      // Prove end-to-end Acervo resolution: the manager resolves the same
      // model directory the fixture points at.
      let manager = AmbienteModelManager()
      let resolved = await manager.modelDirectory(for: .smallSFX)
      #expect(resolved.standardizedFileURL == modelDir.standardizedFileURL)

      let config = try StableAudioModelConfig.load(fromModelDirectory: modelDir)

      // Core audio contract.
      #expect(config.sampleRate == 44100)
      #expect(config.audioChannels == 2)

      // DiT / latent hyperparameters exposed for Sorties 7–9.
      #expect(config.modelType == "diffusion_cond_inpaint")
      #expect(config.ioChannels == 256)
      #expect(config.latentDim == 256)
      #expect(config.model.conditioning.condDim == 768)
      #expect(config.diffusion.embedDim == 1024)
      #expect(config.diffusion.depth == 20)
      #expect(config.diffusion.numHeads == 16)
      #expect(config.diffusion.condTokenDim == 768)
    }
  }

  @Test(
    "model.safetensors loads with known tensor shapes",
    .enabled(if: StableAudioModelFixture.isPresent))
  func loadsWeightsWithKnownShapes() async throws {
    try await withResolvedAcervoModelsDirectory { modelDir in
      let assets = try StableAudioModelAssets.load(fromModelDirectory: modelDir)

      // A non-trivial weight map loaded (real model has 685 tensors).
      #expect(assets.weights.count > 100)

      // Known load-bearing tensor shape (the DiT preprocess conv).
      let preprocess = try #require(
        assets.shape(of: "model.model.preprocess_conv.weight"),
        "preprocess_conv.weight missing from weight map")
      #expect(preprocess == [256, 256, 1])

      // Every known SFX tensor exists at its expected shape — throws on
      // missing/mismatch.
      try assets.verifyTensors(StableAudioModelAssets.knownSFXTensorShapes)

      // Config + weights load together via the combined loader too.
      #expect(assets.config.sampleRate == 44100)
      #expect(assets.config.audioChannels == 2)
    }
  }
}
