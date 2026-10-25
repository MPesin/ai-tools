# QA impact: <task title>

<!--
Fixed template. Keep every heading, table and column exactly as here, in this order,
so QA can read each note the same way. Fill the <...> fields; write "None" in an
empty section rather than deleting it. Written for QA engineers who do not read code:
name screens, features, flows, data, settings and integrations. Never mention files,
classes, functions, methods, commits, diffs, variables, tests by name, or code terms.
-->

| | |
|---|---|
| Task / work item | <id and title, or "None"> |
| Branch / PR | <branch name or PR number> |
| Date | <YYYY-MM-DD> |
| Overall regression risk | **<High / Medium / Low>** — <one plain-language reason> |
| Requirements checked against | <PRD / HLD / work-item names as given, or "No specs provided"> |

## 1. What changed for users

<2 to 5 short sentences: what a user, an admin or an integrated system now sees or gets that is different. Say which screens, features or flows. If nothing is visible to users (an internal change), say so and name what it affects.>

## 2. Regression tests to run

Existing behaviour that this change could have broken. Highest risk first. Every row is something QA already knows how to test.

| # | Area / feature | What to check still works | Why it could break (plain words) | Risk |
|---|---|---|---|---|
| 1 | <area> | <the existing behaviour to re-check> | <what in the change touches it> | <High / Medium / Low> |

## 3. New behaviour to verify

What is new or changed on purpose and has no existing test to fall back on.

| # | Feature | Expected behaviour | Where to see it |
|---|---|---|---|
| 1 | <feature> | <what should happen> | <screen, flow, setting, API consumer> |

## 4. Differences from the requirements

Everything that was built differently from the PRD / HLD / work item, or not built. Empty means none were found in the provided requirements.

| # | Requirement (as written in the spec) | What was built instead | Why (if known) | Needs a decision from |
|---|---|---|---|---|
| 1 | <quote or close paraphrase> | <what the product does now> | <reason from the notes, or "Unknown"> | <Product / Dev / QA> |

Requirements the provided specs do not mention are listed here as "Not covered by provided specs", never as missing.

## 5. Setup QA needs

<Flags, settings, tenants, accounts, test data, migrations or integrations that must be in place before testing. "None" if nothing.>

## 6. Not affected

<Areas checked and found untouched, one line each, so QA can skip them. "None checked" if nothing was ruled out.>

## 7. Open questions for dev / product

<Questions whose answer changes what QA should test. "None" if nothing.>
