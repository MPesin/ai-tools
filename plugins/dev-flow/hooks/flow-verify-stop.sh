#!/usr/bin/env bash
# SubagentStop for dev-* agents.
#   read-only agents : any file changed since SubagentStart is a violation
#   implementer (package mode): changed files outside every package's Owns are violations
#   implementer/fixer: verify.log gained this run's build/test output (a [Pn] block in
#                      package mode); notes.md/plan.md bookkeeping
# A violation or missing evidence blocks the stop once (the agent gets the reason and
# reports); it is also appended to <task folder>/violations.md for the user.
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
[ -f "$HERE/lib.sh" ] || HERE="${CLAUDE_PLUGIN_ROOT}/hooks"
source "$HERE/lib.sh"
load_task_folder
case $AGENT_TYPE in dev-*) ;; *) exit 0 ;; esac

snap="$FLOW_DIR/snap-$AGENT_ID"
marker="$FLOW_DIR/start-$AGENT_ID"
claim_file="$FLOW_DIR/claim-$AGENT_ID"
cleanup() { rm -f "$snap" "$snap.now" "$marker" "$claim_file"; }

if json_bool_true stop_hook_active; then cleanup; exit 0; fi

problems=()
violation=''
claim=$(head -n 1 "$claim_file" 2>/dev/null | tr -d '\r[:space:]')

if [ -s "$snap" ] || [ -f "$snap" ]; then
  tree_snapshot > "$snap.now"
  changed=$(snapshot_diff "$snap" "$snap.now")
  if [ -n "$changed" ]; then
    if is_readonly_agent "$AGENT_TYPE"; then
      violation=$changed
    elif [ "$AGENT_TYPE" = dev-implementer ] && plan_has_packages && [ -n "$claim" ] && [ "$claim" != all ]; then
      allowed=$(for p in $(all_package_ids); do package_owns "$p"; done)
      violation=$(printf '%s\n' "$changed" | while IFS= read -r f; do
        printf '%s\n' "$allowed" | matches_any_pattern "$f" || printf '%s\n' "$f"
      done)
    fi
  fi
fi

if [ -n "$violation" ]; then
  list=$(printf '%s' "$violation" | tr '\n' ' ')
  printf -- '- %s %s (%s): changed outside its allowance: %s\n' "$(now_utc)" "$AGENT_TYPE" "$AGENT_ID" "$list" >> "$TASK_FOLDER/violations.md"
  problems+=("files changed during your run that you must not change: $list (by you, by a build side effect, or by someone else in the same tree). Do not revert them; state in your final message exactly what you changed and why")
fi

if is_writing_agent "$AGENT_TYPE"; then
  verify_log="$TASK_FOLDER/verify.log"
  if [ "$AGENT_TYPE" = dev-implementer ] && plan_has_packages && [ -n "$claim" ] && [ "$claim" != all ]; then
    grep -q -F "[$claim]" "$verify_log" 2>/dev/null \
      || problems+=("verify.log has no [$claim] block; append the command line and raw output of every build/test command you ran under a [$claim] line (shell append, >>)")
  elif [ ! -s "$verify_log" ]; then
    problems+=("verify.log is missing or empty; append the command line and raw output of every build/test command you ran to $verify_log")
  elif [ -f "$marker" ] && [ ! "$verify_log" -nt "$marker" ]; then
    problems+=("verify.log was not updated during this run; append the build/test output of this run to $verify_log")
  fi
  if [ "$AGENT_TYPE" = dev-implementer ]; then
    if plan_has_packages && [ -n "$claim" ] && [ "$claim" != all ]; then
      grep -q -F "[$claim]" "$TASK_FOLDER/notes.md" 2>/dev/null \
        || problems+=("notes.md has no [$claim] lines; append one line per finished step (how it was verified) and any deviation, tagged [$claim]")
    elif grep -q -E '^[[:space:]]*- \[ \]' "$TASK_FOLDER/plan.md" 2>/dev/null && [ ! -s "$TASK_FOLDER/notes.md" ]; then
      problems+=("plan.md still has unchecked '- [ ]' steps and notes.md does not explain them; finish the steps or explain in $TASK_FOLDER/notes.md")
    fi
  fi
fi

if [ ${#problems[@]} -eq 0 ]; then cleanup; exit 0; fi
reason=$(printf '%s; ' "${problems[@]}")
printf '{"decision":"block","reason":"%s"}\n' "$(json_escape "$reason")"
exit 0
