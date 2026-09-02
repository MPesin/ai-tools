# Record spec — contract for the generated decisions skill

```
.claude/skills/decisions/
├── SKILL.md              # index + domain routing, ≤100 lines
└── references/
    ├── <domain>.md       # records for one domain, ≤250 lines
    └── ...
```

Nothing else. No index file, no counts, no timestamps beyond each record's
`date` (which is content — the date of the decision — not provenance). Git
history is the provenance.

## SKILL.md

```markdown
---
name: decisions
description: Decisions and their reasoning for <repo name> — read before planning, changing, or debugging anything in a listed domain, and before proposing an architectural or dependency change. Routes to per-domain records of what was decided, what was rejected and why, and the consequences.
when_to_use: why do we, why is this, have we tried, did we decide, before replacing or refactoring a listed area
paths:
  - src/Billing/**
  - src/Auth/**
---

# Decisions — <repo name>

Read the domain file for the area you are touching; cite records by id
(`D-014`) in plans, commits, and PR descriptions. Records with status
`accepted` are current. Superseded and deprecated records explain history —
read them only when asking why something changed. To add one: `/decide`.

| Domain | Paths | File |
|--------|-------|------|
| billing | src/Billing/**, src/Invoicing/** | references/billing.md |
| auth | src/Auth/** | references/auth.md |
| build | *.csproj, Directory.*.props, .github/** | references/build.md |

What qualifies as a record: a choice between alternatives with a constraint
behind it, a rejected approach, a gotcha that cost real time. Not: facts
readable from the code, personal preferences, task status.
```

- `paths:` is the union of the table's globs, kept in sync by `decide` (when
  it adds a domain) and `lint`. It makes the skill load automatically when
  Claude reads a matching file.
- The table is the only place domains and their globs are defined. No count
  column — counts are derivable.
- Hard cap 100 lines. A repo with more domains than fit gets a coarser
  domain split, not a longer file.

## Domain file

```markdown
# Decisions — billing

### D-014 — Use Dapper instead of EF Core for reporting reads
date: 2026-08-30 · status: accepted · paths: src/Reporting/**
Context: monthly reports join 6 tables over ~40M rows; EF Core's generated
SQL took 30-90 s and could not use the covering index.
Decision: reporting queries are hand-written SQL through Dapper in
`ReportingReadStore`; writes stay in EF Core.
Rejected: EF Core raw SQL (`FromSqlRaw`) — still materializes entities and
tracks them, 3x slower in the spike; a read replica with EF — cost, and the
query shape was the problem, not the load.
Consequences: two data-access styles in one project; reporting SQL is not
migrated automatically — schema changes must update `sql/reporting/*.sql`.
Evidence: PR #212, spike notes in docs/spikes/reporting-perf.md

### D-021 — ...
```

Rules:
- One `###` block per record, in id order (append at the end). Id `D-<n>`,
  global across domains, next = max existing + 1 (`grep -h '^### D-'
  references/*.md`).
- Line 2 carries `date`, `status`, `paths` — `paths` is required and must
  match at least one tracked file at write time.
- `Rejected:` is required: at least one alternative with its reason, or
  `none considered because <reason>`.
- `Evidence:` is optional but expected: commit, PR, issue, test, or document.
- Status values: `proposed` (from seeding or a single session, not yet
  confirmed by the user), `accepted`, `deprecated` (no longer applies, no
  replacement), `superseded-by D-nnn`.
- Body immutability: once `accepted`, only new lines of the form
  `status: superseded-by D-021 (2026-09-14)` or `status: deprecated
  (2026-09-14) — <reason>` may be added, directly under line 2. The
  superseding record's `Context` names what it replaces.
- File cap ~250 lines; `lint` proposes a split (e.g. `billing.md` →
  `billing-invoicing.md`) with the table updated.

## What is never stored

Generation dates, last-verified stamps, record counts, an index of ids,
who wrote a record (git blame has it), and anything the repo-guide skill or
the code already states.
