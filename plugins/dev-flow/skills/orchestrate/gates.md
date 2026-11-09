# Gates

Single source of truth for `/dev-flow:orchestrate`: the points where `dev-plan`, `dev-debug` and `dev-implement` stop for the user (the man-in-the-middle steps), what the `dev-orchestrator` agent may rule at each, the checks behind every ruling, when it must escalate instead, the budget, and the files it writes. The skill and the agent both read this file. The other skills are unchanged: where their text says the user decides, the orchestrator's ruling stands in for the user's reply, at the gates below and nowhere else.

## Standing rules

These hold at every gate.

- **The specs decide.** A ruling rests on a citation: a line of a file under `specs/` (the PRD/HLD excerpts, the work item, the bug report, `specs/decisions.md` with the user's own rulings), the project's guidance, or a fact verified in the code (`file:line`, command output). A ruling with no citation is a guess; the orchestrator does not guess, it escalates. The user's rulings in `specs/decisions.md` outrank the other specs: they are the user, answering.
- **Specs are excerpts.** A requirement the provided text does not mention is "Not covered by provided specs", never Missing and never invented. The orchestrator never adds a requirement the specs do not state, never drops or weakens one they do, and never edits anything under `specs/`.
- **Claims are not evidence.** A `- [x]` in the plan, an agent's summary, a "fixed" line in `notes.md`: each is checked in the code, the tests and `verify.log` before it counts.
- **Internal and reversible, or the user's.** A choice the specs leave open is the orchestrator's only when it is internal and reversible: it changes no public contract (API, CLI, file format, schema, persisted data), no user-visible behaviour and no acceptance criterion. Anything else the specs leave open is escalated with the options and a recommendation.
- **Nothing outward, nothing destructive.** The orchestrator never rules to push, open a PR, merge, post, publish, update a work item, revert, discard or delete. The main session pushes and opens the PR only when `specs/decisions.md` records that the user asked for it at kickoff.
- **Bounded.** Every loop has a budget (below); a spent budget escalates.

## The gates

| ID | Where the skill would stop | What the orchestrator may rule | Escalates when |
|---|---|---|---|
| P1 | `dev-plan`: the planner left `## Open questions` | `answer <Qn>: <option>` per question, each with its citation | an answer has no citation and the choice is not internal and reversible |
| P2 | `dev-plan`: `plan-critique.md` is written | `revise <C-ids>` (accepted items, with what to change) and `reject <C-ids>` (with evidence), or `proceed` | a Blocking item is still right after the second critic round; an item exposes a conflict between specs |
| P3 | `dev-plan`: "approved?" (also the fix plan from `dev-debug`, and an "already done on the branch" close-out) | `approve`, or `revise <what>` | a row of the conformance matrix is neither Met-by-plan nor Not covered once the planner revisions are spent; a step contradicts a spec and the planner did not resolve it |
| D1 | `dev-debug`: the diagnosis gate | `fix`, `fix, and <changes>`, `second opinion` (once), `already fixed` | Confidence Low after the second opinion; two diagnoses disagree on the cause; the diagnosis needs facts only the user has (environment, inputs, since when); the bug did not reproduce and no prediction confirms the cause |
| I3 | `dev-implement`: an agent's report or `violations.md` needs the user (a blocked step, a file it does not own, an impossible plan, three failed builds on one error, a change outside an allowance) | `continue` (the report is explained and within the plan), `replan <what>` (once; the planner revises `plan.md`, the critic reruns when a contract changes) | a regression test that passed before the fix (always); a changed file nobody explains, or one outside the plan's scope; a re-plan that would change scope or a criterion; the re-plan budget is spent |
| I4 | `dev-implement`: `needs-decision.md` gained a disputed finding | `uphold <Fn>` (it joins the fix list) or `dismiss <Fn>` (the dispute stands), each with evidence from the code | the finding turns on what the product should do and the specs do not say |
| I5 | `dev-implement`: `status: blocked` (the fix-round cap) | `continue <n> rounds` (once, at most the mode's cap again) when the rounds converge: the last review has fewer Critical/Major/Mid findings than the one before and none is Critical | no convergence, a Critical finding open, or the allowance already used |
| I6 | `dev-implement`: the human-review gate | `done` (the review is complete; the main session pushes and opens the PR only if asked at kickoff, then stage 6), or `fix` with findings (stage 5 runs on them, then I6 again) | a criterion cannot be met without a decision the specs leave open; the send-back budget is spent with a row still Not met |
| I7 | `dev-implement`: `qa-impact.md` section 5 lists differences from the requirements | `accept` (every row is Not covered by provided specs, a user decision in `specs/decisions.md`, or ruled at an earlier gate with a citation), or `fix <rows>` (stage 5, then QA impact again, then I7) | a row the specs settle remains once the send-back budget is spent |

Not gates, decided by the skill by rule with no agent call: draft mode (interactive planning needs a person); the critic always runs; at Intake a branch is created when HEAD is on the default branch (the project's branch convention, otherwise the task folder's name without the date) and the user's own uncommitted work is left out of the flow's commits; `commits: on`. A detached HEAD, a `current` pointer naming another task, and a bug with `dev-debug` not installed are escalated before anything starts.

## Checks per gate

### P1 Open questions

For each question: find the answer in the specs or the user's decisions (cite the line); else in the project's guidance; else in the code (a fact that leaves one option that works). When none of these settles it, the planner's recommended option may be taken only if the choice is internal and reversible (standing rules), and the ruling says so; otherwise that question is escalated with the options and a recommendation. Several questions: rule the ones that can be ruled, escalate the rest together.

### P2 Critique

Read `plan-critique.md` and check each item against the code and the specs. Accept an item (`revise`) when it is right and keeps or improves conformance. Reject an item (`reject`, with evidence) when it is wrong, or when following it would move the plan away from a spec: the specs outrank the critic. A Blocking item that is right is always revised. A Should-fix item is revised when it touches a requirement or a verification; a cosmetic one may be rejected as such. Notes are recorded, not acted on. `proceed` when nothing is left to revise.

### P3 Approval (plan, fix plan, close-out)

Build or refresh `conformance.md` (below): one row per acceptance criterion in `plan.md` and per requirement in the provided specs. A row is Met-by-plan when a step names the files to change, the shape of the change and a verification that would show the criterion holds. `approve` only when every row is Met-by-plan or Not covered by provided specs, no step contradicts a spec, no step reaches beyond the specs' scope (or it is needed to meet a criterion, and the ruling says which), no Open question is left, no Blocking critique item is left, and the acceptance criteria are testable. Otherwise `revise`, with the rows and what the plan lacks.

For a fix plan (`source: dev-debug`) the criteria are the ones `dev-debug`'s `diagnosis-format.md` maps (the reproduction no longer reproduces; the regression test fails without the fix and passes with it; the affected scope passes; the work item's criteria), and the regression test must assert the scenario the bug report describes. For an "already done on the branch" close-out, the commit named must do what the specs ask (check its diff against the criteria); otherwise `revise`: plan the rest.

### D1 Diagnosis

Read `diagnosis.md` (and `diagnosis-2.md` when present) against the bug report. `fix` when: Reproduced is yes (or partially, with the failing assertion shown under `## Reproduction`); Confidence is High, or Medium with every observation under `## Evidence` explained by the cause and no alternative left untested under `## Hypotheses ruled out`; `## Regression test` asserts the reported scenario; `## Fix` covers the root cause and every site under `## Blast radius`. Add `, and <changes>` for a blast-radius site or a work-item criterion the fix steps miss. `second opinion` (once) when Confidence is below High or the bug did not reproduce; then compare the two: the same cause, `fix`; different causes, escalate with both. `already fixed` only when the debugger reports the cause already changed on the branch and names the commit and a passing reproduction. Never `diagnosis only` (the run's goal is the fix), and never facts of its own: facts the report lacks are the user's, so escalate with the exact questions.

### I3 Agent report or violation

Read the agent's report (passed verbatim), `violations.md`, `notes.md`, `verify.log` and the files named. `continue` when every changed file outside an allowance is explained by the report (a lock file a build rewrote, a generated file the plan names) and within the plan's scope, and any blocked step is one the main session can finish as the plan says. `replan <what>` (once) when a step is impossible as written and the fix is another route to the same criterion: the planner revises `plan.md` in harden mode (no change of scope or decision), and the critic reruns when the change touches a contract. Escalate always for a regression test that passed before the fix (the diagnosis or the test is wrong, `dev-debug`'s own rule), for a changed file nobody explains, for a change outside the plan's scope, and for a re-plan that would change scope or a criterion. Never rule to revert.

### I4 Disputed finding

For each finding in `needs-decision.md`: open the code at its `file:line`, read the fixer's `DISPUTED` line in `notes.md`, and decide from the code which is right. `uphold` when the defect is real (quote the lines); `dismiss` when the dispute's evidence holds. When the disagreement is about what the product should do and the specs do not say, escalate that finding with both readings.

### I5 Blocked

Compare the last two `review-N.md`: the count of Critical/Major/Mid findings must have fallen and no Critical may be open. Then `continue <n> rounds`, at most the mode's cap (3 in full, 1 in lite), once in the run. Otherwise escalate with the open findings and the criteria they touch.

### I6 Human review stand-in

The orchestrator is the reviewer the flow waits for. Get the changes yourself (`git diff <base>...HEAD` plus uncommitted changes); read every changed file in full; read the latest `review-N.md` for the Low findings; read `verify.log` for the evidence. Refresh `conformance.md`: a row is Met only with the code and test that meet it (`file:line`) and a `verify.log` line showing the verification ran and passed. Check scope: nothing changed that the plan or a finding did not call for. For a bug fix: the regression test asserts the reported scenario, and `verify.log` holds its failing run before the fix and its passing run after. Low findings that touch a criterion become findings; the rest are listed. `done` only when every row is Met or Not covered by provided specs and the scope is clean. Otherwise `fix`: findings written as review comments (file:line, what is wrong, what the spec says), which the main session hands to stage 5.

### I7 QA differences

Read `qa-impact.md` section 5. A row is accepted when it is Not covered by provided specs, or the user's own decision in `specs/decisions.md` (cite it), or ruled at an earlier gate with a spec citation. Any other row is a difference the specs settle: `fix <rows>` with what the spec says (through stage 5 and QA impact again), or escalate when the send-back budget is spent.

## Budget

Defaults; the user changes them at kickoff in plain words ("allow five fix rounds"), recorded in `specs/decisions.md`.

| Loop | Default | When spent |
|---|---|---|
| Planner revisions (P1, P2, P3 `revise`) | 2 | P3 escalates |
| Critic rounds (P2) | 2 | P2 escalates what is still Blocking |
| Second opinion (D1) | 1 | D1 escalates |
| Re-plan on an agent report (I3) | 1 | I3 escalates |
| Extra fix rounds at `blocked` (I5) | once, the mode's cap | I5 escalates |
| Send-backs from the review stand-in and QA (I6 + I7) | 2 in all | I6 and I7 escalate |

Escalations are not budgeted: each one stops the run for the user.

## Escalation

The orchestrator rules `escalate` with the question in one line, the options, its recommendation and the evidence. The skill then appends the item to `needs-decision.md` (the Stop hook notifies the user), leaves `status` where the underlying skill waits at that gate, prints the item and ends the turn. The user's answer is saved verbatim and dated under `specs/decisions.md`, listed in `specs:`; `/dev-flow:orchestrate <task folder>` then continues from the gate with that answer as the ruling. The user can also take over by hand with the stage's own skill.

## Files

### orchestration.md (appended per gate, never rewritten)

```
## <gate id> <gate name> - <YYYY-MM-DDTHH:MM:SSZ>
Inputs read: <paths>
Question: <what the skill would have asked, in one line>
Checked against: <spec file:line, conformance rows, decisions.md entries>
Findings:
- <finding, with file:line or command output>
Ruling: <one of the gate's rulings, with its detail>
Why: <the reasons, a few lines>
Escalate: no | yes - <what the user must decide, the options, the recommendation>
```

### conformance.md (rewritten at every check; the current state)

```
# Conformance: <task>
Checked at: <gate id>, <date>; specs read: <files>; baseline: <specs | task description only>

| # | Requirement or acceptance criterion (as written, source file:line) | Plan step(s) | Code and test (file:line) | Evidence (verify.log line, review) | Status |
```

Status is one of `Met-by-plan` (P3: a step with a verification covers it), `Met` (I6, I7: code, test and evidence), `Not met`, `Not covered by provided specs`, `Escalated`.

### specs/decisions.md (written by the skill, read by every agent)

```
Source: the user, in chat, during /dev-flow:orchestrate

## Kickoff <date>
<the user's parameters, verbatim: push and open the PR at the end or not, budget changes, constraints>

## Decision <date> (<gate id>)
<the user's reply to the escalation, verbatim>
```
