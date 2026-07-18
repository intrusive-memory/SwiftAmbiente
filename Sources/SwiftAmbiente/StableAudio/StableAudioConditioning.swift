//
//  StableAudioConditioning.swift
//  SwiftAmbiente
//
//  Sortie 8 (OPERATION PHANTOM FOLEY, WU2): translation of the DiT-side
//  conditioning assembly from the official reference.
//
//  Reference translated from:
//    Stability-AI/stable-audio-3 → optimized/mlx/models/defs/sa3_pipeline.py
//      (`expo_fourier_features`, `SecondsTotalEmbedder`, `apply_prompt_padding`)
//    · assembly (cross-attn cat + global cond) from
//      optimized/mlx/scripts/sa3_mlx.py ("── 2. Conditioning ──").
//
//  This turns the S7 T5Gemma output (embeds + mask) plus a `seconds_total` value
//  into exactly the two tensors the DiT consumes:
//    · cross_attn : (1, S+1, 768)  = [padding-substituted T5Gemma tokens ; seconds token]
//    · global     : (1, 768)       = the seconds token
//  The learned `padding_embedding` and the `seconds_total` linear both come from
//  the DiT's own `model.safetensors` (the `conditioner.conditioners.*` keys), NOT
//  the T5Gemma weights.
//

import Foundation
import MLX

/// The `seconds_total` number-conditioner: ExpoFourierFeatures → Linear, giving a
/// single 768-dim token. Computed in fp32 (weights are fp32 on disk), matching
/// the reference `SecondsTotalEmbedder`.
public struct SecondsTotalEmbedder {
  let weight: MLXArray  // (768, fourierDim) fp32
  let bias: MLXArray    // (768,) fp32
  let minVal: Float
  let maxVal: Float
  let fourierDim: Int
  /// Precomputed `freqs = exp(linspace(0,1,dim/2)·(ln max − ln min)+ln min)·2π`.
  let freqs: MLXArray   // (fourierDim/2,) fp32

  public init(
    weight: MLXArray, bias: MLXArray,
    minVal: Float = 0.0, maxVal: Float = 384.0, fourierDim: Int = 256
  ) {
    self.weight = weight.asType(.float32)
    self.bias = bias.asType(.float32)
    self.minVal = minVal
    self.maxVal = maxVal
    self.fourierDim = fourierDim
    self.freqs = StableAudioDiT.expoFourierFreqs(dim: fourierDim, minFreq: 0.5, maxFreq: 10000.0)
  }

  /// `seconds → (1, 1, 768)` fp32.
  public func callAsFunction(_ seconds: Float) -> MLXArray {
    let clamped = min(max(seconds, minVal), maxVal)
    let norm = (clamped - minVal) / (maxVal - minVal)
    let t = MLXArray([norm])  // (1,) fp32
    let args = t.expandedDimensions(axis: 1) * freqs  // (1, half)
    let ff = MLX.concatenated([MLX.cos(args), MLX.sin(args)], axis: -1)  // (1, fourierDim)
    let out = MLX.matmul(ff, weight.transposed()) + bias  // (1, 768)
    return out.expandedDimensions(axis: 1)  // (1, 1, 768)
  }
}

/// The DiT-side conditioning weights extracted from the model's safetensors.
public struct StableAudioConditioner {
  /// Learned padding embedding, `(cond_dim,)`.
  public let paddingEmbedding: MLXArray
  /// The `seconds_total` embedder.
  public let secondsEmbedder: SecondsTotalEmbedder

  static let paddingKey = "conditioner.conditioners.prompt.padding_embedding"
  static let secondsWeightKey =
    "conditioner.conditioners.seconds_total.embedder.embedding.1.weight"
  static let secondsBiasKey =
    "conditioner.conditioners.seconds_total.embedder.embedding.1.bias"

  /// Build from a loaded safetensors map.
  public static func load(from weights: [String: MLXArray]) throws -> StableAudioConditioner {
    func fetch(_ key: String) throws -> MLXArray {
      guard let a = weights[key] else { throw StableAudioModelLoaderError.tensorMissing(key) }
      return a
    }
    let pad = try fetch(paddingKey).asType(.float32)
    let w = try fetch(secondsWeightKey)
    let b = try fetch(secondsBiasKey)
    return StableAudioConditioner(
      paddingEmbedding: pad,
      secondsEmbedder: SecondsTotalEmbedder(weight: w, bias: b))
  }

  /// Replace padded positions in the T5Gemma output with the learned padding
  /// embedding. `embeds:(B,S,768)`, `mask:(B,S)` (1 = real, 0 = pad).
  public func applyPromptPadding(embeds: MLXArray, mask: MLXArray) -> MLXArray {
    let m = mask.asType(embeds.dtype).expandedDimensions(axis: -1)  // (B,S,1)
    let pe = paddingEmbedding.asType(embeds.dtype).reshaped([1, 1, paddingEmbedding.shape[0]])
    return embeds * m + pe * (1 - m)
  }

  /// The assembled DiT conditioning for one generation.
  public struct Assembled {
    /// `(1, S+1, 768)` cross-attention conditioning, cast to `dtype`.
    public let crossAttn: MLXArray
    /// `(1, 768)` global (seconds_total) conditioning, cast to `dtype`.
    public let globalCond: MLXArray
  }

  /// Assemble `cross_attn` + `global` from T5Gemma output and a duration, mirroring
  /// sa3_mlx.py's "── 2. Conditioning ──" block.
  ///
  /// - Parameters:
  ///   - embeds: T5Gemma last hidden state `(1, S, 768)`.
  ///   - mask: attention mask `(1, S)`.
  ///   - seconds: `seconds_total` value.
  ///   - dtype: sampling dtype (fp16) the tensors are cast to.
  public func assemble(embeds: MLXArray, mask: MLXArray, seconds: Float, dtype: DType) -> Assembled {
    let e = embeds.asType(dtype)
    let padded = applyPromptPadding(embeds: e, mask: mask)
    let secondsEmbed = secondsEmbedder(seconds).asType(dtype)  // (1,1,768)
    let crossAttn = MLX.concatenated([padded, secondsEmbed], axis: 1)  // (1, S+1, 768)
    let globalCond = secondsEmbed[0, axis: 1]  // (1, 768)
    return Assembled(crossAttn: crossAttn, globalCond: globalCond)
  }
}
