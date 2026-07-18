---
type: doc
---

# CDN Distribution — Stable Audio 3 Small SFX

**Status**: Sortie 11 (WU3) output. This document PREPARES the ship manifest;
it does not verify the ship completed — that is Sortie 12's job.

## Ship invocation

The Stable Audio 3 Small SFX weights are mirrored to SwiftAcervo's
shared-models CDN with:

```bash
acervo ship stabilityai/stable-audio-3-small-sfx --no-verify
```

Per `EXECUTION_PLAN.md` OQ-4, this upload was launched **in the background
during mission refinement** (2026-07-18) so the multi-GB mirror could
complete before the mission finished. Sortie 12 is responsible for verifying
the background ship's outcome (success sentinel in `/tmp/acervo-ship-*.log`)
and recording it here — that verification is explicitly **out of scope for
this sortie**.

## Resulting CDN slug

`acervo ship` derives the CDN slug from the HuggingFace repo id using the
Acervo `{org}_{repo}` convention:

```
stabilityai/stable-audio-3-small-sfx  →  stabilityai_stable-audio-3-small-sfx
```

This is exactly `Acervo.slugify("stabilityai/stable-audio-3-small-sfx")`,
computed by `StableAudioModelRepo.componentId` in
`Sources/SwiftAmbiente/StableAudioModelRepo.swift`. Keeping the enum's raw
value, the Acervo component ID (registered in WU1 Sortie 2), and the CDN ship
slug all derived from the same string is what eliminates triple-naming drift
across the download path. `StableAudioModelRepo.smallSFX.rawValue` was
corrected in this sortie from the scaffold's stale
`stabilityai/stable-audio-open-small-sfx` (which predates the Stable Audio 3
family and does not resolve to a real upstream repo) to the
research-verified `stabilityai/stable-audio-3-small-sfx`, so the slug now
agrees end-to-end:

| Source | Value |
|---|---|
| `StableAudioModelRepo.smallSFX.rawValue` | `stabilityai/stable-audio-3-small-sfx` |
| Acervo component ID (`Acervo.slugify(rawValue)`) | `stabilityai_stable-audio-3-small-sfx` |
| CDN ship slug (`acervo ship` output) | `stabilityai_stable-audio-3-small-sfx` |

## Music/parity variant — dropped

The scaffold also declared a `smallMusic` case
(`stabilityai/stable-audio-open-small-music`). No Stable Audio 3 music-variant
repo is currently published upstream under the `stabilityai` org — the
scaffold value predates the SA3 family and does not resolve to a real
release. Per this sortie's scope, `StableAudioModelRepo.smallMusic` (and its
component descriptor) was **removed** rather than pointed at an unverified or
nonexistent repo id. There is therefore no music slug to ship. If Stability
publishes a verified SA3 music repo in the future, re-add the case following
the same `{org}_{repo}` pattern established above.

## License acceptance — USER-OWNED, not performed by any agent

**`acervo ship` mirrors weights to the CDN. It does not discharge, and is not
a substitute for, the legal obligations below.** Two separate licenses gate
any commercial use of this model, and acceptance/registration for both is
**exclusively the user's responsibility**:

1. **Stability AI Community License** — governs the Stable Audio 3 Small SFX
   weights themselves. Free for commercial use only **below ~US$1M annual
   revenue** (across all sources); **requires registration with Stability**
   for any commercial use; **terminates** above the $1M threshold (an
   Enterprise License must be separately negotiated). Also carries a "Powered
   by Stability AI" display obligation.
2. **Google Gemma Terms of Use** — governs the bundled **T5Gemma** text
   encoder shipped inside the SFX model. A separate, custom license with a
   §3.2 use-restriction clause and a Prohibited Use Policy that must be
   **passed through to end users** of any product embedding this library.

Neither this sortie nor any other agent in this mission accepts either
license, registers with Stability, or performs any action that could
constitute agreeing to these terms on the user's behalf. The prerequisite the
background `acervo ship` assumes — that the HuggingFace token used for the
download has already accepted the gated model's terms on HuggingFace — was
established by the user prior to launch, not by an agent.

The full license-acceptance checklist (registration steps, attribution
placement, prohibited-use acknowledgement) is produced by **Sortie 12**, not
this document.
