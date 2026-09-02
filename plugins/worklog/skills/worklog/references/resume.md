# Resume — the ledger-first protocol

Run this at the start of a session on an existing work item and again after
any context compaction. The point is to act on the file and git, not on a
summary of earlier sessions.

1. **Pick the item.** Slug argument, else the only `Status: active` file,
   else list them and ask.
2. **Read the whole file.** Note Next action, the first `[~]`/`[ ]` task,
   the last log entry's date and `next:` line, and the Branch.
3. **Where is the repo?**
   - `git status --porcelain` — uncommitted changes exist? Say what they
     touch before doing anything else.
   - Branch check: current branch ≠ `Branch:` → say so and stop until the
     user decides (switch, or update the file).
   - Last log point: `LAST=$(git log -1 --format=%H -- docs/work/<slug>.md)`.
     Empty `LAST` means the file was never committed: say so, and use the
     `Started:` date instead (`git log --oneline --since=<date>`). Otherwise
     `git log --oneline $LAST..HEAD` and `git diff --stat $LAST..HEAD` — what
     moved since the file was last committed. Task commits are the ones
     whose *subject* starts with an id: `git log --format='%h %s' | grep
     -E '^[0-9a-f]+ T[0-9]+:'` (`--grep` alone also matches bodies).
   - Referenced files: for every path named in the file (Goal links, task
     text, surprises), check it exists; missing ones are listed.
4. **Staleness verdict**, one line:
   - fresh — nothing since the last log commit;
   - drifted — N commits since; list them; tasks whose ids appear in commit
     subjects but are not `[x]` are candidates to close (only with a verify
     run, never on the commit's word);
   - stale — the branch differs, referenced files are missing, or 50 or
     more commits since: say "plan may be stale", propose which tasks to
     re-plan, and wait for the user before editing the plan.
   Also compare: task ids that are `[x]` but appear in no commit subject,
   and the reverse — both are reported, neither is auto-corrected.
5. **Offer re-verify.** Name the last `[x]` task and its verify command;
   run it only on yes. A failure is logged as a surprise and turns the task
   back to `[~]`; it does not block starting the next task unless the user
   says so.
6. **Start.** The Next action line decides which task; the first open
   task is only a fallback when Next action is missing or names a task
   that is already `[x]`/`[-]`. A task marked `human-verify` or `blocked:`
   is announced ("waiting on you: T09 …"), not worked — move on to the
   next open task or stop. Announce: "Resuming <slug> at <task id>: <first
   step>". Work the task. Commit with the id in the subject.
7. **Before stopping** (or when the user says "let's stop"), run `log`.

After compaction: the SessionStart hook re-prints the active items; repeat
steps 2-4 before continuing. The file wins over the compaction summary
whenever they disagree.
