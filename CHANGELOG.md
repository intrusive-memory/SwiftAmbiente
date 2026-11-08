---
type: doc
---

# Changelog

The active changelog for SwiftAmbiente lives in two places:

- **[AGENTS.md → Recent Changes](AGENTS.md#recent-changes)** — version-by-version
  summary kept up to date with each release.
- **[GitHub Releases](https://github.com/intrusive-memory/SwiftAmbiente/releases)**
  — full release notes, asset checksums, and the canonical tag list.

This file is preserved as a stub so existing links don't 404.

## 0.2.0 (2026-11-08)

- GLOSA `ambience` notes: `AmbienteGenerator.render(ambience:to:)` renders a take and
  writes a `<take>.wav.json` render record (digest, generator, version) after the WAV.
- `AmbiencePlanner`: output resolution, render state (`current` / `changed` /
  `notRendered` / `unknown`) and `seed` / `output` write-back into the screenplay.
- `AmbientBed.fill`: loops one take to a span with equal-power crossfades and fades.
- `PCMAudio` WAV type; takes longer than 120 s are rejected (`takeTooLong`).
- `ambiente render <screenplay>` (`--dry-run`, `--force`, `--project-md`); the prompt form
  is now the default `generate` subcommand.
- Depends on glosa-av 0.11.0 (GlosaCore).

## 0.1.0 (2026-11-07, pre-release)

- Initial scaffold mirroring SwiftVoxAlta conventions.
- `AmbienteGenerator` backend abstraction.
- `ProceduralAmbienteGenerator` — interim, dependency-free filtered-noise engine.
- `ambiente` CLI with scene presets and free-form prompts.
- Stable Audio 3 Small SFX neural backend (`StableAudioGenerator`, MLX Swift):
  T5Gemma conditioning, DiT flow-matching sampler with APG, SAME-S decoder;
  golden-output parity gate; on-demand model download via SwiftAcervo;
  model-gated integration CI; README Licensing + NOTICE for the Stability AI
  Community License and Gemma Terms of Use.
