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

This section documents obligations. It is not legal advice.

**SwiftAmbiente's own code is MIT** (see [`LICENSE`](LICENSE)). That license
covers this repository only. The Stable Audio weights and the bundled T5Gemma
encoder are **not vendored in the repo**; they are downloaded at runtime through
SwiftAcervo and keep their own licenses (`LICENSE.md` and `LICENSE_GEMMA.md`
ship alongside the weights). The procedural generator uses no model and carries
no model licensing; it is what runs when the neural model is not installed. The
obligations below apply only when the Stable Audio backend is enabled.
Attributions are in [`NOTICE`](NOTICE).

### 1. Stability AI Community License (Stable Audio 3 Small SFX weights)

- **Registration:** any Commercial Purpose (including creating or distributing
  your product or service, and internal business operations) requires
  registering with Stability AI at <https://stability.ai/community-license>.
- **Revenue threshold:** free below US$1,000,000 annual revenue. If you or your
  affiliates, in aggregate, exceed that amount, from any source and not just
  this product, your licenses terminate as of that date. You must then request a
  license at <https://stability.ai/enterprise>, which Stability may grant in its
  sole discretion.
- **"Powered by Stability AI":** if you distribute the materials or a product
  that uses them, you must prominently display "Powered by Stability AI" on a
  related website, user interface, blogpost, about page, or product
  documentation, and provide a copy of the license.
- **Notice file:** carry "This Stability AI Model is licensed under the Stability
  AI Community License, Copyright (c) Stability AI Ltd. All Rights Reserved" in a
  Notice text file distributed with copies (see `NOTICE`).
- **Use restrictions:** comply with applicable law and Stability's Acceptable Use
  Policy; do not use the model or its outputs to create or improve a foundational
  generative AI model.

### 2. Google Gemma Terms of Use (T5Gemma text encoder)

The weights include T5Gemma, redistributed under the Gemma Terms of Use. Beyond
the Stability license:

- **Use restrictions (Section 3.2):** you must not use it for the restricted uses
  in the [Gemma Prohibited Use
  Policy](https://ai.google.dev/gemma/prohibited_use_policy) or in violation of
  applicable law.
- **Pass-through to end users (Section 3.1):** when you distribute Gemma or Model
  Derivatives, the Section 3.2 restrictions must appear as an **enforceable
  provision** in any agreement governing their use or distribution (license
  agreement, terms of use, etc.), and subsequent users must be told they are
  subject to them. Apps embedding this library should put this in their EULA or
  terms of use.
- **Also required on distribution:** give recipients a copy of the Gemma Terms of
  Use, mark modified files, and include the Gemma notice line in a Notice text
  file (see `NOTICE`).

### Verify with counsel before commercial ship

These points are ambiguous for an embedded Swift library; this README does not
resolve them:

- **Who "distributes" the weights.** Weights are fetched at runtime from a CDN
  into the user's cache, not shipped inside your app binary. Whether that makes
  you, the CDN operator, or neither the distributor under either license (which
  drives the copy-of-license, Notice-file, and pass-through duties) is not
  stated in the texts.
- **Gemma pass-through mechanics.** Section 3.1 requires an enforceable
  provision in agreements governing use. How to satisfy that for an app that only
  embeds the library, and whether a Hosted Service use changes it, is not
  addressed.
- **Integrated end-user product carve-out.** Stability's Section 3 says it does
  not apply to someone who receives the materials from a Licensee "as part of an
  integrated end user product". Whether runtime-downloaded weights qualify is
  unclear.
- **Revenue and affiliates.** The US$1M test is aggregate revenue of you and your
  affiliates from any source, and terminates licenses when crossed. Confirm the
  current threshold and registration terms at the Stability URLs above; the
  license text is dated July 5, 2024 and may be updated.
- **Gemma terms version.** The shipped `LICENSE_GEMMA.md` is dated April 1, 2026;
  the Prohibited Use Policy is incorporated by URL and can change.
- **T5 base encoder status.** The shipped encoder is `t5gemma-b-b-ul2` (Gemma
  terms). Earlier research referred to a t5-base Apache-2.0 component; no such
  component appears in the shipped files, so confirm nothing else is bundled.
- **Attribution placement.** "Powered by Stability AI" must appear on a website,
  UI, about page, or documentation; which of these suffices for your app is your
  call.

### Configuring model downloads (`ACERVO_CDN_BASE_URL`)

To use the neural backend, an app embedding the library must set the CDN base
URL, either as the `ACERVO_CDN_BASE_URL` environment variable or the
`AcervoCDNBaseURL` Info.plist key. SwiftAcervo traps without one of them. The
`ambienta` CLI ships a default (`https://cdn.intrusive-memory.productions/models`).
If the model is not installed, `AmbienteEngine` falls back to the procedural
generator.

## Platform

iOS 26+ / macOS 26+, Apple Silicon only.
