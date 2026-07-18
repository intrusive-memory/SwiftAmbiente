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

## Sortie 6 note — weights format loaded (read before S7–S9)

Sortie 6 parses `model_config.json` (note: **not** `config.json`) and loads
`model.safetensors` via MLX Swift's `MLX.loadArrays(url:)` (safetensors →
`[String: MLXArray]`, lazy — shape/dtype are readable without materializing the
2.2 GB of weights). Facts S7–S9 will build on:

- **Config filename is `model_config.json`.** `config.json` inside
  `t5gemma-b-b-ul2/` is the *text-encoder* config (S7), not the top-level model.
- **Tensor namespace is raw PyTorch-style**, e.g.
  `model.model.preprocess_conv.weight` `[256,256,1]`,
  `model.model.to_cond_embed.0.weight` `[1024,768]`,
  `conditioner.conditioners.seconds_total.embedder.embedding.1.weight`
  `[768,256]`. 685 tensors, F32. `StableAudioModelAssets.knownSFXTensorShapes`
  pins four of these as a load-sanity gate.
- **⚠️ Weights-format divergence to resolve in S7–S9:** the Sortie 4 golden
  fixture was captured by the official Python-MLX backend running weights from
  **`stabilityai/stable-audio-3-optimized`** (MLX-converted), whereas the model
  shipped/loaded here is **`stabilityai/stable-audio-3-small-sfx`** with the raw
  PyTorch tensor names above. The official reference's MLX modules may expect
  *converted* key names (and possibly transposed/fused conv or attention
  weights) rather than these raw `model.model.*` / `conditioner.conditioners.*`
  keys. Before translating a module, S7–S9 must confirm whether the loaded
  small-sfx tensors map 1:1 onto the reference's expected weight keys or whether
  a name/layout conversion step (matching what `optimized` did) is required.
  This is the most likely source of a silent parity failure.

## Sortie 7 note — T5Gemma text encoder (translated + parity-checked)

Sortie 7 translated the official `optimized/mlx/models/defs/t5gemma_mlx.py`
encoder (`_Encoder` + `_SelfAttention`/`_MLP`/`_EncoderLayer` + `_rms_norm` /
`_rope_cos_sin` / `_rotate_half` / `_apply_rope`) op-for-op into MLX Swift
(`T5GemmaTextEncoder.swift`). Invocation convention (`t5.encode(...)`) was
cross-checked against `scripts/parity_forward_mlx.py`.

**Tensor-key mapping — did NOT map 1:1; a name conversion was required
(resolving the S6 ⚠️ flag for the encoder):**

- The T5Gemma weights are the encoder's *own* `t5gemma-b-b-ul2/model.safetensors`
  (340 tensors), NOT the top-level DiT `model.safetensors`. The T5Gemma subfolder
  is a full encoder+decoder checkpoint; **only the `model.encoder.*` half is
  loaded** (the `model.decoder.*` half is discarded — the SFX conditioner uses
  the encoder only).
- The reference MLX module keys are the *stripped* names (`embed_tokens.weight`,
  `layers.{i}.self_attn.q_proj.weight`, `layers.{i}.pre_self_attn_layernorm.weight`,
  `norm.weight`). The shipped small-sfx safetensors carry a **`model.encoder.`
  prefix** on every tensor. `T5GemmaWeightLoader` strips that prefix — the one
  name conversion needed. After stripping, keys map 1:1 to the reference module
  (same layout: Linear weights `(out,in)`, per-layer RMSNorm weights, no biases).
- **Dtype conversion:** the shipped weights are **bf16**; the reference runs its
  forward in **fp16** (its `_Encoder` casts the embedding to fp16 and its npz is
  fp16). We cast bf16→fp16 at load to match the reference numeric path exactly.
- **RoPE inv_freq** is absent from the safetensors (the reference computes it from
  θ=10000 when its optional `rope_inv_freq` key is missing); we compute it the
  same way in Swift, so there is no weight to map.

**Conditioning output (S7 boundary).** `T5GemmaTextConditioner.encode` returns
`(embeddings (B,256,768) fp16, mask (B,256) int32)` — the encoder last-hidden
state + attention mask, matching the reference `T5Gemma.encode`. The learned
padding-embedding substitution (`apply_prompt_padding`), the `seconds_total`
token, and the cross-cat that build the DiT's *final* cross-conditioning use the
**DiT base** weights (`cond.prompt.padding_embedding`), not the T5Gemma weights —
that is Sortie 8, deliberately not applied here.

**Tokenizer.** The reference uses `sentencepiece` on `tokenizer.model`. To avoid
adding a package dependency (swift-transformers is not in this graph; adding it
mid-mission risks the pinned mlx-swift 0.31.3 resolution), `GemmaBPETokenizer`
reads `tokenizer.json` directly and implements the equivalent byte-fallback BPE
(space→"▁" normalizer, no dummy prefix). Verified to reproduce
`sentencepiece.Encode` exactly on the committed reference cases.

**Numerical parity (achieved).** The committed fixture
`Tests/SwiftAmbienteTests/Fixtures/t5gemma-encoder-reference.json` was captured
from the reference `_Encoder` (same safetensors, bf16→fp16) for the fixed prompt
`"gentle rain on a tin roof"` → ids `[116419,8980,611,476,10689,11306]`, output
`(1,256,768)` fp16 (real-token mean −0.0137, std 3.925, absmax 50.25). The Swift
encoder, fed the reference token ids, matches within **abs tolerance 0.5 per fp16
element** (probes at rows 0/last, cols 0–7 and 100–107) and **mean within 0.05,
std within 0.1, absmax within 1.0** — comfortably passed (MLX Swift and Python
MLX share the same C++/Metal kernels, so the deltas are far below the tolerance;
a softcap/RoPE/RMSNorm convention bug would move the probes by many units).

<!-- Sortie 9: parity tolerance + observed delta recorded here. -->
