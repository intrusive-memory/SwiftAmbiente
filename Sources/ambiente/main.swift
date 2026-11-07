import AmbienteCLICore

// `AmbienteCommand` is an `AsyncParsableCommand`, so its entry point is async.
// The command logic lives in `AmbienteCLICore` so the same entry point can be
// embedded in an Xcode tool target.
//
// `runAsMain()` is used rather than a bare `await AmbienteCommand.main()` because
// the async `main()` overload is `@available`-gated and top-level `main.swift`
// code is not an availability-annotated scope — a bare call would resolve to the
// synchronous overload and abort at runtime.
await AmbienteCommand.runAsMain()
