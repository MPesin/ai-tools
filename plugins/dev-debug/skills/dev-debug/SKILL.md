---
name: dev-debug
description: Use when the user has a bug to find and fix in any project — "/dev-debug", "debug this", "find why X fails", "fix this bug", a pasted stack trace, a failing test, a bug work item. A clean-slate debugger subagent reproduces the bug and writes a diagnosis with evidence; the user confirms the root cause; the diagnosis becomes an approved fix plan (regression test first) handed to /dev-flow:dev-implement when the dev-flow plugin is installed. Can stop at the diagnosis. Not for features or planned changes: those start at /dev-flow:dev-plan.
---

# Dev Debug

Find the cause of a bug before anyone changes code, then hand the fix to the implementation flow. Debugging runs in a `dev-debug:dev-debugger` subagent that writes `diagnosis.md`; the task folder, the specs intake, the diagnosis headings, the fix plan contract and the pointer file are all defined in `${CLAUDE_PLUGIN_ROOT}/skills/dev-debug/diagnosis-format.md` (read it first). The main session orchestrates; subagents cannot ask the user questions.

## Hard rules

- Never edit source from this skill, and never fix by hand "because it is obvious": the fix goes through the plan and `/dev-flow:dev-implement`, so it gets a regression test, a review and a QA note. The only files you write are in the task folder and `.claude/flow/<branch key>/planning`. While that pointer exists and the `dev-flow` plugin is installed, its hooks refuse every other write from the main session and block commit, push and posting.
- Never commit, push, or post anywhere. Never update the work item.
- Read the project's own guidance first (CLAUDE.md, AGENTS.md, README, instruction files); project rules override this skill. Check the project's plans location for an existing task folder on the same bug ID before creating one.
- The root cause is confirmed by an explicit user reply, and so is the fix plan. Never set `status: approved` without one.
- Prompts to the debugger carry task data and paths only. Do not pass it your own or the reporter's theory as a conclusion: a theory is saved in the bug report file, where the debugger reads it as a hypothesis.

## 1. Start

1. Check the branch: `git branch --show-current`. On `main` or `master` (or a detached HEAD) stop and ask the user to create a branch for the bug, suggesting a name from the bug id (`git checkout -b fix/<bug-id>`); do nothing else until they have. A flow lives on its branch, and the dev-flow hooks refuse a pointer and the stage agents on those branches. Then create the task folder `YYYY-MM-DD-<bug-id-or-topic>` in the plans location and write its absolute path as the only line of `<project>/.claude/flow/<branch key>/planning` (create the directories), where the branch key is the branch name with every `/` replaced by `__` (`fix/login` gives `fix__login`). Each branch keeps its own pointers, so a task parked on another branch is untouched and comes back when that branch is checked out again. In the same step, before asking anything, write `plan.md` with the frontmatter from `diagnosis-format.md` (`task`, `source: dev-debug`, `status: diagnosing`, `review_round: 0`, an empty `specs:`, `base` set to the merge-base with the default branch), `## Context` holding the bug in one paragraph from whatever the user has said so far, and the other required headings with `Pending diagnosis.` The dev-flow hooks and the dev-flow-panel read this file: without it the band shows Planning instead of Diagnosing.
2. Ask once, in one message: "Paste the bug report, stack trace, failing test name or log excerpt, or give a work item ID. If you know them, add: how to reproduce, the environment, and the last version or commit where it worked." Save everything per **Specs intake** in `diagnosis-format.md`. If the user gave the material in the message that started the skill, use that; do not ask again. The user can add material later; append it the same way.
3. Update `plan.md`: list the saved files in `specs:` and refine `## Context` from the report. The status stays `diagnosing`.

## 2. Diagnose (`dev-debugger`)

Spawn `dev-debug:dev-debugger` with only the task folder path, the project root, `base` and `specs:`. It reproduces the bug, tests hypotheses, and writes `diagnosis.md` (and reproduction scripts under `debug/`). It returns the path, the confidence, whether it reproduced, and the one-sentence root cause. After it returns, check `violations.md` in the task folder; if it exists and gained lines, show them and stop.

If the debugger reports that the bug did not reproduce, the gate below still runs: the user may know the missing input. If it reports that the cause is already changed on the branch (a commit after `base`, or an uncommitted change, at the root cause, and the reproduction passes at HEAD), say so at the gate with the commit and offer `already fixed`.

## 3. Diagnosis gate

Read `diagnosis.md` and show, in a few lines each: the symptom, whether it reproduced and how, the root cause with its `file:line`, the confidence, the blast radius, the proposed fix steps and the regression test, and the open questions. Then stop and wait. Offer these replies:

- **`fix`** (or "fix it", "go ahead"): confirms the root cause and approves the fix plan built from the diagnosis as shown. Continue with **4** and **5** in the same turn.
- **`fix, and ...`**: the same, with changes to the plan (another site to cover, a different test location). Apply them to the plan in **4**, show them in a few lines, then continue with **5**.
- **More information or a disagreement** ("it also happens when ...", "that is not it"): append the new facts to the bug report file in `specs/`, then continue the same debugger via SendMessage, or spawn a fresh one pointed at the existing `diagnosis.md` to revise it. Show the gate again.
- **`second opinion`**: spawn a fresh `dev-debug:dev-debugger` with the same inputs, the output file name `diagnosis-2.md`, and nothing about the first diagnosis. Show where the two agree and disagree. Offer this yourself when the confidence is below High or the user doubts the cause.
- **`diagnosis only`**: stop here. Set `status: done`, delete `.claude/flow/<branch key>/planning`, and print the path of `diagnosis.md`. Say that `/dev-debug:dev-debug <task folder>` resumes it later to plan the fix.
- **`already fixed`** (the user fixed it by hand, or the fix is already on the branch): there is nothing to implement, so no fix plan. Record under `## Context` in `plan.md` the commit (hash and subject) or the uncommitted change that carries the fix, and that the reproduction passes with it. Set `status: done`, delete `.claude/flow/<branch key>/planning`, and print the path of `diagnosis.md`. The change still lacks what the flow would have given it: say that `/dev-flow:dev-qa-impact <task folder>` writes the QA note from the branch, and that the regression test from `diagnosis.md` can be planned with `/dev-flow:dev-plan` (the cause is confirmed). Do not hand the commit to `/dev-flow:dev-implement`: its Intake starts at Implement, where the regression test would pass before any fix and stop the run.

Status stays `diagnosing` until the user replies; with dev-flow installed, its Stop hook notifies them.

## 4. Plan the fix

On `fix`, rewrite `plan.md` from `diagnosis.md` with the mapping table in `diagnosis-format.md`: `status: draft`, one sequential package (no `###` package headings), the regression test as step 1, run before the fix with its failing output appended to `verify.log`; the fix steps next, root cause first and then each blast-radius site; verification last: the regression test passes, the reproduction command no longer reproduces, the affected test scope passes. Each step names exact paths and its own minimal build/test command. Keep the Open questions the diagnosis left and the user did not answer; if one of them changes what the fix is, ask it before writing the plan instead of deciding for the user.

Set `mode` by the lite criteria in `diagnosis-format.md`. The plan critic is skipped by default in this skill: the user has just confirmed a diagnosis carrying its own evidence. When the user asks for it, or a fix step changes a public contract, a schema or persisted data, and the `dev-flow` plugin is installed, spawn `dev-flow:dev-plan-critic` (plan path, project root, `specs:`) and show the counts and the Blocking items before approval.

## 5. Approve and hand over

The `fix` reply approved the plan as shown. In the same turn:

1. Set `status: approved` in `plan.md` and leave `mode` as set.
2. Delete `<project>/.claude/flow/<branch key>/planning`.
3. If the `dev-flow` plugin is installed, invoke the `dev-flow:dev-implement` skill with the plan path. Its Intake writes `.claude/flow/<branch key>/current` and its Implement stage sets `status: implementing` before spawning the implementer, which writes the failing regression test first, then the fix; the review loop, the user's review, human findings and the QA note follow as for any plan. If `dev-flow` is not installed, print the plan path and say that `/dev-flow:dev-implement <plan path>` runs it once `dev-flow` is installed from the same marketplace, or that the plan can be implemented by hand.

Never spawn an implementer or edit source from this skill. With dev-flow installed, its hooks refuse to spawn a stage agent while the `planning` pointer exists or while `status` is not that stage's own.

## Resuming

- `/dev-debug:dev-debug <task folder>` with an existing `diagnosis.md`: show the gate (**3**) again and continue from there; write the `planning` pointer first if it is missing.
- A bug whose cause is already known and confirmed does not need this skill: `/dev-flow:dev-plan` plans the fix directly.

## Exits: the pointer checklist

`<project>/.claude/flow/<branch key>/planning` belongs to `status: diagnosing` and `status: draft` only. Every exit of this skill ends with its deletion; a pointer left behind at a later status makes the dev-flow hooks report it as stale (they stop enforcing it, and the Stop hook removes it), but the skill does not rely on that. The terminal states, each with the pointer step spelled out:

1. `fix`: `status: approved`, **delete the pointer**, invoke `dev-flow:dev-implement` (**5**).
2. `diagnosis only`: `status: done`, **delete the pointer**, print the diagnosis path (**3**).
3. `already fixed`: note the commit in `plan.md`, `status: done`, **delete the pointer**, print the diagnosis path (**3**).
4. Abandoned (the user drops the task, or the debugger cannot proceed and the user does not continue): leave `status` as it is, **delete the pointer**.
