// The state contract of dev-flow-panel: what the pane draws, read from the
// dev-flow task folder (<project>/.claude/flow/current|planning -> plan.md).

export type FlowPointer = 'none' | 'current' | 'planning'

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
    'dev-flow-panel': { flow: Shaped<FlowState> }
  }
}
