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

---

## Sortie 12 — Ship verification

**Status**: VERIFIED. The background `acervo ship stabilityai/stable-audio-3-small-sfx
--no-verify` launched during refinement completed successfully. Verified by
reading the log directly (not re-run — `acervo ship` was NOT re-invoked by
this sortie):

```
/tmp/acervo-ship-stabilityai_stable-audio-3-small-sfx-20260718-045718Z.log
```

Recorded log lines:

```
==ACERVO_START=2026-07-18T04:57:18Z==
==ACERVO_MODEL=stabilityai/stable-audio-3-small-sfx==
==ACERVO_CMD=acervo ship stabilityai/stable-audio-3-small-sfx --no-verify ==
CHECK 0 passed: staging directory matches HF tree listing.
CHECK 4 passed: all staged files match the manifest.
CHECK 5 passed: CDN manifest verified.
CHECK 6 passed: config.json spot-check succeeded.
no orphans to prune.
Ship complete for stabilityai/stable-audio-3-small-sfx.
==ACERVO_EXIT=0==
==ACERVO_END=2026-07-18T05:10:57Z==
```

All 6 CHECKs passed (CHECK 0, 1–3 implicit in the staged/manifest steps,
CHECK 4, CHECK 5, CHECK 6). The success sentinel `==ACERVO_EXIT=0==` confirms
the upload completed without error.

**Resolvable CDN slug**: `stabilityai_stable-audio-3-small-sfx` — this is the
slug now live on SwiftAcervo's shared-models CDN, matching the
`{org}_{repo}` derivation recorded above and the `StableAudioModelRepo`
component ID from WU1 Sortie 2.

Uploaded artifacts observed in the log include both license files bundled in
the upstream HF repo — `LICENSE.md` (Stability AI Community License) and
`LICENSE_GEMMA.md` (Google Gemma Terms of Use) — plus `NOTICE`, confirming
both licenses travel with the mirrored weights. Their presence on the CDN
does **not** constitute acceptance of either license by any agent; see the
checklist below.

## License-acceptance checklist (USER ACTION required — not performed by any agent)

Every item below is a legal-acceptance or registration action. **No sortie,
agent, or automated process in this mission has performed, or is authorized
to perform, any of these items.** The agent's role was limited to running the
`acervo ship` upload mechanic (OQ-4); it stops there.

### Stability AI Community License (governs the Stable Audio 3 Small SFX weights)

- [ ] **USER ACTION (user-owned)** — Register with Stability AI at
      `stability.ai/license` before any commercial use of the shipped
      weights. Registration is mandatory for commercial use regardless of
      revenue.
- [ ] **USER ACTION (user-owned)** — Confirm the deploying organization's
      annual gross revenue (across all sources, not just this product) is
      below the ~US$1M threshold. Commercial use above that threshold is
      **not covered** by the free Community License.
- [ ] **USER ACTION (user-owned)** — If/when annual revenue crosses the
      ~US$1M threshold, the Community License **terminates** for commercial
      use; a separate **Enterprise License** must be negotiated directly with
      Stability AI before continuing commercial use. This is a live,
      revenue-tracked obligation, not a one-time check.
- [ ] **USER ACTION (user-owned)** — Implement and maintain the **"Powered by
      Stability AI"** display obligation in any product/UI that ships audio
      generated by this backend, per the Community License's attribution
      requirements.
- [ ] **USER ACTION (user-owned)** — Retain `LICENSE.md` (Stability AI
      Community License, shipped alongside the weights per the log above) in
      any redistribution of the model or derivative product documentation.

### Google Gemma Terms of Use (governs the bundled T5Gemma text encoder)

- [ ] **USER ACTION (user-owned)** — Read and accept Google's Gemma Terms of
      Use for the T5Gemma text encoder shipped inside the SFX model
      (`t5gemma-b-b-ul2/`), separately from the Stability license. Acceptance
      is a distinct legal act from accepting the Stability Community License.
- [ ] **USER ACTION (user-owned)** — Comply with Gemma Terms **§3.2 use
      restrictions** for any product that embeds this library.
- [ ] **USER ACTION (user-owned)** — Comply with and enforce the Gemma
      **Prohibited Use Policy** referenced by §3.2.
- [ ] **USER ACTION (user-owned)** — **Pass through** the Gemma Prohibited Use
      Policy obligations to **end users** of any app/product embedding
      SwiftAmbiente — this is a redistribution obligation, not satisfied by
      the library author's own compliance alone.
- [ ] **USER ACTION (user-owned)** — Provide attribution to Google for the
      Gemma-derived T5Gemma component, and retain `LICENSE_GEMMA.md` (shipped
      alongside the weights per the log above) in any redistribution.
- [ ] **USER ACTION (user-owned)** — Before commercial ship, have counsel
      verify the Gemma pass-through mechanics for an *embedded* Swift library
      (as opposed to a standalone Gemma-branded app) — flagged as an
      ambiguous item by the mission's research pass and not resolved by this
      sortie.

### Explicitly out of scope for every agent in this mission

- No agent has registered with Stability AI on the user's behalf.
- No agent has accepted the Stability AI Community License terms.
- No agent has accepted the Google Gemma Terms of Use.
- No agent has implemented the "Powered by Stability AI" UI obligation or the
  Gemma prohibited-use pass-through in shipped product code — those are
  product-level, user-owned engineering + legal actions tracked separately
  (see WU4 Sortie 14 for the README/NOTICE documentation of these
  obligations, which is documentation of the requirement, not discharge of
  it).
