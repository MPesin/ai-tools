---
description: Generate or refresh a repo-guide skill (.claude/skills/repo-guide/) indexing this repo for AI agents — the /init replacement
argument-hint: "[refresh]"
---

Invoke the `repo-mapper` skill with the Skill tool and follow it exactly.

Mode argument: "$ARGUMENTS"
- empty → full mapping run
- `refresh` → incremental refresh of an existing index
