//
//  AmbienteRootCommand.swift
//  AmbienteCLICore
//
//  `ambiente` — the root command. `generate` (``AmbienteCommand``) is the
//  default subcommand, so `ambiente "<prompt>"` and every flag it took before
//  subcommands existed keep working; `render` (``AmbienteRenderCommand``)
//  renders a screenplay's `ambience` notes.
//

import ArgumentParser
import Foundation

public struct AmbienteRootCommand: AsyncParsableCommand {
  public init() {}

  public static let configuration = CommandConfiguration(
    commandName: "ambiente",
    abstract: "Generate atmospheric / foley background beds for your scene.",
    discussion: """
      `ambiente "<prompt>"` (or `--scene <name>`) generates one bed — the
      `generate` subcommand, which runs when no subcommand is named.
      `ambiente render <screenplay>` renders the screenplay's GLOSA `ambience`
      notes. Override the model CDN with ACERVO_CDN_BASE_URL.
      """,
    version: "ambiente \(AmbienteCLIVersion.current)",
    subcommands: [AmbienteCommand.self, AmbienteRenderCommand.self],
    defaultSubcommand: AmbienteCommand.self
  )

  /// Entry point that selects the async `main(_:)` overload when called from
  /// top-level `main.swift` code (see ``AmbienteCommand/runAsMain()``).
  public static func runAsMain() async {
    await Self.main(nil)
  }
}
