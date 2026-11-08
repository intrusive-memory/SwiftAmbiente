//
//  AmbientBed.swift
//  SwiftAmbiente
//
//  Loops one generated take to an arbitrary span with equal-power crossfades
//  at each seam, then applies start/end fades. Pure Swift + Accelerate (vDSP /
//  vForce); deterministic; no MLX.
//

import Accelerate
import Foundation

/// Bed filler: turns one take into a bed of any length.
public enum AmbientBed {

  /// Loop `take` to exactly `round(duration × sampleRate)` frames.
  ///
  /// Layout (frames; `N` = take length, `C` = crossfade, `P = N − C`):
  /// the output starts with `take[0..<P]`, then repeats the cycle
  /// `seam ++ take[C..<P]`, where `seam[i] = take[P + i]·cos θᵢ + take[i]·sin θᵢ`
  /// and `θᵢ = (π/2)·(i + ½)/C`. Seams therefore start at frames `k·P` (k ≥ 1).
  /// The result is truncated to the requested length.
  ///
  /// - If the requested length is ≤ the take, the take is trimmed: no seam,
  ///   and `crossfade` is ignored (no clamp warning).
  /// - If `crossfade ≥ take / 2`, it is clamped to `take / 3` with a warning.
  /// - Fades are linear gain ramps per channel: the first frame is exactly 0
  ///   (fade-in) and the last frame is exactly 0 (fade-out). If
  ///   `fadeIn + fadeOut` exceeds the span, both are scaled down proportionally
  ///   with a warning.
  /// - Negative or non-finite times are treated as 0.
  ///
  /// Interleaved multi-channel audio is processed per channel.
  ///
  /// - Returns: The bed (same sample rate and channel count as `take`) and any
  ///   human-readable warnings.
  public static func fill(
    take: PCMAudio,
    duration: TimeInterval,
    crossfade: TimeInterval,
    fadeIn: TimeInterval,
    fadeOut: TimeInterval
  ) -> (PCMAudio, [String]) {
    var warnings: [String] = []
    let sampleRate = take.sampleRate
    let channels = take.channels

    guard sampleRate > 0, channels > 0 else {
      warnings.append(
        "take has an invalid format (sample rate \(sampleRate), \(channels) channels); bed is empty"
      )
      return (PCMAudio(samples: [], sampleRate: sampleRate, channels: channels), warnings)
    }

    let rate = Double(sampleRate)
    let outFrames = frames(duration, rate)
    let takeFrames = take.frameCount

    guard outFrames > 0 else {
      return (PCMAudio(samples: [], sampleRate: sampleRate, channels: channels), warnings)
    }
    guard takeFrames > 0 else {
      warnings.append("take is empty; bed is silence")
      return (
        PCMAudio(
          samples: [Float](repeating: 0, count: outFrames * channels),
          sampleRate: sampleRate, channels: channels),
        warnings
      )
    }

    var out: [Float]
    if outFrames <= takeFrames {
      // Trim: no seam.
      out = Array(take.samples[0..<(outFrames * channels)])
    } else {
      // Loop with equal-power crossfades.
      var crossfadeSeconds = sanitize(crossfade)
      let takeSeconds = take.durationSeconds
      if crossfadeSeconds >= takeSeconds / 2 {
        let clamped = takeSeconds / 3
        warnings.append(
          "crossfade \(format(crossfadeSeconds)) s is at least half the take "
            + "(\(format(takeSeconds)) s); clamped to \(format(clamped)) s")
        crossfadeSeconds = clamped
      }
      let crossfadeFrames = min(frames(crossfadeSeconds, rate), takeFrames / 2)
      out = loop(
        take.samples, takeFrames: takeFrames, channels: channels,
        crossfadeFrames: crossfadeFrames, outFrames: outFrames)
    }

    // Fades.
    var fadeInFrames = frames(fadeIn, rate)
    var fadeOutFrames = frames(fadeOut, rate)
    if fadeInFrames + fadeOutFrames > outFrames {
      let scale = Double(outFrames) / Double(fadeInFrames + fadeOutFrames)
      warnings.append(
        "fadeIn + fadeOut (\(format(sanitize(fadeIn) + sanitize(fadeOut))) s) exceed the bed "
          + "(\(format(Double(outFrames) / rate)) s); scaled to fit")
      fadeInFrames = Int((Double(fadeInFrames) * scale).rounded(.down))
      fadeOutFrames = min(
        Int((Double(fadeOutFrames) * scale).rounded(.down)), outFrames - fadeInFrames)
    }
    if fadeInFrames > 0 {
      let ramp = linearRamp(count: fadeInFrames)  // 0 … (F−1)/F
      applyGain(ramp, to: &out, startFrame: 0, channels: channels)
    }
    if fadeOutFrames > 0 {
      let ramp = Array(linearRamp(count: fadeOutFrames).reversed())  // (F−1)/F … 0
      applyGain(ramp, to: &out, startFrame: outFrames - fadeOutFrames, channels: channels)
    }

    return (PCMAudio(samples: out, sampleRate: sampleRate, channels: channels), warnings)
  }

  // MARK: - Internals

  /// Build the looped buffer (`outFrames × channels` samples).
  private static func loop(
    _ take: [Float], takeFrames: Int, channels: Int, crossfadeFrames c: Int, outFrames: Int
  ) -> [Float] {
    let period = takeFrames - c  // ≥ 1 because c ≤ takeFrames / 2
    let outCount = outFrames * channels

    // Seam block: tail·cos + head·sin, per channel.
    var seam = [Float](repeating: 0, count: c * channels)
    if c > 0 {
      var theta = [Float](repeating: 0, count: c)
      var start = Float.pi / 2 * 0.5 / Float(c)
      var step = Float.pi / 2 / Float(c)
      vDSP_vramp(&start, &step, &theta, 1, vDSP_Length(c))
      var gainOut = [Float](repeating: 0, count: c)
      var gainIn = [Float](repeating: 0, count: c)
      var n = Int32(c)
      vvcosf(&gainOut, theta, &n)
      vvsinf(&gainIn, theta, &n)

      take.withUnsafeBufferPointer { src in
        gainOut.withUnsafeBufferPointer { gOut in
          gainIn.withUnsafeBufferPointer { gIn in
            seam.withUnsafeMutableBufferPointer { dst in
              let tail = src.baseAddress! + period * channels
              let head = src.baseAddress!
              for ch in 0..<channels {
                vDSP_vmma(
                  tail + ch, vDSP_Stride(channels),
                  gOut.baseAddress!, 1,
                  head + ch, vDSP_Stride(channels),
                  gIn.baseAddress!, 1,
                  dst.baseAddress! + ch, vDSP_Stride(channels),
                  vDSP_Length(c))
              }
            }
          }
        }
      }
    }

    // Cycle = seam ++ take[c..<period].
    var cycle = seam
    cycle.append(contentsOf: take[(c * channels)..<(period * channels)])

    var out = [Float]()
    out.reserveCapacity(outCount + cycle.count)
    out.append(contentsOf: take[0..<(period * channels)])
    while out.count < outCount {
      let remaining = outCount - out.count
      if remaining >= cycle.count {
        out.append(contentsOf: cycle)
      } else {
        out.append(contentsOf: cycle[0..<remaining])
      }
    }
    if out.count > outCount { out.removeLast(out.count - outCount) }
    return out
  }

  /// `count` values `i / count`, starting at exactly 0.
  private static func linearRamp(count: Int) -> [Float] {
    var ramp = [Float](repeating: 0, count: count)
    var start: Float = 0
    var step = 1 / Float(count)
    vDSP_vramp(&start, &step, &ramp, 1, vDSP_Length(count))
    return ramp
  }

  /// Multiply `gain.count` frames of `buffer`, starting at `startFrame`, by
  /// `gain` — every channel of an interleaved buffer.
  private static func applyGain(
    _ gain: [Float], to buffer: inout [Float], startFrame: Int, channels: Int
  ) {
    gain.withUnsafeBufferPointer { g in
      buffer.withUnsafeMutableBufferPointer { buf in
        let base = buf.baseAddress! + startFrame * channels
        for ch in 0..<channels {
          vDSP_vmul(
            base + ch, vDSP_Stride(channels),
            g.baseAddress!, 1,
            base + ch, vDSP_Stride(channels),
            vDSP_Length(gain.count))
        }
      }
    }
  }

  private static func sanitize(_ seconds: TimeInterval) -> TimeInterval {
    seconds.isFinite ? max(0, seconds) : 0
  }

  private static func frames(_ seconds: TimeInterval, _ rate: Double) -> Int {
    // Cap far above any real bed so the Int conversion can never trap.
    Int(min((sanitize(seconds) * rate).rounded(), 1e12))
  }

  private static func format(_ seconds: Double) -> String {
    String(format: "%.3f", seconds)
  }
}
