//
//  T5GemmaEncoderTests.swift
//  SwiftAmbienteTests
//
//  Sortie 7 (OPERATION PHANTOM FOLEY, WU2): model-gated verification of the
//  T5Gemma text-conditioning path (tokenizer + encoder).
//
//  GATING: runs only when the real SFX model (with its `t5gemma-b-b-ul2/`
//  subfolder) is resolvable on disk. On CI runners without the model these
//  SKIP cleanly via `@Test(.enabled(if:))`. Point `ACERVO_MODELS_DIR` or
//  `TEST_RUNNER_ACERVO_MODELS_DIR` at the staging root (e.g. `/tmp/acervo-staging`).
//
//  The tests READ env only (no mutation), so no `AcervoModelsDirectoryGate` is
//  needed. The model directory is resolved directly from the fixture helper.
//
//  PARITY: the committed fixture `Fixtures/t5gemma-encoder-reference.json` was
//  captured from the official `optimized/mlx` T5Gemma `_Encoder` (built on the
//  same `t5gemma-b-b-ul2/model.safetensors`, bf16→fp16) for the fixed prompt
//  "gentle rain on a tin roof". We assert (a) the Swift BPE tokenizer reproduces
//  the reference SentencePiece token ids and (b) the Swift encoder output matches
//  the reference within a documented fp16 tolerance. Feeding the reference token
//  ids into the Swift encoder isolates encoder-forward parity from tokenization.
//

import Foundation
import MLX
import Testing

@testable import SwiftAmbiente

/// Decoded reference fixture.
private struct T5GemmaReferenceFixture: Decodable {
  let prompt: String
  let max_len: Int
  let pad_token_id: Int
  let token_ids: [Int]
  let num_tokens: Int
  let out_shape: [Int]
  let out_dtype: String
  let real_mean: Float
  let real_std: Float
  let real_absmax: Float
  let probe_row0_col0_8: [Float]
  let probe_row0_col100_108: [Float]
  let probe_lastreal_col0_8: [Float]
  let row_means_first8: [Float]
  let tokenizer_cases: [String: [Int]]

  static func load() throws -> T5GemmaReferenceFixture {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/t5gemma-encoder-reference.json", isDirectory: false)
    return try JSONDecoder().decode(
      T5GemmaReferenceFixture.self, from: Data(contentsOf: url))
  }
}

/// Model presence gate specific to the T5Gemma subfolder.
private enum T5GemmaFixture {
  static var modelDirectory: URL? { StableAudioModelFixture.modelDirectory }

  static var isPresent: Bool {
    guard StableAudioModelFixture.isPresent, let dir = modelDirectory else { return false }
    let sub = dir.appendingPathComponent(
      T5GemmaEncoderConfig.subfolderName, isDirectory: true)
    let fm = FileManager.default
    return fm.fileExists(atPath: sub.appendingPathComponent("model.safetensors").path)
      && fm.fileExists(atPath: sub.appendingPathComponent("tokenizer.json").path)
  }
}

@Suite("T5Gemma text conditioning (Sortie 7)", .serialized)
struct T5GemmaEncoderTests {

  // MARK: Tokenizer parity (model-gated: needs tokenizer.json)

  @Test(
    "BPE tokenizer reproduces reference SentencePiece token ids",
    .enabled(if: T5GemmaFixture.isPresent))
  func tokenizerMatchesReference() throws {
    let fixture = try T5GemmaReferenceFixture.load()
    let dir = try #require(T5GemmaFixture.modelDirectory)
    let sub = dir.appendingPathComponent(
      T5GemmaEncoderConfig.subfolderName, isDirectory: true)
    let tokenizer = try GemmaBPETokenizer.load(
      fromT5GemmaDirectory: sub, padTokenId: fixture.pad_token_id)

    // The fixed prompt.
    #expect(tokenizer.encode(fixture.prompt) == fixture.token_ids)

    // Additional reference cases (single-token + multi-word).
    for (text, expected) in fixture.tokenizer_cases {
      #expect(tokenizer.encode(text) == expected, "tokenizer mismatch for \(text)")
    }
  }

  // MARK: Conditioning tensor shape + dtype (HARD requirement)

  @Test(
    "conditioning tensor has documented shape (1,256,768) fp16 + mask",
    .enabled(if: T5GemmaFixture.isPresent))
  func conditioningShapeAndDtype() throws {
    let fixture = try T5GemmaReferenceFixture.load()
    let dir = try #require(T5GemmaFixture.modelDirectory)
    let conditioner = try T5GemmaTextConditioner.load(fromModelDirectory: dir)

    let cond = conditioner.encode([fixture.prompt], maxLen: fixture.max_len)

    // Documented shape/dtype the DiT conditioner consumes.
    #expect(cond.embeddings.shape == [1, fixture.max_len, 768])
    #expect(cond.embeddings.dtype == .float16)
    #expect(cond.mask.shape == [1, fixture.max_len])
    #expect(cond.batch == 1)
    #expect(cond.sequenceLength == fixture.max_len)
    #expect(cond.hiddenSize == 768)

    // Mask marks exactly the real tokens.
    let maskVals = cond.mask.asType(.int32).asArray(Int32.self)
    let ones = maskVals.reduce(0) { $0 + Int($1) }
    #expect(ones == fixture.num_tokens)
  }

  // MARK: Numerical parity vs reference encoder (fp16 tolerance)

  @Test(
    "encoder output matches reference within fp16 tolerance",
    .enabled(if: T5GemmaFixture.isPresent))
  func encoderNumericalParity() throws {
    let fixture = try T5GemmaReferenceFixture.load()
    let dir = try #require(T5GemmaFixture.modelDirectory)
    let encoder = try T5GemmaTextEncoder.load(fromModelDirectory: dir)

    // Feed the REFERENCE token ids (isolates encoder from tokenizer).
    let maxLen = fixture.max_len
    var idsFlat = [Int32](repeating: Int32(fixture.pad_token_id), count: maxLen)
    var maskFlat = [Int32](repeating: 0, count: maxLen)
    for (j, t) in fixture.token_ids.enumerated() {
      idsFlat[j] = Int32(t)
      maskFlat[j] = 1
    }
    let ids = MLXArray(idsFlat, [1, maxLen])
    let mask = MLXArray(maskFlat, [1, maxLen])

    let out = encoder(inputIds: ids, attentionMask: mask)
    #expect(out.shape == [1, maxLen, 768])
    #expect(out.dtype == .float16)

    // Flatten to fp32 for comparison.
    let flat = out.asType(.float32).asArray(Float.self)  // [1*maxLen*768]
    let hidden = 768
    func element(_ row: Int, _ col: Int) -> Float { flat[row * hidden + col] }

    // Element-level probes: a convention bug (softcap / RoPE / RMSNorm placement)
    // moves these by many units; matching backend kernels keep them tight.
    let elemTol: Float = 0.5
    for c in 0..<8 {
      #expect(abs(element(0, c) - fixture.probe_row0_col0_8[c]) < elemTol)
      #expect(abs(element(0, 100 + c) - fixture.probe_row0_col100_108[c]) < elemTol)
      #expect(
        abs(element(fixture.num_tokens - 1, c) - fixture.probe_lastreal_col0_8[c]) < elemTol)
    }

    // Global stats over the real (non-pad) token rows.
    let nz = fixture.num_tokens
    var sum: Float = 0, sumSq: Float = 0, absMax: Float = 0
    for r in 0..<nz {
      for c in 0..<hidden {
        let v = element(r, c)
        sum += v
        sumSq += v * v
        absMax = max(absMax, abs(v))
      }
    }
    let count = Float(nz * hidden)
    let mean = sum / count
    let variance = sumSq / count - mean * mean
    let std = variance > 0 ? variance.squareRoot() : 0
    #expect(abs(mean - fixture.real_mean) < 0.05)
    #expect(abs(std - fixture.real_std) < 0.1)
    #expect(abs(absMax - fixture.real_absmax) < 1.0)
  }
}
