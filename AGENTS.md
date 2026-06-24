---
type: reference
---

# AGENTS.md — SwiftAmbiente

Atmospheric / foley background-bed generation for Apple Silicon. The ambience
counterpart to [SwiftVoxAlta](../SwiftVoxAlta): VoxAlta renders voices,
SwiftAmbiente renders the background bed that sits underneath them in
[Produciesta](../Produciesta).

## Status

**Scaffold.** Shipping engine = `ProceduralAmbienteGenerator` (dependency-free
filtered noise, usable today). Neural engine = Stable Audio 3 Small SFX via MLX
Swift, **staged** — see [`REQUIREMENTS-stable-audio-integration.md`](REQUIREMENTS-stable-audio-integration.md).

## Build & test

Never `swift build` / `swift test`. Use the Makefile (xcodebuild under the hood):

```bash
make build        # debug build
make install      # build + copy ./bin/ambienta
make test         # unit tests (no model required)
make help
```

Destination is always `platform=macOS,arch=arm64`.

## Architecture

```
AmbienteEngine            ← front door: picks a backend, renders a bed
 ├─ AmbienteModelManager  ← resolves shared-models dir; loads MLX backend (staged)
 └─ AmbienteGenerator     ← backend protocol
     ├─ ProceduralAmbienteGenerator   ← interim DSP (seeded filtered noise)
     └─ (StableAudioGenerator)        ← planned MLX backend
```

Supporting types: `AmbienteConfig` (sample rate / channels / format),
`GenerationSettings` (duration / steps / cfg / seed), `AmbienteSceneDescriptor`
(preset scenes → prompts), `StableAudioModelRepo` (target models), `WAVWriter`
(16-bit PCM encoder), `AmbienteError`.

### The backend contract

`AmbienteGenerator.generate(prompt:settings:)` returns interleaved WAV matching
the generator's `AmbienteConfig`. Both the procedural and (future) ML engines
honour `durationSeconds` and `seed` so output is reproducible across backends;
`steps` / `cfgScale` are ML-only.

### Backend selection

`AmbienteEngine.resolveGenerator` returns the MLX backend when its model is
installed and loadable, otherwise the procedural generator (and logs which ran to
stderr). Today the ML path always falls through because
`AmbienteModelManager.loadGenerator` throws `modelNotAvailable`.

## CLI — `ambienta`

```bash
ambienta --list-scenes
ambienta --scene rain -d 30 -o rain.wav
ambienta "distant city traffic, muffled hum" -d 15 -o city.wav
ambienta --scene forest --seed 42            # reproducible → ./ambiente.wav
ambienta --model sfx --scene ocean -d 60 -o ocean.wav
```

Scene presets: `room-tone`, `rain`, `forest`, `city`, `ocean`, `cafe`, `night`.

## Conventions inherited from the ecosystem

- **Platforms**: iOS 26+ / macOS 26+, Apple Silicon only. No `@available` for
  older OSes.
- **Shared models**: `~/Library/SharedModels/{org}_{repo}/`, overridable via
  `ACERVO_MODELS_DIR`; `config.json` presence = valid model. SwiftAcervo takes
  over this resolution once wired.
- **Git**: `development` → PR → `main`; releases via `/ship-swift-library`.
- **Package.swift**: the `sibling()` helper prefers a local `../<name>` checkout
  when present, else the released remote.

## Licensing

SwiftAmbiente code: MIT-style; procedural generator: no model licensing. The
neural backend stacks **Stability AI Community License** (commercial < US$1M +
"Powered by Stability AI") **and Google Gemma Terms** (T5Gemma encoder). Both are
inert until the ML backend is enabled. Details in the REQUIREMENTS doc.

## Recent Changes

### 0.1.0-dev
- Initial scaffold: backend abstraction, procedural generator, `ambienta` CLI,
  scene presets, staged Stable Audio integration plan.
