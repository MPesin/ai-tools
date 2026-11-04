# Writing style

How `diagnosis.md`, the fix plan and the gate summary are written. Sentences stay whole, articles and grammar stay, every fact stays; what a reader would skip goes. The rules are the `lean-talk` plugin's skill, `plugins/lean-talk/skills/lean-talk/SKILL.md` in the same marketplace, and the `dev-flow` plugin's `skills/dev-implement/writing-style.md`. They are repeated here because a subagent reads files and cannot invoke a skill; change all three together. The section budgets for `diagnosis.md` are under Required headings in `diagnosis-format.md`.

## Keep

- Full sentences with their articles. Fragments only in table cells and in list items that are not sentences.
- Every `not`, `never`, `no`, `only`, `except`, `unless`. Numbers and units exact.
- Code, commands, paths, identifiers and error text verbatim, in backticks. Never paraphrase an error message or a stack frame.
- One term per thing, the project's term. No invented abbreviations (`cfg`, `impl`), no arrows, no symbols standing in for words.
- The language the project's guidance names for the document; otherwise English. Compress the style, not the language.

## Cut

- Preamble and closers: "This document describes", "In summary".
- Hedging: "it might be worth", "you may want to consider", "probably", "I think". State it, or mark it unverified.
- Filler: just, really, basically, actually, simply, essentially, "in order to", "make sure to".
- A sentence that restates its heading. A fact another section already states: each fact once.
- The story of the investigation. The hypotheses go in the ruled-out table; the prose keeps the cause and its evidence.
- Praise, apology and commentary on your own work.

## Shape

- Conclusion first, then the reason, then the next step.
- One idea per sentence. 20 words or fewer; 25 is the hard limit.
- A paragraph holds at most 3 sentences, and only when they are not parallel items.
- Parallel items are a bulleted list, one line each. Ordered actions, and a mechanism from input to failure, are a numbered list.
- The same fields repeated for several items are a table, one sentence per cell.
- Evidence is `file:line`, a command, or one quoted output line, never a description of the evidence.
- A heading names its content; the first sentence under it adds what the heading does not say.

## Per file

| File | Shape |
|---|---|
| `diagnosis.md` | the three header lines, then the section budgets under Required headings in `diagnosis-format.md` |
| `plan.md` | the fix plan: each step in three lines (path, change, verification); Context 3 to 5 lines; one line per fact, risk and criterion |
| `debug/` | scripts and captured output as they are; never trimmed inside the files, only quoted in the diagnosis |
| the gate summary in chat | one line each: symptom, reproduced or not, root cause with `file:line`, confidence, blast radius, fix steps, regression test, open questions |

## Full sentences anyway

Plain prose, whole sentences, for:

- an irreversible or destructive action;
- a security warning;
- a sequence a list could scramble;
- a question to the user, with its options;
- anything the reader has already misread once.

## Checks while writing

The rules shape the text as you write it; never write long and shorten afterwards. On the draft in your head, not a rewrite of written text:

1. First sentence announces or restates the heading? Delete it.
2. Last sentence recaps? Delete it.
3. A paragraph that is a list in disguise? Make it a list.
4. A sentence with two readings? Rewrite it as one full sentence.
5. Every negation, number, path, command and error still there, verbatim?
