# repo-mapper build — run state

## Goal
Claude Code plugin "repo-mapper" (in ai-tools marketplace repo) replacing /init:
generates a small AGENTS.md index (≤100 lines, stamped) + docs/agents/ references
+ manifest.json in any target repo, usable by Claude/Codex/Gemini. Ships 4 agents
(repo-scout, area-indexer, index-auditor, critical-thinker), /repo-map command,
SessionStart staleness hook.

## Design decisions (from critical review, all approved)
- AGENTS.md IS the index; CLAUDE.md and GEMINI.md are `@AGENTS.md` one-liners
- References in docs/agents/ (NOT .agent/ — collides with Antigravity; no SKILL.md name in output)
- docs/agents/manifest.json: subsystems→globs, per-area stamp commits, generator version;
  hook + incremental refresh read ONLY manifest, never prose
- symbols at FILE granularity (no line numbers — rot economics)
- Generated output is COMMITTED; hook compares merge-base not HEAD
- Refresh: unreachable stamp → full regen; reconcile deleted/renamed dirs; detect user edits in marker regions
- Big repos: gitignore-derived exclusions, subsystem size cap w/ splitting, cost estimate + confirm before fan-out; monorepo → per-package nested AGENTS.md
- Hook: startup matcher only, <100ms, fail-silent, non-git → silent skip. No Tier-3 git hook.
- commands.md: consent gate before executing anything; verified/unverified marking
- Never auto-regenerate. Pipeline: scout → N area-indexers (parallel) → auditor (assemble,
  resolve convention conflicts) → optional critical-thinker review of generated AGENTS.md

## Tasks
1. [x] Repo housekeeping: git init done (0 commits), remove stray empty agents/ skills/ dirs, .gitignore (.remember/, .claude/ state)
2. [x] .claude-plugin/marketplace.json (marketplace: ai-tools)
3. [x] plugins/repo-mapper/.claude-plugin/plugin.json
4. [x] plugins/repo-mapper/commands/repo-map.md (/repo-map [refresh])
5. [x] plugins/repo-mapper/skills/repo-mapper/SKILL.md (small orchestrator)
6. [x] skills references: output-spec.md, agent-playbook.md, freshness.md
7. [x] agents: repo-scout.md, area-indexer.md, index-auditor.md
8. [x] agents: critical-thinker.md (move from .claude/agents/, keep charter, add generated-index review mode)
9. [x] hooks/hooks.json + hooks/staleness-check.sh (startup only, manifest-driven, fail-silent)
10. [x] Commit; give user install steps (/plugin marketplace add <path>, /plugin install repo-mapper@ai-tools)
11. [ ] Acceptance: run /repo-map on a real repo, fresh session answers "where is X?" from index

## Files touched so far
- .claude/agents/critical-thinker.md (created; to be moved into plugin in task 8)
- docs/RUN-STATE.md (this file)

## Commands run
- agent registry check: 'critical-thinker' type not live until session reload (used claude type w/ charter inline for review)

## Open questions
- Cheap experiment pending (post-build): does Codex follow routing table from AGENTS.md to docs/agents/?

## Next action
Task 1 housekeeping, then invoke superpowers:writing-skills before authoring SKILL.md content.

## Build log 2026-08-24
- All files written; hook tested (fresh/stale/unreachable/non-git all correct, 133ms)
- critical-thinker moved from .claude/agents/ into plugin (project copy removed)
- Remaining: task 11 acceptance test on a real repo after user installs plugin
