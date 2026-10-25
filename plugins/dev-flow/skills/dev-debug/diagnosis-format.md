# Diagnosis format

Single source of truth for `diagnosis.md`: `dev-debugger` writes it, the `dev-debug` skill turns it into a fix plan, and the user reads it at the diagnosis gate. The headings are used verbatim.

## Location

`<task folder>/diagnosis.md`. A second, independent diagnosis of the same bug is `diagnosis-2.md` (then `-3`, ...). Reproduction scripts and captured output live under `<task folder>/debug/`. The debugger writes nothing else: no other file in the task folder, nothing in the source tree.

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

## How it maps to plan.md

`dev-debug` builds the fix plan from a confirmed diagnosis (plan structure in `${CLAUDE_PLUGIN_ROOT}/skills/dev-implement/plan-format.md`):

| plan.md | from diagnosis.md |
|---|---|
| frontmatter | `source: dev-debug`, `status: draft`, `mode` by the lite criteria, `specs:` the bug report files, `base` |
| `## Context` | Symptom (expected vs actual) and Root cause, with the reproduction command |
| `## Requirements` and `### Acceptance criteria` | the reproduction no longer reproduces; the regression test passes and fails without the fix; the affected test scope passes; plus the acceptance criteria of the work item, if any |
| `## Specs` | the bug report files under `specs/` |
| `## Verified facts` | Evidence and Reproduction, each with its `file:line` or command |
| `## Steps` | one sequential package: (1) the regression test, run before the fix with its failing output appended to `verify.log`; (2) the Fix steps, root cause first, then each blast-radius site; (3) verification: the regression test, the reproduction command, the affected scope |
| `## Risks` | Blast radius |
| `## Open questions` | Open questions still open after the gate |

`diagnosis.md` stays in the task folder as the record of why the bug happened; the plan carries only what the implementer and the reviewer need.
