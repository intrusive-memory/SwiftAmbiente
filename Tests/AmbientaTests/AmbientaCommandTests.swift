//
//  AmbientaCommandTests.swift
//  AmbientaTests
//

import Foundation
import Testing

@testable import AmbientaCLICore
@testable import SwiftAmbiente

@Suite("ambienta CLI")
struct AmbientaCommandTests {

  @Test("Version string is wired")
  func versionPresent() {
    #expect(!AmbientaVersion.current.isEmpty)
  }

  @Test("Parses a prompt and duration")
  func parsesPromptAndDuration() throws {
    let cmd = try AmbientaCommand.parse(["rain", "on", "a", "roof", "-d", "12"])
    #expect(cmd.duration == 12)
    #expect(cmd.promptWords == ["rain", "on", "a", "roof"])
  }

  @Test("Parses a scene preset flag")
  func parsesScene() throws {
    let cmd = try AmbientaCommand.parse(["--scene", "forest"])
    #expect(cmd.scene == "forest")
  }

  @Test("AudioFileWriter infers format from extension")
  func infersFormat() {
    #expect(AudioFileWriter.inferFormat(fromPath: "bed.wav") == .wav)
    #expect(AudioFileWriter.inferFormat(fromPath: "bed.aiff") == .aiff)
    #expect(AudioFileWriter.inferFormat(fromPath: "bed.unknown") == .wav)
  }

  @Test("Writing a non-WAV format is rejected until transcoding lands")
  func nonWavRejected() {
    #expect(throws: AmbienteError.self) {
      try AudioFileWriter.write(wavData: Data([0, 1, 2]), to: "/tmp/x.aiff", format: .aiff)
    }
  }
}
