//
//  StableAudioGeneratorTests.swift
//  SwiftAmbienteTests
//
//  Sortie 10 (OPERATION PHANTOM FOLEY, WU2): `StableAudioGenerator`
//  conformance. Model-free checks always run; neural tests SKIP when the SFX
//  model is absent (see `StableAudioModelFixture`). Model loads run under
//  `withResolvedAcervoModelsDirectory` (shared env gate).
//

import Foundation
import Testing

@testable import SwiftAmbiente

@Suite("StableAudioGenerator", .acervoEnvironment, .serialized)
struct StableAudioGeneratorTests {

  private static let bogusDir = URL(fileURLWithPath: "/nonexistent/stable-audio-model")

  // MARK: Model-free

  @Test("identifies as stable-audio")
  func identity() {
    let g = StableAudioGenerator(modelDirectory: Self.bogusDir)
    #expect(g.generatorId == "stable-audio")
    #expect(!g.displayName.isEmpty)
  }

  @Test("is unavailable when the model directory is missing")
  func unavailableWithoutModel() async {
    let g = StableAudioGenerator(modelDirectory: Self.bogusDir)
    #expect(await g.isAvailable() == false)
  }

  @Test("rejects a non-positive duration before touching the model")
  func rejectsBadDuration() async {
    let g = StableAudioGenerator(modelDirectory: Self.bogusDir)
    await #expect(throws: AmbienteError.self) {
      _ = try await g.generate(prompt: "rain", settings: GenerationSettings(durationSeconds: 0))
    }
  }

  @Test("defaults the single-take limit to 120 s before any model load")
  func defaultTakeLimit() {
    let g = StableAudioGenerator(modelDirectory: Self.bogusDir)
    #expect(StableAudioGenerator.defaultMaxDurationSeconds == 120)
    #expect(g.maxDurationSeconds == 120)
  }

  @Test("rejects a 121 s take with takeTooLong before touching the model")
  func rejectsTakeOverLimit() async {
    // bogusDir has no model: reaching the load would fail with a different
    // error, so takeTooLong proves the check runs before any model access.
    let g = StableAudioGenerator(modelDirectory: Self.bogusDir)
    do {
      _ = try await g.generate(prompt: "bar", settings: GenerationSettings(durationSeconds: 121))
      Issue.record("expected takeTooLong for a 121 s request")
    } catch AmbienteError.takeTooLong(let seconds, let limit) {
      #expect(seconds == 121)
      #expect(limit == 120)
    } catch {
      Issue.record("expected takeTooLong, got \(error)")
    }
  }

  @Test("accepts a 120 s take (validation only, no model)")
  func acceptsTakeAtLimit() throws {
    let g = StableAudioGenerator(modelDirectory: Self.bogusDir)
    try g.validate(settings: GenerationSettings(durationSeconds: 120))
  }

  @Test("a 120 s take passes the limit and only fails at the missing model")
  func takeAtLimitReachesModelLoad() async {
    // bogusDir does not exist, so the load fails fast on the missing
    // model_config.json — nothing is downloaded or loaded.
    let g = StableAudioGenerator(modelDirectory: Self.bogusDir)
    do {
      _ = try await g.generate(prompt: "bar", settings: GenerationSettings(durationSeconds: 120))
      Issue.record("expected the missing model to fail the load")
    } catch AmbienteError.takeTooLong {
      Issue.record("120 s must be within the limit")
    } catch {
      // Expected: the model directory does not exist.
    }
  }

  @Test("rejects a non-44.1 kHz-stereo config")
  func rejectsUnsupportedConfig() async {
    let g = StableAudioGenerator(
      modelDirectory: Self.bogusDir,
      config: AmbienteConfig(
        generatorModel: AmbienteConfig.default.generatorModel, sampleRate: 22_050,
        channelCount: 1, outputFormat: .wav))
    await #expect(throws: AmbienteError.self) {
      _ = try await g.generate(prompt: "rain", settings: GenerationSettings(durationSeconds: 1))
    }
  }

  // MARK: Model-gated

  @Test(
    "reports available and satisfies the WAV contract with the real model",
    .enabled(if: StableAudioModelFixture.isPresent))
  func wavContract() async throws {
    try await withResolvedAcervoModelsDirectory { dir in
      let config = AmbienteConfig.default
      let g = StableAudioGenerator(modelDirectory: dir, config: config)
      #expect(await g.isAvailable())

      let settings = GenerationSettings(durationSeconds: 2.0, steps: 8, cfgScale: 1.0, seed: 42)
      let data = try await g.generate(prompt: "rain", settings: settings)

      // RIFF/WAVE header, 44-byte header + payload.
      #expect(data.count > 44)
      #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
      #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")

      let wav = try PCMWAV(data: data)
      #expect(wav.sampleRate == 44_100)
      #expect(wav.sampleRate == config.sampleRate)
      #expect(wav.channels == 2)
      #expect(wav.channels == config.channelCount)
      #expect(wav.bitsPerSample == 16)
      #expect(wav.frames == Int((2.0 * Double(config.sampleRate)).rounded()))
      #expect(wav.channelSamples.allSatisfy { ch in ch.contains { $0 != 0 } })
    }
  }

  @Test(
    "is deterministic for the same prompt and seed",
    .enabled(if: StableAudioModelFixture.isPresent))
  func deterministicForSeed() async throws {
    try await withResolvedAcervoModelsDirectory { dir in
      let g = StableAudioGenerator(modelDirectory: dir)
      let settings = GenerationSettings(durationSeconds: 1.0, steps: 4, cfgScale: 1.0, seed: 7)
      let a = try await g.generate(prompt: "forest", settings: settings)
      let b = try await g.generate(prompt: "forest", settings: settings)
      let c = try await g.generate(
        prompt: "forest",
        settings: GenerationSettings(durationSeconds: 1.0, steps: 4, cfgScale: 1.0, seed: 8))
      #expect(a == b)
      #expect(a != c)
    }
  }
}
