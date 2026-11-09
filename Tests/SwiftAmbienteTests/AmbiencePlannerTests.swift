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

/// The line-level difference between two files, computed in process
/// (`CollectionDifference`, a minimal edit script like a unified diff's): the
/// lines a unified diff would show as `-` (removed) and `+` (inserted).
private func lineDifference(
  _ old: URL, _ new: URL
) throws -> (removed: [Substring], inserted: [Substring]) {
  let oldText = try String(contentsOf: old, encoding: .utf8)
  let newText = try String(contentsOf: new, encoding: .utf8)
  let oldLines = oldText.split(separator: "\n", omittingEmptySubsequences: false)
  let newLines = newText.split(separator: "\n", omittingEmptySubsequences: false)
  var removed: [Substring] = []
  var inserted: [Substring] = []
  for change in newLines.difference(from: oldLines) {
    switch change {
    case .remove(_, let line, _): removed.append(line)
    case .insert(_, let line, _): inserted.append(line)
    }
  }
  return (removed, inserted)
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

    // The line diff contains only insertions (`+` lines), each a seed/output key.
    let (removed, added) = try lineDifference(original, screenplay)
    #expect(removed.isEmpty, "write-back removed or changed lines: \(removed)")
    #expect(added.count == 4, "expected seed+output for two notes: \(added)")
    for line in added {
      #expect(isSeedOrOutputKeyLine(line), "unexpected added line: \(line)")
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

  // MARK: Foley (REQUIREMENTS-foley §§ 3.2, 4.3, D-5)

  @Test("Ambience and foley write-back share one rewrite; only key lines are added")
  func foleyWriteBackSharesOneRewrite() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let original = dir.appendingPathComponent("original.fountain")
    let screenplay = dir.appendingPathComponent("teacup.fountain")
    try write(foleyScreenplayText, to: original)
    try write(foleyScreenplayText, to: screenplay)

    var rng = SeededGenerator(seed: 42)
    var writes: [URL] = []
    let plan = try AmbiencePlanner.plan(
      screenplay: screenplay, using: &rng,
      write: { data, url in
        writes.append(url)
        try AtomicFileWriter.write(data, to: url)
      })
    #expect(writes.count == 1, "expected exactly one rewrite, got \(writes)")
    #expect(writes.first == screenplay.resolvingSymlinksInPath())
    #expect(plan.wroteBack)
    #expect(plan.entries.count == 1)
    #expect(plan.foleyEntries.count == 2)
    #expect(plan.diagnostics.isEmpty)

    // The line diff contains only insertions: seed+output for the ambience
    // note and for the first foley note.
    let (removed, added) = try lineDifference(original, screenplay)
    #expect(removed.isEmpty, "write-back removed or changed lines: \(removed)")
    #expect(added.count == 4, "expected seed+output for two notes: \(added)")
    for line in added {
      #expect(isSeedOrOutputKeyLine(line), "unexpected added line: \(line)")
    }

    let ambience = plan.entries[0]
    #expect(ambience.assignedSeed && ambience.assignedOutput)
    let ambienceOutput = try #require(ambience.ambience.output)
    #expect(ambienceOutput.wholeMatch(of: /ambience\/teacup\/amb-[0-9a-f]{8}\.wav/) != nil)

    let fresh = plan.foleyEntries[0]
    #expect(fresh.assignedSeed && fresh.assignedOutput)
    #expect(fresh.foley.seed != nil)
    let foleyOutput = try #require(fresh.foley.output)
    #expect(
      foleyOutput.wholeMatch(of: /foley\/teacup\/fol-[0-9a-f]{8}\.wav/) != nil,
      "bad output \(foleyOutput)")
    #expect(fresh.output == dir.appendingPathComponent(foleyOutput).standardizedFileURL)
    #expect(fresh.state == .notRendered)
    #expect(fresh.line == 12)

    let complete = plan.foleyEntries[1]
    #expect(!complete.assignedSeed && !complete.assignedOutput)
    #expect(complete.foley.seed == 5)
    #expect(
      complete.output == dir.appendingPathComponent("sfx/door.wav").standardizedFileURL)
    #expect(complete.state == .notRendered)
    #expect(complete.line == 19)

    // The rewritten notes parse to exactly the planned notes, and a second
    // plan has nothing to write.
    var writesAgain = 0
    let reread = try AmbiencePlanner.plan(
      screenplay: screenplay, using: &rng, write: { _, _ in writesAgain += 1 })
    #expect(writesAgain == 0)
    #expect(!reread.wroteBack)
    #expect(reread.entries.map(\.ambience) == plan.entries.map(\.ambience))
    #expect(reread.foleyEntries.map(\.foley) == plan.foleyEntries.map(\.foley))
    #expect(reread.foleyEntries.map(\.output) == plan.foleyEntries.map(\.output))
  }

  @Test("A dry run assigns foley values in the plan but writes nothing")
  func foleyDryRunWritesNothing() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let screenplay = dir.appendingPathComponent("teacup.fountain")
    try write(foleyScreenplayText, to: screenplay)
    let before = try Data(contentsOf: screenplay)

    var rng = SeededGenerator(seed: 5)
    var writes = 0
    let plan = try AmbiencePlanner.plan(
      screenplay: screenplay, dryRun: true, using: &rng, write: { _, _ in writes += 1 })
    #expect(writes == 0)
    #expect(!plan.wroteBack)
    #expect(try Data(contentsOf: screenplay) == before)
    #expect(plan.foleyEntries[0].assignedSeed && plan.foleyEntries[0].assignedOutput)
    #expect(plan.foleyEntries[0].output != nil)
    #expect(plan.foleyEntries[0].state == .notRendered)
    let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(contents == ["teacup.fountain"], "dry run left files: \(contents)")
  }

  @Test("writeBack: false leaves a foley note without output unresolved")
  func foleyWriteBackDisabled() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let screenplay = dir.appendingPathComponent("teacup.fountain")
    try write(foleyScreenplayText, to: screenplay)
    let before = try Data(contentsOf: screenplay)
    // A take with a record for the other kind: reported as changed.
    let door = dir.appendingPathComponent("sfx/door.wav")
    try write("not really a wav", to: door)

    var writes = 0
    var rng = SeededGenerator(seed: 6)
    let plan = try AmbiencePlanner.plan(
      screenplay: screenplay, writeBack: false, using: &rng, write: { _, _ in writes += 1 })
    #expect(writes == 0)
    #expect(!plan.wroteBack)
    #expect(try Data(contentsOf: screenplay) == before)
    let fresh = plan.foleyEntries[0]
    #expect(!fresh.assignedSeed && !fresh.assignedOutput)
    #expect(fresh.foley.seed == nil && fresh.foley.output == nil)
    #expect(fresh.output == nil && fresh.status == nil)
    #expect(plan.foleyEntries[1].output == door.standardizedFileURL)
    #expect(plan.foleyEntries[1].state == .unknown)
  }
}

/// One ambience note and one foley note lacking `seed`/`output`, and one
/// foley note that already has both.
private let foleyScreenplayText = """
  Title: Teacup

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
