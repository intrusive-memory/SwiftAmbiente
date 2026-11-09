//
//  FoleyRenderTests.swift
//  SwiftAmbienteTests
//
//  OPERATION THUNDEROUS TEACUP, Sortie 1: `render(foley:to:)`, the
//  directive-aware render record and foley render state. Stub conformers
//  only — no model, no network, temp directories only.
//

import Foundation
import GlosaCore
import Testing

@testable import SwiftAmbiente

// MARK: - Fixtures

/// Returns a short silent mono WAV and counts its calls; never touches a model.
private final class CountingStubGenerator: AmbienteGenerator, @unchecked Sendable {
  let generatorId = "stub"
  let displayName = "Stub"
  private let lock = NSLock()
  private var _calls: [GenerationSettings] = []
  var calls: [GenerationSettings] { lock.withLock { _calls } }

  func isAvailable() async -> Bool { true }
  func generate(prompt: String, settings: GenerationSettings) async throws -> Data {
    lock.withLock { _calls.append(settings) }
    let frames = max(1, Int(settings.durationSeconds * 8_000))
    return PCMAudio(samples: [Float](repeating: 0, count: frames), sampleRate: 8_000, channels: 1)
      .wavData()
  }
}

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("FoleyRenderTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func exists(_ url: URL) -> Bool {
  FileManager.default.fileExists(atPath: url.path)
}

private func foley(
  prompt: String = "door slams shut",
  seed: UInt32? = 42,
  take: Double? = 0.25,
  model: String? = nil,
  offset: Double? = nil
) -> GlosaCore.Foley {
  GlosaCore.Foley(
    documentIndex: 5, prompt: prompt, seed: seed, take: take, model: model, offset: offset)
}

/// The committed v0.2.0-shape ambience record.
private func ambienceRecordFixture() throws -> Data {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/ambience-render-record-0.2.0.json", isDirectory: false)
  return try Data(contentsOf: url)
}

// MARK: - Tests

@Suite("Foley render")
struct FoleyRenderTests {

  @Test("take/seed/steps/cfg map onto GenerationSettings, take defaulting to Foley.defaultTake")
  func settingsMapping() {
    let written = GlosaCore.Foley(
      documentIndex: 0, prompt: "x", seed: 7, take: 3, steps: 50, cfg: 6.5)
    let settings = GenerationSettings(foley: written)
    #expect(settings.durationSeconds == 3)
    #expect(settings.seed == 7)
    #expect(settings.steps == 50)
    #expect(settings.cfgScale == 6.5)

    let defaults = GenerationSettings(foley: GlosaCore.Foley(documentIndex: 0, prompt: "x"))
    #expect(defaults.durationSeconds == GlosaCore.Foley.defaultTake)
    #expect(defaults.seed == nil)
    #expect(defaults.steps == GenerationSettings.default.steps)
    #expect(defaults.cfgScale == GenerationSettings.default.cfgScale)
  }

  @Test("A foley record round-trips through its file form as {\"foley\": …}")
  func foleyRecordRoundTrip() throws {
    let effective = GlosaCore.Foley(
      documentIndex: 0, prompt: "boots on gravel", seed: 1234, take: 3, steps: 8, cfg: 7,
      model: GlosaCore.Foley.defaultModel, offset: -0.5, gain: -6, fadeOut: 0.1,
      output: "foley/ep/fol-0a1b2c3d.wav")
    let record = RenderRecord(
      foley: effective, digest: effective.renderDigest, generator: "stub",
      swiftAmbiente: "0.3.0", rendered: Date(timeIntervalSince1970: 1_794_000_000.75))

    let data = try record.jsonData()
    let decoded = try RenderRecord(jsonData: data)
    #expect(decoded == record)
    #expect(decoded.foley == effective)
    #expect(decoded.ambience == nil)
    #expect(decoded.directive.key == "foley")
    #expect(try decoded.jsonData() == data)

    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(json.keys) == ["foley", "digest", "generator", "swiftAmbiente", "rendered"])
    let schema = try #require(json["foley"] as? [String: Any])
    #expect(schema["prompt"] as? String == "boots on gravel")
    #expect(schema["offset"] as? Double == -0.5)
    #expect(json["rendered"] as? String == "2026-11-06T21:20:00Z")

    // Both directives, or neither, is not a record.
    let both = """
      {"ambience": {"prompt": "a"}, "foley": {"prompt": "b"}, "digest": "x", "generator": "g",
       "swiftAmbiente": "v", "rendered": "2026-11-07T00:00:00Z"}
      """
    #expect(throws: (any Error).self) { _ = try RenderRecord(jsonData: Data(both.utf8)) }
    let neither = """
      {"digest": "x", "generator": "g", "swiftAmbiente": "v", "rendered": "2026-11-07T00:00:00Z"}
      """
    #expect(throws: (any Error).self) { _ = try RenderRecord(jsonData: Data(neither.utf8)) }
  }

  @Test("A pre-existing ambience record decodes as before and re-encodes byte-for-byte")
  func existingAmbienceRecordUnchanged() throws {
    let fixture = try ambienceRecordFixture()
    let record = try RenderRecord(jsonData: fixture)

    let ambience = try #require(record.ambience)
    #expect(record.foley == nil)
    #expect(record.directive.key == "ambience")
    #expect(ambience.prompt == "harbour at dawn")
    #expect(ambience.seed == 99)
    #expect(ambience.take == 0.5)
    #expect(ambience.steps == 8)
    #expect(ambience.cfg == 7)
    #expect(ambience.gain == -3)
    #expect(ambience.model == "stable-audio-3-small-sfx")
    #expect(ambience.output == "ambience/episode-1/amb-1a2b3c4d.wav")
    #expect(record.digest == "0f3c8e2a9b7d4c1e5f6a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e")
    #expect(record.generator == "stable-audio")
    #expect(record.swiftAmbiente == "0.2.0")
    #expect(record.rendered == (try Date("2026-11-07T21:09:57Z", strategy: .iso8601)))

    #expect(try record.jsonData() == fixture)
  }

  @Test("An ambience record beside a foley take reads changed, even with a matching digest")
  func ambienceRecordBesideFoleyTakeIsChanged() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("fol-0001.wav")
    let note = foley()
    try PCMAudio(samples: [0, 0], sampleRate: 8_000, channels: 1).wavData().write(to: output)

    // An ambience record that even claims the foley note's digest.
    let ambienceRecord = RenderRecord(
      ambience: GlosaCore.Ambience(documentIndex: 0, prompt: "door slams shut", seed: 42),
      digest: note.renderDigest, generator: "stub", rendered: Date())
    try ambienceRecord.jsonData().write(to: AmbienceRendering.recordURL(for: output))

    let status = AmbienceRendering.renderStatus(for: note, output: output)
    #expect(status.state == .changed)
    #expect(status.record == ambienceRecord)
    #expect(status.warning == nil)

    // And the converse: a foley record is never a current ambience take.
    let ambienceNote = GlosaCore.Ambience(documentIndex: 0, prompt: "rain", seed: 1)
    let foleyRecord = RenderRecord(
      foley: note, digest: ambienceNote.renderDigest, generator: "stub", rendered: Date())
    try foleyRecord.jsonData().write(to: AmbienceRendering.recordURL(for: output), options: .atomic)
    #expect(AmbienceRendering.renderState(for: ambienceNote, output: output) == .changed)
  }

  @Test("Foley render state: notRendered, unknown, current, changed, unreadable")
  func foleyRenderStates() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("fol-0002.wav")
    let recordURL = AmbienceRendering.recordURL(for: output)

    #expect(AmbienceRendering.renderState(for: foley(), output: output) == .notRendered)

    try PCMAudio(samples: [0, 0], sampleRate: 8_000, channels: 1).wavData().write(to: output)
    #expect(AmbienceRendering.renderState(for: foley(), output: output) == .unknown)

    let record = try await CountingStubGenerator().render(foley: foley(), to: output)
    let status = AmbienceRendering.renderStatus(for: foley(), output: output)
    #expect(status.state == .current)
    #expect(status.record == record)
    // `offset` is mix-time only: it does not enter the digest.
    #expect(AmbienceRendering.renderState(for: foley(offset: -1), output: output) == .current)
    #expect(AmbienceRendering.renderState(for: foley(seed: 43), output: output) == .changed)

    try Data("{ not json".utf8).write(to: recordURL)
    let unreadable = AmbienceRendering.renderStatus(for: foley(), output: output)
    #expect(unreadable.state == .changed)
    #expect(unreadable.record == nil)
    #expect(unreadable.warning != nil)
  }

  @Test("render(foley:) writes the WAV, then the record")
  func renderWritesWAVThenRecord() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("foley/ep/fol-0a1b2c3d.wav")
    let recordURL = AmbienceRendering.recordURL(for: output)
    let note = GlosaCore.Foley(
      documentIndex: 4, prompt: "teacup set down", seed: 7, steps: 4, gain: -2)
    let generator = CountingStubGenerator()

    var writes: [URL] = []
    let record = try await generator.render(
      foley: note, to: output, renderedAt: Date(),
      write: { data, url in
        writes.append(url)
        try AtomicFileWriter.write(data, to: url)
      })
    #expect(writes == [output, recordURL])

    // Generated with the note's settings; take defaults to Foley.defaultTake.
    let calls = generator.calls
    #expect(calls.count == 1)
    #expect(calls.first?.durationSeconds == GlosaCore.Foley.defaultTake)
    #expect(calls.first?.seed == 7)
    #expect(calls.first?.steps == 4)

    let effective = try #require(record.foley)
    #expect(record.digest == note.renderDigest)
    #expect(effective.take == GlosaCore.Foley.defaultTake)
    #expect(effective.model == GlosaCore.Foley.defaultModel)
    #expect(effective.cfg == GenerationSettings.default.cfgScale)
    #expect(effective.gain == -2)
    #expect(effective.documentIndex == 0)

    let onDisk = try RenderRecord(jsonData: try Data(contentsOf: recordURL))
    #expect(onDisk == record)
    #expect(try PCMAudio(wavData: try Data(contentsOf: output)).frameCount > 0)
    #expect(AmbienceRendering.renderState(for: note, output: output) == .current)
  }

  @Test("render(foley:) rejects an unknown model before generating")
  func unknownModelRejectedBeforeGenerating() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("fol.wav")
    let generator = CountingStubGenerator()

    do {
      _ = try await generator.render(foley: foley(model: "stable-audio-9-huge"), to: output)
      Issue.record("render accepted an unknown model id")
    } catch AmbienteError.unknownAmbienceModel(let id) {
      #expect(id == "stable-audio-9-huge")
    }
    #expect(generator.calls.isEmpty)
    #expect(!exists(output))
    #expect(!exists(AmbienceRendering.recordURL(for: output)))

    // A blank prompt is rejected the same way.
    await #expect(throws: AmbienteError.self) {
      _ = try await generator.render(foley: foley(prompt: "  "), to: output)
    }
    #expect(generator.calls.isEmpty)
  }
}
