//
//  StableAudioModelConfig.swift
//  SwiftAmbiente
//
//  Sortie 6 (OPERATION PHANTOM FOLEY, WU2): Codable parse of the Stable Audio 3
//  Small SFX model configuration.
//
//  IMPORTANT: the upstream config file is named `model_config.json` — NOT the
//  conventional `config.json`. See `configFileName`. The `t5gemma-b-b-ul2/`
//  subfolder carries its own `config.json` for the text encoder; that is S7's
//  territory and is deliberately not parsed here.
//
//  This sortie parses config only (plus asset/weight loading in
//  StableAudioAssetLoader.swift). No encoder / sampler / decoder forward passes
//  live here — those are Sorties 7–9.
//

import Foundation

/// Parsed representation of a Stable Audio 3 model's `model_config.json`.
///
/// Only the fields the WU2 pipeline needs are strongly typed (sample rate,
/// channels, latent/io channels, and the DiT hyperparameters). The remaining
/// blocks (`training`, optimizer/discriminator configs, demo prompts, …) are
/// intentionally left undecoded — `Codable` ignores unknown keys, so the config
/// parses even as upstream adds fields.
public struct StableAudioModelConfig: Codable, Sendable, Equatable {
  /// The on-disk configuration file name for a Stable Audio 3 model.
  ///
  /// Deliberately `model_config.json`, not `config.json`: the Stable Audio 3
  /// family stores its top-level model config under this non-standard name,
  /// while `config.json` inside `t5gemma-b-b-ul2/` belongs to the text encoder.
  public static let configFileName = "model_config.json"

  /// e.g. `"diffusion_cond_inpaint"`.
  public let modelType: String

  /// Total latent sample size the model was trained against (raw, unused by
  /// config parsing beyond exposure).
  public let sampleSize: Int

  /// Output sample rate in Hz. `44100` for the SFX variant.
  public let sampleRate: Int

  /// Number of audio channels. `2` (stereo) for the SFX variant.
  public let audioChannels: Int

  /// The nested `model` block: pretransform (autoencoder), conditioning, and
  /// the DiT diffusion configuration.
  public let model: ModelBlock

  private enum CodingKeys: String, CodingKey {
    case modelType = "model_type"
    case sampleSize = "sample_size"
    case sampleRate = "sample_rate"
    case audioChannels = "audio_channels"
    case model
  }

  // MARK: - Convenience accessors

  /// The DiT latent / IO channel count (`model.io_channels`, 256 for SFX).
  public var ioChannels: Int { model.ioChannels }

  /// The autoencoder latent dimension (`pretransform.config.latent_dim`).
  public var latentDim: Int { model.pretransform.config.latentDim }

  /// The autoencoder downsampling ratio (`pretransform.config.downsampling_ratio`).
  public var downsamplingRatio: Int { model.pretransform.config.downsamplingRatio }

  /// The DiT hyperparameters (embed dim, depth, heads, conditioning dims).
  public var diffusion: DiffusionConfig { model.diffusion.config }

  /// Longest take the model renders in one pass: `sampleSize / sampleRate`
  /// (≈ 120 s for the SFX variant). Falls back to
  /// ``StableAudioGenerator/defaultMaxDurationSeconds`` if either is non-positive.
  public var maxDurationSeconds: Double {
    guard sampleSize > 0, sampleRate > 0 else {
      return StableAudioGenerator.defaultMaxDurationSeconds
    }
    return Double(sampleSize) / Double(sampleRate)
  }

  // MARK: - Nested types

  /// The `model` sub-object.
  public struct ModelBlock: Codable, Sendable, Equatable {
    /// The DiT latent / IO channel count (256 for SFX).
    public let ioChannels: Int
    public let pretransform: Pretransform
    public let conditioning: Conditioning
    public let diffusion: Diffusion

    private enum CodingKeys: String, CodingKey {
      case ioChannels = "io_channels"
      case pretransform
      case conditioning
      case diffusion
    }
  }

  /// The autoencoder pretransform block.
  public struct Pretransform: Codable, Sendable, Equatable {
    public let type: String
    public let config: PretransformConfig

    public struct PretransformConfig: Codable, Sendable, Equatable {
      public let latentDim: Int
      public let downsamplingRatio: Int
      public let ioChannels: Int

      private enum CodingKeys: String, CodingKey {
        case latentDim = "latent_dim"
        case downsamplingRatio = "downsampling_ratio"
        case ioChannels = "io_channels"
      }
    }
  }

  /// The conditioning block (text + numeric conditioners). Only the shared
  /// `cond_dim` is strongly typed; the individual conditioner configs (T5Gemma
  /// repo/subfolder, `seconds_total` range) are decoded loosely as S7 owns the
  /// encoder.
  public struct Conditioning: Codable, Sendable, Equatable {
    /// Conditioning embedding dimension (`768` for SFX).
    public let condDim: Int
    public let configs: [ConditionerConfig]

    private enum CodingKeys: String, CodingKey {
      case condDim = "cond_dim"
      case configs
    }
  }

  /// A single conditioner descriptor (`prompt` / `seconds_total`). Decoded
  /// loosely — only the identity/type are exposed here.
  public struct ConditionerConfig: Codable, Sendable, Equatable {
    public let id: String
    public let type: String
  }

  /// The diffusion (DiT) block.
  public struct Diffusion: Codable, Sendable, Equatable {
    /// e.g. `"dit"`.
    public let type: String
    /// e.g. `"rf_denoiser"`.
    public let diffusionObjective: String
    public let config: DiffusionConfig

    private enum CodingKeys: String, CodingKey {
      case type
      case diffusionObjective = "diffusion_objective"
      case config
    }
  }

  /// The DiT hyperparameters consumed by the Sortie 8 sampler.
  ///
  /// Every field that differs between the SA3 DiT variants (sm vs medium) is
  /// read straight from `model.diffusion.config` — `embed_dim` (1024 vs 1536),
  /// `depth` (20 vs 24), `num_heads` (16 vs 24), plus `io_channels`, the
  /// conditioning dims, `local_add_cond_dim`, and `num_memory_tokens`. The DiT
  /// network reads these; it never hardcodes them. Two derived quantities
  /// (``headDim`` = `embed_dim / num_heads`, ``ffInner`` = `embed_dim × 4`) and
  /// two family-wide constants that are NOT carried as scalar keys in the
  /// diffusion block (rope partial-dims = 32, timestep Fourier dim = 256) are
  /// the only values not decoded here — mirroring the reference, which likewise
  /// derives / hardcodes exactly those.
  public struct DiffusionConfig: Codable, Sendable, Equatable {
    /// DiT input/output channels (256 for SFX).
    public let ioChannels: Int
    /// Transformer embedding width (1024 for SFX).
    public let embedDim: Int
    /// Transformer block count (20 for SFX).
    public let depth: Int
    /// Attention head count (16 for SFX).
    public let numHeads: Int
    /// Cross-attention conditioning token dimension (768 for SFX).
    public let condTokenDim: Int
    /// Global (adaLN) conditioning dimension (768 for SFX).
    public let globalCondDim: Int
    /// Local-add (inpaint) conditioning channel count (`local_add_cond_dim`,
    /// 257 for SFX = 1 inpaint mask + 256 masked-input channels).
    public let localAddCondDim: Int
    /// Count of learned memory tokens prepended to the sequence
    /// (`num_memory_tokens`, 64 for SFX).
    public let numMemoryTokens: Int

    /// Per-head width, `embed_dim / num_heads` (64 for SFX).
    public var headDim: Int { embedDim / numHeads }
    /// GLU feed-forward inner width, `embed_dim × 4` (`ff_kwargs.mult` = 4.0 is
    /// a family-wide constant → 4096 for SFX, 6144 for medium).
    public var ffInner: Int { embedDim * 4 }

    private enum CodingKeys: String, CodingKey {
      case ioChannels = "io_channels"
      case embedDim = "embed_dim"
      case depth
      case numHeads = "num_heads"
      case condTokenDim = "cond_token_dim"
      case globalCondDim = "global_cond_dim"
      case localAddCondDim = "local_add_cond_dim"
      case numMemoryTokens = "num_memory_tokens"
    }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      ioChannels = try c.decode(Int.self, forKey: .ioChannels)
      embedDim = try c.decode(Int.self, forKey: .embedDim)
      depth = try c.decode(Int.self, forKey: .depth)
      numHeads = try c.decode(Int.self, forKey: .numHeads)
      condTokenDim = try c.decode(Int.self, forKey: .condTokenDim)
      globalCondDim = try c.decode(Int.self, forKey: .globalCondDim)
      localAddCondDim = try c.decodeIfPresent(Int.self, forKey: .localAddCondDim) ?? 257
      numMemoryTokens = try c.decodeIfPresent(Int.self, forKey: .numMemoryTokens) ?? 64
    }
  }

  // MARK: - Loading

  /// Decode a `StableAudioModelConfig` from raw `model_config.json` bytes.
  public static func decode(from data: Data) throws -> StableAudioModelConfig {
    try JSONDecoder().decode(StableAudioModelConfig.self, from: data)
  }

  /// Load and decode `model_config.json` from an Acervo-resolved model
  /// directory.
  ///
  /// - Parameter modelDirectory: the directory containing
  ///   ``configFileName`` (e.g. the Acervo `{org}_{repo}` slug directory).
  /// - Throws: ``StableAudioModelLoaderError/configNotFound(_:)`` when the file
  ///   is absent, or a `DecodingError` when the JSON does not match.
  public static func load(fromModelDirectory modelDirectory: URL) throws -> StableAudioModelConfig {
    let configURL = modelDirectory.appendingPathComponent(configFileName, isDirectory: false)
    guard FileManager.default.fileExists(atPath: configURL.path) else {
      throw StableAudioModelLoaderError.configNotFound(configURL)
    }
    let data = try Data(contentsOf: configURL)
    return try decode(from: data)
  }
}
