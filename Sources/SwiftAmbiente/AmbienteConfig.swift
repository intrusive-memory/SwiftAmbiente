//
//  AmbienteConfig.swift
//  SwiftAmbiente
//
//  Configuration for SwiftAmbiente's atmospheric-bed generation pipeline.
//

import Foundation

/// Output audio format for rendered ambient beds.
public enum AudioOutputFormat: String, Codable, Sendable {
  case wav
  case aiff
  case caf
}

/// Configuration controlling SwiftAmbiente's model selection and output format.
///
/// The default targets Stable Audio 3 Small SFX (the foley / sound-effects
/// variant), which generates 44.1 kHz stereo audio. Until the MLX Stable Audio
/// backend is wired in (see `REQUIREMENTS-stable-audio-integration.md`), the
/// shipping generator is ``ProceduralAmbienteGenerator``, which honours the same
/// sample-rate / channel-count contract.
public struct AmbienteConfig: Codable, Sendable {
  /// HuggingFace repo ID for the generation model (Stable Audio 3 Small SFX).
  public let generatorModel: String

  /// Output sample rate in Hz. Stable Audio renders at 44.1 kHz.
  public let sampleRate: Int

  /// Number of output channels. Atmospheric beds are stereo by default.
  public let channelCount: Int

  /// Audio output format for rendered beds.
  public let outputFormat: AudioOutputFormat

  public init(
    generatorModel: String,
    sampleRate: Int,
    channelCount: Int,
    outputFormat: AudioOutputFormat
  ) {
    self.generatorModel = generatorModel
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.outputFormat = outputFormat
  }

  /// Default configuration: Stable Audio 3 Small SFX, 44.1 kHz stereo WAV.
  public static let `default` = AmbienteConfig(
    generatorModel: StableAudioModelRepo.smallSFX.rawValue,
    sampleRate: 44_100,
    channelCount: 2,
    outputFormat: .wav
  )
}
