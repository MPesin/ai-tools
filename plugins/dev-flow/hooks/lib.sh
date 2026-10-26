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

# Walk up from the hook's cwd to the first .claude/flow/<name> pointer.
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
    [ -z "$dir" ] || [ "$dir" = "/" ] && return 1
    dir=${dir%/*}
    [ -z "$dir" ] && dir=/
  done
}

# Sets POINTER, POINTER_NAME, FLOW_DIR, PROJECT_DIR, GIT_ROOT, TASK_FOLDER,
# AGENT_TYPE (bare name, plugin prefix stripped), AGENT_ID, SESSION_ID.
# Exits 0 (hook inactive) when no pointer or the task folder is gone.
load_task_folder() {
  POINTER_NAMES=${1:-"current planning"}
  POINTER=$(find_flow_pointer) || exit 0
  POINTER_NAME=${POINTER##*/}
  FLOW_DIR=${POINTER%/*}
  PROJECT_DIR=${FLOW_DIR%/.claude/flow}
  TASK_FOLDER=$(normalize_path "$(head -n 1 "$POINTER" | tr -d '\r')")
  [ -n "$TASK_FOLDER" ] && [ -d "$TASK_FOLDER" ] || exit 0
  GIT_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
  GIT_ROOT=$(normalize_path "${GIT_ROOT:-$PROJECT_DIR}")
  AGENT_TYPE=$(json_field agent_type)
  AGENT_TYPE=${AGENT_TYPE##*:}
  AGENT_ID=$(json_field agent_id)
  SESSION_ID=$(json_field session_id)
}

# Value of a frontmatter key; CR, trailing spaces and surrounding quotes removed.
frontmatter_value() {
  sed -n '/^---/,/^---/p' "$TASK_FOLDER/plan.md" 2>/dev/null | tr -d '\r' \
    | sed -n "s/^$1:[[:space:]]*//p" | head -n 1 | sed 's/[[:space:]]*$//' \
    | sed "s/^\"\(.*\)\"\$/\1/; s/^'\(.*\)'\$/\1/"
}

plan_has_packages() {
  grep -E -q '^###[[:space:]]+P[0-9A-Za-z]+[[:space:]]*-' "$TASK_FOLDER/plan.md" 2>/dev/null
}

# Owns patterns of one package, one per line (comma or whitespace separated in the plan).
package_owns() {
  sed -n "/^###[[:space:]]*$1[[:space:]]*-/,/^##/p" "$TASK_FOLDER/plan.md" 2>/dev/null \
    | tr -d '\r' | sed -n 's/^[[:space:]]*Owns:[[:space:]]*//p' | head -n 1 \
    | tr -d '`' | tr ', ' '\n\n' | sed 's/^\.\///' | grep -v '^[[:space:]]*$'
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
