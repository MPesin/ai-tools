# Capture — init, decide, why

## Init

1. Stop if `.claude/skills/decisions/SKILL.md` exists (offer `lint` instead).
2. Propose domains. Sources, in order of preference: an existing repo-guide
   (`.claude/skills/repo-guide/references/modules.md` — its subsystems are the
   domains, with their paths); otherwise the top-level source directories,
   merged to 3-8 domains. Always add a `build` domain (build files, CI,
   toolchain) — most cross-cutting "why" lives there.
3. Show the domain table, take edits, then write `SKILL.md` per
   record-spec.md and one header-only `references/<domain>.md` per domain.
4. **Offer seeding** (never automatic): dispatch `decision-log:decision-miner`
   with the domain table. It returns ≤20 candidates, most recent first. Show
   them as a numbered list (id-less); the user picks which to keep. Kept
   candidates are written with `status: proposed` and the mined evidence;
   the user can `accept` them one by one now or later via `decide`. The
   miner's candidates are claims from history, not facts — never mark them
   `accepted` on the miner's word.
5. Recommend a commit: `decisions: initialize skill (<n> domains, <m>
   seeded)`.

## Decide

Input: the argument, or the decision reached in this conversation.

1. Read `SKILL.md`; pick the domain by the record's paths (ask when two
   match, or propose a new domain when none does — a new domain adds a table
   row and a `paths:` entry).
2. Draft the record per record-spec.md: id = max + 1, today's date,
   `status: accepted` (the user is confirming it now), paths, Context,
   Decision, Rejected, Consequences, Evidence (the current branch/PR/commit
   if relevant).
3. Gates — decline with the reason when one fails:
   - **Why, not what.** If the record would be true by reading the code
     (`Decision: the service uses Dapper`) with no constraint or rejected
     alternative behind it, decline: "this is derivable — the repo-guide
     covers it."
   - **Rejected alternative present** or an explicit "none considered
     because …". Ask for it once if missing.
   - **Not personal.** "I prefer tabs" → auto memory; say so.
   - **Paths match** at least one tracked file (`git ls-files <glob>`).
   - **Not a duplicate.** `grep -il "<subject>" references/*.md`; if a
     record on the same question exists, offer supersede (new record +
     status line on the old one) instead of a parallel record.
4. Show the full record and the target file. Write only on yes. Append the
   record; add the status line to a superseded record; update the table and
   `paths:` if a domain was added.
5. Recommend a commit: `decisions: D-<n> <title>`.

Supersede mechanics: new record's Context starts with "Supersedes D-<old>:
…"; the old record gets `status: superseded-by D-<new> (<date>)` directly
under its metadata line; nothing else in the old record changes.

## Why (query)

1. Argument is a topic or a path. Path → the domain(s) whose globs match →
   read those files. Topic → `grep -il` over `references/*.md` for the
   topic's words and obvious synonyms; read the matching records only.
2. Answer in ≤30 lines: for each relevant record, its id, title, one-line
   decision, the rejected alternatives, and consequences that matter to the
   question. Accepted records first; superseded ones only when the question
   is about history or when they explain a rejected direction.
3. No matching record → say so plainly, then answer from the code if you
   can, and propose `/decide` if the conversation surfaces the reason.
4. When the caller is a plan or bug fix, end with "cite as D-<n>".

## Implicit capture moments (propose, never write)

- A bug's root cause was non-obvious and a guard or convention now exists
  because of it.
- The user rejected a proposed approach with a reason ("no, use X because").
- A plan weighed alternatives and chose one for a stated reason.
- A dependency, framework, or storage choice was made or reversed.

Proposal wording, once: "Worth recording? `/decide <one-line summary>`".
