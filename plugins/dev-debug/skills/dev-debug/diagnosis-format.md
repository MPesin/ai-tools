# Diagnosis format

Single source of truth for `diagnosis.md`: `dev-debugger` writes it, the `dev-debug` skill turns it into a fix plan, and the user reads it at the diagnosis gate. The headings are used verbatim.

## Task folder

`<plans-location>/YYYY-MM-DD-<bug-id-or-topic>/`, where `<plans-location>` is the project's plans location if its guidance names one, otherwise `.claude/plans/`. The same layout the `dev-flow` plugin uses, so a fix plan written here is picked up by `/dev-flow:dev-implement` without copying:

```
plan.md            # frontmatter holds the state; the fix plan once the cause is confirmed
diagnosis.md       # the debugger's output; diagnosis-2.md (then -3, ...) for an independent second opinion
debug/             # the debugger's reproduction scripts and captured output; never source
specs/             # the bug report, work item, stack trace or log excerpt, saved as markdown
violations.md      # written by the dev-flow hooks when an agent changed a file outside its allowance
```

The debugger writes nothing but `diagnosis*.md` and files under `debug/`: no other file in the task folder, nothing in the source tree.

## Specs intake

The bug report reaches the debugger as files under `specs/`, listed in the plan's `specs:`:

1. **Pasted text** (report, stack trace, log excerpt, failing test output): saved verbatim as `specs/bug-report.md` with a header line `Source: <where it came from, as the user named it>, pasted <date>`. Never paraphrased or cleaned up. Facts the user adds later are appended under a dated line.
2. **A work item or ticket reference**: fetched with the read-only tool the project's guidance names, otherwise pasted by the user; saved as `specs/work-item-<id>.md` with title, type, state, description, repro steps, acceptance criteria and `Source: <tracker> #<id>, fetched <date>`. The work item is never updated.
3. **A document file path**: converted to markdown if the session has a converter, otherwise the user pastes the relevant sections.

A theory in the report ("I think the cache is stale") stays in the file as the reporter's words; the debugger reads it as a hypothesis to test.

## Header

The file starts with three lines, before any heading:

```
Confidence: High | Medium | Low
Reproduced: yes | no | partially
Root cause: <one sentence, or "not found">
```

- **High**: the bug was reproduced, and the cause was confirmed by a prediction that came true (a specific input, call or state that the cause says must fail did fail, and one it says must pass did pass).
- **Medium**: reproduced, and one cause explains every observation, but it was not isolated from an alternative by a test.
- **Low**: not reproduced, or several candidates remain. A Low diagnosis still lists the candidates with the evidence for each; the fix section then says what would settle it, not what to change.

## Required headings

- `## Symptom` — expected behaviour, actual behaviour, the inputs and environment, since when, and who is affected. Separate what was observed (by the debugger or in attached output) from what the report asserts.
- `## Reproduction` — the exact command(s) and the trimmed raw output that shows the failure, or what was tried and why it did not reproduce. Name the scripts and captures under `debug/`.
- `## Root cause` — the defect in plain words, then the code (`file:line`) and the mechanism from input to failure, step by step.
- `## Evidence` — each observation that supports the cause with its `file:line` or command output, and the prediction that was tested with its result.
- `## Hypotheses ruled out` — a table `hypothesis | how it was tested | result`. The reporter's own theory, if the report has one, is a row here or the root cause; never silently adopted.
- `## Blast radius` — other code paths carrying the same defect (`file:line`), other callers of the defective code, data or persisted state already affected, and the commit that introduced the defect when history shows it.
- `## Fix` — `- [ ]` steps with exact file paths, the shape of each change, and the minimal build/test verification per step: the smallest change at the root cause, repeated at every blast-radius site. Then the alternatives considered and why they were rejected, and the symptom patches to avoid.
- `## Regression test` — where the test goes (an existing test file or a new one, by path), what it asserts, and why it fails today and passes after the fix.
- `## Open questions` — each with options and a recommendation; `None` if none. Includes any instrumentation the debugger would have needed and could not add without editing source.

## The fix plan

`dev-debug` builds `plan.md` from a confirmed diagnosis. The plan is the contract with the `dev-flow` plugin: its `skills/dev-implement/plan-format.md` is the authoritative definition, and this section mirrors the parts the fix plan needs (change both together).

Frontmatter:

```yaml
---
task: <bug id or topic>
source: dev-debug
mode: full | lite
status: diagnosing | draft | approved | done
review_round: 0
specs:
  - specs/bug-report.md
base: <merge-base with the default branch>
---
```

`status` is `diagnosing` from the moment the task folder is created until the user confirms the cause (the dev-flow hooks and the dev-flow-panel read it: the panel shows Diagnosing, then Confirm cause once `diagnosis.md` exists; the Stop hook notifies once at intake and again at the gate), `draft` while the fix plan is written, `approved` when handed to `/dev-flow:dev-implement`, `done` when the user stops at the diagnosis. `mode` is `lite` only when the plan has at most 3 steps, changes no public contract or schema, and has no `specs:`; a bug report under `specs/` therefore makes most fixes `full` (three fix rounds, a QA note checked against the report).

Required headings, verbatim, in this order: `## Context`, `## Requirements` with a `### Acceptance criteria` sub-list, `## Specs`, `## Verified facts`, `## Steps` (`- [ ]` items with exact file paths and each its own minimal build/test verification; a bug-fix plan is one sequential package, no `###` package headings), `## Risks`, `## Open questions`.

| plan.md | from diagnosis.md |
|---|---|
| `## Context` | Symptom (expected vs actual) and Root cause, with the reproduction command |
| `## Requirements` and `### Acceptance criteria` | the reproduction no longer reproduces; the regression test passes and fails without the fix; the affected test scope passes; plus the acceptance criteria of the work item, if any |
| `## Specs` | the bug report files under `specs/` |
| `## Verified facts` | Evidence and Reproduction, each with its `file:line` or command |
| `## Steps` | (1) the regression test, run before the fix with its failing output appended to `verify.log`; (2) the Fix steps, root cause first, then each blast-radius site; (3) verification: the regression test, the reproduction command, the affected scope |
| `## Risks` | Blast radius |
| `## Open questions` | Open questions still open after the gate |

`diagnosis.md` stays in the task folder as the record of why the bug happened; the plan carries only what the implementer and the reviewer need.

## Pointer file

`<project>/.claude/flow/planning` holds the absolute task folder path as its only line while the diagnosis is in progress. It is the dev-flow plugin's planning pointer: when dev-flow is installed, its hooks then guard the debugger (only `diagnosis*.md` and `debug/` writable; any other change to the working tree reported) and the main session (only the task folder writable; no commit, push or posting), notify at the gate, and re-inject the state after a restart. Without dev-flow the file is harmless. `dev-debug` deletes it on approval, on `diagnosis only`, and when the task is abandoned.
