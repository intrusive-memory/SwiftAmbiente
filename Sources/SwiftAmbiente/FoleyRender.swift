//
//  FoleyRender.swift
//  SwiftAmbiente
//
//  Renders a GLOSA `foley` note to a one-shot take WAV plus its render record,
//  and reports whether an existing take is current (Produciesta
//  REQUIREMENTS-foley §§ 3.1, 4.1, 4.2).
//

import Foundation
import GlosaCore

// MARK: - Settings mapping

extension GenerationSettings {
  /// The generation settings a `foley` note asks for.
  ///
  /// `take` (or `Foley.defaultTake`) → `durationSeconds`; `seed` → `seed`
  /// (`nil` keeps ``GenerationSettings/defaultSeed``); `steps` and `cfg` →
  /// `steps` / `cfgScale`, falling back to the ``GenerationSettings/default``
  /// values when not written.
  public init(foley: GlosaCore.Foley) {
    let defaults = GenerationSettings.default
    self.init(
      durationSeconds: foley.effectiveTake,
      steps: foley.steps ?? defaults.steps,
      cfgScale: foley.cfg ?? defaults.cfgScale,
      seed: foley.seed.map { UInt64($0) }
    )
  }
}

// MARK: - Render

extension AmbienteGenerator {
  /// Renders a `foley` note to `output` and writes its render record (a
  /// `{"foley": …}` record) to `<output>.json`
  /// (``AmbienceRendering/recordURL(for:)``).
  ///
  /// Same contract as ``render(ambience:to:)``: the take is written to a
  /// temporary file beside `output` and renamed into place, and only then is
  /// the record written the same way. A failure at any point leaves any
  /// previous take and record untouched. Missing parent directories are
  /// created.
  ///
  /// The note's `model` (or `Foley.defaultModel`) must name a known
  /// ``AmbienceModel``; it is validated before anything is generated. The
  /// single-take limit of the generator applies unchanged.
  ///
  /// - Parameters:
  ///   - foley: The note. Must have a prompt.
  ///   - output: The take WAV's file URL (already resolved by the caller).
  /// - Returns: The record written beside the take.
  /// - Throws: ``AmbienteError/unknownAmbienceModel(_:)``,
  ///   ``AmbienteError/invalidAmbience(_:)`` (no prompt, or `output` is not a
  ///   file URL), any generator error, or a file system error.
  public func render(foley: GlosaCore.Foley, to output: URL) async throws -> RenderRecord {
    try await render(
      foley: foley, to: output, renderedAt: Date(), write: AtomicFileWriter.write)
  }

  /// ``render(foley:to:)`` with the clock and the file writer injected (tests
  /// observe write order through `write`).
  func render(
    foley: GlosaCore.Foley,
    to output: URL,
    renderedAt: Date,
    write: (Data, URL) throws -> Void
  ) async throws -> RenderRecord {
    guard output.isFileURL else {
      throw AmbienteError.invalidAmbience("foley output \(output) is not a file URL")
    }
    guard let prompt = foley.prompt,
      !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw AmbienteError.invalidAmbience("the foley note has no prompt")
    }
    _ = try AmbienceModel.resolve(foley.effectiveModel)

    let settings = GenerationSettings(foley: foley)
    let wav = try await generate(prompt: prompt, settings: settings)

    var effective = foley
    effective.documentIndex = 0
    effective.take = settings.durationSeconds
    effective.steps = settings.steps
    effective.cfg = settings.cfgScale
    effective.model = foley.effectiveModel

    let record = RenderRecord(
      foley: effective,
      digest: foley.renderDigest,
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

extension AmbienceRendering {
  /// The render state of `foley` whose take lives at `output`.
  public static func renderState(
    for foley: GlosaCore.Foley, output: URL
  ) -> AmbienceRenderState {
    renderStatus(for: foley, output: output).state
  }

  /// The render state plus the record read and any warning
  /// (REQUIREMENTS-foley § 3.1).
  ///
  /// | State | Condition |
  /// |---|---|
  /// | `notRendered` | no WAV at `output` |
  /// | `unknown` | WAV, no record |
  /// | `changed` | WAV, record digest ≠ note digest, or the record was written for an `ambience` note — or the record cannot be parsed (with `warning`) |
  /// | `current` | WAV, `foley` record whose digest == note digest |
  public static func renderStatus(
    for foley: GlosaCore.Foley, output: URL
  ) -> AmbienceRenderStatus {
    renderStatus(output: output, digest: foley.renderDigest, directiveKey: "foley")
  }
}
