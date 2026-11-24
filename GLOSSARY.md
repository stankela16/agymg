# Antigravity Manager (agymg)

Canonical vocabulary for managing AI coding resources (MCP servers, skills, and plugins), their scope, and their context impact across Claude Code and Google Antigravity.

## Language

### Scope & Ownership

**Master Vault**:
The single source of truth for all registered MCP servers, skills, and plugins managed by agymg.
_Avoid_: Library, catalog, global store

**Global Core**:
The set of resources enabled across every workspace simultaneously, regardless of which project is open.
_Avoid_: Default resources, system-wide, shared

**Project Scope**:
The set of resources enabled exclusively for a single registered repository, isolated from all other projects.
_Avoid_: Local config, workspace overrides

**Repo Skill**:
A skill committed directly inside a repository's `.agents/skills/` or `.claude/skills/` directory rather than symlinked from the Master Vault.
_Avoid_: Local skill, untracked skill

**Effective Set**:
The combined list of resources active in a given workspace: Global Core plus Project Scope (plus any Repo Skills).
_Avoid_: Active list, merged config

### Context & Usage Hygiene

**Context Footprint**:
The estimated token overhead that an enabled resource adds to an AI session, split into always-on startup cost and on-demand invocation cost.
_Avoid_: Token count, size, weight

**Dormant Resource**:
An enabled resource (MCP server, skill, or plugin) with zero recorded invocations within the observation window.
_Avoid_: Unused, dead, idle, stale

**Context Bloat**:
A state where the Effective Set carries high Context Footprint from Dormant Resources or heavy MCP servers unnecessary for the current project.
_Avoid_: Overload, noise, clutter

**Context Health**:
A three-level hygiene rating (`Clean`, `Heavy`, `Bloated`) summarizing how much Dormant Resource weight and MCP schema load an Effective Set carries.
_Avoid_: Score, grade, status

**Observation Window**:
The rolling 30-day period over which local Antigravity and Claude Code transcripts are scanned to count resource invocations.
_Avoid_: History range, lookback

**Demote to Used Projects**:
Moving a resource out of Global Core and enabling it in Project Scope exclusively for the projects where it was invoked during the Observation Window.
_Avoid_: Downgrade, localize, split
