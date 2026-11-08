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
(16-bit PCM encoder), `PCMAudio` (interleaved Float PCM + 16-bit WAV reader,
`init(wavData:)` / `wavData()`), `AmbientBed` (`fill(take:duration:crossfade:fadeIn:fadeOut:)`
loops one take to a span with equal-power seam crossfades + linear fades; vDSP, no MLX),
`AmbienteError`.

### Rendering GLOSA `ambience` notes

SwiftAmbiente depends on glosa-av (`GlosaCore` only). `AmbienteGenerator.render(ambience:to:)`
maps a `GlosaCore.Ambience` note (`take`/`seed`/`steps`/`cfg` → `GenerationSettings`), validates
its `model` id through `AmbienceModel.resolve` (`stable-audio-3-small-sfx` → Stable Audio SFX;
unknown ids throw `AmbienteError.unknownAmbienceModel`), writes the take WAV via temp file +
`rename(2)`, and only then writes the `RenderRecord` to `<output>.json` (e.g. `amb.wav.json`) the
same way. The record's `digest` is the note's `renderDigest` as written; its `ambience` is the
effective schema object. `AmbienceRendering.renderState(for:output:)` returns `current` /
`changed` / `notRendered` / `unknown`; an unparsable record is `changed`
(`renderStatus(for:output:)` carries the warning).

`AmbiencePlanner.plan(screenplay:projectMarkdown:writeBack:dryRun:)` is the shared planner
(`ambiente render` and Produciesta export): finds standalone notes with `GlosaFountainNotes`,
parses them with `GlosaParser`, resolves `output` (absolute as is; relative → the PROJECT.md
directory — explicit URL or `<screenplay dir>/PROJECT.md`, if it exists — else the screenplay
directory), and returns per-note entries with render status. Write-back gives non-`stop` notes
with a prompt a random `UInt32` `seed` and `ambience/<stem>/amb-<8 hex>.wav` `output`, inserting
the key lines right after the note's opening `{"ambience": {` line (pure-addition diff; canonical
`serialize()` would edit the previous last line's comma), then replaces the file atomically. A
note that allows no such insertion (single-line) is replaced by `serialize()`. `dryRun` assigns in
the plan only; `writeBack: false` assigns nothing. Randomness is injectable (`using:`).

### The backend contract

`AmbienteGenerator.generate(prompt:settings:)` returns interleaved WAV matching
the generator's `AmbienteConfig`. Both the procedural and (future) ML engines
honour `durationSeconds` and `seed` so output is reproducible across backends;
`steps` / `cfgScale` are ML-only.

`StableAudioGenerator` renders at most one model window per take:
`StableAudioModelConfig.maxDurationSeconds` (`sample_size / sample_rate`, ≈ 120 s)
once loaded, `StableAudioGenerator.defaultMaxDurationSeconds` (120) before. Longer
requests throw `AmbienteError.takeTooLong(seconds:limit:)` before any model load;
long beds are built by looping a take.

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

## Queryable Codemap

A prebuilt [graphify](https://pypi.org/project/graphifyy/) knowledge graph of this
codebase lives in [`graphify-out/`](graphify-out/) (602 nodes · 1028 edges). **Prefer
querying it before grepping** for architecture or "what connects to what" questions:

```bash
graphify query "How does X flow through the system?"
graphify path "TypeA" "TypeB"      # shortest path between two nodes
graphify explain "SomeType"        # plain-language node explanation
```

Human-readable summary: [`graphify-out/GRAPH_REPORT.md`](graphify-out/GRAPH_REPORT.md).
Refresh after significant changes with `/codemap` (or
`graphify . --backend claude-cli`).
