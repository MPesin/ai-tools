// The state contract of dev-flow-panel: what the pane draws, read from the
// dev-flow task folder (<project>/.claude/flow/current|planning -> plan.md).

export type FlowPointer = 'none' | 'current' | 'planning'

/** How much of the band is drawn: `auto` is two rows while a task is active
 *  and nothing otherwise; `full` adds the stage list, flags and hint, task or not. */
export type PanelView = 'auto' | 'full'

export type FlowState = {
  pointer: FlowPointer
  taskFolder?: string
  planPath?: string
  task?: string
  /** plan.md frontmatter `status`, or `none` without an active task */
  status: string
  mode?: string
  reviewRound?: number
  base?: string
  needsDecision: boolean
  violations: boolean
  checkedAt: number
}

declare module 'claude-code' {
  interface PluginState {
    'dev-flow-panel': { flow: Shaped<FlowState>; view: PanelView }
  }
}
