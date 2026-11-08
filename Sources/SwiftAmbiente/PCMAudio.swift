//
//  PCMAudio.swift
//  SwiftAmbiente
//
//  In-memory interleaved PCM audio with a WAV reader. The inverse of
//  `WAVWriter`: `PCMAudio(wavData:)` parses a 16-bit PCM WAV into Float samples,
//  and `wavData()` re-encodes through `WAVWriter`.
//

import Foundation

/// Interleaved floating-point PCM audio.
///
/// Samples are interleaved (`L,R,L,R,…` for stereo). Samples decoded from a
/// 16-bit WAV are scaled by `1/32767` (the inverse of ``WAVWriter``), so they
/// lie in `-1.00003 ... 1.0`.
public struct PCMAudio: Sendable, Equatable {
  /// Samples per second per channel (e.g. 44_100).
  public let sampleRate: Int

  /// Channel count (1 = mono, 2 = stereo).
  public let channels: Int

  /// Interleaved samples. `samples.count` is a multiple of ``channels``.
  public let samples: [Float]

  /// Number of frames (samples per channel).
  public var frameCount: Int { channels > 0 ? samples.count / channels : 0 }

  /// Duration in seconds.
  public var durationSeconds: Double {
    sampleRate > 0 ? Double(frameCount) / Double(sampleRate) : 0
  }

  /// Errors raised while decoding a WAV buffer.
  public enum DecodeError: Error, LocalizedError, Sendable, Equatable {
    /// The buffer is shorter than a minimal WAV header.
    case tooShort(Int)
    /// The RIFF/WAVE container tags are missing.
    case notRIFFWAVE
    /// A required chunk (`fmt ` or `data`) is missing.
    case missingChunk(String)
    /// The audio is not 16-bit integer PCM.
    case unsupportedFormat(format: Int, bitsPerSample: Int)
    /// The header declares an invalid sample rate or channel count.
    case invalidHeader(String)

    public var errorDescription: String? {
      switch self {
      case .tooShort(let n): return "WAV is \(n) bytes; too short for a WAV header"
      case .notRIFFWAVE: return "Not a RIFF/WAVE file"
      case .missingChunk(let id): return "WAV is missing its '\(id)' chunk"
      case .unsupportedFormat(let f, let b):
        return "Unsupported WAV encoding (format \(f), \(b) bits); only 16-bit PCM is supported"
      case .invalidHeader(let detail): return "Invalid WAV header: \(detail)"
      }
    }
  }

  /// Create audio from interleaved samples.
  public init(samples: [Float], sampleRate: Int, channels: Int) {
    self.samples = samples
    self.sampleRate = sampleRate
    self.channels = channels
  }

  /// Decode a 16-bit PCM WAV (`WAVE_FORMAT_PCM`) buffer.
  ///
  /// Walks the RIFF chunk list, so files with extra chunks (e.g. `LIST`) before
  /// `data` are accepted. A `data` chunk whose declared size runs past the end
  /// of the buffer is truncated to the bytes present; a trailing partial frame
  /// is dropped.
  public init(wavData: Data) throws {
    let bytes = [UInt8](wavData)
    guard bytes.count >= 12 else { throw DecodeError.tooShort(bytes.count) }

    func tag(_ o: Int) -> String { String(decoding: bytes[o..<(o + 4)], as: UTF8.self) }
    func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
    func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

    guard tag(0) == "RIFF", tag(8) == "WAVE" else { throw DecodeError.notRIFFWAVE }

    var format: (audioFormat: Int, channels: Int, sampleRate: Int, bits: Int)?
    var dataRange: Range<Int>?
    var offset = 12
    while offset + 8 <= bytes.count {
      let id = tag(offset)
      let size = u32(offset + 4)
      let body = offset + 8
      switch id {
      case "fmt ":
        guard size >= 16, body + 16 <= bytes.count else {
          throw DecodeError.invalidHeader("fmt chunk is \(size) bytes")
        }
        format = (u16(body), u16(body + 2), u32(body + 4), u16(body + 14))
      case "data":
        dataRange = body..<min(body + size, bytes.count)
      default:
        break
      }
      if dataRange != nil && format != nil { break }
      // Chunks are word-aligned: odd-sized chunks carry one pad byte.
      offset = body + size + (size & 1)
    }

    guard let format else { throw DecodeError.missingChunk("fmt ") }
    guard let dataRange else { throw DecodeError.missingChunk("data") }
    guard format.audioFormat == 1, format.bits == 16 else {
      throw DecodeError.unsupportedFormat(format: format.audioFormat, bitsPerSample: format.bits)
    }
    guard format.channels > 0 else { throw DecodeError.invalidHeader("0 channels") }
    guard format.sampleRate > 0 else { throw DecodeError.invalidHeader("sample rate 0") }

    let frameCount = dataRange.count / (2 * format.channels)
    let sampleCount = frameCount * format.channels
    var samples = [Float](repeating: 0, count: sampleCount)
    var o = dataRange.lowerBound
    for i in 0..<sampleCount {
      let v = Int16(bitPattern: UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8)
      samples[i] = Float(v) / 32_767.0
      o += 2
    }

    self.sampleRate = format.sampleRate
    self.channels = format.channels
    self.samples = samples
  }

  /// Encode as a 16-bit PCM WAV via ``WAVWriter``.
  public func wavData() -> Data {
    WAVWriter.encode(samples: samples, sampleRate: sampleRate, channels: channels)
  }
}
