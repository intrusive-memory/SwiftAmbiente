//
//  AmbienceModel.swift
//  SwiftAmbiente
//
//  Maps the `model` id written in a GLOSA `ambience` note onto a SwiftAmbiente
//  backend. GlosaCore stores `model` as a raw string so the notation stays
//  decoupled from the generator's vocabulary; this is where the vocabulary
//  lives.
//

import Foundation

/// A generator a GLOSA `ambience` note can name in its `model` key.
///
/// The raw value is the id as written in the note
/// (`GlosaCore.Ambience.defaultModel` is `stable-audio-3-small-sfx`).
public enum AmbienceModel: String, CaseIterable, Sendable {
  /// Stable Audio 3 Small SFX — the foley / atmospheric backend.
  case stableAudio3SmallSFX = "stable-audio-3-small-sfx"

  /// The Stable Audio repository this id generates against.
  public var modelRepo: StableAudioModelRepo {
    switch self {
    case .stableAudio3SmallSFX: return .smallSFX
    }
  }

  /// Resolves a note's `model` id.
  ///
  /// - Throws: ``AmbienteError/unknownAmbienceModel(_:)`` when no backend has
  ///   that id. The id is matched exactly (case-sensitive), as written.
  public static func resolve(_ id: String) throws -> AmbienceModel {
    guard let model = AmbienceModel(rawValue: id) else {
      throw AmbienteError.unknownAmbienceModel(id)
    }
    return model
  }
}
