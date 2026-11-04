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
  if [[ $w =~ $re ]]; then w=${QS[${BASH_REMATCH[1]}]}; fi
  w=$(lower "$w")
  w=${w##*/}; w=${w##*\\}
  w=${w%.exe}; w=${w%.cmd}; w=${w%.bat}
  printf '%s' "$w"
}

# A word lowercased, placeholders resolved: for comparing subcommand names.
# Arguments keep their case (git -d is not git -D; -b is not -B), so only the
# names of commands and subcommands, which Windows users may type in any case,
# are compared lowercased.
word_lower() { lower "$(word_text "$1")"; }

is_option() { case $1 in -*) return 0 ;; esac; return 1; }

# check_command TEXT DEPTH
check_command() {
  local text=$1 depth=${2:-0} line
  local -a QS
  text=${text:0:20000}
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
  local line=$1 depth=$2 i=0 n cmd re='^[A-Za-z_][A-Za-z0-9_]*='
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

# The text of a word: a Q<n> placeholder resolves to its quoted contents.
word_text() {
  local w=$1 re='^q([0-9]+)$'
  [[ $w =~ $re ]] && w=${QS[${BASH_REMATCH[1]}]}
  printf '%s' "$w"
}

# git subcommands that are never an alias and need no check, so the common
# commands do not pay for a `git config` lookup.
GIT_PLAIN_SUBS=' status diff log show blame add branch fetch grep ls-files ls-tree rev-parse rev-list config describe remote tag init worktree mv rm notes reflog shortlog cat-file for-each-ref symbolic-ref hash-object check-ignore var version help apply diff-tree diff-files diff-index name-rev merge-base show-ref count-objects fsck gc archive bisect submodule sparse-checkout lfs '

check_git() {
  local -a a=("$@") rest words
  local i=0 n=$# sub x v alias
  GIT_ALIAS_DEPTH=${GIT_ALIAS_DEPTH:-0}
  while [ $i -lt $n ]; do
    case ${a[$i]} in
      -c|--config-env)
        # An alias defined on the command line could run any subcommand.
        v=$(word_lower "${a[$((i+1))]-}")
        case $v in alias.*) deny "git ${a[$i]} alias.* is not allowed during the flow: run the git command itself." ;; esac
        i=$((i+2)); continue ;;
      --config-env=[Aa][Ll][Ii][Aa][Ss].*) deny "git --config-env alias.* is not allowed during the flow: run the git command itself." ;;
      -C|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--attr-source) i=$((i+2)); continue ;;
      -*) i=$((i+1)); continue ;;
      *) break ;;
    esac
  done
  [ $i -lt $n ] || return 0
  sub=$(word_lower "${a[$i]}")
  rest=("${a[@]:$((i+1))}")
  case $sub in
    commit)
      # The main session commits after each stage. A subagent does not: parallel
      # implementers share one index, so one's `git add` would sweep in another's
      # half-done files. --amend would rewrite a commit made before the flow, or
      # one a reviewer already saw; git takes any prefix of it (--am, --amen).
      [ -n "${AGENT_TYPE-}" ] && deny "git commit is not allowed in a subagent ($AGENT_TYPE): the main session commits each stage's files after the stage. Leave your changes uncommitted and report them."
      for x in "${rest[@]}"; do
        case $x in --am|--am=*|--ame|--ame=*|--amen|--amen=*|--amend|--amend=*) deny "git commit --amend is not allowed during the flow: it rewrites an existing commit. Make a new commit." ;; esac
      done ;;
    push)
      # The main session commits each stage, so it may also push them when the
      # user asks; a subagent never does. A push that rewrites or deletes refs on
      # the remote, or publishes a tag, is refused to everyone.
      main_only push "the main session pushes, when the user asks"
      check_push_args "${rest[@]}" ;;
    pull)
      # Keeping the branch in step with the remote is the main session's, on
      # request: a merge or a fast-forward. A rebase rewrites the local commits.
      main_only pull "the main session pulls, when the user asks"
      check_pull_args "${rest[@]}" ;;
    merge|revert|cherry-pick)
      # Each only adds commits (or, with --abort, stops what it started).
      main_only "$sub" "the main session runs it, when the user asks" ;;
    checkout) main_only checkout "the main session runs it, when the user asks"; check_checkout_args "${rest[@]}" ;;
    switch)   main_only switch "the main session runs it, when the user asks";   check_switch_args "${rest[@]}" ;;
    restore)  main_only restore "the main session runs it, when the user asks";  check_restore_args "${rest[@]}" ;;
    clean|rebase|am|filter-branch|filter-repo|commit-tree|update-ref|replace)
      deny "git $sub is not allowed during the flow: it rewrites history or discards changes in the tree the flow works on. If the user wants it, they run it in their own terminal. Do not clear the flow (/dev-flow:clear-flow) to get past this: that abandons the run." ;;
    stash)
      # Stashing hides work and brings it back; drop and clear lose it.
      x=$(word_lower "${rest[0]-}")
      case $x in
        list|show) ;;
        drop|clear) deny "git stash $x is not allowed during the flow: it discards stashed work. Leave the stash; the user drops it." ;;
        *) main_only "stash $x" "the main session stashes and unstashes, when the user asks" ;;
      esac ;;
    reset)
      # --soft followed by a commit rewrites the last commit like --amend.
      for x in "${rest[@]}"; do case $x in --hard|--merge|--keep|--soft) deny "git reset $x is not allowed during the flow." ;; esac; done ;;
    branch)
      check_branch_args "${rest[@]}" ;;
    *)
      # An alias from git config (`git ci` for commit): check what it runs.
      case $GIT_PLAIN_SUBS in *" $sub "*) return 0 ;; esac
      [ "$GIT_ALIAS_DEPTH" -lt 3 ] || return 0
      alias=$(git -C "${GIT_ROOT:-.}" config --get "alias.$sub" 2>/dev/null) || return 0
      [ -n "$alias" ] || return 0
      GIT_ALIAS_DEPTH=$((GIT_ALIAS_DEPTH + 1))
      case $alias in
        '!'*) check_command "${alias#!}" 1 ;;   # a shell alias: read it as a command
        *) read -r -a words <<< "$alias"; check_git "${words[@]}" "${rest[@]}" ;;
      esac
      GIT_ALIAS_DEPTH=$((GIT_ALIAS_DEPTH - 1)) ;;
  esac
  return 0
}

# main_only SUB WHY: a git subcommand the main session may run when the user
# asks, and a subagent never (it would move the tree or the branch under the
# other agents, and the main session is where the user's request arrives).
main_only() {
  [ -z "${AGENT_TYPE-}" ] && return 0
  deny "git $1 is not allowed in a subagent ($AGENT_TYPE): $2. Leave it and report."
}

# The arguments of a main-session `git push`: refuse what rewrites or deletes refs
# on the remote, and what publishes a tag (a tag push is what release pipelines
# listen for). git takes any unambiguous prefix of a long option (--forc, --del),
# and short options cluster (-uf); -o/--push-option and --repo take a value.
check_push_args() {
  local x v name s remote='' src
  while [ $# -gt 0 ]; do
    x=$1; shift
    v=$(word_text "$x")
    case $v in
      --)
        continue ;;
      --*)
        name=${v#--}; name=${name%%=*}
        [ -n "$name" ] || continue
        for s in force force-with-lease force-if-includes delete mirror prune; do
          case $s in "$name"*) deny "git push --$name is not allowed during the flow: it overwrites or deletes branches on the remote. Push without it; the flow never rewrites history, so a plain push is enough." ;; esac
        done
        for s in tags follow-tags; do
          case $s in "$name"*) deny "git push --$name is not allowed during the flow: pushing a tag publishes a release. Push the branch alone; the user pushes tags." ;; esac
        done
        case $name in push-option|repo|receive-pack|exec) [ "$v" = "--$name" ] && shift ;; esac ;;
      -*)
        s=${v#-}; s=${s%%o*}
        case $s in *f*|*d*) deny "git push $v is not allowed during the flow: -f forces and -d deletes branches on the remote. Push without it." ;; esac
        [ "$v" = -o ] && shift ;;
      +*) deny "git push $v is not allowed during the flow: a + refspec forces the update on the remote. Push without the +." ;;
      :*) deny "git push $v is not allowed during the flow: an empty source deletes the branch on the remote." ;;
      *)
        # The first bare word is the remote; the rest are refspecs.
        if [ -z "$remote" ]; then remote=$v; continue; fi
        src=${v%%:*}
        case $v in *refs/tags/*) deny "git push $v is not allowed during the flow: pushing a tag publishes a release. Push the branch alone; the user pushes tags." ;; esac
        [ -n "$src" ] && git -C "${GIT_ROOT:-.}" show-ref --verify --quiet "refs/tags/$src" 2>/dev/null \
          && deny "git push $v is not allowed during the flow: $src is a tag, and pushing a tag publishes a release. Push the branch alone; the user pushes tags." ;;
    esac
  done
  return 0
}

# A main-session `git pull`: a merge or a fast-forward, never a rebase. The
# repo's pull.rebase setting makes a plain `git pull` rebase too.
check_pull_args() {
  local x v explicit=0 conf
  for x in "$@"; do
    v=$(word_text "$x")
    case $v in
      --rebase|--rebase=*|-r|-[A-Za-z]*r*) deny "git pull $v is not allowed during the flow: a rebase rewrites the local commits. Use git pull --no-rebase (a merge) or git pull --ff-only." ;;
      --no-rebase|--ff-only|--ff|--no-ff) explicit=1 ;;
    esac
  done
  [ $explicit = 1 ] && return 0
  conf=$(lower "$(git -C "${GIT_ROOT:-.}" config --get pull.rebase 2>/dev/null)")
  case $conf in ''|false|no|off|0) return 0 ;; esac
  deny "git pull would rebase here (pull.rebase is $conf in this repo's config), and a rebase rewrites the local commits. Use git pull --no-rebase (a merge) or git pull --ff-only."
}

# explicit_paths WORDS...: true when the words name files or folders and none
# of them sweeps the whole tree (., .., :/, *, or no path at all).
explicit_paths() {
  local x v n=0
  [ $# -gt 0 ] || return 1
  for x in "$@"; do
    v=$(word_text "$x")
    case $v in .|..|./|'*'|:/|:/*|'') return 1 ;; esac
    n=$((n+1))
  done
  [ $n -gt 0 ]
}
RESTORE_HINT='To bring back files the user asked for, name them: git restore <paths> (or git checkout -- <paths>); git restore --staged <paths> only unstages.'

# A main-session `git restore`: unstaging is always fine; restoring the working
# tree discards changes, so it needs explicit paths. -s/--source takes a value
# (and -S, the short --staged, is not told apart from it here: use --staged).
check_restore_args() {
  local x v staged=0 worktree=0 skip=0
  local -a paths=()
  for x in "$@"; do
    v=$(word_text "$x")
    if [ $skip = 1 ]; then skip=0; continue; fi
    case $v in
      --) ;;
      --staged) staged=1 ;;
      --worktree|-W|-[A-Za-z]*W*) worktree=1 ;;
      -S) deny "git restore -S is read as --source here and would need a tree; write --staged to unstage. $RESTORE_HINT" ;;
      -s|--source) skip=1 ;;
      --source=*) ;;
      -p|--patch) deny "git restore $v is interactive; not usable here." ;;
      -*) ;;
      *) paths+=("$x") ;;
    esac
  done
  if [ $staged = 1 ] && [ $worktree = 0 ]; then return 0; fi
  explicit_paths "${paths[@]+"${paths[@]}"}" \
    || deny "git restore without explicit paths (., :/, *, or none) would discard every change in the tree the flow works on; not allowed during the flow. $RESTORE_HINT"
  return 0
}

# A main-session `git checkout`: a new branch at HEAD (-b, not -B, which resets
# an existing one) or explicit paths after `--`; a branch switch moves the tree
# the flow works on and is refused.
check_checkout_args() {
  local x v i=0 n=$# create=0 dashdash=0
  local -a a=("$@") paths=()
  while [ $i -lt $n ]; do
    v=$(word_text "${a[$i]}")
    if [ $dashdash = 1 ]; then paths+=("${a[$i]}"); i=$((i+1)); continue; fi
    case $v in
      --) dashdash=1 ;;
      -b) create=1; i=$((i+1)) ;;
      -B|--orphan|--detach|-p|--patch|-f|--force|-m|--merge|--ours|--theirs)
        deny "git checkout $v is not allowed during the flow: it resets a branch, moves HEAD or discards changes. A new branch at HEAD is git checkout -b <name> or git switch -c <name>; $RESTORE_HINT" ;;
      -*) ;;
      *) [ $create = 1 ] || deny "git checkout $v switches branches, which moves the tree the flow works on; not allowed during the flow. A new branch at HEAD is git switch -c <name>; $RESTORE_HINT" ;;
    esac
    i=$((i+1))
  done
  [ $dashdash = 0 ] && return 0
  explicit_paths "${paths[@]+"${paths[@]}"}" \
    || deny "git checkout -- without explicit paths (., :/, *) would discard every change in the tree the flow works on; not allowed during the flow. $RESTORE_HINT"
  return 0
}

# A main-session `git switch`: only a new branch at HEAD (-c, not -C, which
# resets an existing one).
check_switch_args() {
  local x v create=0
  for x in "$@"; do
    v=$(word_text "$x")
    case $v in
      -c|--create) create=1 ;;
      -C|--force-create|--orphan|-d|--detach|-f|--force|--discard-changes|-m|--merge)
        deny "git switch $v is not allowed during the flow: it resets a branch, moves HEAD or discards changes. A new branch at HEAD is git switch -c <name>." ;;
    esac
  done
  [ $create = 1 ] || deny "git switch <branch> moves the tree the flow works on; not allowed during the flow. A new branch at HEAD is git switch -c <name>; the user switches branches."
  return 0
}

# `git branch`: deleting a merged branch (-d) and renaming (-m) are the main
# session's, on request; the forcing forms (-D, -M, -f, -C) rewrite a ref and
# are refused to everyone. Short options cluster (-df), so letters are checked.
check_branch_args() {
  local x v l i
  for x in "$@"; do
    v=$(word_text "$x")
    case $v in
      --force|--force=*) deny "git branch $v is not allowed during the flow: it overwrites a branch." ;;
      --delete|--move|--copy) main_only "branch $v" "the main session deletes, renames and copies branches, when the user asks" ;;
      --*) ;;
      -?*)
        l=${v#-}
        for ((i = 0; i < ${#l}; i++)); do
          case ${l:$i:1} in
            D|M|C|f) deny "git branch $v is not allowed during the flow: it overwrites a branch or deletes an unmerged one (-${l:$i:1})." ;;
            d|m|c) main_only "branch $v" "the main session deletes, renames and copies branches, when the user asks" ;;
          esac
        done ;;
    esac
  done
  return 0
}

# A word with every q<n> placeholder in it replaced by its quoted text
# (query='...' is the word query=q0): for reading an argument's whole value.
expand_quotes() {
  local v=$1 i
  for ((i = ${#QS[@]} - 1; i >= 0; i--)); do v=${v//q$i/${QS[$i]}}; done
  printf '%s' "$v"
}

# gh/glab api: deny anything that is not a plain GET. The exception is the
# graphql endpoint, which is always a POST with the query in a field: a read
# query is allowed, a document holding a mutation is not; --input (the query
# in a file) cannot be read here and is refused.
check_api_args() {
  local tool=$1; shift
  local x v method='' next='' endpoint='' re='(^|[^A-Za-z0-9_])[Mm][Uu][Tt][Aa][Tt][Ii][Oo][Nn]([^A-Za-z0-9_]|$)'
  local -a fields=()
  for x in "$@"; do
    v=$(word_text "$x")
    if [ -n "$next" ]; then
      case $next in method) method=$(lower "$v") ;; field) fields+=("$x") ;; esac
      next=''; continue
    fi
    case $v in
      -X|--method) next=method ;;
      -X*) method=$(lower "${v#-X}") ;;
      --method=*) method=$(lower "${v#--method=}") ;;
      -f|-F|--field|--raw-field) next=field ;;
      -f*|-F*) fields+=("$x") ;;
      --field=*|--raw-field=*) fields+=("$x") ;;
      --input|--input=*) fields+=(--input) ;;
      -H|--header|-p|--preview|-q|--jq|-t|--template|--hostname|--cache) next=skip ;;
      -*) ;;
      *) [ -n "$endpoint" ] || endpoint=$(lower "$v") ;;
    esac
  done
  if [ "$endpoint" = graphql ]; then
    [ -z "$method" ] || [ "$method" = post ] || deny "$tool api graphql -X $method is not a GraphQL request."
    for x in "${fields[@]+"${fields[@]}"}"; do
      [ "$x" = --input ] && deny "$tool api graphql --input reads the query from a file, which the flow cannot check for a mutation; pass the query with -f query='...' instead."
      [[ $(expand_quotes "$x") =~ $re ]] && deny "$tool api graphql with a mutation writes to the server; not allowed during the flow (the user posts and updates). A query that only reads is allowed."
    done
    return 0
  fi
  [ ${#fields[@]} -eq 0 ] || deny "$tool api with fields or input writes to the server; not allowed during the flow."
  [ -z "$method" ] || [ "$method" = get ] || deny "$tool api -X $method is not allowed during the flow."
  return 0
}

# Opening the PR is the one write to a hosting platform the main session may
# make, when the user asks (the human-review gate offers it): it publishes the
# commits the flow made, nothing else. Commenting, replying, reviewing, merging
# and work items stay the user's; a subagent opens nothing.
pr_create() {   # TOOL WHAT
  [ -z "${AGENT_TYPE-}" ] && return 0
  deny "$1 $2 is not allowed in a subagent ($AGENT_TYPE): the main session opens the PR, when the user asks. Leave it and report."
}

check_gh() {
  local grp sub
  grp=$(word_lower "${1-}"); sub=$(word_lower "${2-}")
  case $grp in
    api) shift; check_api_args gh "$@"; return 0 ;;
    pr)       case $sub in view|list|diff|checks|status|'') return 0 ;; create) pr_create gh 'pr create'; return 0 ;; esac ;;
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
  deny "gh $grp $sub posts, changes or publishes something outside the working tree; not allowed during the flow (the user does that; the main session only pushes and opens the PR). Give the user the text or the command to run instead."
}

check_glab() {
  local grp sub
  grp=$(word_lower "${1-}"); sub=$(word_lower "${2-}")
  case $grp in
    api) shift; check_api_args glab "$@"; return 0 ;;
    mr)      case $sub in view|list|diff|'') return 0 ;; create) pr_create glab 'mr create'; return 0 ;; esac ;;
    issue)   case $sub in view|list|'') return 0 ;; esac ;;
    release) case $sub in view|list|download|'') return 0 ;; esac ;;
    repo)    case $sub in view|list|clone|search|'') return 0 ;; esac ;;
    ci)      case $sub in view|list|status|lint|trace|'') return 0 ;; esac ;;
    *) return 0 ;;
  esac
  deny "glab $grp $sub posts or changes something outside the working tree; not allowed during the flow (the user does that; the main session only pushes and opens the MR). Give the user the text or the command to run instead."
}

check_az() {
  local a1 a2 a3 a4 x v method='' next=0
  a1=$(word_lower "${1-}"); a2=$(word_lower "${2-}"); a3=$(word_lower "${3-}"); a4=$(word_lower "${4-}")
  case "$a1 $a2" in
    "repos pr")
      case $a3 in
        list|show|'') return 0 ;;
        create)
          pr_create az 'repos pr create'
          # --auto-complete merges the PR once its policies pass: that is a merge.
          for x in "$@"; do
            if [ $next = 1 ]; then next=0; [ "$(word_lower "$x")" = false ] || deny "az repos pr create --auto-complete merges the PR when its policies pass; not allowed during the flow (the user merges). Create it without --auto-complete."; continue; fi
            v=$(word_lower "$x")
            case $v in --auto-complete) next=1 ;; --auto-complete=false) ;; --auto-complete=*) deny "az repos pr create --auto-complete merges the PR when its policies pass; not allowed during the flow (the user merges). Create it without --auto-complete." ;; esac
          done
          [ $next = 1 ] && deny "az repos pr create --auto-complete merges the PR when its policies pass; not allowed during the flow (the user merges). Create it without --auto-complete."
          return 0 ;;
        reviewer|work-item|policy) case $a4 in list|show|'') return 0 ;; esac ;;
      esac ;;
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
        v=$(word_lower "$x")
        if [ $next = 1 ]; then method=$v; next=0; continue; fi
        case $v in --http-method) next=1 ;; --http-method=*) method=${v#--http-method=} ;; esac
      done
      case $method in ''|get) return 0 ;; esac ;;
    *) return 0 ;;
  esac
  deny "az $a1 $a2 $a3 changes something in Azure DevOps; not allowed during the flow (the user updates work items and PRs; the main session only pushes and opens the PR). Give the user the text or the command to run instead."
}

check_publish() {
  local cmd=$1 a1 a2 x
  a1=$(word_lower "${2-}"); a2=$(word_lower "${3-}")
  case "$cmd $a1 $a2" in
    "dotnet nuget push"|"dotnet nuget delete") deny "dotnet nuget $a2 publishes a package; not allowed during the flow." ;;
    "yarn npm publish") deny "yarn npm publish is not allowed during the flow." ;;
  esac
  case "$cmd $a1" in
    "nuget push"|"nuget delete"|"npm publish"|"npm unpublish"|"npm deprecate"|"yarn publish"|"pnpm publish"|"docker push"|"cargo publish"|"twine upload"|"gem push"|"helm push")
      deny "$cmd $a1 publishes outside the repo; not allowed during the flow." ;;
  esac
  case $cmd in
    mvn)  for x in "$@"; do [ "$(word_lower "$x")" = deploy ] && deny "mvn deploy publishes artifacts; not allowed during the flow."; done ;;
    gradle|gradlew) for x in "$@"; do case $(word_lower "$x") in publish*) deny "gradle $x publishes artifacts; not allowed during the flow." ;; esac; done ;;
  esac
  return 0
}

# MCP servers that only touch this machine (files, a browser, the editor): their
# writes are not posts. The main session is not write-limited, so they pass for
# it; a subagent's writes stay under the name check below. DEV_FLOW_LOCAL_MCP
# adds server names (space-separated, matched as substrings).
mcp_local_server() {
  local s=$1 extra
  case $s in
    *filesystem*|*playwright*|*puppeteer*|*chrome-devtools*|*browser*|*desktop-commander*|*sequential-thinking*|*memory*|ide) return 0 ;;
  esac
  for extra in ${DEV_FLOW_LOCAL_MCP-}; do
    case $s in *"$(lower "$extra")"*) return 0 ;; esac
  done
  return 1
}

# MCP tools: deny names that read like writes to an external system. Opening a
# PR/MR (create_pull_request, create_merge_request, repo_create_pull_request) is
# the main session's, as with gh pr create; anything longer
# (create_pull_request_with_copilot) is not that.
check_mcp_tool() {
  local name=${1#mcp__} tool server
  tool=$(lower "${name#*__}"); server=$(lower "${name%%__*}")
  local re='(^|_)(create|update|delete|remove|add|post|comment|reply|resolve|unresolve|merge|push|submit|vote|approve|request_changes|assign|unassign|close|reopen|edit|set|transition|publish|upload|write|send|move|archive|lock|unlock|dismiss|fork|star|rename|put|patch|insert|append|complete)(_|$)'
  local open_pr='(^|_)create_(pull|merge)_request$'
  if [[ $tool =~ $open_pr ]]; then pr_create "MCP tool" "$1"; return 0; fi
  [ -z "${AGENT_TYPE-}" ] && mcp_local_server "$server" && return 0
  [[ $tool =~ $re ]] && deny "MCP tool $1 looks like it writes to an external system; not allowed during the flow (the user posts and updates; the main session only pushes and opens the PR). Give the user the text to post instead. A server that only touches this machine can be named in DEV_FLOW_LOCAL_MCP."
  return 0
}
