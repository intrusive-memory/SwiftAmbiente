//
//  StableAudioAssetLoader.swift
//  SwiftAmbiente
//
//  Sortie 6 (OPERATION PHANTOM FOLEY, WU2): load the Stable Audio 3 Small SFX
//  weights from an Acervo-resolved model directory into MLX arrays and verify
//  expected tensor names/shapes exist.
//
//  Uses MLX Swift's safetensors loader (`MLX.loadArrays(url:)` in
//  ml-explore/mlx-swift `Source/MLX/IO.swift`), which returns a lazy
//  `[String: MLXArray]` map — tensor metadata (shape/dtype) is available without
//  materializing 2 GB of weights, so shape verification is cheap.
//
//  Scope boundary: this loads and shape-checks assets only. The encoder /
//  sampler / decoder forward passes (Sorties 7–9) are NOT implemented here, and
//  the T5Gemma text encoder under `t5gemma-b-b-ul2/` (Sortie 7) is NOT loaded.
//

import Foundation
import MLX

/// Errors raised while loading or verifying Stable Audio model assets.
public enum StableAudioModelLoaderError: Error, CustomStringConvertible, Sendable {
  /// `model_config.json` was not present at the resolved path.
  case configNotFound(URL)
  /// `model.safetensors` was not present at the resolved path.
  case weightsNotFound(URL)
  /// An expected tensor name was absent from the loaded weight map.
  case tensorMissing(String)
  /// A tensor was present but had an unexpected shape.
  case shapeMismatch(name: String, expected: [Int], actual: [Int])

  public var description: String {
    switch self {
    case .configNotFound(let url):
      return "Stable Audio config not found at \(url.path) "
        + "(expected \(StableAudioModelConfig.configFileName))"
    case .weightsNotFound(let url):
      return "Stable Audio weights not found at \(url.path) "
        + "(expected \(StableAudioModelAssets.weightsFileName))"
    case .tensorMissing(let name):
      return "Stable Audio weights are missing expected tensor '\(name)'"
    case .shapeMismatch(let name, let expected, let actual):
      return "Stable Audio tensor '\(name)' shape mismatch: "
        + "expected \(expected), got \(actual)"
    }
  }
}

/// The loaded assets for a Stable Audio model: parsed config plus the
/// safetensors weight map as MLX arrays.
///
/// The weight map is the raw upstream tensor namespace (e.g.
/// `model.model.preprocess_conv.weight`,
/// `conditioner.conditioners.seconds_total.embedder.embedding.1.weight`). This
/// type provides name/shape verification helpers; it does NOT build any network
/// module (that is Sorties 7–9).
///
/// Not `Sendable`: MLX's `MLXArray` is a reference-backed, non-`Sendable` type,
/// so the loaded weight map must stay within a single concurrency domain. Load
/// and inspect assets on one task; do not pass this value across an `await`
/// boundary.
public struct StableAudioModelAssets {
  /// The on-disk weights file name for a Stable Audio 3 model.
  public static let weightsFileName = "model.safetensors"

  /// The parsed `model_config.json`.
  public let config: StableAudioModelConfig

  /// The safetensors weight map, keyed by upstream tensor name.
  public let weights: [String: MLXArray]

  /// The model directory these assets were loaded from.
  public let modelDirectory: URL

  /// Load the config and safetensors weights from an Acervo-resolved model
  /// directory.
  ///
  /// - Parameter modelDirectory: the directory containing
  ///   `model_config.json` and `model.safetensors` (e.g. the Acervo
  ///   `{org}_{repo}` slug directory).
  /// - Throws: ``StableAudioModelLoaderError`` when a required file is absent,
  ///   a `DecodingError` if the config JSON is malformed, or an MLX load error
  ///   if the safetensors file is unreadable.
  public static func load(fromModelDirectory modelDirectory: URL) throws -> StableAudioModelAssets {
    let config = try StableAudioModelConfig.load(fromModelDirectory: modelDirectory)
    let weights = try loadWeights(fromModelDirectory: modelDirectory)
    return StableAudioModelAssets(
      config: config, weights: weights, modelDirectory: modelDirectory)
  }

  /// Load only the safetensors weight map (no config parse).
  ///
  /// - Throws: ``StableAudioModelLoaderError/weightsNotFound(_:)`` if the file
  ///   is absent, or the underlying MLX load error otherwise.
  public static func loadWeights(fromModelDirectory modelDirectory: URL) throws
    -> [String: MLXArray]
  {
    let weightsURL = modelDirectory.appendingPathComponent(weightsFileName, isDirectory: false)
    guard FileManager.default.fileExists(atPath: weightsURL.path) else {
      throw StableAudioModelLoaderError.weightsNotFound(weightsURL)
    }
    // MLX Swift's safetensors reader. Returns a lazy [String: MLXArray]; shape
    // and dtype are available without evaluating the arrays.
    return try MLX.loadArrays(url: weightsURL)
  }

  // MARK: - Shape verification

  /// The shape of a named tensor, or `nil` if it is absent.
  public func shape(of tensorName: String) -> [Int]? {
    weights[tensorName]?.shape
  }

  /// Assert that a named tensor exists and has the expected shape.
  ///
  /// - Throws: ``StableAudioModelLoaderError/tensorMissing(_:)`` or
  ///   ``StableAudioModelLoaderError/shapeMismatch(name:expected:actual:)``.
  public func verifyTensor(_ name: String, hasShape expected: [Int]) throws {
    guard let array = weights[name] else {
      throw StableAudioModelLoaderError.tensorMissing(name)
    }
    let actual = array.shape
    guard actual == expected else {
      throw StableAudioModelLoaderError.shapeMismatch(
        name: name, expected: expected, actual: actual)
    }
  }

  /// Assert that every `(name, shape)` pair in `expectations` is present and
  /// matches. Verifies the loaded weight map carries the load-bearing tensors
  /// the WU2 pipeline (Sorties 7–9) will consume.
  public func verifyTensors(_ expectations: [String: [Int]]) throws {
    for (name, shape) in expectations {
      try verifyTensor(name, hasShape: shape)
    }
  }

  /// A small set of known tensor name→shape pairs for the Stable Audio 3 Small
  /// SFX model, usable as a sanity gate that the correct weights were loaded.
  /// Shapes verified against the real 685-tensor `model.safetensors`.
  public static let knownSFXTensorShapes: [String: [Int]] = [
    "model.model.preprocess_conv.weight": [256, 256, 1],
    "model.model.postprocess_conv.weight": [256, 256, 1],
    "model.model.to_cond_embed.0.weight": [1024, 768],
    "conditioner.conditioners.seconds_total.embedder.embedding.1.weight": [768, 256],
  ]
}
