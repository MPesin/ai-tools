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
[ -n "$AGENT_ID" ] && tree_snapshot > "$FLOW_DIR/snap-$AGENT_ID"

branch=$(git -C "$GIT_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo unknown)
context="Dev-flow is active. Task folder: $TASK_FOLDER. Project root: $GIT_ROOT. Branch: $branch. status: $(frontmatter_value status). mode: $(frontmatter_value mode). review_round: $(frontmatter_value review_round). base: $(frontmatter_value base)."

if is_writing_agent "$AGENT_TYPE"; then
  : > "$FLOW_DIR/start-$AGENT_ID"
  context="$context The plugin records every build/test command you run, with its output, in $TASK_FOLDER/verify.log; do not append to that file yourself, and do run the project's build and test commands so the record exists."
  if [ "$AGENT_TYPE" = dev-implementer ] && plan_has_packages; then
    context="$context This plan has work packages: before your first edit, write your package id (for example P2; or the word all if you were given no package) as the only content of $FLOW_DIR/claim-$AGENT_ID. Edits are refused until that file exists, and edits outside your package's Owns are refused."
  fi
else
  context="$context You are a read-only agent: write nothing but your own output file. The plugin compares the working tree before and after your run and reports every other changed file to the user."
fi
emit_context SubagentStart "$context"
