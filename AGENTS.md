---
type: reference
updated: 2026-11-07
---

# AGENTS.md — SwiftAmbiente

Atmospheric / foley background-bed generation for Apple Silicon. The ambience
counterpart to [SwiftVoxAlta](../SwiftVoxAlta): VoxAlta renders voices,
SwiftAmbiente renders the background bed that sits underneath them in
[Produciesta](../Produciesta).

## Status

Two backends. **Neural**: `StableAudioGenerator` — Stable Audio 3 Small SFX via
MLX Swift (T5Gemma → DiT → SAME-S), used whenever the model is installed; weights
download on demand through SwiftAcervo. **Fallback**: `ProceduralAmbienteGenerator`
(dependency-free seeded filtered noise) when the model is absent. Design notes and
parity results: `Sources/SwiftAmbiente/StableAudio/STRATEGY.md`. Original
requirements and mission record: [`docs/complete/phantom-foley-01/`](docs/complete/phantom-foley-01/REQUIREMENTS-stable-audio-integration.md).

## Build & test

Never `swift build` / `swift test`. Use the Makefile (xcodebuild under the hood):

```bash
make build        # debug build
make install      # build + copy ./bin/ambiente
make test         # unit tests (no model required)
make help
```

Destination is always `platform=macOS,arch=arm64`.

## Architecture

```
AmbienteEngine            ← front door: picks a backend, renders a bed
 ├─ AmbienteModelManager  ← resolves shared-models dir; loads the MLX Stable Audio backend
 └─ AmbienteGenerator     ← backend protocol
     ├─ ProceduralAmbienteGenerator   ← fallback DSP (seeded filtered noise)
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
installed and loadable (`StableAudioGenerator`, `generatorId == "stable-audio"`),
otherwise the procedural generator (and logs the fallback to stderr). Loading goes
through SwiftAcervo, which **traps** unless the host process sets
`ACERVO_CDN_BASE_URL` (env) or `AcervoCDNBaseURL` (Info.plist); the `ambiente` CLI
sets a default, the library deliberately does not. MLX executables must ship
`mlx-swift_Cmlx.bundle` next to the binary (`make install`/`make release` do).
Model-present tests run with `TEST_RUNNER_ACERVO_MODELS_DIR=<dir>` (the xctest
runner can't read the App Group container).

## CLI — `ambiente`

```bash
ambiente --list-scenes
ambiente --scene rain -d 30 -o rain.wav
ambiente "distant city traffic, muffled hum" -d 15 -o city.wav
ambiente --scene forest --seed 42            # reproducible → ./ambiente.wav
ambiente --model sfx --scene ocean -d 60 -o ocean.wav
```

Scene presets: `room-tone`, `rain`, `forest`, `city`, `ocean`, `cafe`, `night`.

## Conventions inherited from the ecosystem

- **Platforms**: iOS 26+ / macOS 26+, Apple Silicon only. No `@available` for
  older OSes.
- **Shared models**: resolved by SwiftAcervo (`Acervo.sharedModelsDirectory`,
  App Group `group.intrusive-memory.models`), overridable via `ACERVO_MODELS_DIR`;
  a byte-equal `manifest.json` = installed model. Stable Audio's top-level config
  is `model_config.json`, not `config.json`.
- **Git**: `development` → PR → `main`; releases via `/ship-swift-library`.
- **Package.swift**: the `sibling()` helper prefers a local `../<name>` checkout
  when present, else the released remote.

## Licensing

SwiftAmbiente code: MIT-style; procedural generator: no model licensing. The
neural backend stacks the **Stability AI Community License** (registration for
any commercial use; terminates above US$1,000,000 aggregate annual revenue;
"Powered by Stability AI") **and the Google Gemma Terms of Use** (T5Gemma encoder;
§3.1 pass-through of use restrictions to end users). Both apply whenever the
neural backend runs. Authoritative summary: README "Licensing" and `NOTICE`.

## Recent Changes

### 0.1.0 (pre-release)
- Initial scaffold: backend abstraction, procedural generator, `ambiente` CLI,
  scene presets.
- Stable Audio 3 Small SFX neural backend (`StableAudioGenerator`, MLX Swift) with
  golden-output parity gate, SwiftAcervo on-demand download, model-gated
  integration CI, README Licensing + NOTICE (OPERATION PHANTOM FOLEY).
