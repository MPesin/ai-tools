import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'dev-flow-panel',
  component: 'Pane',
  requestId: 'dev-flow',
  props: {
    title: 'dev-flow',
    isFocused: false,
    bodyColumns: 38,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 24 },
    view: {},
  },
} as const

const BAND = {
  plugin: 'dev-flow-panel',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 12,
    bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 11 },
    view: {},
  },
} as const

const PLAN = '---\ntask: login fix\nstatus: human-review\nreview_round: 2\nmode: full\n---\n## Steps\n'
const FILES: Record<string, string> = {
  '/p/.claude/flow/current': '/p/.claude/plans/t\n',
  '/p/.claude/plans/t/plan.md': PLAN,
}

test('without an active task the pane offers Plan, Implement and QA impact, and the band yields', async ($, on) => {
  // Nothing sits beneath the plugin: each hook here stands for the engine.
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.status', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/p' }))
  on('clock.now', () => ({ value: 1 }))
  on('clock.every', () => ({ value: undefined }))
  on('fs.exists', () => ({ value: false }))
  // The engine's own band, drawn when the plugin has nothing to show.
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  await $.session.start({ cwd: '/p', surface: 'desktop', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /No active task/ })).toBeDefined()
    expect(await ui.findAll({ type: 'Button' })).toHaveLength(4)
    await ui.unmount()
  }

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Text' }))?.text).toBe('engine')
  expect(await band.findAll({ type: 'Button' })).toHaveLength(0)
  await band.unmount()
})

test('an active task shows its stage in the pane and Implement resumes that plan', async ($, on) => {
  const ran: string[] = []
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.status', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/p' }))
  on('clock.now', () => ({ value: 1 }))
  on('clock.every', () => ({ value: undefined }))
  on('fs.exists', (_, e) => ({ value: e.path in FILES }))
  on('fs.read', (_, e) => ({ value: FILES[e.path] ?? '' }))
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
  // The steps behind the current one are ticked, the ones ahead are hollow.
  expect(await ui.find({ type: 'Text', text: /✓ Planning/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /○ Done/ })).toBeDefined()
  await ui.press({ key: 'implement' })
  expect(ran).toEqual(['/dev-flow:dev-implement /p/.claude/plans/t/plan.md'])
  await ui.unmount()
})

test('an active task draws the band above the prompt, with the buttons and a way to the pane', async ($, on) => {
  const opened: unknown[] = []
  const ran: string[] = []
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
  on('ui.open', (_, e) => {
    opened.push(e)
    return { value: { isPlaced: true } }
  })
  on('ui.status', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/p' }))
  on('clock.now', () => ({ value: 1 }))
  on('clock.every', () => ({ value: undefined }))
  on('fs.exists', (_, e) => ({ value: e.path in FILES }))
  on('fs.read', (_, e) => ({ value: FILES[e.path] ?? '' }))
  on('fs.stat', (_, e) => ({
    value: { kind: 'file', size: e.path.endsWith('needs-decision.md') ? 12 : 0, mtimeMs: 0, isLink: false },
  }))
  on('command.run', (_, e) => {
    ran.push(`/${e.command} ${e.args}`.trim())
    return { text: 'ran' }
  })

  await $.session.start({ cwd: '/p', surface: 'desktop', isInteractive: true })
  // Nothing opens by itself any more: the band carries the stage.
  expect(opened).toHaveLength(0)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /Your review/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /login fix/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /needs decision/ })).toBeDefined()
  expect(await band.findAll({ type: 'Button' })).toHaveLength(5)

  await band.press({ key: 'qa' })
  expect(ran).toEqual(['/dev-flow:dev-qa-impact /p/.claude/plans/t'])

  // `panel` opens the pane narrow in the dock and sized to its rows inline.
  await band.press({ key: 'panel' })
  expect(opened).toHaveLength(1)
  expect(opened[0]).toMatchObject({ id: 'dev-flow', columns: 40 })
  expect(typeof (opened[0] as { rows?: unknown }).rows).toBe('number')
  await band.unmount()
})
