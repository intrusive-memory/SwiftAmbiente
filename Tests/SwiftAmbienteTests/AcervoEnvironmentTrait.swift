import Foundation
import SwiftAcervo
import Testing

/// Programmatic bootstrap that ensures `ACERVO_APP_GROUP_ID` is set in the
/// test process before any code path reaches `Acervo.sharedModelsDirectory`.
///
/// `xcodebuild test` (Xcode 26+) does not propagate the parent shell's
/// environment to the `xctest` runner, so the env-var configured in
/// `~/.zprofile` is invisible inside tests. Without this trait the first
/// test that touches Acervo crashes the whole runner with
/// `Fatal error: SwiftAcervo: no App Group identifier configured.`
///
/// Apply via `@Suite(.acervoEnvironment, ...)`. The trait is recursive, so
/// nested suites inherit it automatically.
struct AcervoEnvironmentTrait: SuiteTrait, TestScoping {
  var isRecursive: Bool { false }

  func scopeProvider(for test: Test, testCase: Test.Case?) -> AcervoEnvironmentTrait? {
    self
  }

  func provideScope(
    for test: Test,
    testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    if ProcessInfo.processInfo.environment["ACERVO_APP_GROUP_ID"] == nil {
      setenv("ACERVO_APP_GROUP_ID", "group.intrusive-memory.models", 0)
    }
    // `loadGenerator` -> `Acervo.ensureComponentReady` resolves the CDN base
    // URL and traps if none is configured. With the model already present and
    // verified locally no request is made; this placeholder only satisfies the
    // configuration lookup (never overrides a real value).
    if ProcessInfo.processInfo.environment[Acervo.cdnBaseURLEnvironmentVariable] == nil {
      setenv(Acervo.cdnBaseURLEnvironmentVariable, "https://cdn.invalid/models", 0)
    }
    try await function()
  }
}

extension Trait where Self == AcervoEnvironmentTrait {
  static var acervoEnvironment: Self { AcervoEnvironmentTrait() }
}
