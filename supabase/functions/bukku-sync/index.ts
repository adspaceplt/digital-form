/*
 * bukku-sync — sends a client's billing or a supplier's details to Bukku as
 * one contact, by hand (2026-10-18; 2026-10-18-bukku-contacts.sql).
 *
 *   POST { action: 'fields' }                 Bukku's custom contact fields,
 *                                             for Settings' Bukku sheet.
 *   POST { action: 'find', kind, id }         the linked contact, else the
 *                                             contacts that may be it (the
 *                                             same BRN, else the same name),
 *                                             and the next contact code.
 *   POST { action: 'preview', kind, id, contact }
 *                                             what changes in that contact
 *                                             (none: a new one), field by
 *                                             field.
 *   POST { action: 'send', kind, id, contact } creates it (contact null) or
 *                                             updates it, then files the
 *                                             link (`bukku_linked`).
 *
 * What is sent is the database's answer as the colleague (`bukku_prepare`),
 * never the page's. An update reads the contact first and changes only the
 * portal's fields: its code, payment terms, accounts, groups, price level and
 * other people and addresses stay as Bukku holds them; the contact's types
 * gain Customer or Supplier, never lose one. Nothing is ever deleted or
 * archived in Bukku.
 *
 * Secrets: BUKKU_TOKEN (Control Panel › Integrations, API Access),
 *          BUKKU_SUBDOMAIN (the part before .bukku.my), optionally
 *          BUKKU_API (unset: https://api.bukku.my; the staging server for a
 *          test account), plus the platform's SUPABASE_URL and
 *          SUPABASE_ANON_KEY.
 *
 * Verify JWT is off, as every portal function that checks its caller
 * itself: the database answers as the caller. A refusal the person can act
 * on answers 200 with { error }.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const ALLOWED_ORIGINS = ['https://digital.adspace.me', 'http://localhost:8899'];
function cors(origin: string | null) {
  const allow = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin'
  };
}
function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...cors(origin) } });
}
function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }

// ---- Bukku ------------------------------------------------------------------
class BukkuError extends Error {
  code: string;
  status: number;
  constructor(code: string, status: number, message: string) { super(message); this.code = code; this.status = status; }
}
async function bukku(method: string, path: string, body?: unknown): Promise<any> {
  const base = (secret('BUKKU_API') || 'https://api.bukku.my').replace(/\/+$/, '');
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 20000);
  let res: Response;
  try {
    res = await fetch(base + path, {
      method,
      headers: {
        'Authorization': 'Bearer ' + secret('BUKKU_TOKEN'),
        'Company-Subdomain': secret('BUKKU_SUBDOMAIN').replace(/\.bukku\.my$/i, ''),
        'Accept': 'application/json',
        ...(body ? { 'Content-Type': 'application/json' } : {})
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: ctl.signal
    });
  } catch (e) {
    throw new BukkuError('bukku-unreachable', 0, String((e as Error).message || e));
  } finally { clearTimeout(timer); }
  const text = await res.text();
  let data: any = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = null; }
  if (res.status === 401 || res.status === 403) throw new BukkuError('bukku-token', res.status, 'refused');
  if (!res.ok) {
    const msg = (data && (data.message || (data.errors && JSON.stringify(data.errors)))) || text.slice(0, 300);
    throw new BukkuError('bukku-refused', res.status, String(msg).slice(0, 400));
  }
  return data;
}

/* Every contact, a hundred a page (a few hundred at most here), customers,
   suppliers and archived alike, so a match is never missed. */
async function allContacts(): Promise<any[]> {
  const out: any[] = [];
  for (let page = 1; page <= 50; page++) {
    const r = await bukku('GET', `/contacts?page=${page}&page_size=100&status=ALL`);
    const rows = (r && r.contacts) || [];
    out.push(...rows);
    const per = Number(r && r.paging && r.paging.per_page) || rows.length || 100;
    const total = Number(r && r.paging && r.paging.total) || 0;
    if (!rows.length || out.length >= total || rows.length < per) break;
  }
  return out;
}

const digits = (v: unknown) => String(v ?? '').replace(/[^0-9A-Za-z]/g, '').toUpperCase();
const words = (v: unknown) => String(v ?? '').toUpperCase().replace(/\b(SDN|BHD|BERHAD|PLT|PTE|LTD|ENTERPRISE|TRADING|THE)\b/g, ' ')
  .replace(/[^A-Z0-9]+/g, ' ').trim();

/* Bukku's own next code for a name: C, the name's first letter or digit,
   then the next number of four. */
function nextCode(contacts: any[], name: string): string {
  const first = (String(name).toUpperCase().match(/[A-Z0-9]/) || ['X'])[0];
  let n = 0;
  for (const c of contacts) {
    const m = new RegExp('^C-' + first + '(\\d+)$').exec(String(c.contact_code || ''));
    if (m) n = Math.max(n, Number(m[1]));
  }
  return 'C-' + first + String(n + 1).padStart(4, '0');
}

const STATES = ['Johor', 'Kedah', 'Kelantan', 'Melaka', 'Malacca', 'Negeri Sembilan', 'Pahang', 'Penang', 'Pulau Pinang', 'Perak',
  'Perlis', 'Sabah', 'Sarawak', 'Selangor', 'Terengganu', 'Kuala Lumpur', 'Labuan', 'Putrajaya'];
/* One typed address read into Bukku's parts: the whole of it the street,
   the postcode, the town after it and the state where they can be read. */
function addressOf(text: string, country: string) {
  const flat = String(text || '').replace(/\s*\n+\s*/g, ', ').replace(/\s+/g, ' ').trim();
  const pc = (flat.match(country === 'SG' ? /\b(\d{6})\b/ : /\b(\d{5})\b/) || [])[1] || null;
  let city: string | null = null;
  if (pc) {
    const after = flat.slice(flat.indexOf(pc) + pc.length).replace(/^[\s,]+/, '');
    city = (after.split(',')[0] || '').trim() || null;
  }
  const state = STATES.find((s) => new RegExp('\\b' + s + '\\b', 'i').test(flat)) || null;
  return { street: flat.slice(0, 255), postcode: pc, city: city && city.length <= 50 ? city : null, state, country_code: country };
}

// ---- What the portal holds, set over what Bukku holds -------------------------
type Prep = Record<string, any>;
function merged(p: Prep, cur: any | null, code: string) {
  const c = cur || {};
  const out: Record<string, any> = {
    entity_type: c.entity_type || p.entity_type,
    legal_name: p.legal_name,
    contact_code: c.contact_code || code,
    types: Array.from(new Set([...(c.types || []), p.type])),
    default_currency_code: c.default_currency_code || p.currency
  };
  if (!cur) out.entity_type = p.entity_type;
  if (p.other_name || c.other_name) out.other_name = p.other_name || c.other_name;
  for (const k of ['reg_no_type', 'reg_no', 'old_reg_no', 'tax_id_no', 'sst_reg_no', 'email', 'phone_no']) {
    const v = p[k] ?? c[k] ?? null;
    if (v !== null && v !== '') out[k] = v;
  }
  if (out.reg_no && !out.reg_no_type) out.reg_no_type = 'BRN';
  // Kept as Bukku holds them.
  for (const k of ['group_ids', 'price_level_id', 'tag_ids', 'default_term_id', 'default_income_account_id',
    'default_expense_account_id', 'remarks', 'receive_monthly_statement', 'receive_invoice_reminder',
    'receivable_account_id', 'debtor_credit_limit', 'payable_account_id']) {
    if (c[k] !== undefined && c[k] !== null) out[k] = c[k];
  }
  // The billing person: the default billing one renamed, else added as it.
  const persons = (c.contact_persons || []).map((x: any) => ({ id: x.id, first_name: x.first_name, last_name: x.last_name,
    is_default_billing: !!x.is_default_billing, is_default_shipping: !!x.is_default_shipping }));
  if (p.person) {
    const bp = persons.find((x: any) => x.is_default_billing);
    if (bp) { bp.first_name = String(p.person).slice(0, 50); bp.last_name = null; }
    else persons.push({ first_name: String(p.person).slice(0, 50), last_name: null, is_default_billing: true, is_default_shipping: !persons.length });
  }
  if (persons.length) out.contact_persons = persons;
  // The billing address the same way.
  const addrs = (c.addresses || []).map((x: any) => ({ id: x.id, name: x.name, street: x.street, city: x.city, state: x.state,
    postcode: x.postcode, country_code: x.country_code, is_default_billing: !!x.is_default_billing, is_default_shipping: !!x.is_default_shipping }));
  if (p.address) {
    const a = addressOf(p.address, p.country);
    const ba = addrs.find((x: any) => x.is_default_billing);
    if (ba) Object.assign(ba, a);
    else addrs.push({ name: 'Billing Address', ...a, is_default_billing: true, is_default_shipping: !addrs.length });
  }
  if (addrs.length) out.addresses = addrs;
  // The Client ID or Supplier ID in its custom field.
  const fields = (c.fields || []).map((x: any) => ({ id: x.id, field_id: x.field_id, value: x.value }));
  if (p.field_id && p.our_id) {
    const f = fields.find((x: any) => Number(x.field_id) === Number(p.field_id));
    if (f) f.value = p.our_id; else fields.push({ field_id: Number(p.field_id), value: p.our_id });
  }
  if (fields.length) out.fields = fields;
  return out;
}

/* What a person reads changing, field by field. */
function rowsOf(p: Prep, cur: any | null, next: Record<string, any>) {
  const c = cur || {};
  const person = (x: any) => { const bp = (x.contact_persons || []).find((y: any) => y.is_default_billing); return bp ? [bp.first_name, bp.last_name].filter(Boolean).join(' ') : ''; };
  const addr = (x: any) => { const ba = (x.addresses || []).find((y: any) => y.is_default_billing); return ba ? ba.street || '' : ''; };
  const idOf = (x: any) => { const f = (x.fields || []).find((y: any) => Number(y.field_id) === Number(p.field_id)); return f ? String(f.value ?? '') : ''; };
  const T: Record<string, string> = { customer: 'Customer', supplier: 'Supplier', employee: 'Employee' };
  const list: [string, string, string][] = [
    ['Legal name', c.legal_name || '', next.legal_name || ''],
    ['Registration no.', c.reg_no || '', next.reg_no || ''],
    ['Old registration no.', c.old_reg_no || '', next.old_reg_no || ''],
    ['TIN', c.tax_id_no || '', next.tax_id_no || ''],
    ['SST no.', c.sst_reg_no || '', next.sst_reg_no || ''],
    ['Email', c.email || '', next.email || ''],
    ['Phone', c.phone_no || '', next.phone_no || ''],
    ['Billing person', person(c), person(next)],
    ['Billing address', addr(c), addr(next)],
    [p.kind === 'client' ? 'Client ID' : 'Supplier ID', idOf(c), idOf(next)],
    ['Type', (c.types || []).map((t: string) => T[t] || t).join(', '), (next.types || []).map((t: string) => T[t] || t).join(', ')]
  ];
  return list.map(([field, now, after]) => ({ field, now, after, same: now === after }));
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  if (!secret('BUKKU_TOKEN') || !secret('BUKKU_SUBDOMAIN')) return json({ error: 'bukku-not-set-up' }, 200, origin);
  let body: Record<string, any> = {};
  try { body = await req.json(); } catch { return json({ error: 'bad-request' }, 400, origin); }
  const action = String(body.action || '');
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });

  try {
    if (action === 'fields') {
      const cfg = await db.rpc('bukku_config');
      if (cfg.error) return json({ error: 'needs-update' }, 200, origin);
      if (cfg.data && cfg.data.error) return json({ error: cfg.data.error }, 200, origin);
      const r = await bukku('POST', '/v2/lists', { lists: ['fields'], params: {} });
      const items = (r && r.fields && r.fields.items && r.fields.items.contact) || (r && r.fields && r.fields.contact) || [];
      const list = (Array.isArray(items) ? items : (items.items || [])).map((f: any) => ({ id: f.id, name: f.name, type: f.data_type || f.type }))
        .filter((f: any) => f.id && f.name);
      return json({ ok: true, fields: list }, 200, origin);
    }

    const kind = String(body.kind || ''), id = String(body.id || '');
    if (!['client', 'supplier'].includes(kind) || !/^[0-9a-f-]{36}$/i.test(id)) return json({ error: 'bad-request' }, 400, origin);
    const prep = await db.rpc('bukku_prepare', { p_kind: kind, p_id: id });
    if (prep.error) return json({ error: 'needs-update' }, 200, origin);
    const p = prep.data as Prep;
    if (!p || p.error) return json(p || { error: 'bad-request' }, 200, origin);
    if (!p.field_id) return json({ error: 'no-field' }, 200, origin);

    if (action === 'find') {
      if (p.contact_id) {
        const cur = await bukku('GET', `/contacts/${Number(p.contact_id)}`).then((r) => r && r.contact).catch(() => null);
        if (cur) return json({ ok: true, linked: { id: cur.id, code: cur.contact_code, name: cur.legal_name, types: cur.types || [] } }, 200, origin);
      }
      const all = await allContacts();
      const reg = digits(p.reg_no), name = words(p.legal_name), other = words(p.other_name);
      const seen = new Set<number>();
      const found: any[] = [];
      for (const c of all) {
        const why = reg && digits(c.reg_no) === reg ? 'brn'
          : name && words(c.legal_name) === name ? 'name'
          : other && (words(c.legal_name) === other || words(c.other_name) === other) ? 'name'
          : name && name.length > 3 && (words(c.legal_name).includes(name) || name.includes(words(c.legal_name)) && words(c.legal_name).length > 3) ? 'similar' : '';
        if (why && !seen.has(c.id)) {
          seen.add(c.id);
          found.push({ id: c.id, code: c.contact_code, name: c.legal_name, reg_no: c.reg_no || null, types: c.types || [],
            archived: !!c.is_archived, why });
        }
      }
      const rank: Record<string, number> = { brn: 0, name: 1, similar: 2 };
      found.sort((a, b) => rank[a.why] - rank[b.why]);
      return json({ ok: true, candidates: found.slice(0, 5), next_code: nextCode(all, p.legal_name) }, 200, origin);
    }

    const contact = body.contact == null || body.contact === '' ? null : Number(body.contact);
    if (contact !== null && !(contact > 0)) return json({ error: 'bad-request' }, 400, origin);
    if (contact === null && p.contact_id) return json({ error: 'linked' }, 200, origin);
    const cur = contact ? await bukku('GET', `/contacts/${contact}`).then((r) => r && r.contact)
      .catch((e) => { if (e instanceof BukkuError && e.status === 404) return null; throw e; }) : null;
    if (contact && !cur) return json({ error: 'bukku-gone' }, 200, origin);
    const code = cur ? cur.contact_code : nextCode(await allContacts(), p.legal_name);
    const next = merged(p, cur, code);

    if (action === 'preview') {
      return json({ ok: true, code, rows: rowsOf(p, cur, next) }, 200, origin);
    }
    if (action === 'send') {
      const r = cur ? await bukku('PUT', `/contacts/${contact}`, next) : await bukku('POST', '/contacts', next);
      const saved = r && r.contact;
      if (!saved || !saved.id) return json({ error: 'bukku-refused', message: 'No contact came back.' }, 200, origin);
      const l = await db.rpc('bukku_linked', { p_kind: kind, p_id: id, p_contact: saved.id, p_code: saved.contact_code || code });
      if (l.error || (l.data && l.data.error)) {
        console.error('bukku-sync: sent but not filed', kind, id, saved.id, l.error ? l.error.message : l.data.error);
        return json({ error: 'not-filed', contact: saved.id, code: saved.contact_code }, 200, origin);
      }
      return json({ ok: true, contact: saved.id, code: saved.contact_code || code, created: !cur }, 200, origin);
    }
    return json({ error: 'bad-request' }, 400, origin);
  } catch (e) {
    if (e instanceof BukkuError) {
      console.error('bukku-sync:', e.code, e.status, e.message);
      return json({ error: e.code, status: e.status, message: e.code === 'bukku-refused' ? e.message : undefined }, 200, origin);
    }
    console.error('bukku-sync: failed', String((e as Error).message || e));
    return json({ error: 'failed' }, 200, origin);
  }
});
