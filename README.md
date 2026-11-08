<div align="center">

<img src="Sources/AntigravityManager/Resources/AppLogo.png" alt="agymg logo" width="88" height="88" />

# agymg

**Unified MCP, Skills & Plugins Control Center for Claude Code & Antigravity on macOS**

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-006C49?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://www.swift.org/)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-28C840?style=flat-square)](#architecture)
[![License: MIT](https://img.shields.io/badge/license-MIT-4EDEA3?style=flat-square)](LICENSE)

Define your MCP servers, skills, and plugins **once** in a local Master Vault—then toggle them globally or scope them per repository across **both** **Claude Code** and **Antigravity** in one click.

[Quick Install](#quick-install) • [Under the Hood Example](#minimal-example-sharing-1-mcp-server--1-skill-under-the-hood) • [What It Modifies](#what-agymg-modifies-on-disk) • [Headless CLI](#headless-cli--sessionstart-radar) • [Contributing](CONTRIBUTING.md)

</div>

---

<p align="center">
  <img src="docs/assets/control-center-vault.png" alt="agymg Master Vault Control Center" width="100%" />
</p>

<table>
  <tr>
    <td width="64%" valign="top">
      <img src="docs/assets/project-isolation.png" alt="Per-Project MCP & Skill Isolation" width="100%" />
      <p align="center"><sub><b>Per-Project Isolation</b> — Scoped MCP manifests, POSIX skill symlinks, and live <code>.gitignore</code> safety audits.</sub></p>
    </td>
    <td width="36%" valign="top">
      <img src="docs/assets/menubar-popover.png" alt="MenuBar Quick Popover" width="100%" />
      <p align="center"><sub><b>Menubar Popover (<code>⌃⌥A</code>)</b> — Instant toggles and stack-aware recommendations.</sub></p>
    </td>
  </tr>
</table>

---

## Why `agymg`?

Running **Claude Code** alongside **Antigravity** on the same Mac quickly turns into configuration drift and context bloat:

1. **Global MCP Bloat**: Enabling 15 MCP servers globally injects hundreds of tool schemas into *every* agent conversation—burning tokens and exposing production APIs (Stripe, Supabase, cloud providers) inside unrelated repositories.
2. **Incompatible Config Layouts**:
   - **Antigravity** reads global servers from `~/.gemini/config/mcp_config.json` (`serverUrl`), ignores root `.agents/mcp_config.json`, and requires per-project MCP servers to be packaged as a local plugin inside `<repo>/.agents/plugins/<name>/`.
   - **Claude Code** stores user and per-project `mcpServers` inside `~/.claude.json` (`type: "http"`, `url`) and reads skills from `~/.claude/skills/` and `<repo>/.claude/skills/`.
3. **Duplicated Skills**: Maintaining two copies of `SKILL.md` folders across `.claude/skills` and `.agents/skills` guarantees they fall out of sync.

**`agymg` solves all three** with a zero-dependency native SwiftUI menubar app + headless CLI (`< 15 MB` RAM, zero Node/Electron background processes).

---

## Quick Install

> **Requirements**: macOS 14.0+ (Sonoma or Sequoia) and Xcode 16+ or Xcode Command Line Tools 16+ with **Swift 6.0+** (`xcode-select --install`).

### Option 1 — One-Command Install (Recommended)

Compiles a native release binary locally on your Mac and signs `agymg.app` ad-hoc—**zero `com.apple.quarantine` Gatekeeper popups** without needing a paid Apple Developer certificate:

```bash
curl -fsSL https://raw.githubusercontent.com/stankela16/agymg/v1.0.1/Scripts/install.sh | bash
```

This installs `/Applications/agymg.app` and links the `agymg` CLI into `~/.local/bin/agymg` or `/opt/homebrew/bin/agymg` (without overwriting an existing Homebrew formula symlink).

### Option 2 — Homebrew

```bash
brew install stankela16/tap/agymg
agymg install-app
```

### Option 3 — Build from Source

```bash
git clone https://github.com/stankela16/agymg.git
cd agymg
./Scripts/install.sh
```

Launch `agymg` from Spotlight or `/Applications/agymg.app`. On first launch, choose your Projects folder (or skip and import individual repositories anytime with `⌘O`). Existing MCP servers and skills from `~/.claude.json`, `~/.claude/skills`, and `~/.gemini/config/` are imported into your Master Vault automatically—after taking a timestamped `0600` backup snapshot of your original configs.

---

## Minimal Example: Sharing 1 MCP Server & 1 Skill Under the Hood

Curious what `agymg` actually writes to disk—or want to wire up the same cross-agent pattern manually? Here is the exact layout for sharing **one scoped MCP server (`supabase`)** and **one skill (`react-perf`)** inside `~/Projects/acme-web`:

### 1. Single Source of Truth (`~/.gemini/manager-vault/`)

```text
~/.gemini/manager-vault/
├── master_mcp.json               # Canonical MCP definitions (stdio + remote HTTP/SSE)
└── skills/
    └── react-perf/
        └── SKILL.md              # Canonical skill instructions (authored once)
```

### 2. What `agymg` Generates for `~/Projects/acme-web`

```text
~/Projects/acme-web/
├── .gitignore                    # Updated only when .git exists AND project MCPs are enabled
├── .git/info/exclude             # Keeps symlinked .claude/skills entries out of `git status`
├── .agents/                      # ← Read by Antigravity
│   ├── skills/
│   │   └── react-perf -> ~/.gemini/manager-vault/skills/react-perf
│   └── plugins/
│       └── agy-manager/          # Local plugin wrapper required by Antigravity for per-repo MCP
│           ├── plugin.json
│           └── mcp_config.json
└── .claude/                      # ← Read by Claude Code
    └── skills/
        └── react-perf -> ~/.gemini/manager-vault/skills/react-perf
```

#### Antigravity Per-Project Plugin (`.agents/plugins/agy-manager/plugin.json` & `mcp_config.json`)

Antigravity only scopes MCP servers to a single repository when wrapped in a local `.agents/plugins/<name>/` bundle:

```json
// .agents/plugins/agy-manager/plugin.json
{
  "name": "agy-manager"
}
```

```json
// .agents/plugins/agy-manager/mcp_config.json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": ["-y", "@supabase/mcp-server-supabase"],
      "env": {
        "SUPABASE_ACCESS_TOKEN": "sbp_..."
      }
    }
  }
}
```

#### Claude Code Per-Project Scope (`~/.claude.json`)

Simultaneously, `agymg` updates only the `mcpServers` map under the matching project entry inside `~/.claude.json` (preserving file permissions, security trust prompts, OAuth state, and history, while translating remote `serverUrl` ↔ `{"type": "http", "url": "..."}`):

```json
{
  "projects": {
    "/Users/alex/Projects/acme-web": {
      "mcpServers": {
        "supabase": {
          "type": "stdio",
          "command": "npx",
          "args": ["-y", "@supabase/mcp-server-supabase"],
          "env": {
            "SUPABASE_ACCESS_TOKEN": "sbp_..."
          }
        }
      }
    }
  }
}
```

And because both `.agents/skills/react-perf` and `.claude/skills/react-perf` are **POSIX symlinks** pointing to `~/.gemini/manager-vault/skills/react-perf`, editing `SKILL.md` once updates both agents immediately.

---

## What `agymg` Modifies on Disk

`agymg` operates exclusively on local configuration files and POSIX symlinks—no background daemons when closed, no network telemetry, and no bypassing of Claude Code trust prompts:

| Location | Behavior |
| :--- | :--- |
| `~/.gemini/manager-vault/` | Canonical Master Vault directory (`0700`) containing `master_mcp.json`, `global_selection.json`, `projects.json`, `skills/`, `plugins/`, and `backups/snapshot-<timestamp>/` (`0600` JSON files). |
| `~/.gemini/config/skills/` & `~/.claude/skills/` | Pre-existing and newly created global skill folders (older than 30s) are adopted into `~/.gemini/manager-vault/skills/<id>/` and replaced with POSIX symlinks so both agents share one copy. Running `agymg uninstall --restore` converts them back into standalone physical folders. |
| `~/.gemini/config/mcp_config.json` | Writes `mcpServers` (`0600` permissions) with `"disabled": false` for globally enabled servers and `"disabled": true` for catalog-only servers, preserving unrelated top-level keys. |
| `~/.claude.json` | Updates user-scope `mcpServers` and `projects["<repo>"].mcpServers` while preserving existing file permissions and all other keys. Never sets `hasTrustDialogAccepted` or `enableAllProjectMcpServers`, and never overwrites a physical `~/.claude/CLAUDE.md`. |
| `<repo>/.agents/plugins/agy-manager/` | Created (`0600` `mcp_config.json`) **only** when a registered project has at least one project-scoped MCP server enabled; removed when project MCPs are disabled. |
| `<repo>/.gitignore` & `<repo>/.git/info/exclude` | Appends `.agents/plugins/agy-manager/` to `.gitignore` **only** when `<repo>/.git` exists **and** at least one project MCP server is enabled. Symlinked `.claude/skills/<id>` entries are recorded in local `.git/info/exclude` so `git status` remains clean without modifying `.gitignore`. |
| `~/.claude/hooks/mcp-oauth-headers.py` | Installed and referenced via `"headersHelper"` **only** when an enabled remote HTTP MCP server has an existing OAuth token entry in `~/.gemini/antigravity/mcp_oauth_tokens.json` and no static `Authorization` header. |

> **Safety Invariant**: During sync and purge operations, `agymg` only removes POSIX symlinks in target skill/plugin directories—it never deletes real committed or standalone directories.

---

## Features

- **Master Vault (`~/.gemini/manager-vault/`)**: One local catalog for all MCP servers (`stdio` commands + remote HTTP/SSE endpoints), `SKILL.md` packages, and plugins.
- **Zero-Config First-Run Bootstrap**: Automatically imports existing MCP servers and skills from both Claude Code (`~/.claude.json`, `~/.claude/skills/`) and Antigravity (`~/.gemini/config/mcp_config.json`, `~/.gemini/config/skills/`).
- **Global Core vs. Per-Project Isolation**: Keep universal tools (e.g., `github`) in **Global Core** while isolating domain-specific MCPs (`stripe`, `supabase`, `playwright`) to the repositories that actually need them.
- **Menubar Quick Popover & Global Hotkey (`⌃⌥A`)**: Detects your active IDE workspace automatically, surfaces stack-aware recommendations (`package.json`, `Package.swift`, `pyproject.toml`, `Cargo.toml`, `supabase/`), and lets you toggle tools without leaving your editor.
- **Git & Secret Safety Audits**: Protects `.agents/plugins/agy-manager/` in `.gitignore` when writing project MCP manifests and enforces `0600` owner-only permissions on generated credential configs.
- **Live External Change Adoption**: Runs a lightweight 15-second reconciliation check so tools added via `claude mcp add`, `agy mcp`, or newly created skill folders are adopted back into your Vault seamlessly.
- **Automatic & Manual Config Backups**: Before `agymg` touches any external config file for the first time, it snapshots your existing `.claude.json` and `mcp_config.json` into `~/.gemini/manager-vault/backups/snapshot-<timestamp>/` (retaining up to 10 snapshots while always preserving your initial `pre-first-sync` backup, plus one-click manual backups in **Settings → Master Vault**).

---

## Headless CLI & `SessionStart` Radar

Every installation includes the `agymg` CLI for terminal workflows, scripts, and agent hooks:

```bash
# Compact workspace summary + smart Vault recommendations
agymg brief --project ~/Projects/acme-web

# Machine-readable JSON state for scripts or custom skills
agymg brief --project . --json

# Enable or disable Vault resources for a specific project (syncs manifests & symlinks immediately)
agymg set --project . --enable-mcp playwright --enable-skill react-perf

# Enable or disable Vault resources globally across all workspaces
agymg set --global --disable-mcp linear

# Copy agymg.app into /Applications (used after `brew install stankela16/tap/agymg`)
agymg install-app

# Restore symlinked skills/plugins to standalone folders & clean wrappers/hooks
agymg uninstall --restore

# Print CLI version
agymg --version
```

### Optional: Proactive Claude Code `SessionStart` Hook

Want Claude Code to surface missing Vault tools automatically when you open a repository? Add the read-only `agymg hook-session-start --format claude-text` command to `~/.claude/settings.json` (or `agymg hook-session-start --format antigravity` for Antigravity hooks):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "agymg hook-session-start --format claude-text"
          }
        ]
      }
    ]
  }
}
```

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌃⌥A` | Open Control Center window globally from any app |
| `⌘0` | Open Control Center window |
| `⌘1` – `⌘5` | Jump to Master Vault, Global Core, Plugins, Built-ins, or Sync Logs |
| `⌘S` | Synchronize all global and project configurations to disk |
| `⌥⌘S` | Synchronize active workspace |
| `⌘R` | Reload system and workspace definitions from disk |
| `⇧⌘R` | Reveal `~/.gemini/manager-vault/` in Finder |
| `⌘N` | Create a new project workspace |
| `⌘O` | Import an existing project folder into `agymg` |
| `⌘F` | Filter servers, skills, or plugins |
| `⌘,` | Open Settings |

---

## Sandboxed / Custom Environment Variables

For multi-profile setups, CI, or isolated testing without touching `~/.gemini`:

| Variable | Description |
| :--- | :--- |
| `AGYMG_GEMINI_DIR` | Override the base `.gemini` directory (Vault is stored at `$AGYMG_GEMINI_DIR/manager-vault`). |
| `AGYMG_PROJECTS_DIR` | Override the default Projects workspace scan root. |

---

## Uninstall & Restore

1. Restore symlinked skills and plugins back into standalone physical folders and clean up `agymg` project wrappers and Claude hooks:
   ```bash
   agymg uninstall --restore
   ```
   *(Pass `--purge-vault` as well if you also want to delete `~/.gemini/manager-vault/` and its configuration snapshots immediately.)*
2. Remove the application bundle and CLI binary:
   ```bash
   # If installed via Homebrew:
   brew uninstall agymg
   rm -rf /Applications/agymg.app

   # If installed via Scripts/install.sh:
   rm -rf /Applications/agymg.app /opt/homebrew/bin/agymg ~/.local/bin/agymg
   ```

---

## Architecture & Contributing

Built with **Swift 6** (`strict-concurrency=complete`), **SwiftUI**, and **AppKit** using Swift Package Manager—zero external dependencies.

- Read [AGENTS.md](AGENTS.md) for codebase layout and sync invariants.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) for build, packaging, and test instructions (`swift test` runs sandboxed unit & integration tests).

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Nikola Stanojevic.
