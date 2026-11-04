// The state contract of dev-flow-panel: what the pane draws, read from the
// dev-flow task folder (<project>/.claude/flow/current|planning -> plan.md) of
// the task that belongs to this session (the pointer's `session:` line).

export type FlowPointer = 'none' | 'current' | 'planning'

/** How much of the band is drawn: `auto` is two rows while a task is active
 *  and nothing otherwise; `compact` is the same two rows, task or not (what the
 *  band's `less` folds to, so the band does not vanish under the click); `full`
 *  adds the stage list, flags and hint, task or not. */
export type PanelView = 'auto' | 'compact' | 'full'

/** The flow skill this session started last: dev-flow's dev-plan (`plan`) or
 *  dev-debug's (`debug`), seen as its prompt expands or its button is pressed.
 *  Both write the planning pointer before plan.md, so until plan.md says, this
 *  is what tells a bug from a feature. */
export type FlowStart = 'none' | 'plan' | 'debug'

export type FlowState = {
  pointer: FlowPointer
  taskFolder?: string
  planPath?: string
  task?: string
  /** plan.md frontmatter `status`, or `none` without an active task */
  status: string
  /** plan.md frontmatter `source`; `dev-debug` marks a bug task with its own stage list.
   *  Before plan.md is written, and without a task, `dev-debug` when this session last
   *  started dev-debug (FlowStart), so the band shows the bug's stages from the start. */
  source?: string
  /** diagnosis.md exists and is not empty: the debugger has written and the diagnosis gate waits */
  diagnosed: boolean
  mode?: string
  reviewRound?: number
  base?: string
  needsDecision: boolean
  violations: boolean
  /** a task of another Claude Code session on this checkout, as `<task> · <stage> · another session`;
   *  never drawn as this band's task, only noted when this session has none */
  elsewhere?: string
  checkedAt: number
}

declare module 'claude-code' {
  interface PluginState {
    'dev-flow-panel': { flow: Shaped<FlowState>; view: PanelView; started: FlowStart }
  }
}
