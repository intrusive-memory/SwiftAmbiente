//
//  AmbiencePlannerTests.swift
//  SwiftAmbienteTests
//
//  OPERATION BARFLY WALLPAPER, Sortie 7: `AmbiencePlanner` — output
//  resolution, render states and seed/output write-back. Temp directories
//  only; no model, no generation.
//

import Foundation
import GlosaCore
import Testing

@testable import SwiftAmbiente

// MARK: - Fixtures

/// SplitMix64: a seedable generator so write-back values are deterministic.
private struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// Two notes lacking `seed`/`output` (one with author spacing), a `stop`
/// note, and one note that already has both.
private let screenplayText = """
  Title: Barfly

  INT. BAR - NIGHT

  [[ {"ambience": {
    "prompt": "busy bar, glasses clinking",
    "take": 20.0
  }} ]]

  BARTENDER
  What'll it be?

  [[ {"ambience": {
      "prompt":   "rain on the window",
      "length": "continuous"
  }} ]]

  [[ {"ambience": {
    "stop": true
  }} ]]

  EXT. STREET - NIGHT

  [[ {"ambience": {
    "prompt": "traffic",
    "seed": 7,
    "output": "beds/traffic.wav"
  }} ]]

  FADE OUT.

  """

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("AmbiencePlannerTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func write(_ text: String, to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data(text.utf8).write(to: url)
}

/// `diff -u old new` output (empty when identical).
private func unifiedDiff(_ old: URL, _ new: URL) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
  process.arguments = ["-u", old.path, new.path]
  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  #expect(process.terminationStatus <= 1, "diff failed")
  return String(decoding: data, as: UTF8.self)
}

/// Whether `line` (a `+` line's text) is a written-back `seed` / `output` key.
private func isSeedOrOutputKeyLine(_ line: Substring) -> Bool {
  let trimmed = line.trimmingCharacters(in: .whitespaces)
  return (trimmed.hasPrefix("\"seed\": ") || trimmed.hasPrefix("\"output\": "))
    && trimmed.hasSuffix(",")
}

// MARK: - Tests

@Suite("Ambience planner")
struct AmbiencePlannerTests {

  // MARK: Output resolution (§ 3.3)

  @Test("An absolute output resolves as is")
  func absoluteOutput() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let absolute = dir.appendingPathComponent("elsewhere/bed.wav").path
    let screenplay = dir.appendingPathComponent("show/ep1.fountain")
    try write(
      """
      [[ {"ambience": {
        "prompt": "wind",
        "seed": 1,
        "output": "\(absolute)"
      }} ]]

      """, to: screenplay)
    try write("# Project\n", to: dir.appendingPathComponent("show/PROJECT.md"))

    let plan = try AmbiencePlanner.plan(screenplay: screenplay)
    #expect(plan.entries.count == 1)
    #expect(plan.entries[0].output == URL(fileURLWithPath: absolute).standardizedFileURL)
  }

  @Test("A relative output resolves against the PROJECT.md directory when one is found")
  func relativeOutputWithProjectMarkdown() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let screenplay = dir.appendingPathComponent("episodes/ep1.fountain")
    try write(
      """
      [[ {"ambience": {
        "prompt": "wind",
        "seed": 1,
        "output": "beds/wind.wav"
      }} ]]

      """, to: screenplay)

    // Explicit PROJECT.md in a parent directory.
    let projectMd = dir.appendingPathComponent("PROJECT.md")
    try write("# Project\n", to: projectMd)
    let explicit = try AmbiencePlanner.plan(screenplay: screenplay, projectMarkdown: projectMd)
    #expect(explicit.projectMarkdown == projectMd)
    #expect(explicit.outputBase.standardizedFileURL.path == dir.standardizedFileURL.path)
    #expect(
      explicit.entries[0].output
        == dir.appendingPathComponent("beds/wind.wav").standardizedFileURL)
    #expect(explicit.warnings.isEmpty)

    // Discovered `<screenplay dir>/PROJECT.md`.
    let sibling = dir.appendingPathComponent("episodes/PROJECT.md")
    try write("# Episodes\n", to: sibling)
    let discovered = try AmbiencePlanner.plan(screenplay: screenplay)
    #expect(discovered.projectMarkdown == sibling)
    #expect(
      discovered.entries[0].output
        == dir.appendingPathComponent("episodes/beds/wind.wav").standardizedFileURL)
  }

  @Test("A relative output resolves against the screenplay directory without a PROJECT.md")
  func relativeOutputWithoutProjectMarkdown() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let screenplay = dir.appendingPathComponent("episodes/ep1.fountain")
    try write(
      """
      [[ {"ambience": {
        "prompt": "wind",
        "seed": 1,
        "output": "beds/wind.wav"
      }} ]]

      """, to: screenplay)

    let plan = try AmbiencePlanner.plan(screenplay: screenplay)
    #expect(plan.projectMarkdown == nil)
    #expect(
      plan.entries[0].output
        == dir.appendingPathComponent("episodes/beds/wind.wav").standardizedFileURL)

    // An explicit PROJECT.md that does not exist is not "found": warn, use
    // the screenplay directory.
    let missing = dir.appendingPathComponent("PROJECT.md")
    let withMissing = try AmbiencePlanner.plan(screenplay: screenplay, projectMarkdown: missing)
    #expect(withMissing.projectMarkdown == nil)
    #expect(withMissing.entries[0].output == plan.entries[0].output)
    #expect(withMissing.warnings.count == 1)
  }

  // MARK: Write-back (§ 3.2)

  @Test("Write-back adds only seed/output key lines, deterministically")
  func writeBackDiffIsOnlyAddedKeyLines() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let original = dir.appendingPathComponent("original.fountain")
    let screenplay = dir.appendingPathComponent("barfly.fountain")
    try write(screenplayText, to: original)
    try write(screenplayText, to: screenplay)

    var rng = SeededGenerator(seed: 2026)
    let plan = try AmbiencePlanner.plan(screenplay: screenplay, using: &rng)
    #expect(plan.wroteBack)
    #expect(plan.entries.count == 4)

    // The unified diff contains only `+` lines, each a seed/output key.
    let diff = try unifiedDiff(original, screenplay)
    let body = diff.split(separator: "\n", omittingEmptySubsequences: false).filter {
      !$0.hasPrefix("---") && !$0.hasPrefix("+++") && !$0.hasPrefix("@@")
        && !$0.hasPrefix("\\")
    }
    let removed = body.filter { $0.hasPrefix("-") }
    let added = body.filter { $0.hasPrefix("+") }
    #expect(removed.isEmpty, "write-back removed or changed lines: \(removed)")
    #expect(added.count == 4, "expected seed+output for two notes:\n\(diff)")
    for line in added {
      #expect(isSeedOrOutputKeyLine(line.dropFirst()), "unexpected added line: \(line)")
    }

    // Assigned values: seed + `ambience/<stem>/amb-<8 hex>.wav`; stop and
    // complete notes untouched.
    let pattern = /ambience\/barfly\/amb-[0-9a-f]{8}\.wav/
    for entry in plan.entries[0...1] {
      #expect(entry.assignedSeed && entry.assignedOutput)
      #expect(entry.ambience.seed != nil)
      let output = try #require(entry.ambience.output)
      #expect(output.wholeMatch(of: pattern) != nil, "bad output \(output)")
      #expect(entry.output == dir.appendingPathComponent(output).standardizedFileURL)
      #expect(entry.state == .notRendered)
    }
    #expect(plan.entries[0].ambience.output != plan.entries[1].ambience.output)
    #expect(plan.entries[2].ambience.stop)
    #expect(!plan.entries[2].assignedSeed && !plan.entries[2].assignedOutput)
    #expect(plan.entries[2].ambience.seed == nil && plan.entries[2].ambience.output == nil)
    #expect(plan.entries[2].output == nil && plan.entries[2].status == nil)
    #expect(!plan.entries[3].assignedSeed && !plan.entries[3].assignedOutput)
    #expect(plan.entries[3].ambience.seed == 7)

    // The rewritten notes parse to exactly the planned ambiences.
    let reread = try AmbiencePlanner.plan(screenplay: screenplay, writeBack: false)
    #expect(reread.entries.map(\.ambience) == plan.entries.map(\.ambience))
    // Author spacing in the second note survives.
    let rewritten = try String(contentsOf: screenplay, encoding: .utf8)
    #expect(rewritten.contains("    \"prompt\":   \"rain on the window\",\n"))

    // The same generator seed assigns the same values.
    let copy = dir.appendingPathComponent("again/barfly.fountain")
    try write(screenplayText, to: copy)
    var again = SeededGenerator(seed: 2026)
    let replay = try AmbiencePlanner.plan(screenplay: copy, using: &again)
    #expect(replay.entries.map(\.ambience.seed) == plan.entries.map(\.ambience.seed))
    #expect(replay.entries.map(\.ambience.output) == plan.entries.map(\.ambience.output))
  }

  @Test("A second plan after write-back is a no-op")
  func secondPlanIsNoOp() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let screenplay = dir.appendingPathComponent("barfly.fountain")
    try write(screenplayText, to: screenplay)

    var rng = SeededGenerator(seed: 1)
    let first = try AmbiencePlanner.plan(screenplay: screenplay, using: &rng)
    #expect(first.wroteBack)
    let afterFirst = try Data(contentsOf: screenplay)

    let second = try AmbiencePlanner.plan(screenplay: screenplay, using: &rng)
    #expect(!second.wroteBack)
    #expect(try Data(contentsOf: screenplay) == afterFirst)
    #expect(second.entries.allSatisfy { !$0.assignedSeed && !$0.assignedOutput })
    #expect(second.entries.map(\.ambience) == first.entries.map(\.ambience))
    #expect(second.entries.map(\.output) == first.entries.map(\.output))
  }

  @Test("A dry run assigns values in the plan but leaves the file byte-identical")
  func dryRunWritesNothing() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let screenplay = dir.appendingPathComponent("barfly.fountain")
    try write(screenplayText, to: screenplay)
    let before = try Data(contentsOf: screenplay)

    var rng = SeededGenerator(seed: 3)
    let plan = try AmbiencePlanner.plan(screenplay: screenplay, dryRun: true, using: &rng)
    #expect(!plan.wroteBack)
    #expect(try Data(contentsOf: screenplay) == before)
    #expect(plan.entries[0].assignedSeed && plan.entries[0].assignedOutput)
    #expect(plan.entries[0].state == .notRendered)
    let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(contents == ["barfly.fountain"], "dry run left files: \(contents)")
  }

  @Test("writeBack: false assigns nothing and writes nothing")
  func writeBackDisabled() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let screenplay = dir.appendingPathComponent("barfly.fountain")
    try write(screenplayText, to: screenplay)
    let before = try Data(contentsOf: screenplay)

    let plan = try AmbiencePlanner.plan(screenplay: screenplay, writeBack: false)
    #expect(!plan.wroteBack)
    #expect(try Data(contentsOf: screenplay) == before)
    #expect(plan.entries[0].ambience.seed == nil)
    #expect(plan.entries[0].output == nil && plan.entries[0].status == nil)
    #expect(
      plan.entries[3].output
        == dir.appendingPathComponent("beds/traffic.wav").standardizedFileURL)
  }

  // MARK: States and lines

  @Test("Entries carry render states and screenplay line numbers")
  func statesAndLines() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let screenplay = dir.appendingPathComponent("barfly.fountain")
    try write(screenplayText, to: screenplay)
    // A hand-placed take with no record for the complete note.
    try write("not really a wav", to: dir.appendingPathComponent("beds/traffic.wav"))

    let plan = try AmbiencePlanner.plan(screenplay: screenplay, writeBack: false)
    #expect(plan.entries.map(\.line) == [5, 13, 18, 24])
    #expect(plan.entries[3].state == .unknown)
    #expect(plan.diagnostics.isEmpty)
  }

  @Test("A single-line note falls back to the canonical serialization")
  func singleLineNoteFallsBackToSerialize() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let prefix = "INT. ROOM - DAY\n\n"
    let suffix = "\n\nShe waits.\r\n"
    let screenplay = dir.appendingPathComponent("room.fountain")
    try write(prefix + #"[[ {"ambience": {"prompt": "room tone"}} ]]"# + suffix, to: screenplay)

    var rng = SeededGenerator(seed: 9)
    let plan = try AmbiencePlanner.plan(screenplay: screenplay, using: &rng)
    #expect(plan.wroteBack)
    let text = try String(contentsOf: screenplay, encoding: .utf8)
    #expect(text.hasPrefix(prefix + "[[ {\"ambience\": {\n"))
    #expect(text.hasSuffix("}} ]]" + suffix))
    #expect(text == prefix + plan.entries[0].ambience.serialize() + suffix)

    let reread = try AmbiencePlanner.plan(screenplay: screenplay, writeBack: false)
    #expect(reread.entries.map(\.ambience) == plan.entries.map(\.ambience))
  }

  @Test("CRLF line endings are kept in inserted key lines")
  func crlfLineEndings() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let screenplay = dir.appendingPathComponent("crlf.fountain")
    let original = "[[ {\"ambience\": {\r\n  \"prompt\": \"hum\"\r\n}} ]]\r\n"
    try write(original, to: screenplay)

    var rng = SeededGenerator(seed: 11)
    let plan = try AmbiencePlanner.plan(screenplay: screenplay, using: &rng)
    let entry = plan.entries[0]
    let seed = try #require(entry.ambience.seed)
    let output = try #require(entry.ambience.output)
    let expected =
      "[[ {\"ambience\": {\r\n  \"seed\": \(seed),\r\n  \"output\": \"\(output)\",\r\n"
      + "  \"prompt\": \"hum\"\r\n}} ]]\r\n"
    #expect(try String(contentsOf: screenplay, encoding: .utf8) == expected)
  }
}
