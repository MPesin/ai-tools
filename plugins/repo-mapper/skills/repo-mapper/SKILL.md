---
name: repo-mapper
description: Use when asked to map, index, or document a repository for AI agents, to generate or refresh a repo-guide skill, to replace or slim down a large CLAUDE.md, to generate a thin CLAUDE.md of always-loaded rules, or when /repo-map or /repo-mapper:init is invoked. Also use instead of /init when initializing AI context for a codebase.
---

# Repo Mapper

Generate a project skill at `.claude/skills/repo-guide/` — a small SKILL.md
index plus on-demand `references/` — so any AI agent gets oriented cheaply.
The inverse of /init: nothing is force-loaded into every prompt; the index
loads when triggered, its references only when a task needs them.

**Non-negotiables:** never regenerate without an explicit user go-ahead after a
cost estimate; never execute repo commands (build/test/etc.) without user
consent; never overwrite user-authored content without approval.

## References (load just-in-time)

| File | Load when |
|------|-----------|
| `references/output-spec.md` | Before dispatching indexers — exact contract for every generated file |
| `references/agent-playbook.md` | When dispatching the pipeline agents — prompts and rules |
| `references/freshness.md` | Refresh mode, stamps, staleness edge cases |
| `references/init-mode.md` | Init mode — thin CLAUDE.md of always-loaded rules |

## Process

1. **Preflight.** Detect: git repo? (no git → degraded mode, see freshness.md).
   Existing `.claude/skills/repo-guide/` — if present, check
   `git status --porcelain` on it for user edits in flight (ask before
   overwriting). A large existing CLAUDE.md? (migration offer only — never
   modified silently). Monorepo markers (workspaces, multiple packages).
2. **Mode.** map and refresh are the same full pipeline (refresh = full
   regeneration; the scout may read the existing SKILL.md as prior context
   but every area is re-planned from the current tree). Mode `init` is a
   different pipeline entirely: load `references/init-mode.md` and follow
   it instead of steps 3-8 below.
3. **Scout.** Dispatch `repo-scout` (agent-playbook.md). It returns a work plan:
   areas with globs, exclusions, size estimates, proposed verify commands.
4. **Confirm.** Show the user the plan + rough cost (N areas → N parallel
   agents) and ask before fan-out. Ask separately whether the proposed
   build/test commands may be executed for `commands.md` verification.
5. **Index.** Dispatch one `area-indexer` per area, all in a single message
   (parallel). Each writes `.claude/skills/repo-guide/.staging/<area>.md`.
6. **Assemble.** Dispatch `index-auditor`: verifies citations, resolves
   convention conflicts, writes final files per output-spec.md, removes staging.
7. **Review (offer, don't assume).** Offer a `design-critic` pass over the
   generated SKILL.md to flag unproven or wrong claims.
8. **Report.** List files written, SKILL.md size in lines, stamp commit. Offer to
   commit. If an existing fat CLAUDE.md was found, propose the migration plan
   (current → proposed) and wait for approval before shrinking it.
