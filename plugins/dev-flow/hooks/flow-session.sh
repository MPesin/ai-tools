#!/usr/bin/env bash
# SessionStart (startup, resume, clear, compact): when a flow of this session is
# active, put its state back into context so a resumed, cleared or compacted
# session knows the task folder, the stage and how to continue, and warn when the
# pointer looks abandoned. A stale planning pointer (plan past draft/diagnosing,
# or its folder gone) is reported as such. A pointer of another session, or one
# no session has claimed, is named with what it would take to run that flow here.
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
[ -f "$HERE/lib.sh" ] || HERE="${CLAUDE_PLUGIN_ROOT}/hooks"
source "$HERE/lib.sh"
HOOK_EVENT=SessionStart
load_task_folder "planning current"

# The skill that continues a task from its pointer; it writes the pointer again,
# which is how a session takes a flow over.
resume_skill() {   # POINTER_NAME TASK_FOLDER
  if [ "$1" = planning ] && [ "$(frontmatter_value source "$2/plan.md")" = dev-debug ]; then
    printf '/dev-debug:dev-debug %s' "$2"
  elif [ "$1" = planning ]; then
    printf '/dev-flow:dev-plan (continue the plan in %s)' "$2"
  else
    printf '/dev-flow:dev-implement %s/plan.md' "$2"
  fi
}

# The other pointer beside this session's, when another session owns it.
other_session_note() {   # NAME
  local p="$FLOW_DIR/$1" folder
  [ -f "$p" ] && ! pointer_mine "$p" || return 0
  folder=$(normalize_path "$(head -n 1 "$p" | tr -d '\r')")
  printf ' %s: task folder %s at status: %s; the two sessions do not guard or interrupt each other, and that task is not yours to touch.' \
    "$(foreign_notice "$p")" "$folder" "$(frontmatter_value status "$folder/plan.md")"
}

if [ "$POINTER_MINE" != 1 ]; then
  status=$(frontmatter_value status "$TASK_FOLDER/plan.md")
  msg="dev-flow: $(foreign_notice "$POINTER"): task folder $TASK_FOLDER, status: ${status:-unknown}. Its guards and notifications do not apply to this session, and this session cannot spawn its stage agents. Leave that task alone unless the user asks for it. To run that flow from this session: $(resume_skill "$POINTER_NAME" "$TASK_FOLDER"); the skill writes the pointer again, which hands the flow to this session and ends it in the other one. To clear a leftover: rm \"$POINTER\"."
  emit_context SessionStart "$msg"
  exit 0
fi

status=$(frontmatter_value status)
if [ "$POINTER_NAME" = planning ] && [ "$(frontmatter_value source)" = dev-debug ]; then
  next="Debugging is in progress: continue with /dev-debug:dev-debug $TASK_FOLDER (it shows the diagnosis gate again when diagnosis.md exists), or delete $POINTER to abandon it."
elif [ "$POINTER_NAME" = planning ]; then
  next="Planning is in progress: continue with /dev-flow:dev-plan, or delete $POINTER to abandon it."
elif [ "$status" = done ]; then
  next="The run is finished; the Stop hook removes $POINTER at the end of the turn."
else
  next="Continue with /dev-flow:dev-implement $TASK_FOLDER/plan.md (it resumes from status and review_round)."
fi
msg="dev-flow: a flow of this session is active in this project. Task folder: $TASK_FOLDER. status: ${status:-unknown}. mode: $(frontmatter_value mode). review_round: $(frontmatter_value review_round). base: $(frontmatter_value base). $next While the pointer exists the plugin's hooks block git push/discard, commits from subagents and --amend, posting and publishing, and limit what each agent may write (the main session commits each stage's files), in this session and its subagents only; delete $POINTER to switch them off (stage agents then cannot be spawned until Intake writes it again)."
[ -s "$TASK_FOLDER/needs-decision.md" ] && msg="$msg needs-decision.md has items waiting for the user."
[ -s "$TASK_FOLDER/violations.md" ] && msg="$msg violations.md lists files changed outside an agent's allowance."
[ -n "$(find "$POINTER" -mtime +2 2>/dev/null)" ] && msg="$msg The pointer is more than 2 days old: the flow may have been abandoned; ask the user before continuing."
if [ "$POINTER_NAME" = planning ] && [ -f "$FLOW_DIR/current" ] && pointer_mine "$FLOW_DIR/current"; then
  parked=$(normalize_path "$(head -n 1 "$FLOW_DIR/current" | tr -d '\r')")
  msg="$msg Another task is parked meanwhile: $parked at status: $(frontmatter_value status "$parked/plan.md"); its stage agents cannot be spawned until this planning ends (approve or abandon it), then /dev-flow:dev-implement $parked/plan.md resumes it."
fi
case $POINTER_NAME in
  planning) msg="$msg$(other_session_note current)" ;;
  current)  msg="$msg$(other_session_note planning)" ;;
esac
emit_context SessionStart "$msg"
