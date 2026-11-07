---
type: acceptance
mission: OPERATION PHANTOM FOLEY (WU4 / Sortie 15)
requirements: REQUIREMENTS-stable-audio-integration.md
verified_at_commit: 3bc65fa
date: 2026-11-07
---

# ACCEPTANCE: Stable Audio backend integration

All four requirements-doc acceptance checkboxes are **MET**. Several are met with
caveats that differ from the requirements wording; they are listed per item and
again in "Deviations". Items that could not be proven locally are in
"Outstanding / not verified".

## Verification runs (at HEAD `3bc65fa`)

| Command | Result |
|---|---|
| `make build` | `** BUILD SUCCEEDED **` |
| `env -u TEST_RUNNER_ACERVO_MODELS_DIR -u ACERVO_MODELS_DIR make test` | `** TEST SUCCEEDED **`. swift-testing: **"Test run with 32 tests in 9 suites passed"** (13 neural/model-gated tests reported as skipped), plus "Test run with 5 tests in 1 suite passed" (second test target). |
| `TEST_RUNNER_ACERVO_MODELS_DIR=/tmp/acervo-staging make test` | `** TEST SUCCEEDED **`. swift-testing: **"Test run with 32 tests in 9 suites passed"** (0 skipped; neural tests ran, ~23 s), plus "Test run with 5 tests in 1 suite passed". Golden parity printed `rmsRel=0.0099 ltas=0.056 dB spectrogram=0.278 dB envCorr=0.9978`; negative control (seed 43) `spectrogram=14.681 dB envCorr=0.1087`. |

Both runs report 32 tests because swift-testing counts a skipped test in the run
total; the difference is skipped vs executed.

---

## 1. Conformance and WAV contract

**Requirement (verbatim):**
> `StableAudioGenerator` conforms to `AmbienteGenerator` and passes the same
> WAV-contract tests the procedural generator does.

**Status: MET**

**Delivered by:** S10 `592220a` (conformance and engine wiring); S8 `99015f1`,
S9 `3e6e922` (sampler and decoder underneath); S7 `29fb2d9` (T5Gemma); S6
`e2bb48b` (weights loading).

**Evidence:**
- `Sources/SwiftAmbiente/StableAudio/StableAudioGenerator.swift`. The type name
  matches the requirement exactly. `generatorId == "stable-audio"`.
- `StableAudioGeneratorTests` (Tests/SwiftAmbienteTests/StableAudioGeneratorTests.swift):
  - model-free, always run: `identifies as stable-audio`, `is unavailable when
    the model directory is missing`, `rejects a non-positive duration before
    touching the model`, `rejects a non-44.1 kHz-stereo config`.
  - model-gated: `reports available and satisfies the WAV contract with the real
    model` (RIFF/WAVE header, 44.1 kHz, 2 ch, 16-bit, frame count equals
    `duration x sampleRate`, non-silent channels) and `is deterministic for the
    same prompt and seed`.
- `StableAudioGoldenParityTests.goldenParity` re-asserts the WAV contract on a
  5 s render (44-byte header, 220,500 frames, 44.1 kHz stereo 16-bit).
  `golden fixture satisfies the WAV contract` is model-free.
- Procedural counterpart: `ProceduralGeneratorTests` ("Generates a valid WAV of
  approximately the requested duration", determinism, rejects non-positive
  duration). Both generators are checked for the same properties (RIFF/WAVE,
  determinism, duration rejection). They share no single parameterized test body.
  The neural tests use the `PCMWAV` parser, so the check is stricter than the
  procedural one.
- `GenerationSettings.steps`, `cfgScale`, `seed` and `durationSeconds` are honoured.
  Evidence: `StableAudioLatentSamplerTests` (shape for the requested duration,
  same seed gives a byte-identical latent, different seeds diverge, cfg != 1
  path), and the WAV tests above.
- Ran: both `make test` runs above. Model-free tests pass in both. Model-gated
  tests are skipped in run A and pass in run B.

**Differences from the requirement wording:**
- The requirements say to *port from `kellyvv/StableAudio3-IOS`*. That was not
  done. The mission translated Stability's **official `optimized/mlx` Python-MLX
  backend** (`Stability-AI/stable-audio-3`) op-for-op into MLX Swift (decision
  recorded in `Sources/SwiftAmbiente/StableAudio/STRATEGY.md`, S5 `42ccb28`;
  OQ-1 in EXECUTION_PLAN.md). The reason is that this keeps seed and numerical
  parity against a golden fixture from the official reference achievable.
- **Golden-output parity is a spectral/RMS gate, not sample-exact.** Measured
  (STRATEGY.md "Sortie 9 parity tolerance"):

  | Metric | Tolerance | Observed |
  |---|---|---|
  | spectrogram dB error | <= 1.2 | 0.278 |
  | long-term spectrum dB error | <= 0.4 | 0.056 |
  | RMS relative error | <= 0.06 | 0.0099 |
  | frame-RMS envelope correlation | >= 0.97 | 0.9978 |

  Why not sample-exact: (a) the official reference does not reproduce its own
  golden on other MLX builds. Only mlx 0.32.0-0.32.2 reproduce the golden MD5;
  other builds give 5 distinct WAVs. (b) The pinned mlx-swift 0.31.3 wraps MLX
  core 0.31.1, while the golden was made with 0.32.0. (c) `mx.fast.rope` differs
  at the kernel-compile level between SwiftPM-compiled Metal and the Python
  wheel. (d) The SAME-S decoder is chaotic: a 1e-6 relative latent perturbation
  moves decoded patches by relL2 2.5e-2. The tolerance is the reference's own
  worst cross-build delta x 1.5, fixed before Swift was measured. Negative
  controls (other seed, prompt, steps, apg 0) all fail the gate, so it has teeth.
  Swift's result is closer to the golden than every non-golden reference build
  (best 0.345 dB / envCorr 0.9951).

---

## 2. Resolver behaviour

**Requirement (verbatim):**
> `AmbienteEngine.resolveGenerator` returns the ML backend when the model is
> installed, procedural otherwise.

**Status: MET**

**Delivered by:** S10 `592220a` (engine wiring), built on S3 `b1d3ffb` (on-demand
download in `loadGenerator`) and S2 `344da85`.

**Evidence:**
- `Sources/SwiftAmbiente/AmbienteEngine.swift`, `resolveGenerator(model:)`:
  returns `loadGenerator(repo)` result if `isModelInstalled(repo)` and the load
  succeeds, otherwise logs to stderr and returns `ProceduralAmbienteGenerator`.
- `AmbienteEngineTests`:
  - `resolveGenerator returns the procedural generator when no model is
    installed` (always runs; passes in both runs).
  - `resolveGenerator returns the stable-audio backend when the model is
    installed` (model-gated; skipped in run A, passes in run B; asserts
    `generatorId == "stable-audio"` and `isAvailable()`).
- Also covered by the CLI fix in S13b (see Deviations).
- Ran: both `make test` runs above.

**Note on the model-installed test:** it pre-hydrates the Acervo component
descriptor from the staged model's local `manifest.json`, so the
ensure/withComponentAccess flow runs against local files with no network. It
proves the resolver path, not a live CDN fetch.

---

## 3. Acervo download and CI gate

**Requirement (verbatim):**
> Model downloads through SwiftAcervo; CI gates on presence.

**Status: MET** (code and workflow committed and locally verified; the workflow
itself has never run on GitHub, see Outstanding)

**Delivered by:** S1 `904a1b4` (dependency), S2 `344da85` (component registration,
directory resolution delegated to Acervo), S3 `b1d3ffb` (on-demand download in
`loadGenerator`), S11 `6b29079` (correct repo `stabilityai/stable-audio-3-small-sfx`
and ship manifest), S12 `3dd36bb` (CDN ship verified), S13 `feeff6f` (CI wiring),
`e0712c9` and `8afec15` (test env gate fixes).

**Evidence:**
- `Sources/SwiftAmbiente/AmbienteModelManager.swift`: `modelsDirectory` returns
  `Acervo.sharedModelsDirectory`; `modelDirectory(for:)` uses `Acervo.slugify`
  (`{org}_{repo}`); `isModelInstalled` calls `Acervo.isModelAvailable`;
  `loadGenerator` calls `Acervo.ensureComponentReady` then
  `AcervoManager.shared.withComponentAccess`, with `AcervoError` mapped to
  `AmbienteError`.
- `Sources/SwiftAmbiente/StableAudioModelRepo.swift`: component descriptor
  registration.
- `AmbienteModelManagerTests` (`isModelInstalled returns false for an absent
  model, delegating to Acervo`; `modelDirectory(for:) resolves under the
  Acervo-provided shared directory`): pass in both runs.
- CI gate on presence: the tests use `.enabled(if: StableAudioModelFixture.isPresent)`
  (and `GoldenParityFixture.isModelPresent`). Run A shows the 13 model-gated
  tests skipped with no model and a green suite. Run B shows them executing.
- `.github/workflows/integration-tests.yml` (S13): `runs-on: xcode-27`; restores
  the model via `actions/cache`, primes from the CDN on a miss using the vendored
  `.github/scripts/acervo-ci-*.sh`, then runs `xcodebuild build-for-testing` and
  `test-without-building` with `TEST_RUNNER_ACERVO_MODELS_DIR` forwarded into
  the xctest runner. `tests.yml` (unit workflow, `runs-on: xcode-27`) stays
  green without a model because the neural tests skip.
- CDN ship: `3dd36bb` (S12) records the verified `acervo ship` result.
- Ran: both `make test` runs above.

**Differences from the requirement wording:**
- Local model-present runs need `TEST_RUNNER_ACERVO_MODELS_DIR` pointing at a
  plain directory (here an APFS clone at `/tmp/acervo-staging`). The xctest
  runner is denied read access to `~/Library/Group Containers/...` (EPERM), so
  the default App Group path cannot be used under `xcodebuild test`.
- Requirements item 4 said the integration tests would "likely [be] skipped on
  GitHub runners, exactly as SwiftVoxAlta does". The shipped design instead
  primes and caches the model on the runner and runs them there (the
  `acervo-integration-ci` standard). That is stronger than required, and it is
  also the least-verified part (see Outstanding).
- The run-B resolver test uses a pre-hydrated descriptor (see item 2), so no
  live CDN download is exercised by any automated test.

---

## 4. README and NOTICE

**Requirement (verbatim):**
> README "Licensing" section reflects shipped reality; NOTICE file carries
> both attributions.

**Status: MET**

**Delivered by:** S14 `f863d71` (README Licensing section and NOTICE); `9d7ae63`
(MIT LICENSE); S12 `3dd36bb` (user-owned license checklist).

**Evidence:**
- `NOTICE`: carries "This Stability AI Model is licensed under the Stability AI
  Community License, Copyright (c) Stability AI Ltd. All Rights Reserved" and
  "Powered by Stability AI"; and "Gemma is provided under and subject to the
  Gemma Terms of Use found at ai.google.dev/gemma/terms". It states the
  per-license obligations and that it is not legal advice.
- `README.md` "Licensing (read before commercial use)": sections for the
  Stability Community License, the Gemma Terms (Sections 3.1 and 3.2
  pass-through), "Verify with counsel before commercial ship", and "Configuring
  model downloads (`ACERVO_CDN_BASE_URL`)". It states the code is MIT and the
  weights are not vendored.
- Ran: `grep` / read of both files at HEAD (content confirmed above); no test
  covers documentation.

**License discrepancies documented (vs the requirements doc table):**
- Requirements said "register with Stability" under a flat "< US$1M". README and
  NOTICE give the actual text: registration is required for any Commercial
  Purpose; the US$1M test is aggregate revenue of you and your affiliates from
  any source, and licenses terminate when it is crossed.
- Requirements treat T5Gemma as a separate component. The shipped model bundles
  `t5gemma-b-b-ul2` inside the weights, so both licenses travel with one
  download. Earlier research mentioned an Apache-2.0 t5-base component; the README
  flags that no such component appears in the shipped files.
- The Gemma obligation is a Section 3.1 enforceable pass-through to end users,
  more than "attribution". The shipped `LICENSE_GEMMA.md` is dated 2026-04-01,
  and the Stability text 2024-07-05.
- Open legal ambiguities (who "distributes" runtime-downloaded weights, the
  integrated-end-user-product carve-out) are listed for counsel, not resolved.

---

## Other deviations worth recording

- **S13b `3bc65fa`: CLI neural-backend fix.** Without it the `ambienta` CLI
  silently used the procedural generator. SwiftAcervo traps without
  `ACERVO_CDN_BASE_URL`, and the MLX Metal bundle (`mlx-swift_Cmlx.bundle`) was
  not next to the installed binary. The fix defaults `ACERVO_CDN_BASE_URL` in the
  CLI (non-overwriting), copies the bundle in `make install`/release, and reports
  the rendering backend on stderr. Not covered by an automated test.
- mlx-swift is pinned `exact: "0.31.3"` (S5): 0.31.6 ships a `CudaBuild` plugin
  that fails xcodebuild plugin validation.
- Deterministic bytes are not guaranteed across MLX builds (see item 1); same
  build + same seed is byte-identical (tests above).

## Outstanding / not verified

- **First real CI run.** `.github/workflows/integration-tests.yml` has never
  executed on GitHub. The cache key script, CDN primer, cache restore and
  `TEST_RUNNER_*` forwarding are verified only by reading and by the equivalent
  local env. The runner label `xcode-27` was not exercised.
- **Branch protection.** The required-status-check contexts (job names such as
  "Integration Tests (real models)") have not been checked or updated on GitHub.
- **`release.yml` still has `runs-on: macos-26`** (`.github/workflows/release.yml:23`),
  contrary to the current `xcode-27` standard. Left untouched by this sortie.
- **Live CDN download.** No automated test performs a real network
  `ensureComponentReady`; the model-present run uses a local clone with a
  pre-hydrated descriptor. S12 verified the CDN ship separately.
- **CLI end-to-end render** with the neural backend (S13b) has no automated test.
- **User-owned license actions, not done by the mission:** register with
  Stability AI (https://stability.ai/community-license); counsel review of the
  items under "Verify with counsel before commercial ship"; add the Gemma
  pass-through to the consuming app's EULA; display "Powered by Stability AI" in
  any shipped product UI/docs.
- Sample-exact parity with the reference is not achievable and is not claimed
  (item 1).
