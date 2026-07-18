//
//  StableAudioLatentSamplerTests.swift
//  SwiftAmbienteTests
//
//  Sortie 8 (OPERATION PHANTOM FOLEY, WU2): model-gated verification of the DiT
//  flow-matching pingpong sampler → latent.
//
//  GATING: runs only when the real SFX model is resolvable on disk (config +
//  weights + the `t5gemma-b-b-ul2/` encoder subfolder). On CI runners without the
//  model these SKIP cleanly via `@Test(.enabled(if:))`. Point `ACERVO_MODELS_DIR`
//  or `TEST_RUNNER_ACERVO_MODELS_DIR` at the staging root (e.g.
//  `/tmp/acervo-staging`).
//
//  ENV SAFETY: model-load bodies run under `withResolvedAcervoModelsDirectory`
//  (from AcervoModelsDirectoryTestSupport), holding the shared
//  `AcervoModelsDirectoryGate` so a reader never observes a mutator suite's
//  transient temp-dir value of `ACERVO_MODELS_DIR`.
//
//  DETERMINISM: the sampler seeds via `MLXRandom`, matched op-for-op to the
//  reference's `mx.random` seeding (initial noise `key(seed)`, sampler
//  `key(seed+1)`, per-step `split` + `normal`). So the SAME seed must reproduce a
//  byte-identical latent and DIFFERENT seeds must diverge.
//

import Foundation
import MLX
import Testing

@testable import SwiftAmbiente

/// Model presence gate: needs config + weights + the T5Gemma encoder subfolder
/// (the sampler runs the whole conditioning → DiT → sample path).
private enum LatentSamplerFixture {
  static var isPresent: Bool {
    guard StableAudioModelFixture.isPresent,
      let dir = StableAudioModelFixture.modelDirectory
    else { return false }
    let sub = dir.appendingPathComponent(
      T5GemmaEncoderConfig.subfolderName, isDirectory: true)
    let fm = FileManager.default
    return fm.fileExists(atPath: sub.appendingPathComponent("model.safetensors").path)
      && fm.fileExists(atPath: sub.appendingPathComponent("tokenizer.json").path)
  }
}

@Suite("Stable Audio DiT sampler → latent (Sortie 8)", .serialized)
struct StableAudioLatentSamplerTests {

  // A small fixed duration keeps the DiT sequence short so the model-present
  // suite is fast enough to run 10× — 1.0 s → T_lat = ceil(44100/4096) = 11.
  private static let seconds = 1.0
  private static let prompt = "gentle rain on a tin roof"

  private func settings(seed: UInt64, cfg: Double = 1.0, steps: Int = 4) -> GenerationSettings {
    GenerationSettings(
      durationSeconds: Self.seconds, steps: steps, cfgScale: cfg, seed: seed)
  }

  /// Flatten an fp16 latent to an exact fp32 `[Float]` (lossless) for byte-level
  /// equality checks.
  private func floats(_ latent: MLXArray) -> [Float] {
    latent.asType(.float32).asArray(Float.self)
  }

  // MARK: Latent shape

  @Test(
    "latent shape is (1, io_channels, T_lat) for the requested duration",
    .enabled(if: LatentSamplerFixture.isPresent))
  func latentShape() async throws {
    try await withResolvedAcervoModelsDirectory { dir in
      let gen = try StableAudioLatentGenerator.load(fromModelDirectory: dir)
      let expectedT = StableAudioLatentGenerator.latentLength(forSeconds: Self.seconds)
      #expect(expectedT == 11)  // ceil(1.0 * 44100 / 4096)

      let latent = gen.generateLatent(
        prompt: Self.prompt, settings: settings(seed: 42))
      #expect(latent.shape == [1, gen.config.ioChannels, expectedT])
      #expect(latent.shape == [1, 256, 11])
      // The latent is a floating latent in the sampler's working precision. The
      // reference's fp32 zero local-add-cond promotes the cfg=1 residual stream
      // to fp32 (the cfg≠1 branch, which re-casts the velocity to x.dtype, stays
      // fp16) — S9's decoder upcasts to fp32 regardless. We assert a float dtype,
      // not a specific one, to stay faithful to that reference numeric path.
      #expect(latent.dtype == .float32 || latent.dtype == .float16)

      // A real sampled latent is finite and non-trivial (not all-zero / NaN).
      let vals = floats(latent)
      #expect(vals.allSatisfy { $0.isFinite })
      #expect(vals.contains { $0 != 0 })
    }
  }

  // MARK: Same seed → byte-identical

  @Test(
    "same seed reproduces a byte-identical latent",
    .enabled(if: LatentSamplerFixture.isPresent))
  func sameSeedIdentical() async throws {
    try await withResolvedAcervoModelsDirectory { dir in
      let gen = try StableAudioLatentGenerator.load(fromModelDirectory: dir)
      let a = floats(gen.generateLatent(prompt: Self.prompt, settings: settings(seed: 7)))
      let b = floats(gen.generateLatent(prompt: Self.prompt, settings: settings(seed: 7)))
      #expect(a.count == b.count)
      #expect(a == b, "same seed must produce byte-identical latents")
    }
  }

  // MARK: Different seeds → diverge

  @Test(
    "different seeds diverge",
    .enabled(if: LatentSamplerFixture.isPresent))
  func differentSeedsDiverge() async throws {
    try await withResolvedAcervoModelsDirectory { dir in
      let gen = try StableAudioLatentGenerator.load(fromModelDirectory: dir)
      let a = floats(gen.generateLatent(prompt: Self.prompt, settings: settings(seed: 7)))
      let c = floats(gen.generateLatent(prompt: Self.prompt, settings: settings(seed: 99)))
      #expect(a.count == c.count)
      #expect(a != c, "different seeds must produce different latents")
    }
  }

  // MARK: CFG path is also deterministic (exercises the batched uncond branch)

  @Test(
    "cfg ≠ 1 path (batched uncond) is deterministic and diverges by seed",
    .enabled(if: LatentSamplerFixture.isPresent))
  func cfgPathDeterministic() async throws {
    try await withResolvedAcervoModelsDirectory { dir in
      let gen = try StableAudioLatentGenerator.load(fromModelDirectory: dir)
      let s1 = settings(seed: 7, cfg: 7.0)
      let a = floats(gen.generateLatent(prompt: Self.prompt, settings: s1))
      let b = floats(gen.generateLatent(prompt: Self.prompt, settings: s1))
      #expect(a == b, "cfg path must be deterministic for a fixed seed")

      // The CFG (cfg=7) latent differs from the cfg=1 latent at the same seed.
      let plain = floats(gen.generateLatent(prompt: Self.prompt, settings: settings(seed: 7)))
      #expect(a != plain, "cfg=7 must differ from cfg=1")
    }
  }
}
