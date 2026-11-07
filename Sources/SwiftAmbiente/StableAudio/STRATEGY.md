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

## Sortie 8 note — DiT flow-matching pingpong sampler → latent

Sortie 8 translated the DiT velocity network + the `sample_flow_pingpong`
sampler + the `seconds_total` conditioner op-for-op into MLX Swift and wired
`GenerationSettings.{steps,cfgScale,seed,durationSeconds}` into a deterministic
latent. New files: `StableAudioDiT.swift`, `StableAudioConditioning.swift`,
`StableAudioFlowSampler.swift`, `StableAudioLatentGenerator.swift`. Decoding the
latent to audio (SAME-S) is deliberately left to Sortie 9.

**DiT config source — which `DIT_CHOICES` entry.** `scripts/sa3_mlx.py::DIT_CHOICES`
maps `"sm-sfx"` → `{"loader": "models.defs.dit_mlx", "default_decoder": "same-s"}`
— i.e. the SFX DiT is **`dit_mlx.py`** (standard multi-head attention;
embed_dim=1024, depth=20, heads=16, ff_inner=4096), **NOT** `dit_mlx_medium.py`
(the differential-attention 5×-QKV `medium` DiT, embed_dim=1536/depth=24). The
Swift DiT reads every varying hyperparameter from the loaded `model_config.json`
`model.diffusion.config` block (`StableAudioModelConfig.DiffusionConfig`):
`io_channels`, `embed_dim`, `depth`, `num_heads`, `cond_token_dim`,
`global_cond_dim`, `local_add_cond_dim` (257), `num_memory_tokens` (64). Head dim
(64 = embed_dim/num_heads) and GLU inner width (4096 = embed_dim×4, `ff_kwargs.mult`
= 4.0) are derived; rope partial-dims (32) and the timestep Fourier dim (256) are
the reference's family-wide constants (not scalar keys in the diffusion block).
Nothing is hardcoded that varies between the sm and medium configs.

**Weight-key mapping — maps 1:1, NO rename pass required.** Unlike the reference's
torch-ckpt converter (`convert_weights_from_torch_ckpt`, which strips a
`model.model.` prefix, transposes convs, renames `.gamma`→`.weight`, and
`.to_local_embed.{0,2}`→`.seq.{0,2}`), we fetch each tensor by its **literal
on-disk key** from the already-loaded `[String: MLXArray]` safetensors map, so no
renaming is needed:

- All DiT tensors keep the `model.model.` prefix as shipped (e.g.
  `model.model.transformer.layers.{i}.self_attn.to_qkv.weight` `[3072,1024]`,
  `...cross_attn.to_kv.weight` `[2048,1024]`, `...ff.ff.0.proj.weight`
  `[8192,1024]`, `...to_scale_shift_gate` `[6144]`).
- **RMSNorm weights are stored as `.gamma`** (e.g. `...pre_norm.gamma`,
  `...self_attn.q_norm.gamma`); we read `.gamma` directly and feed it to
  `MLX.rmsNorm` (weight cast to the activation dtype so the reference's
  fp16-weight / occasionally-fp32-activation call is well-defined).
- **1×1 convs** (`preprocess_conv.weight`/`postprocess_conv.weight`) ship
  `[out,in,1]`; we squeeze the kernel axis to `[out,in]` and apply the conv as a
  channel matmul (`x_lc @ W.T`) — avoiding any MLX-Conv1d `[out,k,in]` layout
  conversion entirely.
- **Conditioner weights** live in the *same* `model.safetensors` under
  `conditioner.conditioners.prompt.padding_embedding` `[768]`,
  `conditioner.conditioners.seconds_total.embedder.embedding.1.{weight,bias}`
  `[768,256]/[768]` — not a separate `cond.`-prefixed npz as in the reference's
  `load_conditioner_from_npz`.
- **Dtype conversion:** the shipped tensors are **F32**; the reference's default
  `dit_dtype=fp16` path casts the DiT weights to fp16 at load (`load_dit`). We
  match this — DiT weights are cast **F32→fp16**; the `seconds_total` linear and
  `padding_embedding` are kept **fp32** (the reference computes the seconds
  conditioner in fp32 before casting the token to the sampling dtype).

**Seed RNG parity (the crux).** The reference seeds via `mx.random`: the initial
pure noise is `mx.random.normal((1,256,T_lat), dtype=fp16, key=mx.random.key(seed))`
and the sampler is invoked with `seed = user_seed + 1`, doing
`key = mx.random.key(seed)` then per non-terminal step
`key, sub = mx.random.split(key); noise = mx.random.normal(x.shape, key=sub)`.
This is translated one-for-one to `MLXRandom.key`, `MLXRandom.split(key:)` (tuple
form → `(key, sub)`, matching the Python unpack order), and `MLXRandom.normal(_,
dtype:, key:)` — the SAME Threefry PRNG and draw order, so the same seed
reproduces the same noise path. `GenerationSettings.resolvedSeed` supplies the
user seed; the sampler uses `resolvedSeed &+ 1`.

**CFG.** `cfgScale → classifier-free guidance`. When `cfg == 1.0` a single DiT
forward runs (no uncond pass). When `cfg ≠ 1.0` the cond+uncond batch is run in
one forward over `cat([x,x])`; with no negative prompt the uncond branch uses
**zero cross-attn embeddings** (`zeros_like(cross_attn)`, matching upstream). We
implement plain CFG (`cfg_d = cond_d + (cfg−1)·(cond_d − uncond_d)`); the
reference's optional APG projection is disabled (`apg ≤ 0`) since
`GenerationSettings` exposes no APG knob.

**`durationSeconds → T_lat`.** `T_lat = max(1, ceil(seconds · 44100 / 4096))`
(`SAMPLES_PER_LATENT = 4096`), the reference's decoder-independent natural-ceil.
`durationSeconds = 1.0 → T_lat = 11`; the produced latent is `(1, 256, T_lat)`.

**Determinism (verified, model-gated).** `StableAudioLatentSamplerTests`: same
seed → **byte-identical** latents (exact `[Float]` equality of the fp32-widened
latent), different seeds diverge, the cfg≠1 batched-uncond path is likewise
deterministic and differs from cfg=1. `make test`: **5/5** consecutive green
without the model (all neural tests skip) and **10/10** consecutive green with the
model (`TEST_RUNNER_ACERVO_MODELS_DIR=/tmp/acervo-staging`).

**Observed dtype note (faithful to the reference, not a bug).** The reference's
text-to-audio zero local-add-cond is fp32 (`mx.zeros(...)` defaults to fp32); its
per-block MLP bias path then promotes the cfg=1 residual stream — and hence the
returned latent — to **fp32**, while the cfg≠1 branch re-casts the velocity to
`x.dtype` and stays **fp16**. MLX Swift's type-promotion rules are identical, so
the Swift latent's dtype tracks the reference's exactly (S9's decoder upcasts to
fp32 regardless). The test asserts a float dtype rather than a specific one to
preserve this parity.

## Sortie 9 note — SAME-S decoder (Road A: true reference parity)

**Decoder-path decision (user, 2026-07-19): ROAD A — hold the existing golden-WAV
parity gate.** The S4 golden fixture came from `stable-audio-3-optimized`'s
pre-folded `same_s_decoder_f32.npz`, but the shipped `small-sfx/model.safetensors`
carries the decoder as raw-PyTorch weight-norm `pretransform.model.decoder.*`
tensors. Rather than re-baseline on the shipped weights (Road B), we reproduce the
`optimized` export deterministically and prove parity against the current fixture.
Pre-write recon retired every parity risk; there is **no remaining reverse-
engineering** — the conversion is mechanical:

**Architecture — MATCHES the reference `same_s_decoder.py` exactly** (verified
against the shipped tensor shapes): 5×DIM differential attention
(`self_attn.to_qkv.weight [3840,768]` = 5×768 ✓), `DyT` norms
(`{pre,ff,q,k}_norm.{alpha,beta,gamma}`, alpha [1], head-dim norms [64], dim norms
[768] ✓), GLU-SiLU FF (`ff.ff.0.proj [4608,768]` = FF_INNER 2304 × 2 ✓,
`ff.ff.2 [768,2304]` ✓), 6 blocks, RoPE 32 dims / base 10000 / non-traditional,
weight-norm output conv.

**Weight mapping — nested→flat remap + one fold (both deterministic):**
- `pretransform.model.decoder.layers.1.{weight[768,256],bias}` → `project_in`
  (Linear 256→768).
- `pretransform.model.decoder.layers.3.new_tokens [1,1,768]` → `new_tokens`.
- `pretransform.model.decoder.layers.3.transformers.{0..5}.*` → `blocks[0..5]`.
- `pretransform.model.decoder.layers.3.mapping.{weight_g[512,1,1],weight_v[512,768,3],bias}`
  → `mapping`: **weight-norm fold** `w = g · v / ‖v‖` (norm over in+kernel axes,
  per out-channel), then permute PyTorch `[out,in,k]` → MLX conv `[out,k,in]`
  (`transposed(0,2,1)`), applied with `padding:1`. This is the ONLY fold.
- `pretransform.model.bottleneck.running_std` → `running_std`.

**Three parity traps identified & resolved:**
1. **RoPE `inv_freq` is IGNORED.** The shipped blocks carry
   `transformers.*.rope.inv_freq [16]`, but the reference recomputes inv_freq from
   base=10000 via `mx.fast.rope` and discards any stored value. Swift recomputes
   identically (mirror the DiT's `MLX.RoPE(..., base: 10000, traditional: false)`);
   the stored tensor is not loaded.
2. **Bottleneck is asymmetric — decoder uses ONLY `running_std`.** Encoder does
   `x*scaling_factor + bias; x/running_std`; the decoder does only
   `latents * running_std`. The shipped `bottleneck.{scaling_factor,bias,
   noise_scaling_factor}` are encoder-side and are **not** applied on decode.
   Translating only `running_std` is faithful, not a bug.
3. **FP32 throughout.** SAME-S catastrophically cancels at fp16 (differential
   attention), so the whole decoder runs FP32 regardless of the DiT's fp16 latent
   (upcast the S8 latent on entry). The reference decoder always runs FP32.

**Chunking.** `decode_chunked` uses kernel = chunk + 2·overlap; SAME-S config is
`(chunk=8, overlap=2)` → kernel 12. Un-chunked SAME-S requires **even T_lat**
(internal `T·17` must align to 34). The S9 parity test must pin `durationSeconds`
to the exact `--seconds` recorded in the S4 reference-invocation note (NOT S8's
`T_lat=11`, which is odd and only exercised the sampler determinism test).

**Post-decode.** Decoder output is `[B, 512, T_lat·16]` audio *patches*;
patched-pretransform unpatch (`rearrange("b (c h) l -> b c (l h)", h=256)`) →
`[B, 2, T_lat·4096]` stereo waveform → existing `WAVWriter` → interleaved 44.1 kHz
WAV. `512 = 2 (stereo) × 256 (patch)`, giving `samplesPerLatent = 16·256 = 4096`
(consistent with S8).

<!-- Sortie 9: parity tolerance + observed delta recorded here after the build. -->
