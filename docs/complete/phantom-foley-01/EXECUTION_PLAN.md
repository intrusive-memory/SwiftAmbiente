---
type: execution-plan
feature_name: OPERATION PHANTOM FOLEY
starting_point_commit: 6ba401e4a057a37b9fe3831137a0d07405377ad5
mission_branch: mission/phantom-foley/01
iteration: 1
state: completed
updated: 2026-11-07
mission: phantom-foley-01
---

# EXECUTION_PLAN.md — SwiftAmbiente: Stable Audio Backend Integration

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Overview

Replace the interim `ProceduralAmbienteGenerator` fallback with a real neural
backend: **Stable Audio 3 Small — SFX variant**, ported to MLX Swift, with model
distribution through SwiftAcervo's shared-models CDN. Source of truth for scope
and licensing: [`REQUIREMENTS-stable-audio-integration.md`](REQUIREMENTS-stable-audio-integration.md).

**Supervisor's candor note (read before executing):** An earlier version of this
plan treated Work Unit 2 as a research-grade, from-scratch reimplementation of the
diffusion sampler, T5Gemma encoder, and decoder ported by hand from an iOS app.
A deep-research pass (2026-07-17, see **Model Selection** below) established that
Stability ships an **official Apple-Silicon MLX inference backend** in
[`Stability-AI/stable-audio-3`](https://github.com/Stability-AI/stable-audio-3)
(`optimized/mlx/`, Metal-backed, no PyTorch at runtime) plus a CoreML+TFLite path.
WU2 is therefore rescoped from "reimplement the network blind" to "**translate the
official MLX reference into MLX Swift, gated by a golden-output parity harness**."
This is a mechanical, op-for-op translation against a *correct reference* — far
lower risk than the original plan — but it is **not** free: the official reference
is Python-MLX, so a Python→Swift translation is still required (or a CoreML
binding, see Sortie 5). OQ-1/OQ-2/OQ-3 are resolved by the research; OQ-4 is
resolved 2026-07-18 by user override (agent runs `acervo ship`; license
acceptance stays user-owned).

---

## Model Selection

Decision recorded from the deep-research pass of **2026-07-17** (23 adversarially
verified findings). Full landscape and licensing detail in that report; the
operative conclusions:

- **Chosen backend: Stable Audio 3 Small — SFX variant**
  (`stabilityai/stable-audio-3-small-sfx`, 0.6B params, SFX-focused latent
  diffusion). It is the only candidate that is (a) purpose-built for foley/SFX,
  (b) commercially licensable, and (c) has an **official Apple-Silicon MLX
  backend** — no blind reimplementation required.
- **Commercial gate (clears, with obligations):** Stability AI Community License —
  free commercial use **below ~US$1M annual revenue** (across all sources),
  **registration with Stability required for any commercial use**, license
  **terminates** above $1M (must request an Enterprise License). This is a live,
  revenue-tracked obligation, not a one-time check.
- **Compound licensing:** the SFX model bundles the **T5Gemma** text encoder,
  redistributed under **Google's Gemma Terms of Use** — a *separate* custom
  license with §3.2 use restrictions + a Prohibited Use Policy that must be
  **passed through to end users**. Commercial shipping is gated by **both**
  licenses. (The older `stable-audio-open-1.0` uses Apache-2.0 t5-base instead —
  cleaner, but 1.1B and no official MLX path; retained as a fallback only.)
- **Rejected — ElevenLabs Sound Effects:** high quality, but cloud-only and its
  ToS (§9.j) **prohibits using output to build competing SFX products/services** —
  disqualifying for this product.
- **Rejected — Meta AudioGen (non-commercial), TangoFlux (license unverified;
  the CC-BY-SA claim was refuted 0-3).**

**Must legally verify before commercial ship** (flag for counsel, not the agent):
Gemma Terms pass-through obligations for an embedded Swift library; the
Apache-2.0 status of t5-base (Stability's card is silent); and the current $1M
threshold + registration mechanics at `stability.ai/license`.

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| WU1 — SwiftAcervo wiring | `.` | 3 (S1–S3) | 1 | none |
| WU2 — Stable Audio generator (translate official MLX backend) | `Sources/SwiftAmbiente` | 7 (S4–S10) | 2 | WU1 |
| WU3 — CDN distribution & licensing gate | `.` | 2 (S11–S12) | 2 | WU1 |
| WU4 — CI gating & shipped-reality docs | `.` | 3 (S13–S15) | 3 | WU2, WU3 |

Layer semantics: Layer 1 must complete before Layer 2; Layer 2 before Layer 3.
WU2 and WU3 (both Layer 2) run in parallel once WU1 is verified. See
**Parallelism Structure** below.

Priority scores use `priority = (dependency_depth × 3) + (foundation_score × 2) +
(risk_level × 1) + (complexity × 0.5)`; higher = execute earlier. The existing
sortie order already satisfies priority within all hard dependency/layer
constraints, so Pass 3 reordered **0** sorties — it only annotated scores.

---

## WU1 — SwiftAcervo Wiring

Goal: give the model manager a real, Acervo-backed model directory and on-demand
download, mirroring the SwiftVoxAlta pattern. No neural code here — this is the
foundation WU2 plugs into.

### Sortie 1: Add the SwiftAcervo dependency to the build graph

**Priority**: 45.75 — highest; unblocks all 14 downstream sorties and establishes
the dependency all neural code links against.

**Entry criteria**:
- [ ] First sortie — no prerequisites.
- [ ] `make build` is green on the starting commit.

**Tasks**:
1. Uncomment the staged `sibling("SwiftAcervo", …)` block in `Package.swift`
   (lines ~63–66), pinning `from:` to SwiftAcervo's latest released version
   (resolve at dispatch time; do not hardcode here).
2. Add `SwiftAcervo` to the `SwiftAmbiente` target's `dependencies` array via
   `.product(name: "SwiftAcervo", package: "SwiftAcervo")`.
3. Add `import SwiftAcervo` to `AmbienteModelManager.swift` (no behavior change
   yet — just prove the module links).

**Exit criteria**:
- [ ] `make build` succeeds with SwiftAcervo resolved and linked.
- [ ] `make test` passes (existing procedural/config tests unaffected).
- [ ] `grep -q "SwiftAcervo" Package.swift` and the commented staged block is gone.

### Sortie 2: Register components and replace directory resolution with Acervo

**Priority**: 44.0 — establishes the Acervo directory-resolution pattern reused
by every WU2 sortie; blocks 13 downstream.

**Entry criteria**:
- [ ] Sortie 1 exit criteria met (SwiftAcervo linked, `make build` green).

**Tasks**:
1. Add an Acervo component ID to `StableAudioModelRepo` computed as
   `Acervo.slugify(rawValue)` (mirror `VoxAltaModelManager`'s
   `qwen3TTSComponentDescriptors` registration pattern).
2. Register bare component descriptors for the SFX (and music) repos with the
   SwiftAcervo Component Registry at manager init (`Acervo.register(...)`).
3. Rewrite `AmbienteModelManager.sharedModelsDirectory` /
   `modelDirectory(for:)` / `isModelInstalled(_:)` to delegate to
   `Acervo.sharedModelsDirectory` and `Acervo.isModelAvailable(_:)` instead of
   the hand-rolled env/`~/Library/SharedModels` resolution.
4. Preserve the `config.json`-presence-means-valid contract (Acervo enforces it).

**Exit criteria**:
- [ ] `make build` and `make test` pass.
- [ ] `AmbienteModelManager` no longer reads `ACERVO_MODELS_DIR` or
      `homeDirectoryForCurrentUser` directly (`grep` confirms the manual
      resolution is gone).
- [ ] A unit test asserts `isModelInstalled` returns `false` for an absent model
      and delegates to Acervo (using a temp Acervo dir).

### Sortie 3: On-demand download plumbing in `loadGenerator`

**Priority**: 41.0 — completes WU1 (the Layer-1 gate); establishes the
construction seam WU2 Sortie 10 plugs into; blocks all of Layer 2 and 3.

**Entry criteria**:
- [ ] Sortie 2 exit criteria met.

**Tasks**:
1. In `AmbienteModelManager.loadGenerator(_:)`, replace the env/default TODO with
   an Acervo `ensureComponentReady` / `withComponentAccess` call that downloads
   the model on first use (mirror `VoxAltaModelManager`'s v2 access pattern).
2. Map `AcervoError` cases onto `AmbienteError` (checksum failure, size
   mismatch, manifest HTTP error → `.modelNotAvailable` / `.generationFailed`
   with descriptive messages).
3. Leave a single, clearly-marked construction seam where WU2 will instantiate
   the MLX generator; until then, after a successful ensure, throw
   `AmbienteError.modelNotAvailable("backend not yet implemented")` so the engine
   still falls back to procedural.

**Exit criteria**:
- [ ] `make build` and `make test` pass.
- [ ] `loadGenerator` calls an Acervo download/ensure API (`grep` confirms).
- [ ] `AmbienteEngine.resolveGenerator` still returns the procedural generator
      when no model is present (existing behavior preserved; verified by test).

---

## WU2 — Stable Audio Generator (translate official MLX backend)

Goal: a `StableAudioGenerator` type conforming to `AmbienteGenerator`
(`generatorId = "stable-audio"`) that runs Stable Audio 3 Small SFX on Apple
Silicon and honours `GenerationSettings.steps`, `cfgScale`, `seed`,
`durationSeconds`. **Source of truth is Stability's official
[`Stability-AI/stable-audio-3`](https://github.com/Stability-AI/stable-audio-3)
`optimized/mlx/` reference** — every network module is translated op-for-op from
that reference (or bound via CoreML per Sortie 5), NOT reimplemented from a paper
or an iOS app. Technical open questions OQ-1/OQ-2/OQ-3 are resolved.

**Golden-output rule for the whole work unit:** Sortie 4 captures reference audio
from the official backend for a fixed prompt+seed; Sorties 7–9 assert the Swift
output matches it within a documented tolerance, and Sortie 9 gates the final
audio parity. No sortie is complete until its module matches the reference — this
is what keeps a mechanical translation honest.

### Sortie 4: Stand up the official reference & capture the golden-output fixture

**Priority**: 33.25 — highest-risk WU2 sortie (new toolchain + Python
environment); produces the golden fixture reused by Sorties 9's parity gate.

**Entry criteria**:
- [ ] WU1 complete (Acervo-backed model dir + download available).

**Tasks**:
1. Set up Stability's official `optimized/mlx` backend (Python-MLX) and run it
   against the downloaded SFX model for a **fixed prompt + fixed seed + fixed
   steps + fixed cfg**.
2. Capture the resulting WAV as a committed test fixture (the "golden output") at
   a named path under `Tests/`, and record the exact reference invocation
   alongside it.

**Exit criteria**:
- [ ] A committed golden-output WAV fixture at a named path (e.g.
      `Tests/Fixtures/golden-<prompt-slug>-seed<N>.wav`).
- [ ] The exact reference invocation (prompt, seed, steps, cfg) is recorded in a
      committed note so the fixture is reproducible.
- [ ] No Swift build is required by this sortie (reference is Python-MLX).

### Sortie 5: MLX-Swift-vs-CoreML strategy decision + add the dependency

**Priority**: 29.75 — commits the WU2 execution toolchain reused by Sorties 6–10;
blocks the rest of WU2.

**Entry criteria**:
- [ ] Sortie 4 exit criteria met (golden fixture + reference invocation exist).

**Tasks**:
1. Decide the Swift execution strategy: (a) translate the network to **MLX Swift**
   (via the `mlx-swift` toolchain `mlx-audio-swift` already pulls in), or (b)
   convert the model to **CoreML** and bind from Swift. Record the trade-off in
   `Sources/SwiftAmbiente/StableAudio/STRATEGY.md` (CoreML avoids reimplementing
   the net in Swift but is harder to seed deterministically; MLX Swift maps 1:1 to
   the Python reference).
2. Add the chosen dependency to `Package.swift` + the `SwiftAmbiente` target.

**Exit criteria**:
- [ ] `Sources/SwiftAmbiente/StableAudio/STRATEGY.md` exists and records the
      MLX-Swift-vs-CoreML decision + rationale.
- [ ] `make build` succeeds with the chosen dependency linked.
- [ ] `grep` confirms the chosen dependency is present in `Package.swift`.

### Sortie 6: Config + weight/asset loading

**Priority**: 24.0 — establishes the config/asset-loading substrate reused by
Sorties 7–10.

**Entry criteria**:
- [ ] Sortie 5 exit criteria met.

**Tasks**:
1. Create the `Sources/SwiftAmbiente/StableAudio/` module content and a
   `StableAudioModelConfig` type parsing the model's `config.json` (sample rate,
   latent dims, DiT hyperparameters, tokenizer/encoder config).
2. Load the model assets from the Acervo model directory (safetensors → MLX
   arrays, or the converted CoreML package per Sortie 5); assert expected
   tensor/layer names and shapes exist.

**Exit criteria**:
- [ ] `make build` passes.
- [ ] A model-gated test (skipped via `XCTSkipUnless`/`@Test(.enabled(if:))` when
      the model is absent) loads `config.json` + at least one weight/layer and
      asserts a known shape.

### Sortie 7: T5Gemma text conditioning (translate from reference)

**Priority**: 22.25 — new-tech translation; conditioning tensor feeds the sampler.

**Entry criteria**:
- [ ] Sortie 6 exit criteria met.

**Tasks**:
1. Translate the T5Gemma text-encoder path from the official `optimized/mlx`
   reference into the chosen Swift strategy (the encoder ships *inside* the
   backend — this is translation, not a from-scratch Gemma port).
2. Tokenize a prompt and produce the conditioning tensor(s) the DiT expects.
3. Model-gated test asserting encoder output shape/dtype for a fixed prompt, and
   (where feasible) numerical closeness to the reference encoder output.

**Exit criteria**:
- [ ] `make build` passes.
- [ ] Model-gated test produces a conditioning tensor of the documented shape for
      a fixed prompt (skipped when the model is absent).

### Sortie 8: Diffusion sampler (DiT) with steps/cfg/seed

**Priority**: 19.5 — highest algorithmic complexity in WU2; produces the latent
the decoder consumes.

**Entry criteria**:
- [ ] Sortie 7 exit criteria met.

**Tasks**:
1. Translate the DiT diffusion sampler from the official reference into the
   chosen Swift strategy.
2. Wire `GenerationSettings.steps` → sampler step count, `cfgScale` →
   classifier-free guidance, `seed` → deterministic RNG seeding matching the
   reference's seeding scheme.
3. Produce a latent tensor of the expected shape for `durationSeconds`.

**Exit criteria**:
- [ ] `make build` passes.
- [ ] Model-gated test: same seed → byte-identical latents across two runs;
      different seeds diverge.

### Sortie 9: Decode to WAV + golden-output parity

**Priority**: 16.25 — closes the audio pipeline and enforces the golden-output
parity gate for the whole work unit.

**Entry criteria**:
- [ ] Sortie 8 exit criteria met.

**Tasks**:
1. Translate the decoder (autoencoder/VAE) path from the reference to produce a
   44.1 kHz stereo waveform from the Sortie 8 latent.
2. Encode to interleaved WAV via the existing `WAVWriter`, matching
   `AmbienteConfig.default`.
3. Assert output matches the Sortie 4 golden fixture within a documented
   spectral/RMS tolerance; record the tolerance + observed delta in `STRATEGY.md`.

**Exit criteria**:
- [ ] `make build` passes.
- [ ] The produced WAV passes the WAV-contract checks (valid 44-byte header,
      44.1 kHz, stereo, non-empty).
- [ ] Model-gated parity test: Swift waveform matches the golden fixture within
      the documented tolerance; tolerance + observed delta recorded in
      `STRATEGY.md`.

### Sortie 10: `StableAudioGenerator` conformance & engine wiring

**Priority**: 14.25 — defines the public generator type consumed by WU4 tests;
completes WU2.

**Entry criteria**:
- [ ] Sortie 9 exit criteria met.

**Tasks**:
1. Define `struct StableAudioGenerator: AmbienteGenerator` with
   `generatorId = "stable-audio"`, `isAvailable()`, `generate(prompt:settings:)`,
   composing the Sortie 6–9 pipeline.
2. Wire it into the WU1 construction seam in
   `AmbienteModelManager.loadGenerator` (replacing the
   `"backend not yet implemented"` throw from Sortie 3).

**Exit criteria**:
- [ ] `make build` and `make test` pass.
- [ ] `StableAudioGenerator` passes the same WAV-contract tests the procedural
      generator does (valid 44-byte header, 44.1 kHz, stereo, non-empty).
- [ ] Model-gated test: `AmbienteEngine.resolveGenerator` returns the
      `stable-audio` backend when the model is installed.

---

## WU3 — CDN Distribution & Licensing Gate

Goal: make the Small SFX weights installable through Acervo's CDN, gated on
license acceptance. Per OQ-4 the agent **runs the `acervo ship` upload** (launched
in the background during refinement) but does **not** accept license terms or
register on the user's behalf — license acceptance/registration stays user-owned.

### Sortie 11: Correct repo IDs & prepare the ship manifest

**Priority**: 15.5 — corrects the slug that S12, the CDN ship, and CI all depend
on; runs in parallel with WU2 (see Parallelism Structure).

**Entry criteria**:
- [ ] WU1 complete.

**Tasks**:
1. Correct `StableAudioModelRepo` raw values to the research-verified upstream HF
   repo ID **`stabilityai/stable-audio-3-small-sfx`** (the scaffold's
   `stable-audio-open-small-sfx` is stale — it predates the Stable Audio 3
   family). Update the music/parity case to the matching SA3 repo if one exists,
   or drop it as out of scope.
2. Document the `acervo ship stabilityai/stable-audio-3-small-sfx` invocation and
   the resulting `stabilityai_stable-audio-3-small-sfx` slug, matching the Acervo
   `{org}_{repo}` convention (and keep it consistent with the Acervo component ID
   from WU1 Sortie 2).

**Exit criteria**:
- [ ] `StableAudioModelRepo.smallSFX` raw value is
      `stabilityai/stable-audio-3-small-sfx` (`grep` confirms).
- [ ] A `CDN-DISTRIBUTION.md` note records the exact `acervo ship` command and
      resulting slug, with the dual-license-acceptance prerequisite called out.

### Sortie 12: Verify CDN ship + license-acceptance checklist

**Priority**: 11.75 — completes WU3; gates WU4's WU3 dependency.

**Entry criteria**:
- [ ] Sortie 11 exit criteria met.

**Tasks**:
1. Verify the background `acervo ship stabilityai/stable-audio-3-small-sfx`
   (launched during refinement, OQ-4) completed: confirm the CDN slug
   `stabilityai_stable-audio-3-small-sfx` is present/available and record the
   ship's success sentinel (from the `/tmp/acervo-ship-*.log`) in
   `CDN-DISTRIBUTION.md`. If the ship is still running or failed, record its
   state and relaunch per the `/acervo-download-ship` skill.
2. Produce a checklist covering: Stability AI Community License registration +
   "Powered by Stability AI" display obligation, and Google Gemma Terms
   attribution + prohibited-use acknowledgement.
3. Mark every *license-acceptance/registration* item as a **human action** (the
   upload mechanic is agent-run per OQ-4, but the agent must NOT accept terms or
   register on the user's behalf).

**Exit criteria**:
- [ ] `CDN-DISTRIBUTION.md` records the ship outcome (log success sentinel +
      resolvable CDN slug) and a license checklist where every legal-acceptance
      action is flagged user-owned.
- [ ] No sortie accepts Stability/Gemma terms or performs license registration
      (`grep` of the checklist shows every legal item marked user-owned).

---

## WU4 — CI Gating & Shipped-Reality Docs

Goal: gate integration tests on model presence (skipped on GitHub runners, per
the `acervo-integration-ci` standard, exactly as SwiftVoxAlta does) and update
README/NOTICE to reflect the shipped licensing reality.

### Sortie 13: Wire model-gated integration CI

**Priority**: 9.0 — establishes the CI gate; blocks the two remaining docs sorties.

**Entry criteria**:
- [ ] WU2 complete (a real generator exists to test).
- [ ] WU3 complete (model shippable via CDN).

**Tasks**:
1. Apply the `/acervo-integration-ci` standard: vendor the CDN primer +
   cache-key script, add/update the integration-tests workflow to restore models
   via `actions/cache` and prime on miss, forward `TEST_RUNNER_ACERVO_*` env.
2. Normalize every model-dependent test's gate to model presence
   (`XCTSkipUnless` / `@Test(.enabled(if:))`) so the suite is green on runners
   without the model.

**Exit criteria**:
- [ ] Integration-tests workflow exists and references the Acervo cache
      (`grep` confirms `actions/cache` + `TEST_RUNNER_ACERVO_`).
- [ ] `make test` is green locally with no model present (all neural tests skip,
      not fail).

### Sortie 13b: Make the `ambienta` CLI run the neural backend (added 2026-11-07, user-approved)

**Priority**: 8.0 — fixes a shipped-binary crash discovered after S10; runs
parallel to S14 (disjoint files) and gates S15.

**Why this exists**: after S10, `./bin/ambienta` crashes on any machine where the
Stable Audio model is installed: (a) no `ACERVO_CDN_BASE_URL` → SwiftAcervo
`fatalError` (exit 133); (b) with the URL set → MLX `Failed to load the default
metallib` (exit 255), because `make install`/`make release` copy only the binary.

**Entry criteria**:
- [ ] Sortie 13 exit criteria met (commit `feeff6f`).

**Tasks**:
1. Give the CLI a default CDN base URL
   (`https://cdn.intrusive-memory.productions/models`) that an explicitly set
   `ACERVO_CDN_BASE_URL` still overrides, applied in the CLI entry point before
   any engine call. The **library** must not hard-code a CDN URL (consumer choice
   per SwiftAcervo's contract).
2. Make `make install` and `make release` copy `mlx-swift_Cmlx.bundle` from the
   build products directory next to the binary in `./bin`, mirroring
   `../SwiftVoxAlta/Makefile`.
   (The README note about consumer CDN configuration lives in Sortie 14 so the
   two parallel sorties never edit the same file.)

**Exit criteria**:
- [ ] `make install` leaves `bin/ambienta` and `bin/mlx-swift_Cmlx.bundle`.
- [ ] With the model installed and `ACERVO_CDN_BASE_URL` **unset**,
      `./bin/ambienta -d 2 --seed 42 --output <tmp>.wav heavy rain on a tin roof`
      exits 0 and writes a valid 44.1 kHz stereo WAV produced by the
      `stable-audio` backend (CLI output or a verbose flag shows the backend id).
- [ ] With the model absent (e.g. `ACERVO_MODELS_DIR` pointed at an empty dir),
      the same command exits 0 via the procedural backend.
- [ ] `make build` and `make test` green.

### Sortie 14: README "Licensing" section & NOTICE file

**Priority**: 4.75 — docs; can run on a sub-agent (no build) once S13 lands.

**Entry criteria**:
- [ ] Sortie 13 exit criteria met.

**Tasks**:
1. Update the README "Licensing" section to reflect shipped reality: the
   **Stability AI Community License** (free commercial use < ~US$1M revenue,
   mandatory registration, termination above $1M) **and** the **Google Gemma
   Terms of Use** governing the bundled T5Gemma encoder — including the §3.2 use
   restrictions and Prohibited Use Policy that must be **passed through to end
   users** of any app embedding this library.
2. Add/extend a `NOTICE` file carrying both attributions, the "Powered by
   Stability AI" display obligation, and the Gemma prohibited-use pass-through.
3. Add a "verify with counsel before commercial ship" callout listing the
   ambiguous items surfaced by research (Gemma pass-through mechanics for an
   embedded library; t5-base Apache-2.0 status; current $1M/registration terms).
4. (added 2026-11-07 with S13b) Add a short README note that apps embedding the
   library must configure `ACERVO_CDN_BASE_URL` (env) or `AcervoCDNBaseURL`
   (Info.plist) to use the neural backend — SwiftAcervo traps without it — and
   that the `ambienta` CLI ships a default.

**Exit criteria**:
- [ ] README "Licensing" section names both licenses, the "Powered by Stability
      AI" obligation, the $1M/registration terms, and the Gemma pass-through.
- [ ] `NOTICE` file exists with both attributions (`grep` confirms "Stability"
      and "Gemma").
- [ ] README mentions `ACERVO_CDN_BASE_URL` (`grep` confirms).

### Sortie 15: Acceptance-criteria verification pass

**Priority**: 1.75 — terminal verification; depends on everything above.

**Entry criteria**:
- [ ] Sortie 14 exit criteria met.
- [ ] Sortie 13b exit criteria met (CLI renders with the neural backend).

**Tasks**:
1. Walk the four acceptance checkboxes in the requirements doc and verify each
   against the shipped code (conformance + WAV contract, resolver behavior,
   Acervo download + CI gate, README/NOTICE).
2. Produce an `ACCEPTANCE.md` mapping each acceptance item to the sortie(s) and
   test(s) that satisfy it.

**Exit criteria**:
- [ ] `ACCEPTANCE.md` exists; every requirements-doc acceptance checkbox maps to
      a passing test or committed artifact.
- [ ] `make build` and `make test` green.

---

## Parallelism Structure

**Critical Path**: S1 → S2 → S3 → S4 → S5 → S6 → S7 → S8 → S9 → S10 → S13 → S14 →
S15 (length: **13 sorties**). The WU2 chain (S4–S10, 7 sorties) dominates the
shorter WU3 chain (S11–S12), so WU3 is entirely off the critical path.

**Parallel Execution Groups**:
- **Group 1** (Layer 1 — sequential, single agent): S1 → S2 → S3. WU1 is an
  internal chain (each sortie depends on the prior); no intra-unit parallelism.
- **Group 2** (Layer 2 — two concurrent tracks after WU1 verified):
  - **WU2 track (Agent 1 = SUPERVISING AGENT ONLY)**: S4 → S5 → S6 → S7 → S8 →
    S9 → S10. Every WU2 sortie has a `make build`/`make test` step, so the whole
    chain stays on the supervising agent.
  - **WU3 track (Agent 2 = sub-agent, NO BUILD)**: S11 → S12. Both are
    source-edit + doc + CLI-verify work whose exit criteria are `grep`/file/CDN
    checks, not builds. The supervising agent build-verifies S11's
    `StableAudioModelRepo` edit at the next WU2 build.
- **Group 3** (Layer 3 — after WU2 **and** WU3 complete): S13 → S14 → S15. S14 is
  docs-only (sub-agent capable) but depends on S13, so the track is effectively
  sequential.

**Agent Constraints**:
- **Supervising agent**: handles all sorties with build/compile steps — all of
  WU1, all of WU2, S13, and S15.
- **Sub-agents (up to 4; only ~1 useful here)**: WU3 (S11–S12) and S14 carry no
  build steps and can run on a sub-agent. The dependency structure only affords
  **2 concurrent tracks** at peak (WU2 ∥ WU3), so max useful parallelism is
  1 supervising + 1 sub-agent.

**Missed opportunities / notes**:
- WU3 (S11–S12) is short and fully parallel with WU2; it will finish long before
  WU2, satisfying WU4's WU3 dependency early. Dispatch S11 immediately after WU1,
  concurrently with S4.
- Intra-WU2 parallelism is near-zero by nature: config → encoder → sampler →
  decoder → generator is a strict data-dependency chain.
- The `acervo ship` upload (OQ-4) is already running in the background from
  refinement, so it does not consume a critical-path sortie; S12 only *verifies*
  it.

---

## Open Questions

<!-- Consumed by Pass 1 of refine (`refine-blockers`). All resolved. -->

### OQ-1: Which MLX foundation and decoder do we build on? — ✅ RESOLVED (2026-07-17)
**Affects**: WU2 (Sorties 4–10)
**Resolution**: Translate Stability's **official `optimized/mlx` reference** from
[`Stability-AI/stable-audio-3`](https://github.com/Stability-AI/stable-audio-3)
into MLX Swift (on the `mlx-swift` toolchain that `mlx-audio-swift` already
pulls in), OR bind the CoreML+TFLite conversion — the strategy choice is a
documented spike in **Sortie 5**, gated by the golden fixture from **Sortie 4**.
The earlier "SAME-S vs DACVAE" question is moot: the decoder is whatever the
official reference ships, translated op-for-op and validated against a
golden-output fixture. **No from-scratch reimplementation, and no port from the
iOS app.**

### OQ-2: Is there an MLX Swift T5Gemma to reuse, or a full port? — ✅ RESOLVED (2026-07-17)
**Affects**: Sortie 7
**Resolution**: Neither — the T5Gemma encoder ships **inside** the official MLX
backend, so Sortie 7 *translates* it from the reference rather than porting a
Gemma model from scratch. Licensing consequence: T5Gemma is redistributed under
**Google's Gemma Terms of Use**, a separate license that must be cleared and
passed through (now captured in WU3 Sortie 12 and WU4 Sortie 14).

### OQ-3: What are the real upstream HuggingFace repo IDs? — ✅ RESOLVED (2026-07-17)
**Affects**: Sortie 6, Sortie 11 (and `StableAudioModelRepo` correctness)
**Resolution**: The verified target is **`stabilityai/stable-audio-3-small-sfx`**
(Stable Audio 3 family). The scaffold's `stable-audio-open-small-sfx` is stale.
Weights are Stability-hosted; the official repo provides the MLX/CoreML
conversion path, so no independent PyTorch→MLX conversion is required beyond what
the reference documents. `StableAudioModelRepo` is corrected in Sortie 11.

### OQ-4: Scope of the agent's role in CDN upload & license acceptance — ✅ RESOLVED (2026-07-18, user override)
**Affects**: Sortie 11, Sortie 12
**Question**: Should the mission stop at *preparing* the CDN ship + license
checklist, leaving the actual `acervo ship` upload and terms-acceptance to the
user, or is the agent authorized to run `acervo ship`?
**Source**: Work items §3; Licensing obligations § (BLOCKING for commercial use).
**Resolution (user override of breakdown's recommendation)**: The agent **is
authorized to run the `acervo ship` upload** via the `/acervo-download-ship`
skill. Per the user's instruction it is launched **early, in the background,
during refinement** so the multi-GB mirror can complete before the mission does
(kicked off 2026-07-18: `acervo ship stabilityai/stable-audio-3-small-sfx
--no-verify`). **The upload mechanic is now in agent scope.**
**Still user-owned (NOT delegated by this override)**: all *license
acceptance/registration* — Stability AI Community License registration + "Powered
by Stability AI" display, and Google Gemma Terms acceptance + prohibited-use
pass-through. Running `acervo ship` mirrors weights but does **not** discharge
these legal obligations; the Sortie 12 checklist remains, flagged user-owned.
**Prerequisite the override assumes**: the HF token used by `acervo ship` has
already accepted the gated `stabilityai/stable-audio-3-small-sfx` model terms on
HuggingFace (a download precondition, not something the agent can grant itself).

---

## Open Questions & Missing Documentation

<!-- Pass 5 output: vague criteria / lingering questions surfaced after Passes 2–4. -->

Pass 5 scanned all 15 sorties after the atomicity splits and priority/parallelism
annotations. No **blocking** open questions or missing-documentation references
remain (STRATEGY.md, CDN-DISTRIBUTION.md, NOTICE, ACCEPTANCE.md, and the golden
fixture are each created by a named sortie before any sortie consumes them).

One soft criterion was tightened rather than left vague:

| Sortie | Issue Type | Original | Auto-fix applied |
|--------|-----------|----------|------------------|
| S12 | Vague criterion | "CDN slug resolvable" | Now requires recording the `acervo ship` **log success sentinel** + the resolvable slug in `CDN-DISTRIBUTION.md` — machine-checkable against `/tmp/acervo-ship-*.log`. |

No issues require manual resolution.

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 4 |
| Total sorties | 15 (was 13; Pass 2 split S4 and S8) |
| Open questions | 0 unresolved — OQ-1/2/3 resolved by research 2026-07-17; OQ-4 resolved 2026-07-18 (user override: agent runs `acervo ship`, license acceptance stays user-owned) |
| Dependency structure | 3 layers (WU1 → {WU2 ∥ WU3} → WU4) |
| Critical path | 13 sorties (WU1 → WU2 → WU4; WU3 off critical path) |
| Parallelism | 1 supervising agent + 1 useful sub-agent (WU2 ∥ WU3) |
| Model backend | Stable Audio 3 Small SFX via official MLX reference (translated to Swift) |
</content>
</invoke>
