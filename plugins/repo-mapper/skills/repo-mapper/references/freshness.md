# Freshness — stamps, staleness, refresh correctness

## Stamps

- Whole index: `manifest.generated_commit` (full sha) + date; short sha in the
  human-readable header of every generated file and in the SKILL.md freshness line.
- Per area: `areas[].stamp` — the commit that area was last indexed at.

## Staleness detection (three consumers)

1. **Any AI reading SKILL.md** — the freshness line instructs: long
   `git log <stamp>..HEAD` → verify before relying; suggest /repo-map refresh.
2. **SessionStart hook (Claude, this plugin)** — `hooks/staleness-check.sh`.
   Reads ONLY manifest.json. Silent unless: in a git repo AND manifest exists
   AND stamp resolves AND commits-since-merge-base ≥ stale_threshold_commits
   AND changed files intersect indexed globs. Then injects one context line
   naming the stale areas. Fail-silent on every error path; must stay <100ms.
   Startup matcher only (not resume/compact) — one nag per session max.
3. **Non-git or non-Claude** — the SKILL.md freshness line is the mechanism. No git
   hooks are ever installed.

## Refresh algorithm

1. Read manifest. `git cat-file -e <stamp>^{commit}` — unreachable (squash
   merge, rebase, rewrite, shallow clone) → tell user and fall back to FULL
   regeneration. Never diff against an unreachable stamp.
2. Per area: `git diff --name-only <area.stamp>..HEAD` filtered by area globs.
   Non-empty → stale.
3. Reconcile structure BEFORE indexing: paths in manifest globs that no longer
   exist → area is deleted/renamed; scout must re-derive that area's boundaries
   from the current tree (and remove dead entries from all reference files —
   stale-but-described-as-current is worse than unindexed).
4. New top-level dirs not matched by any area's globs → scout assigns them to
   an existing area or creates a new one.
5. Only stale/changed/new areas get indexers. Auditor preserves fresh areas'
   generated content verbatim and re-stamps only what was rebuilt.

## Generated-region edit detection

Before overwriting any generated file, hash its current content (whole-file
sha256) and compare to manifest.checksums. Mismatch = user edited inside
a generated region: show current vs proposed and ask; on approval fold their
edit into the regenerated content (their edits usually encode a real gotcha —
consider promoting it to the Gotchas section).

## Degraded mode (no git)

Stamp = date only. No refresh (always full regen), no hook signal, freshness
line says "generated <date>; no git available — treat details as decaying."
