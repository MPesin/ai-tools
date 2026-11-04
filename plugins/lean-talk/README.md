# lean-talk

Lean responses and documents. Whole sentences with every fact kept, filler and hedging cut, the answer in the first line. Lists for parallel items, tables for repeated fields, a budget per document section. Grammar and articles stay, and nothing that is persisted is left with two readings.

```
/plugin install lean-talk --marketplace MPesin/ai-tools
```

## Skills

- `/lean-talk:lean-talk` - switch the mode on for the session: every reply, and every document written or edited, follows the rules. "stop lean" or "normal mode" switches it off. The rules shape the text as it is written; there is no second pass that takes a long draft and shortens it.
- `/lean-talk:lean-edit <file>`, or `/lean-talk:lean-edit` with pasted text - rewrite text that already exists by the same rules: a file in place, pasted text in the reply. Headings, frontmatter, code, links, tables and anything between `<!-- keep -->` and `<!-- /keep -->` stay as they are; no fact, number, condition, name or instruction is dropped. The reply gives the line and word counts before and after.

## Always on

A skill loads only when it is invoked, so a new session starts in normal mode. To have the mode on in every session, add one line to a `CLAUDE.md`:

```markdown
Before your first reply in a session, invoke the `lean-talk:lean-talk` skill and keep it on.
```

Where to put it:

- `~/.claude/CLAUDE.md` applies to every project on your machine. Create the file if it does not exist.
- `<project>/CLAUDE.md` applies to that project only, for everyone who works in it with the plugin installed.

The skill text, about 90 lines, is then loaded once per session. Without the plugin installed the line does nothing but make Claude say the skill is missing.

## The rules in one table

| Keep | Cut | Shape |
|---|---|---|
| whole sentences, articles, grammar | preamble, closers, hedging, filler | the answer first, then the reason, then the next step |
| every negation, number and unit | a sentence that restates its heading or the question | one idea per sentence, 20 words or fewer |
| code, paths, commands, errors verbatim | a fact stated twice | a paragraph of at most 3 sentences, and only for non-parallel items |
| one term per thing, no invented abbreviations | the story of how you found something | lists for parallel items, tables for repeated fields, one sentence per cell |
| the reader's language | praise and commentary on your own work | evidence as `file:line` or one quoted output line |

In replies: one line before a multi-step tool run, one at a change of direction, one with the result, and no recap at the end. Full sentences anyway for an irreversible action, a security warning, a sequence a list could scramble, and a question to the user.

## Where it comes from

The caveman skill (JuliusBrussee/caveman) cuts replies to fragments and, by its own rules, leaves documents alone. Its sane part is ASD-STE100, the controlled English of maintenance manuals. Short sentences, one instruction each, active voice, one term per thing, with the articles and the grammar kept. This skill is that part, applied to replies and documents alike.

