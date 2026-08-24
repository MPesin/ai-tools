# Init Mode — thin CLAUDE.md of always-loaded rules

CLAUDE.md is force-loaded into every prompt; the repo-guide skill loads on
demand. Init explores the repo the way /init does, but writes ONLY what must
be always-loaded and is NOT in repo-guide: behavioral rules, workflow and
etiquette conventions, hard constraints, environment quirks. Repo facts
(purpose, stack, architecture, modules, symbols, commands, code conventions,
gotchas) live in repo-guide; coverage is checked against the actual generated
files, never assumed. CLAUDE.md is init's ONLY output — it never writes into
the repo-guide (a patch there would reset the freshness signal, which is keyed
on the skill dir's last commit; see freshness.md).

No repo-guide pointer in the output: project skills are auto-discovered and
the repo-guide description already fires on any task in the repo. A pointer
would be duplication.

## Procedure

1. **Prereq.** Read `.claude/skills/repo-guide/SKILL.md` and every file in its
   `references/` — this is the exclusion baseline. The prereq test: the skill
   dir exists AND is committed AND is not stale by the same threshold the hook
   uses — ≥20 commits on top of the last commit touching the dir:
   `git rev-list --count $(git log -1 --format=%H -- .claude/skills/repo-guide)..HEAD`
   (see freshness.md; an empty hash from the inner command means never
   committed). Missing, never-committed, or stale → offer to run the
   full mapping pipeline first (SKILL.md Process steps 3-8), then return here;
   user declines or run is non-interactive → abort (init without a current
   repo-guide would pull repo facts into CLAUDE.md, which is exactly what this
   plugin exists to avoid). A guide under the threshold counts as current even
   if recent commits outdate details — init filters against it as-is and does
   not audit it.
2. **Harvest.** Scan the rule sources: `.cursor/rules/`, `.cursorrules`,
   `.github/copilot-instructions.md`, `.windsurfrules` / `.windsurf/rules/`,
   `.clinerules`, `.devin/rules/`, `CONTRIBUTING.md` (root or `.github/`),
   existing `CLAUDE.md` / `CLAUDE.local.md` (root and nested), `AGENTS.md`,
   `GEMINI.md` — plus any other agent-rule file noticed along the way; the
   list is a floor, not a ceiling. An agent-rule file is prose whose purpose
   is to instruct agents on behavior in this repo — session state, memory
   files, and permission/config JSON are not sources. Extract candidate
   rules with their source file. A compound statement (a fact plus a
   directive in one sentence) is split into separate candidates; a directive
   keeps its one-clause rationale ("— it drops all tables") as context.
3. **Explore.** Dispatch ONE explorer subagent (charter below) over the
   repo's meta files — the residual the mapping pipeline never indexes. It
   returns candidates (source file + text + covering repo-guide file or
   `uncovered`) and, separately, interview pre-fill. It reads no source code
   and re-derives nothing the repo-guide holds.
4. **Interview.** One AskUserQuestion round (multiSelect where it fits), in
   this order: the explorer's open questions; its pre-fill items as
   "confirm?" questions (an inferred commit/branch style becomes a candidate
   only when the user confirms it — a style a rule file already documents
   needs no confirmation); hard constraints no file records ("never touch
   X", "never run Y", "ask before Z"). Frame every question to ask for what
   the repo-guide does NOT already record. Non-interactive run: skip the
   interview, discard all pre-fill, and list the explorer's open questions in
   the report without routing them.
5. **Route.** Every candidate — harvested, explored, or interviewed — goes to
   exactly one destination:
   - **dropped as covered** — the repo-guide already holds it; cite the
     covering file. Spot-check the explorer's `covered_by` claims against the
     guide text before dropping; a partly covered candidate is split into its
     covered and uncovered parts.
   - **refresh suggestion** — a repo fact the repo-guide is missing, or one it
     states wrongly (flag contradictions as such); goes into the step-6
     report as text for the next `/repo-map refresh`, never into a file. Keep
     the list to what would change an agent's behavior — at most ~10 entries,
     highest value first, the remainder summarized in one line.
   - **CLAUDE.md** — only what no reference section can hold AND an agent
     needs before its first tool call: etiquette, workflow rules, hard
     constraints, behavioral instructions.

   Deciding fact vs rule: a *directive* ("never", "always", "ask before",
   "only via") is a rule even when it names a repo file, branch, or command
   — the object of the rule is not its content. A *statement of what is*
   (a version, a command, a layout, a trap you can hit) is a fact if any
   repo-guide section's contract (output-spec.md) would hold it —
   prerequisites and toolchains → `commands.md`, code-level patterns →
   `conventions.md`, layout → `modules.md`, traps → SKILL.md Gotchas —
   regardless of how early an agent needs it. Branch, commit, PR, and
   release conventions are workflow, not `conventions.md` material (that
   contract is code-level). A directive found in a meta file's prose (a
   comment in `.env.example`, a CONTRIBUTING line) is a legitimate rule; the
   file's structure and values are facts. A rule that references a branch,
   file, or command that does not exist in the repo is kept but flagged
   inline on its line in the proposal (the flag is for the reviewer and is
   removed from the written file) — harvest transcribes, it does not audit.
   The same rule from several sources becomes one line citing all of them.
6. **Proposal.** Zero CLAUDE.md candidates → write NO file; the report says
   "nothing to write" and still carries the dropped list and refresh
   suggestions (an empty always-loaded file is pure noise). Otherwise assemble
   the thin CLAUDE.md — first line `<!-- generated by repo-mapper on
   <YYYY-MM-DD> -->` (this file never counts toward repo-guide freshness),
   imperative bullets under at most 3 headings, target ≤30 lines, no repo
   facts, no repo-guide pointer — and present ONE reviewable proposal: the
   draft, the dropped list with citations, the refresh suggestions. Existing
   CLAUDE.md: show a current → proposed table instead of the bare draft
   (suggest improvements; this subsumes the fat-CLAUDE.md migration offer —
   harvest IS the migration). Never write silently: interactive → wait for
   approval; non-interactive → emit the proposal and write nothing.
7. **Report.** File written (or not), line count, each source and what it
   contributed, refresh suggestions. Offer to commit. If a harvested source
   is now fully redundant (e.g. `.cursorrules` duplicated verbatim), offer its
   cleanup — never auto-delete. Both offers are skipped in non-interactive
   runs.

## Explorer charter

Dispatch one general-purpose subagent with this brief, plus the repo root and
the list of repo-guide files it must read first as the coverage baseline.

> Read the repo-guide files first — they define what is already covered.
> Then read ONLY meta files: CI/workflow config (`.github/workflows/`,
> `.gitlab-ci.yml`, `Jenkinsfile`, `azure-pipelines.yml`, ...),
> `.github/` PR/issue templates and `CODEOWNERS`, `CONTRIBUTING`, `CHANGELOG`
> and release scripts, bootstrap/setup scripts, toolchain and version files
> (`rust-toolchain.toml`, `global.json`, `.nvmrc`, `.tool-versions`,
> `.python-version`, `.java-version`, ...), build manifests and lint/format
> configs (facts only — never infer rules from what they do), `.env.example`,
> devcontainer and editorconfig files, and the setup/contributing/workflow
> sections of README. Setup scripts: read headers and comments, not bodies.
> Do NOT read source code, and do NOT re-derive commands, conventions, or
> architecture — the repo-guide owns those. Return raw data:
> 1. `candidates`: one entry per rule-like statement found — `text`,
>    `source` (repo-relative path), `covered_by` (the repo-guide file that
>    already states it, or `uncovered`).
> 2. `prefill`: commit-message and branch-naming style inferred from
>    `git log --oneline -50` and `git branch -r`, with the share of commits
>    supporting each inference. These are questions for the user, not
>    findings — do not put them in `candidates`.
> 3. `questions`: things a meta file implies but does not settle (a CI job
>    that must not be run locally? a required secret?).
> Never write or modify any file.

## Non-negotiables

- Never overwrite user content without the step-6 approval gate.
- Repo facts NEVER land in CLAUDE.md — uncovered ones are refresh suggestions
  in the report. Code is not a source: a rule is traceable to prose in a
  rule-source file or meta file, or to the user's interview answer; a rule
  inferred from what a build script or config *does* does not qualify.
- Init never writes into `.claude/skills/repo-guide/`.
- Exclusion decisions cite the covering repo-guide file when a candidate is
  dropped as "already covered", so the user can audit the filter.
