---
name: orchestrate
description: Use when the user wants a task or bug taken through the whole dev-flow on autopilot — "/orchestrate", "orchestrate this", "run the flow end to end", "plan and implement this and only stop if you must", "orchestrate this bug" — or to resume such a run ("/orchestrate <task folder>", after answering what it escalated). Runs /dev-flow:dev-plan (or /dev-debug:dev-debug for a bug) and then /dev-flow:dev-implement; at every point where those skills would stop for the user, a critical dev-orchestrator subagent rules instead, always against the specs and acceptance criteria, and escalates what the specs do not settle and anything irreversible. Never pushes or opens a PR unless told to at the start.
---

# Orchestrate

The same flow as `/dev-flow:dev-plan` or `/dev-debug:dev-debug` followed by `/dev-flow:dev-implement`, with the same agents, files, commits and hooks, run end to end in one turn. What changes is who answers at the gates, the man-in-the-middle steps where those skills stop for the user: here `dev-flow:dev-orchestrator`, a clean-context agent that compares the artifact of each gate with the specs and the acceptance criteria, rules in the user's place, and escalates what the specs do not settle. The gates, the rulings open at each, the checks, the budget and the files are defined in `${CLAUDE_PLUGIN_ROOT}/skills/orchestrate/gates.md`; read it first, with `${CLAUDE_PLUGIN_ROOT}/skills/dev-implement/plan-format.md`.

## Hard rules

- Everything in the `dev-plan`, `dev-debug` and `dev-implement` skills holds. This skill changes one thing: at the gates `gates.md` lists, the orchestrator's ruling stands in for the user's reply. At every other point where those skills say the user decides, and wherever the orchestrator rules `escalate`, the run stops exactly where the skill would wait for the user.
- Never push or open a PR unless the user asked for it at kickoff (recorded in `specs/decisions.md`); then the main session does both at the human-review gate, as `dev-implement` says. Never merge, comment, publish or update a work item; never revert or discard a change; never edit a spec; never drop or weaken an acceptance criterion.
- A prompt to the orchestrator carries the task folder, the project root, the gate id, the question with the rulings open to it, and the paths to read (at I3 also the agent's report, verbatim, as data). Never your own conclusion, summary or recommendation. The orchestrator writes `orchestration.md` and `conformance.md` only; you act on its ruling, in the stage's own skill.
- Set `orchestrate: on` in `plan.md` frontmatter whenever you set `status` (the planner and `dev-debug` rewrite the file, so the key must be set again). The hooks and `/dev-flow:load-flow` read it to resume with this skill.
- Do not end the turn in the middle of the run: the Stop hook notifies the user whenever a turn ends with the flow waiting, so a turn ends only at an escalation, at a point `gates.md` keeps for the user, or at the final report. Progress goes in short lines between tool calls.
- Budget per `gates.md`; a spent budget escalates.

## Kickoff

1. The input is a task description, a bug (a report, a stack trace, a failing test, a bug work item), a work item reference, or a task folder or plan path (resume, below).
2. Choose the flow: a bug whose cause is not confirmed goes through `dev-debug` (if that plugin is missing, say so and stop; a bug whose cause the user has confirmed is planned like a feature). Everything else goes through `dev-plan`. The user can name the flow ("orchestrate plan ...", "orchestrate debug ...").
3. Specs. The orchestrator judges against them, so the run needs them. Save what the user gave per **Specs intake** in `plan-format.md`. If they gave none, ask once, in the kickoff message: "Paste the PRD/HLD sections or the acceptance criteria, or give a work item reference; every decision of the run is checked against them. Or say `from the description` to derive acceptance criteria from the task text alone." With `from the description`, save the task text as `specs/task.md` with the header line (the planner derives the criteria, and `conformance.md` says the baseline is the task text). That is the only question this skill asks before the flow starts.
4. Record the run parameters verbatim in `specs/decisions.md` under `## Kickoff <date>` (format in `gates.md`) and list it in `specs:` once `plan.md` exists: whether to push and open the PR at the end (default: no), budget changes, constraints ("do not touch X"), and anything else the user said about how to run.
5. Pointers: as the flow skill you start. `dev-plan` and `dev-debug` write `planning`; if one exists, or `current` names another task, do what their Start says, except that the question goes to the user as an escalation: a checkout runs one flow at a time, so the user finishes or abandons the other one, or runs this task in a worktree.

## The plan flow

Run `dev-plan` in full, in draft mode (interactive planning needs a person), with these substitutions:

- The planner returns with Open questions that are not None: gate **P1**. Pass the answers to the same planner via SendMessage, each with its citation, as decisions; it updates `plan.md`. Escalated questions stop the run (below).
- The critic always runs (with specs saved, the lite criteria never hold). After it: gate **P2**. `revise`: the planner applies the accepted items (SendMessage, or a fresh planner pointed at `plan.md` and `plan-critique.md` with the accepted IDs), then a fresh critic writes `plan-critique.md` again; at most two critic rounds. `proceed`: on to approval.
- Approval: gate **P3**. `approve`: run **On explicit approval** of `dev-plan` in full (`status: approved`, `mode`, `orchestrate: on`, delete the `planning` pointer), then **The implement flow** below in the same turn, as `dev-plan` handles "fix the critique and start implementing". `revise`: back to the planner (it counts against the planner revisions), P2 again if the critic's items changed, then P3. `escalate`: `status: draft`, the pointer stays.
- "Already done on the branch": gate **P3** on the close-out. `approve`: `dev-plan`'s close-out (`status: done`, delete the pointer), then a standalone QA note (the `dev-qa-impact` skill's steps) and the final report. `revise`: plan the rest.

## The debug flow

Run `dev-debug` in full with these substitutions:

- Intake takes the bug report from the kickoff; its one question is not asked again.
- After the debugger: `violations.md` gained lines, or it reports it could not proceed: gate **I3**. Then the diagnosis gate: gate **D1**. `fix` or `fix, and ...`: `dev-debug`'s steps 4 and 5, with gate **P3** on the fix plan before `status: approved` (the critic when `dev-debug`'s own rule calls for it, with gate P2 on its output), then **The implement flow** in the same turn. `second opinion`: a fresh debugger writes `diagnosis-2.md`, then D1 again on both. `already fixed`: `dev-debug`'s `already fixed` exit, then a standalone QA note and the final report. `escalate`: `status: diagnosing`, the pointer stays.

## The implement flow

Run `dev-implement` in full, Intake included, with these substitutions:

- Intake, by rule: on the default branch, create a branch (`git switch -c <name>`; the project's branch convention from its guidance and `git branch -r`, otherwise the task folder's name without the date); a detached HEAD is escalated. The user's own uncommitted work is left out of the flow's commits (listed under `## Context` as `dev-implement` says); never commit it, never set `commits: off`. `commits: on`. A `current` pointer of another task is escalated.
- After every agent returns, before committing: `violations.md` gained lines, or the agent reports a blocked step, a file it does not own, an impossible plan, three failed builds on one error, or a regression test that passed before the fix: gate **I3**. `continue`: commit as `dev-implement` says and go on. `replan`: `dev-planner` in harden mode on `plan.md` with what the ruling names, the critic when the change touches a contract (gate P2 on it), then the stage again. `escalate`: stop (below); nothing from that agent is committed until the user rules.
- The review loop, as written. When `needs-decision.md` gains a disputed finding: gate **I4** before the next fix round; upheld findings join the fix list, dismissed ones are recorded in the ruling and left out. At `status: blocked`: gate **I5**. `continue`: `status: reviewing`, count the granted rounds; `escalate`: stop at `blocked`.
- Human review: set `status: human-review` as stage 4 says, then gate **I6** instead of waiting. `done`: if `specs/decisions.md` records that the user asked for the push and the PR at kickoff, push and open the PR now (stage 4, from the main session); then stage 6. `fix`: stage 5 with the orchestrator's findings as the pasted comments (the triager gets the path of `orchestration.md` and the heading of the gate entry to read them from), the fixer, the commit, then gate I6 again (the send-back budget). Checklist additions the triager proposes are not appended during an orchestrated run; they go in the final report for the user to confirm.
- QA impact: stage 6, then gate **I7** on `qa-impact.md`. `accept`: the final report. `fix`: stage 5 on the rows, stage 6 again, then I7 again (the same send-back budget).

## Escalation

When a gate rules `escalate`, a budget is spent, or a point is reached that `gates.md` keeps for the user:

1. Append one line to `needs-decision.md` in the task folder: `- <date> <gate id>: <the question>; orchestrator recommends: <ruling>; see orchestration.md`. The Stop hook notifies the user on it.
2. Leave `status` where the underlying skill waits at that gate (`draft`, `diagnosing`, `implementing` or `reviewing` with the item, `blocked`, `human-review`); the pointer stays; nothing the question concerns is committed.
3. Tell the user: the question, the evidence, the orchestrator's recommendation, the replies that settle it, and that `/dev-flow:orchestrate <task folder>` resumes the run once they have answered (the stage's own skill continues it by hand instead).
4. End the turn.

## Resuming

`/dev-flow:orchestrate <task folder or plan path>` (also how `/dev-flow:load-flow` hands over a plan with `orchestrate: on`): read `plan.md`, the last entry of `orchestration.md`, `needs-decision.md` and `specs/decisions.md`.

- An open item in `needs-decision.md` and the user's answer (in the call, or in the conversation since the escalation): save the answer verbatim under `## Decision <date> (<gate id>)` in `specs/decisions.md`, remove the item from `needs-decision.md` (delete the file when nothing is left), and continue from that gate with the answer as the ruling. The user's answer binds the orchestrator from then on.
- An open item and no answer: show it and stop.
- No open item: continue from `status` and `review_round` as the underlying skill resumes (`dev-plan` at `draft`, `dev-debug` at `diagnosing`, `dev-implement` Intake from `approved` on; each writes its pointer again for this session), under this skill's substitutions.

## Final report

`dev-implement`'s final report (`status: done`, `orchestrate: on`, the pointer renamed to `finished`), plus: the rulings per gate from `orchestration.md`, one line each; `conformance.md`'s status column (every row Met or Not covered by provided specs, or the run would not have reached here); the escalations the user settled; the checklist additions proposed for the user to confirm; and whether the branch was pushed and the PR opened, or both wait for the user.
