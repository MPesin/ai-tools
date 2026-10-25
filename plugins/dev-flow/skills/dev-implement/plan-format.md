# Plan format

Single source of truth for the plan structure and section names. `dev-plan`, `dev-planner`, `dev-plan-critic`, `dev-reviewer`, `dev-qa-impact`, and dev-implement's Intake all use this file. A hand-written plan must satisfy it.

## Task folder

`<plans-location>/YYYY-MM-DD-<task-id-or-topic>/`, where `<plans-location>` is the project's plans location if its guidance names one, otherwise `.claude/plans/`.

```
plan.md            # requirements + steps; frontmatter holds state
plan-critique.md   # dev-plan-critic output
notes.md           # implementation notes (implementer/fixer only; appended, never rewritten)
review-N.md        # Claude review round N, findings with IDs F1, F2...
verify.log         # build/test commands and their output, recorded by the plugin's hooks
human-review.md    # triaged human comments, draft replies, proposed checklist additions
qa-impact.md       # QA impact note from the fixed template (skills/dev-qa-impact/qa-impact-template.md)
needs-decision.md  # disputed findings awaiting the user (written by dev-implement; triggers a notification)
violations.md      # files an agent changed outside its allowance (written by the hooks; triggers a notification)
specs/             # PRD/HLD excerpts and work-item text, saved as markdown
```

Only `plan.md` is required to start. The flow creates the rest. The hooks add `.claude/flow/` (and `.claude/plans/` when the task folder is there) to `.git/info/exclude`, so none of this shows up in `git status`.

## Frontmatter

```yaml
---
task: <id or topic>
source: manual | dev-plan-interactive | dev-plan-draft
mode: full | lite
status: draft | approved | implementing | reviewing | human-review | qa-impact | done | blocked
review_round: 0
specs:            # files in the task folder's specs/ dir (see Specs intake)
  - specs/prd.md
  - specs/hld.md
  - specs/work-item-12345.md
base: <base branch or commit for diffs>
---
```

`status` is updated at every stage transition; resuming reads `status` and `review_round` from here. The status panel plugin (`dev-flow-panel`) and the hooks read the same fields.

## Pointer files

Hooks use these to decide whether anything is active. Each contains the absolute task-folder path as its only line.

- `<project>/.claude/flow/current` — written by `dev-implement` at Intake; renamed to `finished` by the final report.
- `<project>/.claude/flow/planning` — written by `dev-plan` at start, deleted on approval or abandonment.
- `<project>/.claude/flow/finished` — makes the Stop hook send the "done" notification; the hook then deletes it.

The hooks keep their own marker files beside them (`start-*`, `snap-*`, `claim-*`, `notified`); they are removed at `finished`. Deleting the pointer switches every guard off.

## Specs intake

Every spec ends up as a markdown file in the task folder's `specs/`, in one of three ways:

1. **Pasted text.** Save it verbatim as `specs/prd.md`, `specs/hld.md` or `specs/<name>.md`, with a header line: `Source: <doc name/section as the user named it>, pasted <date>, excerpt`. Do not paraphrase or clean up the text.
2. **Azure DevOps work item** (an ID or URL). Fetch it with a read-only Azure DevOps MCP tool if the session has one; otherwise `az boards work-item show --id <id> --org <org>` if the Azure CLI and its devops extension are installed and logged in; otherwise ask the user to paste it. Save Title, Type, State, Description, Acceptance Criteria, Repro Steps (bugs), and linked parent/child IDs with titles to `specs/work-item-<id>.md`. Convert HTML fields to markdown and record `Source: Azure DevOps #<id>, fetched <date>`. Never update the work item (the hooks block the writing commands and tools).
3. **A `.docx` path** given instead of pasted text. Convert with `pandoc` (or `python-docx`) if available and save as markdown; otherwise ask the user to paste.

Excerpts are partial. Every agent that checks conformance states that its check covers only the provided text, and never marks a requirement Missing just because the excerpt does not mention it: it lists what it would need to see ("Not covered by provided specs").

## Required headings

Used verbatim by every agent. `dev-reviewer` and `dev-plan-critic` read the plan by these headings, so they must not be renamed.

- `## Context`
- `## Requirements`, with a `### Acceptance criteria` sub-list
- `## Specs` — which PRD/HLD sections apply, with links
- `## Verified facts` — each fact with evidence: `file:line` or command output; mark anything unverified as an assumption
- `## Steps` — `- [ ]` items, each with exact file paths, the shape of the change, and its own minimal build/test verification; grouped into work packages when the plan is parallel-ready (see Work packages)
- `## Risks`
- `## Open questions` — each with the options and a recommendation; `None` once resolved

## Work packages (parallel-ready plans)

Plans are designed so independent work can run in parallel subagents. Group `## Steps` into work packages:

```
### P1 - <name>
Owns: src/Orders/**, tests/Orders.Tests/**
Depends on: none | P0, P2
- [ ] <step: file paths, shape of the change, its own minimal build/test verification>
```

Rules:

- **Heading and ownership syntax.** A package heading is `### P<n> - <name>`. `Owns:` is a comma-separated list of paths or globs relative to the repository root; `*` also crosses directories (`src/Orders/**` and `src/Orders/*` mean the same). The hooks parse this line and refuse edits outside it, so keep it on one line and exact.
- **Disjoint ownership.** No file appears in two packages' `Owns`. Tests live with the package that owns the code under test.
- **Shared touchpoints are sequenced.** Contracts and schemas, DI/registration, project and config files, and anything several packages need go in an early package (`P0`) that the others depend on, or in a final package named `Integration` (`### P<n> - Integration`, `Owns: *`) that depends on all of them.
- **Acyclic dependencies.** Packages with no unmet dependencies form a wave and run in parallel; the next wave starts when the previous one is done.
- **Package-scoped, parallel-safe verification.** Packages in the same wave build and test at the same time in one working tree, so their commands must not write the same build output or restore the same dependency graph. Each package builds only the projects it owns and skips its dependencies and package restore (they were built by the package it depends on, or in the baseline): `dotnet build <project> --no-dependencies --no-restore` then `dotnet test <test project> --no-build`; `mvn -pl <module>` without `-am`; `npm run build -w <workspace>`; `cargo build -p <crate>`; `go build ./pkg/...`. The `Integration` package carries the full build and the broad test run. If the build tool cannot scope a build safely, the plan is sequential.
- **Only when it pays.** Use parallel packages when there are at least two independent ones. Otherwise write a single package, or plain `- [ ]` steps with no `###` headings: that is one package, run sequentially. Lite-mode plans are always sequential.

## Minimum viable manual plan

The least a hand-written plan needs to pass Intake:

- `## Requirements` with `### Acceptance criteria`
- `## Steps` with `- [ ]` items that name file paths (work packages optional: plain steps run as one sequential package)
- per-step build/test verification

Everything else is optional for `source: manual`. Intake lists gaps and the user decides whether to fill them or have `dev-planner` harden the plan (add paths, verification, and facts without changing decisions).

## Lite mode

A task is lite when it has all of: at most 3 steps, no public contract or schema change, and no `specs:`. Lite mode skips the plan critic and allows only 1 fix round; QA impact still runs. The user can force either mode.
