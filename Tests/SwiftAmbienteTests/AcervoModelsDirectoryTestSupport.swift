//
//  AcervoModelsDirectoryTestSupport.swift
//  SwiftAmbienteTests
//
//  `AmbienteModelManagerTests` and `AmbienteEngineTests` are each
//  `@Suite(.serialized)`, which only serializes tests *within* a suite —
//  Swift Testing still runs the two suites in PARALLEL with each other.
//  Both suites `setenv`/`unsetenv` the process-global `ACERVO_MODELS_DIR`
//  environment variable around their bodies, so without cross-suite
//  serialization one suite's `setenv` can clobber another's between its
//  `setenv` and its read, producing an intermittent wrong-directory
//  mismatch (and, combined with a missing `ACERVO_APP_GROUP_ID`, sometimes
//  a fatal crash of the whole runner).
//
//  This file provides a single shared implementation of the
//  mutate -> read -> restore critical section, serialized across ALL
//  suites via `AcervoModelsDirectoryGate`, so there is exactly one place
//  this logic lives instead of two copy-pasted private helpers.
//

import Foundation
import SwiftAcervo
import Testing

@testable import SwiftAmbiente

/// Async-safe mutex that serializes the `ACERVO_MODELS_DIR` critical
/// section across every suite in this test target.
///
/// Deliberately NOT a thread-blocking lock (`NSLock`/`DispatchSemaphore`):
/// the guarded critical section itself awaits actor-isolated calls (into
/// `AmbienteModelManager`/`AmbienteEngine`), which may need the same
/// cooperative thread pool to make progress. A blocking lock held across
/// those awaits risks starving that pool. Callers that lose the race
/// instead suspend via `withCheckedContinuation`, which yields the thread
/// back to the pool without holding it.
actor AcervoModelsDirectoryGate {
  static let shared = AcervoModelsDirectoryGate()

  private var isLocked = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  private init() {}

  private func acquire() async {
    if !isLocked {
      isLocked = true
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  private func release() {
    if waiters.isEmpty {
      isLocked = false
    } else {
      waiters.removeFirst().resume()
    }
  }

  /// Runs `body` with exclusive access to the gate. No other caller of
  /// `withExclusiveAccess` (from any suite, any test) can run concurrently
  /// with it.
  func withExclusiveAccess<R: Sendable>(
    _ body: @Sendable () async throws -> R
  ) async throws -> R {
    await acquire()
    defer { release() }
    return try await body()
  }
}

/// Snapshots and restores `ACERVO_MODELS_DIR` around `body`, pointing it at
/// a freshly created empty temp directory (as a raw path string) for the
/// duration of the call. Restores the prior value on exit (including on
/// throw) so other tests see a clean slate.
///
/// The whole mutate -> body -> restore sequence runs under
/// `AcervoModelsDirectoryGate.shared`, so it is serialized against every
/// other suite's use of this helper — not just tests within the same
/// suite. `prefix` is used to namespace the temp directory name per call
/// site for easier debugging; it has no effect on correctness.
///
/// Shared by `AmbienteModelManagerTests` and `AmbienteEngineTests` so there
/// is a single implementation of this critical section instead of two
/// copy-pasted ones.
func withTempAcervoModelsDirectory<R: Sendable>(
  prefix: String,
  _ body: @Sendable (String) async throws -> R
) async throws -> R {
  try await AcervoModelsDirectoryGate.shared.withExclusiveAccess {
    let key = Acervo.modelsDirectoryOverrideVariable
    let previous = ProcessInfo.processInfo.environment[key]
    let tempPath = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
      .path
    try? FileManager.default.createDirectory(
      atPath: tempPath, withIntermediateDirectories: true)
    setenv(key, tempPath, 1)
    defer {
      if let previous {
        setenv(key, previous, 1)
      } else {
        unsetenv(key)
      }
      try? FileManager.default.removeItem(atPath: tempPath)
    }
    return try await body(tempPath)
  }
}

/// The baseline (non-mutated) candidate models root, preferring the
/// externally-forwarded `TEST_RUNNER_ACERVO_MODELS_DIR` (stable for the whole
/// run — xcodebuild forwards it from the parent shell env on Xcode 26+, where
/// the parent env otherwise doesn't reach the xctest runner) over
/// `ACERVO_MODELS_DIR` (which mutator suites transiently `setenv`/restore via
/// `withTempAcervoModelsDirectory`). `nil` when neither is configured, i.e. no
/// model is staged for this run.
///
/// Deliberately duplicated (rather than referencing
/// `StableAudioModelFixture.candidateModelsDirectory`) so this foundational
/// support file has no dependency on suite-specific fixtures.
private var stableBaselineAcervoModelsRoot: String? {
  let env = ProcessInfo.processInfo.environment
  return env["TEST_RUNNER_ACERVO_MODELS_DIR"] ?? env["ACERVO_MODELS_DIR"]
}

/// Runs `body` with exclusive access to `AcervoModelsDirectoryGate`, having
/// resolved the REAL (non-temp) Stable Audio SFX model directory the same way
/// product code does — via `AmbienteModelManager.modelDirectory(for:)`, which
/// delegates to `Acervo.sharedModelsDirectory` — and hands that resolved `URL`
/// to `body`.
///
/// For model-gated READER suites (`StableAudioModelLoadingTests`,
/// `T5GemmaEncoderTests`, and future model-load suites) that only need to
/// resolve + load real model files from disk, never mutate env for anyone
/// else's benefit. Every mutator suite's `setenv -> body -> restore` critical
/// section (see `withTempAcervoModelsDirectory` above) runs entirely inside
/// `AcervoModelsDirectoryGate`, so a reader that also holds the gate while it
/// resolves + loads is guaranteed no mutator is mid-transient — it always
/// observes the stable baseline `ACERVO_MODELS_DIR`, i.e. the real model
/// directory, never a mutator's temp dir.
///
/// Callers should already have gated the `@Test` itself with
/// `.enabled(if:)` on model presence; this throws if, despite that, no
/// candidate models root is configured when the body actually runs.
func withResolvedAcervoModelsDirectory<R: Sendable>(
  _ body: @Sendable (URL) async throws -> R
) async throws -> R {
  try await AcervoModelsDirectoryGate.shared.withExclusiveAccess {
    let root = try #require(
      stableBaselineAcervoModelsRoot,
      "gate opened but no candidate models directory is set")
    let key = Acervo.modelsDirectoryOverrideVariable
    let previous = ProcessInfo.processInfo.environment[key]
    setenv(key, root, 1)
    defer {
      if let previous {
        setenv(key, previous, 1)
      } else {
        unsetenv(key)
      }
    }
    let manager = AmbienteModelManager()
    let modelDir = await manager.modelDirectory(for: .smallSFX)
    return try await body(modelDir)
  }
}
