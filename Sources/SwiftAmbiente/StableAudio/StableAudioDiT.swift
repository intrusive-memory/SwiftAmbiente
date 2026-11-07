//
//  StableAudioDiT.swift
//  SwiftAmbiente
//
//  Sortie 8 (OPERATION PHANTOM FOLEY, WU2): op-for-op MLX Swift translation of
//  the official Stable Audio 3 Small SFX DiT.
//
//  Reference translated from:
//    Stability-AI/stable-audio-3 → optimized/mlx/models/defs/dit_mlx.py
//      (the `sm-*` loader — NOT dit_mlx_medium.py, which is the differential-attn
//       `medium` DiT). `scripts/sa3_mlx.py::DIT_CHOICES["sm-sfx"]` maps the SFX
//       model to `models.defs.dit_mlx`, so the SFX DiT is standard multi-head
//       attention, not the medium's differential 5×-QKV variant.
//
//  Hyperparameters come from the loaded `model_config.json`
//  `model.diffusion.config` block (see `StableAudioModelConfig.DiffusionConfig`):
//  embed_dim=1024, depth=20, num_heads=16, cond_token_dim=768,
//  global_cond_dim=768, local_add_cond_dim=257, num_memory_tokens=64. Head dim
//  (64) and GLU inner width (4096) are derived; rope partial-dims (32) and the
//  timestep Fourier dim (256) are the reference's family-wide constants.
//
//  Weight keys are consumed verbatim under the `model.model.` prefix exactly as
//  they appear in the SFX `model.safetensors` (no rename pass is needed: unlike
//  the reference's torch-ckpt converter we fetch each tensor by its literal
//  on-disk key). RMSNorm weights are stored as `.gamma`; 1×1 convs are stored
//  `[out, in, 1]` and permuted to MLX's `[out, 1, in]` for `conv1d`. Weights are cast bf/fp32 → fp16
//  to match the reference's default `dit_dtype=fp16` numeric path.
//
//  SCOPE (S8 boundary): this is the velocity network `v(x, t, cross, global)`.
//  The flow-matching pingpong sampler that drives it lives in
//  StableAudioFlowSampler.swift; the SAME-S decoder (latent → waveform) is
//  Sortie 9 and is NOT implemented here.
//

import Foundation
import MLX
import MLXNN

/// Static hyperparameters for the SFX DiT, derived from the model config plus
/// the reference's family-wide constants.
public struct StableAudioDiTConfig: Sendable, Equatable {
  public let ioChannels: Int
  public let embedDim: Int
  public let depth: Int
  public let numHeads: Int
  public let headDim: Int
  public let ffInner: Int
  public let condTokenDim: Int
  public let globalCondDim: Int
  public let localAddCondDim: Int
  public let numMemoryTokens: Int

  // Family-wide constants (not scalar keys in the diffusion block; the reference
  // hardcodes exactly these two).
  public let ropeDims: Int = 32
  public let timestepFeatDim: Int = 256
  public let normEps: Float = 1e-5
  public let qkNormEps: Float = 1e-6

  public init(diffusion d: StableAudioModelConfig.DiffusionConfig) {
    self.ioChannels = d.ioChannels
    self.embedDim = d.embedDim
    self.depth = d.depth
    self.numHeads = d.numHeads
    self.headDim = d.headDim
    self.ffInner = d.ffInner
    self.condTokenDim = d.condTokenDim
    self.globalCondDim = d.globalCondDim
    self.localAddCondDim = d.localAddCondDim
    self.numMemoryTokens = d.numMemoryTokens
  }
}

// MARK: - Per-layer weights

/// One transformer block's weights, cast to fp16.
struct StableAudioDiTLayerWeights {
  let preNorm: MLXArray            // (E,)
  let selfToQKV: MLXArray          // (3E, E)
  let selfToOut: MLXArray          // (E, E)
  let selfQNorm: MLXArray          // (D,)
  let selfKNorm: MLXArray          // (D,)
  let crossAttendNorm: MLXArray    // (E,)
  let crossToQ: MLXArray           // (E, E)
  let crossToKV: MLXArray          // (2E, E)
  let crossToOut: MLXArray         // (E, E)
  let crossQNorm: MLXArray         // (D,)
  let crossKNorm: MLXArray         // (D,)
  let ffNorm: MLXArray             // (E,)
  let ffProjW: MLXArray            // (2*ffInner, E)
  let ffProjB: MLXArray            // (2*ffInner,)
  let ffOutW: MLXArray             // (E, ffInner)
  let ffOutB: MLXArray             // (E,)
  let toScaleShiftGate: MLXArray   // (6E,)
  let localEmbed0W: MLXArray       // (E, localAddCondDim)
  let localEmbed0B: MLXArray       // (E,)
  let localEmbed2W: MLXArray       // (E, E)
  let localEmbed2B: MLXArray       // (E,)
}

/// Full DiT weight set, cast to fp16.
struct StableAudioDiTWeights {
  let preprocessConv: MLXArray     // (io, 1, io) — MLX conv1d layout [out, k, in]
  let postprocessConv: MLXArray    // (io, 1, io)
  let toCondEmbed0: MLXArray       // (E, condTokenDim)
  let toCondEmbed2: MLXArray       // (E, E)
  let toGlobalEmbed0: MLXArray     // (E, globalCondDim)
  let toGlobalEmbed2: MLXArray     // (E, E)
  let toTimestepEmbed0W: MLXArray  // (E, timestepFeatDim)
  let toTimestepEmbed0B: MLXArray  // (E,)
  let toTimestepEmbed2W: MLXArray  // (E, E)
  let toTimestepEmbed2B: MLXArray  // (E,)
  let projectIn: MLXArray          // (E, io)
  let projectOut: MLXArray         // (io, E)
  let memoryTokens: MLXArray       // (numMem, E)
  let globalCondEmbed0W: MLXArray  // (E, E)
  let globalCondEmbed0B: MLXArray  // (E,)
  let globalCondEmbed2W: MLXArray  // (6E, E)
  let globalCondEmbed2B: MLXArray  // (6E,)
  let layers: [StableAudioDiTLayerWeights]
}

/// Loads the DiT weights from an already-loaded safetensors map (the raw
/// upstream `model.model.*` namespace), casting to fp16.
enum StableAudioDiTWeightLoader {
  static let prefix = "model.model."

  static func load(from weights: [String: MLXArray], config: StableAudioDiTConfig) throws
    -> StableAudioDiTWeights
  {
    func fetch(_ key: String) throws -> MLXArray {
      guard let a = weights[prefix + key] else {
        throw StableAudioModelLoaderError.tensorMissing(prefix + key)
      }
      return a.asType(.float16)
    }
    // 1×1 conv stored PyTorch [out, in, 1]; permute to the MLX conv layout
    // [out, 1, in] so it runs through `conv1d` exactly as the reference's
    // `nn.Conv1d(kernel_size=1)` does.
    func fetchConv(_ key: String) throws -> MLXArray {
      try fetch(key).transposed(0, 2, 1)
    }

    var layers: [StableAudioDiTLayerWeights] = []
    layers.reserveCapacity(config.depth)
    for i in 0..<config.depth {
      let p = "transformer.layers.\(i)."
      layers.append(
        StableAudioDiTLayerWeights(
          preNorm: try fetch(p + "pre_norm.gamma"),
          selfToQKV: try fetch(p + "self_attn.to_qkv.weight"),
          selfToOut: try fetch(p + "self_attn.to_out.weight"),
          selfQNorm: try fetch(p + "self_attn.q_norm.gamma"),
          selfKNorm: try fetch(p + "self_attn.k_norm.gamma"),
          crossAttendNorm: try fetch(p + "cross_attend_norm.gamma"),
          crossToQ: try fetch(p + "cross_attn.to_q.weight"),
          crossToKV: try fetch(p + "cross_attn.to_kv.weight"),
          crossToOut: try fetch(p + "cross_attn.to_out.weight"),
          crossQNorm: try fetch(p + "cross_attn.q_norm.gamma"),
          crossKNorm: try fetch(p + "cross_attn.k_norm.gamma"),
          ffNorm: try fetch(p + "ff_norm.gamma"),
          ffProjW: try fetch(p + "ff.ff.0.proj.weight"),
          ffProjB: try fetch(p + "ff.ff.0.proj.bias"),
          ffOutW: try fetch(p + "ff.ff.2.weight"),
          ffOutB: try fetch(p + "ff.ff.2.bias"),
          toScaleShiftGate: try fetch(p + "to_scale_shift_gate"),
          localEmbed0W: try fetch(p + "to_local_embed.0.weight"),
          localEmbed0B: try fetch(p + "to_local_embed.0.bias"),
          localEmbed2W: try fetch(p + "to_local_embed.2.weight"),
          localEmbed2B: try fetch(p + "to_local_embed.2.bias")))
    }

    return StableAudioDiTWeights(
      preprocessConv: try fetchConv("preprocess_conv.weight"),
      postprocessConv: try fetchConv("postprocess_conv.weight"),
      toCondEmbed0: try fetch("to_cond_embed.0.weight"),
      toCondEmbed2: try fetch("to_cond_embed.2.weight"),
      toGlobalEmbed0: try fetch("to_global_embed.0.weight"),
      toGlobalEmbed2: try fetch("to_global_embed.2.weight"),
      toTimestepEmbed0W: try fetch("to_timestep_embed.0.weight"),
      toTimestepEmbed0B: try fetch("to_timestep_embed.0.bias"),
      toTimestepEmbed2W: try fetch("to_timestep_embed.2.weight"),
      toTimestepEmbed2B: try fetch("to_timestep_embed.2.bias"),
      projectIn: try fetch("transformer.project_in.weight"),
      projectOut: try fetch("transformer.project_out.weight"),
      memoryTokens: try fetch("transformer.memory_tokens"),
      globalCondEmbed0W: try fetch("transformer.global_cond_embedder.0.weight"),
      globalCondEmbed0B: try fetch("transformer.global_cond_embedder.0.bias"),
      globalCondEmbed2W: try fetch("transformer.global_cond_embedder.2.weight"),
      globalCondEmbed2B: try fetch("transformer.global_cond_embedder.2.bias"),
      layers: layers)
  }
}

// MARK: - DiT network

/// Op-for-op MLX Swift translation of the reference `DiT` (dit_mlx.py).
///
/// Not `Sendable`: retains `MLXArray` weights. Build and run within one
/// concurrency domain.
public final class StableAudioDiT {
  public let config: StableAudioDiTConfig
  let weights: StableAudioDiTWeights

  /// Timestep ExpoFourierFeatures frequencies (fp32 buffer), matching the
  /// reference `ExpoFourierFeatures(dim=256, min_freq=0.5, max_freq=10000)`:
  /// `freqs = exp(linspace(0,1,half) * (ln max − ln min) + ln min) * 2π`.
  private let timestepFreqs: MLXArray

  init(config: StableAudioDiTConfig, weights: StableAudioDiTWeights) {
    self.config = config
    self.weights = weights
    self.timestepFreqs = StableAudioDiT.expoFourierFreqs(
      dim: config.timestepFeatDim, minFreq: 0.5, maxFreq: 10000.0)
  }

  /// Build a DiT from a loaded safetensors map + parsed model config.
  public static func load(
    weights: [String: MLXArray], modelConfig: StableAudioModelConfig
  ) throws -> StableAudioDiT {
    let cfg = StableAudioDiTConfig(diffusion: modelConfig.diffusion)
    let w = try StableAudioDiTWeightLoader.load(from: weights, config: cfg)
    return StableAudioDiT(config: cfg, weights: w)
  }

  /// `freqs = exp(linspace(0,1,dim/2) * (ln max − ln min) + ln min) * 2 * π`, fp32,
  /// computed with MLX ops in the reference's exact order
  /// (`dit_mlx.py::ExpoFourierFeatures.__init__`) so it is bit-identical: the
  /// Python float constants become fp32 scalars, and `* 2 * math.pi` is two
  /// separate multiplies.
  static func expoFourierFreqs(dim: Int, minFreq: Double, maxFreq: Double) -> MLXArray {
    let half = dim / 2
    let ramp = MLXArray.linspace(Float(0.0), Float(1.0), count: half)
    let logMin = Foundation.log(minFreq), logMax = Foundation.log(maxFreq)
    let freqs = MLX.exp(ramp * Float(logMax - logMin) + Float(logMin))
    let out = (freqs * Float(2)) * Float(Double.pi)
    MLX.eval(out)
    return out
  }

  // MARK: Ops

  /// Linear (no bias): `x @ W.T`, `W` stored `(out, in)`.
  private func linear(_ x: MLXArray, _ w: MLXArray) -> MLXArray {
    MLX.matmul(x, w.transposed())
  }

  /// Linear with bias: the fused `mx.addmm(b, x, W.T)` that MLX's `nn.Linear`
  /// uses (a separate `matmul + b` rounds differently).
  private func linear(_ x: MLXArray, _ w: MLXArray, _ b: MLXArray) -> MLXArray {
    MLX.addMM(b, x, w.transposed())
  }

  /// RMSNorm matching `mx.fast.rms_norm` (fp32 accumulation inside). Weight is
  /// cast to the input dtype so the mixed-dtype call the reference makes
  /// (fp16 weight, occasionally fp32 activations) is well-defined.
  private func rmsNorm(_ x: MLXArray, _ weight: MLXArray, eps: Float) -> MLXArray {
    MLX.rmsNorm(x, weight: weight.asType(x.dtype), eps: eps)
  }

  /// Scaled dot-product attention; softmax in fp32 (matches
  /// `mx.fast.scaled_dot_product_attention`). q,k,v: `(B, H, T, D)`.
  private func sdpa(_ q: MLXArray, _ k: MLXArray, _ v: MLXArray, scale: Float) -> MLXArray {
    MLX.scaledDotProductAttention(queries: q, keys: k, values: v, scale: scale, mask: nil)
  }

  private func selfAttention(_ x: MLXArray, layer: StableAudioDiTLayerWeights) -> MLXArray {
    let s = x.shape
    let B = s[0], T = s[1]
    let H = config.numHeads, D = config.headDim
    let scale = powf(Float(D), -0.5)

    let qkv = linear(x, layer.selfToQKV)          // (B, T, 3E)
    let parts = qkv.split(parts: 3, axis: -1)     // 3 × (B, T, E)
    func toHeads(_ t: MLXArray) -> MLXArray {
      t.reshaped([B, T, H, D]).transposed(0, 2, 1, 3)  // (B, H, T, D)
    }
    var q = toHeads(parts[0])
    var k = toHeads(parts[1])
    let vv = toHeads(parts[2])
    q = rmsNorm(q, layer.selfQNorm, eps: config.qkNormEps)
    k = rmsNorm(k, layer.selfKNorm, eps: config.qkNormEps)
    q = MLX.RoPE(q, dimensions: config.ropeDims, traditional: false, base: 10000.0, scale: 1.0, offset: 0)
    k = MLX.RoPE(k, dimensions: config.ropeDims, traditional: false, base: 10000.0, scale: 1.0, offset: 0)

    let out = sdpa(q, k, vv, scale: scale)        // (B, H, T, D)
    let merged = out.transposed(0, 2, 1, 3).reshaped([B, T, config.embedDim])
    return linear(merged, layer.selfToOut)
  }

  private func crossAttention(_ x: MLXArray, context: MLXArray, layer: StableAudioDiTLayerWeights)
    -> MLXArray
  {
    let sx = x.shape
    let B = sx[0], Tx = sx[1]
    let Tc = context.shape[1]
    let H = config.numHeads, D = config.headDim
    let scale = powf(Float(D), -0.5)

    let q0 = linear(x, layer.crossToQ)            // (B, Tx, E)
    let kv = linear(context, layer.crossToKV)     // (B, Tc, 2E)
    let kvParts = kv.split(parts: 2, axis: -1)    // 2 × (B, Tc, E)
    var q = q0.reshaped([B, Tx, H, D]).transposed(0, 2, 1, 3)
    var k = kvParts[0].reshaped([B, Tc, H, D]).transposed(0, 2, 1, 3)
    let vv = kvParts[1].reshaped([B, Tc, H, D]).transposed(0, 2, 1, 3)
    q = rmsNorm(q, layer.crossQNorm, eps: config.qkNormEps)
    k = rmsNorm(k, layer.crossKNorm, eps: config.qkNormEps)

    let out = sdpa(q, k, vv, scale: scale)
    let merged = out.transposed(0, 2, 1, 3).reshaped([B, Tx, config.embedDim])
    return linear(merged, layer.crossToOut)
  }

  /// GLU feed-forward: proj → split → `x * silu(gate)` → out.
  private func feedForward(_ x: MLXArray, layer: StableAudioDiTLayerWeights) -> MLXArray {
    let p = linear(x, layer.ffProjW, layer.ffProjB)   // (B, T, 2*ffInner)
    let parts = p.split(parts: 2, axis: -1)
    let gated = parts[0] * MLXNN.silu(parts[1])
    return linear(gated, layer.ffOutW, layer.ffOutB)
  }

  /// Per-block local-embed MLP applied to the (zero) local-add-cond:
  /// Linear → SiLU → Linear. With a zero input this is the block's constant bias
  /// path, but it is data-dependent under inpainting.
  private func localEmbed(_ x: MLXArray, layer: StableAudioDiTLayerWeights) -> MLXArray {
    var h = linear(x, layer.localEmbed0W, layer.localEmbed0B)
    h = MLXNN.silu(h)
    return linear(h, layer.localEmbed2W, layer.localEmbed2B)
  }

  private func block(
    _ xIn: MLXArray, context: MLXArray, globalCond: MLXArray, localEmbedPadded: MLXArray,
    layer: StableAudioDiTLayerWeights
  ) -> MLXArray {
    // ss = (to_scale_shift_gate + global_cond)[:, None, :] → split 6
    let ss = (layer.toScaleShiftGate + globalCond).expandedDimensions(axis: 1)  // (B,1,6E)
    let ssParts = ss.split(parts: 6, axis: -1)
    let scaleSelf = ssParts[0], shiftSelf = ssParts[1], gateSelf = ssParts[2]
    let scaleFF = ssParts[3], shiftFF = ssParts[4], gateFF = ssParts[5]

    var x = xIn
    var residual = x
    var h = rmsNorm(x, layer.preNorm, eps: config.normEps)
    h = h * (1 + scaleSelf) + shiftSelf
    h = selfAttention(h, layer: layer)
    h = h * MLX.sigmoid(1 - gateSelf)
    x = h + residual

    x = x + crossAttention(rmsNorm(x, layer.crossAttendNorm, eps: config.normEps),
                           context: context, layer: layer)

    x = x + localEmbedPadded

    residual = x
    var h2 = rmsNorm(x, layer.ffNorm, eps: config.normEps)
    h2 = h2 * (1 + scaleFF) + shiftFF
    h2 = feedForward(h2, layer: layer)
    h2 = h2 * MLX.sigmoid(1 - gateFF)
    x = h2 + residual
    return x
  }

  private func transformer(
    _ xIn: MLXArray, context: MLXArray, globalEmbed: MLXArray, localZeros: MLXArray
  ) -> MLXArray {
    let B = xIn.shape[0]
    let E = config.embedDim
    let nMem = config.numMemoryTokens

    var x = linear(xIn, weights.projectIn)   // (B, T, E)
    let mem = MLX.broadcast(
      weights.memoryTokens.expandedDimensions(axis: 0), to: [B, nMem, E])
    x = MLX.concatenated([mem, x], axis: 1)  // (B, nMem+T, E)

    // global_cond_embedder: Linear → SiLU → Linear → (B, 6E)
    var g = linear(globalEmbed, weights.globalCondEmbed0W, weights.globalCondEmbed0B)
    g = MLXNN.silu(g)
    let globalCond = linear(g, weights.globalCondEmbed2W, weights.globalCondEmbed2B)

    for layer in weights.layers {
      let localEmb = localEmbed(localZeros, layer: layer)              // (B, T, E)
      let pad = MLXArray.zeros([B, nMem, E], dtype: localEmb.dtype)
      let localEmbPadded = MLX.concatenated([pad, localEmb], axis: 1)  // (B, nMem+T, E)
      x = block(x, context: context, globalCond: globalCond,
                localEmbedPadded: localEmbPadded, layer: layer)
    }

    x = x[nMem..., axis: 1]  // drop memory tokens
    return linear(x, weights.projectOut)   // (B, T, io)
  }

  /// ExpoFourier timestep features: `t:(B,) → (B, timestepFeatDim)`.
  private func timestepFeatures(_ t: MLXArray) -> MLXArray {
    let args = t.expandedDimensions(axis: 1) * timestepFreqs  // (B, half)
    return MLX.concatenated([MLX.cos(args), MLX.sin(args)], axis: -1)
  }

  /// Velocity prediction.
  ///
  /// - Parameters:
  ///   - x: `(B, io, T_lat)` latent (channels-first).
  ///   - t: `(B,)` timestep (σ).
  ///   - crossAttnCond: `(B, condTokens, condTokenDim)` cross-attention conditioning.
  ///   - globalCond: `(B, globalCondDim)` global (seconds_total) conditioning.
  ///   - localAddCond: optional `(B, T_lat, localAddCondDim)` inpaint conditioning;
  ///     `nil` for vanilla text-to-audio (a zero tensor is used).
  /// - Returns: `(B, io, T_lat)` velocity.
  public func callAsFunction(
    _ x: MLXArray, t: MLXArray, crossAttnCond: MLXArray, globalCond: MLXArray,
    localAddCond: MLXArray? = nil
  ) -> MLXArray {
    let B = x.shape[0]
    let T = x.shape[x.shape.count - 1]

    // Conditioning projections.
    var c = linear(crossAttnCond, weights.toCondEmbed0)
    c = MLXNN.silu(c)
    let context = linear(c, weights.toCondEmbed2)

    var gp = linear(globalCond, weights.toGlobalEmbed0)
    gp = MLXNN.silu(gp)
    let globalPre = linear(gp, weights.toGlobalEmbed2)

    // Timestep features + MLP.
    var tf = timestepFeatures(t)
    tf = linear(tf, weights.toTimestepEmbed0W, weights.toTimestepEmbed0B)
    tf = MLXNN.silu(tf)
    let tEmbed = linear(tf, weights.toTimestepEmbed2W, weights.toTimestepEmbed2B)

    let globalEmbed = globalPre + tEmbed  // (B, E)

    // preprocess 1×1 conv + residual, on channels-last.
    let xLC = x.transposed(0, 2, 1)  // (B, T, io)
    let xPP = MLX.conv1d(xLC, weights.preprocessConv) + xLC

    // Match the reference: the text-to-audio zero local-add-cond is fp32 (its
    // per-block MLP bias path then promotes the residual stream to fp32 exactly
    // as the Python reference does — MLX type promotion is identical here).
    let local: MLXArray = localAddCond
      ?? MLXArray.zeros([B, T, config.localAddCondDim], dtype: .float32)

    let h = transformer(xPP, context: context, globalEmbed: globalEmbed, localZeros: local)

    let out = MLX.conv1d(h, weights.postprocessConv) + h  // (B, T, io)
    return out.transposed(0, 2, 1)  // (B, io, T)
  }
}
