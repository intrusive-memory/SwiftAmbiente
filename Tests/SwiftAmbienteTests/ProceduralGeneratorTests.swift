//
//  ProceduralGeneratorTests.swift
//  SwiftAmbienteTests
//

import Foundation
import Testing

@testable import SwiftAmbiente

@Suite("ProceduralAmbienteGenerator")
struct ProceduralGeneratorTests {

  @Test("Generates a valid WAV of approximately the requested duration")
  func generatesWavOfRequestedDuration() async throws {
    let config = AmbienteConfig.default
    let generator = ProceduralAmbienteGenerator(config: config)
    let settings = GenerationSettings(durationSeconds: 2.0, seed: 42)

    let data = try await generator.generate(prompt: "rain", settings: settings)

    // RIFF/WAVE header is present.
    #expect(data.count > 44)
    #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
    #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")

    // Data payload ≈ duration * sampleRate * channels * 2 bytes (16-bit).
    let expectedFrames = Int(2.0 * Double(config.sampleRate))
    let expectedBytes = expectedFrames * config.channelCount * 2
    let payload = data.count - 44
    // Allow a 1-frame rounding slack.
    let slack = config.channelCount * 2
    #expect(abs(payload - expectedBytes) <= slack)
  }

  @Test("Is deterministic for the same prompt and seed")
  func isDeterministic() async throws {
    let generator = ProceduralAmbienteGenerator()
    let settings = GenerationSettings(durationSeconds: 1.0, seed: 7)

    let a = try await generator.generate(prompt: "forest", settings: settings)
    let b = try await generator.generate(prompt: "forest", settings: settings)
    #expect(a == b)
  }

  @Test("Different prompts produce different audio")
  func differentPromptsDiverge() async throws {
    let generator = ProceduralAmbienteGenerator()
    let settings = GenerationSettings(durationSeconds: 1.0, seed: 7)

    let rain = try await generator.generate(prompt: "rain", settings: settings)
    let city = try await generator.generate(prompt: "city", settings: settings)
    #expect(rain != city)
  }

  @Test("Rejects a non-positive duration")
  func rejectsBadDuration() async throws {
    let generator = ProceduralAmbienteGenerator()
    let settings = GenerationSettings(durationSeconds: 0)
    await #expect(throws: AmbienteError.self) {
      _ = try await generator.generate(prompt: "rain", settings: settings)
    }
  }

  @Test("Reports itself as available")
  func isAvailable() async {
    let generator = ProceduralAmbienteGenerator()
    #expect(await generator.isAvailable())
  }
}
