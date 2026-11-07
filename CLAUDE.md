---
type: reference
---

# CLAUDE.md

**Claude Code-specific instructions for SwiftAmbiente**

For comprehensive project documentation, architecture, and the Stable Audio
integration plan, see **[AGENTS.md](AGENTS.md)**.

---

## Claude Code Tool Preferences

### Build System

**CRITICAL**: Always use `xcodebuild` or Makefile targets. NEVER use `swift build` or `swift test`.

```bash
# ✅ CORRECT
make build
make test
xcodebuild build -scheme ambiente -destination 'platform=macOS,arch=arm64'

# ❌ WRONG
swift build
swift test
```

The procedural generator has no native ML dependency today, so `swift build`
would *appear* to work — but the project follows the ecosystem `xcodebuild`
convention so that the staged MLX Stable Audio backend (which needs Metal shader
compilation) drops in without a build-system migration.

### Tool Usage

- **Read/Write/Edit** — Prefer these over `cat`, `sed`, `echo >>`
- **Glob** — Prefer over `find` or `ls` for file discovery
- **Grep** — Prefer over `grep` or `rg` for content search
- **Bash** — Reserve for git, build commands, system operations only

### Git Workflow

- Branch: `development` → PR → `main`
- Never commit directly to `main`
- Use `/ship-swift-library` skill for releases

### Platform Constraints

- **ONLY** iOS 26.0+ and macOS 26.0+
- **NEVER** add `@available` attributes for older versions
- **Apple Silicon only** — M1/M2/M3/M4/M5 required

---

**See [AGENTS.md](AGENTS.md) for:**
- Architecture (the `AmbienteGenerator` backend abstraction)
- The Stable Audio 3 Small SFX integration plan and **licensing obligations**
- CLI (`ambiente`) usage and scene presets
