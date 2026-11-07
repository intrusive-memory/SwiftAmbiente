//
//  T5GemmaTextConditioner.swift
//  SwiftAmbiente
//
//  Sortie 7 (OPERATION PHANTOM FOLEY, WU2): high-level text-conditioning entry
//  point — tokenize a prompt and run the T5Gemma encoder to produce the DiT
//  conditioning tensor(s).
//
//  Mirrors the reference `T5Gemma.encode` (t5gemma_mlx.py): tokenize → forward →
//  return (last_hidden_state, attention_mask). Includes the reference's
//  all-zero-mask guard (an empty prompt row would make the attention softmax see
//  all -inf → NaN; give such a row one visible position for the forward, then
//  restore mask=0 so downstream padding logic still overwrites it).
//
//  SCOPE (S7 boundary): the output is the T5Gemma encoder hidden state + mask.
//  The learned-padding substitution + seconds_total token + cross-cat that form
//  the DiT's final cross-conditioning live in the DiT base conditioner
//  (Sortie 8); they are intentionally NOT applied here.
//

import Foundation
import MLX

/// The T5Gemma text-conditioning output.
///
/// Not `Sendable` (holds `MLXArray`s). Consume within one concurrency domain.
public struct T5GemmaConditioning {
  /// Encoder last hidden state, `(B, maxLen, hidden)` fp16.
  public let embeddings: MLXArray
  /// Attention mask, `(B, maxLen)` int32 (1 = real token, 0 = pad).
  public let mask: MLXArray
  /// The batch size `B`.
  public let batch: Int
  /// The padded sequence length `maxLen`.
  public let sequenceLength: Int
  /// The hidden width (768).
  public let hiddenSize: Int
}

/// Tokenizer + encoder wrapper producing T5Gemma conditioning from raw strings.
///
/// Not `Sendable`: retains the non-Sendable `T5GemmaTextEncoder`.
public final class T5GemmaTextConditioner {
  public let tokenizer: GemmaBPETokenizer
  public let encoder: T5GemmaTextEncoder

  public init(tokenizer: GemmaBPETokenizer, encoder: T5GemmaTextEncoder) {
    self.tokenizer = tokenizer
    self.encoder = encoder
  }

  /// Load tokenizer + encoder from an SFX model directory (the one containing
  /// the `t5gemma-b-b-ul2/` subfolder).
  public static func load(fromModelDirectory modelDir: URL) throws -> T5GemmaTextConditioner {
    let sub = modelDir.appendingPathComponent(
      T5GemmaEncoderConfig.subfolderName, isDirectory: true)
    let encoder = try T5GemmaTextEncoder.load(fromModelDirectory: modelDir)
    let tokenizer = try GemmaBPETokenizer.load(
      fromT5GemmaDirectory: sub, padTokenId: encoder.config.padTokenId)
    return T5GemmaTextConditioner(tokenizer: tokenizer, encoder: encoder)
  }

  /// Tokenize + encode a batch of prompts in one call.
  ///
  /// - Returns: ``T5GemmaConditioning`` with `embeddings` `(B, maxLen, 768)` fp16
  ///   and `mask` `(B, maxLen)` int32.
  public func encode(_ prompts: [String], maxLen: Int = 256) -> T5GemmaConditioning {
    let hidden = encoder.config.hiddenSize
    let (idsFlat, maskFlat, B) = tokenizer.tokenizeBatch(prompts, maxLen: maxLen)

    let ids = MLXArray(idsFlat, [B, maxLen])
    let mask = MLXArray(maskFlat, [B, maxLen])

    // All-zero-mask guard: for the forward pass, ensure every row has at least
    // one visible position so softmax never sees all -inf.
    var forwardMaskFlat = maskFlat
    for row in 0..<B {
      var any = false
      for j in 0..<maxLen where maskFlat[row * maxLen + j] != 0 {
        any = true
        break
      }
      if !any { forwardMaskFlat[row * maxLen] = 1 }
    }
    let forwardMask = MLXArray(forwardMaskFlat, [B, maxLen])

    let embeds = encoder(inputIds: ids, attentionMask: forwardMask)
    return T5GemmaConditioning(
      embeddings: embeds, mask: mask, batch: B,
      sequenceLength: maxLen, hiddenSize: hidden)
  }
}
