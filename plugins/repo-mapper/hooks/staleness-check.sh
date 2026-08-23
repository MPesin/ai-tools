#!/bin/bash
# repo-mapper staleness check — SessionStart(startup) hook.
# Zero stored state: everything is derived from git. Fail-silent everywhere.
exec 2>/dev/null

SKILL_DIR=".claude/skills/repo-guide"
[ -f "$SKILL_DIR/SKILL.md" ] || exit 0
git rev-parse --is-inside-work-tree >/dev/null || exit 0

# Generation point = last commit that touched the skill folder.
STAMP=$(git log -1 --format=%H -- "$SKILL_DIR")
[ -n "$STAMP" ] || exit 0   # index never committed — nothing derivable, stay silent

N=$(git rev-list --count "$STAMP..HEAD")
THRESHOLD="${REPO_MAPPER_STALE_THRESHOLD:-20}"
[ "$N" -ge "$THRESHOLD" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"repo-mapper: the repo index (.claude/skills/repo-guide) is %s commits old — consider /repo-map refresh."}}\n' "$N"
exit 0
