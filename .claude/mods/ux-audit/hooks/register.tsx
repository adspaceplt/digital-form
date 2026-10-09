import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Row, Saved } from '../types'

/* The board of the ADspace portal's sections for the ux-audit skill
   (.claude/skills/ux-audit/SKILL.md in the portal repo): each section's last
   UX and UI grades and open findings, read from the results file the skill writes, and
   whether the section's own scripts changed since that audit (git). A press
   on Audit runs the skill's command; nothing here audits or changes code
   itself. */

const PANE = 'ux-audit'
const RESULTS = 'tests/ux-audit/results.json'

/* The sections the skill knows, with the scripts that draw each. A section
   drawn by admin.js reads as changed whenever admin.js does: broad, but never
   silent. */
export const SECTIONS: readonly { key: string; name: string; files: readonly string[] }[] = [
  { key: 'overview', name: 'Overview', files: ['js/overview.js'] },
  { key: 'work', name: 'My Work', files: ['js/ops.js'] },
  { key: 'clients', name: 'Clients', files: ['js/crm.js', 'js/sales.js'] },
  { key: 'review', name: 'Content Review', files: ['js/admin.js', 'js/mockups.js'] },
  { key: 'scripts', name: 'Video Scripts', files: ['js/scripts.js', 'js/scriptpdf.js'] },
  { key: 'campaigns', name: 'Creator Campaigns', files: ['js/campaigns.js'] },
  { key: 'register', name: 'Documents', files: ['js/register.js', 'js/documents.js', 'js/letters.js'] },
  { key: 'reports', name: 'Reports', files: ['js/reports.js', 'js/smreport.js'] },
  { key: 'links', name: 'Short Links', files: ['js/admin.js'] },
  { key: 'services', name: 'Services', files: ['js/admin.js'] },
  { key: 'team', name: 'Team', files: ['js/team.js', 'js/perf.js', 'js/health.js'] },
  { key: 'handbook', name: 'Handbook', files: ['js/handbook.js'] },
  { key: 'mine', name: 'My HR', files: ['js/perf.js', 'js/health.js'] },
  { key: 'portal', name: 'Client portal', files: ['js/portal.js', 'client/index.html'] },
  { key: 'reviewpage', name: 'Content review page', files: ['js/review.js', 'js/decide.js', 'review/index.html'] },
  { key: 'scriptpage', name: 'Video scripts page', files: ['js/script.js', 'script/index.html'] },
  { key: 'selection', name: 'Creator selection', files: ['js/creators.js', 'creators/index.html'] },
  { key: 'creator', name: 'Creator page', files: ['js/creator.js', 'creator/index.html'] },
  { key: 'front', name: 'Front door', files: ['index.html'] },
]

const rows = atom({ plugin: 'ux-audit', key: 'rows' } as const, [] as Row[])

/* The board from the saved audits and each section's last change: a section
   is current only when it was audited after its scripts last changed. */
export function boardRows(saved: Record<string, Saved>, changedAt: Record<string, string>): Row[] {
  return SECTIONS.map(s => {
    const r = saved[s.key]
    const at = r ? Date.parse(r.audited) : NaN
    const ch = changedAt[s.key]
    const moved = ch ? Date.parse(ch) : NaN
    const state: Row['state'] = !r || !Number.isFinite(at) ? 'never'
      : Number.isFinite(moved) && moved > at ? 'changed' : 'current'
    return { key: s.key, name: s.name, state, ux: r?.ux, ui: r?.ui, grade: r?.grade, audited: r?.audited, open: r?.open, report: r?.report, top: r?.top ?? [] }
  })
}

/* What a row says after its name. */
export function lineOf(r: Row): string {
  if (r.state === 'never') return 'Not audited'
  const day = r.audited ? r.audited.slice(0, 10) : ''
  const open = typeof r.open === 'number' ? ' · ' + r.open + ' open' : ''
  /* An audit gives a UX and a UI grade; one from before gives a single grade. */
  const grades = r.ux || r.ui ? 'UX ' + (r.ux ?? '?') + ' · UI ' + (r.ui ?? '?') : 'Grade ' + (r.grade ?? '?')
  return grades + open + ' · ' + day + (r.state === 'changed' ? ' · changed since' : '')
}

/* Reads the results file and each section's last change, fills the board and
   sets the status line. */
async function load($: EngineInterface): Promise<Row[]> {
  let saved: Record<string, Saved> = {}
  try {
    saved = JSON.parse(String(await $.fs.read(RESULTS)))
  } catch {
    saved = {}
  }
  const changedAt: Record<string, string> = {}
  await Promise.all(SECTIONS.map(async s => {
    try {
      const out = await $.process.run(['git', 'log', '-1', '--format=%cI', '--', ...s.files])
      if (out.exitCode === 0 && out.stdout.trim()) changedAt[s.key] = out.stdout.trim()
    } catch {
      /* Not a git checkout, or git missing: the row keeps its saved state. */
    }
  }))
  const list = boardRows(saved, changedAt)
  await update($, rows, () => list)
  const due = list.filter(r => r.state !== 'current').length
  $.ui.status(due ? 'UX audit: ' + due + ' to check' : undefined)
  return list
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'ux-board',
      description: "Show the UI and UX audit board: each portal section's last grades, and which changed since",
    })
    void load($)
    return next(e)
  })

  on('command.run', { command: 'ux-board' }, async $ => {
    const list = await load($)
    await $.ui.open({ id: PANE, title: 'UX audit' })
    const due = list.filter(r => r.state !== 'current').length
    return { text: due ? due + ' of ' + list.length + ' sections to check.' : 'Every section is audited and current.' }
  })

  /* An audit ends in a turn that writes the results file: read the board
     again after every turn, so a finished audit shows at once. */
  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    void load($)
    return done
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const list = await read($, rows)
    const due = list.filter(r => r.state !== 'current')
    /* Runs the skill as if the person typed /ux-audit <keys>, once the
       session is idle; a project without the skill says so. */
    const audit = (keys: string) => () => {
      $.command.run({ command: 'ux-audit', args: keys }).catch(() => {
        void $.ui.toast('/ux-audit is not available in this project.')
      })
    }
    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" gap={1}>
          {due.length > 0 && (
            <Button key="due" variant="primary" onPress={audit(due.map(r => r.key).join(','))}>
              {'Audit ' + due.length + ' to check'}
            </Button>
          )}
          <Button key="refresh" onPress={() => { void load($) }}>Refresh</Button>
        </Box>
        <Box flexDirection="column">
          {list.map(r => (
            <Box key={'row-' + r.key} flexDirection="row" gap={1}>
              <Box width={22}><Text bold={r.state !== 'current'}>{r.name}</Text></Box>
              <Box flexGrow={1}><Text dimColor={r.state === 'current'} wrap="truncate">{lineOf(r)}</Text></Box>
              <Button key={'audit-' + r.key} plain dimColor onPress={audit(r.key)}>Audit</Button>
            </Box>
          ))}
        </Box>
      </Box>
    )
  })
}
