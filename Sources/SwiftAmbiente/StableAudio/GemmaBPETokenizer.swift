//
//  GemmaBPETokenizer.swift
//  SwiftAmbiente
//
//  Sortie 7 (OPERATION PHANTOM FOLEY, WU2): the SentencePiece-BPE tokenizer for
//  the T5Gemma encoder.
//
//  TOKENIZER CHOICE (documented per sortie brief): the reference
//  `t5gemma_mlx.py` tokenizes with `sentencepiece` on `tokenizer.model`. Rather
//  than add a new package dependency (swift-transformers / swift-tokenizers is
//  NOT in this package's resolved graph — pulling it in mid-mission risks the
//  pinned mlx-swift 0.31.3 resolution), we read the model's `tokenizer.json`
//  directly and implement the equivalent BPE. The Gemma fast tokenizer is a
//  byte-fallback BPE with a single space→"▁" (U+2581) normalizer and no dummy
//  prefix — verified against `sentencepiece.Encode` on the same model:
//    "gentle rain on a tin roof" → [116419, 8980, 611, 476, 10689, 11306]
//    ["gentle","▁rain","▁on","▁a","▁tin","▁roof"]  (note: no leading "▁")
//
//  This is a value type (Sendable): it holds only the vocab / merge-rank maps.
//

import Foundation

/// A byte-fallback BPE tokenizer loaded from a HuggingFace `tokenizer.json`
/// (Gemma / T5Gemma). Reproduces `sentencepiece.Encode` for this model.
public struct GemmaBPETokenizer: Sendable {
  /// piece → token id
  private let vocab: [String: Int]
  /// adjacent-pair → merge rank (lower = higher priority)
  private let mergeRanks: [Pair: Int]
  private let unkId: Int
  private let byteFallback: Bool
  private let fuseUnk: Bool

  public let padTokenId: Int

  private struct Pair: Hashable {
    let a: String
    let b: String
  }

  enum LoadError: Error, CustomStringConvertible {
    case fileNotFound(URL)
    case malformed(String)

    var description: String {
      switch self {
      case .fileNotFound(let url): return "tokenizer.json not found at \(url.path)"
      case .malformed(let why): return "tokenizer.json malformed: \(why)"
      }
    }
  }

  /// Load from `<t5gemmaDir>/tokenizer.json`.
  public static func load(fromT5GemmaDirectory dir: URL, padTokenId: Int = 0) throws
    -> GemmaBPETokenizer
  {
    let url = dir.appendingPathComponent("tokenizer.json", isDirectory: false)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw LoadError.fileNotFound(url)
    }
    let data = try Data(contentsOf: url)
    guard
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let model = root["model"] as? [String: Any]
    else { throw LoadError.malformed("no model object") }

    guard let vocabAny = model["vocab"] as? [String: Any] else {
      throw LoadError.malformed("no model.vocab")
    }
    var vocab = [String: Int](minimumCapacity: vocabAny.count)
    for (k, v) in vocabAny {
      if let i = v as? Int { vocab[k] = i } else if let n = v as? NSNumber { vocab[k] = n.intValue }
    }

    guard let mergesAny = model["merges"] as? [Any] else {
      throw LoadError.malformed("no model.merges")
    }
    var mergeRanks = [Pair: Int](minimumCapacity: mergesAny.count)
    var rank = 0
    for m in mergesAny {
      // Newer HF format: ["left","right"]; older: "left right".
      if let pair = m as? [Any], pair.count == 2,
        let a = pair[0] as? String, let b = pair[1] as? String
      {
        mergeRanks[Pair(a: a, b: b)] = rank
      } else if let s = m as? String, let sp = s.firstIndex(of: " ") {
        let a = String(s[s.startIndex..<sp])
        let b = String(s[s.index(after: sp)...])
        mergeRanks[Pair(a: a, b: b)] = rank
      }
      rank += 1
    }

    let byteFallback = (model["byte_fallback"] as? Bool) ?? true
    let fuseUnk = (model["fuse_unk"] as? Bool) ?? true
    let unkTok = (model["unk_token"] as? String) ?? "<unk>"
    let unkId = vocab[unkTok] ?? 3

    return GemmaBPETokenizer(
      vocab: vocab, mergeRanks: mergeRanks, unkId: unkId,
      byteFallback: byteFallback, fuseUnk: fuseUnk, padTokenId: padTokenId)
  }

  // MARK: - Encoding

  /// Encode a single string into token ids (no BOS/EOS — matches the model's
  /// `add_bos_token=false`, `add_eos_token=false`).
  public func encode(_ text: String) -> [Int] {
    // Normalizer: Replace " " → "▁" (U+2581). No dummy prefix.
    let normalized = text.replacingOccurrences(of: " ", with: "\u{2581}")
    if normalized.isEmpty { return [] }

    // Initial symbols: one per Unicode scalar.
    var symbols = normalized.unicodeScalars.map { String($0) }

    // BPE merge loop: repeatedly merge every occurrence of the min-rank
    // adjacent pair until none remain.
    while symbols.count > 1 {
      var bestRank = Int.max
      var bestIndex = -1
      for i in 0..<(symbols.count - 1) {
        if let r = mergeRanks[Pair(a: symbols[i], b: symbols[i + 1])], r < bestRank {
          bestRank = r
          bestIndex = i
        }
      }
      if bestIndex < 0 { break }
      let a = symbols[bestIndex]
      let b = symbols[bestIndex + 1]
      // Merge every non-overlapping occurrence of this exact pair in one pass.
      var merged = [String]()
      merged.reserveCapacity(symbols.count)
      var i = 0
      while i < symbols.count {
        if i < symbols.count - 1 && symbols[i] == a && symbols[i + 1] == b {
          merged.append(a + b)
          i += 2
        } else {
          merged.append(symbols[i])
          i += 1
        }
      }
      symbols = merged
    }

    // Map symbols → ids, with byte fallback + unk fusion.
    var ids = [Int]()
    ids.reserveCapacity(symbols.count)
    for sym in symbols {
      if let id = vocab[sym] {
        ids.append(id)
        continue
      }
      if byteFallback {
        var mappedAll = true
        var byteIds = [Int]()
        for byte in Array(sym.utf8) {
          let token = String(format: "<0x%02X>", byte)
          if let bid = vocab[token] {
            byteIds.append(bid)
          } else {
            mappedAll = false
            break
          }
        }
        if mappedAll {
          ids.append(contentsOf: byteIds)
          continue
        }
      }
      // Fall through to unk.
      if fuseUnk, ids.last == unkId {
        continue  // fuse consecutive unks
      }
      ids.append(unkId)
    }
    return ids
  }

  /// Tokenize a batch of prompts into `(ids, mask)` padded/truncated to
  /// `maxLen`, mirroring the reference `T5Gemma.tokenize`. `ids` and `mask` are
  /// row-major `[B * maxLen]` `Int32` buffers (1 = real token, 0 = pad).
  public func tokenizeBatch(_ prompts: [String], maxLen: Int = 256)
    -> (ids: [Int32], mask: [Int32], batch: Int)
  {
    let B = prompts.count
    var ids = [Int32](repeating: Int32(padTokenId), count: B * maxLen)
    var mask = [Int32](repeating: 0, count: B * maxLen)
    for (row, prompt) in prompts.enumerated() {
      let toks = encode(prompt)
      let n = min(toks.count, maxLen)
      for j in 0..<n {
        ids[row * maxLen + j] = Int32(toks[j])
        mask[row * maxLen + j] = 1
      }
    }
    return (ids, mask, B)
  }
}
