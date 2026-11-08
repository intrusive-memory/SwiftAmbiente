//
//  PCMAudioTests.swift
//  SwiftAmbienteTests
//
//  OPERATION BARFLY WALLPAPER, Sortie 4: the public WAV reader round-trips
//  `WAVWriter` output.
//

import Foundation
import Testing

@testable import SwiftAmbiente

@Suite("PCMAudio")
struct PCMAudioTests {

  /// One 16-bit quantization step at the `1/32767` scale.
  private static let lsb: Float = 1.0 / 32_767.0

  @Test("decodes WAVWriter stereo output to the same samples")
  func roundTripStereo() throws {
    let samples: [Float] = [0, 0.5, -0.5, 1, -1, 0.25, -0.25, 0.123, -0.987, 0.001]
    let wav = WAVWriter.encode(samples: samples, sampleRate: 44_100, channels: 2)

    let audio = try PCMAudio(wavData: wav)
    #expect(audio.sampleRate == 44_100)
    #expect(audio.channels == 2)
    #expect(audio.frameCount == samples.count / 2)
    #expect(audio.samples.count == samples.count)
    for (decoded, original) in zip(audio.samples, samples) {
      #expect(abs(decoded - original) <= Self.lsb)
    }
  }

  @Test("wavData() re-encodes byte-identically")
  func reencodeIsIdentical() throws {
    let samples = (0..<4_410).map { Float(sin(Double($0) * 0.05)) * 0.8 }
    let wav = WAVWriter.encode(samples: samples, sampleRate: 22_050, channels: 1)

    let audio = try PCMAudio(wavData: wav)
    #expect(audio.sampleRate == 22_050)
    #expect(audio.channels == 1)
    #expect(abs(audio.durationSeconds - 0.2) < 1e-9)
    #expect(audio.wavData() == wav)
  }

  @Test("procedural generator output parses")
  func parsesProceduralOutput() async throws {
    let wav = try await ProceduralAmbienteGenerator().generate(
      prompt: "rain", settings: GenerationSettings(durationSeconds: 0.5))
    let audio = try PCMAudio(wavData: wav)
    #expect(audio.sampleRate == AmbienteConfig.default.sampleRate)
    #expect(audio.channels == AmbienteConfig.default.channelCount)
    #expect(audio.frameCount == Int((0.5 * Double(audio.sampleRate)).rounded()))
  }

  @Test("skips unknown chunks before data")
  func skipsUnknownChunks() throws {
    let wav = WAVWriter.encode(samples: [0.5, -0.5], sampleRate: 8_000, channels: 1)
    // Splice an odd-sized LIST chunk (with its pad byte) between fmt and data.
    var spliced = Data(wav[0..<36])
    spliced.append(contentsOf: Array("LIST".utf8))
    spliced.append(contentsOf: [3, 0, 0, 0, 0x61, 0x62, 0x63, 0x00])
    spliced.append(wav[36...])

    let audio = try PCMAudio(wavData: spliced)
    #expect(audio.channels == 1)
    #expect(audio.samples.count == 2)
    #expect(abs(audio.samples[0] - 0.5) <= Self.lsb)
  }

  @Test("rejects non-WAV data")
  func rejectsGarbage() {
    #expect(throws: PCMAudio.DecodeError.self) {
      _ = try PCMAudio(wavData: Data("definitely not a wav file".utf8))
    }
    #expect(throws: PCMAudio.DecodeError.self) {
      _ = try PCMAudio(wavData: Data([0x52, 0x49]))
    }
  }
}
