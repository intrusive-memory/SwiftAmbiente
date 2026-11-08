//
//  StableAudioGenerator.swift
//  SwiftAmbiente
//
//  Sortie 10 (OPERATION PHANTOM FOLEY, WU2): the public `AmbienteGenerator`
//  conformance for Stable Audio 3 Small SFX. Composes the Sortie 6-9
//  `StableAudioPipeline` and honours the same output contract as
//  `ProceduralAmbienteGenerator`: interleaved 16-bit PCM WAV at the
//  `AmbienteConfig` sample rate / channel count.
//

import Foundation

/// Stable Audio 3 Small SFX backend.
///
/// The model weights are loaded lazily on the first ``generate(prompt:settings:)``
/// call and cached for the lifetime of the value (and its copies). Generation is
/// serialized: concurrent calls run one at a time because the MLX pipeline is
/// not reentrant.
public struct StableAudioGenerator: AmbienteGenerator {
  public let generatorId = "stable-audio"
  public let displayName = "Stable Audio 3 Small SFX (MLX)"

  /// Output contract this generator honours. Stable Audio natively renders
  /// 44.1 kHz stereo, so other configurations are rejected.
  public let config: AmbienteConfig

  /// Acervo-resolved model directory (`<models>/stabilityai_stable-audio-3-small-sfx`).
  public let modelDirectory: URL

  private let cache = PipelineCache()

  public init(modelDirectory: URL, config: AmbienteConfig = .default) {
    self.modelDirectory = modelDirectory
    self.config = config
  }

  public func isAvailable() async -> Bool {
    let fm = FileManager.default
    return fm.fileExists(
      atPath: modelDirectory.appendingPathComponent(StableAudioModelConfig.configFileName).path)
      && fm.fileExists(
        atPath: modelDirectory.appendingPathComponent(StableAudioModelAssets.weightsFileName).path)
  }

  /// Single-take limit used until the model is loaded (Stable Audio 3 Small
  /// SFX: `sample_size 5_292_032 / 44_100 Hz` ≈ 120 s).
  public static let defaultMaxDurationSeconds: Double = 120

  /// Longest take one ``generate(prompt:settings:)`` call renders. Derived from
  /// the loaded model's ``StableAudioModelConfig/maxDurationSeconds``; before the
  /// first load it is ``defaultMaxDurationSeconds``.
  public var maxDurationSeconds: Double {
    cache.loadedMaxDurationSeconds ?? Self.defaultMaxDurationSeconds
  }

  public func generate(prompt: String, settings: GenerationSettings) async throws -> Data {
    try validate(settings: settings)

    let modelDirectory = self.modelDirectory
    let config = self.config
    let cache = self.cache
    let data: Data = try await Task.detached(priority: .userInitiated) {
      do {
        return try cache.withPipeline(modelDirectory: modelDirectory) { pipeline in
          pipeline.generateWAV(prompt: prompt, settings: settings, config: config)
        }
      } catch let error as AmbienteError {
        throw error
      } catch {
        throw AmbienteError.generationFailed(
          "Stable Audio pipeline failed: \(error.localizedDescription)")
      }
    }.value

    guard data.count > 44 else {
      throw AmbienteError.generationFailed("encoder produced an empty buffer")
    }
    return data
  }

  /// Validate a request without touching the model. ``generate(prompt:settings:)``
  /// calls this first, so a rejected request never loads or downloads weights.
  func validate(settings: GenerationSettings) throws {
    guard settings.durationSeconds > 0 else {
      throw AmbienteError.invalidDuration(settings.durationSeconds)
    }
    let limit = maxDurationSeconds
    guard settings.durationSeconds <= limit else {
      throw AmbienteError.takeTooLong(seconds: settings.durationSeconds, limit: limit)
    }
    guard StableAudioPipeline.requestedFrames(forSeconds: settings.durationSeconds) > 0 else {
      throw AmbienteError.invalidDuration(settings.durationSeconds)
    }
    guard settings.steps >= 1 else {
      throw AmbienteError.generationFailed("steps must be >= 1 (got \(settings.steps))")
    }
    guard config.sampleRate == StableAudioLatentGenerator.sampleRate,
      config.channelCount == StableAudioSAMESDecoder.audioChannels
    else {
      throw AmbienteError.generationFailed(
        "Stable Audio renders 44.1 kHz stereo; config requests "
          + "\(config.sampleRate) Hz x \(config.channelCount) ch")
    }
  }
}

/// Lazily loads and serializes access to the non-`Sendable` pipeline.
private final class PipelineCache: @unchecked Sendable {
  private let lock = NSLock()
  private var pipeline: StableAudioPipeline?

  /// Guards `maxDurationSeconds` separately so reading the limit never waits
  /// on a generation holding `lock`.
  private let limitLock = NSLock()
  private var maxDurationSeconds: Double?

  /// The loaded model's single-take limit, or `nil` before the first load.
  var loadedMaxDurationSeconds: Double? {
    limitLock.lock()
    defer { limitLock.unlock() }
    return maxDurationSeconds
  }

  func withPipeline<R>(
    modelDirectory: URL, _ body: (StableAudioPipeline) throws -> R
  ) throws -> R {
    lock.lock()
    defer { lock.unlock() }
    if pipeline == nil {
      let loaded = try StableAudioPipeline.load(fromModelDirectory: modelDirectory)
      pipeline = loaded
      let limit = loaded.latentGenerator.config.maxDurationSeconds
      limitLock.lock()
      maxDurationSeconds = limit
      limitLock.unlock()
    }
    return try body(pipeline!)
  }
}
