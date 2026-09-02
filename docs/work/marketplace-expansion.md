# Marketplace expansion: pr-review, decision-log, worklog, cross-tool install
Status: active · Branch: claude/marketplace-tools-research-mcxg6w · Started: 2026-09-02
Next action: T09 — acceptance: install the three plugins from this branch in a real repo and run /pr-review on an open PR, /decision-log:init, /work start (human-verify)

## Goal
Add three plugins the author asked for (PR review, per-repo domain-based
decision memory generated as a project skill, multi-session workflow with
progress logging), grounded in a survey of existing implementations, and make
the marketplace installable from Copilot CLI and Codex CLI. Leanness over
feature count; stack-agnostic; house principles (on-demand skills, git is the
only state store, consent gates) hold for all three.
Links: docs/RESEARCH.md (survey). The design document and the design-critic
review were session-local; their verdicts are summarized under Decisions.

## Plan
- [x] T01 Survey PR review, decision memory, multi-session workflow, skill landscape, Copilot/Codex (verify: grep -c 'https://' docs/RESEARCH.md → 70+ sources)
- [x] T02 Design the three plugins; adversarial review with the design-critic charter (verify: design review → RETHINK scope / WITH CHANGES / WITH CHANGES, all adopted)
- [x] T03 Build pr-review (verify: claude plugin validate plugins/pr-review --strict → passed, plus skills/agents/commands dirs)
- [x] T04 Build decision-log (verify: claude plugin validate plugins/decision-log --strict → passed after frontmatter fix)
- [x] T05 Build worklog incl. hook (verify: validate → passed; hook fixture: empty/uncommitted/fresh/3 commits/55 commits/two items/non-git all valid JSON, 16 ms)
- [x] T06 Cross-tool: Codex marketplace + agent TOMLs via scripts/sync-crosstool.py, explicit commands path, portable hook var (verify: sync --check → in sync; tomllib parses all 7 files)
- [x] T07 Register plugins in marketplace.json; README; RESEARCH.md Copilot/Codex section (verify: claude plugin validate . --strict → passed)
- [x] T08 Push the branch — git push was 403 (session credential lacks the repo); replayed through the GitHub API (verify: git fetch + git diff HEAD origin/branch → only two exec-bit mode changes)
- [ ] T09 Checkpoint: acceptance on a real repo (human-verify)
- [x] T11 Fixture dry-run of the three skills by a fresh agent; fix every ambiguity and silent failure it found (verify: claude plugin validate --strict on all plugins → passed; hook fixture with control chars → valid JSON)
- [ ] T10 Dogfood: use /work log and /decide from this file in the next session

## Decisions
- Ruling: pr-review builds the memory/learn/address layer on two agents, not a five-lens hunter pipeline — the built-in /code-review already is the hunter — cost if wrong: lower catch rate on first-round bugs, recoverable by running /code-review alongside.
- Ruling: review memory lives in PR marker comments, never in a ledger file — no repo state, git-only principle — cost if wrong: local range reviews have REVIEW.md as their only memory.
- Ruling: worklog stores no commit SHAs; task ids go in commit subjects — rebases and squashes cannot break stored references — cost if wrong: commits made without the id are invisible to `git log --grep`.
- Ruling: decision-log generated skill uses `paths:` for file-driven loading and the plugin skill's description for question-driven loading — the two retrieval paths cover both cases without an always-loaded file — cost if wrong: a question with no matching file open and no trigger phrase is missed; /why is the fallback.
- Ruling: implicit decision capture is propose-only — silent auto-capture failed ~50% in the surveyed trial — cost if wrong: decisions the user never confirms are lost.
- Ruling: Codex agents shipped as generated TOML under codex/agents/, not .codex/agents/ — a consumer-side directory would activate them whenever this repo is opened — cost if wrong: one extra copy step for Codex users.
- Ruling: no .codex-plugin/plugin.json — Codex reads .claude-plugin/plugin.json; only the display name is lost — cost if wrong: plain names in Codex's plugin list.

## Open questions
- Does `${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}` in hooks.json survive Claude Code's placeholder substitution in every version? (validates; runtime untested here)
- Does Copilot scan `commands/` without the explicit `commands` field? (field added regardless)

## Log
### 2026-09-02-3
- done: T08 — seven API commits replayed onto the remote branch; local branch reset to match
- surprises: the GitHub connector (OAuth as the user) could write while the session's git credential could not; the API drops executable bits, hence T08's bash-invoked hooks
- next: T09 acceptance; restore exec bits with `git update-index --chmod=+x` on the two scripts when pushing from a machine with git access

### 2026-09-02-2
- done: T11 — dry-run found 30+ issues; fixed: verifier output collision, no-arg diff excluding the working tree, schema path never given to agents, tests run before consent in address mode, duplicate-id grep comparing whole headings, seeded records vs the Rejected rule, resume mis-reporting fresh on an uncommitted file, `--grep` matching bodies
- surprises: the four earlier commits on this branch carry no task ids (the rule was written after they were made); from T11 on, commit subjects start with the id
- next: T08 (push, blocked on GitHub App access), then T09 acceptance

### 2026-09-02
- done: T01–T07; four commits on the branch
- surprises: `when_to_use:` frontmatter must not start with a quoted fragment (YAML parse error drops all metadata silently); hook JSON broke on embedded double quotes; marketplace.json still carried repo-mapper's pre-redesign description
- tried: push → 403, GitHub App not installed for the repo
- next: T08 once access is granted, then T09
