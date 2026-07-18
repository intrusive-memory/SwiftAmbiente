---
type: doc
title: Golden-output reference fixture — Stable Audio 3 Small SFX
sortie: S4 (OPERATION PHANTOM FOLEY, WU2)
---

# `golden-rain-on-tin-roof-seed42.wav` — reproducibility note

This WAV is a **one-time, out-of-repo verification oracle**: a genuine golden
output captured from Stability AI's official Apple-Silicon **Python-MLX**
inference backend for Stable Audio 3 Small (SFX variant). Later sorties (WU2
S7–S9) translate that same network op-for-op into MLX Swift and assert parity
against this fixture within a documented tolerance (Sortie 9 parity gate).

The Python-MLX stack used to bake this fixture is **verification-only**: it never
ships, never enters `Package.swift`, and never enters CI. The repo/venv/weights
live entirely **outside** this repository tree. This note exists so the fixture
is fully reproducible from the recorded inputs.

## Determinism verification

Generation is deterministic for a fixed prompt + seed. This fixture was captured
by the prior sortie run and **independently re-generated** during Sortie 4
finalization; both runs produced a **byte-identical** WAV:

```
MD5 (golden-rain-on-tin-roof-seed42.wav) = 17b33f1a5d74380eb5e805d62f664c26
```

Any faithful re-run of the exact invocation below on Apple Silicon reproduces
this MD5.

## Official reference backend

| Item | Value |
|------|-------|
| Repo | `https://github.com/Stability-AI/stable-audio-3` |
| Commit SHA | `0385302ea26522f00c80392c4b708df5ebf1adf5` |
| Subdir | `optimized/mlx/` (Python-MLX, Metal-backed, no PyTorch at runtime) |
| CLI wrapper | `optimized/mlx/sa3` → `scripts/sa3_mlx.py` |

## Model weights (downloaded from HuggingFace by the backend)

| Item | Value |
|------|-------|
| MLX weights repo | `stabilityai/stable-audio-3-optimized` |
| MLX weights revision | `08c64b96b1e59942aade69759f60fb88c58c90c4` (refs/main) |
| Source model repo (gated) | `stabilityai/stable-audio-3-small-sfx` |
| Source model revision | `ae12755283df9d62ca39a9b050a39a0b607b8c20` (refs/main) |
| DiT checkpoint | `dit_sm-sfx_f16.npz` (`--dit sm-sfx`) |
| Decoder | `same_s_decoder_f32.npz` (`--decoder same-s`, FP32) |
| Text encoder | `t5gemma_f16.npz` (T5Gemma, bundled) |

The backend pulls the MLX-converted `.npz` weights from
`stabilityai/stable-audio-3-optimized`; the gated `stable-audio-3-small-sfx`
license had been accepted on the active `HF_TOKEN` (a download precondition).

## Exact reproducible invocation

Run from `optimized/mlx/` inside the cloned reference repo (after `./install.sh`
provisions the `uv`-managed `.venv`):

```bash
./sa3 \
  --prompt "heavy rain on a tin roof" \
  --dit sm-sfx \
  --decoder same-s \
  --seconds 5.0 \
  --steps 8 \
  --cfg 7.0 \
  --seed 42 \
  --out golden-rain-on-tin-roof-seed42.wav
```

### Fixed parameters

| Parameter | Value |
|-----------|-------|
| prompt | `heavy rain on a tin roof` |
| seed | `42` |
| steps | `8` |
| cfg | `7.0` (apg=1.0) |
| duration | `5.0` s (T_lat 54 → 5.02s, trimmed to exactly 5.0s) |
| dit | `sm-sfx` |
| decoder | `same-s` |
| dit-dtype | `fp16` (default) |
| negative-prompt | none (uncond branch uses zero embeddings) |

## Output WAV properties

| Property | Value |
|----------|-------|
| Format | RIFF/WAVE, Microsoft PCM |
| Sample rate | 44100 Hz |
| Channels | 2 (stereo) |
| Bit depth | 16-bit |
| Frames | 220500 |
| Duration | 5.0 s (exact) |
| File size | 882044 bytes |
| MD5 | `17b33f1a5d74380eb5e805d62f664c26` |

## Reference environment (verification-only; does not ship)

| Component | Version |
|-----------|---------|
| Platform | macOS (Darwin arm64, Apple Silicon) |
| Python | 3.11.15 (backend `.venv`, uv-managed) |
| mlx | 0.32.0 |
| numpy | 2.4.6 |
| sentencepiece | 0.2.2 |
| huggingface_hub | 1.24.0 |

Backend Python requirements (`optimized/mlx/requirements.txt`):
`mlx>=0.30`, `numpy>=1.24`, `sentencepiece>=0.2`, `huggingface_hub>=0.20`.
