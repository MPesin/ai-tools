#!/usr/bin/env bash
# The task folders of this checkout, for /dev-flow:load-flow: a markdown table,
# newest first, with what the pointer files say about each. Run from the Bash
# tool, where Claude Code sets CLAUDE_CODE_SESSION_ID: that is what tells this
# session's pointer from another session's.
#
#   bash flow-list.sh [PLANS_DIR] [all]
#
# PLANS_DIR defaults to <git root>/.claude/plans; give the project's plans
# location when its guidance names another. A task at status done is listed
# only with `all`. The pointer column reads current|planning|finished with the
# session that holds it (this session, session <id>, or unclaimed), or - when
# no pointer names the folder.
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
DEV_FLOW_INPUT='{}'
source "$HERE/../hooks/lib.sh"
SESSION_ID=${CLAUDE_CODE_SESSION_ID-}

show_all=0
plans=''
for arg in "$@"; do
  case $arg in all) show_all=1 ;; *) plans=$arg ;; esac
done
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
plans=$(normalize_path "${plans:-$root/.claude/plans}")
[ -d "$plans" ] || { printf 'No plans folder at %s (nothing to load; /dev-flow:dev-plan or /dev-debug:dev-debug starts a task).\n' "$plans"; exit 0; }

# pointer_of FOLDER -> "<name> (<holder>)" for the pointer naming FOLDER, or -
POINTER_NAMES="current planning finished"
pointer_of() {
  local name p owner
  [ -n "${FLOW_DIR-}" ] || { printf -- '-'; return; }
  for name in $POINTER_NAMES; do
    p="$FLOW_DIR/$name"
    [ -f "$p" ] || continue
    [ "$(path_key "$(head -n 1 "$p" | tr -d '\r')")" = "$(path_key "$1")" ] || continue
    owner=$(pointer_owner "$p")
    if [ -z "$owner" ]; then printf '%s (unclaimed)' "$name"
    elif [ -n "$SESSION_ID" ] && [ "$owner" = "$SESSION_ID" ]; then printf '%s (this session)' "$name"
    else printf '%s (session %s)' "$name" "$owner"; fi
    return
  done
  printf -- '-'
}
find_flow_dir || FLOW_DIR=''

cell() { printf '%s' "$1" | tr -d '\r' | sed 's/|/\\|/g'; }

printf '| # | folder | task | status | source | mode | round | pointer |\n|---|---|---|---|---|---|---|---|\n'
n=0; hidden=0
for dir in $(ls -1d "$plans"/*/ 2>/dev/null | sort -r); do
  dir=${dir%/}
  [ -f "$dir/plan.md" ] || continue
  status=$(frontmatter_value status "$dir/plan.md")
  if [ "$status" = done ] && [ $show_all = 0 ]; then hidden=$((hidden+1)); continue; fi
  n=$((n+1))
  printf '| %d | %s | %s | %s | %s | %s | %s | %s |\n' "$n" "$(cell "${dir##*/}")" "$(cell "$(frontmatter_value task "$dir/plan.md")")" \
    "$(cell "${status:-none}")" "$(cell "$(frontmatter_value source "$dir/plan.md")")" "$(cell "$(frontmatter_value mode "$dir/plan.md")")" \
    "$(cell "$(frontmatter_value review_round "$dir/plan.md")")" "$(pointer_of "$dir")"
done
[ $n -gt 0 ] || printf '| - | (no task folders with a plan.md) | | | | | | |\n'
printf '\nplans: %s\n' "$plans"
[ $hidden -gt 0 ] && printf '%d finished task(s) hidden; add `all` to list them.\n' "$hidden"
[ -n "$FLOW_DIR" ] && printf 'pointers: %s\n' "$FLOW_DIR"
[ -n "$SESSION_ID" ] && printf 'this session: %s\n' "$SESSION_ID"
exit 0
