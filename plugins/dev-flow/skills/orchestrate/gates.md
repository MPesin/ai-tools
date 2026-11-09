# Gates

Single source of truth for `/dev-flow:orchestrate`: the points where `dev-plan`, `dev-debug` and `dev-implement` stop for the user (the man-in-the-middle steps), what the `dev-orchestrator` agent may rule at each, how it decides (by rule, per item, or by score), when it asks the user instead, the budget, and the files it writes. The skill and the agent both read this file. The other skills are unchanged: where their text says the user decides, the orchestrator's ruling stands in for the user's reply, at the gates below and nowhere else.

## Standing rules

These hold at every gate.

- **The specs decide.** A ruling rests on a citation: a line of a file under `specs/` (the PRD/HLD excerpts, the work item, the bug report, `specs/decisions.md` with the user's own rulings), the project's guidance, or a fact verified in the code (`file:line`, command output). A ruling with no citation is a guess; the orchestrator does not guess, it asks. The user's rulings in `specs/decisions.md` outrank the other specs: they are the user, answering.
- **Specs are excerpts.** A requirement the provided text does not mention is "Not covered by provided specs", never Missing and never invented. The orchestrator never adds a requirement the specs do not state, never drops or weakens one they do, and never edits anything under `specs/`.
- **Know the code and the change.** Before it judges anything, the orchestrator reads the code the gate is about, as it is today and as it is being changed: the files the plan or the diagnosis names, in full, with their callers, tests, contracts, schemas and persisted data; then `git diff <base>...HEAD` and the uncommitted changes, and which plan steps they realise. Its entry records this as `Code context`, so every ruling can be read against what the code does now and what the change does to it. At a planning gate nothing is built yet: the code context then says what the code does today where the plan would change it. The scope follows the gate: the whole change at P3, I4 and I5; at I1, I2 and I3 the files the item names and what calls them.
- **The diff before the claims.** At I4 the orchestrator reads the diff and the changed files before `notes.md`, `verify.log` and the reviews, so that the implementer's account does not anchor it; those files are then read as claims to check, not as evidence. A `- [x]` in the plan, an agent's summary, a "fixed" line in `notes.md`: each counts only once the code, the tests or `verify.log` confirm it.
- **Every choice is explained by its scores.** A procedural action records the trigger that fired; a per-item ruling records its spec fit and evidence scores with the citation; a decision records the full table (under How a ruling is made). A reader of `orchestration.md` sees why each way won or lost without re-reading the code.
- **Unsure means ask.** When no option is clearly best, or the evidence is thin, the orchestrator asks the user, with the options scored, what would settle it and its recommendation, instead of taking the likeliest one.
- **Internal and reversible, or the user's.** A choice the specs leave open is the orchestrator's only when it is internal and reversible: it changes no public contract (API, CLI, file format, schema, persisted data), no user-visible behaviour and no acceptance criterion. Anything else the specs leave open goes to the user, with the options and a recommendation.
- **Nothing outward, nothing destructive.** The orchestrator never rules to push, open a PR, merge, post, publish, update a work item, revert, discard or delete. The main session pushes and opens the PR once, at the end of the run, only when `specs/decisions.md` records that the user asked for it at kickoff.
- **Bounded.** Every loop has a budget (below); a spent budget asks.

## The gates

| ID | Where the skill would stop | Rulings | Asks the user when |
|---|---|---|---|
| P1 | `dev-plan`: the planner left `## Open questions` | per question: `answer <Qn>: <option>`, with its citation | the specs, the user's decisions, the guidance and the code do not settle a question and the choice is not internal and reversible |
| P2 | `dev-plan`: `plan-critique.md` is written | per item: `revise <Cn>` or `reject <Cn>`; `proceed` once nothing is left to revise | a Blocking item is still right after the second critic round; an item exposes a conflict between specs |
| P3 | `dev-plan`: "approved?" (also the fix plan from `dev-debug`, and an "already done on the branch" close-out) | `approve` or `revise <what>` (scored) | `approve` is out and the planner revisions are spent; the top option is not sure |
| D1 | `dev-debug`: the diagnosis gate | `second opinion` (by rule, once); then `fix`, `fix, and <changes>` or `already fixed` (scored) | Confidence Low, or two diagnoses that disagree on the cause, after the second opinion; the diagnosis needs facts only the user has (environment, inputs, since when) |
| I1 | `dev-implement`: an agent's report or `violations.md` needs the user (a blocked step, a file it does not own, an impossible plan, three failed builds on one error, a change outside an allowance) | `replan <what>` (by rule, once); `continue` (scored) | a regression test that passed before the fix (always); a changed file nobody explains, or one outside the plan's scope; `continue` is not sure |
| I2 | `dev-implement`: `needs-decision.md` gained a disputed finding | per finding: `uphold <Fn>` (it joins the fix list) or `dismiss <Fn>` (the dispute stands) | the finding turns on what the product should do and the specs do not say |
| I3 | `dev-implement`: `status: blocked` (the fix-round cap) | `continue <n> rounds` (by rule, once) | the convergence test fails, a Critical finding is open, or the allowance is used |
| I4 | `dev-implement`: the human-review gate | `done` or `fix <findings>` (scored) | a criterion needs a decision the specs leave open; the send-back budget is spent with a row still Not met; the top option is not sure |
| I5 | `dev-implement`: `qa-impact.md` section 5 lists differences from the requirements | per row: `accept <row>` or `fix <row>`; `accept` once every row is accepted | a row the specs settle remains once the send-back budget is spent |

Not gates, decided by the skill by rule with no agent call: draft mode (interactive planning needs a person); the critic always runs; at Intake a branch is created when HEAD is on the default branch (the project's branch convention, otherwise the task folder's name without the date), the user's own uncommitted work is left out of the flow's commits, and `commits: on`. A detached HEAD, a pointer of another task or another session, and a bug with `dev-debug` not installed are found at kickoff, while the user is present, and said there.

## How a ruling is made

Three kinds of choices, so that the scoring stays meaningful and cheap.

1. **By rule: procedural actions.** `second opinion` (D1), `replan` (I1) and `continue <n> rounds` (I3) gather facts or buy rounds; they decide nothing about the product. Each is taken when its trigger holds and its budget allows, and is otherwise not open; it is never scored. The entry records the trigger that fired. Triggers: D1, Confidence below High, or Reproduced `no`; I1, a step impossible as written, confirmed in the code, with another route to the same criterion and no change of scope or criterion; I3, the last `review-N.md` has fewer Critical/Major/Mid findings than the one before and none is Critical.
2. **Per item: P1, P2, I2, I5.** The unit is the question, the critique item, the finding or the QA row, each with two ways. The gate's checks decide it; the entry's table has one row per item with its ruling, its spec fit (S) and evidence (E) scores from the Scoring anchors, and the citation. Rule: S 3 or 2 with E at least 2 rules as the check says; S 1 (the specs are silent) rules only when the choice is internal and reversible (standing rules), else the item is asked; S 0 (the way would contradict a spec) rules the other way; E 1 or less asks. The gate's summary ruling (`proceed`, `accept`) follows from the items.
3. **By score: P3, D1 (after any second opinion), I1 `continue`, I4.** Every decision option is scored on the five criteria below, one reason with a citation per score, and the top total is the ruling when it is sure.

## Scoring

Anchors, 0 to 3 per criterion.

| Criterion | 3 | 2 | 1 | 0 |
|---|---|---|---|---|
| **S, spec fit** | a cited spec line or user decision requires it | consistent with the specs; no line requires it | the specs are silent on it | contradicts a spec line or a user decision |
| **C, criteria**: the acceptance criteria the option affects | every one met, with evidence in the code, the tests and `verify.log`; or the option affects none | every one covered by a plan step with a verification, not built yet | one or more unverified | one or more would be unmet or broken |
| **E, evidence**: how well the option's premise was checked | verified in the code and in a run's output (`file:line`, command output) | verified in the code by reading; nothing run | plausible from reading, not verified | unknown |
| **R, reversibility**: what acting on the ruling does now to the working tree and the remote (the content of the plan or the change is judged by S and C and by the standing rules, not here) | nothing outward or lasting: a status change, a file in the task folder, a commit on the branch | a tree change a later round can undo (a fix round, a re-run) | hard to undo without the user (a migration run, a dependency upgrade in a lock file) | outward or destructive: push, PR, merge, post, publish, deletion, a revert of someone's work |
| **B, scope and cost** | within the plan's scope, no extra stage round | within scope; extra rounds inside the budget, the last one included | within scope, but a finished stage is redone (QA impact again, a plan revised after implementation) | beyond the budget, or adds scope the specs do not ask for |

Hard rules, applied before the totals:

- An option with S = 0 or R = 0 is out: the orchestrator never rules it (an R = 0 option is the user's; it may recommend one when it asks).
- An option the specs are silent on (S = 1) may be ruled only when it is internal and reversible (standing rules).
- P3 `approve` is out when a row of the conformance matrix is neither Met-by-plan nor Not covered by provided specs, when a step contradicts a spec, or when an Open question or a Blocking critique item is left. I4 `done` is out unless every row is Met or Not covered (C = 3) and the scope is clean.

The ruling is the highest total of 15, when the orchestrator is sure: a total of 11 or more, a margin of at least 2 over the runner-up (with one option left after the hard rules there is no runner-up, and the margin rule does not apply), and E of at least 2. Confidence is recorded with it: High when the total is 13 or more and the margin 3 or more (or no runner-up), otherwise Medium. Anything less is not a ruling: the orchestrator asks.

## Checks per gate

### P1 Open questions (per item)

For each question: find the answer in the specs or the user's decisions (cite the line, S 3); else in the project's guidance (S 2); else in the code, a fact that leaves one option that works (S 2, E 2 or 3). When none of these settles it (S 1), the planner's recommended option is taken only if the choice is internal and reversible, and the ruling says so; otherwise that question is asked, with the options and a recommendation. Several questions: rule the ones that can be ruled, ask the rest together.

### P2 Critique (per item)

Check each item of `plan-critique.md` against the code and the specs. `revise` when it is right and keeps or improves conformance; `reject`, with evidence, when it is wrong, or when following it would move the plan away from a spec (the specs outrank the critic, S 0 for the revision). A Blocking item that is right is always revised. A Should-fix item is revised when it touches a requirement or a verification; a cosmetic one may be rejected as such. Notes are recorded, not acted on. `proceed` once nothing is left to revise.

### P3 Approval (plan, fix plan, close-out; scored)

Build or refresh `conformance.md`: one row per acceptance criterion in `plan.md` and per requirement in the provided specs. A row is Met-by-plan when a step names the files to change, the shape of the change and a verification that would show the criterion holds. Then score `approve` and `revise <what>` (the hard rules take `approve` out when a row is uncovered, a step contradicts or exceeds the specs without a criterion that needs it, or an Open question or Blocking item is left). `revise` names the rows and what the plan lacks.

For a fix plan (`source: dev-debug`) the criteria are the ones `dev-debug`'s `diagnosis-format.md` maps (the reproduction no longer reproduces; the regression test fails without the fix and passes with it; the affected scope passes; the work item's criteria), and the regression test must assert the scenario the bug report describes. For an "already done on the branch" close-out, the commit named must do what the specs ask (check its diff against the criteria); otherwise `revise`: plan the rest.

### D1 Diagnosis (by rule, then scored)

Read `diagnosis.md` against the bug report. By rule first: Confidence below High, or Reproduced `no`, takes `second opinion` once (a fresh debugger writes `diagnosis-2.md`); the gate then runs again on both. Two diagnoses with different causes, or a Low confidence after the second, ask. Then score `fix` (with `, and <changes>` for a blast-radius site or a work-item criterion the fix steps miss) against `already fixed` (open only when the debugger reports the cause already changed on the branch and names the commit and a passing reproduction). `fix` needs: Reproduced `yes` (or `partially` with the failing assertion shown under `## Reproduction`); every observation under `## Evidence` explained by the cause and no alternative left untested under `## Hypotheses ruled out`; `## Regression test` asserting the reported scenario; `## Fix` covering the root cause and every site under `## Blast radius`. Never `diagnosis only` (the run's goal is the fix), and never facts of its own: facts the report lacks are the user's, so ask with the exact questions. While `plan.md` is still the diagnosis stub, a debugger that reports a violation or that it cannot proceed goes through I1 with `continue` (the debugger is re-run, pointed at its `diagnosis.md`) or ask; there is no `replan` at `diagnosing`.

### I1 Agent report or violation (by rule, then scored)

Read the agent's report (passed verbatim), `violations.md`, `notes.md`, `verify.log` and the files named. Ask always for a regression test that passed before the fix (the diagnosis or the test is wrong: `dev-debug`'s own rule), for a changed file nobody explains, and for a change outside the plan's scope. By rule, `replan <what>` once when a step is impossible as written, confirmed in the code, and another route reaches the same criterion without changing scope or a criterion: the planner revises `plan.md` in harden mode, and the critic reruns when the change touches a contract. Otherwise score `continue`: every changed file outside an allowance is explained by the report (a lock file a build rewrote, a generated file the plan names) and within the plan's scope, and any blocked step is one the main session can finish as the plan says. Never rule to revert.

### I2 Disputed finding (per item)

For each finding in `needs-decision.md`: open the code at its `file:line`, read the fixer's `DISPUTED` line in `notes.md`, and decide from the code which is right. `uphold` when the defect is real (quote the lines); `dismiss` when the dispute's evidence holds. When the disagreement is about what the product should do and the specs do not say, ask that finding with both readings.

### I3 Blocked (by rule)

Compare the last two `review-N.md`: the count of Critical/Major/Mid findings must have fallen and no Critical may be open. Then `continue <n> rounds`, at most the mode's cap (3 in full, 1 in lite), once in the run. Otherwise ask, with the open findings and the criteria they touch.

### I4 Human review stand-in (scored)

The orchestrator is the reviewer the flow waits for. Get the changes yourself (`git diff <base>...HEAD` plus uncommitted changes) and read every changed file in full before anything else; then the latest `review-N.md` for the Low findings, `notes.md` and `verify.log` for the evidence. Refresh `conformance.md`: a row is Met only with the code and test that meet it (`file:line`) and a `verify.log` line showing the verification ran and passed. Check scope: nothing changed that the plan or a finding did not call for. For a bug fix: the regression test asserts the reported scenario, and `verify.log` holds its failing run before the fix and its passing run after. Low findings that touch a criterion become findings; the rest are listed. Score `done` (out unless every row is Met or Not covered and the scope is clean) against `fix`: findings written as review comments (file:line, what is wrong, what the spec says), which the main session hands to stage 5 as pasted comments.

### I5 QA differences (per item)

Read `qa-impact.md` section 5. A row is accepted when it is Not covered by provided specs, or the user's own decision in `specs/decisions.md` (cite it), or ruled at an earlier gate with a spec citation. Any other row is a difference the specs settle: `fix <row>` with what the spec says (through stage 5 and QA impact again), or ask when the send-back budget is spent. After a close-out (an "already done" plan, an `already fixed` bug) nothing implements, so a row to fix is asked instead.

## Budget

Defaults; the user changes them at kickoff in plain words ("allow five fix rounds"), recorded in `specs/decisions.md`.

| Loop | Default | When spent |
|---|---|---|
| Planner revisions (P2 `revise`, P3 `revise`; P1 answers are not revisions) | 2 | P3 asks |
| Critic rounds (P2) | 2 | P2 asks what is still Blocking |
| Second opinion (D1) | 1 | D1 asks |
| Re-plan on an agent report (I1) | 1 | I1 asks |
| Extra fix rounds at `blocked` (I3) | once, the mode's cap | I3 asks |
| Send-backs from the review stand-in and QA (I4 + I5) | 2 in all | I4 and I5 ask |

Questions to the user are not budgeted: each one stops the run for the user.

## Asking the user (escalation)

An escalation is a question. The orchestrator rules `ask` instead of a ruling when: no option passes the hard rules; the top option is not sure (a total under 11, a margin under 2, or E under 2); a per-item ruling has S 1 without an internal, reversible choice, or E 1 or less; the gate's "Asks the user when" column applies; or a budget is spent. The question is written so the user can answer it in one line: the question itself; each option with its total (or its S and E) and one line on why it scored so; what would settle it (the spec line, fact or test result the orchestrator lacks); and the recommendation, which may be an R = 0 option the orchestrator could not rule itself.

Every stop of the run goes through the skill's Escalation procedure, whatever its source: a ruling of `ask`, a spent budget, or a stop the underlying skill prescribes (a failed commit, a push rejected, a regression test passing before the fix); when no ruling exists, the skill writes the question in the same shape. The skill appends the item to `needs-decision.md` (the Stop hook notifies the user), leaves `status` where the underlying skill waits at that gate, shows the question as written, and ends the turn. The user's answer is saved verbatim and dated under `specs/decisions.md`, listed in `specs:`; `/dev-flow:orchestrate <task folder>` then continues from the gate with that answer as the ruling. The user can also take over by hand with the stage's own skill. Stops at kickoff, before a task folder exists, are plain messages to the user, who is present then.

## Files

### orchestration.md (appended per gate, never rewritten)

```
## <gate id> <gate name> - <YYYY-MM-DDTHH:MM:SSZ>
Inputs read: <paths>
Question: <what the skill would have asked, in one line>
Code context:
- Today: <what the affected code does now, file:line>
- Change under way: <commits since base and uncommitted changes, and the plan steps they realise; or "none yet, the plan proposes ...">
- Touches: <callers, tests, contracts, schemas, persisted data the change reaches; or "none found">
Checked against: <spec file:line, conformance rows, decisions.md entries>
Findings:
- <finding, with file:line or command output>
By rule: <procedural action taken and the trigger that fired, or "none">
Options:                                  (a scored gate)
| # | Option | S | C | E | R | B | Total | Out |
|---|---|---|---|---|---|---|---|---|
| 1 | <option as the gate names it> | 3 | 2 | 2 | 3 | 3 | 13 | |
| 2 | <option> | 2 | 2 | 2 | 3 | 2 | 11 | |
Scoring notes:
- 1: S3 <spec file:line requires it>; C2 <which rows, why not yet 3>; E2 <what was read>; R3 <a status change>; B3
- 2: ...
Items:                                    (a per-item gate)
| Item | Ruling | S | E | Citation and reason |
|---|---|---|---|---|
| C1 | revise | 3 | 2 | prd.md:14 requires ...; the callers at src/x.cs:40 ... |
Ruling: option 1, <keyword with its detail> (13/15, margin 2, confidence Medium)   | or: proceed / accept / the per-item rulings
Why: <the reasons, a few lines, read off the scores>
Escalate: no
```

When it asks instead, the entry ends with:

```
Ruling: ask
Question for the user: <one line the user can answer>
- Option 1 (<total>/15, or S<n> E<n>): <why it scored so>
- Option 2 (...): <why it scored so>
What would settle it: <the spec line, fact or test result the orchestrator lacks>
Recommendation: <option, and why>
Escalate: yes
```

### conformance.md (the current state)

```
# Conformance: <task>
Checked at: <gate id>, <date>; specs read: <files>; baseline: <specs | task description only>

| # | Requirement or acceptance criterion (as written, source file:line) | Plan step(s) | Code and test (file:line) | Evidence (verify.log line, review) | Status |
```

Status is one of `Met-by-plan` (P3: a step with a verification covers it), `Met` (I4, I5: code, test and evidence), `Not met`, `Not covered by provided specs`, `Decided by the user` (a `specs/decisions.md` entry settles it, cited). The matrix is built at the first gate, rewritten in full at P3, I4 and I5, and at the other gates only where a row the item touches changes.

### needs-decision.md (written by the skill and by dev-implement, read by the user)

Two kinds of lines. A disputed finding, appended by `dev-implement` stage 3 and ruled at I2 (the skill removes the line once ruled); and an escalation, appended by the skill:

```
- <YYYY-MM-DDTHH:MM:SSZ> <gate id>: <the question in one line>; orchestrator recommends: <option>; see orchestration.md
```

The file is deleted when nothing is left in it.

### specs/decisions.md (written by the skill, read by every agent)

```
Source: the user, in chat, during /dev-flow:orchestrate

## Kickoff <date>
<the user's parameters, verbatim: push and open the PR at the end or not, budget changes, constraints>

## Decision <date> (<gate id>)
<the user's reply to the escalation, verbatim>
```
