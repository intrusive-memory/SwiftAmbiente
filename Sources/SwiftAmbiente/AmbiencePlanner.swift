//
//  AmbiencePlanner.swift
//  SwiftAmbiente
//
//  Plans the ambience beds of a screenplay: finds its `ambience` notes,
//  resolves each note's `output`, writes back missing `seed` / `output` keys,
//  and reports each take's render state (Produciesta REQUIREMENTS-ambience
//  §§ 3.1–3.3, decisions D-8 and D-13). Shared by `ambiente render` and
//  Produciesta's export.
//

import Foundation
import GlosaCore

// MARK: - Plan

/// One `ambience` note of a screenplay, as planned.
public struct AmbiencePlanEntry: Sendable, Equatable {
  /// The note's position among the screenplay's standalone notes (its
  /// `documentIndex`).
  public var noteIndex: Int

  /// The 1-based line of the screenplay on which the note's `[[` sits.
  public var line: Int

  /// The note, including any `seed` / `output` this plan assigned (also in a
  /// dry run, where they are not written to the file).
  public var ambience: GlosaCore.Ambience

  /// `true` when this plan assigned `seed`.
  public var assignedSeed: Bool

  /// `true` when this plan assigned `output`.
  public var assignedOutput: Bool

  /// The resolved take WAV location. `nil` for a `stop` note, and for a note
  /// with no `output` that this plan did not assign one to (write-back off, or
  /// a note without a prompt).
  public var output: URL?

  /// The render state of the take at `output`; `nil` when `output` is `nil`.
  public var status: AmbienceRenderStatus?

  /// `status?.state`.
  public var state: AmbienceRenderState? { status?.state }

  public init(
    noteIndex: Int,
    line: Int,
    ambience: GlosaCore.Ambience,
    assignedSeed: Bool = false,
    assignedOutput: Bool = false,
    output: URL? = nil,
    status: AmbienceRenderStatus? = nil
  ) {
    self.noteIndex = noteIndex
    self.line = line
    self.ambience = ambience
    self.assignedSeed = assignedSeed
    self.assignedOutput = assignedOutput
    self.output = output
    self.status = status
  }
}

/// The ambience plan of one screenplay.
public struct AmbiencePlan: Sendable, Equatable {
  /// The screenplay planned.
  public var screenplay: URL

  /// The PROJECT.md found (explicit or beside the screenplay), or `nil`.
  public var projectMarkdown: URL?

  /// The directory relative `output` paths resolve against: the PROJECT.md
  /// directory when one was found, else the screenplay directory.
  public var outputBase: URL

  /// Every `ambience` note, `stop` notes included, in document order.
  public var entries: [AmbiencePlanEntry]

  /// Parser diagnostics for `ambience` notes (an unreadable note is reported
  /// here and has no entry). `line` is the screenplay line of the note.
  public var diagnostics: [GlosaDiagnostic]

  /// Planner warnings (e.g. an explicit PROJECT.md that does not exist).
  public var warnings: [String]

  /// `true` when the screenplay file was rewritten.
  public var wroteBack: Bool

  public init(
    screenplay: URL,
    projectMarkdown: URL?,
    outputBase: URL,
    entries: [AmbiencePlanEntry],
    diagnostics: [GlosaDiagnostic] = [],
    warnings: [String] = [],
    wroteBack: Bool = false
  ) {
    self.screenplay = screenplay
    self.projectMarkdown = projectMarkdown
    self.outputBase = outputBase
    self.entries = entries
    self.diagnostics = diagnostics
    self.warnings = warnings
    self.wroteBack = wroteBack
  }
}

// MARK: - Planner

/// Plans a screenplay's ambience beds (REQUIREMENTS-ambience §§ 3.1–3.3).
///
/// ```swift
/// let plan = try AmbiencePlanner.plan(screenplay: url)
/// for entry in plan.entries where entry.state == .notRendered || entry.state == .changed {
///   _ = try await generator.render(ambience: entry.ambience, to: entry.output!)
/// }
/// ```
public enum AmbiencePlanner {

  /// Plans `screenplay`.
  ///
  /// 1. Finds the standalone notes (`GlosaFountainNotes`) and parses them with
  ///    `GlosaParser`; every `ambience` note becomes an entry.
  /// 2. Write-back (§ 3.2, D-8): a non-`stop` note with a prompt that lacks
  ///    `seed` gets a random `UInt32`; one that lacks `output` gets
  ///    `ambience/<screenplay stem>/amb-<8 hex>.wav`. The keys are inserted
  ///    into those notes only, and the file is replaced atomically. Every byte
  ///    outside the rewritten notes is kept.
  /// 3. Resolves `output` (§ 3.3) and reads the render state (§ 3.1).
  ///
  /// - Parameters:
  ///   - screenplay: The `.fountain` file.
  ///   - projectMarkdown: An explicit PROJECT.md. When `nil`,
  ///     `<screenplay dir>/PROJECT.md` is used if it exists.
  ///   - writeBack: `false` assigns nothing and writes nothing; a note without
  ///     `output` then has no resolved output (the caller renders it elsewhere).
  ///   - dryRun: Assigns `seed` / `output` in the returned plan but writes
  ///     nothing.
  /// - Throws: A file-system error reading or writing the screenplay, or
  ///   ``AmbienteError/invalidAmbience(_:)`` when a write-back is needed but
  ///   the screenplay is not valid UTF-8.
  public static func plan(
    screenplay: URL,
    projectMarkdown: URL? = nil,
    writeBack: Bool = true,
    dryRun: Bool = false
  ) throws -> AmbiencePlan {
    var generator = SystemRandomNumberGenerator()
    return try plan(
      screenplay: screenplay, projectMarkdown: projectMarkdown, writeBack: writeBack,
      dryRun: dryRun, using: &generator)
  }

  /// ``plan(screenplay:projectMarkdown:writeBack:dryRun:)`` drawing seeds and
  /// output names from `generator` (tests pass a seeded generator).
  ///
  /// Draw order is document order; per note, `seed` first, then `output`.
  public static func plan<G: RandomNumberGenerator>(
    screenplay: URL,
    projectMarkdown: URL? = nil,
    writeBack: Bool = true,
    dryRun: Bool = false,
    using generator: inout G
  ) throws -> AmbiencePlan {
    var warnings: [String] = []
    let foundProjectMarkdown = Self.projectMarkdown(
      forScreenplay: screenplay, explicit: projectMarkdown)
    if let projectMarkdown, foundProjectMarkdown == nil {
      warnings.append(
        "PROJECT.md \(projectMarkdown.path) does not exist; relative ambience outputs resolve against the screenplay directory."
      )
    }
    let base = outputBase(forScreenplay: screenplay, projectMarkdown: foundProjectMarkdown)

    let data = try Data(contentsOf: screenplay)
    let text = String(decoding: data, as: UTF8.self)
    let notes = GlosaFountainNotes.standaloneNotes(in: text)
    let parsed = GlosaParser().parseFountainWithDiagnostics(notes: notes.map(\.text))
    let lines = lineNumbers(of: notes.map(\.range.lowerBound), in: text)

    // Outputs already taken in this document, so a fresh name never collides.
    var usedOutputs = Set<String>()
    for ambience in parsed.score.ambiences {
      if let output = ambience.output {
        usedOutputs.insert(resolveOutput(output, base: base).path)
      }
    }

    let stem = screenplay.deletingPathExtension().lastPathComponent
    var entries: [AmbiencePlanEntry] = []
    var replacements: [(range: Range<String.Index>, note: String)] = []

    for original in parsed.score.ambiences {
      let index = original.documentIndex
      var ambience = original
      var assignedSeed = false
      var assignedOutput = false

      if writeBack, needsWriteBack(original) {
        if ambience.seed == nil {
          ambience.seed = UInt32.random(in: .min ... .max, using: &generator)
          assignedSeed = true
        }
        if ambience.output == nil {
          let path = freshOutput(stem: stem, base: base, used: usedOutputs, using: &generator)
          usedOutputs.insert(resolveOutput(path, base: base).path)
          ambience.output = path
          assignedOutput = true
        }
        let noteText = String(text[notes[index].range])
        replacements.append(
          (notes[index].range, rewrittenNote(noteText, original: original, updated: ambience)))
      }

      let output: URL? =
        ambience.stop ? nil : ambience.output.map { resolveOutput($0, base: base) }
      entries.append(
        AmbiencePlanEntry(
          noteIndex: index,
          line: lines[index],
          ambience: ambience,
          assignedSeed: assignedSeed,
          assignedOutput: assignedOutput,
          output: output,
          status: output.map { AmbienceRendering.renderStatus(for: ambience, output: $0) }
        ))
    }

    var wroteBack = false
    if !replacements.isEmpty, !dryRun {
      guard Data(text.utf8) == data else {
        throw AmbienteError.invalidAmbience(
          "\(screenplay.lastPathComponent) is not valid UTF-8; seed/output write-back refused")
      }
      var rewritten = ""
      rewritten.reserveCapacity(text.utf8.count + replacements.count * 96)
      var cursor = text.startIndex
      for replacement in replacements.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
        rewritten.append(contentsOf: text[cursor..<replacement.range.lowerBound])
        rewritten.append(replacement.note)
        cursor = replacement.range.upperBound
      }
      rewritten.append(contentsOf: text[cursor...])
      try AtomicFileWriter.write(Data(rewritten.utf8), to: screenplay.resolvingSymlinksInPath())
      wroteBack = true
    }

    let diagnostics = parsed.diagnostics.compactMap { diagnostic -> GlosaDiagnostic? in
      // The parser numbers lines by note (note index + 1); report the
      // screenplay line instead, and keep only diagnostics about ambience
      // notes (the parser sees no dialogue here, so its dialogue-related
      // diagnostics are meaningless).
      guard let line = diagnostic.line, line >= 1, line <= notes.count,
        notes[line - 1].text.contains("\"ambience\"")
      else { return nil }
      var remapped = diagnostic
      remapped.line = lines[line - 1]
      return remapped
    }

    return AmbiencePlan(
      screenplay: screenplay,
      projectMarkdown: foundProjectMarkdown,
      outputBase: base,
      entries: entries,
      diagnostics: diagnostics,
      warnings: warnings,
      wroteBack: wroteBack
    )
  }

  // MARK: Output resolution (§ 3.3)

  /// The PROJECT.md that governs `screenplay`: `explicit` when given, else
  /// `<screenplay dir>/PROJECT.md` — and only if that file exists.
  public static func projectMarkdown(forScreenplay screenplay: URL, explicit: URL?) -> URL? {
    let candidate =
      explicit
      ?? screenplay.deletingLastPathComponent().appendingPathComponent("PROJECT.md")
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else { return nil }
    return candidate
  }

  /// The directory relative outputs resolve against: the PROJECT.md directory
  /// when one was found, else the screenplay directory.
  public static func outputBase(forScreenplay screenplay: URL, projectMarkdown: URL?) -> URL {
    (projectMarkdown ?? screenplay).deletingLastPathComponent()
  }

  /// `output` as a file URL: an absolute path as is, a relative one against
  /// `base`.
  public static func resolveOutput(_ output: String, base: URL) -> URL {
    if output.hasPrefix("/") {
      return URL(fileURLWithPath: output).standardizedFileURL
    }
    return base.appendingPathComponent(output).standardizedFileURL
  }

  // MARK: Write-back (§ 3.2)

  /// Whether `ambience` gets `seed` / `output` written back: not a `stop`
  /// note, has a prompt, and lacks either key.
  static func needsWriteBack(_ ambience: GlosaCore.Ambience) -> Bool {
    guard !ambience.stop,
      let prompt = ambience.prompt,
      !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return false }
    return ambience.seed == nil || ambience.output == nil
  }

  /// A fresh `ambience/<stem>/amb-<8 hex>.wav` that no other note uses and no
  /// file occupies.
  static func freshOutput<G: RandomNumberGenerator>(
    stem: String, base: URL, used: Set<String>, using generator: inout G
  ) -> String {
    var path = ""
    for _ in 0..<64 {
      let hex = String(format: "%08x", UInt32.random(in: .min ... .max, using: &generator))
      path = "ambience/\(stem)/amb-\(hex).wav"
      let resolved = resolveOutput(path, base: base)
      if !used.contains(resolved.path),
        !FileManager.default.fileExists(atPath: resolved.path)
      {
        break
      }
    }
    return path
  }

  /// The note text with `updated`'s new `seed` / `output` keys in it.
  ///
  /// The canonical `serialize()` places `output` (and, in a prompt-only note,
  /// `seed`) **last**, which forces a comma onto the line before it — a
  /// changed line, not a pure addition — and it would also normalize any
  /// author spacing or key order. So the new key lines are instead inserted
  /// into the original text directly after the opening `{"ambience": {` line,
  /// each ending in a comma, indented like the first existing key. Every
  /// existing line stays byte-identical and the diff is exactly the added
  /// `"seed"` / `"output"` lines; the cost is that the keys lead the object
  /// rather than sitting in canonical order (JSON key order is not
  /// significant; a later canonical re-serialization simply reorders them).
  ///
  /// Only when the note's shape allows no such insertion (a single-line
  /// note, an empty object, or anything that does not re-parse to exactly
  /// `updated`) is the whole note replaced by `updated.serialize()`.
  static func rewrittenNote(
    _ note: String, original: GlosaCore.Ambience, updated: GlosaCore.Ambience
  ) -> String {
    var keyLines: [String] = []
    if original.seed == nil, updated.seed != nil { keyLines.append("seed") }
    if original.output == nil, updated.output != nil { keyLines.append("output") }

    let canonicalLines = canonicalKeyLines(for: updated, keys: keyLines)
    if canonicalLines.count == keyLines.count,
      let inserted = insertingKeyLines(canonicalLines, into: note),
      reparsedAmbience(inserted, documentIndex: updated.documentIndex) == updated
    {
      return inserted
    }
    return updated.serialize()
  }

  /// The canonical `"key": value` text for `keys` of `ambience`, as
  /// `serialize()` writes it (same escaping), without indent or comma.
  static func canonicalKeyLines(for ambience: GlosaCore.Ambience, keys: [String]) -> [String] {
    var subset = GlosaCore.Ambience(documentIndex: 0)
    subset.seed = keys.contains("seed") ? ambience.seed : nil
    subset.output = keys.contains("output") ? ambience.output : nil
    let lines = subset.serialize().components(separatedBy: "\n")
    return keys.compactMap { key in
      lines.lazy
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .first { $0.hasPrefix("\"\(key)\":") }
        .map { $0.hasSuffix(",") ? String($0.dropLast()) : $0 }
    }
  }

  /// `note` with `keyLines` inserted as whole lines right after the line that
  /// opens the `ambience` object, or `nil` when that line carries anything
  /// after the `{` or the next line is not a key.
  static func insertingKeyLines(_ keyLines: [String], into note: String) -> String? {
    guard !keyLines.isEmpty, note.hasPrefix("[[") else { return nil }
    var i = note.index(note.startIndex, offsetBy: 2)
    func skipWhitespace() {
      while i < note.endIndex, note[i].isWhitespace { i = note.index(after: i) }
    }
    func expect(_ token: String) -> Bool {
      skipWhitespace()
      guard note[i...].hasPrefix(token) else { return false }
      i = note.index(i, offsetBy: token.count)
      return true
    }
    guard expect("{"), expect("\"ambience\""), expect(":"), expect("{") else { return nil }

    // The rest of the opening line must be blank, ending in a line break.
    while i < note.endIndex, !note[i].isNewline {
      guard note[i].isWhitespace else { return nil }
      i = note.index(after: i)
    }
    guard i < note.endIndex else { return nil }
    let lineBreak = String(note[i])
    let insertAt = note.index(after: i)

    // The next line must be a key; its indentation is reused.
    var j = insertAt
    while j < note.endIndex, note[j].isWhitespace, !note[j].isNewline {
      j = note.index(after: j)
    }
    guard j < note.endIndex, note[j] == "\"" else { return nil }
    let indent = String(note[insertAt..<j])

    let insertion = keyLines.map { indent + $0 + "," + lineBreak }.joined()
    return String(note[..<insertAt]) + insertion + String(note[insertAt...])
  }

  /// The `ambience` a rewritten note parses to, or `nil`.
  static func reparsedAmbience(_ note: String, documentIndex: Int) -> GlosaCore.Ambience? {
    guard let found = GlosaFountainNotes.standaloneNotes(in: note).first,
      var ambience = GlosaParser().parseFountain(notes: [found.text]).ambiences.first
    else { return nil }
    ambience.documentIndex = documentIndex
    return ambience
  }

  // MARK: Lines

  /// 1-based line numbers of `positions` (ascending) in `text`.
  static func lineNumbers(of positions: [String.Index], in text: String) -> [Int] {
    var result: [Int] = []
    result.reserveCapacity(positions.count)
    var line = 1
    var cursor = text.startIndex
    for position in positions {
      while cursor < position {
        if text[cursor].isNewline { line += 1 }
        cursor = text.index(after: cursor)
      }
      result.append(line)
    }
    return result
  }
}
