//
//  GoldenAudioComparison.swift
//  SwiftAmbienteTests
//
//  Sortie 9 (OPERATION PHANTOM FOLEY, WU2): WAV-contract parsing + the spectral/RMS
//  distance used by the golden-output parity gate. The metric definitions here
//  are the ones recorded in Sources/SwiftAmbiente/StableAudio/STRATEGY.md
//  ("Sortie 9 parity tolerance"); change one only together with the other.
//

import Foundation
import MLX

/// A parsed canonical 44-byte-header 16-bit PCM WAV.
struct PCMWAV {
  let sampleRate: Int
  let channels: Int
  let bitsPerSample: Int
  /// De-interleaved samples, one `[Float]` per channel, scaled by `1/32767`
  /// (the reference's `save_wav` scale).
  let channelSamples: [[Float]]
  var frames: Int { channelSamples.first?.count ?? 0 }

  enum ParseError: Error, CustomStringConvertible {
    case tooShort(Int)
    case badTag(String)
    case notPCM16(format: Int, bits: Int)
    case sizeMismatch(declared: Int, actual: Int)
    var description: String {
      switch self {
      case .tooShort(let n): return "WAV is \(n) bytes; needs a 44-byte header + data"
      case .badTag(let t): return "WAV header tag mismatch: \(t)"
      case .notPCM16(let f, let b): return "WAV is not 16-bit PCM (format \(f), \(b) bits)"
      case .sizeMismatch(let d, let a): return "WAV data size \(d) ≠ payload \(a)"
      }
    }
  }

  /// Parse + validate the canonical 44-byte WAV header (RIFF/WAVE, `fmt ` PCM
  /// chunk of size 16, `data` chunk at offset 36) — the WAV contract.
  init(data: Data) throws {
    let bytes = [UInt8](data)
    guard bytes.count > 44 else { throw ParseError.tooShort(bytes.count) }
    func tag(_ o: Int) -> String { String(decoding: bytes[o..<(o + 4)], as: UTF8.self) }
    func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
    func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
    guard tag(0) == "RIFF" else { throw ParseError.badTag("RIFF@0=\(tag(0))") }
    guard tag(8) == "WAVE" else { throw ParseError.badTag("WAVE@8=\(tag(8))") }
    guard tag(12) == "fmt ", u32(16) == 16 else { throw ParseError.badTag("fmt @12=\(tag(12))") }
    guard tag(36) == "data" else { throw ParseError.badTag("data@36=\(tag(36))") }
    let format = u16(20)
    let bits = u16(34)
    guard format == 1, bits == 16 else { throw ParseError.notPCM16(format: format, bits: bits) }
    let dataSize = u32(40)
    guard dataSize == bytes.count - 44 else {
      throw ParseError.sizeMismatch(declared: dataSize, actual: bytes.count - 44)
    }
    let channels = u16(22)
    sampleRate = u32(24)
    self.channels = channels
    bitsPerSample = bits
    let frameCount = dataSize / (2 * channels)
    var chans = [[Float]](repeating: [Float](repeating: 0, count: frameCount), count: channels)
    for f in 0..<frameCount {
      for c in 0..<channels {
        let o = 44 + 2 * (f * channels + c)
        let v = Int16(bitPattern: UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8)
        chans[c][f] = Float(v) / 32767.0
      }
    }
    channelSamples = chans
  }
}

/// Spectral/RMS distance between a candidate and a reference stereo signal.
///
/// Analysis (fixed; see STRATEGY.md): Hann-windowed STFT, frame 2048, hop 1024
/// (≈46 ms / 23 ms at 44.1 kHz), power summed into 32 log-spaced bands from
/// 40 Hz to 20 kHz, `dB = 10·log10(E + 1e-10)`. The dB metrics skip reference
/// frames below ``silenceFloorDBFS``. Each figure is the worst case over the
/// channels.
struct AudioSpectralDelta: CustomStringConvertible {
  /// `|RMS_c − RMS_r| / RMS_r` — overall loudness error (fraction).
  let rmsRelative: Double
  /// Mean over bands of `|mean_t dB_c − mean_t dB_r|` — long-term spectral
  /// shape (timbre) error, in dB.
  let ltasDB: Double
  /// Mean over (frame, band) of `|dB_c − dB_r|` — time-frequency structure
  /// error, in dB.
  let spectrogramDB: Double
  /// Pearson correlation of the per-frame RMS envelopes (1 = identical temporal
  /// dynamics).
  let envelopeCorrelation: Double

  var description: String {
    String(
      format: "rmsRel=%.4f ltas=%.3f dB spectrogram=%.3f dB envCorr=%.4f",
      rmsRelative, ltasDB, spectrogramDB, envelopeCorrelation)
  }

  static let frameLength = 2048
  static let hop = 1024
  static let bandCount = 32
  static let minHz = 40.0
  static let maxHz = 20_000.0
  /// Reference frames quieter than this (≈1 LSB of 16-bit PCM, −90.3 dBFS) are
  /// excluded from the dB-averaged metrics (`ltasDB`, `spectrogramDB`).
  static let silenceFloorDBFS = -90.0
  static let silenceFloorLinear = pow(10.0, silenceFloorDBFS / 20.0)

  static func compare(candidate: PCMWAV, reference: PCMWAV) -> AudioSpectralDelta {
    precondition(candidate.channels == reference.channels, "channel count mismatch")
    let n = min(candidate.frames, reference.frames)
    var rmsRel = 0.0
    var ltas = 0.0
    var spec = 0.0
    var corr = 1.0
    for c in 0..<reference.channels {
      let a = Array(candidate.channelSamples[c][0..<n])
      let b = Array(reference.channelSamples[c][0..<n])
      let ra = rms(a)
      let rb = rms(b)
      rmsRel = max(rmsRel, abs(ra - rb) / rb)
      let da = bandDB(a, sampleRate: reference.sampleRate)
      let db = bandDB(b, sampleRate: reference.sampleRate)
      let bands = da.first?.count ?? 0
      // dB metrics only over frames the 16-bit reference can actually resolve.
      // In digital near-silence (≈1 LSB) a one-LSB difference reads as a 15–28 dB
      // "error" and dominates a mean of dB values (see STRATEGY.md, cfg 1.0 note).
      let refFrameRMS = frameRMS(b)
      var active = refFrameRMS.indices.filter { refFrameRMS[$0] >= silenceFloorLinear }
      if active.isEmpty { active = Array(refFrameRMS.indices) }
      let frames = Double(active.count)
      var l = 0.0
      for k in 0..<bands {
        var ma = 0.0
        var mb = 0.0
        for t in active {
          ma += da[t][k]
          mb += db[t][k]
        }
        l += abs(ma - mb) / frames
      }
      ltas = max(ltas, l / Double(bands))
      var s = 0.0
      for t in active { for k in 0..<bands { s += abs(da[t][k] - db[t][k]) } }
      spec = max(spec, s / (frames * Double(bands)))
      corr = min(corr, pearson(frameRMS(a), refFrameRMS))
    }
    return AudioSpectralDelta(
      rmsRelative: rmsRel, ltasDB: ltas, spectrogramDB: spec, envelopeCorrelation: corr)
  }

  static func rms(_ x: [Float]) -> Double {
    var s = 0.0
    for v in x { s += Double(v) * Double(v) }
    return (s / Double(max(x.count, 1))).squareRoot()
  }

  static func frameCount(_ n: Int) -> Int { n < frameLength ? 0 : 1 + (n - frameLength) / hop }

  static func frameRMS(_ x: [Float]) -> [Double] {
    (0..<frameCount(x.count)).map { t in rms(Array(x[(t * hop)..<(t * hop + frameLength)])) }
  }

  static func pearson(_ a: [Double], _ b: [Double]) -> Double {
    let n = Double(a.count)
    let ma = a.reduce(0, +) / n
    let mb = b.reduce(0, +) / n
    var sab = 0.0
    var saa = 0.0
    var sbb = 0.0
    for i in 0..<a.count {
      sab += (a[i] - ma) * (b[i] - mb)
      saa += (a[i] - ma) * (a[i] - ma)
      sbb += (b[i] - mb) * (b[i] - mb)
    }
    return sab / (saa * sbb).squareRoot()
  }

  /// `[frame][band]` band energies in dB.
  static func bandDB(_ x: [Float], sampleRate: Int) -> [[Double]] {
    let frames = frameCount(x.count)
    var mat = [Float](repeating: 0, count: frames * frameLength)
    var window = [Float](repeating: 0, count: frameLength)
    for i in 0..<frameLength {
      window[i] = Float(0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / Double(frameLength)))
    }
    for t in 0..<frames {
      for i in 0..<frameLength { mat[t * frameLength + i] = x[t * hop + i] * window[i] }
    }
    let spectrum = MLX.rfft(MLXArray(mat, [frames, frameLength]), axis: -1, stream: .cpu)
    let power = MLX.square(MLX.abs(spectrum, stream: .cpu), stream: .cpu).asType(.float32)  // (frames, bins)
    let bins = frameLength / 2 + 1
    // Band assignment matrix (bins × bands).
    var assign = [Float](repeating: 0, count: bins * bandCount)
    let ratio = maxHz / minHz
    for k in 0..<bins {
      let hz = Double(k) * Double(sampleRate) / Double(frameLength)
      guard hz >= minHz, hz < maxHz else { continue }
      let band = Int(Double(bandCount) * log(hz / minHz) / log(ratio))
      assign[k * bandCount + min(band, bandCount - 1)] = 1
    }
    let energies = MLX.matmul(power, MLXArray(assign, [bins, bandCount]), stream: .cpu)
    let flat = energies.asArray(Float.self)
    return (0..<frames).map { t in
      (0..<bandCount).map { k in 10.0 * log10(Double(flat[t * bandCount + k]) + 1e-10) }
    }
  }
}
