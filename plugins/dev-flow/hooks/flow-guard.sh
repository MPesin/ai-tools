#!/usr/bin/env bash
# PreToolUse guard. Active while <project>/.claude/flow/current or /planning exists.
#   Bash, PowerShell  -> no commit/push/discard, no posting, no publishing (commands.sh)
#   mcp__*            -> no MCP tools that write to external systems
#   Edit/Write/NotebookEdit -> per-agent write allowances (case table below)
#   Agent (Task)      -> a stage agent is spawned only at its own plan status (stage_gate);
#                        checked even without a pointer, since a missing pointer is the finding
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
[ -f "$HERE/lib.sh" ] || HERE="${CLAUDE_PLUGIN_ROOT}/hooks"
source "$HERE/lib.sh"
source "$HERE/commands.sh"

deny() {
  echo "dev-flow guard: $1" >&2
  exit 2
}

# stage_gate SUBAGENT_TYPE: the main session may spawn a dev-implement stage agent only
# when plan.md's status names that stage. This is what keeps status (which the hooks
# and the status panel read) in step with what is actually running: the skill text
# alone was skipped when planning and implementing were asked for in one reply.
stage_gate() {
  local agent=${1##*:} want pointer folder status
  case $agent in
    dev-implementer)    want=implementing ;;
    dev-reviewer)       want=reviewing ;;
    dev-fixer)          want='reviewing|human-review' ;;
    dev-review-triager) want=human-review ;;
    # Not gated: dev-planner and dev-plan-critic run under the planning pointer or
    # before Intake (harden mode); dev-debugger (the dev-debug plugin) runs under the
    # planning pointer (status diagnosing) or standalone for a diagnosis without a fix; dev-qa-impact
    # also runs standalone, with no plan or with another task's pointer in place.
    # All four are read-only (write guard above).
    *) return 0 ;;
  esac
  POINTER_NAMES="current planning"
  pointer=$(find_flow_pointer) \
    || deny "$agent runs inside /dev-flow:dev-implement, whose Intake writes <project>/.claude/flow/current and whose stages set status in plan.md before spawning. Run /dev-flow:dev-implement <plan path> instead of spawning $agent directly."
  # planning is checked by name: find_flow_pointer prefers current when both exist.
  [ -f "${pointer%/*}/planning" ] \
    && deny "the plan is still being planned (.claude/flow/planning exists). Finish /dev-flow:dev-plan first: apply the requested plan changes, get the user's explicit approval, set status: approved, delete the planning pointer, then invoke /dev-flow:dev-implement <plan path>. Never implement from dev-plan."
  # A pointer whose folder is gone switches every other guard off silently
  # (load_task_folder exits 0); here that is the finding.
  folder=$(normalize_path "$(head -n 1 "$pointer" | tr -d '\r')")
  [ -n "$folder" ] && [ -d "$folder" ] \
    || deny "$pointer names '${folder:-nothing}', which is not a folder, so the flow's guards are off. Write the absolute task folder path as its only line, or delete it and run /dev-flow:dev-implement <plan path> again."
  [ -f "$folder/plan.md" ] \
    || deny "$folder has no plan.md; $agent needs the task's plan with status $want. Point $pointer at the task folder, or run /dev-flow:dev-implement <plan path>."
  load_task_folder
  status=$(frontmatter_value status)
  case "|$want|" in *"|$status|"*) exit 0 ;; esac
  deny "plan.md has status: ${status:-<none>}, but $agent runs at status $want. Set status in $TASK_FOLDER/plan.md frontmatter to the stage you are starting (the hooks and the status panel read it), then spawn again."
}

tool=$(json_field tool_name)
case $tool in
  Agent|Task) stage_gate "$(tool_input_field subagent_type)"; exit 0 ;;
esac
load_task_folder

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
      deny "$AGENT_TYPE may not edit $base with Edit/Write (append to verify.log with a shell command, >>; the other files belong to another stage)." ;;
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
  dev-debugger)
    # diagnosis.md (or diagnosis-2.md for a second opinion) plus reproduction
    # scripts and captured output under debug/; never the source tree.
    if in_task; then
      case $base in diagnosis*.md) exit 0 ;; esac
      path_under "$target" "$TASK_FOLDER/debug" && exit 0
    fi
    deny "dev-debugger may only write $TASK_FOLDER/diagnosis*.md and files under $TASK_FOLDER/debug/ (attempted: $target). Never edit source, not even to instrument it: record what you would add under Open questions." ;;
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
