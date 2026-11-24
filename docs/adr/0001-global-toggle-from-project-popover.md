---
status: accepted
---

# Allow Toggling Global Core Resources Directly From Project Popover

Google Antigravity loads global MCP servers (`~/.gemini/config/mcp_config.json`) and global skills (`~/.gemini/config/skills/`) into every workspace without supporting a per-project exclusion list. Rather than locking `GLOBAL` toggles as read-only when viewing a project (which made active global MCPs feel unmanageable from the MenuBar popover) or faking a per-project exclude that Antigravity would ignore, we unlock the toggle so turning off a `GLOBAL` resource from a project popover disables it in Global Core immediately (with an inline Undo banner) and offer a "Move to Project-only" action in the expanded detail view.
