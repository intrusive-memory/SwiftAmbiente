---
type: docs
state: completed
updated: 2026-11-07
mission: phantom-foley-01
---

# SUPERVISOR_STATE.md — OPERATION PHANTOM FOLEY

> **Terminology**: A *mission* is the definable scope of work. A *sortie* is an
> atomic agent task within that mission. A *work unit* groups related sorties.

## Mission Metadata

- Operation: **OPERATION PHANTOM FOLEY**
- Iteration: 1
- Starting point commit: `6ba401e4a057a37b9fe3831137a0d07405377ad5`
- Mission branch: `mission/phantom-foley/01`
- Plan: `EXECUTION_PLAN.md`
- max_retries: 3
- Pre-build dependency purge: **skipped (partial — local-only)** — see Decisions Log
- Purge ran at: 2026-07-17 (project-local clean only: `.build`, `Package.resolved`, DerivedData)
- intrusive-memory floors bumped: 0 of 0 (no active intrusive-memory/* deps yet; SwiftAcervo is added by S1)

## Plan Summary

- Work units: 4
- Total sorties: 15
- Dependency structure: layers (WU1 → {WU2 ∥ WU3} → WU4)
- Dispatch mode: dynamic (no explicit template in plan)

## Work Units

| Name | Directory | Sorties | Dependencies |
|------|-----------|---------|-------------|
| WU1 — SwiftAcervo wiring | `.` | 3 (S1–S3) | none |
| WU2 — Stable Audio generator | `Sources/SwiftAmbiente` | 7 (S4–S10) | WU1 |
| WU3 — CDN distribution & licensing | `.` | 2 (S11–S12) | WU1 |
| WU4 — CI gating & docs | `.` | 3 (S13–S15) | WU2, WU3 |

## Per-Work-Unit State

### WU1 — SwiftAcervo wiring
- Work unit state: COMPLETED
- Current sortie: 3 of 3 (all done)
- Sortie state: COMPLETED
- Model: sonnet
- Last verified: S3 COMPLETED (commit b1d3ffb; independent verify: Acervo ensure/withComponentAccess wired lines 79/85, WU2 construction seam + "backend not yet implemented" throw line 101, `.serialized` AmbienteEngineTests asserts procedural fallback, `make build` OK, `make test` green on 2 independent runs, no stray source). WU1 GATE PASSED → Layer 2 open.
- Notes: S1 904a1b4, S2 344da85, S3 b1d3ffb.

### WU1-hardening — Acervo test-gate fix (remediation) — COMPLETED
- Work unit state: COMPLETED
- Sortie state: COMPLETED
- Model: sonnet
- Last verified: commit e0712c9; independent verify: tests-only (0 Sources touched), ported .acervoEnvironment trait + shared AcervoModelsDirectoryGate actor lock + single dedup'd withTempAcervoModelsDirectory helper, `make test` GREEN on 10/10 independent runs. Gate now trustworthy.
- SUPERVISOR LESSON (recorded): 2 passing runs is NOT enough to clear an env-race gate — run env-touching make test 8–10×.

### WU2-hardening-2 — model-reader vs env-mutator race — COMPLETED
- Work unit state: COMPLETED
- Sortie state: COMPLETED
- Model: sonnet
- Last verified: commit 8afec15; tests-only. Agent reproduced the fail first (T5GemmaEncoderTests reading an AmbienteEngineTests temp dir), added shared `withResolvedAcervoModelsDirectory` helper (holds AcervoModelsDirectoryGate), routed S6+S7 readers through it. Independent verify: MODEL-PRESENT make test 15/15 green, default green. Gate solid with AND without model. Helper reusable by S8/S9.

### WU2 — Stable Audio generator
- Work unit state: COMPLETED
- Current sortie: 10 of 10 (all done)
- Sortie state: COMPLETED
- Last verified: S10 COMPLETED (592220a; independent verify: model-present make test 32+5 green incl. resolveGenerator→stable-audio; no-model make test green, neural tests skipped). S9 3e6e922 (spectral parity gate, see Decisions Log). WU2 GATE PASSED → WU4 open.
- OPEN DEFECT (plan gap, surfaced to user): shipped `ambienta` CLI CRASHES when the model is installed — (a) no ACERVO_CDN_BASE_URL → SwiftAcervo fatalError (exit 133); (b) with URL → MLX "Failed to load the default metallib" (exit 255; `make install` copies no metallib into ./bin). No sortie covers CLI + neural backend.
- TEST MODEL PATH: xctest runner gets EPERM on ~/Library/Group Containers; model-present runs need TEST_RUNNER_ACERVO_MODELS_DIR=/tmp/acervo-staging (APFS clone; wiped on reboot).
- KEY PINS: mlx-swift EXACT 0.31.3. Reuse withResolvedAcervoModelsDirectory gate. ARCH: sm-sfx DiT + SAME-S decoder (S9).
- REFERENCE TO TRANSLATE FROM: ~/Projects/stable-audio-3/ (branch golden-fixture-pin @ 0385302)/optimized/mlx/models/ (MLX T5Gemma). Parity helpers: optimized/mlx/scripts/parity_forward_mlx.py + sa3_mlx.py. (Main pkg stable_audio_3/models/conditioners.py uses HF PyTorch T5Gemma — NOT the translate source.)
- T5GEMMA ENCODER CONFIG (Gemma2-style, from t5gemma-b-b-ul2/config.json encoder block): hidden 768, 12 layers, 12 heads, head_dim 64, intermediate 2048, vocab 256000, RMSNorm eps 1e-6, rope_theta 10000, gelu_pytorch_tanh, attn_logit_softcapping 50.0, sliding_window 4096 (alternating sliding/full per layer_types), query_pre_attn_scalar 64. Output 768 → conditioner proj_out → DiT. mlx-swift-lm has NO drop-in Gemma.
- KEY PINS: mlx-swift EXACT 0.31.3. Reuse serialized env test infra (e0712c9). ARCH: sm-sfx DiT + SAME-S decoder.

### WU3 — CDN distribution & licensing
- Work unit state: COMPLETED
- Current sortie: 12 of 12 (all done)
- Sortie state: COMPLETED
- Model: sonnet
- Last verified: S12 COMPLETED (commit 3dd36bb; independent verify: ACERVO_EXIT=0 + CHECK 5/6 recorded in CDN-DISTRIBUTION.md, CDN slug consistent, 11/11 checklist items flagged user-owned, both Stability + Gemma licenses named, tree clean). S11 6b29079.
- Notes: WU3 GATE PASSED. WU4 now waits only on WU2 (WU3 dependency satisfied). acervo ship SUCCESS log: /tmp/acervo-ship-stabilityai_stable-audio-3-small-sfx-20260718-045718Z.log

### WU4 — CI gating & docs
- Work unit state: COMPLETED
- Sorties: 4 (S13, S13b [added 2026-11-07, user-approved], S14, S15)
- S13: COMPLETED (feeff6f; independent verify: YAML parses, scripts `bash -n` clean, primer dry-run vs live CDN rc=0 with cached-file skip, cache key stable; CI-only diff so prior make test results stand). actionlint flags only the mandated `xcode-27` label.
- S13b: COMPLETED (3bc65fa; independent verify: make install → bin/ambienta + bin/mlx-swift_Cmlx.bundle; CDN URL unset + model installed → exit 0, `generator: stable-audio`, afinfo 2ch/44100/Int16/2.0s; empty ACERVO_MODELS_DIR → exit 0 `generator: procedural`; make test 32+5 green with and without model). CLI defect CLOSED.
- S14: COMPLETED (f863d71; independent verify: only README.md+NOTICE in commit; NOTICE grep Stability×7 Gemma×8; README ACERVO_CDN_BASE_URL L152; spot-checked $1,000,000 termination clause, community-license registration URL, 'Powered by Stability AI' placement list, Gemma §3.1 pass-through, integrated-end-user-product carve-out — all verbatim in shipped LICENSE.md/LICENSE_GEMMA.md). Found 11 plan/requirements discrepancies (pass-through is Gemma §3.1 not §3.2; registration required for any Commercial Purpose, not revenue-tied; enterprise license is discretionary; no t5-base component; Gemma has no attribution duty, only Notice line).
- S15: COMPLETED (309f08a; independent verify: ACCEPTANCE.md-only commit, 4/4 MET with evidence; tests at 3bc65fa already supervisor-verified 32+5 both modes).
- FOLLOW-UPS for user: release.yml still `runs-on: macos-26`; new "Integration Tests (real models)" job not in branch-protection required checks.

## Active Agents

| Work Unit | Sortie | Sortie State | Attempt | Model | Complexity Score | Task ID | Output File | Dispatched At |
|-----------|--------|-------------|---------|-------|-----------------|---------|-------------|---------------|
| WU1 | S1 | COMPLETED | 1/3 | sonnet | 8 | a4e0fefbf17b232a8 | tasks/a4e0fefbf17b232a8.output | 2026-07-17 |
| WU1 | S2 | COMPLETED | 1/3 | sonnet | 12 | a9e7667d1f2fc3f21 | tasks/a9e7667d1f2fc3f21.output | 2026-07-17 |
| WU1 | S3 | COMPLETED | 1/3 | sonnet | 12 | a98b1ad4be3cfad66 | tasks/a98b1ad4be3cfad66.output | 2026-07-17 |
| WU2 | S4 | COMPLETED | 1/3 | opus | 20 | a0e18e8ba42bc3249 | tasks/a0e18e8ba42bc3249.output | 2026-07-17 |
| WU2 | S5 | COMPLETED | 1/3 | opus | 16 | ae05d52bf5408fad8 | tasks/ae05d52bf5408fad8.output | 2026-07-17 |
| WU1-hardening | test-gate fix | COMPLETED | 1/3 | sonnet | 9 | a07bb85b785a52746 | tasks/a07bb85b785a52746.output | 2026-07-17 |
| WU2 | S6 | COMPLETED | 1/3 | opus | 18 | adc41cfd2379c864d | tasks/adc41cfd2379c864d.output | 2026-07-17 |
| WU2 | S7 | COMPLETED | 1/3 | opus | 22 | ac5895f7c31af59db | tasks/ac5895f7c31af59db.output | 2026-07-17 |
| WU2-hardening-2 | reader-race fix | COMPLETED | 1/3 | sonnet | 8 | ad71656ee16a5869f | tasks/ad71656ee16a5869f.output | 2026-07-17 |
| WU2 | S8 | COMPLETED | 1/3 | opus | 23 | acbb4cd054897d1fd | tasks/acbb4cd054897d1fd.output | 2026-07-17 |
| WU2 | S9 | COMPLETED (3e6e922) | 1/3 | opus | 24 | a47d06da05c179965 / wu2-s9 (start fe1c337) | tasks/a47d06da05c179965.output | 2026-11-07 |
| WU2 | S10 | COMPLETED (592220a) | 1/3 | sonnet | 9 | aa61b9f0fdb8c9a5c / wu2-s10 (start 3e6e922) | tasks/aa61b9f0fdb8c9a5c.output | 2026-11-07 |
| WU4 | S13 | COMPLETED (feeff6f) | 1/3 | sonnet | 12 | a17df4d7784b872f7 / wu4-s13 (start 592220a) | tasks/a17df4d7784b872f7.output | 2026-11-07 |
| WU4 | S13b | COMPLETED (3bc65fa) | 1/3 | sonnet | 9 | af213aa5fef6b6f4b / wu4-s13b (start feeff6f) | tasks/af213aa5fef6b6f4b.output | 2026-11-07 |
| WU4 | S14 | COMPLETED (f863d71) | 1/3 | sonnet | 5 | a55568b233e8ba142 / wu4-s14 (start feeff6f) | tasks/a55568b233e8ba142.output | 2026-11-07 |
| WU4 | S15 | COMPLETED (309f08a) | 1/3 | sonnet | 7 | a3665c7e2a50fb4c2 / wu4-s15 (start 3bc65fa) | tasks/a3665c7e2a50fb4c2.output | 2026-11-07 |
| WU3 | S11 | COMPLETED | 1/3 | sonnet | 6 | a422b1a9a2fc80d14 | tasks/a422b1a9a2fc80d14.output | 2026-07-17 |
| WU3 | S12 | COMPLETED | 1/3 | sonnet | 6 | a9340d0f1c1371518 | tasks/a9340d0f1c1371518.output | 2026-07-17 |

## Decisions Log

| Timestamp | Work Unit | Sortie | Decision | Rationale |
|-----------|-----------|--------|----------|-----------|
| 2026-07-17 | — | — | Pre-build dep purge: local-only, skip global SPM cache wipe | Zero active intrusive-memory/* deps in Package.swift (SwiftAcervo commented out until S1). Global cache wipe would force re-download across all Swift projects for no floor-bump benefit. Ran project-local clean of .build/Package.resolved/DerivedData instead. Confidence downgrade accepted per execution.md §1a failure handling. |
| 2026-07-17 | WU3 | S12 | Flag OQ-4 acervo ship as FAILED | /tmp/acervo-ship-*.log ends ==ACERVO_EXIT=1== (hf download exit 1). Root cause confirmed: "Access denied. This repository requires approval." — gated-model HF terms not accepted. Off critical path. |
| 2026-07-18 | WU3 | S12 | acervo ship RELAUNCHED (gate cleared) | User accepted the gated-model license on HF. Relaunched via /acervo-download-ship: PID 24901, log /tmp/acervo-ship-stabilityai_stable-audio-3-small-sfx-20260718-045718Z.log. Confirmed STATE=running at 17s (past the 2s access-denied failure point) — approval gate cleared. S12 will verify completion + record the success sentinel. |
| 2026-07-19 | WU2 | S9 | Decoder path: ROAD A — chase true reference parity (user decision) | Golden fixture (S4) was captured from `stable-audio-3-optimized` (MLX-converted, pre-folded `same_s_decoder_f32.npz`), but the SHIPPED `stable-audio-3-small-sfx/model.safetensors` bundles the decoder as 244 raw-PyTorch weight-norm `pretransform.model.decoder.*` tensors (weight_g/weight_v split, un-folded). Unlike DiT/T5Gemma (which mapped 1:1), the SAME-S decoder is fp-fragile (reference: catastrophic fp16 cancellation → must run FP32), so raw≠converted parity is NOT assumed. User chose to HOLD the existing byte/spectral gate against the current golden WAV: fold weight_g/weight_v→weight to match the optimized-npz layout, translate `same_s_decoder.py` op-for-op FP32, and prove parity. Supervisor recommended Road B (re-baseline on shipped weights); user overrode for a provably-identical-to-Stability backend. Accepted risk: highest-complexity sortie (24); if the raw→optimized weight conversion has silent transpose/fold drift the gate may not close on attempt 1 — expect PARTIAL/retry on the weight-mapping step. |
| 2026-07-17 | WU1 | S1 | Model: sonnet | Complexity ~8: 3-file edit (Package.swift, target deps, import), machine-verifiable exit criteria (make build/test + grep), foundation sortie but low ambiguity. Standard build-gate work. |
| 2026-07-17 | WU1 | S2 | Model: sonnet | Complexity ~12: foundational (Acervo resolution pattern reused by all of WU2, 13 dependents) but a concrete reference to mirror (VoxAltaModelManager) lowers ambiguity/risk; machine-verifiable exit (grep + temp-dir unit test). Sonnet over opus because ambiguity is low with the reference present. |
| 2026-07-17 | WU2 | S4 | Model: opus | Complexity ~20: new Python-MLX toolchain + external HF model + official-repo setup, high ambiguity (no explicit commands, env-dependent), gates all of WU2 via the golden fixture. Highest-risk sortie in the mission. Opus warranted. |
| 2026-07-17 | WU3 | S11 | Model: sonnet | Complexity ~6: source edit + doc, no build. Bumped from haiku to sonnet because changing StableAudioModelRepo.smallSFX rawValue changes Acervo.slugify(rawValue) — must stay consistent with S2's registered component ID and the CDN ship slug (real cross-file correctness constraint). |
| 2026-11-07 | WU2 | S9 | Reference relocated + model installed locally | /tmp reference clone was wiped. Re-cloned Stability-AI/stable-audio-3 to ~/Projects/stable-audio-3, branch `golden-fixture-pin` pinned to 0385302 (the S4 fixture's commit; upstream HEAD 790793b has moved). Model fetched from cdn.intrusive-memory.productions into SharedModels/stabilityai_stable-audio-3-small-sfx (manifest-driven install). |
| 2026-11-07 | WU2 | S9 | Resume: dispatch S9 attempt 1 on opus (score 24) | Reconciled state: WU2 block was stale (said S8 DISPATCHED); git 99015f1 confirms S8 done. Entry criteria met: S8 committed, model present + verified, reference pinned. Agent may provision the reference venv to dump intermediates if parity fails. |

| 2026-11-07 | WU2 | S9 | COMPLETED — spectral parity gate | Plan exit criteria explicitly permit a spectral/RMS tolerance; met with margin. Byte-exact Road A would require moving mlx-swift off exact 0.31.3 to 0.32.2+ — surfaced to user, does not block S10. |
| 2026-11-07 | WU2 | S10 | Model: sonnet (score 9) | 3–4 files, machine-verifiable criteria, concrete patterns to mirror (ProceduralAmbienteGenerator, StableAudioPipeline); WU4 depends on it. |
| 2026-11-07 | WU2 | S10 | COMPLETED; CLI defect logged | Exit criteria met (tests). Supervisor smoke-ran ./bin/ambienta with model installed: crashes in both configurations (fatalError w/o CDN URL; missing metallib with it). Plan gap — needs a user-approved fix sortie; not applied by supervisor. Agent's claim 'model not yet published' is FALSE (CDN live, fetched 2026-11-07). |
| 2026-11-07 | WU4 | S13 | Model: sonnet (score 12) | CI workflow + scripts + test gating (3–5 files), external integration risk, concrete standard to follow (/acervo-integration-ci). Independent of CLI defect. |
| 2026-11-07 | WU4 | S13b | PLAN AMENDED (user chose 'Add fix sortie') | Inserted S13b into EXECUTION_PLAN.md; S15 entry now also requires S13b. README CDN note moved into S14 (task 4 + grep exit criterion) so S13b ∥ S14 touch disjoint files. |
| 2026-11-07 | WU4 | S13b | Model: sonnet (score 9) | Makefile + CLI entry point, binary smoke checks, MLX bundle packaging risk; concrete sibling pattern (SwiftVoxAlta Makefile). |
| 2026-11-07 | WU4 | S14 | Model: sonnet (score 5, override) | Score says haiku, but the content is user-facing licensing obligations where a subtle misstatement is costly. |
| 2026-11-07 | WU4 | S15 | Model: sonnet (score 7) | Single artifact, but must map stale requirements (kellyvv port language) to shipped reality and run the model-present + model-absent suites; terminal gate. |
## Watchdog
- Timer task ID: disarmed (no active agents; mission sorties complete)
- Armed at: 2026-11-07 (20-min interval, 3 strikes)
- wu4-s15 strikes: 0/3 (no snapshot yet); (closed) wu4-s13b, wu4-s14
- (closed) wu4-s13
- (closed) wu2-s10
- (closed) wu2-s9 strikes: 0/3 — tick 1 snapshot: HEAD fe1c337, porcelain hash 17e2a6b40782 (2 new src files, 2 new test files, edits to DiT/sampler/conditioning/latent gen)
