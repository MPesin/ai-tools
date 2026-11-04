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
  if [ -n "$(pointer_owner "$p")" ]; then
    printf ' %s: task folder %s at status: %s; the two sessions do not guard or interrupt each other, and that task is not this session'"'"'s to touch.' \
      "$(foreign_notice "$p")" "$folder" "$(frontmatter_value status "$folder/plan.md")"
  else
    printf ' %s: task folder %s at status: %s; /dev-flow:load-flow %s claims it for this session.' \
      "$(foreign_notice "$p")" "$folder" "$(frontmatter_value status "$folder/plan.md")" "$folder"
  fi
}

if [ "$POINTER_MINE" != 1 ]; then
  status=$(frontmatter_value status "$TASK_FOLDER/plan.md")
  msg="dev-flow: $(foreign_notice "$POINTER"): task folder $TASK_FOLDER, status: ${status:-unknown}. Its guards and notifications do not apply to this session, and this session cannot spawn its stage agents. Leave that task alone unless the user asks for it. To run that flow from this session: /dev-flow:load-flow $TASK_FOLDER (or $(resume_skill "$POINTER_NAME" "$TASK_FOLDER") directly); the skill writes the pointer again, which hands the flow to this session, and the other session's run then loses its guards (agents it already has running stay guarded until they stop) and cannot spawn further stage agents. To clear a leftover: /dev-flow:clear-flow all (or rm \"$POINTER\")."
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
elif [ "$status" = human-review ]; then
  next="The run waits at the human-review gate: when the user asks, push the branch and open the PR from this session (the hooks allow both here); review comments go to stage 5, and when the user says the review is done (or asks for QA impact) stage 6 and the final report finish the run: /dev-flow:dev-implement $TASK_FOLDER/plan.md."
else
  next="Continue with /dev-flow:dev-implement $TASK_FOLDER/plan.md (it resumes from status and review_round)."
fi
msg="dev-flow: a flow of this session is active in this project. Task folder: $TASK_FOLDER. status: ${status:-unknown}. mode: $(frontmatter_value mode). review_round: $(frontmatter_value review_round). base: $(frontmatter_value base). $next While the pointer exists the plugin's hooks block pushes and new PRs from subagents, force and delete pushes, pulling, branch switches and discards, commits from subagents and --amend, commenting, merging and publishing, and limit what each agent may write; the main session commits each stage's files and may push and open the PR when the user asks. This holds in this session and its subagents only. /dev-flow:clear-flow abandons the run (it removes $POINTER; stage agents then cannot be spawned until Intake writes it again): suggest it only when the user wants to stop the run, never to push, open the PR or finish it."
[ -s "$TASK_FOLDER/needs-decision.md" ] && msg="$msg needs-decision.md has items waiting for the user."
[ -s "$TASK_FOLDER/violations.md" ] && msg="$msg violations.md lists files changed outside an agent's allowance."
# A task waiting at human review or blocked waits on people, for as long as a
# review takes; only an in-progress stage left for days looks abandoned.
case $status in
  human-review|blocked|done) ;;
  *) [ -n "$(find "$POINTER" -mtime +2 2>/dev/null)" ] && msg="$msg The pointer is more than 2 days old: the flow may have been abandoned; ask the user before continuing." ;;
esac
if [ "$POINTER_NAME" = planning ] && [ -f "$FLOW_DIR/current" ] && pointer_mine "$FLOW_DIR/current"; then
  parked=$(normalize_path "$(head -n 1 "$FLOW_DIR/current" | tr -d '\r')")
  msg="$msg Another task is parked meanwhile: $parked at status: $(frontmatter_value status "$parked/plan.md"); /dev-flow:dev-implement $parked/plan.md resumes it at any time (its stage agents run beside this planning; the planner, critic and debugger belong to this task)."
fi
case $POINTER_NAME in
  planning) msg="$msg$(other_session_note current)" ;;
  current)  msg="$msg$(other_session_note planning)" ;;
esac
emit_context SessionStart "$msg"
