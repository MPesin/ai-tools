# Plan format

Single source of truth for the plan structure and section names. `dev-plan`, `dev-planner`, `dev-plan-critic`, `dev-reviewer`, `dev-qa-impact`, and dev-implement's Intake all use this file. A hand-written plan must satisfy it.

## What comes from the project's rules file

This plugin is language-, framework- and platform-agnostic: it defines the flow, the files and the guards, nothing about how a given project is built or styled. Every agent reads the project's own guidance first (CLAUDE.md, AGENTS.md, README, instruction files) and takes from it:

- the build and test commands, and how to scope them to a change;
- which commands are safe to run side by side (for parallel work packages), or that the project has none;
- the plans location, if not `.claude/plans/`;
- code style, naming, comment and test conventions;
- the hosting platform and the read-only tools for fetching PR comments; the work-item tracker and the read-only tool for fetching an item;
- the language of QA documents;
- the review checklist location, if not `.claude/review-checklist.md`.

Where the guidance is silent, agents ask the user or say so in their output; they do not fall back on a tool or convention of their own.

## Task folder

`<plans-location>/YYYY-MM-DD-<task-id-or-topic>/`, where `<plans-location>` is the project's plans location if its guidance names one, otherwise `.claude/plans/`.

```
plan.md            # requirements + steps; frontmatter holds state
plan-critique.md   # dev-plan-critic output
notes.md           # implementation notes (implementer/fixer only; appended, never rewritten)
review-N.md        # Claude review round N, findings with IDs F1, F2...
verify.log         # build/test commands and raw output, appended (>>) by implementer/fixer; [Pn] blocks in package mode
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
2. **A work item or ticket reference** (an ID or URL in the project's tracker). Fetch it with the read-only tool the project's guidance names (an MCP tool or a CLI the session has); otherwise ask the user to paste it. Save title, type, state, description, acceptance criteria, repro steps (bugs), and linked parent/child items with titles to `specs/work-item-<id>.md`. Convert rich text to markdown and record `Source: <tracker> #<id>, fetched <date>`. Never update the work item (the hooks block the writing commands and tools they know; project rules cover the rest).
3. **A document file path** given instead of pasted text. Convert it to markdown with a converter the session has, if any, and save it; otherwise ask the user to paste the relevant sections.

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
Owns: src/orders/**, tests/orders/**
Depends on: none | P0, P2
- [ ] <step: file paths, shape of the change, its own minimal build/test verification>
```

Rules:

- **Heading and ownership syntax.** A package heading is `### P<n> - <name>`. `Owns:` is a comma-separated list of paths or globs relative to the repository root; `*` also crosses directories (`src/Orders/**` and `src/Orders/*` mean the same). The hooks parse this line and refuse edits outside it, so keep it on one line and exact.
- **Disjoint ownership.** No file appears in two packages' `Owns`. Tests live with the package that owns the code under test.
- **Shared touchpoints are sequenced.** Contracts and schemas, DI/registration, project and config files, and anything several packages need go in an early package (`P0`) that the others depend on, or in a final package named `Integration` (`### P<n> - Integration`, `Owns: *`) that depends on all of them.
- **Acyclic dependencies.** Packages with no unmet dependencies form a wave and run in parallel; the next wave starts when the previous one is done.
- **Package-scoped, parallel-safe verification.** Packages in the same wave build and test at the same time in one working tree, so their commands must not write the same build output, regenerate the same artifacts or fetch the same dependencies. Each package verifies only what it owns, with the commands the project's guidance names as safe to run side by side; the `Integration` package carries the full build and the broad test run. If the guidance names no such commands, the planner asks the user or writes a sequential plan.
- **Only when it pays.** Use parallel packages when there are at least two independent ones. Otherwise write a single package, or plain `- [ ]` steps with no `###` headings: that is one package, run sequentially. Lite-mode plans are always sequential.

## Minimum viable manual plan

The least a hand-written plan needs to pass Intake:

- `## Requirements` with `### Acceptance criteria`
- `## Steps` with `- [ ]` items that name file paths (work packages optional: plain steps run as one sequential package)
- per-step build/test verification

Everything else is optional for `source: manual`. Intake lists gaps and the user decides whether to fill them or have `dev-planner` harden the plan (add paths, verification, and facts without changing decisions).

## Lite mode

A task is lite when it has all of: at most 3 steps, no public contract or schema change, and no `specs:`. Lite mode skips the plan critic and allows only 1 fix round; QA impact still runs. The user can force either mode.
