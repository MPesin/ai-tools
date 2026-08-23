# Freshness — git is the only state store

Principle: information retrievable from git is never stored by the generated
skill. No manifest, no stamps, no checksums.

## How each consumer derives freshness

1. **Any AI reading SKILL.md** — its freshness line instructs: compare
   `git log -1 -- .claude/skills/repo-guide` (when the index last changed)
   with recent repo history; if the repo has moved a lot since, verify
   details against code before relying on them.
2. **SessionStart hook (this plugin)** — pure bash: generation point =
   `git log -1 --format=%H -- .claude/skills/repo-guide`; staleness =
   `git rev-list --count <that>..HEAD`; one generic context line at ≥20
   commits (override: REPO_MAPPER_STALE_THRESHOLD). Silent when: no skill,
   no git, index never committed, or under threshold. Fail-silent, <100ms,
   startup matcher only.
3. **Non-git repos** — SKILL.md keeps its generated-on date comment; that is
   the only freshness signal (degraded mode; no hook signal, no refresh).

## Refresh = full regeneration

`/repo-map refresh` re-runs the whole pipeline (scout → fan-out → auditor)
with the usual cost confirmation. No incremental machinery: the scout may read
the existing SKILL.md as prior context, but every area is re-indexed. If
partial refresh ever proves necessary on a huge repo, it can be reintroduced —
the git history of this plugin contains the manifest-based implementation.

## Protecting user edits

Before overwriting the skill folder, run
`git status --porcelain -- .claude/skills/repo-guide`. Uncommitted changes =
user edits in flight: show them and ask before overwriting. Committed history
needs no protection — git preserves it; recommend committing the regenerated
index as its own commit so any hand edit remains recoverable and diffable.
