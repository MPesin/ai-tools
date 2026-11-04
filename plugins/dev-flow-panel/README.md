# dev-flow-panel

A band above the prompt for the [dev-flow](../dev-flow) and [dev-debug](../dev-debug) plugins: a colour-coded view of the stage the current task is in (features and bugs each have their own stage list), and one button per skill. It is horizontal, sits right above the prompt, has no background of its own, and takes only the rows it draws: a dim rule that keeps it apart from the transcript scrolling above, a blank row of padding, and two rows of content by default.

```
/plugin install dev-flow-panel --marketplace MPesin/ai-tools
```

No pane: a pane docked beside the transcript runs the full height of the terminal whatever is in it, which is the one thing a plugin cannot change.

## Compact

While a task is active, the band sits above the prompt: a rule across the column, a blank row, then two rows. Without a task nothing is drawn, so the band costs no rows, unless you fold the expanded band with `less ▴` (see below).

```
──────────────────────────────────────────────────────────────────────────────────────────────────

▎ Your review   ⚠ needs decision  login fix · round 2 · full · base main        ●─●─●─●─◉─○─○
▎ [ Plan ] [ Debug ] [ Implement ] [ QA impact ] [ Clear ]   ↻ refresh   more ▾   Waiting for you: review…
```

The rule is dim and spans the column, so the band reads as its own block under whatever Claude last printed. The stage is a chip on a block of its theme colour, and an accent bar in the same colour runs down the band. After the chip come the flags for `needs-decision.md` and `violations.md`, the task (plan.md's `task`, else the folder's name) and, dim, the review round, mode and base. At the right end a track of the task's stages shows the steps behind you filled and the current one ringed; it is the first thing to give way when the column is narrow. The second row holds the buttons, with the suggested next step drawn as the primary one, and the hint for this stage, truncated rather than wrapped and left out when fewer than 24 cells remain.

## Full

`/dev-flow-panel`, or the band's `more ▾`, expands it. Expanded, the band is drawn even without a task. `less ▴` folds it back to the two rows, and they stay drawn without a task too (`No active task`, with Load at hand) for the rest of the session, so the band does not vanish under the click. The command folds it back to the default instead, drawn only while a task is active, which is also how you put the folded band away.

```
──────────────────────────────────────────────────────────────────────────────────────────────────

▎ Your review   ⚠ needs decision  login fix · round 2 · full · base main        ●─●─●─●─◉─○─○
▎ ✓ Planning  ✓ Approved  ✓ Implementing  ✓ Claude review  ◉ Your review  ○ QA impact  ○ Done
▎   Waiting for you: review the commits; push and open the PR (or ask Claude to), then QA impact.
▎ ⚠ needs-decision.md  findings wait for your decision
▎ [ Plan ] [ Debug ] [ Implement ] [ QA impact ] [ Clear ]   ↻ refresh   less ▴
```

Without a task of this session the last button is `[ Load ]` instead of `[ Clear ]`.

The stage list runs across, wrapping onto a second row in a narrow column, with the steps behind you ticked and the ones ahead hollow. Under it the hint for the current stage, then one row per flag.

| Button | Runs |
|---|---|
| Plan | `/dev-flow:dev-plan` |
| Debug | `/dev-debug:dev-debug` (the dev-debug plugin), with the active task folder while it is diagnosing, so a press brings the diagnosis gate back. Primary at that stage. |
| Implement / Resume | `/dev-flow:dev-implement <plan.md of the active task>`. Dim while the plan is still a draft or a diagnosis is in progress (`plan.md` at `draft` or `diagnosing`): a press then shows why instead of running the skill, since the plan has to be approved in chat first. A `planning` pointer left behind by a plan at a later status does not dim it; the dev-flow hooks treat such a pointer as stale too. |
| QA impact | `/dev-flow:dev-qa-impact <task folder>`. Primary at Your review and Done. At Your review it means the review is done: the skill runs the flow's QA impact stage and its final report, so the run ends at Done and its guards go off (no Clear needed). Ask Claude to push and open the PR before or with it; the main session may do both while the flow is active. |
| Load | `/dev-flow:load-flow`: lists the task folders under the plans location with their status and which session holds them, and hands the one you pick to the skill its status needs. Drawn while this session has no task. |
| Clear | `/dev-flow:clear-flow`: switches this session's flow off (its pointer files and the hooks' markers go; the task folder and `plan.md` stay, so Load brings the task back). Drawn while this session has a task. It abandons the run; it is not needed to push, open the PR or finish. |
| ↻ refresh | re-reads the task folder now |
| more ▾ / less ▴ | expands the band, or folds it to two rows, which stay drawn even without a task |

With the band focused (ctrl+x tab, or a click) the hotkeys `p`, `d`, `i`, `q`, `l` and `c` press the skill buttons. The engine's own `[-]` at the band's right end collapses it altogether.

## Bug tasks

A task diagnosed by the [dev-debug](../dev-debug) plugin (`plan.md` has `source: dev-debug`) has its own stage list and track, eight steps instead of seven, since the fix plan is written from a confirmed diagnosis rather than planned:

```
▎ ✓ Diagnosing  ◉ Confirm cause  ○ Approved  ○ Implementing  ○ Claude review  ○ Your review  ○ QA impact  ○ Done
▎   Waiting for you: confirm the root cause (reply fix), add facts, ask for a second opinion, or stop at the diagnosis.
```

**Diagnosing** is the debugger at work (`status: diagnosing`, no `diagnosis.md` yet). It is shown from the moment dev-debug starts in this session (the Debug button, `/dev-debug:dev-debug` typed, or the model running the skill): the skill writes the `planning` pointer before `plan.md`, and until `plan.md` says `source: dev-debug` the band goes by the flow skill this session started last, so the bug's list replaces the feature's even before there is a task folder. **Confirm cause** is the diagnosis gate: the same status once `diagnosis.md` exists, the band's `warning` colour since it waits for you, with Debug as the primary button to bring the gate back. **Approved** is the fix plan; in the moment it is being written (`status: draft`) the step is drawn as **Fix plan**. From Implementing on, a bug runs through the same steps as a feature, with the first two ticked. Implement is dim until the plan is approved and explains why on a press.

## Where the stage comes from

The same files the dev-flow hooks use: `<project>/.claude/flow/current` or `planning` points at the task folder (when both exist, the task being planned or diagnosed is shown while its plan is at `draft` or `diagnosing`; a `planning` pointer past that is stale and the `current` task is shown), and `plan.md`'s frontmatter holds `status`, `mode`, `review_round` and `source`; `diagnosis.md` in the task folder tells Diagnosing from Confirm cause. A `planning` pointer whose `plan.md` is not written yet is Diagnosing when dev-debug is the flow skill this session started last, and Planning otherwise. The plugin polls every 4 seconds and refreshes right after a tool call touches those files. The status line under the prompt shows the same stage.

A pointer also names the session it belongs to (`session: <id>` on its second line, stamped by the dev-flow hooks right after the skill writes it), and the band shows a task only when it belongs to this session, or to no session yet. Another session's task on the same checkout is not this band's: the compact band is not drawn for it, and the expanded band names it in one dim line (`login fix · Your review · another session`) next to `No active task`, so two sessions in the same folder each see their own work.

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
