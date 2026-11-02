#!/usr/bin/env bash
# Shared by every dev-flow hook.
#
# Portability rules (hooks run under whatever `bash` the machine has: Git Bash on
# Windows, bash 3.2 on macOS, bash 4/5 on Linux):
#   - no ${var,,}, mapfile, declare -A, |& or &>>      (bash 3.2)
#   - regexes live in variables before [[ =~ ]]        (bash 3.2 quoting)
#   - no sed -i, stat, readlink -f, date %N, md5sum     (GNU-only or BSD-divergent)
#   - hashing goes through `git hash-object`, which is always present where git is
#   - paths are normalized to one form (forward slashes, /c/... for drive letters)
#     before any comparison; on Windows comparisons are case-insensitive
# No jq: fields are pulled out of the hook JSON with regexes. Top-level fields are
# taken from the first occurrence of the key; tool_input/tool_response fields from
# the text after that object's key, so a `content` that quotes a key cannot shadow it.

INPUT=$(cat)

case $(uname -s 2>/dev/null) in
  MINGW*|MSYS*|CYGWIN*) FLOW_OS=windows ;;
  Darwin)               FLOW_OS=mac ;;
  *)                    FLOW_OS=linux ;;
esac

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ---------------------------------------------------------------- JSON helpers

json_decode() {
  local v=$1
  v=${v//\\\\/$'\001'}          # park escaped backslashes first
  v=${v//\\\//\/}
  v=${v//\\\"/\"}
  v=${v//\\n/$'\n'}
  v=${v//\\r/}
  v=${v//\\t/$'\t'}
  v=${v//$'\001'/\\}
  printf '%s' "$v"
}

# json_field KEY [TEXT]  -> decoded value of the first "KEY": "..." in TEXT (default: whole input)
json_field() {
  local text=${2-$INPUT}
  local re='"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
  [[ $text =~ $re ]] || return 0
  json_decode "${BASH_REMATCH[1]}"
}

json_bool_true() {
  local re='"'"$1"'"[[:space:]]*:[[:space:]]*true'
  [[ $INPUT =~ $re ]]
}

# Field inside the tool_input object (the text after its key).
tool_input_field() {
  local after=${INPUT#*\"tool_input\"}
  [ "$after" = "$INPUT" ] && return 0
  json_field "$1" "$after"
}

tool_response_field() {
  local after=${INPUT#*\"tool_response\"}
  [ "$after" = "$INPUT" ] && return 0
  json_field "$1" "$after"
}

json_escape() {
  local v=$1
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
  v=${v//$'\n'/\\n}
  v=${v//$'\r'/}
  v=${v//$'\t'/\\t}
  printf '%s' "$v"
}

emit_context() {   # emit_context EVENT TEXT
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$(json_escape "$2")"
}

# ---------------------------------------------------------------- paths

# One spelling for every path: forward slashes, no doubled or trailing slashes,
# `C:/x` and `C:\x` become `/c/x` (what Git Bash's $PWD and `cd && pwd` print).
normalize_path() {
  local p=$1 re='^([A-Za-z]):(/|$)' d
  p=${p//\\//}
  while [[ $p == *//* ]]; do p=${p//\/\///}; done
  if [[ $p =~ $re ]]; then
    d=$(lower "${BASH_REMATCH[1]}")
    p="/$d${p:2}"
  fi
  [ ${#p} -gt 1 ] && p=${p%/}
  printf '%s' "$p"
}

# Comparison key: normalized, and lowercased on Windows (case-insensitive FS).
path_key() {
  local p
  p=$(normalize_path "$1")
  [ "$FLOW_OS" = windows ] && p=$(lower "$p")
  printf '%s' "$p"
}

# path_under CHILD PARENT -> true when CHILD is PARENT or inside it
path_under() {
  local c p
  c=$(path_key "$1"); p=$(path_key "$2")
  [ "$c" = "$p" ] && return 0
  case $c in "$p"/*) return 0 ;; esac
  return 1
}

# ---------------------------------------------------------------- flow state

# Walk up from the hook's cwd to the first .claude/flow/<name> pointer. The walk
# ends at the first directory that holds a .git (a directory in the main checkout,
# a file in a worktree or submodule): a flow belongs to one checkout, so a session
# in a worktree (Claude Code puts them under <repo>/.claude/worktrees/<name>) must
# not pick up the main checkout's pointer above it.
find_flow_pointer() {
  local dir name
  dir=$(json_field cwd)
  [ -z "$dir" ] && dir=$PWD
  dir=$(cd "$(normalize_path "$dir")" 2>/dev/null && pwd) || return 1
  while :; do
    for name in $POINTER_NAMES; do
      if [ -f "$dir/.claude/flow/$name" ]; then
        printf '%s' "$dir/.claude/flow/$name"
        return 0
      fi
    done
    [ -e "$dir/.git" ] && return 1
    [ -z "$dir" ] || [ "$dir" = "/" ] && return 1
    dir=${dir%/*}
    [ -z "$dir" ] && dir=/
  done
}

# Sets POINTER, POINTER_NAME, FLOW_DIR, PROJECT_DIR, GIT_ROOT, TASK_FOLDER,
# AGENT_TYPE (bare name, plugin prefix stripped), AGENT_ID, SESSION_ID.
# Exits 0 (hook inactive) when no pointer or the task folder is gone, and when
# the pointer found is a stale planning one (stale_exit says so first).
load_task_folder() {
  POINTER_NAMES=${1:-"current planning"}
  AGENT_TYPE=$(json_field agent_type)
  AGENT_TYPE=${AGENT_TYPE##*:}
  # Planner, critic and debugger belong to the task being planned: with a planning
  # pointer beside a parked current (a task waiting at human-review), theirs is the
  # planning one, or they could write nothing but the parked task's folder.
  case $AGENT_TYPE in
    dev-planner|dev-plan-critic|dev-debugger) [ "$POINTER_NAMES" = "current planning" ] && POINTER_NAMES="planning current" ;;
  esac
  POINTER=$(find_flow_pointer) || exit 0
  POINTER_NAME=${POINTER##*/}
  FLOW_DIR=${POINTER%/*}
  PROJECT_DIR=${FLOW_DIR%/.claude/flow}
  SESSION_ID=$(json_field session_id)
  if [ "$POINTER_NAME" = planning ] && planning_stale "$POINTER"; then
    # Beside a current pointer the parked task carries on; the Stop hook sweeps.
    if [ "$HOOK_EVENT" != Stop ] && [ -f "$FLOW_DIR/current" ]; then
      POINTER="$FLOW_DIR/current"; POINTER_NAME=current
    else
      stale_exit
    fi
  fi
  TASK_FOLDER=$(normalize_path "$(head -n 1 "$POINTER" | tr -d '\r')")
  [ -n "$TASK_FOLDER" ] && [ -d "$TASK_FOLDER" ] || exit 0
  GIT_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
  GIT_ROOT=$(normalize_path "${GIT_ROOT:-$PROJECT_DIR}")
  AGENT_ID=$(json_field agent_id)
}

# Statuses of a plan still being planned or diagnosed (plan-format.md): the
# planning pointer belongs to them. Empty is a plan.md not written yet (dev-plan
# and dev-debug write the pointer first).
is_planning_status() {
  case $1 in diagnosing|draft|'') return 0 ;; esac
  return 1
}

# planning_stale PATH: true when the planning pointer at PATH was left behind.
# The skills delete it on approval, on diagnosis-only and on abandonment, so one
# whose plan.md has a later status, or whose folder is gone, guards nothing.
# Sets STALE_FOLDER, STALE_STATUS (empty when the folder is gone), STALE_NOTICE
# (what is wrong and the command that removes it) and STALE_RESUME (how the task
# itself goes on, when it does).
planning_stale() {
  local why
  STALE_STATUS=''; STALE_NOTICE=''; STALE_RESUME=''
  STALE_FOLDER=$(normalize_path "$(head -n 1 "$1" 2>/dev/null | tr -d '\r')")
  if [ -z "$STALE_FOLDER" ] || [ ! -d "$STALE_FOLDER" ]; then
    why="it names '${STALE_FOLDER:-nothing}', which is not a folder, so it guards nothing. Remove it: rm \"$1\" (or write the task folder's absolute path as its only line)."
  else
    STALE_STATUS=$(frontmatter_value status "$STALE_FOLDER/plan.md")
    is_planning_status "$STALE_STATUS" && return 1
    why="it points at $STALE_FOLDER, whose plan.md has status: $STALE_STATUS, past planning (the pointer is deleted on approval), so it guards nothing. The Stop hook removes it at the end of the turn; to remove it now: rm \"$1\"."
    [ "$STALE_STATUS" = done ] || STALE_RESUME=" The task itself continues with /dev-flow:dev-implement $STALE_FOLDER/plan.md (its Intake writes ${1%/*}/current)."
  fi
  STALE_NOTICE="dev-flow: stale pointer $1: $why"
  return 0
}

# A stale planning pointer switches the hooks off like no pointer. The hooks that
# reach the user (HOOK_EVENT set by the script) say so: SessionStart every time,
# PreToolUse once per session (stale-notified beside the pointer), Stop by
# removing the pointer when plan.md proves it stale (a dangling one is only named).
stale_exit() {
  local marker="$FLOW_DIR/stale-notified" key="$POINTER|$STALE_STATUS|$SESSION_ID" msg
  case $HOOK_EVENT in
    SessionStart) emit_context SessionStart "$STALE_NOTICE$STALE_RESUME" ;;
    Stop)
      if [ -n "$STALE_STATUS" ]; then
        rm -f "$POINTER" "$marker"
        msg="dev-flow: removed stale pointer $POINTER (it pointed at $STALE_FOLDER, whose plan.md has status: $STALE_STATUS; nothing was being planned)."
        printf '{"systemMessage":"%s"}\n' "$(json_escape "$msg")"
      elif [ "$(cat "$marker" 2>/dev/null)" != "$key" ]; then
        printf '%s' "$key" > "$marker"
        printf '{"systemMessage":"%s"}\n' "$(json_escape "$STALE_NOTICE")"
      fi ;;
    PreToolUse)
      if [ "$(cat "$marker" 2>/dev/null)" != "$key" ]; then
        printf '%s' "$key" > "$marker"
        printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' \
          "$(json_escape "$STALE_NOTICE")" "$(json_escape "$STALE_NOTICE$STALE_RESUME")"
      fi ;;
  esac
  exit 0
}

# A sed pattern matching WORD in any letter case (POSIX sed has no I flag).
ci_pattern() {
  local w=$1 i c out=''
  for ((i = 0; i < ${#w}; i++)); do
    c=${w:$i:1}
    case $c in [A-Za-z]) out="$out[$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]')$(lower "$c")]" ;; *) out="$out$c" ;; esac
  done
  printf '%s' "$out"
}

# Value of a frontmatter key (any letter case); CR, trailing spaces and surrounding quotes removed.
frontmatter_value() {   # KEY [PLAN_PATH]
  sed -n '/^---/,/^---/p' "${2:-$TASK_FOLDER/plan.md}" 2>/dev/null | tr -d '\r' \
    | sed -n "s/^$(ci_pattern "$1"):[[:space:]]*//p" | head -n 1 | sed 's/[[:space:]]*$//' \
    | sed "s/^\"\(.*\)\"\$/\1/; s/^'\(.*\)'\$/\1/"
}

plan_has_packages() {
  grep -E -q '^###[[:space:]]+P[0-9A-Za-z]+[[:space:]]*-' "$TASK_FOLDER/plan.md" 2>/dev/null
}

# Comma or whitespace separated list -> one item per line; a comma inside {a,b}
# is part of the item.
split_owns() {
  local s=$1 out='' depth=0 c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:$i:1}
    case $c in
      '{') depth=$((depth+1)) ;;
      '}') [ $depth -gt 0 ] && depth=$((depth-1)) ;;
      ,)   [ $depth -gt 0 ] && c=$'\001' ;;
    esac
    out="$out$c"
  done
  printf '%s' "$out" | tr ', ' '\n\n' | tr '\001' ','
}

# Patterns on stdin, one per line; src/{a,b}/** becomes src/a/** and src/b/**.
# Done by hand: brace expansion of plan text through eval would run it.
expand_braces() {
  local pat pre body post alt
  while IFS= read -r pat || [ -n "$pat" ]; do
    case $pat in
      *\{*\}*)
        pre=${pat%%\{*}; body=${pat#*\{}; body=${body%%\}*}; post=${pat#*\}}
        printf '%s\n' "$body" | tr ',' '\n' | while IFS= read -r alt || [ -n "$alt" ]; do printf '%s\n' "$pre$alt$post"; done | expand_braces ;;
      *) printf '%s\n' "$pat" ;;
    esac
  done
}

# Owns patterns of one package, one per line (comma or whitespace separated in the plan).
package_owns() {
  local line
  line=$(sed -n "/^###[[:space:]]*$1[[:space:]]*-/,/^##/p" "$TASK_FOLDER/plan.md" 2>/dev/null \
    | tr -d '\r' | sed -n 's/^[[:space:]]*Owns:[[:space:]]*//p' | head -n 1 | tr -d '`')
  split_owns "$line" | expand_braces | sed 's/^\.\///' | grep -v '^[[:space:]]*$'
}

all_package_ids() {
  grep -E -o '^###[[:space:]]+P[0-9A-Za-z]+' "$TASK_FOLDER/plan.md" 2>/dev/null | sed 's/^###[[:space:]]*//'
}

# matches_any_pattern REL_PATH  (patterns on stdin; `*` crosses `/`, so `src/**` works)
matches_any_pattern() {
  local rel pat
  rel=$(path_key "$1")
  while IFS= read -r pat; do
    pat=$(path_key "$pat")
    case $rel in $pat|$pat/*) return 0 ;; esac
  done
  return 1
}

# Path of TARGET relative to GIT_ROOT, or the absolute path when outside it.
rel_to_root() {
  local t r
  t=$(normalize_path "$1"); r=$GIT_ROOT
  if path_under "$t" "$r"; then printf '%s' "${t:$((${#r}+1))}"; else printf '%s' "$t"; fi
}

SNAPSHOT_LIMIT=${DEV_FLOW_SNAPSHOT_LIMIT:-5000}   # override for tests only

# hash_paths LIST OUT: a "hash path" line in OUT for every path in LIST (paths
# relative to GIT_ROOT, files that exist), in LIST's order. One
# `git hash-object --stdin-paths` for all of them. It stops at a file it cannot
# read (deleted meanwhile, locked on Windows): that one is `unreadable` and
# hashing goes on after it. After 20 such stops git is failing for another
# reason, and the rest are marked unreadable rather than spawning a process per
# file.
hash_paths() {
  local list=$1 out=$2 rest="$1.rest" next="$1.next" n_before n_done fails=0
  : > "$out.h"
  cp "$list" "$rest"
  while [ -s "$rest" ]; do
    n_before=$(wc -l < "$out.h")
    git -C "$GIT_ROOT" hash-object --stdin-paths < "$rest" >> "$out.h" 2>/dev/null && break
    n_done=$(( $(wc -l < "$out.h") - n_before ))
    fails=$((fails + 1))
    if [ $fails -ge 20 ]; then
      tail -n +$((n_done + 1)) "$rest" | sed 's/.*/unreadable/' >> "$out.h"
      break
    fi
    printf 'unreadable\n' >> "$out.h"
    tail -n +$((n_done + 2)) "$rest" > "$next"
    mv -f "$next" "$rest"
  done
  paste -d' ' "$out.h" "$list" > "$out"
  rm -f "$out.h" "$rest" "$next"
}

# A line per changed/untracked path with a content hash ("gone <path>" for a
# path that no longer exists), flow files excluded, at most SNAPSHOT_LIMIT
# lines. Comparing two snapshots (snapshot_changes) names the files that
# changed in between.
#
# The process count is fixed, not one per path: one `git status`, one awk that
# drops the flow's own files (.claude/flow, the task folder), one hash_paths.
# A process per path (before 2.3.1) took more than 600 s for 5,000 untracked
# files on Windows, where a fork costs tens of milliseconds, and the agent sat
# stalled until the hook was killed. `-z` keeps paths unquoted (porcelain
# quotes a path with a space); a path with a newline in its name is not
# supported. Scratch files live beside the snapshot in FLOW_DIR.
tree_snapshot() {
  local task_rel='' ci=0 work="$FLOW_DIR/.snap-$$" path
  [ "$FLOW_OS" = windows ] && ci=1
  if path_under "$TASK_FOLDER" "$GIT_ROOT"; then
    task_rel=$(rel_to_root "$TASK_FOLDER")
    [ $ci = 1 ] && task_rel=$(lower "$task_rel")
  fi
  # -z: "XY path" records; a rename or copy is followed by a record holding
  # its source path, which is skipped (the new path is the one that exists).
  git -C "$GIT_ROOT" --no-optional-locks status --porcelain -z -uall 2>/dev/null \
    | tr '\000' '\n' \
    | awk -v task="$task_rel" -v ci=$ci '
        skip { skip = 0; next }
        { xy = substr($0, 1, 2); p = substr($0, 4)
          if (xy ~ /[RC]/) skip = 1
          k = ci ? tolower(p) : p
          if (k == ".claude/flow" || index(k, ".claude/flow/") == 1) next
          if (task != "" && (k == task || index(k, task "/") == 1)) next
          print p }' | head -n "$SNAPSHOT_LIMIT" > "$work.all"
  # Files that exist go to the hasher; the rest are gone (`[ -f ]` is a builtin).
  while IFS= read -r path; do
    if [ -f "$GIT_ROOT/$path" ]; then printf '%s\n' "$path" >&3; else printf 'gone %s\n' "$path"; fi
  done < "$work.all" > "$work.out" 3> "$work.files"
  [ -s "$work.files" ] && hash_paths "$work.files" "$work.hashed" && cat "$work.hashed" >> "$work.out"
  sort "$work.out"
  rm -f "$work.all" "$work.out" "$work.files" "$work.hashed"
}

# Paths present in exactly one of two snapshot files.
snapshot_diff() {   # OLD NEW
  cat "$1" "$2" | sort | uniq -u | cut -d' ' -f2- | sort -u
}

# snapshot_changes OLD NEW: the paths whose content really changed between the
# two snapshots. A path listed differently in the two is checked against the
# file as it is now, because a listing can change while the file does not:
#   - a commit made meanwhile (the main session commits each stage) drops its
#     files from `git status` unchanged;
#   - with more than SNAPSHOT_LIMIT paths, one path added early in the listing
#     pushes another past the end of it.
# A path recorded in OLD changed when its current hash (or `gone`) differs
# from the recorded one. A path missing from OLD is new when OLD was complete;
# when OLD was cut at the limit it may only have been past the cut, so it
# counts when the file was modified after OLD was written or no longer exists.
snapshot_changes() {
  local old=$1 new=$2 work="$FLOW_DIR/.cmp-$$" path full=1
  [ "$(wc -l < "$old")" -ge "$SNAPSHOT_LIMIT" ] && full=0
  snapshot_diff "$old" "$new" > "$work.cand"
  if [ -s "$work.cand" ]; then
    : > "$work.files"; : > "$work.newer"
    while IFS= read -r path; do
      [ -f "$GIT_ROOT/$path" ] || continue
      printf '%s\n' "$path" >> "$work.files"
      [ "$GIT_ROOT/$path" -nt "$old" ] && printf '%s\n' "$path" >> "$work.newer"
    done < "$work.cand"
    : > "$work.cur"
    [ -s "$work.files" ] && hash_paths "$work.files" "$work.cur"
    awk -v full=$full '
      function rest(line, r) { return substr(line, length(r) + 2) }
      FILENAME == ARGV[1] { cand[$0] = 1; next }
      FILENAME == ARGV[2] { p = rest($0, $1); if (p in cand) was[p] = $1; next }
      FILENAME == ARGV[3] { now[rest($0, $1)] = $1; next }
      FILENAME == ARGV[4] { newer[$0] = 1; next }
      END {
        for (p in cand) {
          cur = (p in now) ? now[p] : "gone"
          if (p in was) { if (was[p] != cur) print p }
          else if (full || cur == "gone" || (p in newer)) print p
        }
      }' "$work.cand" "$old" "$work.cur" "$work.newer" | sort
  fi
  rm -f "$work.cand" "$work.files" "$work.newer" "$work.cur"
}

# Keep the flow's own files out of `git status` so the reviewer and QA agents
# (told to include untracked files) do not see them and `git add -A` skips them.
ensure_git_exclude() {
  local exclude="$GIT_ROOT/.git/info/exclude" rel
  [ -d "$GIT_ROOT/.git" ] || return 0
  mkdir -p "$GIT_ROOT/.git/info" 2>/dev/null || return 0
  grep -q -x -F '.claude/flow/' "$exclude" 2>/dev/null || printf '.claude/flow/\n' >> "$exclude"
  rel=$(rel_to_root "$TASK_FOLDER")
  case $rel in
    .claude/plans/*) grep -q -x -F '.claude/plans/' "$exclude" 2>/dev/null || printf '.claude/plans/\n' >> "$exclude" ;;
  esac
}

now_utc() { date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date; }

# Agent families (bare names). Read-only agents may change nothing in the tree.
is_readonly_agent() {
  case $1 in dev-planner|dev-plan-critic|dev-reviewer|dev-qa-impact|dev-review-triager|dev-debugger) return 0 ;; esac
  return 1
}
is_writing_agent() {
  case $1 in dev-implementer|dev-fixer) return 0 ;; esac
  return 1
}
