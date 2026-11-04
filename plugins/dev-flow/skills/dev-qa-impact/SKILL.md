---
name: dev-qa-impact
description: Use when the user wants a QA impact note for a branch, diff or PR ("/dev-qa-impact", "QA impact", "what should QA retest"). A fixed-template note for QA engineers who do not read code - what changed for users, which regression tests to run, what was built differently from the requirements. No plan file needed.
---

# QA Impact

Produce `qa-impact.md` with the `dev-flow:dev-qa-impact` agent. The note always follows `${CLAUDE_PLUGIN_ROOT}/skills/dev-qa-impact/qa-impact-template.md`: same headings, same tables, same order, so QA can read every note the same way. Folder layout and **Specs intake** are in `${CLAUDE_PLUGIN_ROOT}/skills/dev-implement/plan-format.md`.

Never edit source, commit, push, or post. Never update work items or log in on the user's behalf.

## Steps

1. **Folder:** use the given task folder, or create `YYYY-MM-DD-<branch>` in the plans location (project guidance, otherwise `.claude/plans/`). No `plan.md` needed.
2. **Base:** the plan's `base`, else the merge-base with the default branch, else the range the user gave.
3. **Specs:** if none are known, ask once: "Paste PRD/HLD sections or give a work item ID (or say none)." Save them per Specs intake. For a PR, offer to pull its linked work items (read-only). Without specs the note still lists regression tests; its requirements table then says no specs were provided.
4. **Run:** spawn `dev-flow:dev-qa-impact` with only the folder path, project root, `base` and spec paths. Add "include test scenarios" only if the user asked for them.
5. **Report:** the file path, the overall risk, the top 3 regression tests, and the number of differences from the requirements.
