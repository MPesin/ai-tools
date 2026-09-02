# REVIEW.md — path-scoped review rules and learnings

`REVIEW.md` at the repository root is plain markdown read by review mode
(quoted into `rules.md`) and, when the organization uses it, by Anthropic's
managed Code Review — the same file serves both. It is committed; it is team
knowledge.

## Format

```markdown
# Review guidance

<preamble: applies to every file>
- Rule: public API methods validate arguments and return ProblemDetails.
  Bad: `throw new ArgumentException(...)` from a controller.
  Good: `return ValidationProblem(...)`.
  Why: clients depend on the RFC 7807 shape; see D-014 in .claude/skills/decisions.
- Do not flag: missing XML doc comments (we generate them at release).

## paths: src/Api/**, tests/Api/**
- Rule: every new endpoint has a 4xx test. Bad/Good/Why as above.

## paths: scripts/**
- Do not flag: shell quoting in one-off scripts unless the bug is certain.
```

- One rule per bullet; prescriptive verbs; each `Rule:` carries Bad, Good,
  and Why so the reviewer can quote it and the author can see the intent.
- `## paths:` sections scope everything below them until the next `##`
  heading. Globs are gitignore-style, relative to the repo root.
- `Do not flag:` lines are exclusions. They win over rules.
- Cite decision-log records (`D-nnn`) rather than restating their reasoning.

## Learn mode

Input: the argument, or the finding the user just confirmed ("yes, make that
a rule") or dismissed ("that's intentional") in the conversation.

1. Draft one bullet in the format above. A confirmed finding becomes a
   `Rule:` with the finding's evidence as the Bad example; a dismissal becomes
   `Do not flag:` with the reason and today's date.
2. Propose the scope: the touched file's directory as a `paths:` glob when the
   rule is local, unscoped when it is general. Check the glob matches at
   least one tracked file (`git ls-files <glob>`); refuse a dead glob.
3. Caps: warn at 30 bullets, refuse beyond 40 until the user prunes — a
   quoted file that outgrows the diff stops being read. Offer to merge or
   drop near-duplicates (same subject) before adding.
4. Show the bullet and its section; write only on yes; recommend committing
   `REVIEW.md` with the message `review: <rule subject>`.

Nothing else in this plugin writes to the repository.
