//
//  AmbienceRenderTests.swift
//  SwiftAmbienteTests
//
//  OPERATION BARFLY WALLPAPER, Sortie 6: `render(ambience:to:)`, the render
//  record and render state. Procedural generator and stub conformers only —
//  no model, no network, temp directories only.
//

import Foundation
import GlosaCore
import Testing

@testable import SwiftAmbiente

// MARK: - Fixtures

/// Returns a short silent mono WAV; never touches a model.
private struct StubGenerator: AmbienteGenerator {
  let generatorId = "stub"
  let displayName = "Stub"
  func isAvailable() async -> Bool { true }
  func generate(prompt: String, settings: GenerationSettings) async throws -> Data {
    let frames = max(1, Int(settings.durationSeconds * 8_000))
    return PCMAudio(samples: [Float](repeating: 0, count: frames), sampleRate: 8_000, channels: 1)
      .wavData()
  }
}

/// Always fails to generate.
private struct FailingGenerator: AmbienteGenerator {
  let generatorId = "failing"
  let displayName = "Failing"
  func isAvailable() async -> Bool { true }
  func generate(prompt: String, settings: GenerationSettings) async throws -> Data {
    throw AmbienteError.generationFailed("stub failure")
  }
}

private struct WriteFailure: Error {}

/// A fresh temp directory; the caller removes it.
private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("AmbienceRenderTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func note(
  prompt: String = "rain on a tin roof",
  seed: UInt32? = 42,
  take: Double? = 0.25,
  model: String? = nil,
  gain: Double? = nil
) -> GlosaCore.Ambience {
  GlosaCore.Ambience(
    documentIndex: 3, prompt: prompt, seed: seed, take: take, model: model, gain: gain)
}

private func exists(_ url: URL) -> Bool {
  FileManager.default.fileExists(atPath: url.path)
}

// MARK: - Tests

@Suite("Ambience render")
struct AmbienceRenderTests {

  // MARK: Settings mapping

  @Test("take/seed/steps/cfg map onto GenerationSettings")
  func settingsMapping() {
    let written = GlosaCore.Ambience(
      documentIndex: 0, prompt: "x", seed: 7, take: 12, steps: 50, cfg: 6.5)
    let settings = GenerationSettings(ambience: written)
    #expect(settings.durationSeconds == 12)
    #expect(settings.seed == 7)
    #expect(settings.steps == 50)
    #expect(settings.cfgScale == 6.5)

    let defaults = GenerationSettings(ambience: GlosaCore.Ambience(documentIndex: 0, prompt: "x"))
    #expect(defaults.durationSeconds == GlosaCore.Ambience.defaultTake)
    #expect(defaults.seed == nil)
    #expect(defaults.steps == GenerationSettings.default.steps)
    #expect(defaults.cfgScale == GenerationSettings.default.cfgScale)
  }

  // MARK: Write order

  @Test("The record is written only after the WAV")
  func recordWrittenAfterWAV() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb-0001.wav")
    let recordURL = AmbienceRendering.recordURL(for: output)

    var writes: [URL] = []
    _ = try await StubGenerator().render(
      ambience: note(), to: output, renderedAt: Date(),
      write: { data, url in
        writes.append(url)
        try AtomicFileWriter.write(data, to: url)
      })
    #expect(writes == [output, recordURL])

    // A WAV write that fails leaves no record behind.
    let failedOutput = dir.appendingPathComponent("amb-0002.wav")
    var attempted: [URL] = []
    do {
      _ = try await StubGenerator().render(
        ambience: note(), to: failedOutput, renderedAt: Date(),
        write: { _, url in
          attempted.append(url)
          throw WriteFailure()
        })
      Issue.record("render ignored a failed WAV write")
    } catch is WriteFailure {}
    #expect(attempted == [failedOutput])
    #expect(!exists(failedOutput))
    #expect(!exists(AmbienceRendering.recordURL(for: failedOutput)))
  }

  @Test("A successful render leaves a readable WAV, its record, and no temp files")
  func renderWritesWAVAndRecord() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    // Nested, not-yet-existing directory: render creates it.
    let output = dir.appendingPathComponent("ambience/episode-1/amb-1a2b3c4d.wav")

    let record = try await ProceduralAmbienteGenerator().render(ambience: note(), to: output)

    let audio = try PCMAudio(wavData: try Data(contentsOf: output))
    #expect(audio.frameCount > 0)
    let recordURL = output.deletingLastPathComponent()
      .appendingPathComponent("amb-1a2b3c4d.wav.json")
    #expect(AmbienceRendering.recordURL(for: output) == recordURL)
    let onDisk = try RenderRecord(jsonData: try Data(contentsOf: recordURL))
    #expect(onDisk == record)
    #expect(record.generator == "procedural")
    #expect(record.swiftAmbiente == SwiftAmbiente.version)

    let leftovers = try FileManager.default.contentsOfDirectory(
      atPath: output.deletingLastPathComponent().path)
    #expect(leftovers.sorted() == ["amb-1a2b3c4d.wav", "amb-1a2b3c4d.wav.json"])
  }

  @Test("A failed generation writes nothing and keeps a previous record")
  func failedGenerationWritesNothing() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")

    await #expect(throws: AmbienteError.self) {
      _ = try await FailingGenerator().render(ambience: note(), to: output)
    }
    #expect(!exists(output))
    #expect(!exists(AmbienceRendering.recordURL(for: output)))

    // An earlier take survives a failed regeneration, still reading `changed`.
    _ = try await StubGenerator().render(ambience: note(prompt: "old"), to: output)
    let before = try Data(contentsOf: AmbienceRendering.recordURL(for: output))
    await #expect(throws: AmbienteError.self) {
      _ = try await FailingGenerator().render(ambience: note(prompt: "new"), to: output)
    }
    #expect(try Data(contentsOf: AmbienceRendering.recordURL(for: output)) == before)
    #expect(AmbienceRendering.renderState(for: note(prompt: "new"), output: output) == .changed)
  }

  // MARK: Record contents

  @Test("The record's digest equals the note's renderDigest")
  func recordDigestMatchesNote() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")
    // Written without take/model, so the effective object differs from the
    // note — the digest must still be the note's own.
    let ambience = GlosaCore.Ambience(
      documentIndex: 9, prompt: "night crickets", seed: 1234, steps: 4, gain: -6)
    let generator = StubGenerator()

    let record = try await generator.render(ambience: ambience, to: output)

    #expect(record.digest == ambience.renderDigest)
    let onDisk = try RenderRecord(jsonData: try Data(contentsOf: AmbienceRendering.recordURL(for: output)))
    #expect(onDisk.digest == ambience.renderDigest)
  }

  @Test("The record holds the effective schema object as plain JSON")
  func recordShape() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")
    let ambience = GlosaCore.Ambience(
      documentIndex: 2, prompt: "harbour at dawn", seed: 99, take: 0.5, gain: -3,
      output: "ambience/ep/amb.wav")
    let renderedAt = Date(timeIntervalSince1970: 1_794_000_000.75)

    let record = try await StubGenerator().render(
      ambience: ambience, to: output, renderedAt: renderedAt,
      write: AtomicFileWriter.write)

    // Effective values filled; written keys kept.
    #expect(record.ambience.take == 0.5)
    #expect(record.ambience.model == GlosaCore.Ambience.defaultModel)
    #expect(record.ambience.steps == GenerationSettings.default.steps)
    #expect(record.ambience.cfg == GenerationSettings.default.cfgScale)
    #expect(record.ambience.seed == 99)
    #expect(record.ambience.gain == -3)
    #expect(record.ambience.output == "ambience/ep/amb.wav")
    #expect(record.rendered == Date(timeIntervalSince1970: 1_794_000_000))

    let data = try Data(contentsOf: AmbienceRendering.recordURL(for: output))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(json.keys) == ["ambience", "digest", "generator", "swiftAmbiente", "rendered"])
    let schema = try #require(json["ambience"] as? [String: Any])
    #expect(!schema.keys.contains("object"))
    #expect(schema["prompt"] as? String == "harbour at dawn")
    #expect(schema["model"] as? String == "stable-audio-3-small-sfx")
    #expect(json["generator"] as? String == "stub")
    #expect(json["rendered"] as? String == "2026-11-06T21:20:00Z")
  }

  // MARK: Render state (§ 3.1)

  @Test("State: no WAV is notRendered")
  func stateNotRendered() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")
    #expect(AmbienceRendering.renderState(for: note(), output: output) == .notRendered)
  }

  @Test("State: a WAV with no record is unknown")
  func stateUnknown() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")
    try PCMAudio(samples: [0, 0], sampleRate: 8_000, channels: 1).wavData().write(to: output)
    #expect(AmbienceRendering.renderState(for: note(), output: output) == .unknown)
  }

  @Test("State: a matching record is current, including after a mix-only change")
  func stateCurrent() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")
    let record = try await StubGenerator().render(ambience: note(), to: output)

    let status = AmbienceRendering.renderStatus(for: note(), output: output)
    #expect(status.state == .current)
    #expect(status.record == record)
    #expect(status.warning == nil)
    // `gain` is mix-time only: it does not enter the digest.
    #expect(AmbienceRendering.renderState(for: note(gain: -9), output: output) == .current)
  }

  @Test("State: a record with a different digest is changed")
  func stateChanged() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")
    _ = try await StubGenerator().render(ambience: note(prompt: "rain"), to: output)

    #expect(AmbienceRendering.renderState(for: note(prompt: "snow"), output: output) == .changed)
    #expect(AmbienceRendering.renderState(for: note(seed: 43), output: output) == .changed)
    let status = AmbienceRendering.renderStatus(for: note(prompt: "snow"), output: output)
    #expect(status.warning == nil)
    #expect(status.record != nil)
  }

  @Test(
    "State: an unparsable record is changed, with a warning",
    arguments: [
      "{ not json",
      "{\"digest\": 5}",
      "{\"ambience\": {\"length\": \"forever\"}, \"digest\": \"x\", \"generator\": \"g\", \"swiftAmbiente\": \"v\", \"rendered\": \"2026-11-07T00:00:00Z\"}",
    ])
  func stateUnparsableRecord(recordText: String) throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")
    try PCMAudio(samples: [0, 0], sampleRate: 8_000, channels: 1).wavData().write(to: output)
    try Data(recordText.utf8).write(to: AmbienceRendering.recordURL(for: output))

    let status = AmbienceRendering.renderStatus(for: note(), output: output)
    #expect(status.state == .changed)
    #expect(status.record == nil)
    #expect(status.warning != nil)
  }

  // MARK: Model ids

  @Test("Model ids map to backends")
  func modelMapping() throws {
    #expect(try AmbienceModel.resolve("stable-audio-3-small-sfx") == .stableAudio3SmallSFX)
    #expect(try AmbienceModel.resolve(GlosaCore.Ambience.defaultModel).modelRepo == .smallSFX)
  }

  @Test("An unknown model id throws and writes nothing")
  func unknownModelThrows() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")

    #expect(throws: AmbienteError.self) {
      _ = try AmbienceModel.resolve("stable-audio-9-huge")
    }
    do {
      _ = try await StubGenerator().render(
        ambience: note(model: "stable-audio-9-huge"), to: output)
      Issue.record("render accepted an unknown model id")
    } catch AmbienteError.unknownAmbienceModel(let id) {
      #expect(id == "stable-audio-9-huge")
    }
    #expect(!exists(output))
    #expect(!exists(AmbienceRendering.recordURL(for: output)))
  }

  @Test("A stop note or a missing prompt is rejected")
  func invalidNotesRejected() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("amb.wav")

    await #expect(throws: AmbienteError.self) {
      _ = try await StubGenerator().render(
        ambience: GlosaCore.Ambience(documentIndex: 0, stop: true), to: output)
    }
    await #expect(throws: AmbienteError.self) {
      _ = try await StubGenerator().render(
        ambience: GlosaCore.Ambience(documentIndex: 0, prompt: "  "), to: output)
    }
    #expect(!exists(output))
  }
}
