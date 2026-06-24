---
type: project
---

# REQUIREMENTS — Stable Audio backend integration

This document stages the work to replace `ProceduralAmbienteGenerator` with a
real neural backend. It is the single source of truth for *what* the ML engine
must be and *which licenses* it drags in.

## Target model

**Stable Audio 3 Small — SFX variant** (the foley / sound-effects model).

- 44.1 kHz **stereo** output (already encoded in `AmbienteConfig.default`).
- Fast few-step diffusion (the Small models are designed for on-device / real-time).
- Upstream: Stability AI's official [`stable-audio-3`](https://github.com/Stability-AI/stable-audio-3)
  repository, which ships an `optimized/mlx` path ("Optimized MLX inference for
  M-series Mac") and CoreML for the Small models.

## Why there's a placeholder today

There is **no drop-in Swift package** for Stable Audio on MLX. The proven
Apple-Silicon implementation lives inside an iOS *app*
([kellyvv/StableAudio3-IOS](https://github.com/kellyvv/StableAudio3-IOS), MIT
code, MLX Swift) — a reference to **port from**, not a dependency to add. Until
that port exists, `AmbienteModelManager.loadGenerator(_:)` throws
`modelNotAvailable` and `AmbienteEngine` falls back to the procedural generator.

## Work items

1. **MLX Stable Audio generator** — port the diffusion sampler + SAME-S decoder +
   T5Gemma conditioning from the reference app into a Swift type conforming to
   `AmbienteGenerator` (`generatorId = "stable-audio"`). Honour
   `GenerationSettings.steps`, `cfgScale`, `seed`, `durationSeconds`.
2. **SwiftAcervo wiring** — replace the env/default directory resolution in
   `AmbienteModelManager` with `Acervo.sharedModelsDirectory` and on-demand model
   download. Add the SwiftAcervo sibling dependency in `Package.swift` (the block
   is commented in place). Mirror the `{org}_{repo}` slug convention; `config.json`
   presence = valid model.
3. **CDN distribution** — mirror the Small SFX weights to the intrusive-memory R2
   CDN via the `acervo-cdn-setup` / `acervo ship` flow, gated on accepting the
   Stability + Gemma terms.
4. **Build system** — the MLX backend needs Metal shader compilation, so CI
   integration tests must be gated on model presence (see the
   `acervo-integration-ci` standard) and likely skipped on GitHub runners, exactly
   as SwiftVoxAlta does.

## Licensing obligations (BLOCKING for commercial use)

The Small models stack **two** licenses — both must be cleared before shipping a
commercial build that enables the neural backend:

| Component | License | Obligation |
|-----------|---------|------------|
| Stable Audio 3 Small weights | **Stability AI Community License** | Free commercial use **< US$1M** annual revenue; register with Stability; display **"Powered by Stability AI"**. |
| T5Gemma text encoder | **Google Gemma Terms of Use** | Separate prohibited-use policy + attribution. |

The procedural generator carries **no** model licensing; these obligations are
inert until item 1 lands and the engine actually loads weights.

## Acceptance

- [ ] `StableAudioGenerator` conforms to `AmbienteGenerator` and passes the same
      WAV-contract tests the procedural generator does.
- [ ] `AmbienteEngine.resolveGenerator` returns the ML backend when the model is
      installed, procedural otherwise.
- [ ] Model downloads through SwiftAcervo; CI gates on presence.
- [ ] README "Licensing" section reflects shipped reality; NOTICE file carries
      both attributions.
