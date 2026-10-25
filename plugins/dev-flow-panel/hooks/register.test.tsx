import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'dev-flow-panel',
  component: 'Pane',
  requestId: 'dev-flow',
  props: {
    title: 'dev-flow',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 24 },
    view: {},
  },
} as const

test('without an active task the pane offers Plan, Implement and QA impact', async ($, on) => {
  // Nothing sits beneath the plugin: each hook here stands for the engine.
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.status', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/p' }))
  on('clock.now', () => ({ value: 1 }))
  on('clock.every', () => ({ value: undefined }))
  on('fs.exists', () => ({ value: false }))

  await $.session.start({ cwd: '/p', surface: 'desktop', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /No active task/ })).toBeDefined()
    expect(await ui.findAll({ type: 'Button' })).toHaveLength(4)
    await ui.unmount()
  }
})

test('an active task shows its stage and Implement resumes that plan', async ($, on) => {
  const plan = '---\ntask: login fix\nstatus: human-review\nreview_round: 2\nmode: full\n---\n## Steps\n'
  const files: Record<string, string> = {
    '/p/.claude/flow/current': '/p/.claude/plans/t\n',
    '/p/.claude/plans/t/plan.md': plan,
  }
  const ran: string[] = []
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.status', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/p' }))
  on('clock.now', () => ({ value: 1 }))
  on('clock.every', () => ({ value: undefined }))
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => ({ value: files[e.path] ?? '' }))
  on('fs.stat', (_, e) => ({
    value: { kind: 'file', size: e.path.endsWith('needs-decision.md') ? 12 : 0, mtimeMs: 0, isLink: false },
  }))
  // The dev-flow skills are slash commands of another plugin; this hook stands for them.
  on('command.run', (_, e) => {
    ran.push(`/${e.command} ${e.args}`.trim())
    return { text: 'ran' }
  })

  await $.session.start({ cwd: '/p', surface: 'desktop', isInteractive: true })

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Your review/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /login fix/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /needs-decision/ })).toBeDefined()
  await ui.press({ key: 'implement' })
  expect(ran).toEqual(['/dev-flow:dev-implement /p/.claude/plans/t/plan.md'])
  await ui.unmount()
})
