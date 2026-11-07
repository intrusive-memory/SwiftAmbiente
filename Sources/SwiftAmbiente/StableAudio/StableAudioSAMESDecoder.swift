//
//  StableAudioSAMESDecoder.swift
//  SwiftAmbiente
//
//  Sortie 9 (OPERATION PHANTOM FOLEY, WU2): op-for-op MLX Swift translation of
//  the SAME-S latent decoder + the patched-pretransform unpatch.
//
//  Reference translated from:
//    Stability-AI/stable-audio-3 → optimized/mlx/models/defs/same_s_decoder.py
//      (`DyT`, `DifferentialAttention`, `GLU_FF`, `TransformerBlock`,
//       `SAMESDecoder.__call__`, `decode_chunked`)
//    optimized/mlx/models/defs/sa3_pipeline.py → `patched_decode`
//    optimized/mlx/scripts/sa3_mlx.py → the "── 4. Decode ──" dispatch
//      (chunked / un-chunked / chunk=2 / odd-pad-trim).
//
//  WEIGHTS: read from the shipped small-sfx `model.safetensors` raw
//  `pretransform.model.decoder.*` namespace (see STRATEGY.md "Sortie 9 note"):
//    · layers.1.{weight,bias}                  → project_in (Linear 256→768)
//    · layers.3.new_tokens                     → new_tokens
//    · layers.3.transformers.{i}.*             → blocks[i]
//    · layers.3.mapping.{weight_g,weight_v,bias} → mapping (weight-norm FOLD,
//      w = g · v / ‖v‖ per out-channel, then PyTorch [out,in,k] → MLX [out,k,in])
//    · pretransform.model.bottleneck.running_std → running_std
//  The stored `rope.inv_freq` is NOT loaded (the reference uses `mx.fast.rope`
//  with base 10000); the encoder-side bottleneck tensors are NOT applied.
//
//  PRECISION: FP32 throughout. SAME-S catastrophically cancels in fp16
//  (differential attention); the reference decoder always runs FP32.
//

import Foundation
import MLX
import MLXNN

/// SAME-S decoder: `[B, 256, T_lat]` latents → `[B, 512, T_lat·16]` audio patches.
///
/// Not `Sendable`: retains `MLXArray` weights. Build and run within one
/// concurrency domain.
public final class StableAudioSAMESDecoder {

  // MARK: Constants (SAME-S, from same_s_decoder.py)

  public static let latentDim = 256
  public static let dim = 768
  public static let numHeads = 12
  public static let headDim = 64
  public static let ropeDims = 32
  public static let numBlocks = 6
  public static let ffInner = 2304
  public static let outChannels = 512
  public static let stride = 16
  static let subChunkSize = stride + 1                     // 17
  static let chunkSizeLat = 32
  static let effectiveChunk = chunkSizeLat + chunkSizeLat / stride  // 34
  static let shift = effectiveChunk / 2                     // 17
  static let sinPerPos = subChunkSize - 1                   // 16

  /// `scripts/sa3_mlx.py::DECODER_CHOICES["same-s"]` chunk config.
  public static let defaultChunkSize = 8
  public static let defaultOverlap = 2

  /// Patched-pretransform geometry: 512 = 2 channels × 256 patch.
  public static let patchSize = 256
  public static let audioChannels = 2

  // MARK: Weights

  struct DyTWeights {
    let alpha: MLXArray  // (1,)
    let gamma: MLXArray  // (dim,)
    let beta: MLXArray   // (dim,)
  }

  struct BlockWeights {
    let preNorm: DyTWeights
    let toQKV: MLXArray     // (5·DIM, DIM)
    let toOut: MLXArray     // (DIM, DIM)
    let qNorm: DyTWeights
    let kNorm: DyTWeights
    let ffNorm: DyTWeights
    let gluProjW: MLXArray  // (2·FF_INNER, DIM)
    let gluProjB: MLXArray
    let projOutW: MLXArray  // (DIM, FF_INNER)
    let projOutB: MLXArray
  }

  let runningStd: MLXArray     // (1,)
  let projectInW: MLXArray     // (DIM, 256)
  let projectInB: MLXArray     // (DIM,)
  let newTokens: MLXArray      // (1, 1, DIM)
  let blocks: [BlockWeights]
  let mappingW: MLXArray       // (512, 3, DIM)  MLX conv layout [out, k, in]
  let mappingB: MLXArray       // (512,)

  init(
    runningStd: MLXArray, projectInW: MLXArray, projectInB: MLXArray,
    newTokens: MLXArray, blocks: [BlockWeights], mappingW: MLXArray, mappingB: MLXArray
  ) {
    self.runningStd = runningStd
    self.projectInW = projectInW
    self.projectInB = projectInB
    self.newTokens = newTokens
    self.blocks = blocks
    self.mappingW = mappingW
    self.mappingB = mappingB
  }

  static let decoderPrefix = "pretransform.model.decoder.layers."
  static let runningStdKey = "pretransform.model.bottleneck.running_std"

  /// Build the decoder from an already-loaded small-sfx safetensors map, all
  /// tensors cast to FP32.
  public static func load(from weights: [String: MLXArray]) throws -> StableAudioSAMESDecoder {
    func fetch(_ key: String) throws -> MLXArray {
      guard let a = weights[key] else { throw StableAudioModelLoaderError.tensorMissing(key) }
      return a.asType(.float32)
    }
    func dec(_ key: String) throws -> MLXArray { try fetch(decoderPrefix + key) }
    func dyt(_ p: String) throws -> DyTWeights {
      DyTWeights(
        alpha: try dec(p + ".alpha"), gamma: try dec(p + ".gamma"), beta: try dec(p + ".beta"))
    }

    var blocks: [BlockWeights] = []
    blocks.reserveCapacity(numBlocks)
    for i in 0..<numBlocks {
      let p = "3.transformers.\(i)."
      blocks.append(
        BlockWeights(
          preNorm: try dyt(p + "pre_norm"),
          toQKV: try dec(p + "self_attn.to_qkv.weight"),
          toOut: try dec(p + "self_attn.to_out.weight"),
          qNorm: try dyt(p + "self_attn.q_norm"),
          kNorm: try dyt(p + "self_attn.k_norm"),
          ffNorm: try dyt(p + "ff_norm"),
          gluProjW: try dec(p + "ff.ff.0.proj.weight"),
          gluProjB: try dec(p + "ff.ff.0.proj.bias"),
          projOutW: try dec(p + "ff.ff.2.weight"),
          projOutB: try dec(p + "ff.ff.2.bias")))
    }

    // Weight-norm fold (the ONLY fold): w = g · v / ‖v‖, the norm taken over the
    // (in, kernel) axes per out-channel (PyTorch weight_norm dim=0), then permute
    // PyTorch [out, in, k] → MLX conv [out, k, in].
    let g = try dec("3.mapping.weight_g")  // (512, 1, 1)
    let v = try dec("3.mapping.weight_v")  // (512, 768, 3)
    let norm = MLX.sqrt((v * v).sum(axes: [1, 2], keepDims: true))
    let folded = g * v / norm
    let mappingW = folded.transposed(0, 2, 1)

    let decoder = StableAudioSAMESDecoder(
      runningStd: try fetch(runningStdKey),
      projectInW: try dec("1.weight"),
      projectInB: try dec("1.bias"),
      newTokens: try dec("3.new_tokens"),
      blocks: blocks,
      mappingW: mappingW,
      mappingB: try dec("3.mapping.bias"))
    decoder.evalWeights()
    return decoder
  }

  private func evalWeights() {
    var all: [MLXArray] = [runningStd, projectInW, projectInB, newTokens, mappingW, mappingB]
    for b in blocks {
      all += [
        b.preNorm.alpha, b.preNorm.gamma, b.preNorm.beta, b.toQKV, b.toOut,
        b.qNorm.alpha, b.qNorm.gamma, b.qNorm.beta, b.kNorm.alpha, b.kNorm.gamma, b.kNorm.beta,
        b.ffNorm.alpha, b.ffNorm.gamma, b.ffNorm.beta, b.gluProjW, b.gluProjB, b.projOutW,
        b.projOutB,
      ]
    }
    MLX.eval(all)
  }

  // MARK: Ops (match mlx.nn semantics exactly)

  /// `nn.Linear` without bias: `x @ W.T`.
  private func linear(_ x: MLXArray, _ w: MLXArray) -> MLXArray {
    MLX.matmul(x, w.transposed())
  }

  /// `nn.Linear` with bias: the fused `mx.addmm(b, x, W.T)` MLX's Linear uses.
  private func linear(_ x: MLXArray, _ w: MLXArray, _ b: MLXArray) -> MLXArray {
    MLX.addMM(b, x, w.transposed())
  }

  /// `DyT`: `gamma · tanh(alpha · x) + beta`.
  private func dyt(_ x: MLXArray, _ w: DyTWeights) -> MLXArray {
    w.gamma * MLX.tanh(w.alpha * x) + w.beta
  }

  private func rope(_ x: MLXArray) -> MLXArray {
    MLX.RoPE(
      x, dimensions: Self.ropeDims, traditional: false, base: 10000.0, scale: 1.0, offset: 0)
  }

  /// Differential SDPA: `SDPA(q,k,v) − SDPA(q_diff,k_diff,v)`; `to_qkv` chunk(5)
  /// order is q, k, v, q_diff, k_diff.
  private func attention(_ x: MLXArray, _ w: BlockWeights) -> MLXArray {
    let B = x.shape[0], T = x.shape[1]
    let H = Self.numHeads, D = Self.headDim
    let scale = powf(Float(D), -0.5)

    let qkv = linear(x, w.toQKV)
    let p = qkv.split(parts: 5, axis: -1)
    func toHeads(_ t: MLXArray) -> MLXArray {
      t.reshaped([B, T, H, D]).transposed(0, 2, 1, 3)
    }
    var q = toHeads(p[0])
    var k = toHeads(p[1])
    let v = toHeads(p[2])
    var qDiff = toHeads(p[3])
    var kDiff = toHeads(p[4])

    q = dyt(q, w.qNorm)
    k = dyt(k, w.kNorm)
    qDiff = dyt(qDiff, w.qNorm)
    kDiff = dyt(kDiff, w.kNorm)

    q = rope(q)
    k = rope(k)
    qDiff = rope(qDiff)
    kDiff = rope(kDiff)

    let outMain = MLX.scaledDotProductAttention(
      queries: q, keys: k, values: v, scale: scale, mask: nil)
    let outDiff = MLX.scaledDotProductAttention(
      queries: qDiff, keys: kDiff, values: v, scale: scale, mask: nil)
    let out = (outMain - outDiff).transposed(0, 2, 1, 3).reshaped([B, T, Self.dim])
    return linear(out, w.toOut)
  }

  /// SwiGLU feed-forward (SiLU only).
  private func feedForward(_ x: MLXArray, _ w: BlockWeights) -> MLXArray {
    let h = linear(x, w.gluProjW, w.gluProjB)
    let p = h.split(parts: 2, axis: -1)
    return linear(p[0] * MLXNN.silu(p[1]), w.projOutW, w.projOutB)
  }

  private func block(_ xIn: MLXArray, _ w: BlockWeights) -> MLXArray {
    var x = xIn
    x = x + attention(dyt(x, w.preNorm), w)
    x = x + feedForward(dyt(x, w.ffNorm), w)
    return x
  }

  // MARK: Forward

  /// Un-chunked decode: `[B, 256, T_lat]` → `[B, 512, T_lat·16]`.
  ///
  /// Requires even `T_lat` (the internal `T_lat·17` must align to 34).
  public func callAsFunction(_ latents: MLXArray) -> MLXArray {
    let B = latents.shape[0], tLat = latents.shape[2]
    let D = Self.dim
    precondition(tLat % 2 == 0, "SAME-S un-chunked decode requires even T_lat (got \(tLat))")

    // Bottleneck softnorm decode: only running_std is applied on decode.
    var x = latents * runningStd

    // [B,256,T] → [B,T,256] → [B,T,768]
    x = linear(x.transposed(0, 2, 1), projectInW, projectInB)

    // Single learnable new_token broadcast to 16 positions per latent slot.
    let xE = x.expandedDimensions(axis: 2)  // [B,T,1,D]
    let nt = MLX.broadcast(
      newTokens.expandedDimensions(axis: 0), to: [B, tLat, Self.sinPerPos, D])
    x = MLX.concatenated([xE, nt], axis: 2)  // [B,T,17,D]
    let internalT = tLat * Self.subChunkSize
    x = x.reshaped([B, internalT, D])

    // First half (blocks 0..2): chunks of 34.
    let nc1 = internalT / Self.effectiveChunk
    x = x.reshaped([B * nc1, Self.effectiveChunk, D])
    x = block(x, blocks[0])
    x = block(x, blocks[1])
    x = block(x, blocks[2])
    x = x.reshaped([B, internalT, D])

    // Shift by 17 on both ends → second half (blocks 3..5).
    let left = x[0..., ..<Self.shift, 0...]
    let right = x[0..., (internalT - Self.shift)..., 0...]
    x = MLX.concatenated([left, x, right], axis: 1)
    let nc2 = (internalT + Self.effectiveChunk) / Self.effectiveChunk
    x = x.reshaped([B * nc2, Self.effectiveChunk, D])
    x = block(x, blocks[3])
    x = block(x, blocks[4])
    x = block(x, blocks[5])
    x = x.reshaped([B, internalT + Self.effectiveChunk, D])
    x = x[0..., Self.shift..<(Self.shift + internalT), 0...]

    // Drop the latent slot, keep the 16 new-token positions per latent.
    x = x.reshaped([B * tLat, Self.subChunkSize, D])
    x = x[0..., 1..., 0...]
    x = x.reshaped([B, tLat * Self.sinPerPos, D])

    // WNConv1d (folded) on channels-last [B, T, C].
    let out = MLX.conv1d(x, mappingW, stride: 1, padding: 1) + mappingB  // [B, T·16, 512]
    return out.transposed(0, 2, 1)  // [B, 512, T·16]
  }

  /// Uniform-kernel chunked decode (`decode_chunked`): every call sees a
  /// `chunk + 2·overlap` window of real latents, never zero-padded.
  public func decodeChunked(_ latents: MLXArray, chunkSize: Int, overlap: Int) -> MLXArray {
    let T = latents.shape[2]
    let kernel = chunkSize + 2 * overlap
    precondition(kernel % 2 == 0, "SAME-S needs even kernel (chunk+2·overlap); got \(kernel)")
    if T <= kernel {
      precondition(T % 2 == 0, "SAME-S un-chunked requires even T (= \(T))")
      return self(latents)
    }
    let s = Self.stride
    var pieces: [MLXArray] = []

    // 1) First decode covers output positions [0, chunk+overlap).
    let firstOut = self(latents[.ellipsis, 0..<kernel])
    let validFirst = chunkSize + overlap
    pieces.append(firstOut[.ellipsis, ..<(validFirst * s)])
    var i = validFirst

    // 2) Interior: stride by chunk_size with bilateral overlap context.
    while i + chunkSize + overlap <= T {
      let out = self(latents[.ellipsis, (i - overlap)..<(i + chunkSize + overlap)])
      pieces.append(out[.ellipsis, (overlap * s)..<((overlap + chunkSize) * s)])
      i += chunkSize
    }

    // 3) Last decode covers the remaining (T − i) output positions.
    let remaining = T - i
    if remaining > 0 {
      let lastOut = self(latents[.ellipsis, (T - kernel)..<T])
      let n = lastOut.shape[2]
      pieces.append(lastOut[.ellipsis, (n - remaining * s)...])
    }
    return MLX.concatenated(pieces, axis: -1)
  }

  /// The reference driver's decode dispatch (`sa3_mlx.py` "── 4. Decode ──"):
  /// FP32 upcast, then chunked (`T_lat > kernel`), un-chunked (even `T_lat`),
  /// chunk=2/overlap=2 (odd `T_lat` in `(6, kernel]`), or reflect-pad-one +
  /// trim (tiny odd `T_lat ≤ 6`).
  ///
  /// - Returns: evaluated `[B, 512, T_lat·16]` FP32 audio patches.
  public func decode(_ latents: MLXArray) -> MLXArray {
    let x = latents.asType(.float32)
    let tLat = x.shape[2]
    let chunk = Self.defaultChunkSize, ovl = Self.defaultOverlap
    let kernel = chunk + 2 * ovl
    let patches: MLXArray
    if tLat > kernel {
      patches = decodeChunked(x, chunkSize: chunk, overlap: ovl)
    } else if tLat % 2 == 0 {
      patches = self(x)
    } else if tLat > 6 {
      patches = decodeChunked(x, chunkSize: 2, overlap: 2)
    } else {
      let even = MLX.concatenated([x, x[.ellipsis, (tLat - 1)...]], axis: -1)
      patches = self(even)[.ellipsis, ..<(tLat * Self.stride)]
    }
    MLX.eval(patches)
    return patches
  }

  /// Patched-pretransform unpatch (`patched_decode`):
  /// `rearrange("b (c h) l -> b c (l h)", h=patchSize)` — `[B, c·h, L]` →
  /// `[B, c, L·h]`.
  public static func unpatch(
    _ patches: MLXArray, patchSize: Int = patchSize, channels: Int = audioChannels
  ) -> MLXArray {
    let B = patches.shape[0], CH = patches.shape[1], L = patches.shape[2]
    precondition(CH == channels * patchSize, "expected \(channels * patchSize) channels, got \(CH)")
    return patches.reshaped([B, channels, patchSize, L])
      .transposed(0, 1, 3, 2)
      .reshaped([B, channels, L * patchSize])
  }
}
