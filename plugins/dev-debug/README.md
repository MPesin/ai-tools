# dev-debug

Find the cause of a bug before anyone changes code. A clean-slate, read-only debugger subagent reproduces the bug, tests hypotheses against the code and git history, and writes `diagnosis.md`; you confirm the root cause; the diagnosis becomes an approved fix plan with the regression test as its first step, which the [dev-flow](../dev-flow) plugin implements, reviews and QA-notes. Works on Linux, macOS and Windows (Git Bash).

```
/plugin install dev-debug --marketplace MPesin/ai-tools
```

## Skill

- `/dev-debug:dev-debug` - intake the bug report (pasted text, stack trace, failing test, log excerpt or a work item ID, saved verbatim under the task folder's `specs/`), run the debugger, stop at the **diagnosis gate**, and on `fix` write the fix plan and invoke `/dev-flow:dev-implement`. At the gate you can also add facts ("it also happens when ..."), ask for a `second opinion` (a fresh debugger that knows nothing of the first, writing `diagnosis-2.md`; offered when confidence is below High), stop with `diagnosis only`, or close with `already fixed` when the fix is already on the branch (the diagnosis records the commit; the QA note and the regression test are then planned from it, since the implement flow starts at Implement). Every exit deletes the `planning` pointer. A bug whose cause is already confirmed does not need this plugin: `/dev-flow:dev-plan` plans the fix directly.

The diagnosis headings, the task folder, the specs intake, the fix plan contract and the pointer file are defined in `skills/dev-debug/diagnosis-format.md`.

## Agent

`dev-debugger` (read-only). Pins the symptom, reproduces with the project's own run and test commands, follows the stack trace or log into the code and reads every function on the path in full, uses git history read-only (`git log -S`, `git blame`, `git diff good..bad`; never checkout, bisect or stash), lists candidate causes and tests each with an observation that distinguishes it, searches for sibling sites and other callers, and proposes the smallest fix at the cause plus a regression test that fails today. It time-boxes itself: three dead hypotheses in a row end in an honest Low-confidence diagnosis rather than a guess.

It never edits source, not even to add a print statement. The only files it writes are `diagnosis*.md` and reproduction scripts or captured output under `debug/` in the task folder. Instrumentation it would have needed goes under the diagnosis's open questions for you to add by hand.

## What it writes

```
<plans-location>/YYYY-MM-DD-<bug>/
  plan.md          # status diagnosing -> draft -> approved (or done for diagnosis only); source dev-debug
  diagnosis.md     # Confidence / Reproduced / Root cause header, then Symptom, Reproduction, Root cause, Evidence,
                   # Hypotheses ruled out, Blast radius, Fix, Regression test, Open questions
  diagnosis-2.md   # independent second opinion, on request
  debug/           # reproduction scripts and captured output
  specs/           # the bug report and work item, verbatim
```

`diagnosis.md` stays as the record of why the bug happened; the plan carries only what the implementer and the reviewer need.

## With and without dev-flow

The task folder layout, the plan format and the `.claude/flow/<branch>/planning` pointer are dev-flow's. With `dev-flow` installed:

- the flow lives on the branch (`.claude/flow/<branch>/planning`): a bug can be parked and another task started on another branch of the same checkout, each with its own status and messages; no flow starts on `main` or `master`, the skill asks for a branch first;
- its hooks guard the run: `dev-debugger` may write only `diagnosis*.md` and `debug/`, any other change to the working tree is reported in `violations.md`, the main session may write only the task folder, and commit, push and posting are blocked;
- its Stop hook sends a desktop notification at the diagnosis gate (`waiting for you (confirm-cause)`), and a restarted session is pointed back at `/dev-debug:dev-debug <task folder>`; a `planning` pointer left behind once `plan.md` is past `diagnosing`/`draft` is reported as stale, not enforced, and removed at the next Stop; a diagnosis can start while another task's `current` pointer is parked at human-review (the debugger is keyed on `planning`, though the gate notification and the band then follow the parked task);
- `/dev-flow:dev-implement` runs the fix plan: the implementer writes the regression test first and appends its failing run to `verify.log` before fixing, the reviewer checks cause over symptom, the QA note lists the reported scenario as the first regression test;
- the `dev-flow-panel` band gives a bug task its own stage list (Diagnosing, Confirm cause, Approved, then the implementing steps) and its Debug button starts or resumes this skill.

Without `dev-flow`, the skill and the agent still run and the diagnosis and plan are still written; the agent's own rules are then the only guard, and the plan waits for `dev-flow` or a human to implement it.


## How it runs

```mermaid
sequenceDiagram
    autonumber
    actor U as You
    participant M as Main session (dev-debug skill)
    participant H as Hooks
    participant F as Task folder
    participant D as dev-debugger
    participant C as dev-plan-critic

    U->>M: /dev-debug:dev-debug "bug" (or a stack trace, failing test, work item)
    M->>F: create folder, write .claude/flow/<branch>/planning, plan.md stub with source dev-debug and status diagnosing
    M->>U: Paste the report / stack trace / log, or a work item ID; repro steps, environment, last good version?
    U-->>M: bug report
    M->>F: specs/bug-report.md (verbatim); plan.md (status diagnosing, written at start) gets specs and Context
    Note over H: planning pointer exists -> main session may write only the task folder; commit/push/post blocked
    M->>D: task folder, project root, base, specs (nothing else; a theory in the report is a hypothesis)
    H-->>D: SubagentStart: flow state + snapshot of the working tree
    D->>D: reproduce (project's run/test commands), localize, read history read-only, test hypotheses, find sibling sites
    D->>F: diagnosis.md (confidence, reproduction, root cause file:line, evidence, ruled out, blast radius, fix steps, regression test), debug/ scripts
    H-->>D: SubagentStop: tree unchanged? otherwise block once, log violations.md
    D-->>M: path, confidence, reproduced?, root cause in one sentence
    M->>U: diagnosis summary
    H-->>U: Stop: desktop notification "waiting for you (confirm-cause)"

    alt more facts or a disagreement
        U-->>M: "it also happens when ..."
        M->>F: append to specs/bug-report.md
        M->>D: revise diagnosis.md
    else second opinion (offered when confidence is below High)
        M->>D: fresh debugger, same inputs, writes diagnosis-2.md, knows nothing of the first
        M->>U: where the two agree and disagree
    else diagnosis only
        U-->>M: "diagnosis only"
        M->>F: status done, delete .claude/flow/<branch>/planning
    else already fixed (the fix is on the branch)
        U-->>M: "already fixed"
        M->>F: commit noted in plan.md, status done, delete .claude/flow/<branch>/planning
    end

    U-->>M: "fix" (confirms the cause and approves the fix plan)
    M->>F: plan.md from diagnosis.md: source dev-debug, one sequential package, regression test first, fix at the cause and every sibling site, verification
    opt only on request, or when a step changes a contract, schema or persisted data
        M->>C: dev-plan-critic (plan path, project root, specs)
    end
    M->>F: status approved, delete .claude/flow/<branch>/planning
    M->>M: invoke /dev-flow:dev-implement plan.md
    Note over M: the implementer writes the regression test first and appends its failing run to verify.log before fixing;<br>the reviewer checks cause over symptom; the QA note lists the reported scenario as the first regression test
```

`diagnosis.md` stays in the task folder as the record of why the bug happened; the plan carries only what the implementer and the reviewer need. The debugger never edits source, not even to add a print statement: the hooks refuse it, and anything it would have needed goes under the diagnosis's open questions for you to add by hand.

