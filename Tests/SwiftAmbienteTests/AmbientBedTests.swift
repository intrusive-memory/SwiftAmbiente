//
//  AmbientBedTests.swift
//  SwiftAmbienteTests
//
//  OPERATION BARFLY WALLPAPER, Sortie 5: `AmbientBed.fill` loops one take to a
//  span. Synthetic takes only; no model.
//

import Foundation
import Testing

@testable import SwiftAmbiente

/// SplitMix64: deterministic, seeded noise for the tests.
private struct SplitMix64 {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
  /// Uniform in [-1, 1).
  mutating func nextSample() -> Float {
    Float(Double(next() >> 11) / Double(1 << 53) * 2 - 1)
  }
}

private enum Takes {
  static let sampleRate = 8_000

  /// Seeded uniform noise at amplitude `amplitude`, interleaved.
  static func noise(seconds: Double, channels: Int, seed: UInt64, amplitude: Float = 0.5)
    -> PCMAudio
  {
    var rng = SplitMix64(seed: seed)
    let count = Int((seconds * Double(sampleRate)).rounded()) * channels
    let samples = (0..<count).map { _ in rng.nextSample() * amplitude }
    return PCMAudio(samples: samples, sampleRate: sampleRate, channels: channels)
  }

  /// Stereo sine: L = sin, R = −cos (different phase per channel). Pick
  /// `frequency × seconds` integral so the take holds whole cycles.
  static func stereoSine(frequency: Double, seconds: Double, amplitude: Float) -> PCMAudio {
    let frames = Int((seconds * Double(sampleRate)).rounded())
    var samples = [Float](repeating: 0, count: frames * 2)
    for i in 0..<frames {
      let phase = 2 * Double.pi * frequency * Double(i) / Double(sampleRate)
      samples[2 * i] = amplitude * Float(sin(phase))
      samples[2 * i + 1] = -amplitude * Float(cos(phase))
    }
    return PCMAudio(samples: samples, sampleRate: sampleRate, channels: 2)
  }

  /// Constant `value` on every channel.
  static func dc(seconds: Double, channels: Int, value: Float) -> PCMAudio {
    let count = Int((seconds * Double(sampleRate)).rounded()) * channels
    return PCMAudio(
      samples: [Float](repeating: value, count: count), sampleRate: sampleRate,
      channels: channels)
  }
}

private func channel(_ audio: PCMAudio, _ ch: Int) -> [Float] {
  stride(from: ch, to: audio.samples.count, by: audio.channels).map { audio.samples[$0] }
}

private func rms<C: Collection>(_ xs: C) -> Double where C.Element == Float {
  let sum = xs.reduce(0.0) { $0 + Double($1) * Double($1) }
  return (sum / Double(xs.count)).squareRoot()
}

@Suite("AmbientBed.fill")
struct AmbientBedTests {

  // MARK: 1. Exact length

  @Test(
    "output is exactly round(duration × sampleRate) frames",
    arguments: [0.5, 1.0, 2.5, 7.3337, 30.0])
  func exactLength(duration: Double) {
    let take = Takes.noise(seconds: 1.0, channels: 2, seed: 1)
    let (bed, _) = AmbientBed.fill(
      take: take, duration: duration, crossfade: 0.25, fadeIn: 0.1, fadeOut: 0.2)
    let expected = Int((duration * Double(Takes.sampleRate)).rounded())
    #expect(bed.frameCount == expected)
    #expect(bed.samples.count == expected * 2)
    #expect(bed.sampleRate == take.sampleRate)
    #expect(bed.channels == 2)
  }

  // MARK: 2. Seam continuity

  @Test("max sample step at each seam is ≤ −40 dBFS for a whole-cycle sine take")
  func seamContinuity() {
    // 5 Hz × 1 s = 5 whole cycles: the take loops cleanly on its own, so any
    // step is the crossfade's doing.
    let take = Takes.stereoSine(frequency: 5, seconds: 1.0, amplitude: 0.5)
    let crossfade = 0.25
    let (bed, warnings) = AmbientBed.fill(
      take: take, duration: 5.0, crossfade: crossfade, fadeIn: 0, fadeOut: 0)
    #expect(warnings.isEmpty)

    let threshold = Float(pow(10.0, -40.0 / 20.0))  // 0.01
    let c = Int(crossfade * Double(Takes.sampleRate))
    let period = take.frameCount - c
    let seamStarts = Array(stride(from: period, to: bed.frameCount, by: period))
    #expect(seamStarts.count == 6)

    for ch in 0..<2 {
      let x = channel(bed, ch)
      for s in seamStarts {
        let lo = max(1, s - 2)
        let hi = min(x.count, s + c + 2)
        var maxStep: Float = 0
        for i in lo..<hi { maxStep = max(maxStep, abs(x[i] - x[i - 1])) }
        #expect(maxStep <= threshold, "channel \(ch) seam at \(s): step \(maxStep)")
      }
    }
  }

  // MARK: 3. RMS across a seam

  @Test("RMS across each seam is within ±1 dB of the take RMS for a noise take")
  func seamRMS() {
    let take = Takes.noise(seconds: 2.0, channels: 2, seed: 0xA11CE)
    let crossfade = 0.5
    let (bed, warnings) = AmbientBed.fill(
      take: take, duration: 6.0, crossfade: crossfade, fadeIn: 0, fadeOut: 0)
    #expect(warnings.isEmpty)

    let c = Int(crossfade * Double(Takes.sampleRate))
    let period = take.frameCount - c
    let seamStarts = Array(stride(from: period, to: bed.frameCount - c, by: period))
    #expect(seamStarts.count >= 2)

    for ch in 0..<2 {
      let takeRMS = rms(channel(take, ch))
      let x = channel(bed, ch)
      for s in seamStarts {
        let seamRMS = rms(x[s..<(s + c)])
        let db = 20 * log10(seamRMS / takeRMS)
        #expect(abs(db) <= 1.0, "channel \(ch) seam at \(s): \(db) dB")
      }
    }
  }

  // MARK: 4. Fades

  @Test("fade-in starts at 0 and fade-out ends at 0")
  func fadesReachZero() {
    let take = Takes.dc(seconds: 1.0, channels: 2, value: 0.5)
    let (bed, warnings) = AmbientBed.fill(
      take: take, duration: 3.0, crossfade: 0.25, fadeIn: 0.5, fadeOut: 1.0)
    #expect(warnings.isEmpty)

    let last = bed.frameCount - 1
    for ch in 0..<2 {
      let x = channel(bed, ch)
      #expect(x[0] == 0)
      #expect(x[last] == 0)
      // Fade-in ramps up monotonically inside the first (seam-free) segment.
      let fadeInFrames = Int(0.5 * Double(Takes.sampleRate))
      for i in 1..<fadeInFrames { #expect(x[i] >= x[i - 1]) }
      #expect(x[fadeInFrames] == 0.5)
    }
  }

  @Test("trim path (duration ≤ take) also fades to 0 at both ends")
  func trimFades() {
    let take = Takes.dc(seconds: 2.0, channels: 1, value: 0.5)
    let (bed, warnings) = AmbientBed.fill(
      take: take, duration: 1.0, crossfade: 5.0, fadeIn: 0.1, fadeOut: 0.1)
    #expect(warnings.isEmpty)  // no seam → no crossfade clamp
    #expect(bed.frameCount == Takes.sampleRate)
    #expect(bed.samples.first == 0)
    #expect(bed.samples.last == 0)
    #expect(bed.samples[Takes.sampleRate / 2] == 0.5)
  }

  @Test("fades longer than the span are scaled to fit")
  func fadesScaleToFit() {
    let take = Takes.dc(seconds: 2.0, channels: 2, value: 0.5)
    let (bed, warnings) = AmbientBed.fill(
      take: take, duration: 1.0, crossfade: 0.25, fadeIn: 2.0, fadeOut: 2.0)
    #expect(warnings.contains { $0.contains("fadeIn + fadeOut") })
    #expect(bed.frameCount == Takes.sampleRate)
    let x = channel(bed, 1)
    #expect(x.first == 0)
    #expect(x.last == 0)
    #expect((x.max() ?? 0) > 0.45)
  }

  // MARK: 5. Crossfade clamp

  @Test("crossfade ≥ take/2 is clamped to take/3 with a warning")
  func crossfadeClampWarns() {
    let take = Takes.noise(seconds: 3.0, channels: 2, seed: 42)
    let (clamped, warnings) = AmbientBed.fill(
      take: take, duration: 10.0, crossfade: 2.0, fadeIn: 0.5, fadeOut: 0.5)
    #expect(warnings.count == 1)
    #expect(warnings.first?.contains("crossfade") == true)
    #expect(clamped.frameCount == 10 * Takes.sampleRate)

    // The clamp lands exactly on take/3 = 1.0 s.
    let (explicit, explicitWarnings) = AmbientBed.fill(
      take: take, duration: 10.0, crossfade: 1.0, fadeIn: 0.5, fadeOut: 0.5)
    #expect(explicitWarnings.isEmpty)
    #expect(clamped.samples == explicit.samples)
  }

  @Test("crossfade below take/2 is not clamped")
  func crossfadeNoClamp() {
    let take = Takes.noise(seconds: 3.0, channels: 1, seed: 7)
    let (_, warnings) = AmbientBed.fill(
      take: take, duration: 10.0, crossfade: 1.4, fadeIn: 0.5, fadeOut: 0.5)
    #expect(warnings.isEmpty)
  }
}
