/* One section's last audit, as the ux-audit skill writes it to
   tests/ux-audit/results.json. */
export type Saved = {
  audited: string
  commit?: string
  /* The two grades, A to E, and the lower of them. */
  ux?: string
  ui?: string
  grade?: string
  open?: number
  p1?: number
  p2?: number
  p3?: number
  top?: string[]
  report?: string
}

/* A row of the board: never audited, changed since its audit, or current. */
export type Row = {
  key: string
  name: string
  state: 'never' | 'changed' | 'current'
  ux?: string
  ui?: string
  grade?: string
  audited?: string
  open?: number
  report?: string
  top: string[]
}

declare module 'claude-code' {
  interface PluginState {
    'ux-audit': { rows: Row[] }
  }
}
