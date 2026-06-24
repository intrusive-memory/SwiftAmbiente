//
//  AudioFileWriter.swift
//  AmbientaCLICore
//
//  Writes generated WAV data to disk. SwiftAmbiente generates WAV directly; this
//  writer currently passes WAV through verbatim and is the seam where future
//  aiff/caf transcoding will live.
//

import Foundation
import SwiftAmbiente

/// Writes generated audio to a file path.
enum AudioFileWriter {
  /// Write WAV data to `path`.
  ///
  /// - Parameters:
  ///   - wavData: The generated WAV bytes.
  ///   - path: Destination file path.
  ///   - format: Desired container. Only `.wav` is supported today; other
  ///     formats throw until transcoding is added.
  static func write(wavData: Data, to path: String, format: AudioOutputFormat) throws {
    switch format {
    case .wav:
      let url = URL(fileURLWithPath: path)
      try wavData.write(to: url, options: .atomic)
    case .aiff, .caf:
      throw AmbienteError.audioExportFailed(
        "Output format '\(format.rawValue)' is not yet supported; write .wav and transcode "
          + "with afconvert for now.")
    }
  }

  /// Infer the output format from a path extension, or default to `.wav`.
  static func inferFormat(fromPath path: String) -> AudioOutputFormat {
    let ext = (path as NSString).pathExtension.lowercased()
    return AudioOutputFormat(rawValue: ext) ?? .wav
  }
}
