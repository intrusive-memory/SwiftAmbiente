//
//  RenderRecord.swift
//  SwiftAmbiente
//
//  The render record written beside every rendered ambience or foley take
//  (`<output>.json`, Produciesta REQUIREMENTS-ambience § 4.2,
//  REQUIREMENTS-foley § 4.2).
//

import Foundation
import GlosaCore

/// What was rendered into a take WAV, stored beside it as `<output>.json`.
///
/// The record names the directive that produced the take. On disk, an
/// `ambience` take:
///
/// ```json
/// {"ambience": {…schema object…}, "digest": "…", "generator": "stable-audio",
///  "swiftAmbiente": "0.2.0", "rendered": "2026-11-07T21:09:57Z"}
/// ```
///
/// and a `foley` take (Produciesta REQUIREMENTS-foley § 4.2):
///
/// ```json
/// {"foley": {…schema object…}, "digest": "…", "generator": "stable-audio",
///  "swiftAmbiente": "0.3.0", "rendered": "2026-11-08T10:00:00Z"}
/// ```
///
/// Exactly one of `ambience` or `foley` is present; a record with both or
/// neither does not decode. Ambience records written before foley support have
/// exactly the first shape and decode unchanged.
///
/// The directive object is written in GlosaCore's **schema form** (a bare
/// object, as in the screenplay note), not the synthesized `Codable` form.
///
/// `digest` is the note's `renderDigest` **as written** — the value
/// ``AmbienceRendering/renderState(for:output:)`` (or its foley overload)
/// compares against. The stored directive is the *effective* object (defaults
/// that decided the take filled in), so recomputing a digest from it will
/// generally differ from `digest`; always compare `digest`.
public struct RenderRecord: Sendable, Equatable, Codable {
  /// The directive that produced a take, as its effective note.
  public enum Directive: Sendable, Equatable {
    /// An `ambience` bed.
    case ambience(GlosaCore.Ambience)
    /// A `foley` spot effect.
    case foley(GlosaCore.Foley)

    /// The directive's key in the record (`"ambience"` or `"foley"`).
    public var key: String {
      switch self {
      case .ambience: return "ambience"
      case .foley: return "foley"
      }
    }
  }

  /// The effective note that produced the take: the note as written, with
  /// `take`, `steps`, `cfg` and `model` filled in with the values actually used.
  /// `documentIndex` is not part of the schema and decodes as `0`.
  public var directive: Directive

  /// The effective `ambience`, when the take is an ambience bed.
  public var ambience: GlosaCore.Ambience? {
    if case .ambience(let ambience) = directive { return ambience }
    return nil
  }

  /// The effective `foley`, when the take is a foley effect.
  public var foley: GlosaCore.Foley? {
    if case .foley(let foley) = directive { return foley }
    return nil
  }

  /// `renderDigest` of the note as written (lowercase hex SHA-256).
  public var digest: String

  /// The ``AmbienteGenerator/generatorId`` that rendered the take.
  public var generator: String

  /// The SwiftAmbiente library version that rendered the take.
  public var swiftAmbiente: String

  /// When the take was rendered. Stored as ISO-8601 at whole-second precision.
  public var rendered: Date

  public init(
    directive: Directive,
    digest: String,
    generator: String,
    swiftAmbiente: String = SwiftAmbiente.version,
    rendered: Date
  ) {
    self.directive = directive
    self.digest = digest
    self.generator = generator
    self.swiftAmbiente = swiftAmbiente
    self.rendered = Date(timeIntervalSince1970: rendered.timeIntervalSince1970.rounded(.down))
  }

  /// A record for an `ambience` take.
  public init(
    ambience: GlosaCore.Ambience,
    digest: String,
    generator: String,
    swiftAmbiente: String = SwiftAmbiente.version,
    rendered: Date
  ) {
    self.init(
      directive: .ambience(ambience), digest: digest, generator: generator,
      swiftAmbiente: swiftAmbiente, rendered: rendered)
  }

  /// A record for a `foley` take.
  public init(
    foley: GlosaCore.Foley,
    digest: String,
    generator: String,
    swiftAmbiente: String = SwiftAmbiente.version,
    rendered: Date
  ) {
    self.init(
      directive: .foley(foley), digest: digest, generator: generator,
      swiftAmbiente: swiftAmbiente, rendered: rendered)
  }

  // MARK: Codable

  private enum CodingKeys: String, CodingKey {
    case ambience, foley, digest, generator, swiftAmbiente, rendered
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let hasAmbience = c.contains(.ambience)
    let hasFoley = c.contains(.foley)
    switch (hasAmbience, hasFoley) {
    case (true, false):
      let schema = try c.decode(PlainJSONValue.self, forKey: .ambience).value
      do {
        self.directive = .ambience(try GlosaCore.Ambience(schemaJSON: schema))
      } catch {
        throw DecodingError.dataCorruptedError(
          forKey: .ambience, in: c,
          debugDescription: "`ambience` is not a valid ambience object: \(error)")
      }
    case (false, true):
      let schema = try c.decode(PlainJSONValue.self, forKey: .foley).value
      do {
        self.directive = .foley(try GlosaCore.Foley(schemaJSON: schema))
      } catch {
        throw DecodingError.dataCorruptedError(
          forKey: .foley, in: c,
          debugDescription: "`foley` is not a valid foley object: \(error)")
      }
    case (true, true):
      throw DecodingError.dataCorruptedError(
        forKey: .foley, in: c,
        debugDescription: "a render record holds exactly one of `ambience` or `foley`, not both")
    case (false, false):
      throw DecodingError.keyNotFound(
        CodingKeys.ambience,
        DecodingError.Context(
          codingPath: c.codingPath,
          debugDescription: "a render record holds exactly one of `ambience` or `foley`"))
    }
    self.digest = try c.decode(String.self, forKey: .digest)
    self.generator = try c.decode(String.self, forKey: .generator)
    self.swiftAmbiente = try c.decode(String.self, forKey: .swiftAmbiente)
    let renderedText = try c.decode(String.self, forKey: .rendered)
    do {
      self.rendered = try Date(renderedText, strategy: .iso8601)
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .rendered, in: c,
        debugDescription: "`rendered` is not an ISO-8601 date: \(renderedText)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch directive {
    case .ambience(let ambience):
      try c.encode(PlainJSONValue(ambience.schemaJSON()), forKey: .ambience)
    case .foley(let foley):
      try c.encode(PlainJSONValue(foley.schemaJSON()), forKey: .foley)
    }
    try c.encode(digest, forKey: .digest)
    try c.encode(generator, forKey: .generator)
    try c.encode(swiftAmbiente, forKey: .swiftAmbiente)
    try c.encode(rendered.formatted(.iso8601), forKey: .rendered)
  }

  // MARK: File form

  /// The record as written to disk: pretty-printed UTF-8 JSON with sorted keys.
  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  /// Decodes a record from its file form.
  public init(jsonData: Data) throws {
    self = try JSONDecoder().decode(RenderRecord.self, from: jsonData)
  }
}

// MARK: - Plain JSON bridge

/// Codes a `GlosaJSONValue` as ordinary JSON (objects as JSON objects).
///
/// `GlosaJSONValue`'s own `Codable` form wraps objects as
/// `{"object": [{"key": …, "value": …}]}` to keep member order; the render
/// record wants the schema object exactly as a note would hold it. Member order
/// is not preserved through Foundation's JSON coders — harmless here, since
/// the record's `digest` (not a digest recomputed from the directive) is what
/// render state compares.
struct PlainJSONValue: Codable {
  let value: GlosaJSONValue

  init(_ value: GlosaJSONValue) { self.value = value }

  private struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }

  init(from decoder: any Decoder) throws {
    if let keyed = try? decoder.container(keyedBy: Key.self) {
      var members: [GlosaJSONMember] = []
      for key in keyed.allKeys {
        let member = try keyed.decodeIfPresent(PlainJSONValue.self, forKey: key)?.value ?? .null
        members.append(GlosaJSONMember(key: key.stringValue, value: member))
      }
      value = .object(members)
    } else if var unkeyed = try? decoder.unkeyedContainer() {
      var elements: [GlosaJSONValue] = []
      while !unkeyed.isAtEnd {
        if try unkeyed.decodeNil() {
          elements.append(.null)
        } else {
          elements.append(try unkeyed.decode(PlainJSONValue.self).value)
        }
      }
      value = .array(elements)
    } else {
      let single = try decoder.singleValueContainer()
      if single.decodeNil() {
        value = .null
      } else if let bool = try? single.decode(Bool.self) {
        value = .bool(bool)
      } else if let number = try? single.decode(Double.self) {
        value = .number(number)
      } else {
        value = .string(try single.decode(String.self))
      }
    }
  }

  func encode(to encoder: any Encoder) throws {
    switch value {
    case .object(let members):
      var keyed = encoder.container(keyedBy: Key.self)
      for member in members {
        try keyed.encode(PlainJSONValue(member.value), forKey: Key(member.key))
      }
    case .array(let elements):
      var unkeyed = encoder.unkeyedContainer()
      for element in elements {
        try unkeyed.encode(PlainJSONValue(element))
      }
    case .string(let string):
      var single = encoder.singleValueContainer()
      try single.encode(string)
    case .number(let number):
      var single = encoder.singleValueContainer()
      try single.encode(number)
    case .bool(let bool):
      var single = encoder.singleValueContainer()
      try single.encode(bool)
    case .null:
      var single = encoder.singleValueContainer()
      try single.encodeNil()
    }
  }
}
