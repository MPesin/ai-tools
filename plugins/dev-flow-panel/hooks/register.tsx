// dev-flow-panel: a band above the prompt for the dev-flow plugin. Two rows
// while a task is active (the stage, the task, a track, the skill buttons);
// `/dev-flow-panel` or the band's `more` adds the stage list, the flags and
// the hint. No pane: a docked pane runs the full height of the terminal, and
// the band takes only the rows it draws. The stage comes from the same files
// the dev-flow hooks read: <project>/.claude/flow/current|planning points at
// the task folder, plan.md's frontmatter holds status/mode/round.
import { atom, read, update } from 'claude-code'
import type { Color, Elements, EngineInterface, Register } from 'claude-code'

import type { FlowState, PanelView } from '../types'

const COMMAND = 'dev-flow-panel'
const POLL_MS = 4000

const EMPTY: FlowState = { pointer: 'none', status: 'none', needsDecision: false, violations: false, checkedAt: 0 }
// Bump the tag when FlowState's fields change: a value an earlier version stored
// outlives a reload and is then read as EMPTY instead of as the old shape.
const flow = atom({ plugin: 'dev-flow-panel', key: 'flow' } as const, EMPTY, { shape: 'flow-1' })
const view = atom({ plugin: 'dev-flow-panel', key: 'view' } as const, 'auto' as PanelView)

type Stage = { status: string; label: string; color: Color; hint: string }

// Theme keys rather than raw colours, so the pane follows the user's theme.
const STAGES: readonly Stage[] = [
  { status: 'draft', label: 'Planning', color: 'subtle', hint: 'The plan is being written; answer the critique and approve it in chat. Implement is off until then.' },
  { status: 'approved', label: 'Approved', color: 'suggestion', hint: 'Plan approved. Implement starts the flow.' },
  { status: 'implementing', label: 'Implementing', color: 'claude', hint: 'Implementer subagents are working through the plan.' },
  { status: 'reviewing', label: 'Claude review', color: 'permission', hint: 'Reviewer and fixer are iterating; the loop ends on a review.' },
  { status: 'human-review', label: 'Your review', color: 'warning', hint: 'Waiting for you: review the diff, commit, open the PR, then continue.' },
  { status: 'qa-impact', label: 'QA impact', color: 'ide', hint: 'Writing the QA impact note from the template.' },
  { status: 'done', label: 'Done', color: 'success', hint: 'Finished: plan, reviews and the QA note are in the task folder.' },
]
const BLOCKED: Stage = { status: 'blocked', label: 'Blocked', color: 'error', hint: 'Stopped: open findings or a blocked step need your decision.' }
const NONE: Stage = { status: 'none', label: 'No active task', color: 'inactive', hint: 'Plan a task, or Implement an approved plan.' }

const stageOf = (status: string): Stage =>
  status === 'blocked' ? BLOCKED
  : status === 'none' ? NONE
  : STAGES.find(s => s.status === status) ?? { status, label: status, color: 'text', hint: '' }

const sepOf = (path: string) => (path.includes('\\') ? '\\' : '/')
const join = (dir: string, name: string) => `${dir.replace(/[\\/]+$/, '')}${sepOf(dir)}${name}`

function frontmatter(text: string): Record<string, string> {
  const out: Record<string, string> = {}
  const block = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text)
  if (!block) return out
  for (const line of (block[1] ?? '').split(/\r?\n/)) {
    const kv = /^([A-Za-z_]+):[ \t]*(.*)$/.exec(line)
    if (kv) out[kv[1] ?? ''] = (kv[2] ?? '').trim()
  }
  return out
}

const nonEmpty = async ($: EngineInterface, path: string) => {
  const stat = await $.fs.stat(path).catch(() => undefined)
  return stat !== undefined && stat.size > 0
}

const readText = async ($: EngineInterface, path: string) => {
  const text = await $.fs.read(path).catch(() => '')
  return typeof text === 'string' ? text : ''
}

// The project root and its parents, nearest first: the dev-flow hooks walk up
// from the working directory to the first .claude/flow pointer, so the pointer
// may sit at the git root above where the session started.
const lineage = (root: string) => {
  const dirs = [root]
  let dir = root.replace(/[\\/]+$/, '')
  for (let i = 0; i < 8; i += 1) {
    const cut = Math.max(dir.lastIndexOf('/'), dir.lastIndexOf('\\'))
    if (cut <= 0) break
    dir = dir.slice(0, cut)
    dirs.push(dir)
  }
  return dirs
}

// The first pointer file found, nearest directory first.
async function findPointer($: EngineInterface, root: string) {
  for (const dir of lineage(root)) {
    const flowDir = join(join(dir, '.claude'), 'flow')
    for (const pointer of ['current', 'planning'] as const) {
      const pointerPath = join(flowDir, pointer)
      if (await $.fs.exists(pointerPath)) return { pointer, pointerPath }
    }
  }
  return undefined
}

async function readFlow($: EngineInterface): Promise<FlowState> {
  const checkedAt = await $.clock.now()
  const found = await findPointer($, await $.session.root())
  if (found) {
    const { pointer, pointerPath } = found
    const taskFolder = (await readText($, pointerPath)).split(/\r?\n/)[0]?.trim() ?? ''
    if (!taskFolder) return { ...EMPTY, checkedAt }
    const planPath = join(taskFolder, 'plan.md')
    const fm = frontmatter(await readText($, planPath))
    const round = Number(fm.review_round)
    return {
      pointer,
      taskFolder,
      planPath,
      task: fm.task || undefined,
      status: fm.status || (pointer === 'planning' ? 'draft' : 'unknown'),
      mode: fm.mode || undefined,
      base: fm.base || undefined,
      reviewRound: Number.isFinite(round) && round > 0 ? round : undefined,
      needsDecision: await nonEmpty($, join(taskFolder, 'needs-decision.md')),
      violations: await nonEmpty($, join(taskFolder, 'violations.md')),
      checkedAt,
    }
  }
  return { ...EMPTY, checkedAt }
}

const statusLine = (f: FlowState) =>
  f.pointer === 'none'
    ? undefined
    : [
        `dev-flow: ${stageOf(f.status).label}`,
        f.reviewRound ? `round ${f.reviewRound}` : '',
        f.task ?? '',
        f.needsDecision ? 'needs decision' : '',
        f.violations ? 'violations' : '',
      ].filter(Boolean).join(' · ')

const sameFlow = (a: FlowState, b: FlowState) =>
  JSON.stringify({ ...a, checkedAt: 0 }) === JSON.stringify({ ...b, checkedAt: 0 })

async function refresh($: EngineInterface) {
  const next = await readFlow($)
  const prev = await read($, flow)
  if (sameFlow(prev, next)) return
  // Only a real change is written and drawn, so the band moves with the
  // stage, not with every poll. The invalidate covers a band that last had
  // nothing to draw: the engine keeps that answer until asked again.
  await update($, flow, () => next)
  $.ui.status(statusLine(next))
  $.ui.invalidate('ui.render')
}

const metaOf = (f: FlowState) =>
  [f.reviewRound ? `round ${f.reviewRound}` : '', f.mode ?? '', f.base ? `base ${f.base}` : ''].filter(Boolean).join(' · ')

// What the task is called: plan.md's `task`, else the task folder's name.
const titleOf = (f: FlowState) =>
  f.task ?? (f.taskFolder ? f.taskFolder.replace(/[\\/]+$/, '').split(/[\\/]/).pop() ?? '' : '')

const IN_PROGRESS = ['implementing', 'reviewing', 'qa-impact', 'blocked']

// Implement waits for an approved plan. While the planning pointer exists, or
// plan.md is still a draft, the button is drawn dim and a press says why instead
// of running the skill, which would only refuse the unapproved plan (and the
// dev-flow guard refuses to spawn an implementer at that stage anyway).
const implementBlocked = (f: FlowState) => f.pointer === 'planning' || f.status === 'draft'
const NOT_APPROVED = 'Implement needs an approved plan: answer the critique and approve it in chat first.'

type Controls = Pick<Elements['terminal'], 'Box' | 'Text' | 'Button'>

// A skill is a slash command: $.command.run queues `/command args` as if the
// person typed it (a prompt beginning with / is refused by $.prompt.submit).
const starter = ($: EngineInterface) => (command: string, args?: string) => () => {
  $.command.run(args ? { command, args } : { command }).catch((err: unknown) => {
    $.ui.toast(`/${command} did not run (is the dev-flow plugin installed?): ${String(err)}`)
  })
}

// The three skill buttons, the suggested next step drawn as the primary one.
const skillButtons = ($: EngineInterface, { Button }: Controls, f: FlowState) => {
  const start = starter($)
  const inProgress = IN_PROGRESS.includes(f.status)
  const primary = (yes: boolean) => (yes ? { variant: 'primary' as const } : {})
  return [
    <Button key="plan" hotkey="p" {...primary(f.pointer === 'none')} onPress={start('dev-flow:dev-plan')}>
      Plan
    </Button>,
    implementBlocked(f) ? (
      <Button key="implement" hotkey="i" dimColor onPress={() => { $.ui.toast(NOT_APPROVED) }}>
        Implement
      </Button>
    ) : (
      <Button key="implement" hotkey="i" {...primary(f.status === 'approved' || inProgress)} onPress={start('dev-flow:dev-implement', f.planPath)}>
        {inProgress ? 'Resume' : 'Implement'}
      </Button>
    ),
    <Button key="qa" hotkey="q" {...primary(f.status === 'human-review' || f.status === 'done')} onPress={start('dev-flow:dev-qa-impact', f.taskFolder)}>
      QA impact
    </Button>,
  ]
}
// Cells the three buttons take as the terminal draws them (`[ label ]`), with
// the gaps: what the compact band's hint has to fit beside.
const skillButtonsWidth = (f: FlowState) => 8 + 1 + (IN_PROGRESS.includes(f.status) ? 10 : 13) + 1 + 13

// The stage as a chip: the label on a block of the stage's colour.
const chip = ({ Text }: Controls, stage: Stage) => (
  <Text bold inverse color={stage.color}>{' '}{stage.label}{' '}</Text>
)

// The seven stages as a track, each dot in its stage's colour: the steps
// behind filled, the current one ringed and bold, the ones ahead hollow.
const track = ({ Text }: Controls, f: FlowState) => {
  const at = STAGES.findIndex(s => s.status === f.status)
  return (
    <Text>
      {STAGES.map((s, i) => (
        <Text>
          {i > 0 ? <Text dimColor>{'─'}</Text> : null}
          {i === at ? <Text bold color={s.color}>{'◉'}</Text> : i < at ? <Text color={s.color}>{'●'}</Text> : <Text color={s.color}>{'○'}</Text>}
        </Text>
      ))}
    </Text>
  )
}

const toggleView = async ($: EngineInterface) => {
  const now = await update($, view, v => (v === 'full' ? 'auto' : 'full'))
  $.ui.invalidate('ui.render')
  return now
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: COMMAND,
      description: 'Show or fold the dev-flow band above the prompt: the stage list, flags and buttons for plan, implement and QA impact',
    })
    const first = await readFlow($)
    await update($, flow, () => first)
    $.ui.status(statusLine(first))
    $.clock.every(POLL_MS, () => refresh($))

    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    await refresh($)
    const now = await toggleView($)

    return { text: now === 'full' ? 'dev-flow band expanded above the prompt.' : 'dev-flow band folded to two rows (drawn while a task is active).' }
  })

  // The stage changes when the skills write plan.md or move the pointer files;
  // refresh right after such a tool call instead of waiting for the next poll.
  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    const path = 'file_path' in e && typeof e.file_path === 'string' ? e.file_path : ''
    const command = 'command' in e && typeof e.command === 'string' ? e.command : ''
    if (/plan\.md$|[\\/]\.claude[\\/]flow[\\/]/.test(path) || /\.claude[\\/]flow|plan\.md|needs-decision|violations/.test(command)) {
      void refresh($)
    }

    return ran
  })

  // The band. Compact, two rows:
  //   ▎ Your review   ⚠ needs decision  login fix · round 2 · full       ●─●─●─●─◉─○─○
  //   ▎ [ Plan ] [ Implement ] [ QA impact ]   ↻ refresh   more ▾   Waiting for you: review…
  // Full, the stage list, the hint and the flags between those two rows:
  //   ▎ ✓ Planning  ✓ Approved  ✓ Implementing  ✓ Claude review  ◉ Your review  ○ QA impact  ○ Done
  //   ▎   Waiting for you: review the diff, commit, open the PR, then continue.
  //   ▎ ⚠ needs-decision.md  findings wait for your decision
  // An accent bar in the stage's colour runs down every row; the track at the
  // right end of the first row is what gives way first when the column is narrow.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const f = await read($, flow)
    const full = (await read($, view)) === 'full'
    if (e.props.hasSurvey || (!full && f.pointer === 'none')) return next(e)

    const els = $.ui.resolve(e)
    const { Box, Text, Button } = els
    const stage = stageOf(f.status)
    const at = STAGES.findIndex(s => s.status === f.status)
    const meta = metaOf(f)
    const bar = <Text color={stage.color}>{'▎'}</Text>
    const hintRoom = e.props.bodyColumns - (2 + skillButtonsWidth(f) + 3 + 9 + 3 + 6 + 3)

    return (
      <Box flexDirection="column" width={e.props.bodyColumns}>
        <Box justifyContent="space-between" columnGap={2}>
          <Text wrap="truncate-end">
            {bar}
            {chip(els, stage)}
            {f.needsDecision ? <Text color="warning">{'  ⚠ needs decision'}</Text> : null}
            {f.violations ? <Text color="error">{'  ✗ violations'}</Text> : null}
            {titleOf(f) ? <Text bold color="text">{'  '}{titleOf(f)}</Text> : null}
            {meta ? <Text dimColor>{' · '}{meta}</Text> : null}
            {f.pointer === 'none' ? <Text dimColor>{'  no pointer in .claude/flow'}</Text> : null}
          </Text>
          <Box flexShrink={0}>{track(els, f)}</Box>
        </Box>
        {full ? (
          <Box columnGap={1}>
            {bar}
            <Box flexWrap="wrap" columnGap={2}>
              {STAGES.map((s, i) =>
                i === at ? (
                  <Text bold color={s.color}>{'◉'} {s.label}</Text>
                ) : i < at ? (
                  <Text><Text color="success">{'✓'}</Text><Text color={s.color}> {s.label}</Text></Text>
                ) : (
                  <Text><Text color={s.color}>{'○'}</Text><Text dimColor> {s.label}</Text></Text>
                ),
              )}
            </Box>
          </Box>
        ) : null}
        {full ? (
          <Box columnGap={1}>
            {bar}
            <Text dimColor italic wrap="truncate-end">{'  '}{stage.hint}</Text>
          </Box>
        ) : null}
        {full && f.needsDecision ? (
          <Box columnGap={1}>
            {bar}
            <Text wrap="truncate-end"><Text color="warning">{'⚠ needs-decision.md'}</Text><Text dimColor>{'  findings wait for your decision'}</Text></Text>
          </Box>
        ) : null}
        {full && f.violations ? (
          <Box columnGap={1}>
            {bar}
            <Text wrap="truncate-end"><Text color="error">{'✗ violations.md'}</Text><Text dimColor>{'  files changed outside an allowance'}</Text></Text>
          </Box>
        ) : null}
        <Box columnGap={2}>
          <Box flexShrink={0} columnGap={3}>
            <Box columnGap={1}>
              {bar}
              {skillButtons($, els, f)}
            </Box>
            <Button key="refresh" plain dimColor onPress={() => { void refresh($) }}>
              ↻ refresh
            </Button>
            <Button key="view" plain dimColor onPress={() => toggleView($)}>
              {full ? 'less ▴' : 'more ▾'}
            </Button>
          </Box>
          {!full && hintRoom >= 24 ? (
            <Box flexShrink={1}>
              <Text dimColor italic wrap="truncate-end">{stage.hint}</Text>
            </Box>
          ) : null}
        </Box>
      </Box>
    )
  })
}
