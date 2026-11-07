//
//  AmbienteConfigTests.swift
//  SwiftAmbienteTests
//

import Foundation
import Testing

@testable import SwiftAmbiente

@Suite("AmbienteConfig & scenes")
struct AmbienteConfigTests {

  @Test("Default config is 44.1kHz stereo WAV targeting Stable Audio SFX")
  func defaultConfig() {
    let config = AmbienteConfig.default
    #expect(config.sampleRate == 44_100)
    #expect(config.channelCount == 2)
    #expect(config.outputFormat == .wav)
    #expect(config.generatorModel == StableAudioModelRepo.smallSFX.rawValue)
  }

  @Test("Model repo round-trips through its slug")
  func modelSlugRoundTrip() {
    #expect(StableAudioModelRepo(slug: "sfx") == .smallSFX)
    #expect(StableAudioModelRepo(slug: "music") == nil)
    #expect(StableAudioModelRepo(slug: "nope") == nil)
  }

  @Test("Preset scenes are looked up case-insensitively")
  func presetLookup() {
    #expect(AmbienteSceneDescriptor.preset(id: "rain") != nil)
    #expect(AmbienteSceneDescriptor.preset(id: "RAIN") != nil)
    #expect(AmbienteSceneDescriptor.preset(id: "does-not-exist") == nil)
    #expect(!AmbienteSceneDescriptor.presets.isEmpty)
  }

  @Test("Default generation settings resolve a stable seed")
  func defaultSettings() {
    let settings = GenerationSettings.default
    #expect(settings.durationSeconds == 30.0)
    #expect(settings.resolvedSeed == GenerationSettings.defaultSeed)
  }
}
