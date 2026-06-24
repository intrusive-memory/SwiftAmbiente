//
//  StableAudioModelRepo.swift
//  SwiftAmbiente
//
//  Catalogue of Stable Audio generation models targeted by SwiftAmbiente.
//

import Foundation

/// Stable Audio model variants SwiftAmbiente generates against.
///
/// These are the real upstream repositories the MLX backend will load once the
/// port lands (see `REQUIREMENTS-stable-audio-integration.md`). The SFX variant
/// is the foley / atmospheric model; the music variant is included for parity
/// but is out of scope for background beds.
///
/// > Licensing: the weights are governed by the **Stability AI Community
/// > License** (free commercial use under US$1M annual revenue, with attribution
/// > and registration), *and* the bundled T5Gemma text encoder is governed by
/// > **Google's Gemma Terms of Use**. Both must be cleared before commercial
/// > distribution. See the README "Licensing" section.
public enum StableAudioModelRepo: String, CaseIterable, Sendable {
  /// Stable Audio 3 Small — sound-effects / foley variant. The atmospheric model.
  case smallSFX = "stabilityai/stable-audio-open-small-sfx"

  /// Stable Audio 3 Small — music variant. Out of scope for background beds.
  case smallMusic = "stabilityai/stable-audio-open-small-music"

  /// Short slug used by the CLI `--model` flag.
  public var slug: String {
    switch self {
    case .smallSFX: return "sfx"
    case .smallMusic: return "music"
    }
  }

  /// Resolve a model from a CLI slug (`sfx` / `music`).
  public init?(slug: String) {
    switch slug.lowercased() {
    case "sfx", "small-sfx": self = .smallSFX
    case "music", "small-music": self = .smallMusic
    default: return nil
    }
  }

  /// The slugs accepted by the `--model` flag.
  public static var supportedSlugs: [String] { allCases.map(\.slug) }
}
