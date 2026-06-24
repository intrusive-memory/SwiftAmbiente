//
//  WAVWriter.swift
//  SwiftAmbiente
//
//  Minimal PCM WAV encoder. Converts interleaved Float samples in [-1, 1] to a
//  16-bit little-endian PCM WAV container.
//

import Foundation

/// Encodes interleaved floating-point audio into a 16-bit PCM WAV container.
public enum WAVWriter {
  /// Encode interleaved Float samples (`-1.0 ... 1.0`) into WAV data.
  ///
  /// - Parameters:
  ///   - samples: Interleaved samples. For stereo, layout is L,R,L,R,…
  ///   - sampleRate: Samples per second per channel (e.g. 44_100).
  ///   - channels: Channel count (1 = mono, 2 = stereo).
  /// - Returns: A complete `.wav` byte buffer.
  public static func encode(samples: [Float], sampleRate: Int, channels: Int) -> Data {
    let bitsPerSample = 16
    let bytesPerSample = bitsPerSample / 8
    let blockAlign = channels * bytesPerSample
    let byteRate = sampleRate * blockAlign
    let dataSize = samples.count * bytesPerSample
    let riffChunkSize = 36 + dataSize

    var data = Data(capacity: 44 + dataSize)

    func appendLE<T: FixedWidthInteger>(_ value: T) {
      var v = value.littleEndian
      withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    // RIFF header
    data.append(contentsOf: Array("RIFF".utf8))
    appendLE(UInt32(riffChunkSize))
    data.append(contentsOf: Array("WAVE".utf8))

    // fmt  chunk
    data.append(contentsOf: Array("fmt ".utf8))
    appendLE(UInt32(16))  // PCM fmt chunk size
    appendLE(UInt16(1))  // audio format = PCM
    appendLE(UInt16(channels))
    appendLE(UInt32(sampleRate))
    appendLE(UInt32(byteRate))
    appendLE(UInt16(blockAlign))
    appendLE(UInt16(bitsPerSample))

    // data chunk
    data.append(contentsOf: Array("data".utf8))
    appendLE(UInt32(dataSize))
    for sample in samples {
      let clamped = max(-1.0, min(1.0, sample))
      let scaled = Int16((clamped * 32_767.0).rounded())
      appendLE(scaled)
    }

    return data
  }
}
