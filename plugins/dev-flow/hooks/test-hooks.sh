#!/usr/bin/env bash
# Hook tests. Runs on Linux, macOS and Windows (Git Bash) with the system bash:
#   bash hooks/test-hooks.sh          (exit 0 = all passed)
# Each case feeds a hook the JSON Claude Code would send and asserts allow / deny /
# block / output. On Windows the paths in the JSON are converted to the C:\ form
# Claude Code sends there; elsewhere they are used as they are.

H=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d) || exit 1
trap 'cd /; rm -rf "$T"' EXIT
cd "$T" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p .claude/flow task/specs src/foo src/bar tests
printf 'base\n' > src/foo/alpha.txt; printf 'base\n' > src/bar/beta.txt; printf 'base\n' > src/shared.txt
git add -A && git commit -q -m base

# What Claude Code sends as a path on this OS.
hp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
# Backslashes doubled for JSON.
jp() { local p; p=$(hp "$1"); printf '%s' "${p//\\/\\\\}"; }
CW=$(jp "$T")

pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); printf 'FAIL: %s\n      exit=%s out=[%s] err=[%s]\n' "$1" "$rc" "$out" "$err"; }
run()  { # run HOOK JSON -> rc, out, err
  out=$(printf '%s' "$2" | bash "$H/$1" 2>"$T/.err"); rc=$?; err=$(cat "$T/.err")
}
expect_allow() { run "$2" "$3"; if [ $rc -eq 0 ]; then ok; else bad "$1 (expected allow)"; fi; }
expect_deny()  { run "$2" "$3"; if [ $rc -eq 2 ] && [ -n "$err" ]; then ok; else bad "$1 (expected deny)"; fi; }
expect_block() { run "$2" "$3"; if [ $rc -eq 0 ] && case $out in *'"decision":"block"'*) true ;; *) false ;; esac; then ok; else bad "$1 (expected block)"; fi; }
expect_pass()  { run "$2" "$3"; if [ $rc -eq 0 ] && [ -z "$out" ]; then ok; else bad "$1 (expected silent pass)"; fi; }
expect_out()   { run "$2" "$3"; if [ $rc -eq 0 ] && case $out in *"$4"*) true ;; *) false ;; esac; then ok; else bad "$1 (expected output containing: $4)"; fi; }
assert() { if eval "$2"; then ok; else fail=$((fail+1)); printf 'FAIL: %s\n' "$1"; fi; }

# JSON builders. Every hook input carries the session id Claude Code sends; a
# subagent's carries its parent session's. SID is the session the input comes
# from: s, the session that owns the test flow, unless a case sets another.
SID=s
bash_json() { # AGENT_TYPE COMMAND [DESCRIPTION] [TOOL]   (AID: the agent id, x unless a case sets one)
  local a=''; [ -n "$1" ] && a='"agent_type":"'$1'","agent_id":"'${AID:-x}'",'
  printf '{"session_id":"%s","cwd":"%s",%s"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s","description":"%s"}}' "$SID" "$CW" "$a" "${4:-Bash}" "$2" "${3:-}"
}
write_json() { # AGENT_TYPE PATH [TOOL] [AGENT_ID]
  local a=''; [ -n "$1" ] && a='"agent_type":"'$1'","agent_id":"'${4:-x}'",'
  local key=file_path; [ "${3:-}" = NotebookEdit ] && key=notebook_path
  printf '{"session_id":"%s","cwd":"%s",%s"tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' "$SID" "$CW" "$a" "${3:-Write}" "$key" "$(jp "$2")"
}
post_json() { # AGENT_TYPE TOOL TEXT  (PostToolUse: TEXT is the command, or the path for the file tools)
  local a='' key=command; [ -n "$1" ] && a='"agent_type":"'$1'","agent_id":"x",'
  case $2 in Edit|Write) key=file_path ;; NotebookEdit) key=notebook_path ;; esac
  printf '{"session_id":"%s","cwd":"%s",%s"hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"%s":"%s"},"tool_response":{"ok":true}}' "$SID" "$CW" "$a" "$2" "$key" "$3"
}
mcp_json() { printf '{"session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":{"x":1}}' "$SID" "$CW" "$1"; }
agent_json() { printf '{"session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":{"subagent_type":"%s","prompt":"x","description":"d"}}' "$SID" "$CW" "${2:-Agent}" "$1"; }
agent_json_untyped() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Agent","tool_input":{"prompt":"x","description":"d"}}' "$SID" "$CW"; }
start_json() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SubagentStart","agent_id":"%s","agent_type":"%s"}' "$SID" "$CW" "$1" "$2"; }
stop_json()  { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SubagentStop","agent_id":"%s","agent_type":"%s","stop_hook_active":%s}' "$SID" "$CW" "$1" "$2" "${3:-false}"; }
main_stop_json() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$SID" "$CW"; }
session_json()   { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$SID" "$CW" "$1"; }

# A pointer as the skills and the claim hook leave it: the task folder's path,
# then the session it belongs to (s unless given).
ptr() { # NAME FOLDER [SESSION]
  printf '%s\nsession: %s\n' "$(hp "$2")" "${3:-s}" > ".claude/flow/$1"
}

plan() { # STATUS [PACKAGES=0|1]
  if [ "${2:-0}" = 1 ]; then
    printf -- '---\ntask: t\nsource: manual\nmode: full\nstatus: %s\nreview_round: 0\nbase: main\n---\n## Steps\n### P0 - Shared\nOwns: src/shared.txt\nDepends on: none\n- [ ] zero\n### P1 - Foo\nOwns: src/foo/**, tests/foo*\nDepends on: P0\n- [ ] one\n### P2 - Bar\nOwns: `src/bar/**`\nDepends on: P0\n- [ ] two\n' "$1" > task/plan.md
  else
    printf -- '---\ntask: t\nsource: manual\nmode: full\nstatus: %s\nreview_round: 0\nbase: main\n---\n## Steps\n- [ ] one\n' "$1" > task/plan.md
  fi
}
plan implementing

echo "== lib: path normalization"
out=$(printf '' | bash -c 'source "$1"; normalize_path "C:\\Users\\me\\proj\\"; echo; normalize_path "c:/a//b/"; echo; normalize_path "/x/y"' _ "$H/lib.sh")
assert "normalize_path handles drive letters, backslashes, doubled and trailing slashes" '[ "$out" = "/c/Users/me/proj
/c/a/b
/x/y" ]'
out=$(printf '' | bash -c 'source "$0"; json_decode "a\\nb \\\"q\\\" C:\\\\x"' "$H/lib.sh")
assert "json_decode handles \\n, \\\" and \\\\" '[ "$out" = "a
b \"q\" C:\\x" ]'

echo "== guard inactive without a pointer"
expect_allow "no pointer: git commit passes" flow-guard.sh "$(bash_json '' 'git commit -m x')"
expect_deny  "no pointer: spawning dev-implementer (Intake skipped)" flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
expect_deny  "no pointer: spawning dev-reviewer"                    flow-guard.sh "$(agent_json dev-flow:dev-reviewer)"
assert "deny names dev-implement"  'case $err in *"/dev-flow:dev-implement"*) true;; *) false;; esac'
expect_allow "no pointer: dev-qa-impact runs standalone"            flow-guard.sh "$(agent_json dev-flow:dev-qa-impact)"
expect_allow "no pointer: dev-planner (harden before Intake)"       flow-guard.sh "$(agent_json dev-flow:dev-planner)"
expect_allow "no pointer: dev-debugger (diagnosis without a fix)"  flow-guard.sh "$(agent_json dev-debug:dev-debugger)"
expect_allow "no pointer: general-purpose agent"                    flow-guard.sh "$(agent_json general-purpose)"
expect_allow "no pointer: Agent call without subagent_type"         flow-guard.sh "$(agent_json_untyped)"

echo "== guard: a pointer that names no task is a finding, not an off switch"
ptr current /nowhere/at/all
expect_deny  "dangling current: spawn dev-implementer"   flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny names the pointer and the folder" 'case $err in *".claude/flow/current"*"/nowhere/at/all"*) true;; *) false;; esac'
expect_allow "dangling current: dev-qa-impact not gated" flow-guard.sh "$(agent_json dev-flow:dev-qa-impact)"
ptr current ''
expect_deny  "empty current: spawn dev-fixer"            flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
assert "deny says it names nothing" 'case $err in *"names '"'"'nothing'"'"'"*) true;; *) false;; esac'
mkdir -p noplan; ptr current "$T/noplan"
expect_deny  "current folder without plan.md: spawn dev-reviewer" flow-guard.sh "$(agent_json dev-flow:dev-reviewer)"
assert "deny names plan.md" 'case $err in *"no plan.md"*) true;; *) false;; esac'

ptr current "$T/task"

echo "== guard: git"
expect_allow "main session: git commit"         flow-guard.sh "$(bash_json '' 'git commit -m x')"
expect_allow "main session: git add -- paths && git commit" flow-guard.sh "$(bash_json '' 'git add -- src/a.cs src/b.cs && git commit -m \"P1 - Foo\"')"
expect_deny  "main session: git commit --amend" flow-guard.sh "$(bash_json '' 'git commit --amend --no-edit')"
expect_deny  "implementer: git commit"          flow-guard.sh "$(bash_json dev-flow:dev-implementer 'git commit -m x')"
assert "deny says the main session commits" 'case $err in *"main session commits"*) true;; *) false;; esac'
expect_deny  "fixer: git add . && git commit"   flow-guard.sh "$(bash_json dev-flow:dev-fixer 'git add . && git commit -am x')"
expect_deny  "general-purpose subagent: git commit" flow-guard.sh "$(bash_json general-purpose 'git commit -m x')"
expect_deny  "git push"                         flow-guard.sh "$(bash_json '' 'git push origin main')"
expect_deny  "git --no-pager push"              flow-guard.sh "$(bash_json '' 'git --no-pager push')"
expect_deny  "git -C \"my repo\" push"          flow-guard.sh "$(bash_json '' 'git -C \"my repo\" push')"
expect_deny  "git -c x=y commit --amend"        flow-guard.sh "$(bash_json '' 'git -c user.name=x commit --amend -m y')"
expect_deny  "git commit --amen (prefix of --amend)" flow-guard.sh "$(bash_json '' 'git commit --amen -m y')"
expect_deny  "git commit --am"                  flow-guard.sh "$(bash_json '' 'git commit --am --no-edit')"
expect_allow "git commit --author (not --amend)" flow-guard.sh "$(bash_json '' 'git commit --author=\"a <a@b>\" -m y')"
expect_deny  "subagent: git -c alias.c=commit c" flow-guard.sh "$(bash_json dev-flow:dev-implementer 'git -c alias.c=commit c -m x')"
expect_deny  "git -c \"alias.p=push\" p"        flow-guard.sh "$(bash_json '' 'git -c \"alias.p=push\" p')"
git config alias.ci commit; git config alias.pp '!git push origin'; git config alias.st status
expect_deny  "subagent: config alias ci = commit" flow-guard.sh "$(bash_json dev-flow:dev-fixer 'git ci -m x')"
expect_allow "main session: config alias ci = commit" flow-guard.sh "$(bash_json '' 'git ci -m x')"
expect_deny  "shell alias pp = !git push"       flow-guard.sh "$(bash_json '' 'git pp')"
expect_allow "alias st = status"                flow-guard.sh "$(bash_json '' 'git st')"
git config --unset alias.ci; git config --unset alias.pp; git config --unset alias.st
expect_deny  "git commit-tree"                  flow-guard.sh "$(bash_json dev-flow:dev-implementer 'git commit-tree HEAD^{tree} -m x')"
expect_deny  "git update-ref"                   flow-guard.sh "$(bash_json '' 'git update-ref refs/heads/main HEAD~1')"
expect_deny  "git reset --soft"                 flow-guard.sh "$(bash_json '' 'git reset --soft HEAD~1')"
expect_deny  "git pull"                         flow-guard.sh "$(bash_json '' 'git pull --rebase')"
expect_deny  "git reset --hard"                 flow-guard.sh "$(bash_json '' 'git reset --hard HEAD~1')"
expect_deny  "git checkout -- ."                flow-guard.sh "$(bash_json '' 'git checkout -- .')"
expect_deny  "git restore ."                    flow-guard.sh "$(bash_json '' 'git restore .')"
expect_deny  "git stash"                        flow-guard.sh "$(bash_json '' 'git stash')"
expect_deny  "git clean -fdx"                   flow-guard.sh "$(bash_json '' 'git clean -fdx')"
expect_deny  "git branch -D"                    flow-guard.sh "$(bash_json '' 'git branch -D feature')"
expect_deny  "chained: npm test && git push"    flow-guard.sh "$(bash_json '' 'npm test && git push')"
expect_deny  "subshell: \$(git push)"           flow-guard.sh "$(bash_json '' 'echo $(git push)')"
expect_deny  "line continuation: git \\<newline> push" flow-guard.sh "$(bash_json '' 'git \\\n push origin')"
expect_deny  "wrapper: sudo env X=1 git push"   flow-guard.sh "$(bash_json '' 'sudo env X=1 git push')"
expect_deny  "wrapper: timeout 10 git push"     flow-guard.sh "$(bash_json '' 'timeout -k 5 10 git push')"
expect_deny  "launcher: bash -c \"git push\""   flow-guard.sh "$(bash_json '' 'bash -c \"cd x && git push\"')"
expect_deny  "launcher: cmd /c \"git push\""    flow-guard.sh "$(bash_json '' 'cmd /c \"git push\"')"
expect_deny  "launcher: wsl git push"           flow-guard.sh "$(bash_json '' 'wsl git push')"
expect_deny  "quoted git path (Windows)"        flow-guard.sh "$(bash_json '' '\"C:\\\\Program Files\\\\Git\\\\bin\\\\git.exe\" push')"
expect_deny  "PowerShell tool: git push"        flow-guard.sh "$(bash_json '' '& git.exe push' '' PowerShell)"
expect_deny  "PowerShell: Git Push (case)"      flow-guard.sh "$(bash_json '' 'Git Push origin' '' PowerShell)"
expect_allow "git status && git diff"           flow-guard.sh "$(bash_json '' 'git status && git diff')"
expect_allow "git stash list"                   flow-guard.sh "$(bash_json '' 'git stash list')"
expect_allow "git reset (unstage)"              flow-guard.sh "$(bash_json '' 'git reset src/foo/alpha.txt')"
expect_allow "git branch (list)"                flow-guard.sh "$(bash_json '' 'git branch -a')"
expect_allow "git log, description says push"  flow-guard.sh "$(bash_json '' 'git log --oneline -5' 'check whether git push already happened')"
expect_allow "grep \"git push\" docs/"          flow-guard.sh "$(bash_json '' 'grep -rn \"git push\" docs/')"
expect_allow "echo remember to git push"        flow-guard.sh "$(bash_json '' 'echo remember to git push later')"
expect_allow "heredoc body mentions git push"   flow-guard.sh "$(bash_json '' 'cat >> notes.md <<EOF\ndid not run git push\nEOF')"
expect_allow "git push as a literal word arg"   flow-guard.sh "$(bash_json '' 'rg \"git push\" -l')"

echo "== guard: hosting platforms and publishing"
expect_deny  "gh pr comment"      flow-guard.sh "$(bash_json '' 'gh pr comment 5 -b hi')"
expect_deny  "gh pr create"       flow-guard.sh "$(bash_json '' 'gh pr create --fill')"
expect_deny  "gh pr merge"        flow-guard.sh "$(bash_json '' 'gh pr merge 5')"
expect_deny  "gh api POST"        flow-guard.sh "$(bash_json '' 'gh api -X POST repos/o/r/issues -f title=x')"
expect_allow "gh api GET"         flow-guard.sh "$(bash_json '' 'gh api repos/o/r/pulls/5/comments')"
expect_allow "gh pr view/diff"    flow-guard.sh "$(bash_json '' 'gh pr view 5 && gh pr diff 5')"
expect_deny  "az repos pr create" flow-guard.sh "$(bash_json '' 'az repos pr create --title x')"
expect_deny  "az boards wi update" flow-guard.sh "$(bash_json '' 'az boards work-item update --id 1 --state Done')"
expect_allow "az boards wi show"  flow-guard.sh "$(bash_json '' 'az boards work-item show --id 1 --org https://dev.azure.com/o')"
expect_allow "az repos pr list"   flow-guard.sh "$(bash_json '' 'az repos pr list')"
expect_deny  "glab mr create"     flow-guard.sh "$(bash_json '' 'glab mr create --fill')"
expect_deny  "dotnet nuget push"  flow-guard.sh "$(bash_json '' 'dotnet nuget push x.nupkg -k key')"
expect_deny  "npm publish"        flow-guard.sh "$(bash_json '' 'npm publish')"
expect_deny  "docker push"        flow-guard.sh "$(bash_json '' 'docker push img:1')"
expect_allow "dotnet build/test"  flow-guard.sh "$(bash_json '' 'dotnet build src/Foo --no-dependencies && dotnet test tests/Foo.Tests')"
expect_allow "npm test"           flow-guard.sh "$(bash_json '' 'npm test')"

echo "== guard: MCP tools"
expect_deny  "mcp github create_pull_request"     flow-guard.sh "$(mcp_json mcp__github__create_pull_request)"
expect_deny  "mcp azure-devops wit_update_work_item" flow-guard.sh "$(mcp_json mcp__azure-devops__wit_update_work_item)"
expect_deny  "mcp github add_issue_comment"       flow-guard.sh "$(mcp_json mcp__github__add_issue_comment)"
expect_allow "mcp github get_pull_request"        flow-guard.sh "$(mcp_json mcp__github__get_pull_request)"
expect_allow "mcp azure-devops wit_get_work_item" flow-guard.sh "$(mcp_json mcp__azure-devops__wit_get_work_item)"
expect_allow "mcp search_code"                    flow-guard.sh "$(mcp_json mcp__github__search_code)"

echo "== guard: spawning a stage agent needs that stage's status"
expect_allow "implementing: spawn dev-implementer"              flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
expect_allow "implementing: bare agent name"                    flow-guard.sh "$(agent_json dev-implementer)"
expect_allow "implementing: legacy Task tool"                   flow-guard.sh "$(agent_json dev-flow:dev-implementer Task)"
expect_deny  "implementing: spawn dev-reviewer"                 flow-guard.sh "$(agent_json dev-flow:dev-reviewer)"
expect_deny  "implementing: spawn dev-fixer"                    flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
expect_deny  "implementing: spawn dev-review-triager"           flow-guard.sh "$(agent_json dev-flow:dev-review-triager)"
expect_allow "implementing: dev-qa-impact is not gated"         flow-guard.sh "$(agent_json dev-flow:dev-qa-impact)"
printf -- '---\ntask: t\r\nstatus: implementing   \r\n---\r\n- [ ] one\r\n' > task/plan.md
expect_allow "CRLF and trailing spaces in status"               flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
printf -- '---\ntask: t\nstatus: "implementing"\n---\n- [ ] one\n' > task/plan.md
expect_allow "double-quoted status"                             flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
printf -- "---\ntask: t\nstatus: 'implementing'\n---\n- [ ] one\n" > task/plan.md
expect_allow "single-quoted status"                             flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
printf -- '---\nTask: t\nStatus: implementing\n---\n- [ ] one\n' > task/plan.md
expect_allow "capitalised Status: key"                          flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
plan approved
expect_deny  "approved: spawn dev-implementer (status not set)" flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny names the current and the wanted status" 'case $err in *"status: approved"*implementing*) true;; *) false;; esac'
plan draft
expect_deny  "draft: spawn dev-implementer"                     flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
plan reviewing
expect_allow "reviewing: spawn dev-reviewer"                    flow-guard.sh "$(agent_json dev-flow:dev-reviewer)"
expect_allow "reviewing: spawn dev-fixer"                       flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
expect_deny  "reviewing: spawn dev-implementer"                 flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
plan human-review
expect_allow "human-review: spawn dev-fixer"                    flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
expect_allow "human-review: spawn dev-review-triager"           flow-guard.sh "$(agent_json dev-flow:dev-review-triager)"
expect_allow "human-review: spawn dev-qa-impact (panel button)" flow-guard.sh "$(agent_json dev-flow:dev-qa-impact)"
expect_deny  "human-review: spawn dev-reviewer"                 flow-guard.sh "$(agent_json dev-flow:dev-reviewer)"
plan qa-impact
expect_allow "qa-impact: spawn dev-qa-impact"                   flow-guard.sh "$(agent_json dev-flow:dev-qa-impact)"
expect_deny  "qa-impact: spawn dev-fixer"                       flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
plan done
expect_allow "done with current still present: dev-qa-impact"  flow-guard.sh "$(agent_json dev-flow:dev-qa-impact)"
plan blocked
expect_deny  "blocked: spawn dev-fixer"                         flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
expect_deny  "blocked: spawn dev-reviewer"                      flow-guard.sh "$(agent_json dev-flow:dev-reviewer)"
assert "deny at blocked names reviewing" 'case $err in *"status: blocked"*reviewing*) true;; *) false;; esac'
expect_allow "any status: dev-planner"                          flow-guard.sh "$(agent_json dev-flow:dev-planner)"
expect_allow "any status: dev-plan-critic"                      flow-guard.sh "$(agent_json dev-flow:dev-plan-critic)"
expect_allow "any status: dev-debugger"                         flow-guard.sh "$(agent_json dev-debug:dev-debugger)"
expect_allow "any status: Explore"                              flow-guard.sh "$(agent_json Explore)"
plan implementing

echo "== guard: write allowances"
expect_deny  "reviewer writes src/foo/alpha.txt"              flow-guard.sh "$(write_json dev-flow:dev-reviewer "$T/src/foo/alpha.txt")"
expect_deny  "reviewer writes review-notes.md in src"    flow-guard.sh "$(write_json dev-flow:dev-reviewer "$T/src/review-notes.md")"
expect_deny  "reviewer edits notebook"                   flow-guard.sh "$(write_json dev-flow:dev-reviewer "$T/src/x.ipynb" NotebookEdit)"
expect_allow "reviewer writes task/review-1.md"          flow-guard.sh "$(write_json dev-flow:dev-reviewer "$T/task/review-1.md")"
expect_allow "reviewer writes task/review-1.md via Edit" flow-guard.sh "$(write_json dev-flow:dev-reviewer "$T/task/review-1.md" Edit)"
expect_deny  "critic writes plan.md"                     flow-guard.sh "$(write_json dev-flow:dev-plan-critic "$T/task/plan.md")"
expect_allow "critic writes plan-critique.md"            flow-guard.sh "$(write_json dev-flow:dev-plan-critic "$T/task/plan-critique.md")"
expect_deny  "qa-impact writes qa-impact.md elsewhere"   flow-guard.sh "$(write_json dev-flow:dev-qa-impact "$T/other/qa-impact.md")"
expect_allow "qa-impact writes task/qa-impact.md"        flow-guard.sh "$(write_json dev-flow:dev-qa-impact "$T/task/qa-impact.md")"
expect_deny  "triager writes src"                        flow-guard.sh "$(write_json dev-flow:dev-review-triager "$T/src/foo/alpha.txt")"
expect_allow "triager writes human-review.md"            flow-guard.sh "$(write_json dev-flow:dev-review-triager "$T/task/human-review.md")"
expect_deny  "planner writes src"                        flow-guard.sh "$(write_json dev-flow:dev-planner "$T/src/foo/alpha.txt")"
expect_allow "planner writes task/specs/prd.md"          flow-guard.sh "$(write_json dev-flow:dev-planner "$T/task/specs/prd.md")"
expect_allow "debugger writes task/diagnosis.md"         flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/task/diagnosis.md")"
expect_allow "debugger writes task/diagnosis-2.md"       flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/task/diagnosis-2.md")"
expect_allow "debugger writes task/debug/repro.sh"       flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/task/debug/repro.sh")"
expect_deny  "debugger writes src (no instrumentation)"  flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/src/foo/alpha.txt")"
assert "deny says never instrument" 'case $err in *instrument*) true;; *) false;; esac'
expect_deny  "debugger writes src/debug/x.sh"            flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/src/debug/x.sh")"
expect_deny  "debugger writes plan.md"                   flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/task/plan.md")"
expect_deny  "debugger writes notes.md"                  flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/task/notes.md")"
expect_deny  "debugger writes diagnosis.md elsewhere"    flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/src/diagnosis.md")"
expect_allow "bare agent name (user-level copy) still matched" flow-guard.sh "$(write_json dev-planner "$T/task/plan.md")"
expect_deny  "fixer edits plan.md"                       flow-guard.sh "$(write_json dev-flow:dev-fixer "$T/task/plan.md")"
expect_deny  "fixer edits verify.log"                    flow-guard.sh "$(write_json dev-flow:dev-fixer "$T/task/verify.log")"
expect_allow "fixer edits src"                           flow-guard.sh "$(write_json dev-flow:dev-fixer "$T/src/foo/alpha.txt")"
expect_allow "fixer writes notes.md"                     flow-guard.sh "$(write_json dev-flow:dev-fixer "$T/task/notes.md")"
expect_allow "implementer (no packages) edits src"       flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/foo/alpha.txt")"
expect_allow "implementer (no packages) edits plan.md"   flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/task/plan.md")"
expect_deny  "implementer edits verify.log"              flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/task/verify.log")"
expect_allow "main session edits src during dev-implement" flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_allow "Explore agent untouched"                   flow-guard.sh "$(write_json Explore "$T/src/foo/alpha.txt")"

echo "== guard: work packages (Owns)"
plan implementing 1
expect_deny  "implementer without claim is refused"      flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/foo/alpha.txt" Write p1)"
printf 'P1\n' > .claude/flow/claim-p1
expect_allow "P1 edits src/foo/alpha.txt"                     flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/foo/alpha.txt" Write p1)"
expect_allow "P1 edits tests/foo-tests.txt (glob)"         flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/tests/foo-tests.txt" Write p1)"
expect_deny  "P1 edits src/bar/beta.txt (P2 owns)"           flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/bar/beta.txt" Write p1)"
expect_deny  "P1 edits src/shared.txt (P0 owns)"          flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/shared.txt" Write p1)"
expect_deny  "P1 edits plan.md"                          flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/task/plan.md" Edit p1)"
expect_deny  "P1 edits notes.md with Edit (must append)" flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/task/notes.md" Edit p1)"
expect_allow "P1 writes its claim file"                  flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/.claude/flow/claim-p1" Write p1)"
printf 'P2\n' > .claude/flow/claim-p2
expect_allow "P2 edits src/bar/beta.txt (backticked Owns)"   flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/bar/beta.txt" Write p2)"
printf 'all\n' > .claude/flow/claim-p3
expect_allow "claim all edits anything"                  flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/shared.txt" Write p3)"
printf -- '---\ntask: t\nstatus: implementing\n---\n## Steps\n### P1 - Braces\nOwns: src/{foo,bar}/**, tests/{foo,bar}-*\n- [ ] one\n### P2 - Rest\nOwns: src/shared.txt\n- [ ] two\n' > task/plan.md
printf 'P1\n' > .claude/flow/claim-p4
expect_allow "Owns with {a,b}: first alternative"        flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/foo/alpha.txt" Write p4)"
expect_allow "Owns with {a,b}: second alternative"       flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/bar/beta.txt" Write p4)"
expect_allow "Owns with {a,b}: second pattern"           flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/tests/bar-x.txt" Write p4)"
expect_deny  "Owns with {a,b}: outside both"             flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/src/shared.txt" Write p4)"
assert "deny lists the expanded patterns" 'case $err in *"src/foo/**"*"src/bar/**"*) true;; *) false;; esac'
rm -f .claude/flow/claim-*

echo "== SubagentStart"
expect_out  "implementer start injects context + claim instruction" flow-context.sh "$(start_json i1 dev-flow:dev-implementer)" "claim-i1"
assert "start marker and snapshot written"  '[ -f .claude/flow/start-i1 ] && [ -f .claude/flow/snap-i1 ]'
assert ".git/info/exclude has .claude/flow/" 'grep -q -x -F ".claude/flow/" .git/info/exclude'
expect_out  "reviewer start says read-only"  flow-context.sh "$(start_json r1 dev-flow:dev-reviewer)" "read-only"
expect_out  "debugger start names debug/"    flow-context.sh "$(start_json d1 dev-debug:dev-debugger)" "task/debug/"
assert "debugger snapshot written"            '[ -f .claude/flow/snap-d1 ]'
expect_pass "Explore start is silent"        flow-context.sh "$(start_json e1 Explore)"

echo "== SubagentStop: evidence and bookkeeping"
plan implementing 1
printf 'P2\n' > .claude/flow/claim-i2
run flow-context.sh "$(start_json i2 dev-flow:dev-implementer)"
printf '[P1] $ make -C src/foo build\nok\n' >> task/verify.log
expect_block "P2 stops with no [P2] block in verify.log (P1's does not count)" flow-verify-stop.sh "$(stop_json i2 dev-flow:dev-implementer)"
printf '[P2] $ make -C src/bar build\nBuild succeeded.\n' >> task/verify.log
expect_block "P2 stops with no [P2] notes"      flow-verify-stop.sh "$(stop_json i2 dev-flow:dev-implementer)"
printf '[P2] step two: make build ok\n' >> task/notes.md
expect_pass  "P2 stops cleanly"                 flow-verify-stop.sh "$(stop_json i2 dev-flow:dev-implementer)"
assert "markers cleaned for i2" '[ ! -f .claude/flow/claim-i2 ] && [ ! -f .claude/flow/start-i2 ]'
plan implementing
rm -f task/notes.md .claude/flow/claim-i1
run flow-context.sh "$(start_json i1 dev-flow:dev-implementer)"; sleep 1.1
expect_block "single implementer: verify.log not updated this run" flow-verify-stop.sh "$(stop_json i1 dev-flow:dev-implementer)"
printf '$ make test\nok\n' >> task/verify.log
expect_block "single implementer: unchecked steps, no notes" flow-verify-stop.sh "$(stop_json i1 dev-flow:dev-implementer)"
printf 'step one skipped: reason\n' > task/notes.md
expect_pass  "single implementer: explained in notes"      flow-verify-stop.sh "$(stop_json i1 dev-flow:dev-implementer)"
run flow-context.sh "$(start_json f1 dev-flow:dev-fixer)"; sleep 1.1
expect_block "fixer: stale verify.log"   flow-verify-stop.sh "$(stop_json f1 dev-flow:dev-fixer)"
printf '$ make test\nok\n' >> task/verify.log
expect_pass  "fixer: fresh verify.log"   flow-verify-stop.sh "$(stop_json f1 dev-flow:dev-fixer)"
expect_pass  "stop_hook_active: never blocks"              flow-verify-stop.sh "$(stop_json i9 dev-flow:dev-fixer true)"

echo "== SubagentStop: working-tree violations"
run flow-context.sh "$(start_json r2 dev-flow:dev-reviewer)"
printf 'reviewer edit\n' >> src/foo/alpha.txt
expect_block "reviewer changed a source file (via any means)" flow-verify-stop.sh "$(stop_json r2 dev-flow:dev-reviewer)"
assert "violation logged" 'grep -q "dev-reviewer (r2): changed outside its allowance: src/foo/alpha.txt" task/violations.md'
assert "block names the file" 'case $out in *src/foo/alpha.txt*) true;; *) false;; esac'
git checkout -q -- src/foo/alpha.txt; rm -f task/violations.md
run flow-context.sh "$(start_json r3 dev-flow:dev-reviewer)"
printf '| F1 | Low | x | y | z | w |\n' > task/review-1.md
printf 'obj\n' > .claude/flow/scratch
expect_pass "reviewer wrote only review-1.md and flow files" flow-verify-stop.sh "$(stop_json r3 dev-flow:dev-reviewer)"
rm -f .claude/flow/scratch task/review-1.md
run flow-context.sh "$(start_json d2 dev-debug:dev-debugger)"
printf 'print(x)\n' >> src/foo/alpha.txt
expect_block "debugger instrumented a source file" flow-verify-stop.sh "$(stop_json d2 dev-debug:dev-debugger)"
assert "debugger violation logged" 'grep -q "dev-debugger (d2): changed outside its allowance: src/foo/alpha.txt" task/violations.md'
git checkout -q -- src/foo/alpha.txt; rm -f task/violations.md
run flow-context.sh "$(start_json d3 dev-debug:dev-debugger)"
mkdir -p task/debug; printf 'Confidence: High\n' > task/diagnosis.md; printf 'out\n' > task/debug/repro.out
expect_pass "debugger wrote only diagnosis.md and debug/" flow-verify-stop.sh "$(stop_json d3 dev-debug:dev-debugger)"
rm -rf task/debug task/diagnosis.md
plan implementing 1
printf 'P1\n' > .claude/flow/claim-i4
run flow-context.sh "$(start_json i4 dev-flow:dev-implementer)"
printf 'p1 edit\n' >> src/foo/alpha.txt            # own package
printf 'p2 edit\n' >> src/bar/beta.txt            # a parallel implementer's package: not a violation
printf 'stray\n' > src/stray.txt               # outside every package: violation
printf '[P1] $ make -C src/foo build\nok\n' >> task/verify.log
printf '[P1] done\n' >> task/notes.md
expect_block "implementer: file outside every Owns is reported" flow-verify-stop.sh "$(stop_json i4 dev-flow:dev-implementer)"
assert "only the stray file is named" 'case $out in *src/stray.txt*) case $out in *src/bar/beta.txt*) false;; *) true;; esac;; *) false;; esac'
git checkout -q -- src; rm -f src/stray.txt task/violations.md task/notes.md

echo "== SubagentStart/Stop: a tree with thousands of untracked files"
# An untracked, unignored cache (graphify-out and the like) once made the snapshot
# spawn a process per file: over 600 s on Windows, and the agent stalled. Start and
# stop now take a fixed number of git processes, counted through a shim on PATH.
mkdir -p cache/out; i=0; while [ $i -lt 2000 ]; do printf '{"n":%d}' $i > cache/out/$i.json; i=$((i+1)); done
REAL_GIT=$(command -v git)
mkdir -p "$T/shim"
printf '#!/bin/sh\necho x >> "%s/git-calls"\nexec "%s" "$@"\n' "$T" "$REAL_GIT" > "$T/shim/git"; chmod +x "$T/shim/git"
: > "$T/git-calls"
PATH="$T/shim:$PATH" run flow-context.sh "$(start_json r5 dev-flow:dev-reviewer)"
assert "every untracked file is in the snapshot, hashed" '[ "$(grep -c " cache/out/" .claude/flow/snap-r5)" -eq 2000 ] && ! grep -q -e "^unreadable" -e "^gone" .claude/flow/snap-r5'
assert "no scratch or partial snapshot files left" '[ -z "$(ls -A .claude/flow | grep -e "^\.snap-" -e "^\.cmp-" -e "\.tmp$")" ]'
printf 'changed\n' > cache/out/1234.json
PATH="$T/shim:$PATH" expect_block "reviewer changed one untracked file among thousands" flow-verify-stop.sh "$(stop_json r5 dev-flow:dev-reviewer)"
assert "only that file is named" 'case $out in *"cache/out/1234.json"*) case $out in *"cache/out/1235.json"*) false;; *) true;; esac;; *) false;; esac'
assert "start and stop ran a handful of git processes, not one per file" '[ "$(wc -l < "$T/git-calls")" -lt 20 ]'
rm -rf cache task/violations.md
# git that cannot hash at all: the snapshot gives up after a bounded number of
# retries instead of one process per file.
mkdir -p cache; i=0; while [ $i -lt 100 ]; do printf '%d\n' $i > cache/$i.json; i=$((i+1)); done
mkdir -p "$T/badgit"
printf '#!/bin/sh\necho x >> "%s/git-calls"\ncase "$*" in *hash-object*) exit 128 ;; esac\nexec "%s" "$@"\n' "$T" "$REAL_GIT" > "$T/badgit/git"; chmod +x "$T/badgit/git"
: > "$T/git-calls"
PATH="$T/badgit:$PATH" run flow-context.sh "$(start_json r10 dev-flow:dev-reviewer)"
assert "a failing hasher marks files unreadable" '[ "$(grep -c "^unreadable cache/" .claude/flow/snap-r10)" -eq 100 ]'
assert "and stops retrying after a few attempts" '[ "$(wc -l < "$T/git-calls")" -lt 30 ]'
rm -rf cache .claude/flow/snap-r10 .claude/flow/start-r10
run flow-context.sh "$(start_json r6 dev-flow:dev-reviewer)"; rm -f .claude/flow/snap-r6
printf 'changed\n' >> src/foo/alpha.txt
expect_out  "no snapshot (start hook cut off by its timeout): stop says the check did not run" flow-verify-stop.sh "$(stop_json r6 dev-flow:dev-reviewer)" "working-tree check did not run"
git checkout -q -- src

echo "== SubagentStart/Stop: paths with spaces, commits meanwhile, the snapshot limit"
BASE_SHA=$(git rev-parse HEAD)
mkdir -p "src/with space"; printf 'base\n' > "src/with space/f g.txt"; git add -A src; git commit -q -m spaced
printf 'uncommitted before the run\n' >> "src/with space/f g.txt"
run flow-context.sh "$(start_json r7 dev-flow:dev-reviewer)"
printf 'reviewer edit\n' >> "src/with space/f g.txt"
expect_block "reviewer changed an already-modified file whose path has spaces" flow-verify-stop.sh "$(stop_json r7 dev-flow:dev-reviewer)"
assert "the path is named unquoted" 'case $out in *"src/with space/f g.txt"*) true;; *) false;; esac'
git checkout -q -- src; rm -f task/violations.md
printf 'new\n' > src/committed.txt; printf 'more\n' >> src/shared.txt
run flow-context.sh "$(start_json r8 dev-flow:dev-reviewer)"
git add -- src/committed.txt src/shared.txt; git commit -q -m "main session commits meanwhile"
expect_pass "files committed by the main session during a run are not a change" flow-verify-stop.sh "$(stop_json r8 dev-flow:dev-reviewer)"
git reset -q --hard "$BASE_SHA"; rm -rf "src/with space"
# Limit 20 with 40 untracked files: an implementer's edit to a tracked file pushes
# the last untracked file out of the listing; that file did not change.
mkdir -p cache; i=10; while [ $i -lt 50 ]; do printf '%d\n' $i > cache/$i.json; i=$((i+1)); done
plan implementing 1; printf 'P1\n' > .claude/flow/claim-i5
export DEV_FLOW_SNAPSHOT_LIMIT=20
run flow-context.sh "$(start_json i5 dev-flow:dev-implementer)"
printf 'p1 edit\n' >> src/foo/alpha.txt
printf '[P1] $ make\nok\n' >> task/verify.log; printf '[P1] done\n' >> task/notes.md
expect_pass "past the limit: a path pushed out of the listing is not a change" flow-verify-stop.sh "$(stop_json i5 dev-flow:dev-implementer)"
run flow-context.sh "$(start_json r9 dev-flow:dev-reviewer)"; sleep 1.1
printf 'new\n' > cache/00-new.json
expect_block "past the limit: a file the agent created is still a change" flow-verify-stop.sh "$(stop_json r9 dev-flow:dev-reviewer)"
assert "it is named, nothing else" 'case $out in *"cache/00-new.json"*) case $out in *"cache/4"*) false;; *) true;; esac;; *) false;; esac'
unset DEV_FLOW_SNAPSHOT_LIMIT
git checkout -q -- src; rm -rf cache task/violations.md task/notes.md; plan implementing

echo "== Stop: notifications"
cat > "$T/fake-notify.sh" <<NEOF
#!/usr/bin/env bash
printf 'NOTIFY: %s | %s\n' "\$1" "\$2" >> "$T/notify.log"
NEOF
chmod +x "$T/fake-notify.sh"
export DEV_FLOW_NOTIFY_CMD="$T/fake-notify.sh"
plan implementing
expect_pass "implementing: no notification"      flow-notify.sh "$(main_stop_json)"
plan diagnosing
expect_out  "diagnosing: systemMessage (bug report intake)" flow-notify.sh "$(main_stop_json)" '"systemMessage":"dev-flow: t: waiting for you (diagnosing)"'
expect_pass "diagnosing again: deduplicated"              flow-notify.sh "$(main_stop_json)"
printf 'Confidence: High\n' > task/diagnosis.md
expect_out  "diagnosis.md written: the gate notifies again" flow-notify.sh "$(main_stop_json)" '"systemMessage":"dev-flow: t: waiting for you (confirm-cause)"'
rm -f task/diagnosis.md
plan human-review
expect_out  "human-review: systemMessage"        flow-notify.sh "$(main_stop_json)" '"systemMessage":"dev-flow: t: waiting for you (human-review)"'
expect_pass "human-review again: deduplicated"   flow-notify.sh "$(main_stop_json)"
printf 'disputed\n' > task/needs-decision.md
expect_out  "needs-decision changes the state"   flow-notify.sh "$(main_stop_json)" "(human-review+needs-decision)"
assert "four desktop notifications sent (diagnosing, confirm-cause, human-review, +needs-decision)" '[ "$(grep -c NOTIFY "$T/notify.log")" = 4 ]'
rm -f task/needs-decision.md
mv .claude/flow/current .claude/flow/finished; touch .claude/flow/start-zz .claude/flow/snap-zz
expect_out  "finished pointer notifies done"     flow-notify.sh "$(main_stop_json)" "(done)"
assert "finished pointer and markers removed"    '[ ! -f .claude/flow/finished ] && [ ! -f .claude/flow/start-zz ] && [ ! -f .claude/flow/snap-zz ] && [ ! -f .claude/flow/notified ]'
plan done; ptr current "$T/task"; touch .claude/flow/start-yy
expect_out  "current left at done (rename skipped) is finished too" flow-notify.sh "$(main_stop_json)" "(done)"
assert "current pointer and markers removed"     '[ ! -f .claude/flow/current ] && [ ! -f .claude/flow/start-yy ] && [ ! -f .claude/flow/notified ]'
unset DEV_FLOW_NOTIFY_CMD

echo "== Stop: notification text is never spliced into a script"
ptr current "$T/task"
mkdir -p "$T/bin"
printf '#!/bin/sh\necho MINGW64_NT\n' > "$T/bin/uname"
printf '#!/bin/sh\nprintf "%%s\\n" "$4" > "%s/ps.txt"\nprintf "%%s|%%s\\n" "$DEV_FLOW_TITLE" "$DEV_FLOW_MESSAGE" > "%s/ps-env.txt"\n' "$T" "$T" > "$T/bin/powershell.exe"
chmod +x "$T/bin/uname" "$T/bin/powershell.exe"
printf -- "---\ntask: Fix login'); Write-Host PWNED; ('\nstatus: human-review\n---\n" > task/plan.md
out=$(printf '%s' "$(main_stop_json)" | PATH="$T/bin:$PATH" bash "$H/flow-notify.sh" 2>/dev/null); sleep 1
assert "powershell script contains no task text"  '! grep -q "PWNED" "$T/ps.txt" && grep -q "DEV_FLOW_MESSAGE" "$T/ps.txt"'
assert "task text travels in the environment"     'grep -q "PWNED" "$T/ps-env.txt"'
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/osa.txt"\n' "$T" > "$T/bin/osascript"; printf '#!/bin/sh\necho Darwin\n' > "$T/bin/uname"; chmod +x "$T/bin/osascript"
rm -f .claude/flow/notified
printf '%s' "$(main_stop_json)" | PATH="$T/bin:$PATH" bash "$H/flow-notify.sh" >/dev/null 2>&1
assert "osascript gets the text as argv"          'grep -q "on run argv" "$T/osa.txt" && grep -q "PWNED" "$T/osa.txt"'

echo "== SessionStart"
plan reviewing
expect_out "resume re-injects the task folder and status" flow-session.sh "$(session_json resume)" "status: reviewing"
expect_out "startup names clear-flow as the way out"      flow-session.sh "$(session_json startup)" "/dev-flow:clear-flow"
plan done
expect_out "current at done: finished, not 'continue with dev-implement'" flow-session.sh "$(session_json resume)" "finished"
assert "no resume hint at done" 'case $out in *"Continue with"*) false;; *) true;; esac'
mv .claude/flow/current .claude/flow/planning
printf -- '---\ntask: t\nsource: dev-debug\nstatus: diagnosing\n---\n' > task/plan.md
expect_out "planning pointer with source dev-debug resumes dev-debug" flow-session.sh "$(session_json resume)" "/dev-debug:dev-debug"
plan draft
expect_out "planning pointer otherwise resumes dev-plan"          flow-session.sh "$(session_json resume)" "/dev-flow:dev-plan,"
mv .claude/flow/planning .claude/flow/current
rm .claude/flow/current
expect_pass "no pointer: silent"                           flow-session.sh "$(session_json startup)"

echo "== pointer lookup stops at the checkout's .git"
plan implementing; ptr current "$T/task"
# A subdirectory of the project finds the pointer at the root above it.
sub_session() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$(jp "$T/src/foo")"; }
expect_out "a subdirectory finds the pointer at the git root" flow-session.sh "$(sub_session)" "status: implementing"
# A Claude Code worktree lives under <repo>/.claude/worktrees/<name>, below the
# pointer's directory; a session there must not pick up the main checkout's flow.
git worktree add -q "$T/.claude/worktrees/bug" -b bug >/dev/null 2>&1
WT=$(jp "$T/.claude/worktrees/bug")
wt_session() { printf '{"session_id":"s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$WT"; }
wt_bash()    { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"d"}}' "$WT" "$1"; }
wt_agent()   { printf '{"session_id":"s","cwd":"%s","tool_name":"Agent","tool_input":{"subagent_type":"%s","prompt":"x","description":"d"}}' "$WT" "$1"; }
expect_pass  "worktree session: no flow re-injected"        flow-session.sh "$(wt_session)"
expect_allow "worktree session: git push is not guarded"    flow-guard.sh "$(wt_bash 'git push')"
expect_deny  "worktree session: stage agent needs its own pointer" flow-guard.sh "$(wt_agent dev-flow:dev-implementer)"
expect_out   "main checkout still sees its flow"            flow-session.sh "$(session_json startup)" "status: implementing"
# A flow started inside the worktree is found from there and only there.
mkdir -p "$T/.claude/worktrees/bug/.claude/flow" "$T/.claude/worktrees/bug/task"
printf -- '---\ntask: bug\nstatus: reviewing\nmode: lite\nreview_round: 1\n---\n' > "$T/.claude/worktrees/bug/task/plan.md"
printf '%s\nsession: s\n' "$(hp "$T/.claude/worktrees/bug/task")" > "$T/.claude/worktrees/bug/.claude/flow/current"
expect_out   "worktree session sees the worktree's own flow" flow-session.sh "$(wt_session)" "status: reviewing"
expect_out   "main checkout keeps its own"                   flow-session.sh "$(session_json startup)" "status: implementing"
git worktree remove --force "$T/.claude/worktrees/bug" >/dev/null 2>&1; git branch -q -D bug >/dev/null 2>&1
rm .claude/flow/current

echo "== planning pointer"
ptr planning "$T/task"
plan draft
expect_deny  "main session edits src while planning"   flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_allow "main session writes plan.md while planning" flow-guard.sh "$(write_json '' "$T/task/plan.md")"
expect_allow "main session writes .claude/flow/planning"  flow-guard.sh "$(write_json '' "$T/.claude/flow/planning")"
expect_allow "main session may commit while planning"  flow-guard.sh "$(bash_json '' 'git commit -m x')"
expect_deny  "git push while planning"                 flow-guard.sh "$(bash_json '' 'git push')"
expect_deny  "critic writes src while planning"        flow-guard.sh "$(write_json dev-flow:dev-plan-critic "$T/src/foo/alpha.txt")"
expect_deny  "spawn dev-implementer while planning"    flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny says to finish dev-plan and run dev-implement" 'case $err in *dev-plan*dev-implement*) true;; *) false;; esac'
assert "deny at draft names the status" 'case $err in *"planning exists"*"status: draft"*) true;; *) false;; esac'
expect_deny  "spawn dev-fixer while planning"          flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
expect_allow "spawn dev-plan-critic while planning"    flow-guard.sh "$(agent_json dev-flow:dev-plan-critic)"
expect_allow "spawn dev-planner while planning"        flow-guard.sh "$(agent_json dev-flow:dev-planner)"
expect_allow "spawn dev-debugger while planning"       flow-guard.sh "$(agent_json dev-debug:dev-debugger)"
expect_allow "spawn dev-qa-impact while planning"      flow-guard.sh "$(agent_json dev-flow:dev-qa-impact)"
rm task/plan.md
expect_deny  "no plan.md yet (dev-plan just started): main session edits src" flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_deny  "no plan.md yet: spawn dev-implementer"   flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny says no status yet" 'case $err in *"status: none yet"*) true;; *) false;; esac'
printf -- '---\ntask: t\nsource: dev-debug\nstatus: diagnosing\n---\n' > task/plan.md
expect_deny  "diagnosing: main session edits src"      flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_deny  "diagnosing: git push"                    flow-guard.sh "$(bash_json '' 'git push')"
expect_deny  "diagnosing: debugger commits"            flow-guard.sh "$(bash_json dev-debug:dev-debugger 'git commit -m x')"
expect_deny  "diagnosing: spawn dev-implementer"       flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny names status diagnosing and dev-debug" 'case $err in *"status: diagnosing"*"/dev-debug:dev-debug"*) true;; *) false;; esac'
expect_allow "diagnosing: spawn dev-debugger"          flow-guard.sh "$(agent_json dev-debug:dev-debugger)"
run flow-notify.sh "$(main_stop_json)"
assert "Stop keeps a genuine planning pointer (diagnosing)" '[ -f .claude/flow/planning ]'
plan draft
run flow-notify.sh "$(main_stop_json)"
assert "Stop keeps a genuine planning pointer (draft)" '[ -f .claude/flow/planning ]'
# planning for a second task written while a current task is parked: current wins
# the lookup, the second task's genuine planning pointer still gates.
plan human-review; ptr current "$T/task"
mkdir -p task2; printf -- '---\ntask: t2\nstatus: draft\n---\n' > task2/plan.md; ptr planning "$T/task2"
expect_deny  "planning beside current: spawn dev-fixer"   flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
assert "deny is the dev-plan message with the second plan's status" 'case $err in *"planning exists"*"task2/plan.md has status: draft"*) true;; *) false;; esac'
expect_deny  "planning beside current: spawn dev-review-triager" flow-guard.sh "$(agent_json dev-flow:dev-review-triager)"
# The second task's own agents belong to the planning pointer, not the parked current.
expect_allow "planning beside current: planner writes task2/plan.md"           flow-guard.sh "$(write_json dev-flow:dev-planner "$T/task2/plan.md")"
expect_deny  "planning beside current: planner writes the parked task's folder" flow-guard.sh "$(write_json dev-flow:dev-planner "$T/task/plan.md")"
expect_deny  "planning beside current: planner writes src"                     flow-guard.sh "$(write_json dev-flow:dev-planner "$T/src/foo/alpha.txt")"
expect_allow "planning beside current: critic writes task2/plan-critique.md"   flow-guard.sh "$(write_json dev-flow:dev-plan-critic "$T/task2/plan-critique.md")"
printf -- '---\ntask: b2\nsource: dev-debug\nstatus: diagnosing\n---\n' > task2/plan.md
expect_allow "planning beside current: debugger writes task2/diagnosis.md"     flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/task2/diagnosis.md")"
expect_deny  "planning beside current: debugger writes task/diagnosis.md"      flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/task/diagnosis.md")"
expect_out   "planning beside current: debugger start gets the planning task"  flow-context.sh "$(start_json d9 dev-debug:dev-debugger)" "task2. "
assert "debugger start says diagnosing" 'case $out in *"status: diagnosing"*) true;; *) false;; esac'
expect_pass  "planning beside current: debugger stop compares against its own snapshot" flow-verify-stop.sh "$(stop_json d9 dev-debug:dev-debugger)"
expect_allow "planning beside current: reviewer still writes the parked task"  flow-guard.sh "$(write_json dev-flow:dev-reviewer "$T/task/review-1.md")"
expect_deny  "planning beside current: reviewer writes task2"                  flow-guard.sh "$(write_json dev-flow:dev-reviewer "$T/task2/review-1.md")"
rm -f .claude/flow/notified
expect_out   "planning beside current: Stop announces the planning task's gate"  flow-notify.sh "$(main_stop_json)" "b2: waiting for you (diagnosing)"
expect_out   "planning beside current: SessionStart re-injects the planning task" flow-session.sh "$(session_json resume)" "/dev-debug:dev-debug"
assert "and names the parked task with its status" 'case $out in *"parked"*"/task at status: human-review"*) true;; *) false;; esac'
printf -- '---\ntask: b2\nsource: dev-debug\nstatus: done\n---\n' > task2/plan.md
expect_out   "stale planning beside current: SessionStart re-injects the current task" flow-session.sh "$(session_json resume)" "status: human-review"
expect_allow "stale planning beside current: debugger falls back to current"    flow-guard.sh "$(write_json dev-debug:dev-debugger "$T/task/diagnosis.md")"
expect_out   "stale planning beside current: Stop sweeps it"                   flow-notify.sh "$(main_stop_json)" "removed stale pointer"
assert "current untouched" '[ -f .claude/flow/current ] && [ ! -f .claude/flow/planning ]'
mkdir -p task2; printf -- '---\ntask: t2\nstatus: draft\n---\n' > task2/plan.md; ptr planning "$T/task2"
rm .claude/flow/current; ptr planning "$T/task"; plan draft
expect_out   "planner start gets context"              flow-context.sh "$(start_json p1 dev-flow:dev-planner)" "status: draft"
expect_pass  "verify-stop: planner with no changes passes" flow-verify-stop.sh "$(stop_json p1 dev-flow:dev-planner)"

echo "== stale planning pointer: a plan past planning switches the guards off, with a notice"
rm -f .claude/flow/current .claude/flow/stale-notified .claude/flow/notified
plan implementing
expect_allow "stale (implementing): main session edits src"   flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
assert "notice names the pointer, the status and rm" 'case $out in *"systemMessage"*"stale pointer"*"/.claude/flow/planning"*"status: implementing"*"rm "*"additionalContext"*"/dev-flow:dev-implement"*) true;; *) false;; esac'
expect_allow "stale (implementing): git push passes"          flow-guard.sh "$(bash_json '' 'git push')"
assert "the notice is given once per session" '[ -z "$out" ]'
expect_allow "stale (implementing): mcp create_pull_request"  flow-guard.sh "$(mcp_json mcp__github__create_pull_request)"
expect_deny  "stale (implementing): dev-implementer still needs current" flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny names the stale pointer, its status and dev-implement" 'case $err in *"stale pointer"*"status: implementing"*"/dev-flow:dev-implement"*) true;; *) false;; esac'
ptr current "$T/task"
expect_allow "stale planning beside current: spawn dev-implementer" flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
expect_allow "stale planning beside current: main session edits src" flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
rm .claude/flow/current
printf -- '---\ntask: t\nsource: dev-debug\nstatus: implementing\n---\n' > task/plan.md
expect_out  "SessionStart reports the pointer as stale"      flow-session.sh "$(session_json startup)" "stale pointer"
assert "no 'in progress' claim, resume hint names dev-implement" 'case $out in *"in progress"*) false;; *"status: implementing"*"/dev-flow:dev-implement"*) true;; *) false;; esac'
expect_out  "Stop removes the stale pointer and says so"     flow-notify.sh "$(main_stop_json)" "removed stale pointer"
assert "pointer and marker gone, plan.md untouched" '[ ! -f .claude/flow/planning ] && [ ! -f .claude/flow/stale-notified ] && grep -q "status: implementing" task/plan.md'
ptr planning "$T/task"; plan approved
expect_allow "stale (approved, pointer not deleted): main session edits src" flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_deny  "stale (approved): spawn dev-implementer"       flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny names status approved" 'case $err in *"stale pointer"*"status: approved"*) true;; *) false;; esac'
run flow-notify.sh "$(main_stop_json)"
assert "Stop removes it at approved too" '[ ! -f .claude/flow/planning ]'
ptr planning "$T/task"; plan done
expect_out  "SessionStart at done: no resume hint"           flow-session.sh "$(session_json resume)" "status: done"
assert "done offers nothing to resume" 'case $out in *"/dev-flow:dev-implement"*) false;; *) true;; esac'
run flow-notify.sh "$(main_stop_json)"
ptr planning /nowhere/at/all
expect_allow "dangling planning: main session edits src"     flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
assert "notice says not a folder and names rm" 'case $out in *"stale pointer"*"/nowhere/at/all"*"not a folder"*"rm "*) true;; *) false;; esac'
expect_deny  "dangling planning: spawn dev-implementer"      flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny says not a folder" 'case $err in *"not a folder"*"/dev-flow:dev-implement"*) true;; *) false;; esac'
expect_out  "SessionStart reports the dangling pointer"      flow-session.sh "$(session_json resume)" "not a folder"
rm -f .claude/flow/stale-notified   # the notice is given once per session; PreToolUse gave it above
expect_out  "Stop names a dangling pointer"                  flow-notify.sh "$(main_stop_json)" "not a folder"
assert "but leaves it for the user to fix or remove" '[ -f .claude/flow/planning ]'
rm -f .claude/flow/planning .claude/flow/stale-notified

echo "== session scoping: a flow guards only the session that owns it"
# Session s runs the flow; session o works in the same checkout, on the same branch.
rm -f .claude/flow/planning .claude/flow/current .claude/flow/notified .claude/flow/stale-notified
plan human-review; ptr current "$T/task"
SID=o
expect_allow "another session: git push passes"                      flow-guard.sh "$(bash_json '' 'git push origin main')"
expect_allow "another session: git commit --amend passes"            flow-guard.sh "$(bash_json '' 'git commit --amend --no-edit')"
expect_allow "another session: mcp create_pull_request passes"       flow-guard.sh "$(mcp_json mcp__github__create_pull_request)"
expect_allow "another session: a subagent of its own commits"        flow-guard.sh "$(bash_json general-purpose 'git commit -m x')"
expect_allow "another session: its reviewer-typed agent writes src"  flow-guard.sh "$(write_json dev-flow:dev-reviewer "$T/src/foo/alpha.txt")"
expect_allow "another session: main session edits src"               flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_deny  "another session: a stage agent needs a flow of its own" flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
assert "deny names the owning session and how to take the flow over" 'case $err in *"belongs to another Claude Code session (s)"*"/dev-flow:dev-implement"*) true;; *) false;; esac'
expect_allow "another session: dev-qa-impact still not gated"        flow-guard.sh "$(agent_json dev-flow:dev-qa-impact)"
expect_pass  "another session: SubagentStart is silent"              flow-context.sh "$(start_json o1 dev-flow:dev-reviewer)"
assert "no snapshot or marker for it" '[ ! -f .claude/flow/snap-o1 ] && [ ! -f .claude/flow/start-o1 ]'
expect_pass  "another session: SubagentStop is silent"               flow-verify-stop.sh "$(stop_json o1 dev-flow:dev-implementer)"
expect_pass  "another session: Stop sends no notification"           flow-notify.sh "$(main_stop_json)"
assert "nothing recorded as notified" '[ ! -f .claude/flow/notified ]'
expect_out   "another session: SessionStart names the owner, the task and how to run it here" flow-session.sh "$(session_json startup)" "belongs to another Claude Code session (s)"
assert "it names the task folder, the status, dev-implement and rm" 'case $out in *"/task, status: human-review"*"/dev-flow:dev-implement "*"/task/plan.md"*"rm "*) true;; *) false;; esac'
assert "and does not describe the flow as this session's" 'case $out in *"flow of this session"*) false;; *) true;; esac'
SID=s
expect_deny  "owner session: git push is still refused"              flow-guard.sh "$(bash_json '' 'git push')"
expect_deny  "owner session: its reviewer may not write src"         flow-guard.sh "$(write_json dev-flow:dev-reviewer "$T/src/foo/alpha.txt")"
expect_allow "owner session: spawn dev-fixer at human-review"        flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
expect_out   "owner session: Stop notifies"                          flow-notify.sh "$(main_stop_json)" "(human-review)"
expect_out   "owner session: SessionStart (a resumed session keeps its id) re-injects the flow" flow-session.sh "$(session_json resume)" "flow of this session"
assert "and says the guards hold in this session only" 'case $out in *"this session and its subagents only"*) true;; *) false;; esac'
rm -f .claude/flow/notified
# A hook input without a session id (an older harness) cannot tell sessions
# apart: every pointer counts, as before 2.5.0.
expect_deny  "no session id in the input: the pointer still guards"  flow-guard.sh "$(printf '{"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push"}}' "$CW")"

echo "== session scoping: an unclaimed pointer, and the claim right after the tool call that wrote it"
hp "$T/task" > .claude/flow/current          # as the skill writes it: no session line yet
expect_allow "unclaimed pointer: git push passes (no session owns it)"   flow-guard.sh "$(bash_json '' 'git push')"
expect_deny  "unclaimed pointer: a stage agent is refused"              flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
assert "deny says no session owns it" 'case $err in *"no session owns it yet"*) true;; *) false;; esac'
expect_out   "unclaimed pointer: SessionStart says so"                  flow-session.sh "$(session_json startup)" "no session owns it yet"
expect_pass  "claim: a command that does not name the flow dir claims nothing" flow-claim.sh "$(post_json '' Bash 'git status')"
assert "pointer still unclaimed" '! grep -q "^session:" .claude/flow/current'
expect_pass  "claim: a subagent never claims"                           flow-claim.sh "$(post_json dev-flow:dev-implementer Bash 'cat .claude/flow/current')"
assert "pointer still unclaimed after the subagent" '! grep -q "^session:" .claude/flow/current'
expect_out   "claim: the main session's command that wrote the pointer claims it" flow-claim.sh "$(post_json '' Bash 'mkdir -p .claude/flow && echo /x > .claude/flow/current')" "now owns"
assert "pointer carries the task folder and the session line" '[ "$(head -n 1 .claude/flow/current)" = "$(hp "$T/task")" ] && grep -q -x "session: s" .claude/flow/current && [ "$(wc -l < .claude/flow/current)" -eq 2 ]'
assert "the context names the pointer and says other sessions are unaffected" 'case $out in *"additionalContext"*".claude/flow/current"*"not affected"*) true;; *) false;; esac'
expect_deny  "after the claim: git push is refused in the owner session" flow-guard.sh "$(bash_json '' 'git push')"
SID=o
expect_pass  "claim: another session's command leaves an owned pointer alone" flow-claim.sh "$(post_json '' Bash 'cat .claude/flow/current')"
assert "owner unchanged" 'grep -q -x "session: s" .claude/flow/current'
expect_allow "and that session is still not guarded by it"              flow-guard.sh "$(bash_json '' 'git push')"
SID=s
hp "$T/task2" > .claude/flow/planning
expect_out   "claim: the Write tool on a pointer path claims it"        flow-claim.sh "$(post_json '' Write "$(jp "$T/.claude/flow/planning")")" "planning"
assert "planning claimed, current untouched" 'grep -q -x "session: s" .claude/flow/planning && [ "$(wc -l < .claude/flow/current)" -eq 2 ]'
expect_pass  "claim: nothing left to claim is silent"                   flow-claim.sh "$(post_json '' Write "$(jp "$T/.claude/flow/planning")")"
rm -f .claude/flow/planning
hp "$T/task" > .claude/flow/current
expect_out   "claim: a PowerShell command naming the pointer (backslashes) claims it" flow-claim.sh "$(post_json '' PowerShell 'Set-Content -Path .claude\\flow\\current -Value x')" "now owns"
assert "claimed" 'grep -q -x "session: s" .claude/flow/current'

echo "== session scoping: two sessions, two tasks, one checkout"
# Session s implements task (current); session o plans task2 (planning) beside it.
plan implementing; ptr current "$T/task"
mkdir -p task2; printf -- '---\ntask: t2\nstatus: draft\n---\n' > task2/plan.md; ptr planning "$T/task2" o
expect_allow "s: another session's planning does not gate the stage agents"  flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
expect_allow "s: main session edits src while the other session plans"       flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_out   "s: SessionStart re-injects its own flow"                       flow-session.sh "$(session_json resume)" "status: implementing"
assert "and names the other task as another session's, not as parked" 'case $out in *"planning belongs to another Claude Code session (o)"*"/task2 at status: draft"*"do not guard"*) case $out in *parked*) false;; *) true;; esac;; *) false;; esac'
SID=o
expect_deny  "o: its own planning limits its main session to the task folder" flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_allow "o: main session writes task2/plan.md"                          flow-guard.sh "$(write_json '' "$T/task2/plan.md")"
expect_deny  "o: git push while planning"                                    flow-guard.sh "$(bash_json '' 'git push')"
expect_deny  "o: no stage agent while its own plan is a draft"               flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny says the plan is still being planned" 'case $err in *"still being planned"*"task2/plan.md has status: draft"*) true;; *) false;; esac'
expect_out   "o: its planner start gets task2"                               flow-context.sh "$(start_json p7 dev-flow:dev-planner)" "task2. "
expect_pass  "o: its planner stop compares against its own snapshot"         flow-verify-stop.sh "$(stop_json p7 dev-flow:dev-planner)"
expect_out   "o: SessionStart re-injects its planning"                       flow-session.sh "$(session_json resume)" "/dev-flow:dev-plan"
assert "and names the other session's task as not its own" 'case $out in *"current belongs to another Claude Code session (s)"*"/task at status: implementing"*"not this session'"'"'s to touch"*) true;; *) false;; esac'
rm -f .claude/flow/notified
expect_out   "o: Stop announces its own gate, not the other session's"       flow-notify.sh "$(main_stop_json)" "t2: waiting for you (draft)"
SID=s
rm -rf task2 .claude/flow/planning .claude/flow/current .claude/flow/notified .claude/flow/stale-notified

echo "== session scoping: the claim follows writes, not reads"
hp "$T/task" > .claude/flow/current          # unclaimed
expect_pass "claim: cat of the pointer by the main session claims nothing"   flow-claim.sh "$(post_json '' Bash 'cat .claude/flow/current')"
expect_pass "claim: a redirect elsewhere in the command claims nothing"      flow-claim.sh "$(post_json '' Bash 'cat .claude/flow/current 2>/dev/null')"
expect_pass "claim: ls of the flow dir claims nothing"                       flow-claim.sh "$(post_json '' Bash 'ls -la .claude/flow')"
expect_pass "claim: a path that merely contains flow/current claims nothing" flow-claim.sh "$(post_json '' Bash 'cat src/workflow/current.ts')"
expect_pass "claim: the Write tool on a marker file claims nothing"          flow-claim.sh "$(post_json '' Write "$(jp "$T/.claude/flow/claim-x")")"
assert "still unclaimed" '! grep -q "^session:" .claude/flow/current'
expect_out  "claim: a redirect to the pointer claims"                        flow-claim.sh "$(post_json '' Bash "printf '%s\\\\n' /x > .claude/flow/current")" "now owns"
hp "$T/task" > .claude/flow/current
expect_out  "claim: tee into the pointer claims"                             flow-claim.sh "$(post_json '' Bash 'echo /x | tee .claude/flow/current')" "now owns"
hp "$T/task" > .claude/flow/current
expect_out  "claim: cd into the flow dir and a redirect to current claims"   flow-claim.sh "$(post_json '' Bash 'cd .claude/flow && echo /x > current')" "now owns"
hp "$T/task" > .claude/flow/current
expect_out  "claim: mv onto the pointer claims"                              flow-claim.sh "$(post_json '' Bash 'mv /tmp/x .claude/flow/current')" "now owns"
rm -f .claude/flow/current

echo "== session scoping: another session's finished run is swept, its live run is not"
plan human-review; ptr current "$T/task" o
expect_pass "Stop: another session's current at human-review is left alone"  flow-notify.sh "$(main_stop_json)"
assert "kept" '[ -f .claude/flow/current ] && grep -q -x "session: o" .claude/flow/current'
plan done; touch .claude/flow/start-zz .claude/flow/notified
expect_pass "Stop: another session's current at done is swept, silently"     flow-notify.sh "$(main_stop_json)"
assert "pointer and markers gone" '[ ! -f .claude/flow/current ] && [ ! -f .claude/flow/start-zz ] && [ ! -f .claude/flow/notified ]'
ptr finished "$T/task" o; ptr planning "$T/task2" s; mkdir -p task2; printf -- '---\ntask: t2\nstatus: draft\n---\n' > task2/plan.md; touch .claude/flow/snap-yy
run flow-notify.sh "$(main_stop_json)"
assert "Stop: another session's finished pointer is swept; this session's planning and the markers stay" '[ ! -f .claude/flow/finished ] && [ -f .claude/flow/planning ] && [ -f .claude/flow/snap-yy ]'
rm -rf task2 .claude/flow/planning .claude/flow/snap-yy .claude/flow/notified

echo "== session scoping: an agent that started under the flow stays guarded after a take-over"
plan implementing; ptr current "$T/task" o
SID=o; run flow-context.sh "$(start_json i8 dev-flow:dev-implementer)"     # session o's implementer starts
assert "its snapshot sits beside the pointer" '[ -f .claude/flow/snap-i8 ] && [ -f .claude/flow/start-i8 ]'
ptr current "$T/task" s                                                   # session s takes the flow over
AID=i8
expect_deny  "o's running implementer: git push is still refused"           flow-guard.sh "$(bash_json dev-flow:dev-implementer 'git push')"
expect_deny  "o's running implementer: git commit is still refused"         flow-guard.sh "$(bash_json dev-flow:dev-implementer 'git commit -m x')"
expect_deny  "o's running implementer: verify.log is still protected"       flow-guard.sh "$(write_json dev-flow:dev-implementer "$T/task/verify.log" Write i8)"
expect_block "o's running implementer: its stop still needs the evidence"   flow-verify-stop.sh "$(stop_json i8 dev-flow:dev-implementer)"
sleep 1.1; printf '$ make\nok\n' >> task/verify.log; printf 'done\n' > task/notes.md
expect_pass  "o's running implementer: stops cleanly once the evidence is in" flow-verify-stop.sh "$(stop_json i8 dev-flow:dev-implementer)"
expect_allow "o's implementer after its stop: no longer guarded (markers gone)" flow-guard.sh "$(bash_json dev-flow:dev-implementer 'git push')"
AID=x
expect_allow "o's main session itself is no longer guarded"                 flow-guard.sh "$(bash_json '' 'git push')"
SID=s; rm -f task/notes.md .claude/flow/current .claude/flow/cross-notified

echo "== Stop: an unclaimed pointer is named once per session, with load-flow"
hp "$T/task" > .claude/flow/current; plan human-review
expect_out  "Stop names an unclaimed pointer"                     flow-notify.sh "$(main_stop_json)" "names no session"
assert "and load-flow with the folder, and clear-flow" 'case $out in *"/dev-flow:load-flow "*"/task (status: human-review)"*"/dev-flow:clear-flow"*) true;; *) false;; esac'
expect_pass "said once per session"                               flow-notify.sh "$(main_stop_json)"
SID=o
expect_out  "another session hears it once too"                   flow-notify.sh "$(main_stop_json)" "names no session"
expect_pass "and then no more"                                    flow-notify.sh "$(main_stop_json)"
SID=s
ptr current "$T/task" s
expect_out  "once claimed, the owner's Stop announces its gate as usual" flow-notify.sh "$(main_stop_json)" "(human-review)"
rm -f .claude/flow/current .claude/flow/unclaimed-notified .claude/flow/notified

echo "== guard: a branch switch or discard beside another session's flow is warned about once, never blocked"
plan implementing; ptr current "$T/task" o
expect_allow "git push: allowed, no warning (sessions push as they like)" flow-guard.sh "$(bash_json '' 'git push')"
assert "silent" '[ -z "$out" ]'
expect_allow "git checkout: allowed, with a warning"              flow-guard.sh "$(bash_json '' 'git checkout -- src')"
assert "a terminal line and context, no decision" 'case $out in *"systemMessage"*"belongs to another Claude Code session (o)"*"uncommitted work"*"additionalContext"*) case $out in *"decision"*) false;; *) true;; esac;; *) false;; esac'
expect_allow "git stash: allowed, silent the second time"         flow-guard.sh "$(bash_json '' 'git stash')"
assert "silent" '[ -z "$out" ]'
SID=o
expect_deny  "the owner session: git checkout is still refused"   flow-guard.sh "$(bash_json '' 'git checkout -- src')"
SID=s
rm -f .claude/flow/current .claude/flow/cross-notified

echo "== scripts: flow-list and flow-clear (run from the Bash tool, keyed on CLAUDE_CODE_SESSION_ID)"
S="$H/../scripts"
mkdir -p .claude/plans/2026-01-01-a .claude/plans/2026-01-02-b .claude/plans/2026-01-03-c
printf -- '---\ntask: A done\nstatus: done\nsource: manual\nmode: lite\nreview_round: 1\n---\n' > .claude/plans/2026-01-01-a/plan.md
printf -- '---\ntask: B | draft\nstatus: draft\nsource: dev-plan-draft\n---\n' > .claude/plans/2026-01-02-b/plan.md
printf -- '---\ntask: C review\nstatus: human-review\nsource: dev-plan-interactive\nmode: full\nreview_round: 2\n---\n' > .claude/plans/2026-01-03-c/plan.md
ptr current "$T/.claude/plans/2026-01-03-c" s; ptr planning "$T/.claude/plans/2026-01-02-b" o
out=$(CLAUDE_CODE_SESSION_ID=s bash "$S/flow-list.sh" 2>&1); rc=$?
assert "list: newest first, done hidden, header present" '[ $rc -eq 0 ] && case $out in *"| # | folder | task | status"*"| 1 | 2026-01-03-c | C review | human-review | dev-plan-interactive | full | 2 | current (this session) |"*"| 2 | 2026-01-02-b | B \\| draft | draft | dev-plan-draft |  |  | planning (session o) |"*"1 finished task(s) hidden"*) true;; *) false;; esac'
assert "list: the done task is not listed by default" 'case $out in *"2026-01-01-a"*) false;; *) true;; esac'
out=$(CLAUDE_CODE_SESSION_ID=s bash "$S/flow-list.sh" "$T/.claude/plans" all 2>&1)
assert "list all: the done task is listed, without a pointer" 'case $out in *"| 3 | 2026-01-01-a | A done | done | manual | lite | 1 | - |"*) true;; *) false;; esac'
out=$(CLAUDE_CODE_SESSION_ID=s bash "$S/flow-list.sh" "$T/nowhere" 2>&1)
assert "list: a missing plans folder is said, not an error" 'case $out in *"No plans folder at"*"/nowhere"*) true;; *) false;; esac'
touch .claude/flow/start-q .claude/flow/notified
out=$(CLAUDE_CODE_SESSION_ID=s bash "$S/flow-clear.sh" 2>&1); rc=$?
assert "clear: removes this session's pointer, keeps the other session's, says so" '[ $rc -eq 0 ] && [ ! -f .claude/flow/current ] && [ -f .claude/flow/planning ] && case $out in *"removed "*"/current"*"status: human-review"*"kept "*"/planning"*"(o;"*"clear-flow all"*"guards are off in this session"*) true;; *) false;; esac'
assert "clear: markers stay while another session's pointer remains" '[ -f .claude/flow/start-q ] && [ -f .claude/flow/notified ]'
out=$(CLAUDE_CODE_SESSION_ID=s bash "$S/flow-clear.sh" 2>&1)
assert "clear again: nothing of this session's" 'case $out in *"kept "*"Nothing of this session"*) true;; *) false;; esac'
out=$(CLAUDE_CODE_SESSION_ID=s bash "$S/flow-clear.sh" all 2>&1)
assert "clear all: removes the other session's pointer and the markers" '[ ! -f .claude/flow/planning ] && [ ! -f .claude/flow/start-q ] && [ ! -f .claude/flow/notified ] && case $out in *"removed "*"/planning of session o"*"marker files are removed"*) true;; *) false;; esac'
out=$(CLAUDE_CODE_SESSION_ID=s bash "$S/flow-clear.sh" 2>&1)
assert "clear with no pointer: says nothing is active" 'case $out in *"nothing to clear"*) true;; *) false;; esac'
hp "$T/task" > .claude/flow/current
out=$(CLAUDE_CODE_SESSION_ID=s bash "$S/flow-clear.sh" 2>&1)
assert "clear: an unclaimed pointer counts as this session's" '[ ! -f .claude/flow/current ] && case $out in *"removed "*"/current"*) true;; *) false;; esac'
ptr current "$T/task" o
out=$(env -u CLAUDE_CODE_SESSION_ID bash "$S/flow-clear.sh" 2>&1)   # no session id at all: an older Claude Code
assert "clear without a session id: every pointer counts" '[ ! -f .claude/flow/current ]'
rm -rf .claude/plans

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
