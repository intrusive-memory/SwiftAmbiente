//
//  StableAudioGoldenParityTests.swift
//  SwiftAmbienteTests
//
//  Sortie 9 (OPERATION PHANTOM FOLEY, WU2): the golden-output parity gate for the
//  whole Stable Audio work unit, plus model-free checks of the SAME-S unpatch.
//
//  GOLDEN: Tests/Fixtures/golden-rain-on-tin-roof-seed42.wav, captured from
//  Stability's official Python-MLX reference (see the fixture's README for the
//  exact invocation). The Swift pipeline (T5Gemma → DiT ping-pong sampler →
//  SAME-S decoder → unpatch → WAVWriter) is run with the SAME parameters and
//  must match within the spectral/RMS tolerance documented — with its
//  derivation and the observed delta — in
//  Sources/SwiftAmbiente/StableAudio/STRATEGY.md ("Sortie 9 parity tolerance").
//
//  WHY NOT SAMPLE-EXACT: the official reference itself produces 5 distinct
//  waveforms across MLX builds (0.30.0 … 0.32.4) for this exact invocation; the
//  SAME-S decoder amplifies ulp-level differences (e.g. RoPE kernel rounding)
//  into large sample-wise differences. The tolerance is therefore the
//  reference's own cross-build spread (×1.5), and the gate is shown to have
//  teeth by an in-suite negative control (a different seed must FAIL it).
//
//  GATING: model-dependent tests SKIP (not fail) when the SFX model is absent,
//  via `@Test(.enabled(if:))`. Point `TEST_RUNNER_ACERVO_MODELS_DIR` (or
//  `ACERVO_MODELS_DIR`) at a staging root such as `/tmp/acervo-staging`. Model
//  loads run under `withResolvedAcervoModelsDirectory` (shared env gate).
//

import Foundation
import MLX
import Testing

@testable import SwiftAmbiente

/// Model presence gate: config + weights + the T5Gemma encoder subfolder.
private enum GoldenParityFixture {
  static var isModelPresent: Bool {
    guard StableAudioModelFixture.isPresent,
      let dir = StableAudioModelFixture.modelDirectory
    else { return false }
    let sub = dir.appendingPathComponent(T5GemmaEncoderConfig.subfolderName, isDirectory: true)
    let fm = FileManager.default
    return fm.fileExists(atPath: sub.appendingPathComponent("model.safetensors").path)
      && fm.fileExists(atPath: sub.appendingPathComponent("tokenizer.json").path)
  }

  static var goldenURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // SwiftAmbienteTests/
      .deletingLastPathComponent()  // Tests/
      .appendingPathComponent("Fixtures/golden-rain-on-tin-roof-seed42.wav", isDirectory: false)
  }

  // The exact reference invocation (golden-rain-on-tin-roof-seed42.README.md).
  static let prompt = "heavy rain on a tin roof"
  static let seed: UInt64 = 42
  static let settings = GenerationSettings(
    durationSeconds: 5.0, steps: 8, cfgScale: 1.0, seed: seed)
  static let expectedFrames = 220_500  // 5.0 s × 44.1 kHz, trimmed exactly

  /// The documented parity tolerance (STRATEGY.md "Sortie 9 parity tolerance"):
  /// the worst delta the official reference itself shows across MLX builds
  /// 0.30.5 … 0.32.4 vs the golden, × 1.5.
  enum Tolerance {
    static let spectrogramDB = 1.2
    static let ltasDB = 0.4
    static let rmsRelative = 0.06
    static let minEnvelopeCorrelation = 0.97
  }

  static func withinTolerance(_ d: AudioSpectralDelta) -> Bool {
    d.spectrogramDB <= Tolerance.spectrogramDB && d.ltasDB <= Tolerance.ltasDB
      && d.rmsRelative <= Tolerance.rmsRelative
      && d.envelopeCorrelation >= Tolerance.minEnvelopeCorrelation
  }
}

@Suite("Stable Audio golden-output parity (Sortie 9)", .serialized)
struct StableAudioGoldenParityTests {

  // MARK: Model-free: unpatch layout

  @Test("unpatch is rearrange('b (c h) l -> b c (l h)', h=256)")
  func unpatchLayout() {
    let c = 2
    let h = 256
    let l = 3
    // patches[0, ch·h + p, t] = 1000·ch + 10·t + p/1000 encodes (channel, time, patch-pos).
    var vals = [Float](repeating: 0, count: c * h * l)
    for ch in 0..<c {
      for p in 0..<h {
        for t in 0..<l {
          vals[(ch * h + p) * l + t] = Float(1000 * ch + 10 * t) + Float(p) / 1000
        }
      }
    }
    let out = StableAudioSAMESDecoder.unpatch(MLXArray(vals, [1, c * h, l]))
    #expect(out.shape == [1, c, l * h])
    let flat = out.asArray(Float.self)
    for ch in 0..<c {
      for t in 0..<l {
        for p in [0, 1, 255] {
          // Output sample index t·h + p of channel ch.
          let got = flat[ch * l * h + t * h + p]
          #expect(got == Float(1000 * ch + 10 * t) + Float(p) / 1000)
        }
      }
    }
  }

  @Test("requested frame count matches the reference trim")
  func requestedFrames() {
    #expect(StableAudioPipeline.requestedFrames(forSeconds: 5.0) == 220_500)
    #expect(StableAudioLatentGenerator.latentLength(forSeconds: 5.0) == 54)
    // 54 latents × 4096 = 221,184 samples before the trim to 220,500.
    #expect(54 * StableAudioLatentGenerator.samplesPerLatent >= 220_500)
  }

  @Test("golden fixture satisfies the WAV contract")
  func goldenFixtureContract() throws {
    let golden = try PCMWAV(data: Data(contentsOf: GoldenParityFixture.goldenURL))
    #expect(golden.sampleRate == 44_100)
    #expect(golden.channels == 2)
    #expect(golden.frames == GoldenParityFixture.expectedFrames)
  }

  // MARK: Model-gated: end-to-end parity

  @Test(
    "Swift text→WAV matches the golden fixture within the documented spectral/RMS tolerance",
    .enabled(if: GoldenParityFixture.isModelPresent))
  func goldenParity() async throws {
    try await withResolvedAcervoModelsDirectory { dir in
      let pipeline = try StableAudioPipeline.load(fromModelDirectory: dir)
      let config = AmbienteConfig.default
      let wav = pipeline.generateWAV(
        prompt: GoldenParityFixture.prompt, settings: GoldenParityFixture.settings,
        config: config)

      // WAV contract: valid 44-byte header, 44.1 kHz, stereo, 16-bit, non-empty.
      let candidate = try PCMWAV(data: wav)
      #expect(wav.count == 44 + GoldenParityFixture.expectedFrames * 2 * 2)
      #expect(candidate.sampleRate == config.sampleRate)
      #expect(candidate.sampleRate == 44_100)
      #expect(candidate.channels == config.channelCount)
      #expect(candidate.channels == 2)
      #expect(candidate.bitsPerSample == 16)
      #expect(candidate.frames == GoldenParityFixture.expectedFrames)
      #expect(candidate.channelSamples.allSatisfy { ch in ch.contains { $0 != 0 } })

      let golden = try PCMWAV(data: Data(contentsOf: GoldenParityFixture.goldenURL))
      let delta = AudioSpectralDelta.compare(candidate: candidate, reference: golden)
      let t = GoldenParityFixture.Tolerance.self
      #expect(delta.spectrogramDB <= t.spectrogramDB, "golden parity: \(delta)")
      #expect(delta.ltasDB <= t.ltasDB, "golden parity: \(delta)")
      #expect(delta.rmsRelative <= t.rmsRelative, "golden parity: \(delta)")
      #expect(delta.envelopeCorrelation >= t.minEnvelopeCorrelation, "golden parity: \(delta)")
      print("[S9 golden parity] Swift vs golden: \(delta)")

      // Negative control: the gate must REJECT a wrong output of the same
      // pipeline (same prompt, different seed) — proves the tolerance has teeth.
      let wrong = pipeline.generateWAV(
        prompt: GoldenParityFixture.prompt,
        settings: GenerationSettings(durationSeconds: 5.0, steps: 8, cfgScale: 1.0, seed: 43),
        config: config)
      let wrongDelta = AudioSpectralDelta.compare(
        candidate: try PCMWAV(data: wrong), reference: golden)
      #expect(
        !GoldenParityFixture.withinTolerance(wrongDelta),
        "negative control (seed 43) unexpectedly within tolerance: \(wrongDelta)")
      print("[S9 golden parity] negative control seed 43 vs golden: \(wrongDelta)")

      // Negative control: over-driven guidance. The Small SFX model is distilled
      // to run at cfg 1.0; cfg 7.0 yields loud, clipped, garbled audio (the bug
      // that shipped as the default before this fixture was re-recorded).
      let overdriven = pipeline.generateWAV(
        prompt: GoldenParityFixture.prompt,
        settings: GenerationSettings(durationSeconds: 5.0, steps: 8, cfgScale: 7.0, seed: 42),
        config: config)
      let overdrivenDelta = AudioSpectralDelta.compare(
        candidate: try PCMWAV(data: overdriven), reference: golden)
      #expect(
        !GoldenParityFixture.withinTolerance(overdrivenDelta),
        "negative control (cfg 7.0) unexpectedly within tolerance: \(overdrivenDelta)")
      print("[S9 golden parity] negative control cfg 7.0 vs golden: \(overdrivenDelta)")
    }
  }
}
