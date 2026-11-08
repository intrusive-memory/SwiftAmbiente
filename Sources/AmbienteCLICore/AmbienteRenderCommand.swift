//
//  AmbienteRenderCommand.swift
//  AmbienteCLICore
//
//  `ambiente render <screenplay>` — plan a screenplay's GLOSA `ambience` notes
//  with `AmbiencePlanner` (output resolution, render state, seed/output
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
    abstract: "Render the ambience beds of a screenplay's GLOSA `ambience` notes.",
    discussion: """
      Plans every `ambience` note in the screenplay: resolves its `output`
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
  /// A dry run never resolves a generator, so it loads no model.
  ///
  /// - Returns: The number of takes that failed to render.
  @discardableResult
  public func execute(emit: (String) -> Void) async throws -> Int {
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
    let selected = Self.entriesToRender(in: plan, force: force)

    if dryRun {
      for entry in selected { outcomes[entry.noteIndex] = .wouldRender }
    } else if !selected.isEmpty {
      // The note's `model` picks the backend, loaded (downloaded on first use)
      // through the model manager. Unlike `AmbienteEngine.resolveGenerator`,
      // there is no procedural fallback: a fallback take would get a render
      // record matching the note's digest and read as `current`, so the real
      // model would never replace it.
      let manager = AmbienteModelManager()
      var generators: [StableAudioModelRepo: Result<any AmbienteGenerator, any Error>] = [:]
      for entry in selected {
        guard let output = entry.output else { continue }
        do {
          let repo = try AmbienceModel.resolve(entry.ambience.effectiveModel).modelRepo
          if generators[repo] == nil {
            FileHandle.standardError.write(Data("loading model \(repo.rawValue)\n".utf8))
            do {
              generators[repo] = .success(try await manager.loadGenerator(repo))
            } catch {
              generators[repo] = .failure(error)
            }
          }
          let generator = try generators[repo]!.get()
          FileHandle.standardError.write(
            Data("rendering note \(entry.noteIndex) (line \(entry.line)) → \(output.path)\n".utf8))
          _ = try await generator.render(ambience: entry.ambience, to: output)
          outcomes[entry.noteIndex] = .rendered
        } catch {
          failures += 1
          outcomes[entry.noteIndex] = .failed
          Self.warn(
            "note \(entry.noteIndex) (line \(entry.line)): render failed: \(error.localizedDescription)",
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
    return result
  }

  // MARK: - State table

  /// What this run did (or would do) with a take.
  public enum AmbienceRenderOutcome: String, Sendable, Equatable {
    case wouldRender = "would render"
    case rendered
    case failed
  }

  /// The state table: one row per `ambience` note — note index, screenplay
  /// line, render state, action, prompt excerpt and output path (relative to
  /// the plan's output base when inside it).
  ///
  /// Pure: reads only `plan` and `outcomes`, so it is testable without a
  /// model.
  public static func stateTable(
    for plan: AmbiencePlan, outcomes: [Int: AmbienceRenderOutcome] = [:]
  ) -> String {
    let header = ["NOTE", "LINE", "STATE", "ACTION", "PROMPT", "OUTPUT"]
    var rows: [[String]] = []
    for entry in plan.entries {
      let state: String
      if entry.ambience.stop {
        state = "stop"
      } else {
        state = entry.state?.rawValue ?? "-"
      }
      let action: String
      if let outcome = outcomes[entry.noteIndex] {
        action = outcome.rawValue
      } else if entry.state == .unknown {
        action = "keep"
      } else {
        action = "-"
      }
      rows.append([
        String(entry.noteIndex),
        String(entry.line),
        state,
        action,
        promptExcerpt(entry.ambience.prompt),
        entry.output.map { displayPath($0, base: plan.outputBase) } ?? "-",
      ])
    }

    var lines: [String] = []
    lines.append("Screenplay: \(plan.screenplay.path)")
    lines.append("Outputs relative to: \(plan.outputBase.path)")
    if plan.entries.isEmpty {
      lines.append("No ambience notes.")
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
