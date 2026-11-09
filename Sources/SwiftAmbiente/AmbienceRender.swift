//
//  AmbienceRender.swift
//  SwiftAmbiente
//
//  Renders a GLOSA `ambience` note to a take WAV plus its render record, and
//  reports whether an existing take is current (Produciesta
//  REQUIREMENTS-ambience §§ 3.1, 4.2, 4.3).
//

import Foundation
import GlosaCore

// MARK: - Settings mapping

extension GenerationSettings {
  /// The generation settings an `ambience` note asks for.
  ///
  /// `take` (or `Ambience.defaultTake`) → `durationSeconds`; `seed` → `seed`
  /// (`nil` keeps ``GenerationSettings/defaultSeed``); `steps` and `cfg` →
  /// `steps` / `cfgScale`, falling back to the ``GenerationSettings/default``
  /// values when not written.
  public init(ambience: GlosaCore.Ambience) {
    let defaults = GenerationSettings.default
    self.init(
      durationSeconds: ambience.effectiveTake,
      steps: ambience.steps ?? defaults.steps,
      cfgScale: ambience.cfg ?? defaults.cfgScale,
      seed: ambience.seed.map { UInt64($0) }
    )
  }
}

// MARK: - Render

extension AmbienteGenerator {
  /// Renders an `ambience` note to `output` and writes its render record to
  /// `<output>.json` (``AmbienceRendering/recordURL(for:)``).
  ///
  /// The take is written to a temporary file beside `output` and renamed into
  /// place; only then is the record written the same way. A failure at any
  /// point leaves any previous take and record untouched (a stale record keeps
  /// reading as ``AmbienceRenderState/changed``). Missing parent directories
  /// are created.
  ///
  /// The note's `model` (or `Ambience.defaultModel`) must name a known
  /// ``AmbienceModel``; it is validated before anything is generated. Which
  /// backend actually renders is this generator — the record's `generator` is
  /// its ``generatorId``.
  ///
  /// - Parameters:
  ///   - ambience: The note. Must not be a `stop` note and must have a prompt.
  ///   - output: The take WAV's file URL (already resolved by the caller).
  /// - Returns: The record written beside the take.
  /// - Throws: ``AmbienteError/unknownAmbienceModel(_:)``,
  ///   ``AmbienteError/invalidAmbience(_:)``, any generator error, or a file
  ///   system error.
  public func render(ambience: GlosaCore.Ambience, to output: URL) async throws -> RenderRecord {
    try await render(
      ambience: ambience, to: output, renderedAt: Date(), write: AtomicFileWriter.write)
  }

  /// ``render(ambience:to:)`` with the clock and the file writer injected
  /// (tests observe write order through `write`).
  func render(
    ambience: GlosaCore.Ambience,
    to output: URL,
    renderedAt: Date,
    write: (Data, URL) throws -> Void
  ) async throws -> RenderRecord {
    guard output.isFileURL else {
      throw AmbienteError.invalidAmbience("output \(output) is not a file URL")
    }
    guard !ambience.stop else {
      throw AmbienteError.invalidAmbience("a stop note has nothing to render")
    }
    guard let prompt = ambience.prompt,
      !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw AmbienteError.invalidAmbience("the note has no prompt")
    }
    _ = try AmbienceModel.resolve(ambience.effectiveModel)

    let settings = GenerationSettings(ambience: ambience)
    let wav = try await generate(prompt: prompt, settings: settings)

    var effective = ambience
    effective.documentIndex = 0
    effective.take = settings.durationSeconds
    effective.steps = settings.steps
    effective.cfg = settings.cfgScale
    effective.model = ambience.effectiveModel

    let record = RenderRecord(
      ambience: effective,
      digest: ambience.renderDigest,
      generator: generatorId,
      swiftAmbiente: SwiftAmbiente.version,
      rendered: renderedAt
    )
    let recordData = try record.jsonData()

    try write(wav, output)
    try write(recordData, AmbienceRendering.recordURL(for: output))
    return record
  }
}

// MARK: - Render state

/// Whether a note's take on disk is up to date (REQUIREMENTS-ambience § 3.1).
public enum AmbienceRenderState: String, Sendable, Equatable, CaseIterable {
  /// The WAV exists and its record's digest equals the note's digest: mix it.
  case current
  /// The WAV exists and its record's digest differs, or the record cannot be
  /// read: regenerate.
  case changed
  /// There is no WAV: generate.
  case notRendered
  /// The WAV exists with no record (a hand-placed file): mix as-is, warn.
  case unknown
}

/// A render state plus what was found on disk.
public struct AmbienceRenderStatus: Sendable, Equatable {
  public var state: AmbienceRenderState
  /// The record beside the take, when one was read.
  public var record: RenderRecord?
  /// Set when the record exists but cannot be parsed (state is `changed`).
  public var warning: String?

  public init(state: AmbienceRenderState, record: RenderRecord? = nil, warning: String? = nil) {
    self.state = state
    self.record = record
    self.warning = warning
  }
}

/// Render-record location and render-state checks for `ambience` notes.
public enum AmbienceRendering {
  /// The render record beside a take: `<output>.json` (`amb-1a2b.wav` →
  /// `amb-1a2b.wav.json`).
  public static func recordURL(for output: URL) -> URL {
    output.appendingPathExtension("json")
  }

  /// The render state of `ambience` whose take lives at `output`.
  public static func renderState(
    for ambience: GlosaCore.Ambience, output: URL
  ) -> AmbienceRenderState {
    renderStatus(for: ambience, output: output).state
  }

  /// The render state plus the record read and any warning.
  ///
  /// | State | Condition |
  /// |---|---|
  /// | `notRendered` | no WAV at `output` |
  /// | `unknown` | WAV, no record |
  /// | `changed` | WAV, record digest ≠ note digest, or the record was written for a `foley` note — or the record cannot be parsed (with `warning`) |
  /// | `current` | WAV, `ambience` record whose digest == note digest |
  public static func renderStatus(
    for ambience: GlosaCore.Ambience, output: URL
  ) -> AmbienceRenderStatus {
    renderStatus(output: output, digest: ambience.renderDigest, directiveKey: "ambience")
  }

  /// The shared state machine: `directiveKey` is the directive the caller's
  /// note is (`"ambience"` / `"foley"`); a record naming another directive is
  /// `changed` even when the digests match.
  static func renderStatus(
    output: URL, digest: String, directiveKey: String
  ) -> AmbienceRenderStatus {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: output.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      return AmbienceRenderStatus(state: .notRendered)
    }

    let recordFile = recordURL(for: output)
    guard fileManager.fileExists(atPath: recordFile.path) else {
      return AmbienceRenderStatus(state: .unknown)
    }

    let record: RenderRecord
    do {
      record = try RenderRecord(jsonData: try Data(contentsOf: recordFile))
    } catch {
      return AmbienceRenderStatus(
        state: .changed,
        warning:
          "Render record \(recordFile.lastPathComponent) could not be read (\(error.localizedDescription)); the take will be regenerated."
      )
    }

    let current = record.directive.key == directiveKey && record.digest == digest
    return AmbienceRenderStatus(state: current ? .current : .changed, record: record)
  }
}

// MARK: - Atomic file writes

/// Writes a file through a temporary sibling and a `rename(2)`, so readers see
/// either the old file or the complete new one.
enum AtomicFileWriter {
  static func write(_ data: Data, to destination: URL) throws {
    let directory = destination.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent(
      ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
    do {
      try data.write(to: temporary)
      guard rename(temporary.path, destination.path) == 0 else {
        let reason = String(cString: strerror(errno))
        throw AmbienteError.audioExportFailed(
          "could not move \(temporary.lastPathComponent) to \(destination.path): \(reason)")
      }
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      throw error
    }
  }
}
