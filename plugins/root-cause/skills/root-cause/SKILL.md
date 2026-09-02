---
name: root-cause
description: Use when a bug, failing test, crash, or unexpected behavior needs diagnosing, before proposing any fix, and whenever a fix did not work. Reproduce first, localize by bisection, test one hypothesis at a time against a written prediction, state the root cause as a mechanism, then fix with a regression test. Not for runtime-log troubleshooting of Claude Code itself (that is /debug).
when_to_use: Trigger phrases - why does this fail, it works on my machine, flaky test, intermittent, the fix did not help, still broken, regression, stack trace, exception, wrong output.
argument-hint: "[symptom, failing test, or issue]"
---

# Root cause

Debugging that starts with a fix is guessing. This skill makes the guess
explicit, tests it, and refuses to patch a symptom whose mechanism is not
yet known.

| Load | When |
|------|------|
| `references/ledger.md` | every run — the hypothesis ledger format and the escalation rule |
| `references/techniques.md` | when localizing — bisection, differential runs, tracing, per-ecosystem pointers |

**Non-negotiables**
- No fix before a reproduction. A bug you cannot trigger on demand is not
  understood; an intermittent one gets a reproduction rate, not a shrug.
- One hypothesis at a time, each with a prediction written *before* the
  check runs. A check whose outcome you could not have predicted either way
  is not a test of anything.
- The root cause is a **mechanism** ("the cache key omits the tenant id, so
  tenant B reads A's entry after A's first request"), never a location
  ("something in CacheService") or a symptom restated.
- Three failed fixes → stop. Question the model of the system, not the next
  line to change. Say so to the user.
- Never delete, skip, or loosen a test to make the symptom go away.
- Anything that executes (tests, builds, the app, migrations) is named
  before it runs, and heavy or side-effecting runs wait for a yes.

## Process

1. **Capture the symptom** exactly: the command or action, the input, the
   expected result, the actual result (verbatim output or stack trace), the
   environment, and when it started (`git log` since the last known good).
   Write it at the top of the ledger.
2. **Reproduce.** Find the smallest input and the fastest command that show
   the failure every time (or record the rate over N runs for a flake).
   Prefer a failing test as the reproduction; write one if none exists —
   it becomes the regression test later.
3. **Localize.** Narrow the space before theorizing: `git bisect` when it
   is a regression, a differential run (working vs failing input, env,
   version) when it is not, tracing at the boundary between "still correct"
   and "already wrong". techniques.md lists the moves. Stop localizing when
   the wrong value has a first appearance.
4. **Hypothesize and test**, one row of the ledger at a time: hypothesis →
   prediction ("if true, changing X makes the test pass and Y still fails")
   → the cheapest check → result → keep or discard. Discarded hypotheses
   stay in the ledger; they are evidence too.
5. **State the root cause** in one or two sentences as a mechanism, with
   the evidence line that proves it. If the statement contains "probably",
   go back to step 4.
6. **Fix minimally** at the mechanism, not at the symptom. Run the
   reproduction: it must pass now and must have failed before. Run the
   surrounding tests. A fix that needs the test changed is suspect.
7. **Guard.** Ask where else the same mechanism applies (`grep` for the
   pattern); list the places, fix only the ones in scope, name the rest.
8. **Record.** If the root cause was non-obvious, propose `/decide` (when
   decision-log is installed) with the mechanism and the guard as the
   reasoning; if a worklog item is active, it goes under `surprises`. Report:
   symptom → root cause → fix → regression test → guards, in that order.

## Escalation (after three failed fixes)

Stop editing. Re-read the ledger; the discarded hypotheses usually share an
assumption. Write that assumption down and test it directly. If it holds,
the design, not the code, is the problem — say so and offer a design-critic
review instead of a fourth patch.
