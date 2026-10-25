#!/usr/bin/env bash
# SessionStart (startup, resume, compact): when a flow is active, put its state back
# into context so a resumed or compacted session knows the task folder, the stage and
# how to continue, and warn when the pointer looks abandoned.
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
[ -f "$HERE/lib.sh" ] || HERE="${CLAUDE_PLUGIN_ROOT}/hooks"
source "$HERE/lib.sh"
load_task_folder "current planning"

status=$(frontmatter_value status)
if [ "$POINTER_NAME" = planning ]; then
  next="Planning is in progress: continue with /dev-flow:dev-plan, or delete $POINTER to abandon it."
else
  next="Continue with /dev-flow:dev-implement $TASK_FOLDER/plan.md (it resumes from status and review_round)."
fi
msg="dev-flow: a flow is active in this project. Task folder: $TASK_FOLDER. status: ${status:-unknown}. mode: $(frontmatter_value mode). review_round: $(frontmatter_value review_round). base: $(frontmatter_value base). $next While the pointer exists the plugin's hooks block git commit/push/discard, posting and publishing, and limit what each agent may write; delete $POINTER to switch them off (stage agents then cannot be spawned until Intake writes it again)."
[ -s "$TASK_FOLDER/needs-decision.md" ] && msg="$msg needs-decision.md has items waiting for the user."
[ -s "$TASK_FOLDER/violations.md" ] && msg="$msg violations.md lists files changed outside an agent's allowance."
[ -n "$(find "$POINTER" -mtime +2 2>/dev/null)" ] && msg="$msg The pointer is more than 2 days old: the flow may have been abandoned; ask the user before continuing."
emit_context SessionStart "$msg"
