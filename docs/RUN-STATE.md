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
11. [x] Acceptance: run /repo-map on a real repo, fresh session answers "where is X?" from index

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
- Restructure per user: marketplace renamed michaelp-ai-tools; critical-thinker
  split into its own general plugin (plugins/critical-thinker/); repo-mapper
  playbook references sibling plugin with general-agent fallback
- Renamed critical-thinker plugin/agent to design-critic (design-review focus explicit in name); all references updated
- Added README.md + MIT LICENSE; pushed to github.com/MPesin/ai-tools (public, HTTPS remote)
- Acceptance test on CodeReviewUtil PASSED: full pipeline run (scout → 11 indexers
  → auditor). Output: AGENTS.md 57 lines @ 4451a37, 5 refs + manifest, importers.
  25/25 citations verified. Hook silent on fresh index. Fresh-session probe answered
  a 3-part navigation question via CLAUDE.md → AGENTS.md → symbols.md/commands.md
  with only 1 verification grep — no grep crawl. Verified cmds: fmt/typecheck/lint exit 0.
  Generated files in CodeReviewUtil left uncommitted (user's call).
- Output dir changed per user: docs/agents/ → .repo-map/ (plugin spec/agents/hook/README + migrated CodeReviewUtil output, checksum recomputed, hook re-verified silent)
- Design change per user: generated output is now a PROJECT SKILL at
  .claude/skills/repo-guide/ (SKILL.md + references/ + manifest.json); no
  CLAUDE/AGENTS/GEMINI files created. Plugin spec/agents/hook/README updated
  (v0.2.0). CodeReviewUtil migrated; checksums rebuilt (whole-file sha256, now
  covering all generated files); hook re-verified silent. Second fresh-session
  probe PASSED via skill route (3 reads to change-site, no grep crawl).
- Verified via web: Copilot auto-discovers project skills in .claude/skills
  (Agent Skills support since 2025-12); Codex CLI same SKILL.md format but
  scans .codex/skills/ — symlink bridge proposed, not yet implemented.
- Lean redesign per user principle "information retrievable from git shouldn't
  be stored": manifest.json REMOVED entirely. Stamp/staleness/edit-detection all
  derived from git (git log -1 -- skill dir; rev-list count; status --porcelain).
  Hook rewritten in pure bash (no python), threshold 20 via REPO_MAPPER_STALE_THRESHOLD.
  Refresh = full regeneration (incremental machinery preserved in git history if
  ever needed). CodeReviewUtil migrated (manifest deleted, sha dropped from headers).
  Hook re-tested: uncommitted/fresh/non-git silent, 25-commits→message, override works, 129ms.
- OPEN: all caps/budgets/economics validated only on ONE SMALL repo (187 files).
  Before trusting at scale: run on a large monorepo, check scout decomposition,
  SKILL.md routing pressure, full-regen refresh cost. Spec now flags these as defaults.

## Feature: /repo-mapper:init (2026-08-25)

Goal: new init mode — generate a THIN CLAUDE.md (target ≤30 lines) holding only
the always-loaded behavioral layer NOT in the generated repo-guide: workflow
rules, hard constraints, env quirks. Approved design (bounded path):
- Output: thin CLAUDE.md only; NO repo-guide pointer (skill auto-discovery
  makes it redundant — user decision 2026-08-25)
- Prereq: reads existing repo-guide to know exclusions; if missing, offer to
  run full repo-map pipeline first
- Sources: harvest rule files (.cursor/rules, .cursorrules,
  copilot-instructions.md, CONTRIBUTING.md, existing CLAUDE.md) + one
  AskUserQuestion interview round; no history inference
- output-spec "never writes CLAUDE.md" stays true for map/refresh; init is the
  explicit user-approved exception

Tasks:
1. [x] commands/init.md (new) — /repo-mapper:init entry point, mode `init`
2. [x] SKILL.md — add init mode fork + reference-table row + description trigger
3. [x] references/init-mode.md (new) — full init procedure
4. [x] references/output-spec.md — reconcile CLAUDE.md exception paragraph
5. [x] Verify: TWO subagent dry-runs against CodeReviewUtil (has real repo-guide).
   Run 1 found 9 gaps (empty-harvest unspecified, staleness undefined for init,
   non-interactive deadlock, interview invites repo facts, dangling comment-format
   xref, closed-vs-open harvest list, etc.) — all fixed. Run 2 reached correct
   terminal outcome ("nothing to write", no file) and left 4 wording residues +
   1 leak risk (repo facts not categorically excluded) — all fixed: agent-rule
   file defined, step-5/step-7 composed, staleness command made executable,
   CATEGORICAL repo-fact exclusion added to Non-negotiables.
6. [x] README.md updated (init bullet, usage line, layout comment); plugin.json 0.4.0
7. [ ] Commit README/RUN-STATE (pending; plugin files committed in 58c2352)

## Feature: init v2 — /init-like exploration (2026-08-25)

User wants init to behave like built-in /init (explore the codebase) but with
zero duplicate work/instructions vs repo-guide. design-critic review (inline
charter) returned WITH CHANGES; all adopted:
- NO repo-guide patching (would reset the freshness signal keyed on
  `git log -1 -- .claude/skills/repo-guide`; reverses "refresh = full regen").
  Uncovered repo facts → report-only refresh suggestions. User decision.
- NO six-category gap-check (can't find a missing convention without
  re-deriving conventions → unverified partial re-index).
- Explorer reads META FILES ONLY (CI, .github templates, CONTRIBUTING,
  release/bootstrap scripts, CHANGELOG, toolchain files, .env.example,
  devcontainer, README setup sections) — never source code.
- git-log commit/branch style → interview pre-fill only, never a candidate.
- Routing tie-breaker: if a repo-guide section's contract would hold the
  fact, it is a repo-fact regardless of when an agent needs it.
- Non-interactive → emit proposal, write nothing.
- Stack-line interview pre-fill proposed, REJECTED by user ("no need").

Tasks:
1. [x] references/init-mode.md — rewrite steps 2–6 + explorer charter inline
2. [x] README init bullet
3. Verify: fixture dry-run PASSED — 12/12 pre-registered routes correct
       (7 CLAUDE.md bullets, 7 dropped w/ citation, prefill discarded, proposal
       emitted/nothing written). 14 ambiguities reported; fixed the real ones:
       directive-vs-fact rule (prohibitions win over section tie-breaker),
       branch/PR conventions are workflow not conventions.md, meta-file prose
       is a valid source, compound statements split, nonexistent-ref rules
       flagged, documented style needs no confirm, questions listed
       non-interactively, empty-hash = never committed. CodeReviewUtil dry-run
       (pre-fix doc) PASSED: "nothing to write", 24 candidates all dropped w/
       correct citations, zero leaks; its extra silences fixed (partial
       coverage split, contradictions → flagged refresh suggestion, ~10-entry
       cap, parent spot-checks covered_by, build manifests = facts only, script
       headers only). FINAL fixture re-run on revised doc PASSED: 12/12 routes,
       7 specific landings correct; last tweaks: inline flag on proposal line
       (stripped from file), directive keeps rationale, duplicate sources merge.
3. [x] Verify — DONE (3 dry-runs total on v2)
4. [ ] Commit

Next action: task 1.

## 2026-09-02 — marketplace expansion

Run tracking for this repo moved to the worklog format it now ships:
see docs/work/marketplace-expansion.md (plan, decisions, session log).
Summary: surveyed PR review, decision memory, multi-session workflow, the
skill landscape and Copilot/Codex compatibility (docs/RESEARCH.md); designed
pr-review, decision-log and worklog; design-critic review adopted (pr-review
scope cut to memory/learn/address on two agents; worklog stores no SHAs;
decision-log uses paths: + propose-only capture); built and validated all
three; added Codex-native marketplace and agent TOMLs via
scripts/sync-crosstool.py. Push blocked on GitHub App access at time of
writing.
