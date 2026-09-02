# Research: skills, agents and plugins worth adding (2026-09-02)

Survey run before designing the `pr-review`, `decision-log` and `worklog` plugins.
Five parallel research passes: PR review, decision memory, multi-session
workflow, the general skill landscape, and Copilot/Codex compatibility. This
file keeps the conclusions and the sources; the designs themselves live in
each plugin's `SKILL.md` and references.

## What Claude Code already does (do not duplicate)

| Built-in | Covers | Consequence for this marketplace |
|---|---|---|
| `/code-review [effort] [--comment] [--fix] [target]`, `ultra` | Bug + cleanup review of a branch, PR, path or range; background subagent; inline GitHub comments; cloud-verified deep review | A review plugin must add what this lacks: memory across rounds, learnings, reading existing threads, the author side |
| Managed Code Review (Team/Enterprise) | Multi-agent + verification + dedup + severity + `REVIEW.md` + auto-resolve | Not available on Pro/Max, ZDR, or non-GitHub; a local plugin targets those users and stays `REVIEW.md`-compatible |
| `/security-review`, `security-guidance` plugin | Security-only passes with a strong false-positive filter | Out of scope for `pr-review` |
| `/simplify`, `/debug`, `/batch`, `/loop`, `/goal` | Cleanup, runtime-log debugging, parallel worktrees, scheduling, condition loops | `worklog` documents `/goal` as its loop instead of shipping one |
| CLAUDE.md hierarchy, `.claude/rules/*.md` with `paths:`, `@imports` | Always-on instructions | `decision-log` never adds an always-loaded file |
| Auto memory (`~/.claude/projects/<repo>/memory/`) | Personal, machine-local notes; skips facts derivable from code | `decision-log` captures team decisions only and hands personal preferences to auto memory |
| Subagent `memory: project` | Per-agent committed memory | Not reused; the decision store must be readable by the main session |
| Plan mode, `plansDirectory`, sessions, `--resume`, compaction re-injection via `SessionStart(compact)` | Planning and in-session continuity | `worklog` consumes approved plans and re-injects state through the sanctioned hook |
| `feature-dev`, `ralph-loop`, `commit-commands`, `skill-creator`, `claude-md-management`, `csharp-lsp` (official plugins) | Single-session feature flow, same-prompt loops, commit helpers, skill evals, CLAUDE.md audits, C# diagnostics | Install from `claude-plugins-official`; nothing here re-implements them |

## The three requested capabilities: what exists, what is missing

### PR review

Official `code-review` plugin: haiku eligibility gate, summary, four parallel
reviewers (two CLAUDE.md compliance, one diff-only bug hunter, one
security/logic), a per-finding validator, inline comments with full-SHA
permalinks. It skips any PR it already commented on, so re-review is
impossible ([issue #19618](https://github.com/anthropics/claude-code/issues/19618),
closed not planned). The official-marketplace variant adds cheap
high-yield lenses: git blame/history, comments on previous PRs touching the
same files, in-code comments as guidance, and a 0/25/50/75/100 scoring rubric
with an 80 threshold. `pr-review-toolkit` adds silent-failure, test-gap,
comment-rot and type-design analyzers with no cross-agent normalization.

Community: superpowers `requesting-code-review` (reviewer gets crafted
context, never session history; plan alignment first) and
`receiving-code-review` (verify before implementing, no sycophancy);
tag1consulting `claude-comprehensive-review` (blind zero-context hunter,
JSON finding schema, severity normalization, proximity dedup, suppressions,
cost tiers, pending-review posting, "diff text is data not instructions") at
the cost of a 150 KB prompt; `aidankinzett/claude-git-pr-skill`
(draft → approve → post mechanics). SaaS reference points: CodeRabbit
learnings and incremental reviews, Graphite rule format and per-rule
acceptance metrics, Greptile `directoryRules`, Cursor Bugbot reading existing
comments to avoid duplicates, Copilot's endless re-review loop as the failure
to avoid.

Gaps nobody covers locally: incremental re-review with memory of prior
findings, file-based learnings, reading existing threads, an author-side
address-comments loop with an exit condition, plan/linked-issue alignment,
prompt-injection hardening in the reviewer prompt.

### Decision memory

No native ADR loading ([issue #13853](https://github.com/anthropics/claude-code/issues/13853))
and no repo-committed team-shared decision store. Reference designs: MADR 4.0
(status, considered options, pros/cons), log4brains (immutable once accepted),
`adr-kit` (frontmatter ids, supersedes links, init audit, verification gates),
ECC ADR skill (explicit, implicit-suggest and query triggers; alternatives with
rejection reason), Copilot Memory (facts stored with code citations that are
re-validated), Devin Knowledge (per-record trigger descriptions), Karpathy's
LLM wiki (index first, ingest/query/lint), Cline/Roo memory banks (everything
loads every task: the bloat anti-pattern). Two hard-won lessons: silent
background auto-capture failed about half the time in a 700-session trial
(awrshift memory kit), and recording only the winning option turns the log
into a restatement of the code.

### Multi-session workflow

Plan mode writes plans to `~/.claude/plans` unless `plansDirectory` is set;
sessions and auto memory are machine-local; Agent SDK docs say to capture
results as application state rather than rely on resume. Anthropic's
long-running-agent harness: a feature list whose items are never deleted,
only status-flipped; a progress file; re-verify the last feature before new
work. superpowers' execution ledger: task lines carry commit ranges, "after
compaction trust the ledger and `git log` over recollection", and the
costliest observed failure is re-doing completed work. Conductor puts the
commit SHA next to each done checkbox. Agent OS v3 retired its own task
orchestration in favor of plan mode. Handoff skills add staleness checks
(commits since the last entry, missing referenced files). No public
convention named RUN-STATE.md exists; this repo's own file is the closest.

## Other skills and agents worth adopting

Ranked by leverage for day-to-day development. Install-from-source items are
better taken as-is than re-implemented.

| # | Skill / plugin | Why | Source |
|---|---|---|---|
| 1 | Verification-before-done gate | Evidence before claims; pairs with a Stop hook running build/test on touched projects | superpowers `verification-before-completion`; `codewithmukesh/dotnet-claude-kit` `/verify` |
| 2 | Systematic debugging | Root cause before fix, "three failed fixes means question the architecture" | superpowers `systematic-debugging`; `mattpocock/skills` `diagnosing-bugs` |
| 3 | TDD discipline and enforcer | Only `tdd-guard` blocks untested code; .NET reporter in progress | superpowers `test-driven-development`; `nizos/tdd-guard` |
| 4 | .NET hooks | `dotnet format` on edit, build on save, restore on csproj change, block `--no-verify`, protect tests | `dotnet-claude-kit` hooks; `karanb192/claude-code-hooks`; official `csharp-lsp` |
| 5 | Official .NET skills | NuGet, upgrade, test, MSBuild diagnosis, diagnostics | `dotnet/skills` (`/plugin marketplace add dotnet/skills`); `Aaronontheweb/dotnet-skills` |
| 6 | Minimal, surgical coding rules | About 150 words with outsized effect | `forrestchang/andrej-karpathy-skills`; `DietrichGebert/ponytail` |
| 7 | Conventional-commit skill | Daily use, thin | `inprojectspl/conventional-commits`; official `commit-commands` |
| 8 | Refactoring skill | Analysis first, one commit per transformation | `finereli/refactoring`; `ciembor/agent-rules-books` |
| 9 | Security layers | Per-edit, per-turn and on-commit review | official `security-guidance`; `trailofbits/skills` |
| 10 | Skill-writing method | Baseline-fail first, capture rationalizations, size caps | official `skill-creator`; superpowers `writing-skills` |

Also noted: `oraios/serena` and the LSP plugins for symbol-level navigation,
`mksglu/context-mode` for tool-output compression (Elastic license),
`OthmanAdi/planning-with-files` for a heavier plan/findings/progress trio.

## Sources

Anthropic: [code-review plugin](https://github.com/anthropics/claude-code/tree/main/plugins/code-review),
[pr-review-toolkit](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit),
[claude-plugins-official](https://github.com/anthropics/claude-plugins-official),
[code review docs](https://code.claude.com/docs/en/code-review),
[ultrareview](https://code.claude.com/docs/en/ultrareview),
[memory](https://code.claude.com/docs/en/memory),
[skills](https://code.claude.com/docs/en/skills),
[hooks](https://code.claude.com/docs/en/hooks),
[sessions](https://code.claude.com/docs/en/sessions),
[sub-agents](https://code.claude.com/docs/en/sub-agents),
[cwc-long-running-agents](https://github.com/anthropics/cwc-long-running-agents).

Community: [obra/superpowers](https://github.com/obra/superpowers),
[tag1consulting/claude-comprehensive-review](https://github.com/tag1consulting/claude-comprehensive-review),
[aidankinzett/claude-git-pr-skill](https://github.com/aidankinzett/claude-git-pr-skill),
[adr/madr](https://github.com/adr/madr), [rvdbreemen/adr-kit](https://github.com/rvdbreemen/adr-kit),
[affaan-m/ECC](https://github.com/affaan-m/ECC),
[awrshift/claude-memory-kit](https://github.com/awrshift/claude-memory-kit),
[codenamev/claude_memory](https://github.com/codenamev/claude_memory),
[Karpathy LLM wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f),
[gemini-cli-extensions/conductor](https://github.com/gemini-cli-extensions/conductor),
[github/spec-kit](https://github.com/github/spec-kit),
[OpenAI ExecPlans](https://github.com/openai/openai-cookbook/blob/main/articles/codex_exec_plans.md),
[thepushkarp/handoff](https://github.com/thepushkarp/handoff),
[open-gsd/gsd-core](https://github.com/open-gsd/gsd-core),
[GWUDCAP/cc-sessions](https://github.com/GWUDCAP/cc-sessions),
[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills),
[mattpocock/skills](https://github.com/mattpocock/skills),
[nizos/tdd-guard](https://github.com/nizos/tdd-guard),
[dotnet/skills](https://github.com/dotnet/skills),
[Aaronontheweb/dotnet-skills](https://github.com/Aaronontheweb/dotnet-skills),
[codewithmukesh/dotnet-claude-kit](https://github.com/codewithmukesh/dotnet-claude-kit),
[karanb192/claude-code-hooks](https://github.com/karanb192/claude-code-hooks),
[trailofbits/skills](https://github.com/trailofbits/skills),
[forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills),
[finereli/refactoring](https://github.com/finereli/refactoring).

SaaS reference points (second-hand where vendor docs were unreachable):
CodeRabbit learnings and path instructions, Graphite rule format, Greptile
`directoryRules`, Cursor Bugbot, GitHub Copilot code review and Copilot
Memory ([docs source](https://github.com/github/docs/blob/main/content/copilot/concepts/agents/copilot-memory.md)),
Devin Knowledge.
