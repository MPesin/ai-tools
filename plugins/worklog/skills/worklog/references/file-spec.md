# Work file spec — `docs/work/<slug>.md`

Slug: kebab-case, ≤40 chars, from the feature or issue (`oauth-login`,
`fix-1234-null-order`). One file per work item; parallel work items never
share a file, so worktrees and teammates do not conflict.

```markdown
# OAuth login
Status: active · Branch: feat/oauth-login · Started: 2026-09-02
Next action: T03 — write the failing test for the refresh-token path (tests/Auth/RefreshTests.cs)

## Goal
Two or three sentences: what done looks like, and what is out of scope.
Links: issue, spec, plan file (docs/plans/2026-09-02-oauth.md).

## Plan
- [x] T01 Add OAuth client config and DI registration (verify: dotnet build → 0 errors)
- [x] T02 Login endpoint happy path with test (verify: dotnet test --filter Login → 3 passed)
- [~] T03 Refresh-token path with test (verify: dotnet test --filter Refresh)
- [ ] T04 Logout revokes refresh token (verify: dotnet test --filter Logout)
- [ ] T05 Checkpoint: manual login against the staging IdP (human-verify)
- [-] T06 Remember-me cookie (dropped: out of scope per D-031)

## Decisions
- D-031 (decision-log): no remember-me in v1.
- Ruling: tokens stored server-side — client storage was rejected for XSS exposure — cost if wrong: one extra table.

## Open questions
- Does staging IdP support PKCE? (blocks T05)

## Log
### 2026-09-02
- done: T01, T02
- surprises: IdP metadata endpoint needs a trailing slash (see src/Auth/Discovery.cs)
- next: T03

### 2026-09-01
- done: file created from plan; T01 started
- next: T01
```

## Rules by section

- **Header line 2**: `Status: active | paused | done`, `Branch:`, `Started:`.
  The hook reads `Status:`; keep the exact spelling.
- **Next action**: one line, rewritten every session, naming a task id and
  the first concrete step. This is what a fresh session (or the hook) shows.
- **Goal links**: repo paths or URLs only — resume checks that every path
  exists, so prose must not be written as a link.
- **Plan**: `- [ ] Tnn <text>` per task; ids zero-padded, never reused.
  States: `[ ]` todo, `[~]` in progress, `[x]` done with a verify token,
  `[-]` dropped with a reason. Task text is frozen once written; split or
  re-scope by adding tasks. Checkpoint tasks (`human-verify`) are ordinary
  rows so human gates survive across sessions. Size tasks so one fits in one
  session.
- **Verify token**: on a `[x]` row, `(verify: <exact command> → <short
  result>)` — the command was run this session; quote its real result. For a
  human or review checkpoint, the check performed and its outcome (`verify:
  design review → WITH CHANGES, adopted`). Open rows may carry the planned
  command without an arrow; the arrow and result are what `[x]` requires.
- **Decisions**: either a decision-log id or a one-line ruling
  `what — why — cost if wrong`. No paragraphs.
- **Open questions**: things only a human can settle; remove when settled
  and record the answer as a decision or a task.
- **Log**: newest first, entries added and never edited; one `### <date>`
  per session (suffix `-2` for a second session the same day); bullets
  `done`, `surprises`, `next`, optionally `tried` for things that failed and
  why. ≤15 lines.
  When the section exceeds ~150 lines, move everything but the latest
  three entries to `docs/work/archive/<slug>.md` (committed).

## Start

1. Source of the tasks, in order: a plan file given as a path; the plan
   approved in this conversation; when neither exists and `plansDirectory`
   is set, its files listed by modification time — propose the newest and
   confirm, never assume; otherwise the description argument (a bare slug
   with no description → ask for one). From a description alone, draft the
   tasks yourself and mark the whole Plan as proposed until the user
   confirms it; when more than five tasks emerge, suggest plan mode first.
2. Draft the file: goal from the plan's intent; tasks from its steps, each
   with a concrete verify command where one exists; checkpoint tasks where
   the plan needs a human; decisions the plan already made.
3. `Branch:` is the current branch unless that is the default branch, in
   which case ask once for the feature branch to use.
4. Show the file; write on yes; recommend the commit
   `worklog: start <slug>` (no task id — nothing was done yet).

## Updating (`log`, `done`)

- `log`: from what happened this session — tasks whose verify command ran
  and passed become `[x]` with the token; the one being worked becomes
  `[~]`; new tasks discovered get new ids; a new `###` entry goes at the top
  of Log; Next action is rewritten. Show the diff; write on yes; offer the
  commit `<current task id>: log session` (or fold the file into the task's
  own commit if the user prefers — ask once per work item).
- `done`: every task `[x]` or `[-]`; every `[x]` has a token; Open
  questions empty or moved to decisions/tasks; `Status: done`; final log
  entry with the outcome. Offer to record any ruling worth keeping via
  `/decide`.
- `paused`: set by the user, or suggested when the hook reports the item
  looks abandoned.
