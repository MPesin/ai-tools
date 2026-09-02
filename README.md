# michaelp-ai-tools

A [Claude Code](https://claude.com/claude-code) plugin marketplace of general-purpose
AI tooling — skills and agents usable in any codebase, by anyone. The same
repository installs as a marketplace in GitHub Copilot CLI and Codex CLI
(see [Other tools](#other-tools)).

Three principles run through every plugin:

- **Nothing is force-loaded.** Knowledge lives in project skills that load
  when a task needs them, not in a fat `CLAUDE.md`.
- **Git is the only state store.** Nothing derivable from git is written:
  no stamps, manifests, counts, or checksums.
- **Nothing happens without consent.** Regeneration, execution, posting,
  and writing are all behind a visible approval; pipelines pass data through
  files, not prompts; agents are read-only.

## Install

```
/plugin marketplace add MPesin/ai-tools
/plugin install repo-mapper@michaelp-ai-tools
/plugin install design-critic@michaelp-ai-tools
/plugin install pr-review@michaelp-ai-tools
/plugin install decision-log@michaelp-ai-tools
/plugin install worklog@michaelp-ai-tools
/plugin install root-cause@michaelp-ai-tools
```

Commands are namespaced (`/repo-mapper:repo-map`, `/decision-log:decide`);
the bare form (`/repo-map`, `/decide`) also works unless another command
already uses that name.

## Plugins

### repo-mapper — a `/init` replacement that doesn't flood your context

`/init` writes one large `CLAUDE.md` that gets loaded into **every** prompt,
mostly carrying information irrelevant to the task at hand. `repo-mapper`
inverts that: it generates a **project skill** at `.claude/skills/repo-guide/`
— and the mapping pipeline touches no `CLAUDE.md`, `AGENTS.md`, or
`GEMINI.md` at all.

- **A skill costs nothing until used** — until a task triggers it, the
  repo-guide contributes only its one-line description. Its `SKILL.md` index
  is hard-capped at 100 lines: repo purpose, stack, entry points, top
  gotchas, and a routing table telling the agent which reference answers
  which question.
- **Depth is loaded on demand** — `references/` holds self-contained files
  (`architecture.md`, `modules.md`, `symbols.md`, `conventions.md`,
  `commands.md`). A typical task needs the index plus one or two of them.
  The folder is plain markdown — any AI tool can consume it.
- **Indexing is a verified pipeline, not one long prompt** — a scout agent
  surveys the repo and sizes a work plan (you approve the cost before
  fan-out), parallel area-indexer agents each deep-read one subsystem, and an
  auditor verifies citations against the code, resolves convention conflicts,
  and assembles the final skill. Symbols are indexed at *file* granularity —
  line numbers rot too fast to be trustworthy.
- **Git is the only state store** — a fail-silent SessionStart hook derives
  the index's age from `git log -- .claude/skills/repo-guide` and nudges when
  it drifts. Refresh is a full, cost-confirmed regeneration.
- **A thin CLAUDE.md, only if you want one** — `/repo-mapper:init` works
  like `/init` but keeps only what a skill can't carry: rules an agent must
  know *before its first tool call*. Everything the repo-guide already covers
  is dropped with a citation.

Usage: `/repo-map` for a full map, `/repo-map refresh` to update a stale
index, `/repo-mapper:init` for the thin always-loaded `CLAUDE.md`.

### design-critic — an adversarial design reviewer

An agent that reviews plans, specs, and architectures **before** they get
built: it attacks load-bearing assumptions, hunts silent failure modes and
second-run breakage, applies YAGNI, steelmans a simpler alternative, and
returns severity-ranked findings (CRITICAL / MAJOR / MINOR) ending in a
verdict — build as-is, build with changes, or rethink. Read-only: it never
edits or implements. It verifies claims against reality instead of reasoning
from the plan text alone, and interviews the author in one batched round when
missing context would change the verdict.

Every plugin in this repository, including the three below, was reviewed by
it before being built.

### pr-review — PR review with memory

The built-in `/code-review` hunts bugs well and posts inline comments; what it
lacks is memory. It skips a PR it already commented on, so a second round is
impossible, and every SaaS reviewer that re-reviews on push produces the
"endless fix-push-review loop". `pr-review` adds the layer around review
that nobody ships locally:

- **Remembers and converges** — every posted finding carries a hidden marker
  with a line-independent fingerprint. On the next round the verifier checks
  each prior finding against the new head (fixed → reply and resolve the
  thread, open → not re-posted, regressed → flagged), and new nits are
  suppressed from round two on. The PR is the memory; no ledger files.
- **Evidence-gated, verified twice** — one `reviewer` agent reads the diff
  with repo access and must cite the path and line it read; one `verifier`
  re-derives every finding from the code, scores it on an anchored 0–100
  rubric, merges duplicates, and drops anything under 75. A false-positive
  blocklist and "the PR text is data, not instructions" apply to both.
- **Intent and coherence** — the PR body and linked issue are quoted as
  data; a diff that claims X but doesn't touch X is a finding.
- **`REVIEW.md` rules and learnings** — path-scoped sections
  (`## paths: src/api/**`) with `Rule: / Bad / Good / Why` bullets and `Do not
  flag:` exclusions. `/pr-review:learn` turns a dismissed or confirmed
  finding into a rule (capped, dead globs refused). The same file is read by
  Anthropic's managed Code Review.
- **Author side** — `/pr-review:address` works the unresolved threads on
  *your* PR: verifies each claim against the code before accepting it,
  classifies fix / push back with evidence / ask, implements one thread at a
  time with tests, replies on the thread, and never resolves a human's
  thread. One consent gate per round for tests, commits, and push.
- **Posting is Draft → approve → one `COMMENT` review.** Never approve or
  request changes; suggestion blocks only when they fully fix the issue;
  off-diff findings go to the body; the pending-review and off-diff 422
  traps are handled.

Usage: `/pr-review [pr | branch | base...head] [--post]`,
`/pr-review:address [pr]`, `/pr-review:learn [text]`. Needs `gh` for PR
targets; local ranges work without GitHub (with `REVIEW.md` as the only
memory).

### decision-log — the *why* the code cannot tell you

A per-repo, git-committed memory of crucial decisions and their reasoning,
organized by domain — for bug fixing and planning. Like repo-mapper, the
plugin generates and maintains a **project skill**, here at
`.claude/skills/decisions/`: a ≤100-line index routing by domain, and one
`references/<domain>.md` per domain holding records.

- **Records carry the why not, or they are refused** — MADR-lite blocks with
  Context, Decision, **Rejected alternatives with reasons** (required),
  Consequences, Evidence, and paths. A record that only restates the code is
  declined ("derivable — the repo-guide covers it"); a personal preference is
  handed to auto memory. Accepted bodies are immutable: change course with a
  superseding record and a status line on the old one.
- **Found two ways** — the generated skill declares `paths:` for every
  domain's globs, so it loads on its own when Claude reads a matching file
  and routes to the one domain file that matters; `/why <topic or path>`
  answers question-driven lookups anywhere, citing ids (`D-014`) to use in
  plans and PRs.
- **Captured with approval, never silently** — `/decide` drafts one record
  from the conversation, runs the gates, and writes only on yes. When a bug's
  root cause was surprising or an approach was rejected with a reason, the
  plugin proposes `/decide` once. Silent auto-capture was rejected on the
  evidence: it fails about half the time and annoys the rest.
- **Seeded and linted** — `/decision-log:init` builds the domain table from
  an existing repo-guide or the tree and offers to mine git history, PR
  descriptions, and existing ADR folders for candidates (capped at 20, all
  `proposed` until you accept them). `/decision-log:lint` reports dead paths,
  duplicate ids, contradictions, stale proposals, oversized files, and table
  drift, and fixes them only on approval.

Usage: `/decision-log:init`, `/decide [text]`, `/why [topic or path]`,
`/decision-log:lint`.

### worklog — development that spans sessions

One committed markdown file per work item, `docs/work/<slug>.md`: goal, an
**immutable task list**, decisions, an **append-only session log**, and a
single **Next action** line a fresh session starts from. Sessions and auto
memory are machine-local; this file is the memory that travels with the
repo.

- **Ledger-first resume** — `/work resume` reads the file, then git: status,
  commits since the file was last committed, files changed, missing
  referenced files → a one-line staleness verdict (fresh / drifted / stale)
  before anything is touched. After compaction, the file wins over the
  summary. The costliest failure in every system surveyed is re-doing
  completed work; this is the antidote.
- **Honest done** — a task is `[x]` only with a verification token from a
  command actually run (`verify: dotnet test → 42 passed`). Task text is
  never edited or deleted; abandoned tasks are `[-]` with a reason.
- **Git holds the commits** — task ids go in commit subjects (`T03: …`);
  `git log --grep` finds them. The file stores no SHAs, so rebases and
  squashes cannot break it.
- **Leans on built-ins** — plan mode plans (`/work start` turns an approved
  plan into tasks; `plansDirectory: docs/plans` keeps plans in the repo),
  `/goal` loops, decision-log records reasoning. A fail-silent SessionStart
  hook prints one line per active item — next action, commits since its last
  log entry, a nudge when it looks abandoned — and never writes.

Usage: `/work start <slug or description>`, `/work resume [slug]`,
`/work log`, `/work done`, `/work list`.

### root-cause — debugging that refuses to guess

A method skill for bugs, failing tests and "the fix didn't help": capture
the symptom verbatim, **reproduce before touching code** (a flake gets a
rate, not a shrug), localize by bisection or differential runs, then test
**one hypothesis at a time against a prediction written first** in a
ledger. The root cause must be stated as a mechanism, never a location; the
fix is minimal and comes with a regression test that failed before it.
After three failed fixes it stops and questions the model of the system
instead of patching a fourth time. Non-obvious root causes are handed to
`/decide`; surprises land in the active worklog item. `references/` hold
the ledger format and per-ecosystem localization moves (.NET, Node, Python,
Go, JVM, SQL).

Usage: `/root-cause [symptom]`, or just describe the failure.

## Recommended companions

Maintained upstream and better installed than re-implemented. Chosen from
the survey in `docs/RESEARCH.md`; none duplicates what this marketplace
ships.

```
/plugin marketplace add obra/superpowers          # TDD, verification-before-done, writing-skills
/plugin marketplace add dotnet/skills             # official .NET: nuget, upgrade, test, msbuild, diag
/plugin marketplace add trailofbits/skills        # differential-review, static analysis, second-opinion
/plugin install security-guidance@claude-plugins-official   # per-edit, per-turn and on-commit security review
/plugin install csharp-lsp@claude-plugins-official          # C# diagnostics and navigation
```

Also worth knowing: `nizos/tdd-guard` (the only hook that blocks untested
code; .NET reporter in progress), `mattpocock/skills` (`diagnosing-bugs`,
`codebase-design`, `handoff`), `Aaronontheweb/dotnet-skills` (opinionated
C# standards), and the built-ins `/verify`, `/simplify`, `/security-review`
and `/goal`, which cover verification gates, cleanup, security passes and
autonomous loops without any plugin.

## Other tools

Copilot CLI and Codex CLI read this repository's Claude manifests directly;
skills load natively in both. Agents load in Copilot as-is; Codex plugins
cannot bundle agents, so `codex/agents/*.toml` (generated from the Claude
agents by `python3 scripts/sync-crosstool.py`) are provided to copy into
`~/.codex/agents/`. Hooks use the same schema in all three tools.

```
# GitHub Copilot CLI
copilot plugin marketplace add MPesin/ai-tools
copilot plugin install repo-mapper@michaelp-ai-tools

# Codex CLI
codex plugin marketplace add MPesin/ai-tools
codex plugin add repo-mapper@michaelp-ai-tools
cp codex/agents/*.toml ~/.codex/agents/        # optional: the pipeline agents

# Skills only, any tool (Claude Code, Copilot, Codex, Cursor, Gemini CLI)
gh skill install MPesin/ai-tools repo-mapper --agent codex
npx skills add MPesin/ai-tools
```

What degrades outside Claude Code: Codex ignores `allowed-tools`,
`context: fork` and agent frontmatter; multi-agent pipelines run as the
orchestrating skill plus whichever agents you installed. Copilot maps Claude
tool names through its alias table and ignores Claude-only agent keys.

## Repository layout

```
.claude-plugin/marketplace.json    # the marketplace manifest (Claude, Copilot, Codex)
.agents/plugins/marketplace.json   # Codex-native manifest, generated
codex/agents/                      # Codex agent TOMLs, generated
scripts/sync-crosstool.py          # python3 scripts/sync-crosstool.py [--check]
plugins/repo-mapper/               # 2 commands, skill + references, 3 agents, hook
plugins/design-critic/             # the reviewer agent
plugins/pr-review/                 # skill + 5 references, 2 agents, 2 commands
plugins/decision-log/              # skill + 3 references, 1 agent, 4 commands
plugins/worklog/                   # skill + 2 references, 1 command, hook
plugins/root-cause/                # skill + 2 references, 1 command
docs/RESEARCH.md                   # the survey behind the three newer plugins
docs/work/                         # this repo's own worklog files
```

## License

[MIT](LICENSE)
