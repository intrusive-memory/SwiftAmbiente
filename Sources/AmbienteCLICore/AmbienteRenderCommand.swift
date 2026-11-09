//
//  AmbienteRenderCommand.swift
//  AmbienteCLICore
//
//  `ambiente render <screenplay>` — plan a screenplay's GLOSA `ambience` notes
//  and `foley` notes with `AmbiencePlanner` (output resolution, render state, seed/output
//  write-back), generate every `changed` / `notRendered` take, and print a
//  state table (Produciesta REQUIREMENTS-ambience § 4.4).
//

import ArgumentParser
import Foundation
import SwiftAmbiente

public struct AmbienteRenderCommand: AsyncParsableCommand {
  public init() {}

  public static let configuration = CommandConfiguration(
    commandName: "render",
    abstract: "Render the ambience beds and foley effects of a screenplay's GLOSA notes.",
    discussion: """
      Plans every `ambience` and `foley` note in the screenplay: resolves its `output`
      (relative paths against the PROJECT.md directory when one is found, else
      the screenplay directory), writes a missing `seed` / `output` back into
      the note, and reads the take's render state. Then generates every
      `changed` / `notRendered` take (every take with --force) with the
      backend the note's `model` names — downloading its model on first use,
      with no procedural fallback — and prints a state table.

      A take in state `unknown` (a WAV with no render record — a hand-placed
      file) is kept and reported with a warning. --force overwrites it too.

      --dry-run reports the plan and changes nothing: no write-back, no takes.
      """
  )

  @Argument(help: "The .fountain screenplay whose ambience notes to render.")
  public var screenplay: String

  @Flag(name: .long, help: "Print the plan's state table; write and generate nothing.")
  public var dryRun: Bool = false

  @Flag(
    name: .long, help: "Regenerate every take, including current and hand-placed (`unknown`) ones.")
  public var force: Bool = false

  @Option(
    name: .customLong("project-md"),
    help:
      "PROJECT.md that relative outputs resolve against. Default: <screenplay dir>/PROJECT.md if present."
  )
  public var projectMd: String?

  // MARK: - Run

  public mutating func run() async throws {
    AmbienteCommand.applyDefaultCDNBaseURL()
    let failures = try await execute { print($0) }
    if failures > 0 {
      throw ExitCode.failure
    }
  }

  /// Plans the screenplay, renders the selected takes (unless `--dry-run`),
  /// and hands the state table to `emit`. Warnings go to stderr.
  ///
  /// A dry run never resolves a generator, so it loads no model. `loadGenerator`
  /// replaces the model manager (tests inject a fake).
  ///
  /// - Returns: The number of takes that failed to render.
  @discardableResult
  public func execute(
    loadGenerator: ((StableAudioModelRepo) async throws -> any AmbienteGenerator)? = nil,
    emit: (String) -> Void
  ) async throws -> Int {
    let screenplayURL = URL(fileURLWithPath: screenplay).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: screenplayURL.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw ValidationError("Screenplay not found: \(screenplay)")
    }
    let projectURL = projectMd.map { URL(fileURLWithPath: $0).standardizedFileURL }

    let plan = try AmbiencePlanner.plan(
      screenplay: screenplayURL, projectMarkdown: projectURL, writeBack: true, dryRun: dryRun)

    for warning in Self.warnings(for: plan, force: force) {
      Self.warn(warning)
    }

    var outcomes: [Int: AmbienceRenderOutcome] = [:]
    var failures = 0
    let selectedAmbience = Self.entriesToRender(in: plan, force: force)
    let selectedFoley = Self.foleyEntriesToRender(in: plan, force: force)

    // One work list across both kinds, in document order.
    struct Job {
      var noteIndex: Int
      var line: Int
      var output: URL
      var model: String
      var render: (any AmbienteGenerator, URL) async throws -> Void
    }
    var jobs: [Job] = []
    for entry in selectedAmbience {
      guard let output = entry.output else { continue }
      jobs.append(
        Job(
          noteIndex: entry.noteIndex, line: entry.line, output: output,
          model: entry.ambience.effectiveModel,
          render: { generator, url in
            _ = try await generator.render(ambience: entry.ambience, to: url)
          }
        ))
    }
    for entry in selectedFoley {
      guard let output = entry.output else { continue }
      jobs.append(
        Job(
          noteIndex: entry.noteIndex, line: entry.line, output: output,
          model: entry.foley.effectiveModel,
          render: { generator, url in _ = try await generator.render(foley: entry.foley, to: url) }
        ))
    }
    jobs.sort { $0.noteIndex < $1.noteIndex }

    if dryRun {
      for job in jobs { outcomes[job.noteIndex] = .wouldRender }
    } else if !jobs.isEmpty {
      // The note's `model` picks the backend, loaded (downloaded on first use)
      // through the model manager. Unlike `AmbienteEngine.resolveGenerator`,
      // there is no procedural fallback: a fallback take would get a render
      // record matching the note's digest and read as `current`, so the real
      // model would never replace it.
      let manager = AmbienteModelManager()
      let load = loadGenerator ?? { repo in try await manager.loadGenerator(repo) }
      var generators: [StableAudioModelRepo: Result<any AmbienteGenerator, any Error>] = [:]
      for job in jobs {
        do {
          let repo = try AmbienceModel.resolve(job.model).modelRepo
          if generators[repo] == nil {
            FileHandle.standardError.write(Data("loading model \(repo.rawValue)\n".utf8))
            do {
              generators[repo] = .success(try await load(repo))
            } catch {
              generators[repo] = .failure(error)
            }
          }
          let generator = try generators[repo]!.get()
          FileHandle.standardError.write(
            Data("rendering note \(job.noteIndex) (line \(job.line)) → \(job.output.path)\n".utf8))
          try await job.render(generator, job.output)
          outcomes[job.noteIndex] = .rendered
        } catch {
          failures += 1
          outcomes[job.noteIndex] = .failed
          Self.warn(
            "note \(job.noteIndex) (line \(job.line)): render failed: \(error.localizedDescription)",
            prefix: "error: ")
        }
      }
    }

    emit(Self.stateTable(for: plan, outcomes: outcomes))
    return failures
  }

  // MARK: - Selection

  /// Whether an entry is a take that can be rendered: not a `stop` note, has
  /// a prompt and a resolved output.
  static func isRenderable(_ entry: AmbiencePlanEntry) -> Bool {
    guard !entry.ambience.stop, entry.output != nil, entry.state != nil,
      let prompt = entry.ambience.prompt,
      !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return false }
    return true
  }

  /// The entries to generate: renderable `changed` / `notRendered` takes, or
  /// with `force` every renderable take, including `current` and `unknown`
  /// (hand-placed) ones.
  public static func entriesToRender(in plan: AmbiencePlan, force: Bool) -> [AmbiencePlanEntry] {
    plan.entries.filter { entry in
      guard isRenderable(entry), let state = entry.state else { return false }
      switch state {
      case .changed, .notRendered: return true
      case .current, .unknown: return force
      }
    }
  }

  /// The foley counterpart of ``entriesToRender(in:force:)``: renderable
  /// (prompt, resolved output) `changed` / `notRendered` foley takes, plus
  /// `current` and `unknown` ones with `force`.
  public static func foleyEntriesToRender(in plan: AmbiencePlan, force: Bool) -> [FoleyPlanEntry] {
    plan.foleyEntries.filter { entry in
      guard entry.output != nil, let state = entry.state,
        let prompt = entry.foley.prompt,
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return false }
      switch state {
      case .changed, .notRendered: return true
      case .current, .unknown: return force
      }
    }
  }

  /// Planner warnings, note diagnostics, unreadable-record warnings, and one
  /// warning per `unknown` take (kept, or overwritten when `force`), ready to print.
  public static func warnings(for plan: AmbiencePlan, force: Bool = false) -> [String] {
    var result = plan.warnings
    for diagnostic in plan.diagnostics {
      let line = diagnostic.line.map { "line \($0): " } ?? ""
      result.append("\(line)\(diagnostic.message)")
    }
    for entry in plan.entries {
      if let warning = entry.status?.warning {
        result.append("note \(entry.noteIndex) (line \(entry.line)): \(warning)")
      }
      if entry.state == .unknown, let output = entry.output {
        result.append(
          force
            ? "note \(entry.noteIndex) (line \(entry.line)): \(output.path) has no render record (hand-placed?); overwriting it (--force)."
            : "note \(entry.noteIndex) (line \(entry.line)): \(output.path) has no render record (hand-placed?); left as is."
        )
      }
    }
    for entry in plan.foleyEntries {
      if let warning = entry.status?.warning {
        result.append("note \(entry.noteIndex) (line \(entry.line)): \(warning)")
      }
      if entry.state == .unknown, let output = entry.output {
        result.append(
          force
            ? "note \(entry.noteIndex) (line \(entry.line)): \(output.path) has no render record (hand-placed?); overwriting it (--force)."
            : "note \(entry.noteIndex) (line \(entry.line)): \(output.path) has no render record (hand-placed?); left as is."
        )
      }
    }
    return result
  }

  // MARK: - State table

  /// What this run did (or would do) with a take.
  public enum AmbienceRenderOutcome: String, Sendable, Equatable {
    case wouldRender = "would render"
    case rendered
    case failed
  }

  /// The state table: one row per `ambience` or `foley` note, in document
  /// order — note index, kind, screenplay line, render state, action, prompt excerpt and output path (relative to
  /// the plan's output base when inside it).
  ///
  /// Pure: reads only `plan` and `outcomes`, so it is testable without a
  /// model.
  public static func stateTable(
    for plan: AmbiencePlan, outcomes: [Int: AmbienceRenderOutcome] = [:]
  ) -> String {
    let header = ["NOTE", "KIND", "LINE", "STATE", "ACTION", "PROMPT", "OUTPUT"]
    // (noteIndex, row) pairs from both kinds, merged into document order.
    var indexed: [(Int, [String])] = []

    func action(_ noteIndex: Int, _ state: AmbienceRenderState?) -> String {
      if let outcome = outcomes[noteIndex] { return outcome.rawValue }
      return state == .unknown ? "keep" : "-"
    }

    for entry in plan.entries {
      indexed.append(
        (
          entry.noteIndex,
          [
            String(entry.noteIndex),
            "ambience",
            String(entry.line),
            entry.ambience.stop ? "stop" : (entry.state?.rawValue ?? "-"),
            action(entry.noteIndex, entry.state),
            promptExcerpt(entry.ambience.prompt),
            entry.output.map { displayPath($0, base: plan.outputBase) } ?? "-",
          ]
        ))
    }
    for entry in plan.foleyEntries {
      indexed.append(
        (
          entry.noteIndex,
          [
            String(entry.noteIndex),
            "foley",
            String(entry.line),
            entry.state?.rawValue ?? "-",
            action(entry.noteIndex, entry.state),
            promptExcerpt(entry.foley.prompt),
            entry.output.map { displayPath($0, base: plan.outputBase) } ?? "-",
          ]
        ))
    }
    let rows = indexed.sorted { $0.0 < $1.0 }.map(\.1)

    var lines: [String] = []
    lines.append("Screenplay: \(plan.screenplay.path)")
    lines.append("Outputs relative to: \(plan.outputBase.path)")
    if rows.isEmpty {
      lines.append("No ambience or foley notes.")
      return lines.joined(separator: "\n")
    }
    let all = [header] + rows
    let widths = header.indices.map { column in all.map { $0[column].count }.max() ?? 0 }
    for row in all {
      let cells = row.indices.map { column -> String in
        column == row.count - 1
          ? row[column] : row[column].padding(toLength: widths[column], withPad: " ", startingAt: 0)
      }
      lines.append(cells.joined(separator: "  "))
    }
    return lines.joined(separator: "\n")
  }

  /// The first `limit` characters of `prompt` with whitespace runs collapsed,
  /// `…` when truncated, `-` when absent.
  public static func promptExcerpt(_ prompt: String?, limit: Int = 40) -> String {
    guard let prompt else { return "-" }
    let collapsed = prompt.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    guard !collapsed.isEmpty else { return "-" }
    guard collapsed.count > limit else { return collapsed }
    return String(collapsed.prefix(limit - 1)) + "…"
  }

  /// `url`'s path relative to `base` when inside it, else its absolute path.
  static func displayPath(_ url: URL, base: URL) -> String {
    let basePath = base.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
  }

  private static func warn(_ message: String, prefix: String = "warning: ") {
    FileHandle.standardError.write(Data("\(prefix)\(message)\n".utf8))
  }
}
