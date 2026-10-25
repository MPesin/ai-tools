import { expect, mock, test } from 'claude-code/testing'

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

test('without an active task the band yields to the engine until /dev-flow-panel expands it', async ($, on) => {
  // Nothing sits beneath the plugin: each hook here stands for the engine.
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
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

  const quiet = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await quiet.find({ type: 'Text' }))?.text).toBe('engine')
  expect(await quiet.findAll({ type: 'Button' })).toHaveLength(0)
  await quiet.unmount()

  const ran = await $.command.run({ command: 'dev-flow-panel', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } })
  expect(ran.text).toMatch(/expanded/)

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    expect(await band.find({ type: 'Text', text: /No active task/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /○ Planning/ })).toBeDefined()
    expect(await band.findAll({ type: 'Button' })).toHaveLength(6)
    await band.unmount()
  }
})

test('an active task draws two rows, and the buttons run the skills on that task', async ($, on) => {
  const ran: string[] = []
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
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

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /Your review/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /login fix/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /needs decision/ })).toBeDefined()
  // Compact: the stage list is not drawn.
  expect(await band.find({ type: 'Text', text: /✓ Planning/ })).toBeUndefined()
  await band.press({ key: 'implement' })
  expect(ran).toEqual(['/dev-flow:dev-implement /p/.claude/plans/t/plan.md'])
  await band.press({ key: 'qa' })
  expect(ran[1]).toBe('/dev-flow:dev-qa-impact /p/.claude/plans/t')
  await band.unmount()
})

test('more expands the band to the stage list, the hint and the flags; less folds it', async ($, on) => {
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
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

  await $.session.start({ cwd: '/p', surface: 'desktop', isInteractive: true })

  // A press writes the view; the surface redraws its readers after, so each
  // state is read from a fresh drawing.
  const compact = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await compact.press({ key: 'view' })
  await compact.unmount()

  const full = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await full.find({ type: 'Text', text: /✓ Planning/ })).toBeDefined()
  expect(await full.find({ type: 'Text', text: /◉ Your review/ })).toBeDefined()
  expect(await full.find({ type: 'Text', text: /○ Done/ })).toBeDefined()
  expect(await full.find({ type: 'Text', text: /needs-decision\.md/ })).toBeDefined()
  expect(await full.find({ type: 'Text', text: /Waiting for you/ })).toBeDefined()
  expect((await full.find({ type: 'Button', key: 'view' }))?.text).toMatch(/less/)
  await full.press({ key: 'view' })
  await full.unmount()

  const folded = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await folded.find({ type: 'Text', text: /✓ Planning/ })).toBeUndefined()
  expect((await folded.find({ type: 'Button', key: 'view' }))?.text).toMatch(/more/)
  await folded.unmount()
})

test('while the plan is a draft, Implement is dim and a press explains instead of running the skill', async ($, on) => {
  const files: Record<string, string> = {
    '/p/.claude/flow/planning': '/p/.claude/plans/t\n',
    '/p/.claude/plans/t/plan.md': '---\ntask: login fix\nstatus: draft\n---\n',
  }
  const ran: string[] = []
  const toasts: string[] = []
  const clock = mock.clock(on)
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.toast', (_, e) => { toasts.push(e.text); return { value: undefined } })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/p' }))
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => ({ value: files[e.path] ?? '' }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 0, mtimeMs: 0, isLink: false } }))
  on('command.run', (_, e) => {
    ran.push(`/${e.command} ${e.args}`.trim())
    return { text: 'ran' }
  })

  await $.session.start({ cwd: '/p', surface: 'desktop', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    expect(await band.find({ type: 'Text', text: /Planning/ })).toBeDefined()
    await band.press({ key: 'implement' })
    expect(ran).toEqual([])
    expect(toasts.at(-1)).toMatch(/approve/)
    await band.unmount()
  }

  // Approved in chat: the planning pointer gives way to current and the button runs the skill.
  delete files['/p/.claude/flow/planning']
  files['/p/.claude/flow/current'] = '/p/.claude/plans/t\n'
  files['/p/.claude/plans/t/plan.md'] = '---\ntask: login fix\nstatus: approved\nmode: full\n---\n'
  await clock.advance(4000)

  const approved = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await approved.press({ key: 'implement' })
  expect(ran).toEqual(['/dev-flow:dev-implement /p/.claude/plans/t/plan.md'])
  await approved.unmount()
})

test('while the debugger works, the band shows Diagnosing in the first slot, Debug resumes the gate and Implement explains', async ($, on) => {
  const files: Record<string, string> = {
    '/p/.claude/flow/planning': '/p/.claude/plans/b\n',
    '/p/.claude/plans/b/plan.md': '---\ntask: crash on save\nsource: dev-debug\nstatus: diagnosing\n---\n',
  }
  const ran: string[] = []
  const toasts: string[] = []
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.toast', (_, e) => { toasts.push(e.text); return { value: undefined } })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/p' }))
  on('clock.now', () => ({ value: 1 }))
  on('clock.every', () => ({ value: undefined }))
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => ({ value: files[e.path] ?? '' }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 0, mtimeMs: 0, isLink: false } }))
  on('command.run', (_, e) => {
    ran.push(`/${e.command} ${e.args}`.trim())
    return { text: 'ran' }
  })

  await $.session.start({ cwd: '/p', surface: 'desktop', isInteractive: true })

  const compact = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await compact.find({ type: 'Text', text: /Diagnosing/ })).toBeDefined()
  expect(await compact.find({ type: 'Text', text: /crash on save/ })).toBeDefined()
  await compact.press({ key: 'implement' })
  expect(ran).toEqual([])
  expect(toasts.at(-1)).toMatch(/diagnosis/)
  await compact.press({ key: 'debug' })
  expect(ran).toEqual(['/dev-flow:dev-debug /p/.claude/plans/b'])
  await compact.press({ key: 'view' })
  await compact.unmount()

  // Expanded: Diagnosing takes Planning's place in the list; the steps ahead are unchanged.
  const full = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await full.find({ type: 'Text', text: /◉ Diagnosing/ })).toBeDefined()
  expect(await full.find({ type: 'Text', text: /Planning/ })).toBeUndefined()
  expect(await full.find({ type: 'Text', text: /○ Approved/ })).toBeDefined()
  await full.press({ key: 'view' })
  await full.unmount()
})

test('the poll picks up a stage change in plan.md and a pointer at the git root above the session', async ($, on) => {
  // The session starts in a subfolder; the pointer sits at the repository root.
  const files: Record<string, string> = {
    '/repo/.claude/flow/planning': '/repo/.claude/plans/t\n',
    '/repo/.claude/plans/t/plan.md': '---\ntask: login fix\nstatus: draft\n---\n',
  }
  let invalidated = 0
  const clock = mock.clock(on)
  on('command.register', () => ({ value: { command: 'dev-flow-panel' } }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.invalidate', () => { invalidated += 1; return { value: undefined } })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/repo/apps/web' }))
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => ({ value: files[e.path] ?? '' }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 0, mtimeMs: 0, isLink: false } }))

  await $.session.start({ cwd: '/repo/apps/web', surface: 'desktop', isInteractive: true })

  const planning = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await planning.find({ type: 'Text', text: /Planning/ })).toBeDefined()
  await planning.unmount()

  // The plan is approved and the planning pointer gives way to current.
  delete files['/repo/.claude/flow/planning']
  files['/repo/.claude/flow/current'] = '/repo/.claude/plans/t\n'
  files['/repo/.claude/plans/t/plan.md'] = '---\ntask: login fix\nstatus: approved\nmode: lite\n---\n'
  // One poll period passes; the refresh it runs settles with the advance.
  await clock.advance(4000)

  const approved = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await approved.find({ type: 'Text', text: /Approved/ })).toBeDefined()
  expect(await approved.find({ type: 'Text', text: /lite/ })).toBeDefined()
  expect(invalidated).toBeGreaterThan(0)
  await approved.unmount()
})
