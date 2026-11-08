//
//  AmbienteError.swift
//  SwiftAmbiente
//
//  Error types for SwiftAmbiente atmospheric / foley audio generation.
//

import Foundation

/// Errors that can occur during ambient-bed generation and export.
public enum AmbienteError: Error, LocalizedError, Sendable {
  /// The requested generation model is not available or not downloaded.
  case modelNotAvailable(String)

  /// Audio generation failed inside the generator backend.
  case generationFailed(String)

  /// Audio export or format conversion failed.
  case audioExportFailed(String)

  /// The requested duration is non-positive or exceeds the backend's limit.
  case invalidDuration(Double)

  /// The requested preset scene name is not recognized.
  case unsupportedScene(String)

  /// The requested take is longer than the backend renders in one pass.
  /// Longer spans are built by looping a take, not by asking for a longer one.
  case takeTooLong(seconds: Double, limit: Double)

  public var errorDescription: String? {
    switch self {
    case .modelNotAvailable(let model):
      return "Model not available: \(model). Ensure the model has been downloaded."
    case .generationFailed(let detail):
      return "Ambient generation failed: \(detail)"
    case .audioExportFailed(let detail):
      return "Audio export failed: \(detail)"
    case .invalidDuration(let seconds):
      return "Invalid duration: \(seconds)s. Duration must be greater than 0."
    case .unsupportedScene(let name):
      return
        "Unsupported scene '\(name)'. Use `ambiente --list-scenes` to see the built-in presets, or pass a free-form text prompt."
    case .takeTooLong(let seconds, let limit):
      return "Requested take of \(seconds)s exceeds the \(limit)s single-take limit."
    }
  }
}
