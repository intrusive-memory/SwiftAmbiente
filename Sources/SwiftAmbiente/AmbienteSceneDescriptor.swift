//
//  AmbienteSceneDescriptor.swift
//  SwiftAmbiente
//
//  Built-in atmosphere presets — named scenes that expand to generation prompts.
//  Analogous to SwiftVoxAlta's preset speakers: a curated starting set so callers
//  don't have to hand-write prompts for common beds.
//

import Foundation

/// A named atmosphere preset that expands to a generation prompt.
public struct AmbienteSceneDescriptor: Codable, Sendable, Identifiable {
  /// Stable scene identifier (e.g. `"rain"`), used by `--scene`.
  public let id: String

  /// Human-readable name.
  public let name: String

  /// The text prompt this scene expands to for the generator backend.
  public let prompt: String

  public init(id: String, name: String, prompt: String) {
    self.id = id
    self.name = name
    self.prompt = prompt
  }
}

extension AmbienteSceneDescriptor {
  /// The built-in preset scenes shipped with SwiftAmbiente.
  public static let presets: [AmbienteSceneDescriptor] = [
    .init(
      id: "room-tone", name: "Room Tone",
      prompt: "quiet interior room tone, subtle air handling, no music, steady background bed"),
    .init(
      id: "rain", name: "Rain",
      prompt: "steady rain on a window, occasional distant thunder, soft and atmospheric"),
    .init(
      id: "forest", name: "Forest",
      prompt: "dense forest ambience, wind through leaves, distant birdsong, gentle and continuous"),
    .init(
      id: "city", name: "City Street",
      prompt: "distant city traffic hum, faint passing cars, muffled urban background"),
    .init(
      id: "ocean", name: "Ocean",
      prompt: "ocean waves on a shoreline, slow swell, distant gulls, calm and wide"),
    .init(
      id: "cafe", name: "Café",
      prompt: "quiet café murmur, indistinct chatter, faint clinking, warm interior ambience"),
    .init(
      id: "night", name: "Night",
      prompt: "calm night ambience, crickets, faint breeze, sparse and atmospheric"),
  ]

  /// Look up a preset scene by its identifier.
  public static func preset(id: String) -> AmbienteSceneDescriptor? {
    presets.first { $0.id == id.lowercased() }
  }
}
