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

# The hook's working directory, resolved.
hook_cwd() {
  local dir
  dir=$(json_field cwd)
  [ -z "$dir" ] && dir=$PWD
  cd "$(normalize_path "$dir")" 2>/dev/null && pwd
}

# A flow lives on a branch: its pointers sit in <project>/.claude/flow/<branch key>/,
# the branch name with / as __ and characters a file name cannot carry as _, so
# switching branches parks the flow and brings it back. Pointers written straight
# into .claude/flow/ (older skills, or a project outside git) are still read, after
# the branch's own. Sets FLOW_BRANCH ('' when detached or outside git) and
# FLOW_BRANCH_KEY ('' when there is no branch).
flow_branch() {   # DIR
  FLOW_IN_GIT=''; FLOW_BRANCH=''; FLOW_BRANCH_KEY=''
  [ -n "$1" ] && [ "$(git -C "$1" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || return 0
  FLOW_IN_GIT=1
  FLOW_BRANCH=$(git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null | tr -d '\r')
  FLOW_BRANCH_KEY=$(printf '%s' "$FLOW_BRANCH" | sed 's,/,__,g; s,[\\:*?"<>|[:space:]],_,g')
}

# main and master (DEV_FLOW_PROTECTED_BRANCHES overrides, space separated) carry no
# flow: the skills ask for a branch first, and the hooks refuse a pointer or a
# stage agent there. A detached HEAD has no branch to live on either. Outside git
# there is no branch to protect.
is_protected_branch() {
  [ -n "$FLOW_IN_GIT" ] || return 1
  [ -z "$FLOW_BRANCH" ] && return 0
  case " ${DEV_FLOW_PROTECTED_BRANCHES:-main master} " in *" $FLOW_BRANCH "*) return 0 ;; esac
  return 1
}

# The nearest <dir>/.claude/flow directory, with or without a pointer (for the list
# of flows parked on other branches). Sets FLOW_ROOT.
find_any_flow_root() {
  local dir
  dir=$(hook_cwd) || return 1
  flow_branch "$dir"
  while :; do
    if [ -d "$dir/.claude/flow" ]; then FLOW_ROOT="$dir/.claude/flow"; return 0; fi
    [ -e "$dir/.git" ] && return 1
    [ -z "$dir" ] || [ "$dir" = "/" ] && return 1
    dir=${dir%/*}
    [ -z "$dir" ] && dir=/
  done
}

# Walk up from the hook's cwd to the first <dir>/.claude/flow that holds a pointer
# (in the branch's directory or at the top). The walk ends at the first directory
# that holds a .git (a directory in the main checkout, a file in a worktree or
# submodule): a flow belongs to one checkout, so a session in a worktree (Claude
# Code puts them under <repo>/.claude/worktrees/<name>) must not pick up the main
# checkout's pointer above it. Sets FLOW_ROOT (and FLOW_BRANCH*); no subshell, so
# the caller keeps them.
find_flow_root() {
  local dir name
  dir=$(hook_cwd) || return 1
  flow_branch "$dir"
  while :; do
    for name in $POINTER_NAMES; do
      if [ -n "$FLOW_BRANCH_KEY" ] && [ -f "$dir/.claude/flow/$FLOW_BRANCH_KEY/$name" ] || [ -f "$dir/.claude/flow/$name" ]; then
        FLOW_ROOT="$dir/.claude/flow"
        return 0
      fi
    done
    [ -e "$dir/.git" ] && return 1
    [ -z "$dir" ] || [ "$dir" = "/" ] && return 1
    dir=${dir%/*}
    [ -z "$dir" ] && dir=/
  done
}

# pointer_path NAME: the path of pointer NAME under FLOW_ROOT, the branch's own
# when it exists, else the top-level one (which may not exist either).
pointer_path() {
  if [ -n "$FLOW_BRANCH_KEY" ] && [ -f "$FLOW_ROOT/$FLOW_BRANCH_KEY/$1" ]; then
    printf '%s' "$FLOW_ROOT/$FLOW_BRANCH_KEY/$1"
  else
    printf '%s' "$FLOW_ROOT/$1"
  fi
}

# The first pointer of POINTER_NAMES, branch directory before the top level. Sets
# POINTER (with FLOW_ROOT and FLOW_BRANCH*); false when there is none.
find_flow_pointer() {
  local name p
  find_flow_root || return 1
  for name in $POINTER_NAMES; do
    p=$(pointer_path "$name")
    [ -f "$p" ] && { POINTER=$p; return 0; }
  done
  return 1
}

# Flows parked on other branches of this checkout: "key (pointer, status: s)" lines.
parked_flows() {
  local d key name folder
  [ -d "$FLOW_ROOT" ] || return 0
  for d in "$FLOW_ROOT"/*/; do
    [ -d "$d" ] || continue
    key=${d%/}; key=${key##*/}
    [ "$key" = "$FLOW_BRANCH_KEY" ] && continue
    for name in current planning; do
      [ -f "$d$name" ] || continue
      folder=$(normalize_path "$(head -n 1 "$d$name" | tr -d '\r')")
      printf '%s (%s, status: %s)\n' "$key" "$name" "$(frontmatter_value status "$folder/plan.md")"
      break
    done
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
  find_flow_pointer || exit 0
  POINTER_NAME=${POINTER##*/}
  FLOW_DIR=${POINTER%/*}
  PROJECT_DIR=${FLOW_ROOT%/.claude/flow}
  SESSION_ID=$(json_field session_id)
  if [ "$POINTER_NAME" = planning ] && planning_stale "$POINTER"; then
    # Beside a current pointer the parked task carries on; the Stop hook sweeps.
    if [ "$HOOK_EVENT" != Stop ] && [ -f "$(pointer_path current)" ]; then
      POINTER=$(pointer_path current); POINTER_NAME=current; FLOW_DIR=${POINTER%/*}
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
    [ "$STALE_STATUS" = done ] || STALE_RESUME=" The task itself continues with /dev-flow:dev-implement $STALE_FOLDER/plan.md (its Intake writes current)."
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

# Files the flow itself writes; never a violation.
is_flow_path() {   # REL_PATH relative to GIT_ROOT
  local p
  p=$(path_key "$1")
  case $p in .claude/flow|.claude/flow/*) return 0 ;; esac
  if path_under "$TASK_FOLDER" "$GIT_ROOT"; then
    path_under "$GIT_ROOT/$1" "$TASK_FOLDER" && return 0
  fi
  return 1
}

# A line per changed/untracked path with a content hash, flow files excluded.
# Comparing two snapshots names exactly the files that changed in between.
tree_snapshot() {
  local line path hash
  git -C "$GIT_ROOT" --no-optional-locks -c core.quotePath=false status --porcelain -uall 2>/dev/null \
    | head -n 5000 | while IFS= read -r line; do
      path=${line:3}
      case $path in *" -> "*) path=${path##* -> } ;; esac
      is_flow_path "$path" && continue
      if [ -f "$GIT_ROOT/$path" ]; then
        hash=$(git -C "$GIT_ROOT" hash-object -- "$path" 2>/dev/null)
        printf '%s %s\n' "${hash:-unreadable}" "$path"
      else
        printf 'gone %s\n' "$path"
      fi
    done | sort
}

# Paths present in exactly one of two snapshot files.
snapshot_diff() {   # OLD NEW
  cat "$1" "$2" | sort | uniq -u | cut -d' ' -f2- | sort -u
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
