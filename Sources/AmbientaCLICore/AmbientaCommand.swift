//
//  AmbientaCommand.swift
//  AmbientaCLICore
//
//  `ambienta` — generate an atmospheric / foley background bed from a text
//  prompt or a built-in scene preset.
//

import ArgumentParser
import Foundation
import SwiftAmbiente

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct AmbientaCommand: AsyncParsableCommand {
  public init() {}

  public static let configuration = CommandConfiguration(
    commandName: "ambienta",
    abstract: "Generate atmospheric / foley background beds for your scene.",
    discussion: """
      Renders a background audio bed from a free-form prompt or a built-in scene
      preset. The shipping engine is a procedural (filtered-noise) generator; the
      neural Stable Audio backend is staged (see REQUIREMENTS-stable-audio-integration.md).
      """,
    version: "ambienta \(AmbientaVersion.current)"
  )

  // MARK: - Scene / Prompt

  @Option(name: .long, help: "Use a built-in scene preset (e.g. rain, forest, city).")
  public var scene: String?

  @Flag(name: .long, help: "List the built-in scene presets and exit.")
  public var listScenes: Bool = false

  // MARK: - Generation Settings

  @Option(
    name: [.customShort("d"), .long],
    help: "Length of the generated bed, in seconds.")
  public var duration: Double = 30.0

  @Option(name: .long, help: "Deterministic seed for reproducible output.")
  public var seed: UInt64?

  @Option(
    name: .long,
    help: "Preferred Stable Audio variant when installed: 'sfx' or 'music'. Default: sfx.")
  public var model: String?

  // MARK: - Output

  @Option(
    name: [.customShort("o"), .long],
    help: "Write the bed to this file path. Defaults to ./ambiente.wav.")
  public var output: String?

  // MARK: - Positional

  @Argument(help: "Free-form atmosphere prompt (ignored when --scene is given).")
  public var promptWords: [String] = []

  // MARK: - Run

  public mutating func run() async throws {
    if listScenes {
      runListScenes()
      return
    }

    if duration <= 0 {
      throw ValidationError("--duration must be greater than 0.")
    }

    let repo = try resolveModel()
    let prompt = try resolvePrompt()

    Self.applyDefaultCDNBaseURL()
    let engine = AmbienteEngine()
    let generator = await engine.resolveGenerator(model: repo)
    FileHandle.standardError.write(Data("generator: \(generator.generatorId)\n".utf8))
    let wavData = try await generator.generate(
      prompt: prompt,
      settings: GenerationSettings(durationSeconds: duration, seed: seed)
    )

    let outputPath = output ?? "./ambiente.wav"
    let format = AudioFileWriter.inferFormat(fromPath: outputPath)
    try AudioFileWriter.write(wavData: wavData, to: outputPath, format: format)

    let bytes = wavData.count
    FileHandle.standardError.write(
      Data(
        "Wrote \(String(format: "%.1f", duration))s bed (\(bytes) bytes) to \(outputPath)\n".utf8))
  }

  // MARK: - CDN Configuration

  /// Default model CDN for the CLI. SwiftAcervo has no built-in default (it
  /// `fatalError`s when unset), so the consuming executable supplies one. An
  /// explicitly set `ACERVO_CDN_BASE_URL` always wins (`overwrite = 0`).
  static let defaultCDNBaseURL = "https://cdn.intrusive-memory.productions/models"

  static func applyDefaultCDNBaseURL() {
    setenv("ACERVO_CDN_BASE_URL", defaultCDNBaseURL, 0)
  }

  // MARK: - Resolution Helpers

  /// Resolve the `--model` flag to a Stable Audio variant (default `.smallSFX`).
  private func resolveModel() throws -> StableAudioModelRepo {
    guard let model else { return .smallSFX }
    guard let repo = StableAudioModelRepo(slug: model) else {
      let slugs = StableAudioModelRepo.supportedSlugs.joined(separator: "', '")
      throw ValidationError("Invalid model: '\(model)'. Use '\(slugs)'.")
    }
    return repo
  }

  /// Resolve the generation prompt from `--scene` or positional words.
  private func resolvePrompt() throws -> String {
    if let scene {
      guard let descriptor = AmbienteSceneDescriptor.preset(id: scene) else {
        throw AmbienteError.unsupportedScene(scene)
      }
      return descriptor.prompt
    }
    let joined = promptWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !joined.isEmpty else {
      throw ValidationError(
        "Provide an atmosphere prompt, or pass --scene <name> (see --list-scenes).")
    }
    return joined
  }

  // MARK: - --list-scenes

  private func runListScenes() {
    print("Built-in scenes:")
    for scene in AmbienteSceneDescriptor.presets {
      print("  \(scene.id)\t\(scene.name) — \(scene.prompt)")
    }
  }

  // MARK: - Async Entry Point

  /// Availability-annotated entry point so the async `main()` overload is
  /// selected when called from top-level `main.swift` code. Mirrors the pattern
  /// documented in SwiftVoxAlta's `DigaCommand.runAsMain()`.
  public static func runAsMain() async {
    await Self.main(nil)
  }
}
