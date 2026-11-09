/*
 * creator-mail — sends the creator emails the database queued (2026-11-08,
 * 2026-11-08-creator-payment-details.sql): Details received and Details
 * approved to the creator, Details to review to the finance address.
 *
 *   POST { action: 'drain' }  from the database alone (`creator_mail_kick`,
 *                          pg_cron `creator-mail-drain`), carrying the wake
 *                          secret as `x-adspace-wake`; the function asks
 *                          `wake_secret_ok` and answers anyone else 401.
 *                          Each queued email is claimed once
 *                          (`creator_mail_claim`), sent through Resend in
 *                          the portal's one layout and closed
 *                          (`creator_mail_done`): sent, failed, or not
 *                          confirmed where Resend's answer never came,
 *                          never sent again by itself. No send starts after
 *                          90 seconds; what is left waits for the next wake.
 *
 * The words are the database's, filled when the email was queued; the page
 * sends none. Resend's word on each reaches `creator_emails` through
 * supplier-mail's webhook (`supplier_email_status`).
 *
 * The same wake adds each approved set of payment details as a row of the
 * finance team's Google Sheet (2026-11-09, CREATOR PAYMENTS SHEET): the
 * sheet's header row read, each value put under the header that names it
 * (`COLUMNS`), a header naming none left empty; claimed and closed by the
 * service role (`creator_sheet_claim`, `creator_sheet_done`), a row refused
 * tried again at the next wake. Nothing is claimed while Google is not set
 * up, so no try is spent.
 *
 *   POST { action: 'check' }  from Settings, as the colleague (Business
 *                          settings at Work, `creator_sheet_get`): the
 *                          sheet's tab and its headers, each with the value
 *                          it will hold; nothing written.
 *
 * Secrets for the sheet: GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET (the
 * client meet-create uses) and GOOGLE_SHEETS_REFRESH_TOKEN, a refresh token
 * with the Sheets scope (docs/GOOGLE-SHEETS-SETUP.md).
 *
 * From MAIL_CREATOR_FROM (unset: ADspace <noreply-creator@sc.adspace.me>),
 * replies to MAIL_CREATOR_REPLY_TO (unset: ap@adspacestudios.com).
 * Secrets: RESEND_API_KEY, plus the platform's SUPABASE_URL and
 * SUPABASE_SERVICE_ROLE_KEY. Verify JWT is off: pg_net calls with no session.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { layout, resend } from '../_shared/mail.ts';
import { cors, json as cjson } from '../_shared/cors.ts';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
const FROM = () => secret('MAIL_CREATOR_FROM') || 'ADspace <noreply-creator@sc.adspace.me>';
const REPLY_TO = () => secret('MAIL_CREATOR_REPLY_TO') || 'ap@adspacestudios.com';
const BUDGET = 90000;
const ROUNDS = 20;

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

type Row = { id: string; purpose: string; to_email: string; subject: string; body: string };

// ---- The payments sheet ------------------------------------------------------
/* What each value is called in a header: a header holding every word of one
   of a value's names takes that value; the longest name wins, each value once. */
export const COLUMNS: [string, string[]][] = [
  ['creator_id', ['creator id', 'creator code']],
  ['reference', ['reference', 'request no', 'request id']],
  ['approved_by', ['approved by']],
  ['approved', ['approved', 'approval date', 'approved on']],
  ['submitted', ['submitted', 'submission date', 'timestamp']],
  ['billing_as', ['billing as', 'billing type']],
  ['legal_name', ['legal name', 'name as per', 'registered name', 'full name']],
  ['id_no', ['nric', 'passport', 'brn', 'id no', 'ic no', 'identification']],
  ['tin', ['tin', 'tax identification']],
  ['address', ['billing address', 'address']],
  ['currency', ['currency']],
  ['method', ['payment method', 'method']],
  ['bank', ['bank name', 'bank']],
  ['account', ['account number', 'account no', 'account']],
  ['payee', ['payee', 'account holder', 'beneficiary']],
  ['email', ['email address', 'email']],
  ['whatsapp', ['whatsapp', 'mobile', 'phone']],
  ['creator_name', ['creator name', 'creator', 'name']]
];
const words = (v: string) => String(v || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().split(' ').filter(Boolean);
export function columnsOf(headers: string[]): (string | null)[] {
  const out: (string | null)[] = headers.map(() => null);
  const taken = new Set<string>();
  const cands: { i: number; key: string; len: number }[] = [];
  headers.forEach((h, i) => {
    const hw = words(h);
    for (const [key, names] of COLUMNS) for (const n of names) {
      const nw = words(n);
      if (nw.length && nw.every((w) => hw.includes(w))) cands.push({ i, key, len: nw.length * 100 + n.length });
    }
  });
  cands.sort((a, b) => b.len - a.len || a.i - b.i);
  for (const c of cands) if (out[c.i] === null && !taken.has(c.key)) { out[c.i] = c.key; taken.add(c.key); }
  return out;
}
const GOOGLE = ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_SHEETS_REFRESH_TOKEN'];
async function googleToken(): Promise<string | null> {
  if (GOOGLE.some((k) => !secret(k))) return null;
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: secret('GOOGLE_CLIENT_ID'), client_secret: secret('GOOGLE_CLIENT_SECRET'),
      refresh_token: secret('GOOGLE_SHEETS_REFRESH_TOKEN'), grant_type: 'refresh_token' }) });
  const d = await r.json().catch(() => ({}));
  return r.ok && d.access_token ? String(d.access_token) : null;
}
const SHEETS = 'https://sheets.googleapis.com/v4/spreadsheets/';
async function sheetGet(token: string, path: string): Promise<any> {
  const r = await fetch(SHEETS + path, { headers: { Authorization: 'Bearer ' + token } });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error('google ' + r.status + ' ' + String((d.error && d.error.message) || '').slice(0, 200));
  return d;
}
/* The tab named, else the spreadsheet's first, and its header row. */
async function headersOf(token: string, sheet: string, tab: string | null): Promise<{ tab: string; headers: string[] }> {
  let t = tab;
  if (!t) {
    const meta = await sheetGet(token, encodeURIComponent(sheet) + '?fields=sheets.properties.title');
    t = String((meta.sheets && meta.sheets[0] && meta.sheets[0].properties && meta.sheets[0].properties.title) || 'Sheet1');
  }
  const q = "'" + t.replace(/'/g, "''") + "'";
  const v = await sheetGet(token, encodeURIComponent(sheet) + '/values/' + encodeURIComponent(q + '!1:1'));
  return { tab: t, headers: ((v.values && v.values[0]) || []).map((x: unknown) => String(x ?? '')) };
}
async function sheetRows(db: any, began: number): Promise<{ added: number; failed: number }> {
  let added = 0, failed = 0;
  const token = await googleToken();
  if (!token) return { added, failed };
  const { data, error } = await db.rpc('creator_sheet_claim', { p_n: 10 });
  if (error || !data) return { added, failed };
  const rows = (data.rows || []) as any[], sh = data.sheet || {};
  if (!rows.length) return { added, failed };
  let head: { tab: string; headers: string[] } | null = null, why = '';
  try { if (sh.spreadsheet_id) head = await headersOf(token, sh.spreadsheet_id, sh.tab || null); else why = 'no spreadsheet set'; }
  catch (e) { why = String((e as Error).message || e).slice(0, 400); }
  const cols = head ? columnsOf(head.headers) : [];
  if (head && !cols.some(Boolean)) why = 'no header in the sheet names a value';
  for (const r of rows) {
    if (!head || why || Date.now() - began > BUDGET) {
      await db.rpc('creator_sheet_done', { p_id: r.id, p_ok: false, p_error: why || 'not sent: out of time' });
      failed++; continue;
    }
    const line = cols.map((k) => (k ? String((r.values || {})[k] ?? '') : ''));
    try {
      const q = "'" + head.tab.replace(/'/g, "''") + "'";
      const res = await fetch(SHEETS + encodeURIComponent(sh.spreadsheet_id) + '/values/' + encodeURIComponent(q + '!A1') +
        ':append?valueInputOption=RAW&insertDataOption=INSERT_ROWS', { method: 'POST',
        headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: JSON.stringify({ values: [line] }) });
      if (!res.ok) throw new Error('google ' + res.status + ' ' + (await res.text()).slice(0, 200));
      await db.rpc('creator_sheet_done', { p_id: r.id, p_ok: true, p_error: null });
      added++;
    } catch (e) {
      await db.rpc('creator_sheet_done', { p_id: r.id, p_ok: false, p_error: String((e as Error).message || e).slice(0, 400) });
      failed++;
    }
  }
  return { added, failed };
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } });
  let body: Record<string, any> = {};
  try { body = await req.json(); } catch { body = {}; }
  /* Settings' check, as the colleague: the sheet's headers and what each holds. */
  if (body.action === 'check') {
    const me = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
    const g = await me.rpc('creator_sheet_get');
    if (g.error) return cjson({ error: 'needs-update' }, 200, origin);
    if (!g.data || g.data.error) return cjson({ error: (g.data && g.data.error) || 'denied' }, 200, origin);
    if (!g.data.spreadsheet_id) return cjson({ error: 'no-sheet' }, 200, origin);
    const token = await googleToken();
    if (!token) return cjson({ error: 'google-not-set-up' }, 200, origin);
    try {
      const h = await headersOf(token, g.data.spreadsheet_id, g.data.tab || null);
      const cols = columnsOf(h.headers);
      return cjson({ ok: true, tab: h.tab, columns: h.headers.map((x, i) => ({ header: x, value: cols[i] })) }, 200, origin);
    } catch (e) {
      return cjson({ error: 'google-refused', reason: String((e as Error).message || e).slice(0, 200) }, 200, origin);
    }
  }
  const given = req.headers.get('x-adspace-wake') || '';
  const woken = given.length >= 32 ? await db.rpc('wake_secret_ok', { p_given: given }) : null;
  if (!woken || woken.error || woken.data !== true) return reply({ error: 'denied' }, 401);

  const apiKey = secret('RESEND_API_KEY');
  let sent = 0, failed = 0;
  const began = Date.now();
  for (let round = 0; apiKey && round < ROUNDS; round++) {
    if (Date.now() - began > BUDGET) break;
    const { data: batch, error } = await db.rpc('creator_mail_claim', { p_n: 1 });
    if (error) return reply({ error: 'claim', reason: error.message, sent, failed });
    const rows = (Array.isArray(batch) ? batch : []) as Row[];
    if (!rows.length) break;
    for (const r of rows) {
      const out = await resend({
        from: FROM(), to: [r.to_email], reply_to: REPLY_TO(), subject: r.subject,
        html: layout({ heading: r.subject, body: r.body }),
        text: r.body
      }, 'creator-' + r.id, apiKey);
      await db.rpc('creator_mail_done', { p_id: r.id, p_status: out.status, p_provider: out.provider, p_error: out.error });
      if (out.status === 'sent') sent++; else failed++;
    }
  }
  const sheet = await sheetRows(db, began).catch((e) => { console.error('creator-mail: sheet', String((e as Error).message || e)); return { added: 0, failed: 0 }; });
  return reply({ ok: true, sent, failed, sheet, mail: apiKey ? 'on' : 'mail-not-set-up' });
});
