# dev-flow-panel

A band above the prompt, and a pane on request, for the [dev-flow](../dev-flow) plugin: a colour-coded view of the stage the current task is in, and one button per skill.

```
/plugin install dev-flow-panel --marketplace MPesin/ai-tools
```

## The band

While a task is active, two rows sit above the prompt and nothing opens by itself. Without a task the band is not drawn, so it costs no rows.

```
● Your review  round 2 · full  ·  login fix  ·  ••••●○○                 needs decision
[ Plan ] [ Implement ] [ QA impact ]  refresh  panel   Waiting for you: review the diff…
```

The first row is the stage (coloured by its theme key), the review round and mode, the task, and a track of the seven stages with the steps behind you filled. Flags for `needs-decision.md` and `violations.md` sit at the right. The second row holds the buttons and the hint for this stage; the hint truncates rather than wraps, so the band never grows past two rows. The engine's own `[-]` collapses it.

| Button | Runs |
|---|---|
| Plan | `/dev-flow:dev-plan` |
| Implement / Resume | `/dev-flow:dev-implement <plan.md of the active task>` |
| QA impact | `/dev-flow:dev-qa-impact <task folder>` |
| refresh | re-reads the task folder now |
| panel | opens the pane below |

The suggested next step is drawn as the primary button. With the band focused (ctrl+x tab, or a click) the hotkeys are `p`, `i`, `q`, `r` and `d`.

## The pane

`/dev-flow-panel` (or the band's `panel` button) opens a pane with the full stage list, the steps behind you ticked, the hint for the current stage, and the same buttons. In the fullscreen layout the pane docks beside the transcript: a dock always runs the full height of the terminal, so the pane asks for a narrow column (40 cells, which the engine floors at 24 and caps at 45% of the width) instead of the default share. On the main screen it opens inline above the prompt, sized to its own rows rather than a third of the screen. A width or height you drag it to wins over both.

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
