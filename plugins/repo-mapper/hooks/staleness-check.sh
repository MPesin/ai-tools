#!/bin/bash
# repo-mapper staleness check — SessionStart(startup) hook.
# Reads ONLY .claude/skills/repo-guide/manifest.json. Fail-silent on every error path.
exec 2>/dev/null

MANIFEST=".claude/skills/repo-guide/manifest.json"
[ -f "$MANIFEST" ] || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

python3 - "$MANIFEST" <<'PY' 2>/dev/null || exit 0
import json, subprocess, sys, fnmatch

def git(*args):
    return subprocess.run(("git",) + args, capture_output=True, text=True, timeout=3)

try:
    m = json.load(open(sys.argv[1]))
    stamp = m["generated_commit"]
    threshold = int(m.get("stale_threshold_commits", 5))
    # stamp unreachable (squash/rebase/rewrite/shallow) -> tell, don't diff
    if git("cat-file", "-e", stamp + "^{commit}").returncode != 0:
        msg = "repo-mapper: index stamp commit is unreachable (history rewritten?) — run /repo-map to regenerate."
    else:
        base = git("merge-base", stamp, "HEAD").stdout.strip()
        if not base:
            sys.exit(0)
        n = int(git("rev-list", "--count", base + "..HEAD").stdout.strip() or 0)
        if n < threshold:
            sys.exit(0)
        changed = git("diff", "--name-only", base + "..HEAD").stdout.splitlines()
        if not changed:
            sys.exit(0)
        stale = sorted({
            a["name"] for a in m.get("areas", [])
            for g in a.get("globs", [])
            for f in changed
            if fnmatch.fnmatch(f, g) or fnmatch.fnmatch(f, g.replace("/**", "/*"))
        })
        if not stale:
            sys.exit(0)
        msg = (f"repo-mapper: repo index is {n} commits stale "
               f"(areas: {', '.join(stale)}) — run /repo-map refresh to update.")
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "SessionStart", "additionalContext": msg}}))
except SystemExit:
    raise
except Exception:
    pass
PY
exit 0
