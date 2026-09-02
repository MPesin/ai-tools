#!/bin/bash
# worklog — SessionStart(startup|clear|compact) hook.
# Lists active work items with their next action. Everything is derived from
# the files and git; nothing is stored. Fail-silent, one line per item.
exec 2>/dev/null

DIR="docs/work"
[ -d "$DIR" ] || exit 0
IN_GIT=0
git rev-parse --is-inside-work-tree >/dev/null && IN_GIT=1
THRESHOLD="${WORKLOG_STALE_THRESHOLD:-50}"

OUT=""
for f in "$DIR"/*.md; do
  [ -f "$f" ] || continue
  grep -q '^Status: active' "$f" || continue
  SLUG=$(basename "$f" .md)
  NEXT=$(grep -m1 '^Next action:' "$f" | sed 's/^Next action:[[:space:]]*//' | tr -d '"\\\000-\037')
  LINE="worklog: active $SLUG — next: ${NEXT:-(none recorded)}."
  if [ "$IN_GIT" = 1 ]; then
    STAMP=$(git log -1 --format=%H -- "$f")
    if [ -n "$STAMP" ]; then
      N=$(git rev-list --count "$STAMP..HEAD")
      [ "$N" -gt 0 ] && LINE="$LINE $N commits since the file was last committed."
      [ "$N" -ge "$THRESHOLD" ] && LINE="$LINE Looks abandoned — consider /work done or Status: paused."
    fi
  fi
  LINE="$LINE Run /work resume $SLUG."
  OUT="${OUT}${OUT:+ }$LINE"
done
[ -n "$OUT" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$OUT"
exit 0
