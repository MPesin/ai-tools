---
name: worklog
description: Use when development work spans more than one session and needs a durable record — starting a work item from a plan, resuming one in a fresh session, logging what a session did, or closing one — or when /work is invoked. Keeps one committed markdown file per work item in docs/work/ and resumes ledger-first, trusting the file and git over recollection.
when_to_use: Trigger phrases - continue where we left off, what was I working on, pick up the feature, log progress, before we stop - and any feature or bug-fix work that spans sessions.
argument-hint: "[start <slug or description> | resume [slug] | log [note] | done [slug] | list]"
---

# Worklog

One file per work item: `docs/work/<slug>.md`, committed. It holds the goal,
an immutable task list, decisions, an append-only session log, and a single
**Next action** line a fresh session starts from. The session transcript is
not the memory; the file and git are.

| Mode | Load |
|------|------|
| `start` | `references/file-spec.md` |
| `resume` | `references/resume.md` |
| `log`, `done` | `references/file-spec.md` §Updating |
| `list` | nothing — `grep -l '^Status: active' docs/work/*.md` and each file's Next action line |

**Non-negotiables**
- Task text is never edited or deleted. New tasks get new ids; abandoned
  ones are marked `[-]` with a reason. Progress is status changes only.
- A task is `[x]` only with a verification token — `verify: <command> →
  <result>` — from something actually run this session. No token, no tick.
- Commits carry the task id in the subject (`T03: add 4xx test`). The file
  stores no shas: `git log --format='%h %s' | grep ' T03:'` finds them.
  Rebases and squashes cannot break a reference that is not stored.
- Nothing runs (tests, builds) without an offer and a yes, including the
  re-verify step at resume.
- The log is add-only: one new entry per session at the top, ≤15 lines,
  never edited afterwards. Old entries are archived, not rewritten.

## Ledger-first resume, in one breath

Read the file → `git status` → `git log --oneline <last file commit>..HEAD`
→ files changed since → staleness verdict → offer to re-verify the last
`[x]` → start the first `[ ]` or `[~]` task. After compaction, do this again
rather than trusting the summary. `references/resume.md` has the exact steps.

## Fit with other tools

- Plan mode plans the work; `start` turns an approved plan into tasks.
  Setting `plansDirectory: docs/plans` in `.claude/settings.json` keeps plan
  files in the repo next to work files.
- Decisions with reasoning go to the decision-log plugin when installed
  (`/decide`, cite `D-nnn` under Decisions); otherwise a one-line ruling in
  the file.
- For autonomy: `/goal every task in docs/work/<slug>.md is [x] or [-]`.
- The plugin's SessionStart hook prints one line per active item (next
  action, commits since its last log entry, a nudge when it looks
  abandoned). It never writes.
