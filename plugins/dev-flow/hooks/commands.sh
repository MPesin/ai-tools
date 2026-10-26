#!/usr/bin/env bash
# Command analysis for flow-guard.sh: splits a Bash or PowerShell command string
# into simple commands and denies the ones the flow forbids. Sourced, not run.
#
# Why not one regex over the whole string: `grep -rn "git commit" docs/` and
# `echo "remember to git push"` must pass, `git -C "my repo" push`,
# `git --no-pager push`, `cmd /c "git push"` and `wsl git push` must not.
#
# Pipeline: lowercase -> drop heredoc bodies -> replace quoted strings by Q<n>
# placeholders (contents kept) -> split on ; | & ( ) { } ` and newlines -> for
# each simple command skip VAR=x prefixes and wrappers (sudo, env, timeout...),
# resolve the command word and dispatch. An interpreter launcher (bash -c,
# pwsh -Command, wsl, eval...) has its quoted strings analysed as commands too,
# two levels deep.
#
# `deny` is defined by the sourcing script (prints the reason, exit 2).

# Drop heredoc bodies: everything after `<<WORD` up to the line that is WORD.
strip_heredocs() {
  local line delim='' re='<<-?[[:space:]]*["'"'"']?([A-Za-z_][A-Za-z0-9_]*)["'"'"']?'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$delim" ]; then
      [ "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')" = "$delim" ] && delim=''
      continue
    fi
    printf '%s\n' "$line"
    [[ $line =~ $re ]] && delim=${BASH_REMATCH[1]}
  done
}

# split_quotes TEXT -> DEQUOTED (quoted strings replaced by Q0, Q1, ...) and QUOTED[n] (their contents).
# A backslash-newline outside quotes becomes a space (line continuation).
split_quotes() {
  local s=$1 i=0 n=${#1} c q='' buf='' out=''
  QUOTED=()
  while [ $i -lt $n ]; do
    c=${s:$i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then
        out="${out}q${#QUOTED[@]}"
        QUOTED[${#QUOTED[@]}]=$buf
        buf=''; q=''
      elif [ "$q" = '"' ] && [ "$c" = '\' ]; then
        buf="$buf${s:$((i+1)):1}"; i=$((i+1))
      else
        buf="$buf$c"
      fi
    else
      case $c in
        \'|\") q=$c ;;
        \\)
          if [ "${s:$((i+1)):1}" = $'\n' ]; then out="$out "; else out="$out${s:$((i+1)):1}"; fi
          i=$((i+1)) ;;
        *) out="$out$c" ;;
      esac
    fi
    i=$((i+1))
  done
  if [ -n "$q" ]; then out="${out}q${#QUOTED[@]}"; QUOTED[${#QUOTED[@]}]=$buf; fi
  DEQUOTED=$out
}

# The command name of a word: a placeholder resolves to its quoted text
# ("C:\Program Files\Git\bin\git.exe" push), then basename, then .exe/.cmd/.bat dropped.
cmd_name() {
  local w=$1 re='^q([0-9]+)$'
  if [[ $w =~ $re ]]; then w=${QS[${BASH_REMATCH[1]}]}; w=$(lower "$w"); fi
  w=${w##*/}; w=${w##*\\}
  w=${w%.exe}; w=${w%.cmd}; w=${w%.bat}
  printf '%s' "$w"
}

is_option() { case $1 in -*) return 0 ;; esac; return 1; }

# check_command TEXT DEPTH
check_command() {
  local text=$1 depth=${2:-0} line
  local -a QS
  text=$(lower "${text:0:20000}")
  text=$(strip_heredocs <<< "$text")
  split_quotes "$text"
  QS=("${QUOTED[@]}")
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
    [ -n "$line" ] && check_simple "$line" "$depth"
  done <<< "$(printf '%s\n' "$DEQUOTED" | tr ';|&(){}`' '\n\n\n\n\n\n\n\n')"
}

# check_simple LINE DEPTH   (QS is the enclosing check_command's placeholder table)
check_simple() {
  local -a w a
  local line=$1 depth=$2 i=0 n cmd re='^[a-z_][a-z0-9_]*='
  read -r -a w <<< "$line"
  n=${#w[@]}
  while [ $i -lt $n ]; do
    cmd=$(cmd_name "${w[$i]}")
    if [[ $cmd =~ $re ]]; then i=$((i+1)); continue; fi
    case $cmd in
      sudo|doas|command|exec|builtin|nohup|time|nice|ionice|chronic|stdbuf|env|xargs|start-process|start|saps)
        i=$((i+1)); while [ $i -lt $n ] && is_option "${w[$i]}"; do i=$((i+1)); done; continue ;;
      timeout)
        i=$((i+1))
        while [ $i -lt $n ] && is_option "${w[$i]}"; do
          case ${w[$i]} in -k|-s|--kill-after|--signal) i=$((i+2)) ;; *) i=$((i+1)) ;; esac
        done
        i=$((i+1)); continue ;;   # the duration
    esac
    break
  done
  [ $i -lt $n ] || return 0
  a=("${w[@]:$((i+1))}")
  case $cmd in
    git)  check_git "${a[@]}" ;;
    gh)   check_gh "${a[@]}" ;;
    glab) check_glab "${a[@]}" ;;
    az)   check_az "${a[@]}" ;;
    dotnet|nuget|npm|yarn|pnpm|docker|cargo|twine|gem|helm|mvn|gradle|gradlew) check_publish "$cmd" "${a[@]}" ;;
    bash|sh|zsh|dash|ksh|fish|cmd|powershell|pwsh|wsl|eval|script|ssh|busybox|invoke-expression|iex|invoke-command|icm)
      [ "$depth" -ge 2 ] && return 0
      local rest="${a[*]}" q
      [ -n "$rest" ] && check_simple "$rest" "$depth"
      for q in "${QS[@]}"; do check_command "$q" $((depth+1)); done ;;
  esac
  return 0
}

check_git() {
  local -a a=("$@") rest
  local i=0 n=$# sub x
  while [ $i -lt $n ]; do
    case ${a[$i]} in
      -c|-C|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env|--attr-source) i=$((i+2)); continue ;;
      -*) i=$((i+1)); continue ;;
      *) break ;;
    esac
  done
  [ $i -lt $n ] || return 0
  sub=${a[$i]}
  rest=("${a[@]:$((i+1))}")
  case $sub in
    commit|push|checkout|restore|clean|rebase|merge|cherry-pick|revert|am|switch|filter-branch|filter-repo)
      deny "git $sub is not allowed during the flow: the user commits, pushes and discards changes. Delete $POINTER to switch the guards off." ;;
    stash)
      case ${rest[0]-} in list|show) ;; *) deny "git stash is not allowed during the flow (uncommitted work is the deliverable)." ;; esac ;;
    reset)
      for x in "${rest[@]}"; do case $x in --hard|--merge|--keep) deny "git reset $x is not allowed during the flow." ;; esac; done ;;
    branch)
      for x in "${rest[@]}"; do case $x in -d|-D|-f|-m|-M|--delete|--force|--move) deny "git branch $x is not allowed during the flow." ;; esac; done ;;
  esac
  return 0
}

# gh/glab api: deny anything that is not a plain GET
check_api_args() {
  local tool=$1; shift
  local x method='' next=0
  for x in "$@"; do
    if [ $next = 1 ]; then method=$x; next=0; continue; fi
    case $x in
      -X|--method) next=1 ;;
      -X*) method=${x#-X} ;;
      --method=*) method=${x#--method=} ;;
      -f|-F|--field|--raw-field|--input|--input=*|-f*|-F*) deny "$tool api with fields or input writes to the server; not allowed during the flow." ;;
    esac
  done
  [ -z "$method" ] || [ "$method" = get ] || deny "$tool api -X $method is not allowed during the flow."
  return 0
}

check_gh() {
  local grp=${1-} sub=${2-}
  case $grp in
    api) shift; check_api_args gh "$@"; return 0 ;;
    pr)       case $sub in view|list|diff|checks|status|'') return 0 ;; esac ;;
    issue)    case $sub in view|list|status|'') return 0 ;; esac ;;
    release)  case $sub in view|list|download|'') return 0 ;; esac ;;
    repo)     case $sub in view|list|clone|'') return 0 ;; esac ;;
    workflow) case $sub in view|list|'') return 0 ;; esac ;;
    run)      case $sub in view|list|watch|download|'') return 0 ;; esac ;;
    gist)     case $sub in view|list|clone|'') return 0 ;; esac ;;
    label|secret|variable|ssh-key|gpg-key|ruleset|project|cache|codespace)
              case $sub in list|view|'') return 0 ;; esac ;;
    *) return 0 ;;
  esac
  deny "gh $grp $sub posts, changes or publishes something outside the working tree; not allowed during the flow (the user does that)."
}

check_glab() {
  local grp=${1-} sub=${2-}
  case $grp in
    api) shift; check_api_args glab "$@"; return 0 ;;
    mr)      case $sub in view|list|diff|'') return 0 ;; esac ;;
    issue)   case $sub in view|list|'') return 0 ;; esac ;;
    release) case $sub in view|list|download|'') return 0 ;; esac ;;
    repo)    case $sub in view|list|clone|search|'') return 0 ;; esac ;;
    ci)      case $sub in view|list|status|lint|trace|'') return 0 ;; esac ;;
    *) return 0 ;;
  esac
  deny "glab $grp $sub posts or changes something outside the working tree; not allowed during the flow."
}

check_az() {
  local a1=${1-} a2=${2-} a3=${3-} a4=${4-} x method='' next=0
  case "$a1 $a2" in
    "repos pr")
      case $a3 in list|show|'') return 0 ;; reviewer|work-item|policy) case $a4 in list|show|'') return 0 ;; esac ;; esac ;;
    "repos create"|"repos delete"|"repos update"|"repos import") ;;
    "repos policy") case $a3 in list|show|'') return 0 ;; esac ;;
    "repos ref")    case $a3 in list|'') return 0 ;; esac ;;
    "boards work-item")
      case $a3 in show|'') return 0 ;; relation) case $a4 in list|show|'') return 0 ;; esac ;; esac ;;
    "boards iteration"|"boards area")
      case $a4 in list|show|'') return 0 ;; esac ;;
    "pipelines run") ;;
    "pipelines build")   case $a3 in queue|cancel) ;; *) return 0 ;; esac ;;
    "pipelines release") case $a3 in create) ;; *) return 0 ;; esac ;;
    "pipelines variable"|"pipelines variable-group") case $a3 in create|update|delete) ;; *) return 0 ;; esac ;;
    "devops invoke")
      for x in "$@"; do
        if [ $next = 1 ]; then method=$x; next=0; continue; fi
        case $x in --http-method) next=1 ;; --http-method=*) method=${x#--http-method=} ;; esac
      done
      case $method in ''|get) return 0 ;; esac ;;
    *) return 0 ;;
  esac
  deny "az $a1 $a2 $a3 changes something in Azure DevOps; not allowed during the flow (the user updates work items and PRs)."
}

check_publish() {
  local cmd=$1 a1=${2-} a2=${3-} x
  case "$cmd $a1 $a2" in
    "dotnet nuget push"|"dotnet nuget delete") deny "dotnet nuget $a2 publishes a package; not allowed during the flow." ;;
    "yarn npm publish") deny "yarn npm publish is not allowed during the flow." ;;
  esac
  case "$cmd $a1" in
    "nuget push"|"nuget delete"|"npm publish"|"npm unpublish"|"npm deprecate"|"yarn publish"|"pnpm publish"|"docker push"|"cargo publish"|"twine upload"|"gem push"|"helm push")
      deny "$cmd $a1 publishes outside the repo; not allowed during the flow." ;;
  esac
  case $cmd in
    mvn)  for x in "$@"; do [ "$x" = deploy ] && deny "mvn deploy publishes artifacts; not allowed during the flow."; done ;;
    gradle|gradlew) for x in "$@"; do case $x in publish*) deny "gradle $x publishes artifacts; not allowed during the flow." ;; esac; done ;;
  esac
  return 0
}

# MCP tools: deny names that read like writes to an external system.
check_mcp_tool() {
  local name=${1#mcp__} tool
  tool=$(lower "${name#*__}")
  local re='(^|_)(create|update|delete|remove|add|post|comment|reply|resolve|unresolve|merge|push|submit|vote|approve|request_changes|assign|unassign|close|reopen|edit|set|transition|publish|upload|write|send|move|archive|lock|unlock|dismiss|fork|star|rename|put|patch|insert|append|complete)(_|$)'
  [[ $tool =~ $re ]] && deny "MCP tool $1 looks like it writes to an external system; not allowed during the flow (the user posts and updates). Delete $POINTER to switch the guards off."
  return 0
}
