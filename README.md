# michaelp-ai-tools

A [Claude Code](https://claude.com/claude-code) plugin marketplace of general-purpose
AI tooling — skills and agents usable in any codebase, by anyone.

## Install

```
/plugin marketplace add MPesin/ai-tools
/plugin install repo-mapper@michaelp-ai-tools
/plugin install design-critic@michaelp-ai-tools
```

## Plugins

### repo-mapper — a `/init` replacement that doesn't flood your context

`/init` writes one large `CLAUDE.md` that gets loaded into **every** prompt,
mostly carrying information irrelevant to the task at hand. `repo-mapper`
inverts that:

- **`AGENTS.md` is the index** — hard-capped at 100 lines, stamped with the
  commit it was generated at. It holds the repo's purpose, stack, entry
  points, top gotchas, and a routing table telling agents which reference
  answers which question. Codex auto-loads it; `CLAUDE.md` and `GEMINI.md`
  become one-line `@AGENTS.md` imports — so Claude Code, Codex, and Gemini
  all see the same small index.
- **Depth is loaded on demand** — `.repo-map/` holds self-contained
  reference files (`architecture.md`, `modules.md`, `symbols.md`,
  `conventions.md`, `commands.md`). A typical task needs the index plus one
  or two of them, not all.
- **Indexing is a verified pipeline, not one long prompt** — a scout agent
  surveys the repo and sizes a work plan (you approve the cost before
  fan-out), parallel area-indexer agents each deep-read one subsystem, and an
  auditor verifies citations against the code, resolves convention conflicts,
  and assembles the final files. Symbols are indexed at *file* granularity —
  line numbers rot too fast to be trustworthy.
- **Staleness is detected, never guessed** — `.repo-map/manifest.json`
  records per-area commit stamps. A fail-silent SessionStart hook compares
  them against merge-base and tells you exactly which areas drifted:
  `repo index is 12 commits stale (areas: api) — run /repo-map refresh`.
  Refresh re-indexes only stale areas, and falls back to full regeneration
  when history was rewritten.
- **Nothing runs without consent** — regeneration is never automatic, and
  build/test commands are only executed (to mark `commands.md` entries
  `verified`) if you approve.

Usage: `/repo-map` for a full map, `/repo-map refresh` to update a stale index.

### design-critic — an adversarial design reviewer

An agent that reviews plans, specs, and architectures **before** they get
built (not a general critical-thinking aid): it attacks load-bearing
assumptions, hunts silent failure modes and second-run breakage, applies
YAGNI, steelmans a simpler alternative, and returns severity-ranked findings
(CRITICAL / MAJOR / MINOR) ending in a verdict — build as-is, build with
changes, or rethink. Read-only: it never edits or implements.

It verifies claims against reality (reads files, runs read-only commands)
instead of reasoning from the plan text alone. repo-mapper optionally uses it
to review a freshly generated index against the actual code.

This repository's own design was reviewed by it before being built.

## Repository layout

```
.claude-plugin/marketplace.json    # the marketplace manifest
plugins/repo-mapper/               # command, skill + references, 3 agents, hook
plugins/design-critic/             # the reviewer agent
```

## License

[MIT](LICENSE)
