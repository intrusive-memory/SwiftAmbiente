//
//  StableAudioModelRepo.swift
//  SwiftAmbiente
//
//  Catalogue of Stable Audio generation models targeted by SwiftAmbiente.
//

import Foundation
import SwiftAcervo

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

// MARK: - Acervo Component Registration

extension StableAudioModelRepo {
  /// The Acervo component ID for this model variant.
  ///
  /// Equal to `Acervo.slugify(rawValue)`, which is also the CDN slug under
  /// which the model's manifest is served. Keeping component ID ==
  /// slugified repo ID == CDN slug eliminates triple-naming, mirroring the
  /// `Qwen3TTSModelRepo.componentId` convention in SwiftVoxAlta.
  public var componentId: String {
    Acervo.slugify(rawValue)
  }
}

/// Bare component descriptors for the SFX and music Stable Audio variants.
///
/// No `files:` or `estimatedSizeBytes:` declared — SwiftAcervo auto-hydrates
/// each one from the CDN manifest on first call to `ensureComponentReady`, so
/// the file list and total size are always whatever the published manifest
/// says, never a stale local mirror. `minimumMemoryBytes` is a conservative
/// estimate for the 0.6B-parameter Small variant; refine once real manifests
/// are published (WU3).
let stableAudioComponentDescriptors: [ComponentDescriptor] = [
  ComponentDescriptor(
    id: StableAudioModelRepo.smallSFX.componentId,
    type: .backbone,
    displayName: "Stable Audio 3 Small — SFX",
    repoId: StableAudioModelRepo.smallSFX.rawValue,
    minimumMemoryBytes: 1_500_000_000
  ),
  ComponentDescriptor(
    id: StableAudioModelRepo.smallMusic.componentId,
    type: .backbone,
    displayName: "Stable Audio 3 Small — Music",
    repoId: StableAudioModelRepo.smallMusic.rawValue,
    minimumMemoryBytes: 1_500_000_000
  ),
]

/// Module-level registration trigger.
///
/// Evaluated once (lazily) on first access, registering both Stable Audio
/// component descriptors with the SwiftAcervo Component Registry.
/// `AmbienteModelManager.init()` references this to ensure registration
/// happens before any model loading or download call.
let registerStableAudioComponents: Void = {
  Acervo.register(stableAudioComponentDescriptors)
}()
