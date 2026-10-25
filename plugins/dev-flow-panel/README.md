# dev-flow-panel

A band above the prompt, and a pane on request, for the [dev-flow](../dev-flow) plugin: a colour-coded view of the stage the current task is in, and one button per skill.

```
/plugin install dev-flow-panel --marketplace MPesin/ai-tools
```

## The band

While a task is active, two rows sit above the prompt and nothing opens by itself. Without a task the band is not drawn, so it costs no rows.

```
▎ Your review   ⚠ needs decision  login fix · round 2 · full · base main        ●─●─●─●─◉─○─○
▎ [ Plan ] [ Implement ] [ QA impact ]   ↻ refresh   panel ↗   Waiting for you: review the diff…
```

The stage is a chip on a block of its theme colour, and an accent bar in the same colour ties the two rows. After the chip come the flags for `needs-decision.md` and `violations.md`, the task (plan.md's `task`, else the folder's name) and, dim, the review round, mode and base. At the right end a track of the seven stages shows the steps behind you filled and the current one ringed; it is the first thing to give way when the column is narrow. The second row holds the buttons, with the suggested next step drawn as the primary one, and the hint for this stage, truncated rather than wrapped and left out when fewer than 24 cells remain. The engine's own `[-]` collapses the band.

| Button | Runs |
|---|---|
| Plan | `/dev-flow:dev-plan` |
| Implement / Resume | `/dev-flow:dev-implement <plan.md of the active task>` |
| QA impact | `/dev-flow:dev-qa-impact <task folder>` |
| ↻ refresh | re-reads the task folder now |
| panel ↗ | opens the pane below |

With the band or the pane focused (ctrl+x tab, or a click) the hotkeys `p`, `i` and `q` press the three skill buttons.

## The pane

`/dev-flow-panel` (or the band's `panel ↗` button) opens a pane: the chip and the task in a header, the seven stages as a list with the steps behind you ticked and the hint under the current one, the flags, and the same buttons.

```
╭────────────────────────────────────╮
│ Your review   login fix            │
│ round 2 · full · base main         │
╰────────────────────────────────────╯

 ✓ Planning
 ✓ Approved
 ✓ Implementing
 ✓ Claude review
 ◉ Your review
   Waiting for you: review the diff,
   commit, open the PR, then continue.
 ○ QA impact
 ○ Done

 ⚠ needs-decision.md
   findings wait for your decision

 [ Plan ] [ Implement ] [ QA impact ]
 ↻ refresh
```

In the fullscreen layout the pane docks beside the transcript, where the header is framed in the stage's colour. A dock always runs the full height of the terminal, so the pane asks for a narrow column (40 cells, which the engine floors at 24 and caps at 45% of the width) instead of the default share. On the main screen it opens inline above the prompt, sized to its own rows rather than a third of the screen, with the accent bar in place of the frame. A width or height you drag it to wins over both.

## Where the stage comes from

The same files the dev-flow hooks use: `<project>/.claude/flow/current` or `planning` points at the task folder, and `plan.md`'s frontmatter holds `status`, `mode` and `review_round`. The plugin polls every 4 seconds and refreshes right after a tool call touches those files. The status line under the prompt shows the same stage.

| Stage | Colour (theme key) |
|---|---|
| Planning | subtle |
| Approved | suggestion |
| Implementing | claude |
| Claude review | permission |
| Your review | warning |
| QA impact | ide |
| Done | success |
| Blocked | error |

## Developing

This is a hooks module (`hooks/register.tsx`), not a bash hook. `claude plugin validate plugins/dev-flow-panel` checks it, `claude plugin test plugins/dev-flow-panel` runs `hooks/register.test.tsx` against the engine, and `tsc -p plugins/dev-flow-panel` type-checks it once the engine has laid its declarations in `.claude-plugin/types/` (it does so on first load).
