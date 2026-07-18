//
//  StableAudioFlowSampler.swift
//  SwiftAmbiente
//
//  Sortie 8 (OPERATION PHANTOM FOLEY, WU2): op-for-op MLX Swift translation of
//  the flow-matching ping-pong sampler.
//
//  Reference translated from:
//    Stability-AI/stable-audio-3 → optimized/mlx/models/defs/sa3_pipeline.py
//      · logsnr_shift          (default sampling schedule warp)
//      · build_pingpong_schedule
//      · sample_flow_pingpong  (rf_denoiser ping-pong update)
//
//  PARITY CRUX — the PRNG. The reference seeds via `mx.random`: the sampler is
//  invoked with `seed = user_seed + 1`, does `key = mx.random.key(seed)`, and per
//  step draws `sub` from `mx.random.split(key)` then `mx.random.normal(shape,
//  key=sub)`. MLX Swift's `MLXRandom` is the SAME Threefry PRNG with the SAME
//  key/split/normal semantics, so translating those calls one-for-one reproduces
//  the reference's exact noise sequence for a given seed. The initial noise
//  (drawn with `key(user_seed)`) lives in StableAudioLatentGenerator.
//

import Foundation
import MLX
import MLXRandom

/// The flow-matching ping-pong sampler + its schedule.
public enum StableAudioFlowSampler {

  /// Default sampling-schedule warp for SA3 (`logsnr_shift`, rate 0 → no
  /// sequence-length dependence). Maps `t∈[0,1]` through log-SNR space:
  /// `t_out = sigmoid(-(logsnr_end − t·(logsnr_end − anchor)))`, endpoints
  /// preserved exactly. Operates on Swift `Float` (the schedule is tiny).
  static func logsnrShift(
    _ t: Float, anchorLogsnr: Float = -6.2, logsnrEnd: Float = 2.0
  ) -> Float {
    if t <= 0 { return 0 }
    if t >= 1 { return 1 }
    let logsnr = logsnrEnd - t * (logsnrEnd - anchorLogsnr)
    return 1.0 / (1.0 + expf(logsnr))  // sigmoid(-logsnr)
  }

  /// Linear `t` from `sigmaMax → 0` over `steps+1` points, optionally warped by
  /// `logsnrShift` with the start re-anchored to `sigmaMax`. Returns `steps+1`
  /// fp32 values (`sigmas[last] == 0`), mirroring `build_pingpong_schedule`.
  public static func buildPingpongSchedule(
    steps: Int, sigmaMax: Float = 1.0, useLogsnrShift: Bool = true
  ) -> [Float] {
    precondition(steps >= 1, "steps must be ≥ 1")
    let n = steps + 1
    // linspace(sigmaMax, 0, n): endpoints inclusive.
    var t = [Float](repeating: 0, count: n)
    let denom = Float(n - 1)
    for i in 0..<n {
      t[i] = sigmaMax + (0.0 - sigmaMax) * (Float(i) / denom)
    }
    if useLogsnrShift {
      for i in 0..<n { t[i] = logsnrShift(t[i]) }
      // Re-anchor the start to sigmaMax (matches the reference's concat).
      t[0] = sigmaMax
    }
    return t
  }

  /// Ping-pong sampler for rf_denoiser models.
  ///
  /// Per step `i` (`i = 0 .. num_steps-1`):
  /// ```
  /// denoised = x − t_curr · v(x, t_curr)
  /// x_next   = (1 − t_next) · denoised + t_next · noise   // if not last & t_next>0
  ///          = denoised                                   // otherwise
  /// ```
  ///
  /// - Parameters:
  ///   - x: initial noise latent `(B, io, T_lat)`.
  ///   - sigmas: the schedule from ``buildPingpongSchedule(steps:sigmaMax:useLogsnrShift:)``.
  ///   - seed: the sampler PRNG seed (the reference passes `user_seed + 1`).
  ///   - modelFn: `(x, t) → v` velocity prediction (CFG is composed by the caller).
  /// - Returns: the sampled latent `(B, io, T_lat)`.
  public static func sampleFlowPingpong(
    x xInit: MLXArray, sigmas: [Float], seed: UInt64,
    modelFn: (MLXArray, MLXArray) -> MLXArray
  ) -> MLXArray {
    var x = xInit
    var key = MLXRandom.key(seed)
    let numSteps = sigmas.count - 1
    let B = x.shape[0]

    for i in 0..<numSteps {
      let tCurr = sigmas[i]
      let tNext = sigmas[i + 1]

      // t_tensor = t_curr * ones((B,), dtype=x.dtype)  (fp32 scalar × fp16 ones → fp32)
      let tTensor = MLXArray(tCurr) * MLXArray.ones([B], dtype: x.dtype)
      let v = modelFn(x, tTensor)

      let denoised = x - MLXArray(tCurr).asType(x.dtype) * v

      if i < numSteps - 1 && tNext > 0.0 {
        let (nextKey, sub) = MLXRandom.split(key: key)
        key = nextKey
        let noise = MLXRandom.normal(x.shape, dtype: x.dtype, key: sub)
        x = MLXArray(1.0 - tNext).asType(x.dtype) * denoised
          + MLXArray(tNext).asType(x.dtype) * noise
      } else {
        x = denoised
      }
      MLX.eval(x)
    }
    return x
  }
}
