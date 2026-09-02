# Lint — keep the decisions skill trustworthy

Report first; change files only after the user approves each group of
fixes. Read `SKILL.md` and every `references/*.md`.

| Check | How | Proposed fix |
|-------|-----|--------------|
| Duplicate ids | `grep -h '^### D-' references/*.md \| sort \| uniq -d` | renumber the later one (by git history) and update citations found by `grep -rn D-<n>` |
| Dead paths | each record's `paths:` and each table glob: `git ls-files <glob>` empty | ask: update the glob, or mark the record `deprecated` |
| Stale, unevidenced | `date` older than 12 months and no `Evidence:` | list for review; no automatic change |
| Orphaned proposals | `status: proposed` older than 90 days | ask: accept, or delete (a proposal was never accepted, so deleting it is allowed) |
| Contradictions | two `accepted` records in one domain answering the same question (same subject, different decision) | propose that the newer supersedes the older |
| Broken supersede links | `superseded-by D-<n>` where D-<n> does not exist, or a superseding record whose Context does not name the old id | fix the link |
| Missing `Rejected:` | record without the line | ask the user for it, or mark `proposed` |
| Oversized domain file | > 250 lines | propose a split with the new table row and `paths:` entry |
| Oversized index | `SKILL.md` > 100 lines | coarser domains or shorter prose |
| Table drift | a `references/*.md` not in the table, a table row without a file, or `paths:` not equal to the union of table globs | regenerate table rows and `paths:` from the files and globs |
| Rules leaking in | a record that is an instruction ("always use X") with no decision behind it | move to CLAUDE.md or REVIEW.md, or add the why |

Output: one line per finding with the file and id, grouped by check, then
the proposed fixes as a numbered list to approve. End with the counts
(records per domain, derived — not written anywhere).
