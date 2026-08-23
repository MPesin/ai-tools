# Agent Playbook — dispatching the pipeline

Agents (installed by this plugin): `repo-mapper:repo-scout`,
`repo-mapper:area-indexer`, `repo-mapper:index-auditor`,
`repo-mapper:critical-thinker`.

Data flows through files, not prompts: indexers write staging files; the
auditor reads them. Keeps every context small.

## 1. repo-scout (one agent, first)

Prompt must include: repo root path; mode (map|refresh); manifest content if it
exists; any user-stated focus. Ask for its work-plan JSON as the final message.

Sanity-check the returned plan yourself before showing the user:
- excludes cover lockfiles/vendored/generated dirs
- no area estimated above its size cap (scout must split oversized areas)
- refresh mode: areas limited to stale ones + deletions/renames reconciled

## 2. area-indexer (N agents, parallel — single message, one Task per area)

Prompt template per area:
- area name + globs + excludes (from the plan)
- instruction: write findings to `docs/agents/.staging/<area>.md` using the
  staging format below; final message = one-line summary only
- the relevant section caps (symbols rows budget = 150 / N areas, min 10)

Staging file format (sections, all optional except MODULES):
```
# <area>
## MODULES    — path — purpose — key files
## SYMBOLS    — | Symbol | Kind | File | Role |
## CONVENTIONS — claim + example file path each
## ARCHITECTURE — boundaries, flows touching this area
## GOTCHAS    — non-obvious traps
## COMMANDS   — proposed (NOT executed) build/test commands relevant to area
```

## 3. index-auditor (one agent, last)

Prompt must include: mode; work plan; output-spec.md content (or tell it to
read the file); whether user consented to command execution; existing-file
checksums state from preflight. Its job:
- read all staging files; verify a sample (≥10 or all if fewer) of file
  citations exist; drop or fix false ones
- resolve convention conflicts: majority rule + explicit exceptions note
- write final docs/agents/* + AGENTS.md + pointer blocks per output-spec
- refresh mode: rewrite only stale areas' content, reconcile deletions,
  preserve fresh areas' sections verbatim
- write manifest.json (new stamps, checksums), delete `.staging/`
- final message: list of files written + line count of AGENTS.md + anything
  it could not verify

## 4. critical-thinker (optional, offered after assembly)

Prompt: "Review the generated AGENTS.md and docs/agents/ against the actual
code. Flag: claims not supported by the code, missing load-bearing gotchas,
navigation table entries that mislead. Severity-ranked findings only."

## Dispatch rules

- All area-indexers in ONE message (true parallelism).
- Never pass file contents between agents through your own context when a path
  suffices.
- An indexer that fails/returns empty: note the gap in AGENTS.md ("area X
  unindexed") rather than silently omitting — never fake coverage.
