#!/usr/bin/env bash
# Stop hook (main session): when the flow waits for the user (diagnosing, then
# confirm-cause once diagnosis.md exists, draft, human-review, blocked, done, a
# needs-decision.md or violations.md), show a terminal message and
# send a desktop notification once per state. The `finished` pointer (written by the
# final report) notifies "done" and is then removed with the run's marker files; a
# `current` left at status done (the rename skipped) is treated the same, or it
# would keep commit and push blocked for good.
# A planning pointer left behind by a plan past draft/diagnosing is removed here
# (stale_exit in lib.sh), with a message; one naming a missing folder is only named.
HERE=$(printf '%s' "$0" | sed 's|[/\\][^/\\]*$||'); [ "$HERE" = "$0" ] && HERE=.
[ -f "$HERE/lib.sh" ] || HERE="${CLAUDE_PLUGIN_ROOT}/hooks"
source "$HERE/lib.sh"
HOOK_EVENT=Stop
# planning first: a task being planned or diagnosed beside a parked current is the
# one the user is working on, so its gate is the one to announce.
load_task_folder "planning current finished"
[ -z "$AGENT_TYPE" ] || exit 0

finish_cleanup() {
  [ "$POINTER_NAME" = finished ] || [ "$status" = done ] || return 0
  rm -f "$POINTER" "$FLOW_DIR/notified" "$FLOW_DIR/stale-notified" "$FLOW_DIR"/start-* "$FLOW_DIR"/snap-* "$FLOW_DIR"/claim-* 2>/dev/null
}

status=$(frontmatter_value status)
flags=''
[ -s "$TASK_FOLDER/needs-decision.md" ] && flags="$flags+needs-decision"
[ -s "$TASK_FOLDER/violations.md" ] && flags="$flags+violations"
if [ "$POINTER_NAME" = finished ] || [ "$status" = done ]; then
  state=done
else
  case $status in
    diagnosing) if [ -s "$TASK_FOLDER/diagnosis.md" ]; then state=confirm-cause; else state=$status; fi ;;
    draft|human-review|blocked|done) state=$status ;;
    *) [ -n "$flags" ] || exit 0; state=${status:-unknown} ;;
  esac
fi
state="$state$flags"

key="$TASK_FOLDER|$state"
notified="$FLOW_DIR/notified"
if [ "$(cat "$notified" 2>/dev/null)" = "$key" ]; then finish_cleanup; exit 0; fi
printf '%s' "$key" > "$notified"

task=$(frontmatter_value task)
[ -n "$task" ] || task=${TASK_FOLDER##*/}
title="dev-flow"
message="$task: waiting for you ($state)"

# Text reaches every notifier through environment variables or argv, never by
# splicing it into a script: a task title with a quote must not run code.
export DEV_FLOW_TITLE=$title DEV_FLOW_MESSAGE=$message
ps_toast() {
  powershell.exe -NoProfile -NonInteractive -Command '$t=$env:DEV_FLOW_TITLE; $m=$env:DEV_FLOW_MESSAGE; Add-Type -AssemblyName System.Windows.Forms; $n=New-Object System.Windows.Forms.NotifyIcon; $n.Icon=[System.Drawing.SystemIcons]::Information; $n.Visible=$true; $n.ShowBalloonTip(5000,$t,$m,[System.Windows.Forms.ToolTipIcon]::Info); Start-Sleep -Seconds 6; $n.Dispose()' >/dev/null 2>&1 &
}
send_notification() {
  if [ -n "$DEV_FLOW_NOTIFY_CMD" ]; then
    "$DEV_FLOW_NOTIFY_CMD" "$title" "$message" >/dev/null 2>&1
    return 0
  fi
  case $FLOW_OS in
    windows) command -v powershell.exe >/dev/null 2>&1 && ps_toast ;;
    mac) osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$title" "$message" >/dev/null 2>&1 ;;
    *)
      if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message" >/dev/null 2>&1
      elif grep -qi microsoft /proc/version 2>/dev/null && command -v powershell.exe >/dev/null 2>&1; then
        ps_toast   # WSL
      fi ;;
  esac
  return 0
}
send_notification

printf '{"systemMessage":"%s"}\n' "$(json_escape "dev-flow: $message")"
finish_cleanup
exit 0
