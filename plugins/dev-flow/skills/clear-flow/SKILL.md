---
name: clear-flow
description: Use when the user wants the dev-flow guards switched off or the active dev-flow task dropped in this session — "/clear-flow", "clear the flow", "stop the flow", "turn the guards off", "the flow is stuck", "remove the leftover pointer". Removes this session's pointer files only; the task folder and plan.md stay, so /dev-flow:load-flow brings the task back. Not for clearing the conversation (that is the built-in /clear), and not the way to push, open a PR or finish a run: the main session pushes and opens the PR on request while the flow is active, and QA impact finishes the run.
---

# Clear flow

Switch this session's flow off. The flow is the pointer files in `<project>/.claude/flow/` (`current`, `planning`, `finished`; format in `${CLAUDE_PLUGIN_ROOT}/skills/dev-implement/plan-format.md`); the task folder and its `plan.md` are the record of the task and stay as they are.

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/flow-clear.sh"` and show its output. It removes the pointers that belong to this session (or to no session), and the hooks' marker files once no pointer is left. A pointer of another Claude Code session is kept and named.
2. When it kept another session's pointer and the user wants that one gone too (the session is closed, or the user says so), ask once, then run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/flow-clear.sh" all`. Say what that means: the flow in that session loses its guards from then on and cannot spawn further stage agents (agents it already has running stay guarded until they stop).
3. End with one line: the guards are off in this session; the task (folder and `status`) is untouched; `/dev-flow:load-flow` or the stage's own skill (`/dev-flow:dev-implement <plan path>`, `/dev-flow:dev-plan <task folder>`, `/dev-debug:dev-debug <task folder>`) resumes it.

Never delete a task folder, never edit `plan.md`, never commit, push or post. Deleting the pointer is all this skill does; the stage agents cannot be spawned until a skill writes `current` again.
