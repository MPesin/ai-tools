# dev-flow-panel

A pane beside the chat for the [dev-flow](../dev-flow) plugin: one button per skill and a colour-coded view of the stage the current task is in.

```
/plugin install dev-flow-panel --marketplace MPesin/ai-tools
```

`/dev-flow-panel` opens the pane (it also opens by itself at session start when a task is active). The buttons run the skills as if you typed them:

| Button | Runs |
|---|---|
| Plan | `/dev-flow:dev-plan` |
| Implement / Resume | `/dev-flow:dev-implement <plan.md of the active task>` |
| QA impact | `/dev-flow:dev-qa-impact <task folder>` |
| refresh | re-reads the task folder now |

The stage comes from the same files the dev-flow hooks use: `<project>/.claude/flow/current` or `planning` points at the task folder, and `plan.md`'s frontmatter holds `status`, `mode` and `review_round`. The pane polls every 4 seconds and refreshes right after a tool call touches those files. The status line under the prompt shows the same stage.

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

`needs-decision.md` and `violations.md` in the task folder are flagged in the pane and the status line.

This is a hooks module (`hooks/register.tsx`), not a bash hook. `claude plugin validate plugins/dev-flow-panel` checks it, `claude plugin test plugins/dev-flow-panel` runs `hooks/register.test.tsx` against the engine, and `tsc -p plugins/dev-flow-panel` type-checks it once the engine has laid its declarations in `.claude-plugin/types/` (it does so on first load).
