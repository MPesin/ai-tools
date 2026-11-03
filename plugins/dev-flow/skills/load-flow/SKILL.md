---
name: load-flow
description: Use when the user wants to pick up an existing dev-flow task in this session — "/load-flow", "load the plan", "resume the task", "which plans do I have", "continue the flow from the plans folder" — with or without naming the task. Lists the task folders under the project's plans location with their status and which session holds them, lets the user choose, and hands the chosen task to the skill its status needs (dev-plan, dev-debug, dev-implement, dev-qa-impact).
---

# Load flow

Make an existing task the one this session works on, and continue it with the right skill. This skill writes nothing itself: the skill it hands over to writes the pointer, and the hooks stamp it for this session (`${CLAUDE_PLUGIN_ROOT}/skills/dev-implement/plan-format.md`, Pointer files).

## 1. List

Read the project's own guidance first (CLAUDE.md, AGENTS.md, README): when it names a plans location, pass it; otherwise the default `.claude/plans/` applies.

- With an argument that names a task folder or a `plan.md`: use that task and skip the list.
- Otherwise run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/flow-list.sh" [<plans location>]` (add `all` when the user wants finished tasks too) and show its table as it is: folder, task, status, source, mode, review round, and the pointer column (which pointer names the task, and whether it is this session's, another session's, or unclaimed).
- Ask once which task to load (by number or name). With exactly one candidate, propose it and ask for a yes.

## 2. Check the pointers before handing over

A checkout runs one flow at a time, and a flow belongs to the session that wrote its pointer. From the pointer column:

- The chosen task's pointer is this session's, or there is none: go on.
- The chosen task's pointer belongs to another session: say so and ask before going on. Loading it here hands the flow to this session; the other session's run then loses its guards and cannot spawn further stage agents, though agents it already has running are not stopped. If the user is unsure whether that session is still open, they check before answering.
- Another task's pointer belongs to this session: ask whether to clear it first (`/dev-flow:clear-flow`), since loading a second task would replace it.
- Another task's pointer belongs to another session: say that this checkout is in use by that session for that task. Two flows in one working tree share its files and its git index, which the flow does not support; the user either waits, clears that flow (`/dev-flow:clear-flow all`, when that session is gone), or runs this task in a git worktree.

## 3. Hand over by status

Read `status` from the chosen task's `plan.md` and invoke the skill, with the task folder or plan path as its argument:

| `status` | Invoke |
|---|---|
| `draft` | `dev-flow:dev-plan <task folder>` (it resumes the plan and writes the `planning` pointer again) |
| `diagnosing` | `dev-debug:dev-debug <task folder>` (the dev-debug plugin; it shows the diagnosis gate again) |
| `approved`, `implementing`, `reviewing`, `human-review`, `qa-impact`, `blocked` | `dev-flow:dev-implement <plan path>` (its Intake writes `current` and resumes from `status` and `review_round`; at `blocked` it stops for the user's decision) |
| `done` | nothing to resume: say so, and offer `/dev-flow:dev-qa-impact <task folder>` when `qa-impact.md` is missing |
| none or unknown | show the frontmatter and ask; a `plan.md` that does not follow the plan format is validated by `dev-implement` Intake |

Never write a pointer, edit `plan.md`, spawn a stage agent, commit, push or post from this skill.
