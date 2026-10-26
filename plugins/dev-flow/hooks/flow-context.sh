#!/usr/bin/env bash
# SubagentStart for dev-* agents: inject the flow state, snapshot the working tree
# (compared at SubagentStop), mark the start of writing agents, keep the flow's
# files out of git status.
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
[ -f "$HERE/lib.sh" ] || HERE="${CLAUDE_PLUGIN_ROOT}/hooks"
source "$HERE/lib.sh"
load_task_folder
case $AGENT_TYPE in dev-*) ;; *) exit 0 ;; esac

ensure_git_exclude
if [ -n "$AGENT_ID" ]; then
  tree_snapshot > "$FLOW_DIR/snap-$AGENT_ID"
  printf '%s\n' "$TASK_FOLDER" > "$FLOW_DIR/task-$AGENT_ID"   # read at SubagentStop if the pointer is gone
fi

branch=$(git -C "$GIT_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo unknown)
context="Dev-flow is active. Task folder: $TASK_FOLDER. Project root: $GIT_ROOT. Branch: $branch. status: $(frontmatter_value status). mode: $(frontmatter_value mode). review_round: $(frontmatter_value review_round). base: $(frontmatter_value base)."

if is_writing_agent "$AGENT_TYPE"; then
  : > "$FLOW_DIR/start-$AGENT_ID"
  context="$context Append the command line and raw output of every build/test command you run to $TASK_FOLDER/verify.log with a shell append (>>); a run that adds nothing there is refused when you stop."
  if [ "$AGENT_TYPE" = dev-implementer ] && plan_has_packages; then
    context="$context This plan has work packages: before your first edit, write your package id (for example P2; or the word all if you were given no package) as the only content of $FLOW_DIR/claim-$AGENT_ID. Edits are refused until that file exists, and edits outside your package's Owns are refused."
  fi
elif [ "$AGENT_TYPE" = dev-debugger ]; then
  context="$context You are a read-only agent: write nothing but your diagnosis file in the task folder and reproduction scripts or captured output under $TASK_FOLDER/debug/. Never edit source, not even to instrument it. The plugin compares the working tree before and after your run and reports every other changed file to the user."
else
  context="$context You are a read-only agent: write nothing but your own output file. The plugin compares the working tree before and after your run and reports every other changed file to the user."
fi
emit_context SubagentStart "$context"
