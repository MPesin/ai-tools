# Hypothesis ledger

Kept in the conversation (or in the active worklog file under a `Ledger`
heading when the user wants it durable). Never in the repo otherwise.

```
Symptom: POST /orders returns 500 for quantities over 999 (prod only)
Command: dotnet test --filter OrderQuantityTests → 1 failed
Expected: 201 with the order id · Actual: 500, InvalidCastException in OrderMapper.Map
Since: 2026-08-28 (commit 3f2a9c1 introduced decimal quantities)
Reproduces: 5/5 locally with quantity=1000

| # | Hypothesis | Prediction | Check | Result | Verdict |
|---|------------|------------|-------|--------|---------|
| 1 | int overflow in Map | quantity=2147483648 fails, 1000 passes | run with both | 1000 fails too | discarded |
| 2 | JSON binder reads 1000 as decimal, Map casts (int) | the DTO holds 1000.0m before Map | log dto.Quantity.GetType() | System.Decimal | confirmed |

Root cause: the request binder maps the numeric field to decimal since 3f2a9c1,
and OrderMapper.Map casts it with (int) which throws for boxed decimals —
values under 1000 pass only because the test fixtures send integers.
Fix: Convert.ToInt32 with a range check in Map; regression test with 1000.5.
Guards: same cast pattern in InvoiceMapper.Map (in scope, fixed) and
ReportMapper.Map (out of scope, noted).
```

Rules:
- A row is written before its check runs; the prediction must name an
  observable that differs between "true" and "false".
- Cheapest check first: a `grep`, a log line, a single test run, before a
  build or a full suite. Say what will run; heavy runs wait for a yes.
- Discarded rows stay. When three fixes have failed, the discarded rows are
  the first thing to re-read: the shared assumption behind them is the
  next hypothesis.
- "Confirmed" needs the evidence line, not the absence of a
  contradiction.

## Flaky failures

Record the rate (`fails 3/20`) and treat the variability itself as the
first localization target: what differs between passing and failing runs
(timing, ordering, shared state, environment, time of day)? A flake that
becomes deterministic under a fixed seed, serial execution, or a frozen
clock has just told you its mechanism.
