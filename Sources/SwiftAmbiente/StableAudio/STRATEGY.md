---
type: doc
title: Swift execution strategy for the Stable Audio 3 Small SFX port
sortie: S5 (OPERATION PHANTOM FOLEY, WU2)
decision: MLX Swift (ml-explore/mlx-swift)
status: decided
---

# Stable Audio backend — MLX Swift vs CoreML strategy decision

**Decision: translate the official Python-MLX reference into MLX Swift**
(`ml-explore/mlx-swift`). CoreML is rejected as the execution strategy.

## Context

Sortie 4 captured the golden-output fixture
(`Tests/Fixtures/golden-rain-on-tin-roof-seed42.wav`) from Stability AI's
**official Apple-Silicon Python-MLX** backend (`Stability-AI/stable-audio-3`,
`optimized/mlx/`): `--dit sm-sfx --decoder same-s`, MLX-converted weights from
`stabilityai/stable-audio-3-optimized`, `mlx 0.32.0`. Sorties 7–9 must reproduce
that exact waveform within a documented tolerance, and Sortie 9 makes byte/latent
and spectral parity against that fixture the gate for the whole work unit.

The deciding constraint for this sortie is therefore **the golden-output parity
gate**, and specifically **deterministic seed parity with the Python-MLX
reference's RNG scheme** (Sortie 8 requires same-seed → identical latents,
matching the reference seeding).

## Option A — MLX Swift (CHOSEN)

`ml-explore/mlx-swift` is the Swift binding of the same MLX runtime the reference
is built on. It maps **op-for-op and RNG-for-RNG** to Python MLX: the array ops,
NN layers, FFT, and the `MLXRandom` PRNG follow the same algorithms and seeding
semantics as the Python `mlx`/`mlx.core.random` the reference uses. That makes the
WU2 work a **mechanical, op-for-op translation against a correct reference**, and
it makes deterministic seed parity with the golden fixture *achievable* rather
than a reverse-engineering exercise.

Concretely this is what the parity gate needs:

- **Seed parity (Sortie 8):** `MLXRandom.seed(_:)` / keyed RNG in mlx-swift mirror
  Python MLX's `mlx.core.random` key/split scheme, so the reference's `--seed 42`
  can be reproduced. CoreML has no equivalent hook into that PRNG stream.
- **Numerical parity (Sorties 7 & 9):** identical MLX kernels on the same Metal
  backend give the closest achievable match to the reference's intermediate
  tensors and final waveform, keeping the tolerance in Sortie 9 tight and
  honest.
- **Translation, not reimplementation:** the network (DiT sampler, T5Gemma
  encoder, SAME-S decoder) is copied module-for-module from a *known-correct*
  Python-MLX source into the same primitives in Swift — far lower risk than a
  blind paper reimplementation.
- **Ecosystem fit:** the sibling package `../mlx-audio-swift` (product `MLXAudio`)
  already depends on `ml-explore/mlx-swift`, so the toolchain is proven in this
  collection and the dependency graph stays coherent (see version note below).

Cost, stated honestly: the network must be hand-translated from Python to Swift
(Sorties 6–9). It is not free — but it is mechanical against a correct reference,
and it is the only path that keeps the parity gate reachable.

## Option B — CoreML conversion + Swift binding (REJECTED)

Converting the model to a CoreML package and calling it from Swift would avoid
reimplementing the network in Swift, which is genuinely attractive on effort. It
is rejected because it defeats the parity gate:

- **No deterministic seed parity.** CoreML gives no access to the MLX PRNG stream;
  reproducing the reference's `--seed 42` latents (Sortie 8's exit criterion of
  same-seed → identical latents matching the reference) becomes intractable. Any
  in-graph or externally-supplied noise would diverge from `mlx.core.random`,
  breaking the golden-output comparison.
- **Extra conversion step + drift.** A PyTorch/MLX → CoreML conversion introduces
  its own numerical drift (op fusion, precision changes, unsupported-op fallbacks)
  on top of the seed problem, widening the tolerance the parity gate is meant to
  keep tight, and adding a model-conversion artifact to maintain and re-verify.
- **The reference is MLX, not CoreML.** The official backend and the Sortie 4
  fixture are Python-MLX; MLX Swift is the 1:1 counterpart. CoreML would compare
  against the fixture across two runtimes, not one.

## Consequence for this sortie

Add `ml-explore/mlx-swift` to the build graph and link it from the StableAudio
module (products `MLX`, `MLXNN`, `MLXRandom`, `MLXFFT` — the primitives Sorties
6–9 need: arrays/ops, NN layers, deterministic RNG, and FFT). The mlx-swift
version is **pinned to match the sibling `../mlx-audio-swift` package**
(`exact: "0.31.3"`, the version that package's lockfile resolves to) so a single
mlx-swift identity resolves across the whole collection graph and cannot
conflict. Note: the open range `.upToNextMajor(from: "0.31.3")` drifts up to
`0.31.6`, which ships a `CudaBuild` build-tool plugin that fails xcodebuild's
plugin validation on macOS; `0.31.3` predates that plugin and builds clean, so
the pin is exact.

Sortie 9 will record the final parity tolerance and observed delta below when the
pipeline is complete.

<!-- Sortie 9: parity tolerance + observed delta recorded here. -->
