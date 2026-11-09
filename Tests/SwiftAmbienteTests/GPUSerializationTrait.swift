//
//  GPUSerializationTrait.swift
//  SwiftAmbienteTests
//
//  Swift Testing runs suites in PARALLEL with each other; `.serialized` only
//  orders tests *within* one suite. The real-model suites (model loading,
//  T5Gemma, DiT sampler, generator, golden parity, engine) each load the
//  Stable Audio weights and drive MLX/Metal, so in CI they used to run on the
//  GPU at the same time. On the hosted runner's virtualized GPU that
//  contention pushed a command buffer past the Metal watchdog
//  (`kIOGPUCommandBufferCallbackErrorTimeout`); MLX turns that into an
//  uncaught `std::runtime_error`, which aborts the whole xctest process.
//
//  `.serializedOnGPU` makes those suites mutually exclusive: at most one
//  GPU-heavy suite runs at a time, across the whole test target.
//
//  Lock order: this gate is always taken OUTERMOST (around the whole suite).
//  `AcervoModelsDirectoryGate` is taken inside test bodies and never held
//  while waiting on this gate, so the two cannot deadlock.
//

import Testing

/// Async-safe, FIFO mutex for GPU-heavy suites. Suspends waiters instead of
/// blocking a cooperative-pool thread (same reasoning as
/// `AcervoModelsDirectoryGate`).
actor GPUTestGate {
  static let shared = GPUTestGate()

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

  func withExclusiveAccess(
    _ body: @Sendable () async throws -> Void
  ) async throws {
    await acquire()
    defer { release() }
    try await body()
  }
}

/// Suite trait: run the whole suite while holding `GPUTestGate.shared`.
struct GPUSerializationTrait: SuiteTrait, TestScoping {
  var isRecursive: Bool { false }

  func scopeProvider(for test: Test, testCase: Test.Case?) -> GPUSerializationTrait? {
    // Scope the suite once (not each test inside it), so the gate is held
    // for the suite's full run.
    test.isSuite ? self : nil
  }

  func provideScope(
    for test: Test,
    testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    try await GPUTestGate.shared.withExclusiveAccess(function)
  }
}

extension Trait where Self == GPUSerializationTrait {
  /// Serialize this suite against every other `.serializedOnGPU` suite.
  static var serializedOnGPU: Self { GPUSerializationTrait() }
}
