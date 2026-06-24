---
type: reference
---

# GEMINI.md

**Gemini-specific instructions for SwiftAmbiente**

For comprehensive project documentation, architecture, and the Stable Audio
integration plan, see **[AGENTS.md](AGENTS.md)**.

---

## Build System

**CRITICAL**: Always use `xcodebuild` or Makefile targets. NEVER use `swift build` or `swift test`.

```bash
# ✅ CORRECT
make build
make test

# ❌ WRONG
swift build
swift test
```

## Platform Constraints

- **ONLY** iOS 26.0+ and macOS 26.0+
- **NEVER** add `@available` attributes for older versions
- **Apple Silicon only** — M1/M2/M3/M4/M5 required

## Git Workflow

- Branch: `development` → PR → `main`
- Never commit directly to `main`

---

**See [AGENTS.md](AGENTS.md) for architecture, the Stable Audio integration plan,
and licensing obligations.**
