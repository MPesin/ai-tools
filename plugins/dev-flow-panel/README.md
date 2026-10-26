# dev-flow-panel

A band above the prompt for the [dev-flow](../dev-flow) and [dev-debug](../dev-debug) plugins: a colour-coded view of the stage the current task is in (features and bugs each have their own stage list), and one button per skill. It is horizontal, sits right above the prompt, has no background of its own, and takes only the rows it draws: two by default.

```
/plugin install dev-flow-panel --marketplace MPesin/ai-tools
```

No pane: a pane docked beside the transcript runs the full height of the terminal whatever is in it, which is the one thing a plugin cannot change.

## Compact

While a task is active, two rows sit above the prompt. Without a task nothing is drawn, so the band costs no rows.

```
▎ Your review   ⚠ needs decision  login fix · round 2 · full · base main        ●─●─●─●─◉─○─○
▎ [ Plan ] [ Debug ] [ Implement ] [ QA impact ]   ↻ refresh   more ▾   Waiting for you: review the diff…
```

The stage is a chip on a block of its theme colour, and an accent bar in the same colour runs down the band. After the chip come the flags for `needs-decision.md` and `violations.md`, the task (plan.md's `task`, else the folder's name) and, dim, the review round, mode and base. At the right end a track of the task's stages shows the steps behind you filled and the current one ringed; it is the first thing to give way when the column is narrow. The second row holds the buttons, with the suggested next step drawn as the primary one, and the hint for this stage, truncated rather than wrapped and left out when fewer than 24 cells remain.

## Full

`/dev-flow-panel`, or the band's `more ▾`, expands it; the command or `less ▴` folds it back. Expanded, the band is drawn even without a task.

```
▎ Your review   ⚠ needs decision  login fix · round 2 · full · base main        ●─●─●─●─◉─○─○
▎ ✓ Planning  ✓ Approved  ✓ Implementing  ✓ Claude review  ◉ Your review  ○ QA impact  ○ Done
▎   Waiting for you: review the diff, commit, open the PR, then continue.
▎ ⚠ needs-decision.md  findings wait for your decision
▎ [ Plan ] [ Debug ] [ Implement ] [ QA impact ]   ↻ refresh   less ▴
```

The stage list runs across, wrapping onto a second row in a narrow column, with the steps behind you ticked and the ones ahead hollow. Under it the hint for the current stage, then one row per flag.

| Button | Runs |
|---|---|
| Plan | `/dev-flow:dev-plan` |
| Debug | `/dev-debug:dev-debug` (the dev-debug plugin), with the active task folder while it is diagnosing, so a press brings the diagnosis gate back. Primary at that stage. |
| Implement / Resume | `/dev-flow:dev-implement <plan.md of the active task>`. Dim while the plan is still a draft or a diagnosis is in progress (the `planning` pointer exists): a press then shows why instead of running the skill, since the plan has to be approved in chat first. |
| QA impact | `/dev-flow:dev-qa-impact <task folder>` |
| ↻ refresh | re-reads the task folder now |
| more ▾ / less ▴ | expands or folds the band |

With the band focused (ctrl+x tab, or a click) the hotkeys `p`, `d`, `i` and `q` press the four skill buttons. The engine's own `[-]` at the band's right end collapses it altogether.

## Bug tasks

A task diagnosed by the [dev-debug](../dev-debug) plugin (`plan.md` has `source: dev-debug`) has its own stage list and track, eight steps instead of seven, since the fix plan is written from a confirmed diagnosis rather than planned:

```
▎ ✓ Diagnosing  ◉ Confirm cause  ○ Approved  ○ Implementing  ○ Claude review  ○ Your review  ○ QA impact  ○ Done
▎   Waiting for you: confirm the root cause (reply fix), add facts, ask for a second opinion, or stop at the diagnosis.
```

**Diagnosing** is the debugger at work (`status: diagnosing`, no `diagnosis.md` yet). **Confirm cause** is the diagnosis gate: the same status once `diagnosis.md` exists, the band's `warning` colour since it waits for you, with Debug as the primary button to bring the gate back. **Approved** is the fix plan; in the moment it is being written (`status: draft`) the step is drawn as **Fix plan**. From Implementing on, a bug runs through the same steps as a feature, with the first two ticked. Implement is dim until the plan is approved and explains why on a press.

## Where the stage comes from

The same files the dev-flow hooks use: `<project>/.claude/flow/current` or `planning` points at the task folder, and `plan.md`'s frontmatter holds `status`, `mode`, `review_round` and `source`; `diagnosis.md` in the task folder tells Diagnosing from Confirm cause. The plugin polls every 4 seconds and refreshes right after a tool call touches those files. The status line under the prompt shows the same stage.

Every stage has a theme colour of its own, and it is used wherever that stage appears: its chip and the accent bar while it is current, its dot in the track, and its glyph in the list, where the label is in colour behind you, bold for the current step and dim ahead. Hints are dim italics, ticks are `success`, and the flags are `warning` and `error`. Theme keys rather than raw colours, so it follows your theme. (On the terminal `dimColor` replaces a colour rather than tinting it, which is why a dim label sits next to a coloured glyph instead of being coloured itself.)

| Stage | Colour (theme key) |
|---|---|
| Planning | subtle |
| Diagnosing (bug) | claude |
| Confirm cause (bug) | warning |
| Fix plan (bug) | subtle |
| Approved | suggestion |
| Implementing | claude |
| Claude review | permission |
| Your review | warning |
| QA impact | ide |
| Done | success |
| Blocked | error |

## Developing

This is a hooks module (`hooks/register.tsx`), not a bash hook. `claude plugin validate plugins/dev-flow-panel` checks it, `claude plugin test plugins/dev-flow-panel` runs `hooks/register.test.tsx` against the engine, and `tsc -p plugins/dev-flow-panel` type-checks it once the engine has laid its declarations in `.claude-plugin/types/` (it does so on first load).
