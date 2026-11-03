#!/usr/bin/env bash
# Switches this session's flow off, for /dev-flow:clear-flow: removes its pointer
# files (current, planning, finished) from <project>/.claude/flow and, once no
# pointer is left there, the hooks' marker files. Task folders and plan.md are
# never touched: the task keeps its status, and /dev-flow:load-flow (or the
# stage's skill) brings it back. Run from the Bash tool, where Claude Code sets
# CLAUDE_CODE_SESSION_ID: a pointer of another session is kept and named, unless
# `all` is given (for the leftover of a session that is gone; the flow in a
# session that is still running then loses its guards from here on).
#
#   bash flow-clear.sh [all]
#
# A pointer with no session line (written by hand, or by dev-flow before 2.5.0)
# counts as this session's. Without a session id (an older Claude Code) every
# pointer does, as the hooks then cannot tell sessions apart either.
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
DEV_FLOW_INPUT='{}'
source "$HERE/../hooks/lib.sh"
SESSION_ID=${CLAUDE_CODE_SESSION_ID-}

all=0; [ "${1-}" = all ] && all=1
POINTER_NAMES="current planning finished"
find_flow_dir || { printf 'No pointer in .claude/flow at or above %s: no flow is active in this checkout, nothing to clear.\n' "$PWD"; exit 0; }

describe() {   # FOLDER -> "task folder F, status S" (or that the folder is gone)
  local folder
  folder=$(normalize_path "$1")
  if [ -d "$folder" ]; then printf 'task folder %s, status: %s' "$folder" "$(frontmatter_value status "$folder/plan.md")"
  else printf 'task folder %s (not a folder)' "${folder:-nothing}"; fi
}

removed=0; kept=0
for name in $POINTER_NAMES; do
  p="$FLOW_DIR/$name"
  [ -f "$p" ] || continue
  folder=$(head -n 1 "$p" | tr -d '\r')
  owner=$(pointer_owner "$p")
  if [ -z "$owner" ] || pointer_mine "$p"; then
    rm -f "$p"; removed=$((removed+1))
    printf 'removed %s (%s)\n' "$p" "$(describe "$folder")"
  elif [ $all = 1 ]; then
    rm -f "$p"; removed=$((removed+1))
    printf 'removed %s of session %s (%s): that session no longer runs this flow.\n' "$p" "$owner" "$(describe "$folder")"
  else
    kept=$((kept+1))
    printf 'kept %s: it belongs to another Claude Code session (%s; %s). To remove it too: /dev-flow:clear-flow all.\n' "$p" "$owner" "$(describe "$folder")"
  fi
done

if [ $kept = 0 ]; then
  rm -f "$FLOW_DIR/notified" "$FLOW_DIR/stale-notified" "$FLOW_DIR"/start-* "$FLOW_DIR"/snap-* "$FLOW_DIR"/.snap-* "$FLOW_DIR"/.cmp-* "$FLOW_DIR"/claim-* 2>/dev/null
  printf 'No pointer left in %s; the hooks'"'"' marker files are removed too.\n' "$FLOW_DIR"
fi
if [ $removed -gt 0 ]; then
  printf 'The dev-flow guards are off in this session. The task folders and their plan.md are untouched: /dev-flow:load-flow picks a task up again.\n'
else
  printf 'Nothing of this session'"'"'s to remove.\n'
fi
exit 0
