---
name: dev-debug
description: Use when the user has a bug to find and fix in any project — "/dev-debug", "debug this", "find why X fails", "fix this bug", a pasted stack trace, a failing test, a bug work item. A clean-slate debugger subagent reproduces the bug and writes a diagnosis with evidence; the user confirms the root cause; the diagnosis becomes an approved fix plan (regression test first) handed to /dev-flow:dev-implement when the dev-flow plugin is installed. Can stop at the diagnosis. Not for features or planned changes: those start at /dev-flow:dev-plan.
---

# Dev Debug

Find the cause of a bug before anyone changes code, then hand the fix to the implementation flow. Debugging runs in a `dev-debug:dev-debugger` subagent that writes `diagnosis.md`; the task folder, the specs intake, the diagnosis headings, the fix plan contract and the pointer file are all defined in `${CLAUDE_PLUGIN_ROOT}/skills/dev-debug/diagnosis-format.md` (read it first). The main session orchestrates; subagents cannot ask the user questions.

## Hard rules

- Never edit source from this skill, and never fix by hand "because it is obvious": the fix goes through the plan and `/dev-flow:dev-implement`, so it gets a regression test, a review and a QA note. The only files you write are in the task folder and `.claude/flow/planning`. While that pointer exists and the `dev-flow` plugin is installed, its hooks refuse every other write from the main session and block commit, push and posting.
- Never commit, push, or post anywhere. Never update the work item.
- Read the project's own guidance first (CLAUDE.md, AGENTS.md, README, instruction files); project rules override this skill. Check the project's plans location for an existing task folder on the same bug ID before creating one.
- The root cause is confirmed by an explicit user reply, and so is the fix plan. Never set `status: approved` without one.
- Prompts to the debugger carry task data and paths only. Do not pass it your own or the reporter's theory as a conclusion: a theory is saved in the bug report file, where the debugger reads it as a hypothesis.

## 1. Start

1. Create the task folder `YYYY-MM-DD-<bug-id-or-topic>` in the plans location and write its absolute path as the only line of `<project>/.claude/flow/planning` (create the directory).
2. Ask once, in one message: "Paste the bug report, stack trace, failing test name or log excerpt, or give a work item ID. If you know them, add: how to reproduce, the environment, and the last version or commit where it worked." Save everything per **Specs intake** in `diagnosis-format.md`. If the user gave the material in the message that started the skill, use that; do not ask again. The user can add material later; append it the same way.
3. Set `base` to the merge-base with the default branch. Write `plan.md` with the frontmatter from `diagnosis-format.md` (`task`, `source: dev-debug`, `status: diagnosing`, `review_round: 0`, `specs:`, `base`), `## Context` holding the bug in one paragraph, and the other required headings with `Pending diagnosis.` Writing it now is what lets the dev-flow hooks and the dev-flow-panel show the Diagnosing stage and notify you at the gate.

## 2. Diagnose (`dev-debugger`)

Spawn `dev-debug:dev-debugger` with only the task folder path, the project root, `base` and `specs:`. It reproduces the bug, tests hypotheses, and writes `diagnosis.md` (and reproduction scripts under `debug/`). It returns the path, the confidence, whether it reproduced, and the one-sentence root cause. After it returns, check `violations.md` in the task folder; if it exists and gained lines, show them and stop.

If the debugger reports that the bug did not reproduce, the gate below still runs: the user may know the missing input.

## 3. Diagnosis gate

Read `diagnosis.md` and show, in a few lines each: the symptom, whether it reproduced and how, the root cause with its `file:line`, the confidence, the blast radius, the proposed fix steps and the regression test, and the open questions. Then stop and wait. Offer these replies:

- **`fix`** (or "fix it", "go ahead"): confirms the root cause and approves the fix plan built from the diagnosis as shown. Continue with **4** and **5** in the same turn.
- **`fix, and ...`**: the same, with changes to the plan (another site to cover, a different test location). Apply them to the plan in **4**, show them in a few lines, then continue with **5**.
- **More information or a disagreement** ("it also happens when ...", "that is not it"): append the new facts to the bug report file in `specs/`, then continue the same debugger via SendMessage, or spawn a fresh one pointed at the existing `diagnosis.md` to revise it. Show the gate again.
- **`second opinion`**: spawn a fresh `dev-debug:dev-debugger` with the same inputs, the output file name `diagnosis-2.md`, and nothing about the first diagnosis. Show where the two agree and disagree. Offer this yourself when the confidence is below High or the user doubts the cause.
- **`diagnosis only`**: stop here. Set `status: done`, delete `.claude/flow/planning`, and print the path of `diagnosis.md`. Say that `/dev-debug:dev-debug <task folder>` resumes it later to plan the fix.

Status stays `diagnosing` until the user replies; with dev-flow installed, its Stop hook notifies them.

## 4. Plan the fix

On `fix`, rewrite `plan.md` from `diagnosis.md` with the mapping table in `diagnosis-format.md`: `status: draft`, one sequential package (no `###` package headings), the regression test as step 1, run before the fix with its failing output appended to `verify.log`; the fix steps next, root cause first and then each blast-radius site; verification last: the regression test passes, the reproduction command no longer reproduces, the affected test scope passes. Each step names exact paths and its own minimal build/test command. Keep the Open questions the diagnosis left and the user did not answer; if one of them changes what the fix is, ask it before writing the plan instead of deciding for the user.

Set `mode` by the lite criteria in `diagnosis-format.md`. The plan critic is skipped by default in this skill: the user has just confirmed a diagnosis carrying its own evidence. When the user asks for it, or a fix step changes a public contract, a schema or persisted data, and the `dev-flow` plugin is installed, spawn `dev-flow:dev-plan-critic` (plan path, project root, `specs:`) and show the counts and the Blocking items before approval.

## 5. Approve and hand over

The `fix` reply approved the plan as shown. In the same turn:

1. Set `status: approved` in `plan.md` and leave `mode` as set.
2. Delete `<project>/.claude/flow/planning`.
3. If the `dev-flow` plugin is installed, invoke the `dev-flow:dev-implement` skill with the plan path. Its Intake writes `.claude/flow/current` and its Implement stage sets `status: implementing` before spawning the implementer, which writes the failing regression test first, then the fix; the review loop, the user's review, human findings and the QA note follow as for any plan. If `dev-flow` is not installed, print the plan path and say that `/dev-flow:dev-implement <plan path>` runs it once `dev-flow` is installed from the same marketplace, or that the plan can be implemented by hand.

Never spawn an implementer or edit source from this skill. With dev-flow installed, its hooks refuse to spawn a stage agent while the `planning` pointer exists or while `status` is not that stage's own.

## Resuming and exits

- `/dev-debug:dev-debug <task folder>` with an existing `diagnosis.md`: show the gate (**3**) again and continue from there; write the `planning` pointer first if it is missing.
- If the user abandons the task, delete `.claude/flow/planning`. It must be removed on every exit path.
- A bug whose cause is already known and confirmed does not need this skill: `/dev-flow:dev-plan` plans the fix directly.
