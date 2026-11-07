//
//  T5GemmaTextEncoder.swift
//  SwiftAmbiente
//
//  Sortie 7 (OPERATION PHANTOM FOLEY, WU2): op-for-op MLX Swift translation of
//  the official Stable Audio 3 `optimized/mlx` T5Gemma text encoder.
//
//  Reference translated from:
//    Stability-AI/stable-audio-3 → optimized/mlx/models/defs/t5gemma_mlx.py
//      · _rms_norm / _rope_cos_sin / _rotate_half / _apply_rope
//      · _SelfAttention / _MLP / _EncoderLayer / _Encoder
//  Invocation convention cross-checked against:
//    optimized/mlx/scripts/parity_forward_mlx.py  (t5.encode(...) usage)
//
//  Encoder facts (Gemma2-style, from t5gemma-b-b-ul2/config.json "encoder"):
//    hidden 768 · 12 layers · 12 heads · head_dim 64 · GeGLU(2048) intermediate
//    RMSNorm(1 + w) in fp32 · RoPE (θ=10000, half-half layout)
//    attn logit softcap = 50 · query_pre_attn_scalar = 64 (scale = 64^-0.5)
//    embed × √hidden_size · forward runs in fp16 (matches the reference npz path)
//
//  SCOPE (S7 boundary): this produces the encoder last-hidden-state + attention
//  mask — i.e. the T5Gemma conditioning tensor the DiT conditioner consumes. The
//  learned padding-embedding substitution (`apply_prompt_padding` in
//  models/defs/sa3_pipeline.py) and the seconds_total token / cross-cat that
//  build the final DiT cross-conditioning use the *DiT base* weights
//  (`cond.prompt.padding_embedding`), NOT the T5Gemma weights — that is Sortie 8.
//  We deliberately stop at (embeds, mask).
//

import Foundation
import MLX
import MLXNN

// MARK: - Config

/// Gemma2-style encoder hyperparameters, mirroring the reference
/// `T5GemmaConfig`. Defaults match the SFX model's `t5gemma-b-b-ul2/config.json`
/// **encoder** block; ``load(fromT5GemmaDirectory:)`` overrides them from disk.
public struct T5GemmaEncoderConfig: Sendable, Equatable {
  public var hiddenSize: Int = 768
  public var numHiddenLayers: Int = 12
  public var numAttentionHeads: Int = 12
  public var numKeyValueHeads: Int = 12
  public var headDim: Int = 64
  public var intermediateSize: Int = 2048
  public var vocabSize: Int = 256_000
  public var ropeTheta: Float = 10_000.0
  public var rmsNormEps: Float = 1e-6
  public var attnLogitSoftcapping: Float = 50.0
  public var queryPreAttnScalar: Int = 64
  public var padTokenId: Int = 0

  public init() {}

  /// The on-disk subfolder (inside the SFX model directory) holding the
  /// T5Gemma encoder weights + config + tokenizer.
  public static let subfolderName = "t5gemma-b-b-ul2"

  /// The encoder weights file inside ``subfolderName``.
  public static let weightsFileName = "model.safetensors"

  /// The encoder config file inside ``subfolderName``.
  public static let configFileName = "config.json"

  private struct RawConfig: Decodable {
    struct Block: Decodable {
      let hidden_size: Int?
      let num_hidden_layers: Int?
      let num_attention_heads: Int?
      let num_key_value_heads: Int?
      let head_dim: Int?
      let intermediate_size: Int?
      let vocab_size: Int?
      let rope_theta: Float?
      let rms_norm_eps: Float?
      let attn_logit_softcapping: Float?
      let query_pre_attn_scalar: Int?
    }
    let encoder: Block?
    let pad_token_id: Int?
  }

  /// Parse the encoder block from `t5gemma-b-b-ul2/config.json`. Missing fields
  /// keep their (correct) defaults, so this parses even as upstream adds keys.
  public static func load(fromT5GemmaDirectory dir: URL) throws -> T5GemmaEncoderConfig {
    let url = dir.appendingPathComponent(configFileName, isDirectory: false)
    var cfg = T5GemmaEncoderConfig()
    guard FileManager.default.fileExists(atPath: url.path) else { return cfg }
    let raw = try JSONDecoder().decode(RawConfig.self, from: Data(contentsOf: url))
    if let pad = raw.pad_token_id { cfg.padTokenId = pad }
    if let b = raw.encoder {
      if let v = b.hidden_size { cfg.hiddenSize = v }
      if let v = b.num_hidden_layers { cfg.numHiddenLayers = v }
      if let v = b.num_attention_heads { cfg.numAttentionHeads = v }
      if let v = b.num_key_value_heads { cfg.numKeyValueHeads = v }
      if let v = b.head_dim { cfg.headDim = v }
      if let v = b.intermediate_size { cfg.intermediateSize = v }
      if let v = b.vocab_size { cfg.vocabSize = v }
      if let v = b.rope_theta { cfg.ropeTheta = v }
      if let v = b.rms_norm_eps { cfg.rmsNormEps = v }
      if let v = b.attn_logit_softcapping { cfg.attnLogitSoftcapping = v }
      if let v = b.query_pre_attn_scalar { cfg.queryPreAttnScalar = v }
    }
    return cfg
  }
}

// MARK: - Weights

/// Per-layer encoder weights, cast to fp16 to match the reference forward path.
struct T5GemmaLayerWeights {
  let qProj: MLXArray  // (H*D, hidden)
  let kProj: MLXArray
  let vProj: MLXArray
  let oProj: MLXArray
  let gateProj: MLXArray  // (intermediate, hidden)
  let upProj: MLXArray
  let downProj: MLXArray  // (hidden, intermediate)
  let preSelfAttnLN: MLXArray  // (hidden,)
  let postSelfAttnLN: MLXArray
  let preFeedforwardLN: MLXArray
  let postFeedforwardLN: MLXArray
}

/// The full loaded encoder weight set.
struct T5GemmaWeights {
  let embedTokens: MLXArray  // (vocab, hidden)
  let layers: [T5GemmaLayerWeights]
  let norm: MLXArray  // (hidden,)
}

/// Loads the T5Gemma encoder weights from
/// `<modelDir>/t5gemma-b-b-ul2/model.safetensors`, stripping the upstream
/// `model.encoder.` prefix and casting bf16 → fp16 (the on-disk weights are
/// bf16; the reference runs its forward in fp16, so we match that path — this is
/// the one name/layout conversion S6 flagged, documented in STRATEGY.md).
enum T5GemmaWeightLoader {
  static let prefix = "model.encoder."

  static func load(fromT5GemmaDirectory dir: URL, config: T5GemmaEncoderConfig) throws
    -> T5GemmaWeights
  {
    let url = dir.appendingPathComponent(
      T5GemmaEncoderConfig.weightsFileName, isDirectory: false)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw StableAudioModelLoaderError.weightsNotFound(url)
    }
    let raw = try MLX.loadArrays(url: url)

    func fetch(_ key: String) throws -> MLXArray {
      guard let a = raw[prefix + key] else {
        throw StableAudioModelLoaderError.tensorMissing(prefix + key)
      }
      return a.asType(.float16)
    }

    var layers: [T5GemmaLayerWeights] = []
    layers.reserveCapacity(config.numHiddenLayers)
    for i in 0..<config.numHiddenLayers {
      let p = "layers.\(i)."
      layers.append(
        T5GemmaLayerWeights(
          qProj: try fetch(p + "self_attn.q_proj.weight"),
          kProj: try fetch(p + "self_attn.k_proj.weight"),
          vProj: try fetch(p + "self_attn.v_proj.weight"),
          oProj: try fetch(p + "self_attn.o_proj.weight"),
          gateProj: try fetch(p + "mlp.gate_proj.weight"),
          upProj: try fetch(p + "mlp.up_proj.weight"),
          downProj: try fetch(p + "mlp.down_proj.weight"),
          preSelfAttnLN: try fetch(p + "pre_self_attn_layernorm.weight"),
          postSelfAttnLN: try fetch(p + "post_self_attn_layernorm.weight"),
          preFeedforwardLN: try fetch(p + "pre_feedforward_layernorm.weight"),
          postFeedforwardLN: try fetch(p + "post_feedforward_layernorm.weight")))
    }
    return T5GemmaWeights(
      embedTokens: try fetch("embed_tokens.weight"),
      layers: layers,
      norm: try fetch("norm.weight"))
  }
}

// MARK: - Encoder

/// Op-for-op MLX Swift translation of the reference `_Encoder`.
///
/// Not `Sendable`: it retains `MLXArray` weights (reference-backed, non-Sendable).
/// Build and run it within a single concurrency domain; extract Swift values
/// (e.g. `[Float]`) before crossing an `await` boundary.
public final class T5GemmaTextEncoder {
  public let config: T5GemmaEncoderConfig
  let weights: T5GemmaWeights

  /// Precomputed RoPE inverse frequencies (fp32), θ=10000, half-half layout.
  private let invFreq: [Float]

  init(config: T5GemmaEncoderConfig, weights: T5GemmaWeights) {
    self.config = config
    self.weights = weights
    let d = config.headDim
    let theta = config.ropeTheta
    var inv = [Float]()
    inv.reserveCapacity(d / 2)
    for i in stride(from: 0, to: d, by: 2) {
      inv.append(1.0 / powf(theta, Float(i) / Float(d)))
    }
    self.invFreq = inv
  }

  /// Load config + weights from an SFX model directory (the directory that
  /// contains the `t5gemma-b-b-ul2/` subfolder).
  public static func load(fromModelDirectory modelDir: URL) throws -> T5GemmaTextEncoder {
    let sub = modelDir.appendingPathComponent(
      T5GemmaEncoderConfig.subfolderName, isDirectory: true)
    let cfg = try T5GemmaEncoderConfig.load(fromT5GemmaDirectory: sub)
    let w = try T5GemmaWeightLoader.load(fromT5GemmaDirectory: sub, config: cfg)
    return T5GemmaTextEncoder(config: cfg, weights: w)
  }

  // MARK: Ops (translated from t5gemma_mlx.py)

  /// Gemma-style RMSNorm: normalize in fp32, scale by (1 + weight), cast back.
  private func rmsNorm(_ x: MLXArray, _ weight: MLXArray) -> MLXArray {
    let dtype = x.dtype
    let x32 = x.asType(.float32)
    let variance = (x32 * x32).mean(axis: -1, keepDims: true)
    let n = x32 * MLX.rsqrt(variance + config.rmsNormEps)
    let scaled = n * (MLXArray(Float(1.0)) + weight.asType(.float32))
    return scaled.asType(dtype)
  }

  /// (cos, sin) of shape (S, head_dim), half-half layout, computed in fp32.
  private func ropeCosSin(seqLen: Int) -> (MLXArray, MLXArray) {
    let pos = MLXArray(Array(0..<seqLen).map { Float($0) })  // (S,)
    let inv = MLXArray(invFreq)  // (head_dim/2,)
    let freqs = MLX.outer(pos, inv)  // (S, head_dim/2)
    let emb = MLX.concatenated([freqs, freqs], axis: -1)  // (S, head_dim)
    return (MLX.cos(emb), MLX.sin(emb))
  }

  /// rotate_half: [-x[..., half:], x[..., :half]] concatenated on the last axis.
  private func rotateHalf(_ x: MLXArray) -> MLXArray {
    let parts = x.split(parts: 2, axis: -1)  // [first, second]
    return MLX.concatenated([-parts[1], parts[0]], axis: -1)
  }

  /// Apply RoPE to q and k (each (B, H, S, D)); cos/sin are (S, D).
  private func applyRope(_ q: MLXArray, _ k: MLXArray, _ cos: MLXArray, _ sin: MLXArray)
    -> (MLXArray, MLXArray)
  {
    let cos4 = cos.expandedDimensions(axes: [0, 1])  // (1,1,S,D)
    let sin4 = sin.expandedDimensions(axes: [0, 1])
    let qc = cos4.asType(q.dtype)
    let qs = sin4.asType(q.dtype)
    let kc = cos4.asType(k.dtype)
    let ks = sin4.asType(k.dtype)
    let qOut = (q * qc) + (rotateHalf(q) * qs)
    let kOut = (k * kc) + (rotateHalf(k) * ks)
    return (qOut, kOut)
  }

  /// Linear (no bias): x @ W.T, W stored as (out, in) exactly as upstream.
  private func linear(_ x: MLXArray, _ weight: MLXArray) -> MLXArray {
    MLX.matmul(x, weight.transposed())
  }

  private func selfAttention(
    _ x: MLXArray, layer: T5GemmaLayerWeights,
    cos: MLXArray, sin: MLXArray, addMask: MLXArray?
  ) -> MLXArray {
    let shape = x.shape
    let B = shape[0]
    let S = shape[1]
    let H = config.numAttentionHeads
    let D = config.headDim
    let scaling = powf(Float(config.queryPreAttnScalar), -0.5)

    var q = linear(x, layer.qProj).reshaped([B, S, H, D]).transposed(0, 2, 1, 3)
    var k = linear(x, layer.kProj).reshaped([B, S, H, D]).transposed(0, 2, 1, 3)
    let v = linear(x, layer.vProj).reshaped([B, S, H, D]).transposed(0, 2, 1, 3)
    (q, k) = applyRope(q, k, cos, sin)

    var qk = MLX.matmul(q, k.transposed(0, 1, 3, 2)) * scaling
    let cap = config.attnLogitSoftcapping
    qk = MLX.tanh(qk / cap) * cap
    if let addMask { qk = qk + addMask }
    let p = MLX.softmax(qk.asType(.float32), axis: -1).asType(v.dtype)
    let out = MLX.matmul(p, v).transposed(0, 2, 1, 3).reshaped([B, S, H * D])
    return linear(out, layer.oProj)
  }

  private func mlp(_ x: MLXArray, layer: T5GemmaLayerWeights) -> MLXArray {
    let gate = MLXNN.geluApproximate(linear(x, layer.gateProj))
    return linear(gate * linear(x, layer.upProj), layer.downProj)
  }

  private func encoderLayer(
    _ x0: MLXArray, layer: T5GemmaLayerWeights,
    cos: MLXArray, sin: MLXArray, addMask: MLXArray?
  ) -> MLXArray {
    var h = rmsNorm(x0, layer.preSelfAttnLN)
    h = selfAttention(h, layer: layer, cos: cos, sin: sin, addMask: addMask)
    h = rmsNorm(h, layer.postSelfAttnLN)
    let x = x0 + h
    var h2 = rmsNorm(x, layer.preFeedforwardLN)
    h2 = mlp(h2, layer: layer)
    h2 = rmsNorm(h2, layer.postFeedforwardLN)
    return x + h2
  }

  /// Forward pass. `inputIds` (B, S) int32; `attentionMask` (B, S) int32/float
  /// (1 = real token, 0 = pad) or nil. Returns the last hidden state (B, S, 768)
  /// fp16.
  public func callAsFunction(inputIds: MLXArray, attentionMask: MLXArray?) -> MLXArray {
    let B = inputIds.shape[0]
    let S = inputIds.shape[1]
    let hidden = config.hiddenSize

    // Embedding gather → fp16, then × √hidden_size.
    let flatIds = inputIds.reshaped([B * S])
    var x = MLX.take(weights.embedTokens, flatIds, axis: 0).reshaped([B, S, hidden])
    x = x.asType(.float16)
    let normalizer = MLXArray(Float(sqrtf(Float(hidden)))).asType(.float16)
    x = x * normalizer

    let (cos, sin) = ropeCosSin(seqLen: S)

    var addMask: MLXArray? = nil
    if let attentionMask {
      let keep = attentionMask.asType(.float32)
      let am = ((MLXArray(Float(1.0)) - keep) * Float(-1e9))
        .expandedDimensions(axes: [1, 2])  // (B,1,1,S)
      addMask = am.asType(x.dtype)
    }

    for layer in weights.layers {
      x = encoderLayer(x, layer: layer, cos: cos, sin: sin, addMask: addMask)
    }
    return rmsNorm(x, weights.norm)
  }
}
