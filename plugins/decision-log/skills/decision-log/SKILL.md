---
name: decision-log
description: Use when a decision with non-obvious reasoning was just made or rejected (during a bug fix, a plan, or a review) and should be recorded for the repo; when the user asks why something is built the way it is or whether an approach was already tried; or when /decision-log:init, /decide, /why, or /decision-log:lint is invoked. Maintains the per-repo decisions project skill at .claude/skills/decisions/.
when_to_use: Trigger phrases - why do we, why is this, have we tried, did we already decide, we decided to, instead of X because, record this decision, no use X because - and after a root cause turned out to be surprising.
argument-hint: "[init | decide [text] | decide accept D-nnn | why [topic] | lint]"
---

# Decision Log

Maintains a **project skill** at `.claude/skills/decisions/` in the target
repo: a ≤100-line `SKILL.md` index that routes by domain, and one
`references/<domain>.md` per domain holding decision records. Plain
markdown any agent can read; committed to git; nothing derivable from git is
stored (no timestamps, counts, or manifests).

What belongs here: the **why** that code cannot tell you — a choice between
alternatives, the constraint that forced it, what was rejected and why, and
the consequences the next person will hit. What does not: facts derivable from
the code (that is the repo-guide's job), personal preferences (auto memory),
and task progress (worklog).

| Mode | Load |
|------|------|
| `init` — create the skill, optionally seed it | `references/capture.md` §Init, `references/record-spec.md` |
| `decide` — draft one record, gate it, write on approval | `references/capture.md`, `references/record-spec.md` |
| `why` — answer from records | `references/capture.md` §Query |
| `lint` — health check, report first | `references/lint.md` |

**Non-negotiables**
- Never write a record without showing it, rendered exactly as it will be
  written, and getting a yes. Never *accept* one that lacks a rejected
  alternative (or an explicit "none considered because …") — a record
  without a *why not* restates the code. Seeded records may carry `Rejected:
  unknown` only while `proposed`.
- Accepted record bodies are immutable. Changing course means a new record
  that supersedes the old one; the old one gets a status line, not an edit.
- Not derivable from code, not personal, paths named. A candidate that fails
  a gate is declined with the reason and, if personal, handed to auto memory.
- Implicit capture is best-effort: when a session produced a decision worth
  keeping, *propose* `/decide` in one line. Never write silently, never nag
  twice about the same decision.

## Retrieval, two ways

- **File-driven**: the generated skill declares `paths:` covering every
  domain's globs, so it loads on its own when Claude reads matching files,
  and its table routes to the one domain file that matters.
- **Question-driven**: this skill's description catches "why / have we
  tried" questions anywhere, and mode `why` greps the records directly. Plans
  and PR descriptions cite records by id (`D-014`).

## Routing details

- Mode from the first argument; without one, infer: a question → `why`; a
  decision just made in the conversation → `decide`; no skill present →
  offer `init` first.
- All modes start by reading `.claude/skills/decisions/SKILL.md` if present
  (the domain table is the source of truth for domains and paths). Shell
  commands in the references run from `.claude/skills/decisions/`.
- A record's current status is its **last** `status:` line (supersede and
  deprecate append lines; they never rewrite line 2).
