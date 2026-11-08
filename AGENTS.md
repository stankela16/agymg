# AGENTS.md — Contributor & AI Coding Agent Guide

`agymg` is a native macOS 14+ (Sonoma / Sequoia) MenuBar + Control Center application and headless CLI written in Swift 6 and SwiftUI. It acts as a single **Master Vault** (`~/.gemini/manager-vault/`) that synchronizes MCP servers, `SKILL.md` skills, and plugins across **Claude Code** and **Google Antigravity** — both globally and per repository.

---

## 1. Architecture Overview

### Master Vault (`~/.gemini/manager-vault/`)
- `master_mcp.json` — Canonical catalog of MCP server definitions (normalized to Antigravity format: `command`/`args`/`env` for stdio, `serverUrl`/`headers` for remote SSE/HTTP).
- `skills/<skill-id>/SKILL.md` — Canonical skill directories synced via POSIX symlinks.
- `plugins/<plugin-id>/` — Reusable plugin bundles (`plugin.json`, `mcp_config.json`, `skills/`).
- `global_selection.json` — IDs of resources enabled globally across all workspaces.
- `projects.json` — Registered `ProjectProfile` records and per-project resource selections.
- `backups/snapshot-<timestamp>/` — Automatic pre-first-sync and manual configuration snapshots (retains the 10 most recent snapshots).

### Synchronization Targets (`SyncEngine`)
1. **Global Core**:
   - **Antigravity**: Writes `~/.gemini/config/mcp_config.json` (`"disabled": false` for enabled global servers, `"disabled": true` for catalog-only servers), symlinks enabled global skills into `~/.gemini/config/skills/`, and links plugins into `~/.gemini/config/plugins/`.
   - **Claude Code**: Updates user-scope `mcpServers` in `~/.claude.json` (preserving all other keys and `projects` entries, translating `serverUrl` → `url` + `"type": "http"` or `"type": "stdio"`), and symlinks enabled global skills into `~/.claude/skills/`.
2. **Project Isolation (`SyncEngine+Project`)**:
   - **Antigravity**: Because Antigravity does not load a bare `<repo>/.agents/mcp_config.json`, `agymg` generates a local plugin wrapper at `<repo>/.agents/plugins/agy-manager/plugin.json` + `mcp_config.json` (`0600`), symlinks project skills into `<repo>/.agents/skills/`, and protects `.agents/plugins/agy-manager/` in `<repo>/.gitignore` whenever `<repo>/.git` exists and project MCP servers are enabled so API tokens are never committed.
   - **Claude Code**: Writes project-scoped `mcpServers` under `projects["<repo_path>"].mcpServers` in `~/.claude.json` and symlinks project skills into `<repo>/.claude/skills/` without touching committed repository-local skills.
3. **External Adoption (`VaultService.adoptExternalChanges`)**:
   - Every 15 seconds while the app is running, newly added MCP servers (`claude mcp add`, `agy mcp`) and newly created skills (older than 30 seconds so in-flight agent writes are never interrupted) are imported into the Master Vault instead of being overwritten.

---

## 2. Swift 6 & macOS HIG Engineering Standards

1. **Strict Concurrency**:
   - Release builds compile with `-Xswiftc -strict-concurrency=complete`.
   - UI state lives in `@MainActor @Observable final class AppState`. File I/O and manifest generation run inside `actor SyncEngine` and `actor VaultService`.
2. **Zero I/O in `View.body`**:
   - Never call `FileManager`, `UserDefaults`, `JSONSerialization`, or `Process` inside SwiftUI `body` properties. Precompute or load asynchronously via `.task` / `@Observable` state.
3. **Apple HIG & 8pt Grid**:
   - Use `DesignTokens.Spacing` (`4pt`, `8pt`, `12pt`, `16pt`, `24pt`, `32pt`), semantic `NSColor`-backed SwiftUI colors, and translucent macOS materials.
   - Do not introduce nested vertical `ScrollView`s inside `Vault*Tab` or `Project*Tab` views; `MasterVaultView` and `ProjectDetailView` own the single outer `ScrollView`.
4. **Test Airlock**:
   - `PathConstants.isRunningUnderTests` routes all fallback paths to a temporary sandbox directory (`AntigravityTestAirlock`) so `swift test` never touches a developer's real `~/.gemini` or `~/.claude.json`.

---

## 3. Build, Test & Package Commands

```bash
# Run unit & adversarial test suite
swift test

# Build release binary with strict concurrency checks
swift build -c release -Xswiftc -strict-concurrency=complete

# Assemble & ad-hoc sign agymg.app
./Scripts/package_app.sh release
```
