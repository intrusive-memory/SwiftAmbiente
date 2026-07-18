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
