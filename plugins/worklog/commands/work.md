---
description: Manage a multi-session work item in docs/work/ — start one from a plan, resume ledger-first, log the session, mark it done, or list active items
argument-hint: "[start <slug or description> | resume [slug] | log [note] | done [slug] | list]"
disable-model-invocation: true
---

Invoke the `worklog` skill with the Skill tool and follow it exactly.

Arguments: "$ARGUMENTS" (empty → `resume` when exactly one item is active,
else `list`).
