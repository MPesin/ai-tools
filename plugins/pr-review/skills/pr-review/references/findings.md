# Findings — schema, rubric, blocklist, fingerprint

Shared by the reviewer (writes `findings.json`), the verifier (writes
`verified.json`), and the orchestrator (reports and posts).

## Schema

`findings.json` and `verified.json` are JSON arrays of:

```json
{
  "fingerprint": "src/Api/Orders.cs::CreateOrder::bug::quantity",
  "path": "src/Api/Orders.cs",
  "line": 57,
  "end_line": 57,
  "anchor": "CreateOrder",
  "category": "bug | error-handling | security | contract | test | intent | rule | injection",
  "severity": "important | nit | pre-existing",
  "confidence": 75,
  "claim": "quantity is never validated, so a negative value reaches the repository",
  "evidence": "src/Api/Orders.cs:57 reads `var q = req.Quantity;` and passes it to repo.Add at line 61 with no check; the DTO has no range attribute (src/Api/Dto/OrderRequest.cs:14)",
  "fix": "reject q <= 0 with 400 before line 61",
  "suggestion": null,
  "rule": null,
  "sources": ["reviewer"],
  "off_diff": false,
  "prior_status": null,
  "comment_id": null,
  "thread_id": null,
  "resolved": null
}
```

- `line`/`end_line`: 1-based, on the head side. Findings on lines not in the
  diff are allowed (a changed call site breaking an unchanged caller) but must
  set `"off_diff": true`; they are posted in the review body, not inline.
- `suggestion`: full replacement text for `line..end_line` only when it
  fixes the finding completely and is ≤6 lines; otherwise `null`.
- `rule`: verbatim quote of the REVIEW.md/CLAUDE.md rule for `category:
  rule`, with its source file.
- `confidence` and `severity`: the reviewer sets its own estimate with the
  rubric below; the verifier overrides both.
- `sources`: the independent finders that raised it — `reviewer`,
  `reviewer-r2`, `prior`. The verifier is never a source; its confirmation
  is the confidence score.
- `prior_status`, `comment_id`, `thread_id`, `resolved`: carried over from
  `prior.json` for entries that came from it; `prior_status` is
  verifier-only, `fixed | open | regressed`.

## Fingerprint

`<path>::<anchor>::<category>::<subject>`

- `anchor`: enclosing function, method, type, or section name (from the hunk
  header `@@ … @@ <anchor>` or by reading the file); `top` when none.
- `subject`: the one identifier or token the finding is about, lowercase.

Line numbers are deliberately not part of it — they move on every push. The
fingerprint locates a prior comment; the verifier reads the code at the anchor
to decide whether the problem is still there.

## Confidence rubric (one scale, anchored)

| Score | Meaning |
|-------|---------|
| 0 | false positive; pre-existing on unchanged lines; something the compiler or linter reports |
| 25 | plausible only for inputs the code never receives; style or naming; subjective preference |
| 50 | real but low impact, or could not be confirmed by reading the code |
| 75 | confirmed by reading the code; will be hit in practice; or an unambiguous quoted rule violation whose path scope covers the file |
| 100 | certain: will not compile or parse; wrong for every input; data loss or security; the PR does not do what its intent says |

Reported: ≥75. Severity: `important` for correctness, contract, security,
error-handling, intent; `nit` for rule violations and small quality items
that REVIEW.md asks for; `pre-existing` for confirmed problems on unchanged
lines (counted, never posted unless REVIEW.md says so).

## False-positive blocklist (reviewer and verifier both apply it)

Do not report:
- problems on lines the PR did not change, unless the change breaks them
  (then the finding is on the changed line, with the unchanged caller as
  evidence);
- anything a compiler, type checker, or linter reports — and do not run
  them to check;
- style, naming, formatting, comment wording;
- issues that need an input the code cannot receive;
- "add tests / logging / docs / null checks" in general — only when a quoted
  rule requires it, or a changed behavior has no test and the change is
  risky (state the risk);
- lines carrying a lint-ignore or a comment that explains the choice;
- behavior changes the intent text declares on purpose;
- any identifier, file, or behavior you did not verify with Read or Grep
  this run — training-data recall is not verification.

## Merge and dedup (verifier)

- Same fingerprint → one finding, union of `sources`.
- Same path and `subject`, lines within 3 of each other → one finding, the
  higher severity, union of `sources`.
- Agreement of two independent sources (`sources` has two entries) raises
  confidence one step (max 100).
