//
//  AmbienteCommandTests.swift
//  AmbienteCLITests
//

import Foundation
import Testing

@testable import AmbienteCLICore
@testable import SwiftAmbiente

@Suite("ambiente CLI")
struct AmbienteCommandTests {

  @Test("Version string is wired")
  func versionPresent() {
    #expect(!AmbienteCLIVersion.current.isEmpty)
  }

  @Test("Parses a prompt and duration")
  func parsesPromptAndDuration() throws {
    let cmd = try AmbienteCommand.parse(["rain", "on", "a", "roof", "-d", "12"])
    #expect(cmd.duration == 12)
    #expect(cmd.promptWords == ["rain", "on", "a", "roof"])
  }

  @Test("Guidance defaults to cfg 1.0 / 8 steps and is overridable")
  func parsesGuidance() throws {
    let defaults = try AmbienteCommand.parse(["rain"])
    #expect(defaults.cfg == 1.0)
    #expect(defaults.steps == 8)
    let custom = try AmbienteCommand.parse(["rain", "--cfg", "2.5", "--steps", "12"])
    #expect(custom.cfg == 2.5)
    #expect(custom.steps == 12)
  }

  @Test("Library default guidance is cfg 1.0 (Small SFX is distilled for it)")
  func libraryDefaultCFG() {
    #expect(GenerationSettings().cfgScale == 1.0)
  }

  @Test("Parses a scene preset flag")
  func parsesScene() throws {
    let cmd = try AmbienteCommand.parse(["--scene", "forest"])
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
