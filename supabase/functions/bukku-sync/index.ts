/*
 * bukku-sync — sends a client's billing or a supplier's details to Bukku as
 * one contact, by hand (2026-10-18; 2026-10-18-bukku-contacts.sql).
 *
 *   POST { action: 'fields' }                 Bukku's custom contact fields,
 *                                             for Settings' Bukku sheet.
 *   POST { action: 'taxes' }                  Bukku's tax codes, for Settings'
 *                                             Tax codes (2026-10-22); read only.
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
 *   POST { action: 'link', kind, id, contact } links that contact as Bukku
 *                                             holds it, nothing sent
 *                                             (`bukku_link_only`).
 *   POST { action: 'contacts', q }            Bukku's customers matching
 *                                             every word typed (name) or the
 *                                             registration no., for Add
 *                                             entity (2026-10-29).
 *   POST { action: 'contact', contact }       one of them read whole, to
 *                                             fill New billing entity.
 *   POST { action: 'invoices', client? }      the overdue invoices
 *                                             (2026-10-28): Bukku's unpaid
 *                                             invoices held to the clients
 *                                             the colleague sees
 *                                             (`invoice_scope`), with the
 *                                             reminders sent; read at the
 *                                             press, never stored. With a
 *                                             client, that client's unpaid
 *                                             invoices, those not yet due
 *                                             too (its Billing).
 *   POST { action: 'remind', contact, invoices, cc, subject, body, again }
 *                                             one reminder to one Bukku
 *                                             contact: each invoice read
 *                                             again from Bukku, one paid
 *                                             since left out and named, the
 *                                             table, figures and links built
 *                                             here, filed and closed by the
 *                                             service role
 *                                             (`invoice_email_begin`,
 *                                             `invoice_email_done`), sent
 *                                             through Resend (_shared/mail.ts)
 *                                             from MAIL_FINANCE_FROM (unset:
 *                                             ADspace Finance
 *                                             <noreply-finance@sc.adspace.me>),
 *                                             replies to MAIL_FINANCE_REPLY_TO
 *                                             (unset: einvoice@adspacestudios.com).
 *
 * What is sent is the database's answer as the colleague (`bukku_prepare`),
 * never the page's. An update reads the contact first and changes only the
 * portal's fields: its code, accounts, groups, price level and other people
 * stay as Bukku holds them, its payment term too unless a supplier's agreed
 * term is one Bukku holds, and an address or a name Bukku already holds is
 * kept however it is set out; the contact's types
 * gain Customer or Supplier, never lose one. Nothing is ever deleted or
 * archived in Bukku.
 *
 * Secrets: BUKKU_TOKEN (Control Panel › Integrations, API Access),
 *          BUKKU_SUBDOMAIN (the part before .bukku.my), optionally
 *          BUKKU_API (unset: https://api.bukku.my; the staging server for a
 *          test account), RESEND_API_KEY for a reminder, plus the
 *          platform's SUPABASE_URL, SUPABASE_ANON_KEY and
 *          SUPABASE_SERVICE_ROLE_KEY.
 *
 * Verify JWT is off, as every portal function that checks its caller
 * itself: the database answers as the caller. A refusal the person can act
 * on answers 200 with { error }.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json } from '../_shared/cors.ts';
import { esc, FONT, layout, resend } from '../_shared/mail.ts';

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
/* One typed address read into Bukku's parts (2026-10-19, the user: Bukku
   holds the street, postcode, city, state and country apart): the country
   and the state taken off its end, the postcode and the town after it,
   the rest the street, a line break read as a comma and never doubled. */
const COUNTRIES = ['Malaysia', 'Singapore'];
function addressOf(text: string, country: string) {
  const flat = String(text || '').replace(/\s*,?\s*\n+\s*/g, ', ').replace(/\s+/g, ' ').replace(/(\s*,\s*)+/g, ', ')
    .replace(/^[\s,]+|[\s,]+$/g, '');
  let parts = flat.split(/\s*,\s*/).filter(Boolean);
  const re = (w: string) => new RegExp('^' + w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '$', 'i');
  if (parts.length) {
    // "Selangor Malaysia" or "Malaysia" alone: the country off the end.
    const last = parts[parts.length - 1].replace(new RegExp('\\s+(' + COUNTRIES.join('|') + ')$', 'i'), '');
    if (COUNTRIES.some((c) => re(c).test(last))) parts.pop(); else parts[parts.length - 1] = last;
  }
  let state: string | null = null;
  if (parts.length > 1) {
    const last = parts[parts.length - 1];
    const hit = STATES.find((x) => re(x).test(last));
    if (hit) { state = hit; parts.pop(); }
  }
  let pc: string | null = null, city: string | null = null;
  const pcRe = country === 'SG' ? /\b(\d{6})\b/ : /\b(\d{5})\b/;
  for (let i = parts.length - 1; i >= 0 && !pc; i--) {
    const m = pcRe.exec(parts[i]);
    if (!m) continue;
    pc = m[1];
    const rest = parts[i].replace(m[0], ' ').replace(/\s+/g, ' ').trim();
    if (rest) {
      // "52200 Petaling Jaya Selangor": a state at the end of the town is the state.
      const st = !state ? STATES.find((x) => new RegExp('\\s' + x + '$', 'i').test(rest)) : undefined;
      city = st ? rest.slice(0, rest.length - st.length).trim() : rest;
      if (st) state = st;
    } else if (parts[i + 1] && !state) { city = parts[i + 1]; parts.splice(i + 1, 1); }
    parts.splice(i, 1);
  }
  if (!state) state = STATES.find((x) => new RegExp('\\b' + x + '\\b', 'i').test(flat)) || null;
  if (country === 'SG' && !city && pc) city = 'Singapore';
  const street = parts.join(', ') || flat;
  return { street: street.slice(0, 255), postcode: pc, city: city && city.length <= 50 ? city : null, state, country_code: country };
}
/* The same address however it is punctuated or cased. */
const plain = (v: unknown) => String(v ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
function sameAddress(a: any, b: any) {
  if (!a || !b) return false;
  if (plain(a.street) !== plain(b.street)) return false;
  for (const k of ['postcode', 'city', 'state']) if (a[k] && plain(a[k]) !== plain(b[k])) return false;
  return !a.country_code || !b.country_code || a.country_code === b.country_code;
}
const addressLine = (a: any) => a ? [a.street, [a.postcode, a.city].filter(Boolean).join(' '), a.state,
  a.country_code === 'SG' ? 'Singapore' : a.country_code === 'MY' ? 'Malaysia' : a.country_code].filter(Boolean).join(', ') : '';
/* A name's words, a salutation's dots dropped. */
const nameWords = (v: unknown) => String(v ?? '').toUpperCase().replace(/[.]/g, '').split(/\s+/).filter(Boolean);
/* The salutations a name may open on, the longest first (the contact
   sheet's list; never Tan, a surname too). */
const SALS = ["Dato' Sri", 'Datin Sri', 'Datuk Sri', 'Tan Sri', 'Puan Sri', 'Mr', 'Ms', 'Mrs', 'Miss', 'Mdm', 'Madam', 'Dr',
  'Prof', "Dato'", 'Dato', 'Datin', 'Datuk', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik'].map(nameWords);
/* How many of a name's first words are a salutation (0 for none). */
const salLead = (words: string[]) => {
  const s = SALS.filter((x) => x.length <= words.length && x.every((w, i) => words[i] === w))
    .sort((a, b) => b.length - a.length)[0];
  return s ? s.length : 0;
};

// ---- What the portal holds, set over what Bukku holds -------------------------
type Prep = Record<string, any>;
/* A supplier's payment term as Bukku's own term (2026-10-19): the one
   whose name carries the same days ("NET 30", "Net 30 days"); none found,
   Bukku's is kept. */
async function termsOf(): Promise<any[]> {
  try {
    const r = await bukku('POST', '/v2/lists', { lists: ['terms'], params: {} });
    const t = r && r.terms;
    const list = Array.isArray(t) ? t : (t && (Array.isArray(t.items) ? t.items : null)) || [];
    return list.filter((x: any) => x && x.id && x.name);
  } catch { return []; }
}
function termFor(terms: any[], term: unknown): any | null {
  const d = (String(term ?? '').match(/\d+/) || [])[0];
  if (!d) return null;
  return terms.find((x: any) => (String(x.name).match(/\d+/) || [])[0] === d && /net/i.test(String(x.name)))
    || terms.find((x: any) => (String(x.name).match(/\d+/) || [])[0] === d) || null;
}

function merged(p: Prep, cur: any | null, code: string, term?: any | null) {
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
  // A supplier's agreed term over Bukku's, where Bukku holds the same.
  if (term && term.id) out.default_term_id = term.id;
  // The billing person: the default billing one renamed, else added as it.
  const persons = (c.contact_persons || []).map((x: any) => ({ id: x.id, first_name: x.first_name, last_name: x.last_name,
    is_default_billing: !!x.is_default_billing, is_default_shipping: !!x.is_default_shipping }));
  /* With its salutation (2026-10-19); a name Bukku already holds in full
     (every word of ours in Bukku's) is kept, the salutation put before it
     where Bukku's lacks it, and in place of another it opens on
     (2026-10-29: Ms Agnes Ang read Mrs Ms Agnes Ang). */
  if (p.person) {
    const sal = String(p.salutation || '').trim();
    const named = (sal ? sal + ' ' : '') + String(p.person);
    const bp = persons.find((x: any) => x.is_default_billing);
    if (bp) {
      const theirs = nameWords([bp.first_name, bp.last_name].filter(Boolean).join(' '));
      if (nameWords(p.person).every((w) => theirs.includes(w))) {
        const lead = salLead(theirs), first = String(bp.first_name || '').trim().split(/\s+/).filter(Boolean);
        const same = lead && nameWords(sal).join(' ') === theirs.slice(0, lead).join(' ');
        if (sal && !same) {
          // Bukku's own salutation sits in its first name; a name split otherwise is set whole.
          if (lead && first.length >= lead) bp.first_name = [sal].concat(first.slice(lead)).join(' ').slice(0, 50);
          else if (lead) { bp.first_name = named.slice(0, 50); bp.last_name = null; }
          else bp.first_name = (sal + ' ' + (bp.first_name || '')).trim().slice(0, 50);
        }
      } else { bp.first_name = named.slice(0, 50); bp.last_name = null; }
    }
    else persons.push({ first_name: named.slice(0, 50), last_name: null, is_default_billing: true, is_default_shipping: false });
  }
  if (persons.length) out.contact_persons = persons;
  // The billing address the same way.
  const addrs = (c.addresses || []).map((x: any) => ({ id: x.id, name: x.name, street: x.street, city: x.city, state: x.state,
    postcode: x.postcode, country_code: x.country_code, is_default_billing: !!x.is_default_billing, is_default_shipping: !!x.is_default_shipping }));
  if (p.address) {
    const a = addressOf(p.address, p.country);
    const ba = addrs.find((x: any) => x.is_default_billing);
    // The address Bukku holds, however set out, is kept.
    if (ba) { if (!sameAddress(a, ba)) Object.assign(ba, a); }
    else addrs.push({ name: 'Billing Address', ...a, is_default_billing: true, is_default_shipping: false });
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
function rowsOf(p: Prep, cur: any | null, next: Record<string, any>, terms: any[] = []) {
  const c = cur || {};
  const person = (x: any) => { const bp = (x.contact_persons || []).find((y: any) => y.is_default_billing); return bp ? [bp.first_name, bp.last_name].filter(Boolean).join(' ') : ''; };
  const addr = (x: any) => addressLine((x.addresses || []).find((y: any) => y.is_default_billing));
  const termName = (id: unknown) => { const t = terms.find((x: any) => Number(x.id) === Number(id)); return t ? String(t.name) : ''; };
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
    ['Payment term', termName(c.default_term_id), termName(next.default_term_id)],
    [p.kind === 'client' ? 'Client ID' : 'Supplier ID', idOf(c), idOf(next)],
    ['Type', (c.types || []).map((t: string) => T[t] || t).join(', '), (next.types || []).map((t: string) => T[t] || t).join(', ')]
  ];
  return list.map(([field, now, after]) => ({ field, now, after, same: now === after }));
}


// ---- A billing entity started from Bukku (2026-10-29) ------------------------
/* Add entity's second list (the user, 2026-10-29: "Cant even find or
   lookup"): Bukku's customers whose name or registration no. holds every
   word typed, and one picked read whole to fill New billing entity. Read
   only, nothing written in Bukku or the portal. Held as the overdue
   invoices are (`invoice_scope`): Clients: Billing at Work, a contact
   linked to a client the colleague sees, any other only for a colleague
   who sees every client. */
async function contactsAction(action: string, body: Record<string, any>, db: any, origin: string | null): Promise<Response> {
  const sc = await db.rpc('invoice_scope');
  if (sc.error) return json({ error: 'needs-update' }, 200, origin);
  const scope = sc.data || {};
  if (scope.error) return json({ error: scope.error }, 200, origin);
  if (scope.send !== true) return json({ error: 'denied' }, 200, origin);
  const linked = new Set<number>((scope.links || []).map((l: any) => Number(l.contact)));
  const may = (id: number) => scope.all === true || linked.has(id);
  const customer = (c: any) => (c.types || []).includes('customer') && !c.is_archived;

  if (action === 'contact') {
    const id = Number(body.contact);
    if (!(id > 0) || !may(id)) return json({ error: 'denied' }, 200, origin);
    const c = await bukku('GET', `/contacts/${id}`).then((r) => r && r.contact)
      .catch((e) => { if (e instanceof BukkuError && e.status === 404) return null; throw e; });
    if (!c) return json({ error: 'bukku-gone' }, 200, origin);
    const addr = (c.addresses || []).find((a: any) => a.is_default_billing) || (c.addresses || [])[0];
    const s = (v: unknown) => { const x = String(v ?? '').trim(); return x || null; };
    return json({ ok: true, entity: {
      legal_name: s(c.legal_name), company_no: s(c.reg_no), company_no_old: s(c.old_reg_no),
      tin: s(c.tax_id_no), sst_no: s(c.sst_reg_no), finance_email: s(c.email),
      billing_address: s(addressLine(addr)) } }, 200, origin);
  }

  const q = String(body.q || '').trim().slice(0, 80);
  const want = words(q).split(' ').filter(Boolean), reg = digits(q);
  if (q.length < 2 || (!want.length && reg.length < 4)) return json({ ok: true, contacts: [] }, 200, origin);
  if (scope.all !== true && !linked.size) return json({ ok: true, contacts: [] }, 200, origin);
  const hit = (c: any) => {
    const name = words(c.legal_name) + ' ' + words(c.other_name);
    return (want.length && want.every((w) => name.includes(w))) || (reg.length >= 4 && digits(c.reg_no).includes(reg));
  };
  const found = (await allContacts()).filter((c) => customer(c) && may(Number(c.id)) && hit(c))
    .sort((a, b) => String(a.legal_name).localeCompare(String(b.legal_name))).slice(0, 8)
    .map((c) => ({ id: c.id, code: c.contact_code, name: c.legal_name, other: c.other_name || null, reg_no: c.reg_no || null }));
  return json({ ok: true, contacts: found }, 200, origin);
}

// ---- Overdue invoices (2026-10-28) -------------------------------------------
/* Malaysia's day: the one a due date is counted against. */
export function todayMY(now = Date.now()): string { return new Date(now + 8 * 3600e3).toISOString().slice(0, 10); }
const cents = (n: number) => Math.round((Number(n) || 0) * 100) / 100;
const LINK = /^https:\/\/[a-z0-9-]+\.bukku\.my\/[A-Za-z0-9/_-]+$/;
/* What of an invoice is overdue: the unpaid part of every instalment whose
   date has passed, else (one date) the balance once its date has passed.
   Null where nothing is overdue, or where instalments carry no balance of
   their own (then the invoice is read whole). */
export function overdueOf(inv: any, today: string): any | null | undefined {
  const bal = cents(inv.balance);
  if (!(bal > 0) || (inv.status && inv.status !== 'ready')) return null;
  const terms = (Array.isArray(inv.term_items) ? inv.term_items : []).filter((t: any) => t && /^\d{4}-\d{2}-\d{2}$/.test(String(t.date || '')))
    .slice().sort((a: any, b: any) => String(a.date).localeCompare(String(b.date)));
  if (terms.length <= 1) {
    const due = (terms[0] && terms[0].date) || String(inv.date || '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(due) || !(due < today)) return null;
    return { amount: bal, due, part: null };
  }
  if (!terms.every((t: any) => t.balance != null)) return undefined;
  const past = terms.filter((t: any) => t.date < today && cents(t.balance) > 0);
  if (!past.length) return null;
  const amount = cents(Math.min(bal, past.reduce((n: number, t: any) => n + cents(t.balance), 0)));
  if (!(amount > 0)) return null;
  return { amount, due: past[0].date, part: partOf(terms, past[0], past[past.length - 1]) };
}
/* The instalments a line covers, first to last: "Instalment 2 of 3", or
   "Instalments 1 to 2 of 3" where several have passed (review 2026-10-29,
   4: the last one's number stood beside the first one's date). `n` is the
   last, as an open page before this read it. */
function partOf(terms: any[], first: any, last: any) {
  const from = terms.indexOf(first) + 1, to = terms.indexOf(last) + 1;
  return { n: to, from, to, of: terms.length };
}
export function partWord(p: any): string {
  if (!p || !p.of) return '';
  const from = Number(p.from || p.n), to = Number(p.to || p.n);
  return from === to ? 'Instalment ' + to + ' of ' + p.of : 'Instalments ' + from + ' to ' + to + ' of ' + p.of;
}
/* Instalments Bukku sent with no balances of their own, even on the
   invoice read whole, never taken for paid (review 2026-10-29, 5). Where
   each carries its amount, what is paid (the invoice less its balance) is
   set against them in date order: overdue is what the instalments passed
   ask beyond it, due on the first one not covered (review 2026-10-29, 3:
   RM 1,000 in two read as all overdue from the first date). Without
   amounts, the whole balance from the earliest date passed. */
export function overdueWhole(inv: any, today: string): any | null {
  const bal = cents(inv.balance);
  if (!(bal > 0) || (inv.status && inv.status !== 'ready')) return null;
  const terms = (Array.isArray(inv.term_items) ? inv.term_items : []).filter((t: any) => t && /^\d{4}-\d{2}-\d{2}$/.test(String(t.date || '')))
    .slice().sort((a: any, b: any) => String(a.date).localeCompare(String(b.date)));
  const total = cents(inv.amount);
  if (terms.length > 1 && total >= bal && terms.every((t: any) => t.amount != null && Number.isFinite(Number(t.amount)))) {
    let left = cents(total - bal), first: any = null, last: any = null, owed = 0;
    for (const t of terms) {
      const amt = cents(t.amount);
      const open = cents(Math.max(0, amt - left));
      left = cents(Math.max(0, left - amt));
      if (!(open > 0)) continue;
      if (!(t.date < today)) break;
      if (!first) first = t;
      last = t; owed = cents(owed + open);
    }
    if (!first) return null;
    return { amount: cents(Math.min(bal, owed)), due: first.date, part: partOf(terms, first, last) };
  }
  const due = (terms[0] && terms[0].date) || String(inv.date || '');
  return /^\d{4}-\d{2}-\d{2}$/.test(due) && due < today ? { amount: bal, due, part: null } : null;
}
/* An unpaid invoice not yet past its date (a client's Billing lists these
   too): its balance, due on its earliest unpaid instalment, else its date. */
export function dueOf(inv: any): any | null {
  const bal = cents(inv.balance);
  if (!(bal > 0) || (inv.status && inv.status !== 'ready')) return null;
  const terms = (Array.isArray(inv.term_items) ? inv.term_items : []).filter((t: any) => t && /^\d{4}-\d{2}-\d{2}$/.test(String(t.date || '')))
    .slice().sort((a: any, b: any) => String(a.date).localeCompare(String(b.date)));
  const open = terms.filter((t: any) => t.balance == null || cents(t.balance) > 0);
  const due = (open[0] && open[0].date) || (terms[0] && terms[0].date) || String(inv.date || '');
  return /^\d{4}-\d{2}-\d{2}$/.test(due) ? { amount: bal, due, part: null } : null;
}
function lineOf(inv: any, od: any, today: string) {
  const days = Math.round((Date.parse(today + 'T00:00:00Z') - Date.parse(od.due + 'T00:00:00Z')) / 86400000);
  const link = String(inv.short_link || '');
  return { id: Number(inv.id), number: String(inv.number || ''), date: String(inv.date || ''), due: od.due, days,
    amount: od.amount, balance: cents(inv.balance), total: cents(inv.amount),
    currency: /^[A-Z]{3}$/.test(String(inv.currency_code || '')) ? String(inv.currency_code) : 'MYR',
    link: LINK.test(link) ? link : null, part: od.part,
    contact: Number(inv.contact_id), contact_name: String(inv.contact_name || ''), contact_email: String(inv.contact_email || '') };
}
/* Every invoice still owing, a hundred a page: Bukku's Outstanding and
   Overdue lists together, each once. One client's Billing asks for its own
   contacts alone (review 2026-10-29, 12); every row is still held to the
   contacts asked for by the caller, so a filter Bukku did not apply costs
   time, never a wrong row. */
async function unpaid(contacts?: number[]): Promise<any[]> {
  const seen = new Map<number, any>();
  const by = contacts && contacts.length && contacts.length <= 5 ? contacts.map((c) => `&contact_id=${c}`) : [''];
  for (const who of by) for (const ps of ['OVERDUE', 'OUTSTANDING']) {
    for (let page = 1; page <= 50; page++) {
      const r = await bukku('GET', `/sales/invoices?payment_status=${ps}&status=ready&page=${page}&page_size=100${who}`);
      const rows = (r && r.transactions) || [];
      for (const x of rows) if (x && x.id && !seen.has(Number(x.id))) seen.set(Number(x.id), x);
      const per = Number(r && r.paging && r.paging.per_page) || rows.length || 100;
      const total = Number(r && r.paging && r.paging.total) || 0;
      if (!rows.length || page * per >= total || rows.length < per) break;
    }
  }
  return Array.from(seen.values());
}
async function oneInvoice(id: number): Promise<any | null> {
  return bukku('GET', `/sales/invoices/${id}`).then((r) => (r && r.transaction) || null)
    .catch((e) => { if (e instanceof BukkuError && e.status === 404) return null; throw e; });
}
/* Several invoices read whole, five at a time, in the order asked. */
async function manyInvoices(ids: number[]): Promise<(any | null)[]> {
  const out: (any | null)[] = [];
  for (let i = 0; i < ids.length; i += 5) out.push(...await Promise.all(ids.slice(i, i + 5).map((id) => oneInvoice(id))));
  return out;
}
const money = (n: number, cur: string) => (cur === 'MYR' ? 'RM ' : cur === 'SGD' ? 'S$ ' : cur + ' ') +
  cents(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
const day = (d: string) => { const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(d || ''); return m ? Number(m[3]) + ' ' + MON[Number(m[2]) - 1] + ' ' + m[1] : ''; };
/* The invoices as the email's table: built here from Bukku's figures read at
   the send, never from a page. One invoice carries one button; several,
   each row its own View PDF. Totals are kept per currency. */
export function invoiceTable(lines: any[]): string {
  const cell = 'padding:10px 12px;border-top:1px solid #ececec;font-size:14px;line-height:1.4;color:#1b1a17;';
  const head = 'padding:10px 12px;font-size:12px;font-weight:600;color:#6b6760;text-align:left;';
  const many = lines.length > 1;
  const rows = lines.map((l) => '<tr><td style="' + cell + '">' + esc(l.number) +
      (l.part ? '<br><span style="font-size:12px;color:#6b6760;">' + esc(partWord(l.part)) + '</span>' : '') + '</td>' +
    '<td class="hide-sm" style="' + cell + 'white-space:nowrap;">' + esc(day(l.date)) + '</td>' +
    '<td class="hide-sm" style="' + cell + 'white-space:nowrap;">' + esc(day(l.due)) + '</td>' +
    '<td style="' + cell + 'text-align:right;white-space:nowrap;">' + esc(money(l.amount, l.currency)) + '</td>' +
    (many ? '<td style="' + cell + 'text-align:right;white-space:nowrap;">' +
      (l.link ? '<a href="' + esc(l.link) + '" style="color:#0066cc;text-decoration:none;font-weight:500;font-size:13px;">View PDF</a>' : '') + '</td>' : '') +
    '</tr>').join('');
  const byCur: Record<string, number> = {};
  for (const l of lines) byCur[l.currency] = cents((byCur[l.currency] || 0) + l.amount);
  const tot = Object.keys(byCur).sort().map((c) => money(byCur[c], c)).join('<br>');
  const table = '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;background:#f9f9f9;border-radius:10px;border-collapse:separate;font-family:' + FONT + ';">' +
    '<tr><th style="' + head + '">Invoice</th><th class="hide-sm" style="' + head + '">Issued</th><th class="hide-sm" style="' + head + '">Due</th>' +
    '<th style="' + head + 'text-align:right;">Amount due</th>' + (many ? '<th style="' + head + '"></th>' : '') + '</tr>' + rows +
    '<tr><td style="' + cell + 'font-weight:600;">Total due</td><td class="hide-sm" style="' + cell + '"></td><td class="hide-sm" style="' + cell + '"></td>' +
    '<td style="' + cell + 'font-weight:600;text-align:right;white-space:nowrap;">' + tot + '</td>' + (many ? '<td style="' + cell + '"></td>' : '') + '</tr></table>';
  const one = !many && lines[0] && lines[0].link
    ? '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;"><tr><td style="background:#0071e3;border-radius:8px;"><a href="' + esc(lines[0].link) + '" style="display:inline-block;padding:7px 14px;text-align:center;font-family:' + FONT + ';font-size:13px;line-height:16px;font-weight:500;color:#ffffff;text-decoration:none;">View PDF</a></td></tr></table>'
    : '';
  return table + one;
}
const FIN_FROM = () => secret('MAIL_FINANCE_FROM') || 'ADspace Finance <noreply-finance@sc.adspace.me>';
const FIN_REPLY = () => secret('MAIL_FINANCE_REPLY_TO') || 'einvoice@adspacestudios.com';

async function invoiceAction(action: string, body: Record<string, any>, db: any, origin: string | null): Promise<Response> {
  const sc = await db.rpc('invoice_scope');
  if (sc.error) return json({ error: 'needs-update' }, 200, origin);
  const scope = sc.data || {};
  if (scope.error) return json({ error: scope.error }, 200, origin);
  const links = new Map<number, any>();
  for (const l of scope.links || []) links.set(Number(l.contact), l);
  const today = todayMY();
  const mayContact = (c: number) => links.has(c) || scope.all === true;

  if (action === 'invoices') {
    /* One client's (its Billing, 2026-10-28): the Bukku contacts linked to
       it alone, and its unpaid invoices not yet due as well. */
    const forClient = /^[0-9a-f-]{36}$/i.test(String(body.client || '')) ? String(body.client) : null;
    const want = forClient ? new Set(Array.from(links.values()).filter((l) => l.client === forClient).map((l) => Number(l.contact))) : null;
    if (want && !want.size) return json({ ok: true, today, send: scope.send === true, all: scope.all === true, linked: false, rows: [], reminders: [] }, 200, origin);
    /* A colleague who sees no linked client and not every contact reads
       nothing from Bukku (review 2026-10-29, 12). */
    if (!want && !links.size && scope.all !== true) return json({ ok: true, today, send: scope.send === true, all: false, rows: [], reminders: [] }, 200, origin);
    const all = (await unpaid(want ? Array.from(want) : undefined)).filter((inv) => {
      const c = Number(inv.contact_id);
      return want ? want.has(c) : mayContact(c);
    });
    const first = all.map((inv) => overdueOf(inv, today));
    const whole = await manyInvoices(all.filter((_, i) => first[i] === undefined).map((inv) => Number(inv.id)));
    const out: any[] = [];
    let w = 0;
    for (let i = 0; i < all.length; i++) {
      const inv = all[i];
      const c = Number(inv.contact_id);
      let od = first[i];
      let src = inv;
      if (od === undefined) {
        src = whole[w++];
        od = src ? overdueOf({ ...inv, ...src }, today) : null;
        if (od === undefined) od = overdueWhole({ ...inv, ...src }, today);
      }
      if (!od && want && src) od = dueOf({ ...inv, ...src });
      if (!od) continue;
      const l = lineOf({ ...inv, ...src, contact_email: inv.contact_email, short_link: inv.short_link || src.short_link }, od, today);
      const link = links.get(c);
      if (link) Object.assign(l, { client: link.client, client_name: link.name, client_code: link.code, client_slug: link.slug, to: link.to });
      else l.contact_email = l.contact_email || '';
      out.push(l);
    }
    out.sort((a, b) => b.days - a.days || a.number.localeCompare(b.number));
    const contacts = Array.from(new Set(out.map((l) => l.contact)));
    const rem = contacts.length ? await db.rpc('invoice_reminders', { p_contacts: contacts }) : { data: { rows: [] } };
    return json({ ok: true, today, send: scope.send === true, all: scope.all === true, rows: out,
      reminders: (rem.data && rem.data.rows) || [] }, 200, origin);
  }

  // action === 'remind'
  if (scope.send !== true) return json({ error: 'denied' }, 200, origin);
  if (!secret('RESEND_API_KEY')) return json({ error: 'mail-not-set-up' }, 200, origin);
  const contact = Number(body.contact);
  const ids = Array.isArray(body.invoices) ? body.invoices.map(Number).filter((n: number) => n > 0) : [];
  if (!(contact > 0) || !ids.length || ids.length > 50) return json({ error: 'bad-request' }, 400, origin);
  if (!mayContact(contact)) return json({ error: 'denied' }, 200, origin);
  /* What is left out is said for what it is: paid, voided in Bukku, or
     not yet due (review 2026-10-29, 6: a voided invoice read as paid). */
  const lines: any[] = [], paid: string[] = [], voided: string[] = [], notDue: string[] = [];
  const uniq = Array.from(new Set(ids)) as number[];
  const read = await manyInvoices(uniq);
  for (let i = 0; i < uniq.length; i++) {
    const inv = read[i], id = uniq[i];
    if (!inv || Number(inv.contact_id) !== contact) return json({ error: 'bad-request' }, 400, origin);
    let od = overdueOf(inv, today);
    if (od === undefined) od = overdueWhole(inv, today);
    if (!od) {
      const no = String(inv.number || id);
      if (inv.status && inv.status !== 'ready') voided.push(no);
      else if (!(cents(inv.balance) > 0)) paid.push(no);
      else notDue.push(no);
      continue;
    }
    lines.push(lineOf(inv, od, today));
  }
  const left = { paid, voided, not_due: notDue };
  if (!lines.length) return json({ error: 'nothing-overdue', ...left }, 200, origin);
  lines.sort((a, b) => a.due.localeCompare(b.due) || a.number.localeCompare(b.number));
  const link = links.get(contact);
  const bc = await bukku('GET', `/contacts/${contact}`).then((r) => (r && r.contact) || null).catch(() => null);
  const svc = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const begun = await svc.rpc('invoice_email_begin', {
    p_actor: scope.me && scope.me.id, p_client: link ? link.client : null, p_contact: contact,
    p_name: String((bc && (bc.legal_name || bc.other_name)) || lines[0].contact_name || ''),
    p_email: String((bc && bc.email) || lines[0].contact_email || ''),
    p_invoices: lines.map((l) => ({ id: l.id, number: l.number, date: l.date, due: l.due, amount: l.amount, currency: l.currency,
      link: l.link, part: l.part })),
    p_cc: body.cc !== false, p_subject: String(body.subject || ''), p_body: String(body.body || ''), p_again: body.again === true });
  if (begun.error) return json({ error: 'needs-update' }, 200, origin);
  const b = begun.data || {};
  if (b.error) return json({ ...b, ...left }, 200, origin);
  const heading = String(b.subject || '').split(/\s+·\s+/)[0].trim() || 'Payment reminder';
  const html = layout({ heading, body: String(b.body || ''), preheader: String(b.subject || ''), block: invoiceTable(lines),
    fine: [String(b.legal || ''), String(b.disclaimer || '')] });
  const text = String(b.body || '').replace(/\{\s*invoices\s*\}/i, lines.map((l) => l.number + '  ' + money(l.amount, l.currency) +
    '  due ' + day(l.due) + (l.link ? '  ' + l.link : '')).join('\n'));
  const msg: Record<string, unknown> = { from: FIN_FROM(), to: [String(b.to || '')], reply_to: FIN_REPLY(),
    subject: String(b.subject || ''), html, text };
  if (b.cc) msg.cc = [String(b.cc)];
  const sent = await resend(msg, String(b.id), secret('RESEND_API_KEY'));
  const done = await svc.rpc('invoice_email_done', { p_id: b.id, p_status: sent.status, p_provider: sent.provider || null, p_error: sent.error || null });
  if (done.error) console.error('bukku-sync: reminder not closed', done.error.message);
  if (sent.status !== 'sent') console.error('bukku-sync: reminder', sent.status, sent.error);
  return json(sent.status === 'sent' ? { ok: true, id: b.id, to: b.to, cc: b.cc || null, ...left }
    : { error: sent.status === 'unknown' ? 'not-confirmed' : 'not-sent', ...left }, 200, origin);
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

    /* The tax codes Bukku bills with (2026-10-22), read for the Settings
       page's Tax codes: read only, nothing written in Bukku. The page keeps
       them through tax_codes_save. Asked of bukku_config, as 'fields' is, so
       a colleague at View alone never has the company's token used for them
       (2026-10-22, BE-12). */
    if (action === 'taxes') {
      const me = await db.rpc('bukku_config');
      if (me.error) return json({ error: 'needs-update' }, 200, origin);
      if (me.data && me.data.error) return json({ error: me.data.error }, 200, origin);
      const r = await bukku('POST', '/v2/lists', { lists: ['tax_codes'], params: {} });
      const raw = (r && r.tax_codes) || [];
      const items = Array.isArray(raw) ? raw : (raw.items || raw.data || []);
      const list = items.map((t: any) => {
        const rate = Number(t.rate ?? t.tax_rate ?? t.percentage ?? t.value);
        return {
          code: String(t.code ?? t.name ?? '').trim().slice(0, 30),
          name: String(t.description ?? t.name ?? '').trim().slice(0, 80),
          rate: isFinite(rate) ? Math.round(rate * 100) / 100 : null,
          active: !(t.is_archived || t.archived || t.is_active === false || t.active === false),
          bukku_id: t.id != null ? String(t.id) : null
        };
      }).filter((t: any) => t.code && /^[A-Za-z0-9._ -]{1,30}$/.test(t.code) && t.rate != null && t.rate >= 0 && t.rate <= 100);
      return json({ ok: true, codes: list }, 200, origin);
    }

    if (action === 'invoices' || action === 'remind') return await invoiceAction(action, body, db, origin);
    if (action === 'contacts' || action === 'contact') return await contactsAction(action, body, db, origin);

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
    /* A linked record is sent to its own contact alone, and a contact
       another record holds is never written over (BE-2, 2026-10-22). */
    if (contact !== null && p.contact_id && contact !== Number(p.contact_id)) return json({ error: 'linked' }, 200, origin);
    if (contact !== null && (action === 'send' || action === 'link')) {
      const free = await db.rpc('bukku_contact_check', { p_kind: kind, p_id: id, p_contact: contact });
      if (free.error) return json({ error: 'needs-update' }, 200, origin);
      if (free.data && free.data.error) return json({ error: free.data.error }, 200, origin);
    }
    const cur = contact ? await bukku('GET', `/contacts/${contact}`).then((r) => r && r.contact)
      .catch((e) => { if (e instanceof BukkuError && e.status === 404) return null; throw e; }) : null;
    if (contact && !cur) return json({ error: 'bukku-gone' }, 200, origin);
    const code = cur ? cur.contact_code : nextCode(await allContacts(), p.legal_name);
    const terms = p.payment_term ? await termsOf() : [];
    const next = merged(p, cur, code, termFor(terms, p.payment_term));

    /* Link only (2026-10-19): the contact as Bukku holds it, linked and
       nothing sent. */
    if (action === 'link') {
      if (!cur) return json({ error: 'bad-request' }, 400, origin);
      const l = await db.rpc('bukku_link_only', { p_kind: kind, p_id: id, p_contact: cur.id, p_code: cur.contact_code || code });
      if (l.error) return json({ error: 'needs-update' }, 200, origin);
      if (l.data && l.data.error) return json({ error: l.data.error }, 200, origin);
      return json({ ok: true, contact: cur.id, code: cur.contact_code || code, linked: true }, 200, origin);
    }
    if (action === 'preview') {
      return json({ ok: true, code, rows: rowsOf(p, cur, next, terms) }, 200, origin);
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
