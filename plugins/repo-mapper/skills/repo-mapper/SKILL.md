---
name: repo-mapper
description: Use when asked to map, index, or document a repository for AI agents, to generate or refresh AGENTS.md / .repo-map/, to replace or slim down a large CLAUDE.md, or when /repo-map is invoked. Also use instead of /init when initializing AI context files for a codebase.
---

# Repo Mapper

Generate a small, stamped `AGENTS.md` index plus on-demand reference files in
`.repo-map/`, so any AI agent (Claude Code, Codex, Gemini) gets oriented
cheaply. The inverse of /init: the always-loaded file stays tiny; depth is
loaded only when a task needs it.

**Non-negotiables:** never regenerate without an explicit user go-ahead after a
cost estimate; never execute repo commands (build/test/etc.) without user
consent; never overwrite user-authored content without approval.

## References (load just-in-time)

| File | Load when |
|------|-----------|
| `references/output-spec.md` | Before dispatching indexers — exact contract for every generated file |
| `references/agent-playbook.md` | When dispatching the pipeline agents — prompts and rules |
| `references/freshness.md` | Refresh mode, stamps, staleness edge cases |

## Process

1. **Preflight.** Detect: git repo? (no git → degraded mode, see freshness.md).
   Existing `.repo-map/manifest.json`? Existing `AGENTS.md` / `CLAUDE.md` /
   `GEMINI.md` and whether they are user-authored, generated, or generated-then-
   edited (checksums in manifest). Monorepo markers (workspaces, multiple
   packages).
2. **Mode.** Manifest exists and user asked for refresh → refresh (freshness.md
   algorithm picks stale areas only). Otherwise full map. Unreachable stamp
   commit → full map.
3. **Scout.** Dispatch `repo-scout` (agent-playbook.md). It returns a work plan:
   areas with globs, exclusions, size estimates, proposed verify commands.
4. **Confirm.** Show the user the plan + rough cost (N areas → N parallel
   agents) and ask before fan-out. Ask separately whether the proposed
   build/test commands may be executed for `commands.md` verification.
5. **Index.** Dispatch one `area-indexer` per area, all in a single message
   (parallel). Each writes `.repo-map/.staging/<area>.md`.
6. **Assemble.** Dispatch `index-auditor`: verifies citations, resolves
   convention conflicts, writes final files per output-spec.md, writes
   manifest.json, patches pointer files, removes staging.
7. **Review (offer, don't assume).** Offer a `design-critic` pass over the
   generated AGENTS.md to flag unproven or wrong claims.
8. **Report.** List files written, index size in lines, stamp commit. Offer to
   commit. If an existing fat CLAUDE.md was found, propose the migration plan
   (current → proposed) and wait for approval before shrinking it.
