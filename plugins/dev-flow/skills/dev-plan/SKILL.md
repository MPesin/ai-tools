---
name: dev-plan
description: Use when the user wants to plan a task, bug, or work item before implementing it — "/dev-plan", "plan this task", "let's plan X together". Produces an approved plan in the standard format (interactive with the user, or drafted by a planner subagent), reviewed by a plan critic before approval. Never implements; hand the approved plan path to /dev-flow:dev-implement.
---

# Dev Plan

Produce a plan that satisfies `${CLAUDE_PLUGIN_ROOT}/skills/dev-implement/plan-format.md` (read it first; it defines the task folder, frontmatter, pointer files, work packages and required headings). End by setting `status: approved` and printing the plan path. This skill never implements anything.

## Hard rules

- Never edit source code. The only files you write are in the task folder and `.claude/flow/planning`. While the `planning` pointer exists the hooks refuse every other write from the main session.
- Never commit, push, or post anywhere.
- Read the project's own guidance (CLAUDE.md, AGENTS.md, README, instruction files) first; project rules override this skill. Check the project's plans/handoffs/notes locations for existing work on the task ID.
- Approval must be an explicit user reply. Set `status: approved` only then.

## Start

1. Create the task folder and write its absolute path as the only line of `<project>/.claude/flow/planning` (create the directory).
2. Ask once: "Paste the relevant PRD/HLD sections, or give a work item / ticket reference (or say none)." Save them per **Specs intake** in `plan-format.md` and list them in `specs:`. The user can add specs at any point; append them the same way.
3. Choose the mode.

## Choosing the mode

- **Interactive** if the user says "together", "discuss", or "back and forth", or the task is ambiguous.
- **Draft** if the user wants it done for them.
- Otherwise ask once: "Plan interactively with you, or have a planner subagent draft it?"

## Design for parallel subagents

Prefer plans that `dev-implement` can run in parallel subagents. Split the work into work packages as defined in `plan-format.md` (one-line comma-separated `Owns`, explicit `Depends on`, shared touchpoints in an early or final package, parallel-safe package-scoped verification). Say in the summary which packages form each wave. If the task is small or tightly coupled, write one sequential package and say why. Ask the user only when the split is a real design choice.

## Interactive mode

Main session only; no planner subagent.

1. Write `plan.md` early with `source: dev-plan-interactive`, `status: draft`, `review_round: 0`.
2. Explore the code yourself (use `Explore` for broad searches) and record verified facts with evidence.
3. Ask the user one or two questions at a time. Update `plan.md` as decisions are made; keep unresolved items under `## Open questions` in the file.

## Draft mode

1. Spawn `dev-flow:dev-planner` with only the task, the project root, the task folder path, and `specs:` (it designs work packages per `plan-format.md`). Tell it `source: dev-plan-draft`.
2. Show the user the returned summary and open questions.
3. If they want changes, continue the same planner via SendMessage, or spawn a fresh one pointed at the existing `plan.md`, and show the result again.

## Before approval

Unless the plan qualifies as lite (or the user forced lite), spawn a fresh `dev-flow:dev-plan-critic` with only the plan path, the project root, and `specs:`. Show the user the counts from `plan-critique.md` and its Blocking items. The user decides what to change; re-run the critic only if they ask.

## On explicit approval

1. Set `status: approved` and `mode` (lite criteria are in `plan-format.md`; the user can force either).
2. Delete `<project>/.claude/flow/planning`.
3. Print the absolute path of `plan.md` and tell the user to run `/dev-flow:dev-implement <plan path>`.

If the user abandons planning, delete `.claude/flow/planning` as well. It must be removed on every exit path.
