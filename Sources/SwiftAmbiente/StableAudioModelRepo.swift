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
/// is the foley / atmospheric model — the only variant in scope for background
/// beds.
///
/// > No Stable Audio 3 music-variant repo is currently published upstream (the
/// > scaffold's `stable-audio-open-small-music` predates the SA3 family and does
/// > not resolve to a real SA3 release). Per EXECUTION_PLAN.md Sortie 11, the
/// > music/parity case is dropped as out of scope rather than pointed at a
/// > nonexistent or unverified repo id. Re-add it if/when Stability publishes a
/// > verified SA3 music repo.
///
/// > Licensing: the weights are governed by the **Stability AI Community
/// > License** (free commercial use under US$1M annual revenue, with attribution
/// > and registration), *and* the bundled T5Gemma text encoder is governed by
/// > **Google's Gemma Terms of Use**. Both must be cleared before commercial
/// > distribution. See the README "Licensing" section.
public enum StableAudioModelRepo: String, CaseIterable, Sendable {
  /// Stable Audio 3 Small — sound-effects / foley variant. The atmospheric model.
  case smallSFX = "stabilityai/stable-audio-3-small-sfx"

  /// Short slug used by the CLI `--model` flag.
  public var slug: String {
    switch self {
    case .smallSFX: return "sfx"
    }
  }

  /// Resolve a model from a CLI slug (`sfx`).
  public init?(slug: String) {
    switch slug.lowercased() {
    case "sfx", "small-sfx": self = .smallSFX
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

/// Bare component descriptor for the SFX Stable Audio variant.
///
/// No `files:` or `estimatedSizeBytes:` declared — SwiftAcervo auto-hydrates
/// it from the CDN manifest on first call to `ensureComponentReady`, so the
/// file list and total size are always whatever the published manifest says,
/// never a stale local mirror. `minimumMemoryBytes` is a conservative estimate
/// for the 0.6B-parameter Small variant; refine once real manifests are
/// published (WU3).
let stableAudioComponentDescriptors: [ComponentDescriptor] = [
  ComponentDescriptor(
    id: StableAudioModelRepo.smallSFX.componentId,
    type: .backbone,
    displayName: "Stable Audio 3 Small — SFX",
    repoId: StableAudioModelRepo.smallSFX.rawValue,
    minimumMemoryBytes: 1_500_000_000
  )
]

/// Module-level registration trigger.
///
/// Evaluated once (lazily) on first access, registering the Stable Audio
/// component descriptor(s) with the SwiftAcervo Component Registry.
/// `AmbienteModelManager.init()` references this to ensure registration
/// happens before any model loading or download call.
let registerStableAudioComponents: Void = {
  Acervo.register(stableAudioComponentDescriptors)
}()
