---
name: dev-implement
description: Use when the user wants to implement an approved plan and take it through review in any project — Implement, Claude code review, fix findings, human code review, fix human findings, QA impact — with each Claude stage run by a subagent. Starts from an approved plan path produced by /dev-flow:dev-plan or written by hand. Trigger on "/dev-implement", "implement this plan", "run the dev flow", "implement and review this plan".
---

# Dev Implement

Orchestrate from the main session. Each Claude stage runs in its own subagent; the human gates are you stopping and waiting for the user. Subagents cannot ask the user questions or spawn subagents, so the main session owns coordination.

State between stages is files in the task folder, never chat summaries. Plan structure, folder layout, pointer files, lite criteria and work packages are defined in `${CLAUDE_PLUGIN_ROOT}/skills/dev-implement/plan-format.md`.

## Rules

- Work in the current project. Do not assume a language, framework, repo layout, or hosting platform; discover them.
- Never commit, push, or post to a PR/review system in any stage. The user does that.
- Hard rules live in the agent files. Spawn agents by their plugin-scoped names: `dev-flow:dev-implementer`, `dev-flow:dev-reviewer`, `dev-flow:dev-fixer`, `dev-flow:dev-review-triager`, `dev-flow:dev-planner`, `dev-flow:dev-qa-impact`. Prompts carry only task data and paths. If an agent is missing, fall back to `general-purpose` and paste that agent's rules into the prompt, and tell the user the hooks cannot then tell it apart from the main session. Do not use a review tool tied to a different hosting platform than the project uses.
- Update `status` (and `review_round`) in `plan.md` frontmatter at every stage transition, before spawning the stage's agent. The hooks and the status panel read them, and the guard refuses to spawn an agent at the wrong status: `dev-implementer` needs `implementing`, `dev-reviewer` `reviewing`, `dev-fixer` `reviewing` or `human-review`, `dev-review-triager` `human-review`, `dev-qa-impact` `qa-impact` (or `human-review`). None of them can be spawned while `.claude/flow/planning` exists or no pointer exists at all.
- Do not advance past a human gate without an explicit user reply.
- Never run subagents with `isolation: "worktree"`: a subagent worktree starts from the default branch without the uncommitted changes of earlier waves, and nothing merges it back. All work happens in the one working tree.
- After every subagent returns, check `violations.md` in the task folder. If it gained lines, show them to the user and stop; the user decides whether to keep or revert those changes.
- The hooks: while `<project>/.claude/flow/current` exists, the plugin blocks commit/push/discard, posting and publishing (Bash, PowerShell and MCP tools), limits what each agent may write, refuses to let an implementer or fixer finish without this run's build/test output in `verify.log`, compares the working tree before and after each read-only agent, and notifies the user at the gates. If a guard blocks the main session wrongly, the user can delete the pointer file.

## Stages

### 1. Intake

Input is a plan path or task folder, or a PR/review reference (which jumps to stage 5). Run Intake in full every time, including when `/dev-flow:dev-plan` hands over in the same turn because the user approved and asked to implement in one reply.

- A bare task description: ask once whether to run `/dev-flow:dev-plan` in draft mode first; otherwise tell the user to run it.
- Validate `plan.md` against `plan-format.md`. If `source: manual` has gaps, list them, then either ask the user to fill them or, if they agree, spawn `dev-planner` in harden mode (adds paths, verification, and facts without changing decisions). The user re-approves.
- Require `status: approved` (or a later status when resuming).
- Set `mode` from the lite criteria unless the user forced one. Set `base` to the merge-base with the default branch if it is empty.
- Create missing folder files (`notes.md`) and write the absolute task folder path as the only line of `<project>/.claude/flow/current` (create the directory). From here on the hooks are active.
- Resume: continue from the frontmatter's `status` and `review_round`.

### 2. Implement (`dev-implementer`)

Set `status: implementing` in `plan.md` before the first Agent call; the guard refuses to spawn `dev-implementer` at any other status.

If the plan has work packages, run them in waves: all packages whose dependencies are done start together as parallel `dev-implementer` subagents (several Agent calls in one message). Each prompt contains only the task folder path, project root, plan path, and its package id. The hooks hand each implementer the path of its claim file at start and refuse edits outside its package's `Owns`; you pass nothing else. Wait for the whole wave before starting the next. After each wave read the `[Pn]` lines in `notes.md`, tick the matching `- [x]` boxes in `plan.md` yourself, check `violations.md`, and stop on any package that reported a blocked step or a file it does not own. The `Integration` package runs last, alone.

Plans without packages run as one implementer whose prompt contains only the task folder path, project root and plan path. It ticks `plan.md` itself.

The implementer takes a test baseline first, implements, runs the project's build and test commands and appends them with their raw output to `verify.log`, and writes discrepancies to `notes.md`.

### 3. Review/fix loop (`dev-reviewer`, `dev-fixer`)

Set `status: reviewing`. Rounds alternate review → fix → review; the loop always ends on a review, never on an unreviewed fix.

1. Increment `review_round` to N and spawn a brand-new `dev-reviewer`; never resume one. Give it only the task description, the task folder path, and the file path `review-N.md`. Do not pass implementer output, changed-file lists, results, or previous findings. It writes `review-N.md` (findings F1, F2, ... with severity and file:line) and returns only the path and counts.
2. Read `review-N.md`. A finding is *previously disputed* when `notes.md` holds a `DISPUTED` line from the fixer for the same file within a few lines, or for the same issue, from an earlier round. Append those to `needs-decision.md` in the task folder (the notify hook alerts the user) and leave them out of the fix list.
3. If no Critical/Major/Mid findings remain to fix, go to stage 4.
4. If the number of fix rounds so far equals the cap (3 in full mode, 1 in lite mode), set `status: blocked`, report the open findings, and stop.
5. Spawn `dev-fixer` with the `review-N.md` path and the IDs to fix. It fixes them, or disputes them with evidence in `notes.md`, and returns per-ID outcomes. Go to 1.
6. Low findings are listed for the user, not fixed.

### 4. Human review (gate)

Set `status: human-review`. Report changed files, the `verify.log` tail, the round count, Low findings, and disputed findings. Offer a PR description and commit message drafted from `plan.md` and the diff (text only; never commit). Stop. The notify hook alerts the user.

### 5. Fix human findings (`dev-review-triager`, then `dev-fixer`)

1. `dev-review-triager` fetches unresolved comments (PR reference) with the session's read-only tools for the project's hosting platform, or uses pasted comments, and writes `human-review.md`: each item `fix` or `reply-only` with reasons, draft replies, and a `## Proposed checklist additions` section. It never posts.
2. `dev-fixer` gets the `human-review.md` path and applies the `fix` items.
3. Show the proposed checklist additions and append only the ones the user confirms to the project's `review-checklist.md` (the location named in project guidance, otherwise `.claude/review-checklist.md`).

Report the fixes and the draft replies. The user commits, pushes, and replies.

### 6. QA impact (`dev-qa-impact`)

The last stage that writes, so it describes the final code. Set `status: qa-impact`. Spawn `dev-qa-impact` with the task folder path, project root, `base`, and `specs:`. It fills the fixed template in `${CLAUDE_PLUGIN_ROOT}/skills/dev-qa-impact/qa-impact-template.md`. Show its overall risk, the top regression tests and the number of differences from the requirements, then the path to `qa-impact.md`. If code changes after this point, re-run it.

## Final report

Show the task folder path, a per-stage summary, the evidence quoted from `verify.log`, unresolved items, and the next human action. Set `status: done` and rename `<project>/.claude/flow/current` to `<project>/.claude/flow/finished` (the Stop hook sends the "done" notification and removes it together with the run's marker files).
