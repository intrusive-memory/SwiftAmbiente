---
type: test-cleanup-report
state: completed
updated: 2026-11-07
mission: phantom-foley-01
---

# Test Cleanup Report: OPERATION PHANTOM FOLEY

## Removed

None

## Flagged for Review

| file:test_name | concern | recommended action |
|---|---|---|
| StableAudioGoldenParityTests.swift:goldenParity | Model-gated via `.enabled(if: GoldenParityFixture.isModelPresent)`; skips on runners without the model. Relies on the integration-tests workflow to ever execute. Spans about 45 lines (under the 200 line threshold). | Keep. CI-safe skip-on-missing gating. Confirm integration-tests.yml keeps running it. |
| AmbienteEngineTests, StableAudioGeneratorTests, StableAudioLatentSamplerTests, StableAudioModelLoadingTests, T5GemmaEncoderTests (model-gated tests) | All use `.enabled(if: <fixture>.isPresent)`, which only reads env. Conditions are CI-safe. | Keep. No action. |

No test contained hard-coded user paths, public network calls, unseeded randomness, sleeps, wall-clock assertions, empty bodies, or duplicates. The only `~/Library` mention is a comment in AmbienteModelManagerTests.swift.

## Build Verification

- `env -u TEST_RUNNER_ACERVO_MODELS_DIR -u ACERVO_MODELS_DIR make test`: passed. Test run with 32 tests in 9 suites passed; Test run with 5 tests in 1 suite passed. TEST SUCCEEDED.
- `TEST_RUNNER_ACERVO_MODELS_DIR=/tmp/acervo-staging make test`: passed. Test run with 32 tests in 9 suites passed; Test run with 5 tests in 1 suite passed. TEST SUCCEEDED.
