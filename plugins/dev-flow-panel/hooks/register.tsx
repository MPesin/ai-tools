// dev-flow-panel: a pane beside the chat with buttons that start the dev-flow
// skills and a colour-coded view of the current stage. The stage comes from the
// same files the dev-flow hooks read: <project>/.claude/flow/current|planning
// points at the task folder, plan.md's frontmatter holds status/mode/round.
import { atom, read, update } from 'claude-code'
import type { Color, EngineInterface, Register } from 'claude-code'

import type { FlowState } from '../types'

const PANE = 'dev-flow'
const COMMAND = 'dev-flow-panel'
const POLL_MS = 4000

const EMPTY: FlowState = { pointer: 'none', status: 'none', needsDecision: false, violations: false, checkedAt: 0 }
// Bump the tag when FlowState's fields change: a value an earlier version stored
// outlives a reload and is then read as EMPTY instead of as the old shape.
const flow = atom({ plugin: 'dev-flow-panel', key: 'flow' } as const, EMPTY, { shape: 'flow-1' })

type Stage = { status: string; label: string; color: Color; hint: string }

// Theme keys rather than raw colours, so the pane follows the user's theme.
const STAGES: readonly Stage[] = [
  { status: 'draft', label: 'Planning', color: 'subtle', hint: 'The plan is being written; approve it in chat when it is ready.' },
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

async function readFlow($: EngineInterface): Promise<FlowState> {
  const checkedAt = await $.clock.now()
  const root = await $.session.root()
  const flowDir = join(join(root, '.claude'), 'flow')
  for (const pointer of ['current', 'planning'] as const) {
    const pointerPath = join(flowDir, pointer)
    if (!(await $.fs.exists(pointerPath))) continue
    const taskFolder = (await readText($, pointerPath)).split(/\r?\n/)[0]?.trim() ?? ''
    if (!taskFolder) continue
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
  // Only a real change is written, so the pane is redrawn when the stage moves,
  // not on every poll.
  await update($, flow, prev => (sameFlow(prev, next) ? prev : next))
  $.ui.status(statusLine(next))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: COMMAND,
      description: 'Open the dev-flow panel: buttons for plan, implement and QA impact, and the current stage',
    })
    const first = await readFlow($)
    await update($, flow, () => first)
    $.ui.status(statusLine(first))
    if (first.pointer !== 'none') void $.ui.open({ id: PANE, title: 'dev-flow' })
    $.clock.every(POLL_MS, () => refresh($))

    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    await refresh($)
    const opened = await $.ui.open({ id: PANE, title: 'dev-flow' })

    return { text: opened.isPlaced ? 'dev-flow panel opened.' : `dev-flow panel waits for a wider window (${opened.reason}).` }
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

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const f = await read($, flow)
    const stage = stageOf(f.status)
    const inProgress = ['implementing', 'reviewing', 'qa-impact', 'blocked'].includes(f.status)
    // A skill is a slash command: $.command.run queues `/command args` as if the
    // person typed it (a prompt beginning with / is refused by $.prompt.submit).
    const start = (command: string, args?: string) => () => {
      $.command.run(args ? { command, args } : { command }).catch((err: unknown) => {
        $.ui.toast(`/${command} did not run (is the dev-flow plugin installed?): ${String(err)}`)
      })
    }
    const primary = (yes: boolean) => (yes ? { variant: 'primary' as const } : {})
    const where = f.task ?? (f.pointer === 'none' ? 'no pointer in .claude/flow' : f.taskFolder ?? '')

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="column">
          <Text bold color={stage.color}>
            {'●'} {stage.label}
            {f.reviewRound ? <Text dimColor>{'  '}round {f.reviewRound}</Text> : null}
            {f.mode ? <Text dimColor>{'  '}{f.mode}</Text> : null}
          </Text>
          <Text dimColor>{where}</Text>
          {f.needsDecision ? <Text color="warning">needs-decision.md: findings wait for your decision</Text> : null}
          {f.violations ? <Text color="error">violations.md: files changed outside an agent's allowance</Text> : null}
        </Box>
        <Box flexDirection="column">
          {STAGES.map(s =>
            s.status === f.status ? (
              <Text bold color={s.color}>{'▶'} {s.label}</Text>
            ) : (
              <Text dimColor>{'  '}{s.label}</Text>
            ),
          )}
        </Box>
        <Text dimColor>{stage.hint}</Text>
        <Box gap={1}>
          <Button key="plan" hotkey="p" {...primary(f.pointer === 'none')} onPress={start('dev-flow:dev-plan')}>
            Plan
          </Button>
          <Button key="implement" hotkey="i" {...primary(f.status === 'approved' || inProgress)} onPress={start('dev-flow:dev-implement', f.planPath)}>
            {inProgress ? 'Resume' : 'Implement'}
          </Button>
          <Button key="qa" hotkey="q" {...primary(f.status === 'human-review' || f.status === 'done')} onPress={start('dev-flow:dev-qa-impact', f.taskFolder)}>
            QA impact
          </Button>
          <Button key="refresh" hotkey="r" plain dimColor onPress={() => { void refresh($) }}>
            refresh
          </Button>
        </Box>
      </Box>
    )
  })
}
