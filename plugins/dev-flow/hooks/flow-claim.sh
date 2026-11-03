#!/usr/bin/env bash
# PostToolUse (main session; Bash, PowerShell, Write, Edit, NotebookEdit): the
# session whose tool call wrote a pointer owns the flow. The skills write the task
# folder's path as the pointer's only line; right after that tool call this hook
# adds `session: <id>`, and from then on the pointer counts only in this session
# and its subagents (lib.sh). A pointer that already names a session is left
# alone: taking a flow over is writing the pointer again (Intake does), never a
# side effect of another session's tool call.
#
# Only a tool call that names the flow directory can have written a pointer, so
# the hook returns at once for every other call; the cost is a regex on the
# command or path. A subagent never claims: it carries its parent's session id
# and writes no pointers (its claim-* files sit beside them, which is why the
# agent check comes first).
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
[ -f "$HERE/lib.sh" ] || HERE="${CLAUDE_PLUGIN_ROOT}/hooks"
source "$HERE/lib.sh"
HOOK_EVENT=PostToolUse

[ -z "$(json_field agent_type)" ] || exit 0
[ -n "$SESSION_ID" ] || exit 0
case $(json_field tool_name) in
  Bash|PowerShell) text=$(tool_input_field command) ;;
  Edit|Write)      text=$(tool_input_field file_path) ;;
  NotebookEdit)    text=$(tool_input_field notebook_path) ;;
  *) exit 0 ;;
esac
re='\.claude[/\\]flow|flow[/\\](current|planning|finished)'
[[ $(lower "$text") =~ $re ]] || exit 0

POINTER_NAMES="current planning finished"
find_flow_dir || exit 0
claimed=''
for name in $POINTER_NAMES; do
  p="$FLOW_DIR/$name"
  [ -f "$p" ] || continue
  [ -z "$(pointer_owner "$p")" ] || continue
  folder=$(head -n 1 "$p" | tr -d '\r')
  printf '%s\nsession: %s\n' "$folder" "$SESSION_ID" > "$p"
  claimed="$claimed $p ($folder)"
done
[ -n "$claimed" ] || exit 0
emit_context PostToolUse "dev-flow: this session now owns$claimed. The flow's guards and notifications apply to this session and its subagents only; other Claude Code sessions on this checkout are not affected by it and must not run its stage agents."
