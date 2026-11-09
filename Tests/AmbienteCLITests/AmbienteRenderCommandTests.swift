//
//  AmbienteRenderCommandTests.swift
//  AmbienteCLITests
//
//  OPERATION BARFLY WALLPAPER, Sortie 8: `ambiente` subcommands and
//  `ambiente render <screenplay>`. Temp directories only; no model, no
//  generation, no network.
//

import ArgumentParser
import Foundation
import Testing

@testable import AmbienteCLICore
@testable import SwiftAmbiente

// MARK: - Fixtures

/// A new note (no seed/output), a note whose take is a hand-placed WAV (no
/// record → `unknown`), a note whose take will be made `current` by a test,
/// and a `stop` note.
private let screenplayText = """
  Title: Barfly

  INT. BAR - NIGHT

  [[ {"ambience": {
    "prompt": "busy bar, glasses clinking, low murmur of a crowded room",
    "take": 20.0
  }} ]]

  BARTENDER
  What'll it be?

  [[ {"ambience": {
    "prompt": "rain on the window",
    "seed": 3,
    "output": "beds/hand-placed.wav"
  }} ]]

  [[ {"ambience": {
    "prompt": "traffic",
    "seed": 7,
    "output": "beds/traffic.wav"
  }} ]]

  [[ {"ambience": {
    "stop": true
  }} ]]

  FADE OUT.

  """

private func makeProject() throws -> (directory: URL, screenplay: URL) {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("AmbienteRenderCommandTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(
    at: directory.appendingPathComponent("beds"), withIntermediateDirectories: true)
  let screenplay = directory.appendingPathComponent("episode.fountain")
  try Data(screenplayText.utf8).write(to: screenplay)
  // Hand-placed take: a WAV with no render record.
  try Data("RIFF-not-really".utf8).write(
    to: directory.appendingPathComponent("beds/hand-placed.wav"))
  return (directory, screenplay)
}

private let foleyScreenplayText = """
  Title: Tea

  INT. KITCHEN - MORNING

  [[ {"ambience": {
    "prompt": "kettle hiss, quiet kitchen"
  }} ]]

  MARGARET
  More tea?

  [[ {"foley": {
    "prompt": "teacup set down on a saucer",
    "take": 2.0
  }} ]]

  She leaves.

  [[ {"foley": {
    "prompt": "door slams shut",
    "seed": 5,
    "output": "sfx/door.wav"
  }} ]]

  FADE OUT.

  """

private func makeFoleyProject() throws -> (directory: URL, screenplay: URL) {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("AmbienteRenderFoley-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let screenplay = directory.appendingPathComponent("episode.fountain")
  try Data(foleyScreenplayText.utf8).write(to: screenplay)
  return (directory, screenplay)
}

/// Returns a short silent WAV; never touches a model.
private struct FakeGenerator: AmbienteGenerator {
  let generatorId = "fake"
  let displayName = "Fake"
  func isAvailable() async -> Bool { true }
  func generate(prompt: String, settings: GenerationSettings) async throws -> Data {
    let frames = max(1, Int(settings.durationSeconds * 8_000))
    return PCMAudio(samples: [Float](repeating: 0, count: frames), sampleRate: 8_000, channels: 1)
      .wavData()
  }
}

/// Every file under `directory` (relative path → bytes).
private func snapshot(_ directory: URL) throws -> [String: Data] {
  var result: [String: Data] = [:]
  let base = directory.resolvingSymlinksInPath().path
  guard
    let enumerator = FileManager.default.enumerator(
      at: directory.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey])
  else { return result }
  for case let url as URL in enumerator {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey])
    guard values.isRegularFile == true else { continue }
    let path = url.resolvingSymlinksInPath().path
    result[String(path.dropFirst(base.count))] = try Data(contentsOf: url)
  }
  return result
}

// MARK: - Argument parsing

@Suite("ambiente subcommands")
struct AmbienteSubcommandParsingTests {

  @Test("A bare prompt parses into the default generate subcommand")
  func bareFormIsGenerate() throws {
    let parsed = try AmbienteRootCommand.parseAsRoot(["rain", "on", "a", "roof", "-d", "12"])
    let cmd = try #require(parsed as? AmbienteCommand)
    #expect(cmd.promptWords == ["rain", "on", "a", "roof"])
    #expect(cmd.duration == 12)
  }

  @Test("Generate flags work without naming the subcommand")
  func defaultSubcommandFlags() throws {
    let scene = try #require(
      try AmbienteRootCommand.parseAsRoot(["--scene", "forest", "--seed", "42", "-o", "f.wav"])
        as? AmbienteCommand)
    #expect(scene.scene == "forest")
    #expect(scene.seed == 42)
    #expect(scene.output == "f.wav")

    let list = try #require(
      try AmbienteRootCommand.parseAsRoot(["--list-scenes"]) as? AmbienteCommand)
    #expect(list.listScenes)
  }

  @Test("The explicit generate form takes a prompt that starts with a subcommand name")
  func explicitGenerate() throws {
    let cmd = try #require(
      try AmbienteRootCommand.parseAsRoot(["generate", "render", "farm", "hum"])
        as? AmbienteCommand)
    #expect(cmd.promptWords == ["render", "farm", "hum"])
  }

  @Test("render parses its screenplay and flags")
  func parsesRender() throws {
    let cmd = try #require(
      try AmbienteRootCommand.parseAsRoot([
        "render", "ep1.fountain", "--dry-run", "--force", "--project-md", "proj/PROJECT.md",
      ]) as? AmbienteRenderCommand)
    #expect(cmd.screenplay == "ep1.fountain")
    #expect(cmd.dryRun)
    #expect(cmd.force)
    #expect(cmd.projectMd == "proj/PROJECT.md")
  }

  @Test("render flags default off")
  func renderDefaults() throws {
    let cmd = try #require(
      try AmbienteRootCommand.parseAsRoot(["render", "ep1.fountain"]) as? AmbienteRenderCommand)
    #expect(cmd.screenplay == "ep1.fountain")
    #expect(!cmd.dryRun)
    #expect(!cmd.force)
    #expect(cmd.projectMd == nil)
  }

  @Test("render requires a screenplay")
  func renderRequiresScreenplay() {
    #expect(throws: (any Error).self) {
      _ = try AmbienteRootCommand.parseAsRoot(["render"])
    }
  }
}

// MARK: - render

@Suite("ambiente render")
struct AmbienteRenderCommandTests {

  @Test("--dry-run prints the state table and writes nothing")
  func dryRunWritesNothing() async throws {
    let (directory, screenplay) = try makeProject()
    defer { try? FileManager.default.removeItem(at: directory) }
    let before = try snapshot(directory)

    let cmd = try #require(
      try AmbienteRootCommand.parseAsRoot(["render", screenplay.path, "--dry-run"])
        as? AmbienteRenderCommand)
    var emitted: [String] = []
    let failures = try await cmd.execute { emitted.append($0) }

    #expect(failures == 0)
    #expect(try snapshot(directory) == before)
    #expect(try Data(contentsOf: screenplay) == Data(screenplayText.utf8))

    let table = emitted.joined(separator: "\n")
    let lines = table.components(separatedBy: "\n")
    #expect(
      lines.contains { $0.hasPrefix("NOTE") && $0.contains("STATE") && $0.contains("OUTPUT") })

    let newNote = try #require(lines.first { $0.contains("busy bar") })
    #expect(newNote.contains("notRendered"))
    #expect(newNote.contains("would render"))
    #expect(newNote.contains("ambience/episode/amb-"))
    #expect(newNote.contains("…"))  // long prompt is excerpted

    let handPlaced = try #require(lines.first { $0.contains("rain on the window") })
    #expect(handPlaced.contains("unknown"))
    #expect(handPlaced.contains("keep"))
    #expect(handPlaced.contains("beds/hand-placed.wav"))
    #expect(!handPlaced.contains("would render"))

    let traffic = try #require(lines.first { $0.contains("traffic") })
    #expect(traffic.contains("notRendered"))
    #expect(traffic.contains("beds/traffic.wav"))

    #expect(lines.contains { $0.contains("stop") })
  }

  @Test("--force adds current and unknown (hand-placed) takes")
  func forceSelection() throws {
    let (directory, screenplay) = try makeProject()
    defer { try? FileManager.default.removeItem(at: directory) }

    // Make the traffic take `current`: a WAV plus a record with its digest.
    let first = try AmbiencePlanner.plan(screenplay: screenplay, dryRun: true)
    let traffic = try #require(first.entries.first { $0.ambience.prompt == "traffic" })
    let trafficOutput = try #require(traffic.output)
    try Data("RIFF-not-really".utf8).write(to: trafficOutput)
    let record = RenderRecord(
      ambience: traffic.ambience, digest: traffic.ambience.renderDigest,
      generator: "procedural", rendered: Date(timeIntervalSince1970: 0))
    try record.jsonData().write(to: AmbienceRendering.recordURL(for: trafficOutput))

    let plan = try AmbiencePlanner.plan(screenplay: screenplay, dryRun: true)
    #expect(plan.entries.first { $0.ambience.prompt == "traffic" }?.state == .current)

    let normal = AmbienteRenderCommand.entriesToRender(in: plan, force: false)
      .compactMap(\.ambience.prompt)
    #expect(normal.count == 1)
    #expect(normal.first?.hasPrefix("busy bar") == true)

    let forced = AmbienteRenderCommand.entriesToRender(in: plan, force: true)
      .compactMap(\.ambience.prompt)
    #expect(forced.count == 3)
    #expect(forced.contains("traffic"))
    #expect(forced.contains("rain on the window"))

    let warnings = AmbienteRenderCommand.warnings(for: plan)
    #expect(warnings.contains { $0.contains("hand-placed.wav") && $0.contains("left as is") })
    let forcedWarnings = AmbienteRenderCommand.warnings(for: plan, force: true)
    #expect(
      forcedWarnings.contains { $0.contains("hand-placed.wav") && $0.contains("overwriting") })
  }

  @Test("The state table marks rendered and failed outcomes")
  func tableOutcomes() throws {
    let (directory, screenplay) = try makeProject()
    defer { try? FileManager.default.removeItem(at: directory) }
    let plan = try AmbiencePlanner.plan(screenplay: screenplay, dryRun: true)
    let indices = AmbienteRenderCommand.entriesToRender(in: plan, force: false).map(\.noteIndex)
    #expect(indices.count == 2)

    let table = AmbienteRenderCommand.stateTable(
      for: plan, outcomes: [indices[0]: .rendered, indices[1]: .failed])
    let lines = table.components(separatedBy: "\n")
    #expect(lines.first { $0.contains("busy bar") }?.contains("rendered") == true)
    #expect(lines.first { $0.contains("traffic") }?.contains("failed") == true)
  }

  @Test("The state table has a KIND column and rows for both kinds in document order")
  func foleyTable() async throws {
    let (directory, screenplay) = try makeFoleyProject()
    defer { try? FileManager.default.removeItem(at: directory) }
    let before = try snapshot(directory)

    let cmd = try #require(
      try AmbienteRootCommand.parseAsRoot(["render", screenplay.path, "--dry-run"])
        as? AmbienteRenderCommand)
    var emitted: [String] = []
    let failures = try await cmd.execute { emitted.append($0) }
    #expect(failures == 0)
    #expect(try snapshot(directory) == before)  // dry run writes no files

    let lines = emitted.joined(separator: "\n").components(separatedBy: "\n")
    #expect(lines.contains { $0.hasPrefix("NOTE") && $0.contains("KIND") })

    let kettle = try #require(lines.first { $0.contains("kettle hiss") })
    #expect(kettle.contains("ambience"))
    let cup = try #require(lines.first { $0.contains("teacup") })
    #expect(cup.contains("foley"))
    #expect(cup.contains("notRendered"))
    #expect(cup.contains("would render"))
    #expect(cup.contains("foley/episode/fol-"))
    let door = try #require(lines.first { $0.contains("door slams") })
    #expect(door.contains("foley"))
    #expect(door.contains("sfx/door.wav"))

    // Document order: kettle, teacup, door.
    let k = try #require(lines.firstIndex { $0.contains("kettle hiss") })
    let c = try #require(lines.firstIndex { $0.contains("teacup") })
    let d = try #require(lines.firstIndex { $0.contains("door slams") })
    #expect(k < c && c < d)
  }

  @Test("Foley takes are rendered with the injected generator; current ones only with --force")
  func foleyRenders() async throws {
    let (directory, screenplay) = try makeFoleyProject()
    defer { try? FileManager.default.removeItem(at: directory) }

    let cmd = try #require(
      try AmbienteRootCommand.parseAsRoot(["render", screenplay.path]) as? AmbienteRenderCommand)
    var emitted: [String] = []
    let failures = try await cmd.execute(loadGenerator: { _ in FakeGenerator() }) {
      emitted.append($0)
    }
    #expect(failures == 0)

    let plan = try AmbiencePlanner.plan(screenplay: screenplay, dryRun: true)
    #expect(plan.entries.count == 1)
    #expect(plan.foleyEntries.count == 2)
    for entry in plan.foleyEntries {
      let output = try #require(entry.output)
      #expect(FileManager.default.fileExists(atPath: output.path))
      #expect(entry.state == .current)
      let record = try Data(contentsOf: AmbienceRendering.recordURL(for: output))
      let json = try #require(try JSONSerialization.jsonObject(with: record) as? [String: Any])
      #expect(json["foley"] != nil)
      #expect(json["ambience"] == nil)
    }
    let table = emitted.joined(separator: "\n")
    #expect(table.contains("KIND"))
    #expect(table.contains("rendered"))

    // Everything is current now: nothing to do without --force, all with it.
    #expect(AmbienteRenderCommand.foleyEntriesToRender(in: plan, force: false).isEmpty)
    #expect(AmbienteRenderCommand.foleyEntriesToRender(in: plan, force: true).count == 2)
  }

  @Test("A missing screenplay is a validation error")
  func missingScreenplay() async throws {
    let cmd = try #require(
      try AmbienteRootCommand.parseAsRoot([
        "render", "/nonexistent/\(UUID().uuidString).fountain", "--dry-run",
      ]) as? AmbienteRenderCommand)
    await #expect(throws: ValidationError.self) {
      _ = try await cmd.execute { _ in }
    }
  }

  @Test("Prompt excerpts collapse whitespace and truncate")
  func promptExcerpt() {
    #expect(AmbienteRenderCommand.promptExcerpt(nil) == "-")
    #expect(AmbienteRenderCommand.promptExcerpt("  rain \n on   tin ") == "rain on tin")
    let long = String(repeating: "a", count: 50)
    let excerpt = AmbienteRenderCommand.promptExcerpt(long, limit: 10)
    #expect(excerpt.count == 10)
    #expect(excerpt.hasSuffix("…"))
  }
}
