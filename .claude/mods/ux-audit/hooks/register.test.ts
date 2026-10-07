import { expect, test } from 'claude-code/testing'

import { SECTIONS, boardRows, lineOf } from './register'

const SAVED = {
  clients: { audited: '2026-10-05T10:00:00+08:00', grade: 'B', open: 3, top: [] },
  work: { audited: '2026-10-07T10:00:00+08:00', ux: 'A', ui: 'B', grade: 'B', open: 1, top: [] },
}
const CHANGED = {
  clients: '2026-10-06T09:00:00+08:00',
  work: '2026-10-06T09:00:00+08:00',
}

test('a section is current only when audited after its scripts last changed', () => {
  const rows = boardRows(SAVED, CHANGED)
  expect(rows).toHaveLength(SECTIONS.length)
  const by = Object.fromEntries(rows.map(r => [r.key, r]))
  expect(by.clients?.state).toBe('changed')
  expect(by.work?.state).toBe('current')
  expect(by.overview?.state).toBe('never')
  expect(lineOf(by.clients!)).toBe('Grade B · 3 open · 2026-10-05 · changed since')
  expect(lineOf(by.work!)).toBe('UX A · UI B · 1 open · 2026-10-07')
  expect(lineOf(by.overview!)).toBe('Not audited')
})

test('/ux-board reads the results and git, and Audit sends the skill', async ($, on) => {
  on('fs.read', async () => ({ value: JSON.stringify(SAVED) }))
  on('ui.status', async () => ({ value: undefined }))
  on('ui.open', async () => ({ value: { isPlaced: true as const } }))
  on('process.run', async (_$, e) => {
    const files = e.argv.slice(e.argv.indexOf('--') + 1)
    const key = SECTIONS.find(s => s.files.join() === files.join())?.key
    const at = key === 'clients' || key === 'work' ? CHANGED[key] : ''
    return { value: { exitCode: 0, stdout: at + '\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  const sent: string[] = []
  on('command.run', { command: 'ux-audit' }, async (_$, e) => {
    sent.push('/' + e.command + ' ' + e.args)
    return { text: '' }
  })

  const out = await $.command.run({
    command: 'ux-board',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 120 },
  })
  expect(out).toMatchObject({ text: (SECTIONS.length - 1) + ' of ' + SECTIONS.length + ' sections to check.' })

  for (const surface of ['terminal', 'desktop'] as const) {
    sent.length = 0
    const ui = await $.ui.mount({
      plugin: 'ux-audit',
      surface,
      component: 'Pane',
      requestId: 'ux-audit',
      props: { title: 'UX audit', isFocused: true, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
    })
    expect(await ui.findAll({ type: 'Button', text: /^Audit$/ })).toHaveLength(SECTIONS.length)
    await ui.press({ key: 'audit-clients' })
    expect(sent).toEqual(['/ux-audit clients'])
    await ui.press({ key: 'due' })
    expect(sent[1]?.split(' ')[0]).toBe('/ux-audit')
    expect(sent[1]?.split(' ')[1]?.split(',')).toHaveLength(SECTIONS.length - 1)
  }
})
