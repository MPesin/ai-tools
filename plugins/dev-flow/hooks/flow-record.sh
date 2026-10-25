#!/usr/bin/env bash
# PostToolUse recorder (Bash, PowerShell). While dev-implementer or dev-fixer runs,
# every build/test-like command and its output tail are appended to
# <task folder>/verify.log by the plugin, so the evidence is what actually ran,
# not what the agent reports. Pure read commands are skipped.
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
[ -f "$HERE/lib.sh" ] || HERE="${CLAUDE_PLUGIN_ROOT}/hooks"
source "$HERE/lib.sh"
load_task_folder current
is_writing_agent "$AGENT_TYPE" || exit 0

tool=$(json_field tool_name)
case $tool in Bash|PowerShell) ;; *) exit 0 ;; esac
cmd=$(tool_input_field command)
[ -n "$cmd" ] || exit 0

# Record unless every simple command is a plain read (cd/ls/cat/grep/git status...).
worth_recording=0
while IFS= read -r line; do
  first=$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
  first=${first##*/}; first=${first%.exe}
  case $first in
    ''|ls|dir|cat|type|head|tail|grep|rg|find|fd|pwd|cd|echo|printf|wc|which|where|tree|sed|awk|sort|uniq|cut|tr|test|'['|true|false|date|env|export|set|mkdir|touch|cp|mv|rm|chmod|basename|dirname|stat|file|diff|less|more|tee|sleep|git|get-childitem|get-content|select-string|write-output|write-host|set-location|get-location|get-item|copy-item|move-item|remove-item|new-item) ;;
    *) worth_recording=1 ;;
  esac
done <<< "$(printf '%s\n' "$cmd" | tr ';|&' '\n\n\n')"
[ $worth_recording = 1 ] || exit 0

pkg=$(head -n 1 "$FLOW_DIR/claim-$AGENT_ID" 2>/dev/null | tr -d '\r[:space:]')
out=$(tool_response_field stdout)
err=$(tool_response_field stderr)
if [ -z "$out$err" ]; then
  raw=${INPUT#*\"tool_response\"}
  [ "$raw" != "$INPUT" ] && out=$(json_decode "${raw:0:20000}")
fi

block=$(
  printf '\n=== dev-flow [%s] agent %s %s\n$ %s\n' "${pkg:-all}" "${AGENT_ID:-main}" "$(now_utc)" "$cmd"
  [ -n "$out" ] && printf '%s\n' "$out" | tail -n 150 | cut -c1-4000
  [ -n "$err" ] && { printf -- '--- stderr\n'; printf '%s\n' "$err" | tail -n 60 | cut -c1-4000; }
)
printf '%s\n' "$block" >> "$TASK_FOLDER/verify.log"
exit 0
