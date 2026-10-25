#!/usr/bin/env bash
# PreToolUse guard. Active while <project>/.claude/flow/current or /planning exists.
#   Bash, PowerShell  -> no commit/push/discard, no posting, no publishing (commands.sh)
#   mcp__*            -> no MCP tools that write to external systems
#   Edit/Write/NotebookEdit -> per-agent write allowances (table below)
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
[ -f "$HERE/lib.sh" ] || HERE="${CLAUDE_PLUGIN_ROOT}/hooks"
source "$HERE/lib.sh"
source "$HERE/commands.sh"
load_task_folder

deny() {
  echo "dev-flow guard: $1" >&2
  exit 2
}

tool=$(json_field tool_name)
case $tool in
  Bash|PowerShell) check_command "$(tool_input_field command)" 0; exit 0 ;;
  mcp__*)          check_mcp_tool "$tool"; exit 0 ;;
  Edit|Write)      target=$(tool_input_field file_path) ;;
  NotebookEdit)    target=$(tool_input_field notebook_path) ;;
  *) exit 0 ;;
esac
[ -n "$target" ] || exit 0
target=$(normalize_path "$target")
base=${target##*/}

in_task() { path_under "$target" "$TASK_FOLDER"; }
in_flow() { path_under "$target" "$FLOW_DIR"; }

# only_file PATTERN: the agent may write nothing but $TASK_FOLDER/PATTERN
only_file() {
  if in_task; then case $base in $1) exit 0 ;; esac; fi
  deny "$AGENT_TYPE may only write $TASK_FOLDER/$1 (attempted: $target)."
}

# Files other agents or the main session own; implementer and fixer never edit them.
deny_flow_outputs() {
  in_task || return 0
  case $base in
    verify.log|review-*.md|plan-critique.md|qa-impact.md|human-review.md|needs-decision.md|violations.md)
      deny "$AGENT_TYPE may not edit $base (it belongs to another stage; verify.log is written by the plugin)." ;;
  esac
}

implementer_check() {
  in_flow && exit 0
  deny_flow_outputs
  plan_has_packages || exit 0            # one implementer: plan.md, notes.md and any source file
  local claim_file="$FLOW_DIR/claim-$AGENT_ID" claim owns rel
  [ -f "$claim_file" ] \
    || deny "this plan has work packages: before editing, write your package id (P2, or 'all' when you run the whole plan) to $claim_file, then retry."
  claim=$(head -n 1 "$claim_file" | tr -d '\r[:space:]')
  [ "$claim" = all ] && exit 0
  if in_task; then
    case $base in
      plan.md)  deny "parallel implementers do not edit plan.md; report finished steps as [$claim] lines in notes.md (the main session ticks the boxes)." ;;
      notes.md) deny "parallel implementers append to notes.md with a shell command (>>), not Edit/Write, so concurrent appends do not overwrite each other." ;;
    esac
    exit 0
  fi
  owns=$(package_owns "$claim")
  [ -n "$owns" ] || exit 0               # no Owns line: nothing to enforce (the plan critic flags this)
  rel=$(rel_to_root "$target")
  printf '%s\n' "$owns" | matches_any_pattern "$rel" \
    || deny "package $claim does not own $rel (Owns: $(printf '%s' "$owns" | tr '\n' ' ')). Stop and report the step instead of editing outside your package."
  exit 0
}

case $AGENT_TYPE in
  dev-reviewer)       only_file 'review-*.md' ;;
  dev-plan-critic)    only_file 'plan-critique.md' ;;
  dev-qa-impact)      only_file 'qa-impact.md' ;;
  dev-review-triager) only_file 'human-review.md' ;;
  dev-planner)
    in_task || deny "dev-planner may only write inside $TASK_FOLDER (attempted: $target)."
    exit 0 ;;
  dev-fixer)
    in_flow && exit 0
    deny_flow_outputs
    in_task && [ "$base" = plan.md ] && deny "dev-fixer does not edit plan.md; it appends to notes.md."
    exit 0 ;;
  dev-implementer) implementer_check ;;
  '')
    # Main session. While /dev-plan runs, only the task folder and the flow dir are writable.
    if [ "$POINTER_NAME" = planning ]; then
      in_task || in_flow \
        || deny "while /dev-plan runs, writes are limited to the task folder $TASK_FOLDER (attempted: $target). Approve or abandon the plan first."
    fi
    exit 0 ;;
esac
exit 0
