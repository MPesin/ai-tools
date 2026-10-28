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

# JSON builders
bash_json() { # AGENT_TYPE COMMAND [DESCRIPTION] [TOOL]
  local a=''; [ -n "$1" ] && a='"agent_type":"'$1'","agent_id":"x",'
  printf '{"session_id":"s","cwd":"%s",%s"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s","description":"%s"}}' "$CW" "$a" "${4:-Bash}" "$2" "${3:-}"
}
write_json() { # AGENT_TYPE PATH [TOOL] [AGENT_ID]
  local a=''; [ -n "$1" ] && a='"agent_type":"'$1'","agent_id":"'${4:-x}'",'
  local key=file_path; [ "${3:-}" = NotebookEdit ] && key=notebook_path
  printf '{"session_id":"s","cwd":"%s",%s"tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' "$CW" "$a" "${3:-Write}" "$key" "$(jp "$2")"
}
mcp_json() { printf '{"cwd":"%s","tool_name":"%s","tool_input":{"x":1}}' "$CW" "$1"; }
agent_json() { printf '{"session_id":"s","cwd":"%s","tool_name":"%s","tool_input":{"subagent_type":"%s","prompt":"x","description":"d"}}' "$CW" "${2:-Agent}" "$1"; }
agent_json_untyped() { printf '{"session_id":"s","cwd":"%s","tool_name":"Agent","tool_input":{"prompt":"x","description":"d"}}' "$CW"; }
start_json() { printf '{"cwd":"%s","hook_event_name":"SubagentStart","agent_id":"%s","agent_type":"%s"}' "$CW" "$1" "$2"; }
stop_json()  { printf '{"cwd":"%s","hook_event_name":"SubagentStop","agent_id":"%s","agent_type":"%s","stop_hook_active":%s}' "$CW" "$1" "$2" "${3:-false}"; }
main_stop_json() { printf '{"cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$CW"; }
session_json()   { printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$CW" "$1"; }

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
printf '/nowhere/at/all\n' > .claude/flow/current
expect_deny  "dangling current: spawn dev-implementer"   flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny names the pointer and the folder" 'case $err in *".claude/flow/current"*"/nowhere/at/all"*) true;; *) false;; esac'
expect_allow "dangling current: dev-qa-impact not gated" flow-guard.sh "$(agent_json dev-flow:dev-qa-impact)"
: > .claude/flow/current
expect_deny  "empty current: spawn dev-fixer"            flow-guard.sh "$(agent_json dev-flow:dev-fixer)"
mkdir -p noplan; hp "$T/noplan" > .claude/flow/current
expect_deny  "current folder without plan.md: spawn dev-reviewer" flow-guard.sh "$(agent_json dev-flow:dev-reviewer)"
assert "deny names plan.md" 'case $err in *"no plan.md"*) true;; *) false;; esac'

hp "$T/task" > .claude/flow/current

echo "== guard: git"
expect_deny  "git commit"                       flow-guard.sh "$(bash_json '' 'git commit -m x')"
expect_deny  "git push"                         flow-guard.sh "$(bash_json '' 'git push origin main')"
expect_deny  "git --no-pager push"              flow-guard.sh "$(bash_json '' 'git --no-pager push')"
expect_deny  "git -C \"my repo\" push"          flow-guard.sh "$(bash_json '' 'git -C \"my repo\" push')"
expect_deny  "git -c x=y commit"                flow-guard.sh "$(bash_json '' 'git -c user.name=x commit -m y')"
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
expect_deny  "PowerShell: Git Commit (case)"    flow-guard.sh "$(bash_json '' 'Git Commit -m x' '' PowerShell)"
expect_allow "git status && git diff"           flow-guard.sh "$(bash_json '' 'git status && git diff')"
expect_allow "git stash list"                   flow-guard.sh "$(bash_json '' 'git stash list')"
expect_allow "git reset (unstage)"              flow-guard.sh "$(bash_json '' 'git reset src/foo/alpha.txt')"
expect_allow "git branch (list)"                flow-guard.sh "$(bash_json '' 'git branch -a')"
expect_allow "git log, description says push"  flow-guard.sh "$(bash_json '' 'git log --oneline -5' 'check whether git push already happened')"
expect_allow "grep \"git commit\" docs/"        flow-guard.sh "$(bash_json '' 'grep -rn \"git commit\" docs/')"
expect_allow "echo remember to git push"        flow-guard.sh "$(bash_json '' 'echo remember to git push later')"
expect_allow "heredoc body mentions git push"   flow-guard.sh "$(bash_json '' 'cat >> notes.md <<EOF\ndid not run git push\nEOF')"
expect_allow "git commit as a literal word arg" flow-guard.sh "$(bash_json '' 'rg \"git commit\" -l')"

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
plan done; hp "$T/task" > .claude/flow/current; touch .claude/flow/start-yy
expect_out  "current left at done (rename skipped) is finished too" flow-notify.sh "$(main_stop_json)" "(done)"
assert "current pointer and markers removed"     '[ ! -f .claude/flow/current ] && [ ! -f .claude/flow/start-yy ] && [ ! -f .claude/flow/notified ]'
unset DEV_FLOW_NOTIFY_CMD

echo "== Stop: notification text is never spliced into a script"
hp "$T/task" > .claude/flow/current
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
expect_out "startup names the pointer to delete"          flow-session.sh "$(session_json startup)" "delete"
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
plan implementing; hp "$T/task" > .claude/flow/current
# A subdirectory of the project finds the pointer at the root above it.
sub_session() { printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$(jp "$T/src/foo")"; }
expect_out "a subdirectory finds the pointer at the git root" flow-session.sh "$(sub_session)" "status: implementing"
# A Claude Code worktree lives under <repo>/.claude/worktrees/<name>, below the
# pointer's directory; a session there must not pick up the main checkout's flow.
git worktree add -q "$T/.claude/worktrees/bug" -b bug >/dev/null 2>&1
WT=$(jp "$T/.claude/worktrees/bug")
wt_session() { printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$WT"; }
wt_bash()    { printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"d"}}' "$WT" "$1"; }
wt_agent()   { printf '{"session_id":"s","cwd":"%s","tool_name":"Agent","tool_input":{"subagent_type":"%s","prompt":"x","description":"d"}}' "$WT" "$1"; }
expect_pass  "worktree session: no flow re-injected"        flow-session.sh "$(wt_session)"
expect_allow "worktree session: git commit is not guarded"  flow-guard.sh "$(wt_bash 'git commit -m x')"
expect_deny  "worktree session: stage agent needs its own pointer" flow-guard.sh "$(wt_agent dev-flow:dev-implementer)"
expect_out   "main checkout still sees its flow"            flow-session.sh "$(session_json startup)" "status: implementing"
# A flow started inside the worktree is found from there and only there.
mkdir -p "$T/.claude/worktrees/bug/.claude/flow" "$T/.claude/worktrees/bug/task"
printf -- '---\ntask: bug\nstatus: reviewing\nmode: lite\nreview_round: 1\n---\n' > "$T/.claude/worktrees/bug/task/plan.md"
hp "$T/.claude/worktrees/bug/task" > "$T/.claude/worktrees/bug/.claude/flow/current"
expect_out   "worktree session sees the worktree's own flow" flow-session.sh "$(wt_session)" "status: reviewing"
expect_out   "main checkout keeps its own"                   flow-session.sh "$(session_json startup)" "status: implementing"
git worktree remove --force "$T/.claude/worktrees/bug" >/dev/null 2>&1; git branch -q -D bug >/dev/null 2>&1
rm .claude/flow/current

echo "== planning pointer"
hp "$T/task" > .claude/flow/planning
plan draft
expect_deny  "main session edits src while planning"   flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_allow "main session writes plan.md while planning" flow-guard.sh "$(write_json '' "$T/task/plan.md")"
expect_allow "main session writes .claude/flow/planning"  flow-guard.sh "$(write_json '' "$T/.claude/flow/planning")"
expect_deny  "git commit while planning"               flow-guard.sh "$(bash_json '' 'git commit -m x')"
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
expect_deny  "diagnosing: git commit"                  flow-guard.sh "$(bash_json '' 'git commit -m x')"
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
plan human-review; hp "$T/task" > .claude/flow/current
mkdir -p task2; printf -- '---\ntask: t2\nstatus: draft\n---\n' > task2/plan.md; hp "$T/task2" > .claude/flow/planning
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
rm .claude/flow/current; hp "$T/task" > .claude/flow/planning; plan draft
expect_out   "planner start gets context"              flow-context.sh "$(start_json p1 dev-flow:dev-planner)" "status: draft"
expect_pass  "verify-stop: planner with no changes passes" flow-verify-stop.sh "$(stop_json p1 dev-flow:dev-planner)"

echo "== stale planning pointer: a plan past planning switches the guards off, with a notice"
rm -f .claude/flow/current .claude/flow/stale-notified .claude/flow/notified
plan implementing
expect_allow "stale (implementing): main session edits src"   flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
assert "notice names the pointer, the status and rm" 'case $out in *"systemMessage"*"stale pointer"*"/.claude/flow/planning"*"status: implementing"*"rm "*"additionalContext"*"/dev-flow:dev-implement"*) true;; *) false;; esac'
expect_allow "stale (implementing): git commit passes"        flow-guard.sh "$(bash_json '' 'git commit -m x')"
assert "the notice is given once per session" '[ -z "$out" ]'
expect_allow "stale (implementing): mcp create_pull_request"  flow-guard.sh "$(mcp_json mcp__github__create_pull_request)"
expect_deny  "stale (implementing): dev-implementer still needs current" flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny names the stale pointer, its status and dev-implement" 'case $err in *"stale pointer"*"status: implementing"*"/dev-flow:dev-implement"*) true;; *) false;; esac'
hp "$T/task" > .claude/flow/current
expect_allow "stale planning beside current: spawn dev-implementer" flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
expect_allow "stale planning beside current: main session edits src" flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
rm .claude/flow/current
printf -- '---\ntask: t\nsource: dev-debug\nstatus: implementing\n---\n' > task/plan.md
expect_out  "SessionStart reports the pointer as stale"      flow-session.sh "$(session_json startup)" "stale pointer"
assert "no 'in progress' claim, resume hint names dev-implement" 'case $out in *"in progress"*) false;; *"status: implementing"*"/dev-flow:dev-implement"*) true;; *) false;; esac'
expect_out  "Stop removes the stale pointer and says so"     flow-notify.sh "$(main_stop_json)" "removed stale pointer"
assert "pointer and marker gone, plan.md untouched" '[ ! -f .claude/flow/planning ] && [ ! -f .claude/flow/stale-notified ] && grep -q "status: implementing" task/plan.md'
hp "$T/task" > .claude/flow/planning; plan approved
expect_allow "stale (approved, pointer not deleted): main session edits src" flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
expect_deny  "stale (approved): spawn dev-implementer"       flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny names status approved" 'case $err in *"stale pointer"*"status: approved"*) true;; *) false;; esac'
run flow-notify.sh "$(main_stop_json)"
assert "Stop removes it at approved too" '[ ! -f .claude/flow/planning ]'
hp "$T/task" > .claude/flow/planning; plan done
expect_out  "SessionStart at done: no resume hint"           flow-session.sh "$(session_json resume)" "status: done"
assert "done offers nothing to resume" 'case $out in *"/dev-flow:dev-implement"*) false;; *) true;; esac'
run flow-notify.sh "$(main_stop_json)"
printf '/nowhere/at/all\n' > .claude/flow/planning
expect_allow "dangling planning: main session edits src"     flow-guard.sh "$(write_json '' "$T/src/foo/alpha.txt")"
assert "notice says not a folder and names rm" 'case $out in *"stale pointer"*"/nowhere/at/all"*"not a folder"*"rm "*) true;; *) false;; esac'
expect_deny  "dangling planning: spawn dev-implementer"      flow-guard.sh "$(agent_json dev-flow:dev-implementer)"
assert "deny says not a folder" 'case $err in *"not a folder"*"/dev-flow:dev-implement"*) true;; *) false;; esac'
expect_out  "SessionStart reports the dangling pointer"      flow-session.sh "$(session_json resume)" "not a folder"
expect_out  "Stop names a dangling pointer"                  flow-notify.sh "$(main_stop_json)" "not a folder"
assert "but leaves it for the user to fix or remove" '[ -f .claude/flow/planning ]'
rm -f .claude/flow/planning .claude/flow/stale-notified

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
