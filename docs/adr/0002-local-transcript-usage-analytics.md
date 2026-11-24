---
status: accepted
---

# Derive Resource Usage From Local Transcripts Instead of Runtime Proxies

To show how often each MCP server and skill is actually invoked without intercepting IDE traffic, modifying user prompts, or running background MCP proxies, `ContextUsageService` scans existing local Antigravity (`transcript.jsonl`) and Claude Code (`~/.claude/projects/*/*.jsonl`) session logs read-only over a rolling 30-day Observation Window. Results are cached incrementally by file path, size, and modification time so periodic background refreshes stay under a few milliseconds with zero UI impact and zero data leaving the machine.
