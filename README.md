---
type: doc
---

# SwiftAmbiente

**Atmospheric / foley background-bed generation for Apple Silicon.**

SwiftAmbiente is the ambience counterpart to [SwiftVoxAlta](../SwiftVoxAlta):
where VoxAlta renders *voices*, SwiftAmbiente renders the *background* — room
tone, rain, wind, city hum, the foley bed you lay underneath dialogue in
[Produciesta](../Produciesta).

> **Status: scaffold.** The shipping engine is a procedural (filtered-noise)
> generator that produces a usable bed today. The neural backend — Stable Audio 3
> Small SFX via MLX Swift — is staged and documented in
> [`REQUIREMENTS-stable-audio-integration.md`](REQUIREMENTS-stable-audio-integration.md).

## Why "Ambiente"

`sonido ambiente` is the term Spanish-language audio engineers use for
atmospheric / room-tone beds — the technically-correct word for what this library
makes. It joins the ecosystem's Spanish-word naming theme (Hablare, Echada,
Secuencia, VoxAlta…).

## Install

```swift
.package(url: "https://github.com/intrusive-memory/SwiftAmbiente.git", from: "0.1.0")
```

## Library usage

```swift
import SwiftAmbiente

let engine = AmbienteEngine()
let wav = try await engine.render(prompt: "rain on a tin roof, distant thunder",
                                  duration: 20)
try wav.write(to: URL(fileURLWithPath: "rain.wav"))
```

`AmbienteEngine` prefers the MLX Stable Audio backend when its model is installed
and falls back to the procedural generator otherwise, so you always get a result.

## CLI

```bash
make install                       # builds ./bin/ambienta

ambienta --list-scenes             # show built-in presets
ambienta --scene rain -d 30 -o rain.wav
ambienta "quiet café murmur, distant traffic" -d 15 -o cafe.wav
ambienta --scene forest --seed 42  # reproducible; writes ./ambiente.wav
```

## Architecture

| Type | Role |
|------|------|
| `AmbienteGenerator` | Backend protocol — `generate(prompt:settings:) -> WAV` |
| `ProceduralAmbienteGenerator` | Interim DSP backend (seeded filtered noise) |
| `AmbienteEngine` | Picks the best available backend, renders a bed |
| `AmbienteModelManager` | Resolves shared-models dir; loads the MLX backend (staged) |
| `AmbienteSceneDescriptor` | Built-in scene presets → prompts |
| `StableAudioModelRepo` | Target models (Small SFX / Small Music) |

## Licensing (read before commercial use)

The *target* neural model carries **two** stacked licenses:

1. **Stability AI Community License** — free commercial use under **US$1M** annual
   revenue, requires registration with Stability and a visible **"Powered by
   Stability AI"** attribution.
2. **Google Gemma Terms of Use** — the T5Gemma text encoder bundled with the
   Small models has its own prohibited-use policy.

SwiftAmbiente's own code is MIT-style and the procedural generator has **no model
licensing at all**. The two obligations above apply only once the Stable Audio
backend is enabled. See
[`REQUIREMENTS-stable-audio-integration.md`](REQUIREMENTS-stable-audio-integration.md).

## Platform

iOS 26+ / macOS 26+, Apple Silicon only.
