---
name: lean-edit
description: Rewrite existing text lean - a markdown file in place, or pasted text returned in the reply. Use for "/lean-edit", "/lean-edit <file>", "shorten this", "make this lean", "tighten this document", "too wordy, rewrite it". Keeps every fact, heading, code block, link and table. Not for writing new text - that is lean-talk.
---

# Lean edit

Rewrite the given text so the reader gets every fact in one pass and reads nothing else. The rules are in `${CLAUDE_PLUGIN_ROOT}/skills/lean-talk/SKILL.md`: read it and apply Keep, Cut, Shape, Documents and Full sentences anyway. This file adds what an edit of existing text needs.

## Input

- A file path: rewrite the file in place. Several paths: one file at a time, each with its own report.
- Pasted text, or "this" pointing at text in the conversation: return the rewritten text in the reply, with nothing before or after it.
- Code or configuration files: refuse and say why; the skill rewrites prose only.

## What stays as it is

- Every heading and its order, the frontmatter, code blocks, inline code, links, images, tables and their columns, IDs and numbering.
- Anything between `<!-- keep -->` and `<!-- /keep -->`.
- Quoted text and text saved verbatim: a spec excerpt, a bug report, a work item, a reviewer's comment, legal text.
- The language of the text.

## Process

1. Read the whole input once.
2. Rewrite section by section in one pass. Parallel sentences become a list and repeated fields a table. Merge bullets that say the same thing, keep one example per pattern, cut hedging and filler.
3. Drop no fact, number, condition, name or instruction. Unsure whether a sentence carries one? Keep the sentence.
4. Write the file back, or return the text. Report in two lines: lines and words before and after, and what you left long on purpose.

## Hard rules

- Never change the meaning. A dropped negation, condition or number is a defect, not a saving.
- Never add: no new facts, no commentary, no note about the edit inside the text.
- Never touch anything outside the given text or file.
- Where lean-talk says full sentences anyway, keep them.
