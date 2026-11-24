/*
 * bukku-sync — sends a client's billing or a supplier's details to Bukku as
 * one contact, by hand (2026-10-18; 2026-10-18-bukku-contacts.sql), and a
 * colleague as an employee (kind `member`, 2026-11-17).
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
 *   POST { action: 'read', kind, id }         a linked client's or billing
 *                                             entity's billing read from
 *                                             Bukku into the portal
 *                                             (2026-10-30, BILLING FROM
 *                                             BUKKU): taken where the link
 *                                             is held, else what differs.
 *                                             A supplier's (2026-11-22) is
 *                                             compared alone, never taken.
 *   POST { action: 'hold', kind, id }         Use Bukku's: the same, taken
 *                                             and held (Work); a supplier
 *                                             takes what differs.
 *   POST { action: 'save', kind, id, values, expected }
 *                                             the Billing sheet's changes
 *                                             saved straight to Bukku, then
 *                                             read back into the portal;
 *                                             refused `stale` where Bukku
 *                                             moved since it was read.
 *   POST { action: 'match-creators' }         with the wake secret: each creator
 *                                             with approved payment details and
 *                                             no link, matched to a Bukku contact
 *                                             by ID number, else name; read only.
 *   POST { action: 'nightly' }                every held link read again
 *                                             (pg_cron at 00:30 MYT, with
 *                                             the wake secret).
 *   POST { action: 'contacts' }               Bukku's customers the
 *                                             colleague may add, read once
 *                                             as Add entity opens and
 *                                             filtered on the page; those
 *                                             the portal links marked held.
 *                                             With q, only those matching
 *                                             every word typed or the
 *                                             registration no. (a tab
 *                                             opened before 2026-10-30).
 *   POST { action: 'adopt', client, contact } one of them added to the
 *                                             client as a billing entity,
 *                                             linked and held in one step.
 *   POST { action: 'send', kind: 'entity', id, guard: true }
 *                                             a new entity made in Bukku,
 *                                             unless Bukku holds a customer
 *                                             of its registration no.,
 *                                             which is linked instead.
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
 *   POST { action: 'payments' }               Clients' Payments view's Read
 *                                             from Bukku (2026-11-19): asked
 *                                             as the caller
 *                                             (`payment_analysis`), the 24
 *                                             months' invoices and suppliers'
 *                                             bills read for 25 seconds and
 *                                             kept (`bukku_docs_take`); the
 *                                             nightly run reads them too.
 *   POST { action: 'supplierbills' }          Suppliers' Payments view's
 *                                             Read from Bukku (2026-11-22):
 *                                             asked as the caller
 *                                             (`supplier_bills`, Suppliers
 *                                             Work), the suppliers' bills
 *                                             read for 25 seconds and kept.
 *   POST { action: 'supplierbilllink', id }  a supplier bill's page in
 *                                             Bukku, where the caller reads
 *                                             that bill (Suppliers View).
 *   POST { action: 'bills', creator }        a creator's Bukku bills (2026-11-09,
 *                                             CREATOR PAYMENTS): read from the
 *                                             creator's linked contact, kept
 *                                             through `creator_bills_take` (the
 *                                             service role's), each matched to
 *                                             the booking whose Job reference
 *                                             or earlier job it names, Paid
 *                                             where no balance stands; answers
 *                                             `creator_bills_list` as the
 *                                             caller. Read again every night.
 *   POST { action: 'remind', contact, invoices, cc, to?, ccs?, subject, body, again }
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
 *                                             from the finance sender, replying
 *                                             to the finance mailbox (Settings,
 *                                             Messages: Reply-to mailboxes).
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
import { esc, FONT, layout, resend, sender } from '../_shared/mail.ts';

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
    /* Bukku's reason field by field where it gives one, never only "The
       given data was invalid." (2026-11-10). */
    const errs = data && data.errors && typeof data.errors === 'object'
      ? Object.values(data.errors).flat().map((x) => String(x)).filter(Boolean).slice(0, 3).join(' ') : '';
    const msg = (data && (errs || data.message)) || text.slice(0, 300);
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

const STATES = ['Wilayah Persekutuan Kuala Lumpur', 'Wilayah Persekutuan Labuan', 'Wilayah Persekutuan Putrajaya',
  'Johor', 'Kedah', 'Kelantan', 'Melaka', 'Malacca', 'Negeri Sembilan', 'Pahang', 'Penang', 'Pulau Pinang', 'Perak',
  'Perlis', 'Sabah', 'Sarawak', 'Selangor', 'Terengganu', 'Kuala Lumpur', 'Labuan', 'Putrajaya'];
/* A state as Bukku names it (2026-11-10: Bukku refused Penang, "The given
   data was invalid"; it holds the LHDN list's names). */
const STATE_AS: Record<string, string> = { 'penang': 'Pulau Pinang', 'malacca': 'Melaka',
  'kuala lumpur': 'Wilayah Persekutuan Kuala Lumpur', 'labuan': 'Wilayah Persekutuan Labuan',
  'putrajaya': 'Wilayah Persekutuan Putrajaya' };
const stateAs = (v: string | null) => v ? (STATE_AS[v.toLowerCase()] || v) : v;
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
  return { street: street.slice(0, 255), postcode: pc, city: city && city.length <= 50 ? city : null, state: stateAs(state), country_code: country };
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
  const nricHid = /INDIVIDUAL$/.test(String(p.entity_type || '')) && !p.reg_no;
  const list: [string, string, string, string][] = [
    ['legal_name', p.kind === 'creator' ? 'Legal name' : 'Registered Company Name', c.legal_name || '', next.legal_name || ''],
    /* An individual's registration no. is an NRIC: one the colleague may
       not send (no reg_no prepared) is not read from Bukku either. */
    ['reg_no', 'Business Registration No.', nricHid ? '' : c.reg_no || '', nricHid ? '' : next.reg_no || ''],
    ['old_reg_no', 'Old Registration No.', c.old_reg_no || '', next.old_reg_no || ''],
    ['tax_id_no', 'TIN', c.tax_id_no || '', next.tax_id_no || ''],
    ['sst_reg_no', 'SST Registration No.', c.sst_reg_no || '', next.sst_reg_no || ''],
    ['email', 'Email', c.email || '', next.email || ''],
    ['phone_no', 'Phone', c.phone_no || '', next.phone_no || ''],
    ['person', 'Billing contact', person(c), person(next)],
    ['address', 'Billing address', addr(c), addr(next)],
    ['term', 'Payment term', termName(c.default_term_id), termName(next.default_term_id)],
    ['our_id', p.kind === 'supplier' ? 'Supplier ID' : p.kind === 'creator' ? 'Creator ID' : 'Client ID', idOf(c), idOf(next)],
    ['types', 'Type', (c.types || []).map((t: string) => T[t] || t).join(', '), (next.types || []).map((t: string) => T[t] || t).join(', ')]
  ];
  /* An existing contact's change is chosen field by field (2026-11-10, the
     user: "choose which one to send"); the type is always sent. */
  return list.filter(([key]) => key !== 'our_id' || !!p.field_id).map(([key, field, now, after]) => ({ key, field, now, after, same: now === after,
    pick: !!cur && key !== 'types' }));
}

/* The fields left unticked kept as Bukku holds them. */
const KEEP: Record<string, string[]> = { legal_name: ['legal_name'], reg_no: ['reg_no', 'reg_no_type'],
  old_reg_no: ['old_reg_no'], tax_id_no: ['tax_id_no'], sst_reg_no: ['sst_reg_no'], email: ['email'], phone_no: ['phone_no'],
  person: ['contact_persons'], address: ['addresses'], term: ['default_term_id'], our_id: ['fields'] };
export function keepAsHeld(next: Record<string, any>, cur: any, skip: unknown): Record<string, any> {
  if (!cur || !Array.isArray(skip)) return next;
  const out = { ...next };
  // Lists in the shape a send writes them (merged's own), as Bukku holds them.
  const held = merged({}, cur, cur.contact_code || '');
  for (const k of skip) for (const f of KEEP[String(k)] || []) {
    const v = ['contact_persons', 'addresses', 'fields'].includes(f) ? held[f] : cur[f];
    if (v === undefined || v === null) delete out[f]; else out[f] = v;
  }
  return out;
}

/* A send with fields left unticked: those fields stay the portal's own and
   are never copied back from Bukku. Where one still differs, the link is
   not held: it reads Differs from Bukku and the person chooses (audit
   2026-11-11). Answers the fields to take, or null to take nothing. */
const KEPT_BILL: Record<string, string[]> = { legal_name: ['legal_name'], reg_no: ['company_no'],
  old_reg_no: ['company_no_old'], tax_id_no: ['tin'], sst_reg_no: ['sst_no'], email: ['finance_email'],
  person: ['person'], address: ['billing_address'] };
export function takeAfterSend(changed: string[], skip: unknown): string[] | null {
  const kept = new Set((Array.isArray(skip) ? skip : []).flatMap((k) => KEPT_BILL[String(k)] || []));
  return changed.some((f) => kept.has(f)) ? null : changed;
}


// ---- Billing from Bukku (2026-10-30) ---------------------------------------
/* Once linked, Bukku holds a client's or an entity's billing (the user,
   2026-10-29: "we dont need two sides update"). What Bukku holds of a
   contact, read as the portal's billing: the default billing address and
   person, the registered name in capitals. */
export function valuesOf(c: any) {
  const s = (v: unknown) => { const x = String(v ?? '').replace(/\s+/g, ' ').trim(); return x || null; };
  const ba = (c.addresses || []).find((a: any) => a.is_default_billing) || null;
  const bp = (c.contact_persons || []).find((x: any) => x.is_default_billing) || null;
  const name = s(c.legal_name), mail = s(c.email);
  return { legal_name: name ? name.toUpperCase() : null, company_no: s(c.reg_no), company_no_old: s(c.old_reg_no),
    tin: s(c.tax_id_no), sst_no: s(c.sst_reg_no), finance_email: mail ? mail.toLowerCase() : null,
    billing_address: s(addressLine(ba)), person: s(bp ? [bp.first_name, bp.last_name].filter(Boolean).join(' ') : '') };
}
const BILL = ['legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no', 'person', 'finance_email', 'billing_address'];
/* The fields a record compares (2026-11-22): a supplier names its own
   (`bukku_portal` `fields`: never an individual's NRIC, no old
   registration no.), a client and an entity every one. */
export function fieldsOf(portal: any): string[] {
  return portal && Array.isArray(portal.fields) ? BILL.filter((f) => portal.fields.includes(f)) : BILL;
}
/* Bukku's values held to those fields: what a record does not compare is
   never answered to the page nor taken. */
export function onlyFields(vals: Record<string, any>, portal: any): Record<string, any> {
  const keep = fieldsOf(portal), out: Record<string, any> = {};
  for (const f of keep) out[f] = vals[f] ?? null;
  return out;
}
/* The fields in which the portal and Bukku differ, each read as Bukku sets
   it out: an address in its parts, a registration no. by its letters and
   digits, a person with or without the salutation Bukku keeps, and a
   person whose every word Bukku's name holds (Angel against Angel Lim:
   Send keeps Bukku's whole name, 2026-10-30). */
export function differs(portal: any, bk: any, country: string): string[] {
  const out: string[] = [];
  const bare = (v: unknown) => { const w = nameWords(v); return w.slice(salLead(w)).join(' '); };
  for (const f of fieldsOf(portal)) {
    const a = String(portal[f] ?? '').trim(), b = String(bk[f] ?? '').trim();
    let same: boolean;
    if (!a || !b) same = !a && !b;
    else if (f === 'billing_address') same = sameAddress(addressOf(a, country), addressOf(b, country));
    else if (f === 'company_no') same = digits(a) === digits(b);
    else if (f === 'person') {
      const ours = nameWords(a), theirs = nameWords(b).slice(salLead(nameWords(b)));
      same = ours.join(' ') === nameWords(b).join(' ') || bare(a) === bare(b) ||
        (ours.slice(salLead(ours)).length > 0 && ours.slice(salLead(ours)).every((w) => theirs.includes(w)));
    }
    else if (f === 'finance_email') same = a.toLowerCase() === b.toLowerCase();
    else same = a.replace(/\s+/g, ' ').toUpperCase() === b.replace(/\s+/g, ' ').toUpperCase();
    if (!same) out.push(f);
  }
  return out;
}
/* A read's print: a save is refused where Bukku moved since. */
export async function hashOf(v: Record<string, unknown>): Promise<string> {
  const text = JSON.stringify(BILL.map((f) => v[f] ?? null));
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
const svcDb = () => createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function contactOf(id: number): Promise<any | null> {
  return bukku('GET', `/contacts/${id}`).then((r) => (r && r.contact) || null)
    .catch((e) => { if (e instanceof BukkuError && e.status === 404) return null; throw e; });
}
/* Bukku's details into the record (`bukku_take`, the service role's). */
async function take(actor: unknown, kind: string, id: string, vals: any, hash: string, changed: string[], mode: string) {
  const t = await svcDb().rpc('bukku_take', { p_actor: actor || null, p_kind: kind, p_id: id, p_values: vals, p_hash: hash,
    p_changed: changed, p_mode: mode });
  if (t.error) { console.error('bukku-sync: not taken', kind, id, t.error.message); return { error: 'not-filed' }; }
  return t.data || { error: 'not-filed' };
}

async function billingAction(action: string, kind: string, id: string, body: Record<string, any>, db: any, origin: string | null): Promise<Response> {
  const may = await db.rpc('bukku_read_may', { p_kind: kind, p_id: id, p_level: action === 'read' ? 'view' : 'work' });
  if (may.error) return json({ error: 'needs-update' }, 200, origin);
  const d = may.data || {};
  if (d.error) return json({ error: d.error }, 200, origin);
  if (!d.linked) return json({ ok: true, linked: false }, 200, origin);
  const portal = d.portal || {}, country = portal.country === 'SG' ? 'SG' : 'MY';

  if (action === 'save') {
    if (!d.held) return json({ error: 'not-held' }, 200, origin);
    const values = body.values && typeof body.values === 'object' && !Array.isArray(body.values) ? body.values : null;
    if (!values || !Object.keys(values).length) return json({ error: 'bad-request' }, 400, origin);
    const pw = await db.rpc('bukku_prepare_with', { p_kind: kind, p_id: id, p_values: values });
    if (pw.error) return json({ error: 'needs-update' }, 200, origin);
    const p = pw.data as Prep;
    if (!p || p.error) return json(p || { error: 'bad-request' }, 200, origin);
    const cur = await contactOf(Number(d.contact_id));
    if (!cur) return json({ error: 'bukku-gone' }, 200, origin);
    const before = valuesOf(cur);
    /* Changed in Bukku since the sheet was opened: read in, nothing sent. */
    if (!body.expected || await hashOf(before) !== String(body.expected)) {
      const ch = differs(portal, before, country);
      const t = await take(d.me, kind, id, before, await hashOf(before), ch, 'read');
      return json({ error: 'stale', changed: ch, values: before, hash: await hashOf(before), person_in: t.person_in }, 200, origin);
    }
    /* Only what the sheet changed goes; every other detail is Bukku's own. */
    const has = (k: string) => Object.prototype.hasOwnProperty.call(values, k);
    const p2: Prep = Object.assign({}, p, {
      legal_name: has('legal_name') ? p.legal_name : cur.legal_name,
      reg_no: has('company_no') ? p.reg_no : cur.reg_no, reg_no_type: has('company_no') ? p.reg_no_type : cur.reg_no_type,
      old_reg_no: has('company_no_old') ? p.old_reg_no : cur.old_reg_no, tax_id_no: has('tin') ? p.tax_id_no : cur.tax_id_no,
      sst_reg_no: has('sst_no') ? p.sst_reg_no : cur.sst_reg_no, email: has('finance_email') ? p.email : cur.email,
      address: has('billing_address') ? p.address : null, person: has('bill_contact_id') ? p.person : null,
      salutation: has('bill_contact_id') ? p.salutation : null, phone_no: cur.phone_no, other_name: cur.other_name
    });
    const next = merged(p2, cur, cur.contact_code);
    for (const k of (Array.isArray(p.clear) ? p.clear : [])) delete next[k];
    if (Array.isArray(p.clear) && p.clear.includes('reg_no')) delete next.reg_no_type;
    const r = await bukku('PUT', `/contacts/${cur.id}`, next);
    const saved = r && r.contact;
    if (!saved || !saved.id) return json({ error: 'bukku-refused', message: 'Bukku did not return the contact. Please try again.' }, 200, origin);
    const after = valuesOf(saved), hash = await hashOf(after);
    const ch = differs(portal, after, country);
    const t = await take(d.me, kind, id, after, hash, ch, 'save');
    if (t.error) return json({ error: t.error }, 200, origin);
    return json({ ok: true, held: true, code: saved.contact_code || d.code, values: after, hash, changed: ch, person_in: t.person_in }, 200, origin);
  }

  // read, hold
  const cur = await contactOf(Number(d.contact_id));
  if (!cur) return json({ error: 'bukku-gone', code: d.code }, 200, origin);
  const vals = onlyFields(valuesOf(cur), portal), hash = await hashOf(vals);
  const ch = differs(portal, vals, country);
  const t = await take(d.me, kind, id, vals, hash, ch, action === 'hold' ? 'hold' : 'read');
  if (t.error) return json({ error: t.error }, 200, origin);
  return json({ ok: true, linked: true, held: t.held === true, code: cur.contact_code || d.code, read_at: new Date().toISOString(), hash,
    values: vals, changed: t.held ? ch : [], person_in: t.person_in,
    differs: t.held ? [] : ch.map((f) => ({ field: f, portal: portal[f] ?? null, bukku: (vals as any)[f] ?? null })) }, 200, origin);
}

/* The nightly run (pg_cron at 00:30 MYT), 100 seconds in all. Creators'
   bills and the months' invoices go first, each with its share of the time,
   then every held link is read again, the oldest first, in what is left:
   at a few hundred links the reads took the whole run and the bills and
   invoices none (audit 2026-11-15). The run writes a beat when it ends
   (`job_beat`), which the admins' morning check reads. */
async function nightly(req: Request, origin: string | null): Promise<Response> {
  const svc = svcDb();
  const ok = await svc.rpc('wake_secret_ok', { p_given: req.headers.get('x-adspace-wake') || '' });
  if (ok.error || ok.data !== true) return json({ error: 'unauthorised' }, 401, origin);
  const began = Date.now(), until = began + 100000;
  let stop = '';
  const halt = (e: unknown) => {
    if (e instanceof BukkuError && (e.code === 'bukku-token' || e.code === 'bukku-unreachable')) {
      stop = e.code === 'bukku-token' ? "Bukku refused the portal's connection" : 'Bukku did not respond';
    }
    return !!stop;
  };
  /* Creators' bills (2026-11-09): each creator with a booking posted and not
     yet read Paid, in the first 35 seconds. */
  let bills = 0;
  const due = await svc.rpc('creator_bills_due');
  for (const d of ((due.data || []) as any[])) {
    if (stop || Date.now() > began + 35000) break;
    try { const r = await creatorBills(String(d.creator), Number(d.contact)); if (!r.error) bills++; }
    catch (e) {
      console.error('bukku-sync: nightly bills', d.creator, String((e as Error).message || e));
      if (halt(e)) break;
    }
  }
  /* Months not yet matched to their invoice (2026-11-10), up to 60 seconds. */
  let months = 0;
  const mdue = stop ? { data: [], error: null } : await svc.rpc('ops_month_invoices_due');
  for (const m of ((mdue.data || []) as any[])) {
    if (stop || Date.now() > began + 60000) break;
    try {
      const found = await monthInvoices((m.contacts || []).map(Number), String(m.from), String(m.to));
      const t = await svc.rpc('ops_month_invoice_take', { p_engagement: m.engagement, p_invoices: found });
      if (!t.error) months++;
    } catch (e) {
      console.error('bukku-sync: nightly month', m.engagement, String((e as Error).message || e));
      if (halt(e)) break;
    }
  }
  /* Payment patterns (2026-11-19): the invoices' and suppliers' bills'
     history, up to 80 seconds. */
  let history = '';
  for (const kind of ['invoice', 'bill'] as const) {
    if (stop) break;
    try { const h = await payHistory(kind, began + (kind === 'invoice' ? 74000 : 80000)); if (h.error) history = h.error; }
    catch (e) {
      console.error('bukku-sync: nightly history', kind, String((e as Error).message || e));
      history = 'failed';
      if (halt(e)) break;
    }
  }
  /* Every held link read again, the oldest first, in the time left. */
  const list = await svc.rpc('bukku_held_links');
  const rows = (list.data || []) as any[];
  let read = 0, failed = 0;
  for (const l of rows) {
    if (stop || Date.now() > until) break;
    try {
      const cur = await contactOf(Number(l.contact_id));
      if (!cur) { failed++; continue; }
      const vals = valuesOf(cur), portal = l.portal || {};
      const t = await take(null, l.kind, l.id, vals, await hashOf(vals), differs(portal, vals, portal.country === 'SG' ? 'SG' : 'MY'), 'read');
      if (t.error) failed++; else read++;
    } catch (e) {
      failed++;
      console.error('bukku-sync: nightly', l.kind, l.id, String((e as Error).message || e));
      if (halt(e)) break;
    }
  }
  const bad = stop || (list.error || due.error || mdue.error ? 'the database did not answer' : '') ||
    (history ? 'the payment history was not saved' : '');
  await svc.rpc('job_beat', { p_job: 'bukku-nightly', p_ok: !bad, p_detail: bad || null });
  if (list.error) return json({ error: 'needs-update' }, 200, origin);
  return json({ ok: true, read, failed, left: rows.length - read - failed, bills, months, history: history || 'ok' }, 200, origin);
}

// ---- Creators to their Bukku contacts (2026-11-11) --------------------------
/* The creators brought in from the AP01 form were paid through Bukku before
   the portal: each holding approved payment details and no Bukku link of
   its own is matched to the contact whose registration no. is its ID
   number, else the one contact whose name is its legal name; a contact
   another record links is said, never offered. Read only: the links are
   made from the list by hand. */
export function creatorMatches(reqs: any[], creators: any[], links: any[], contacts: any[]) {
  const linked = new Set(links.filter((l) => l.kind === 'creator').map((l) => String(l.record_id)));
  const taken = new Map<number, string>(links.map((l) => [Number(l.contact_id), String(l.kind)]));
  const latest = new Map<string, any>();
  for (const r of reqs) {
    const k = String(r.creator_id), had = latest.get(k);
    if (!had || String(r.decided_at || '') > String(had.decided_at || '')) latest.set(k, r);
  }
  const live = contacts.filter((c) => c && c.id && !c.is_archived);
  const out: any[] = [];
  for (const cr of creators) {
    const r = latest.get(String(cr.id));
    if (!r || linked.has(String(cr.id))) continue;
    const id = digits(r.id_no), name = words(r.legal_name);
    let hits = id.length >= 6 ? live.filter((c) => digits(c.reg_no) === id) : [];
    let why = 'id';
    if (!hits.length && name) { hits = live.filter((c) => words(c.legal_name) === name || words(c.other_name) === name); why = 'name'; }
    if (hits.length > 1) {
      const sup = hits.filter((c) => (c.types || []).includes('supplier'));
      if (sup.length === 1) hits = sup;
    }
    const one = hits.length === 1 ? hits[0] : null;
    out.push({ creator: cr.id, code: cr.creator_code, name: r.legal_name, why: one ? why : hits.length ? 'several' : 'none',
      contact: one ? Number(one.id) : null, contact_code: one ? one.contact_code || null : null,
      contact_name: one ? one.legal_name || null : null, supplier: one ? (one.types || []).includes('supplier') : null,
      taken: one && taken.has(Number(one.id)) ? taken.get(Number(one.id)) : null,
      several: hits.length > 1 ? hits.slice(0, 5).map((c) => c.contact_code || String(c.id)) : undefined });
  }
  return out.sort((a, b) => String(a.code).localeCompare(String(b.code)));
}
async function matchCreators(req: Request, origin: string | null): Promise<Response> {
  const svc = svcDb();
  const ok = await svc.rpc('wake_secret_ok', { p_given: req.headers.get('x-adspace-wake') || '' });
  if (ok.error || ok.data !== true) return json({ error: 'unauthorised' }, 401, origin);
  /* Every row, a thousand at a time: PostgREST answers a thousand at most,
     and a list cut short would offer a contact already linked (audit
     2026-11-11). */
  const every = async (make: () => any, keys: string[]) => {
    const out: any[] = [];
    for (let at = 0; ; at += 1000) {
      let q = make();
      for (const k of keys) q = q.order(k, { ascending: true });
      const r = await q.range(at, at + 999);
      if (r.error) return { data: null, error: r.error };
      out.push(...(r.data || []));
      if ((r.data || []).length < 1000) return { data: out, error: null };
    }
  };
  const [reqs, crs, lks] = await Promise.all([
    every(() => svc.from('creator_pay_requests').select('creator_id, id_no, legal_name, decided_at').eq('status', 'approved'), ['id']),
    every(() => svc.from('creators').select('id, creator_code'), ['id']),
    every(() => svc.from('bukku_links').select('kind, record_id, contact_id'), ['kind', 'record_id'])
  ]);
  if (reqs.error || crs.error || lks.error) return json({ error: 'needs-update' }, 200, origin);
  const rows = creatorMatches(reqs.data || [], crs.data || [], lks.data || [], await allContacts());
  return json({ ok: true, rows }, 200, origin);
}

/* Bukku's reference no. (`number2`) alone, as a list draws it beside the
   number: `AB2609081 / Reference: XXXX` (2026-11-23). */
export function refNo(x: any): string {
  return String((x && x.number2) || '').trim().slice(0, 60);
}

// ---- A creator's bills (2026-11-09, CREATOR PAYMENTS) -------------------------
/* Every purchase bill of the creator's Bukku contact, a hundred a page, its
   reference read where Bukku keeps it (the bill's reference no., else its
   description or remarks); a void bill is left out, a draft kept as one
   (2026-11-13: Create bill makes drafts, read Draft in Bukku). */
export function billOf(x: any) {
  const ref = [x.number2, x.reference, x.title, x.description, x.remarks].filter((v) => v != null && String(v).trim() !== '')
    .map((v) => String(v).trim()).join(' ').slice(0, 200);
  return { id: Number(x.id), number: String(x.number || ''), ref, ref_no: refNo(x), date: /^\d{4}-\d{2}-\d{2}$/.test(String(x.date || '')) ? String(x.date) : null,
    amount: cents(x.amount), balance: x.balance == null || x.balance === '' ? null : cents(x.balance),
    currency: /^[A-Z]{3}$/.test(String(x.currency_code || '')) ? String(x.currency_code) : 'MYR',
    draft: String(x.status || '') === 'draft' };
}
/* The latest date among the payments, credits and refunds Bukku applied
   to a bill (its `linked_items` that are not bills), else null. A sales
   invoice's the same, `self` naming what is no payment (2026-11-19). */
export function paidOn(bill: any, self: RegExp = /bill/): string | null {
  const ds = ((bill && bill.linked_items) || [])
    .filter((l: any) => l && !self.test(String(l.type || '')) && /^\d{4}-\d{2}-\d{2}$/.test(String(l.date || '')))
    .map((l: any) => String(l.date)).sort();
  return ds.length ? ds[ds.length - 1] : null;
}
/* `made`: a bill Create bill just made, by Bukku's own ID, held to its
   booking from then on (`made_for`), whatever its reference reads later. */
async function creatorBills(creator: string, contact: number, made?: { id: number; option: string }): Promise<any> {
  const out: any[] = [];
  for (let page = 1; page <= 20; page++) {
    const r = await bukku('GET', `/purchases/bills?contact_id=${contact}&page=${page}&page_size=100`);
    const rows = (r && r.transactions) || [];
    for (const x of rows) {
      if (!x || !x.id || Number(x.contact_id) !== contact) continue;
      if (x.status && !['draft', 'ready', 'paid'].includes(String(x.status))) continue;
      const b: any = billOf(x);
      if (made && b.id === made.id) b.made_for = made.option;
      out.push(b);
    }
    const per = Number(r && r.paging && r.paging.per_page) || rows.length || 100;
    const total = Number(r && r.paging && r.paging.total) || 0;
    if (!rows.length || page * per >= total || rows.length < per) break;
  }
  /* A paid bill's day is its payments' (2026-11-12, the user: "it should
     follow Bukku's bill payment voucher"): a bill read alone lists what was
     applied to it, each with its date; the latest is the day it was paid.
     Read once a bill, ten a run, so a night never reads a creator's whole
     history again. */
  const known = new Set<number>();
  try {
    const kept = await svcDb().from('creator_bills').select('bill_id').eq('creator_id', creator).not('paid_on', 'is', null);
    for (const k of ((kept && kept.data) || []) as any[]) known.add(Number(k.bill_id));
  } catch (_e) { /* none known: the day is read again, ten a run */ }
  let asked = 0;
  for (const b of out) {
    if (asked >= 10 || b.draft || b.balance == null || b.balance > 0 || known.has(b.id)) continue;
    asked++;
    try { b.paid_on = paidOn(await bukku('GET', `/purchases/bills/${b.id}`).then((r: any) => (r && r.transaction) || null)); }
    catch (_e) { /* left for the next read */ }
  }
  const t = await svcDb().rpc('creator_bills_take', { p_creator: creator, p_contact: contact, p_rows: out });
  if (t.error) { console.error('bukku-sync: bills not kept', creator, t.error.message); return { error: 'not-filed' }; }
  return t.data || { error: 'not-filed' };
}

/* The chart of accounts flattened (parents and their children), the expense
   and cost of sales accounts alone, A to Z by code. */
export function expenseAccounts(raw: any): any[] {
  const top = Array.isArray(raw) ? raw : ((raw && (raw.items || raw.data)) || []);
  const out: any[] = [];
  const walk = (list: any[]) => {
    for (const a of list || []) {
      if (!a) continue;
      if (a.id && /expense|cost_of_sales/.test(String(a.type || '')) && !a.is_archived)
        out.push({ id: Number(a.id), code: String(a.code || ''), name: String(a.name || '').slice(0, 120), type: String(a.type) });
      if (Array.isArray(a.children)) walk(a.children);
    }
  };
  walk(top);
  return out.sort((x, y) => (x.code || x.name).localeCompare(y.code || y.name, 'en', { numeric: true }));
}
/* A bill of the contact already holding the Job reference, drafts included,
   so a second press, or one made by hand, is never made twice. */
async function billHolding(contact: number, ref: string): Promise<string | null> {
  const key = (v: unknown) => String(v ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const k = key(ref);
  if (k.length < 4) return null;
  const r = await bukku('GET', `/purchases/bills?search=${encodeURIComponent(ref)}&contact_id=${contact}&page=1&page_size=100`);
  for (const x of ((r && r.transactions) || []) as any[]) {
    if (!x || Number(x.contact_id) !== contact || String(x.status || '') === 'void') continue;
    if (key([x.number2, x.reference, x.title, x.description, x.remarks, x.number].join(' ')).includes(k)) return String(x.number || x.id);
  }
  return null;
}
/* The bill as Bukku's Create Bill takes it (2026-11-15, the user's example):
   on credit, the Job reference in its reference no., one line of the KOC fee
   item (found by its SKU) at the fee, on the account found by its code, with
   the classification code set, no tax, a draft for the team to post. */
export function billBody(p: any, item: any): Record<string, unknown> {
  const line: Record<string, unknown> = { account_id: Number(item.account_id), product_id: Number(item.product_id),
    description: billLine(p), unit_price: Number(p.amount), quantity: 1, classification_code: String(item.classification_code) };
  if (item.product_unit_id) line.product_unit_id = Number(item.product_unit_id);
  const out: Record<string, unknown> = {
    payment_mode: 'credit', contact_id: Number(p.contact_id), number2: String(p.ref).slice(0, 50), date: String(p.date),
    currency_code: p.currency === 'SGD' ? 'SGD' : 'MYR', exchange_rate: p.currency === 'SGD' ? Number(p.fx) : 1,
    tax_mode: 'exclusive', description: String(p.description || '').slice(0, 200),
    /* A draft for the team to check and post in Bukku, its e-Invoice action
       NORMAL (2026-11-13, the user: "Keep it normal and draft at bukku"). */
    status: 'draft', myinvois_action: 'NORMAL',
    form_items: [line]
  };
  if (p.due) out.due_date = String(p.due);
  return out;
}
/* The line's words: KOC Fee - Client: {brand} ({campaign}) ({creator}). */
export function billLine(p: any): string {
  return ('KOC Fee - Client: ' + String(p.client_name || '') + ' (' + String(p.campaign || '') + ') (' + String(p.creator_name || '') + ')').slice(0, 255);
}
/* The product of a SKU among Bukku's products, its base unit; archived left out. */
export function productOf(raw: any, sku: string): any {
  const list = Array.isArray(raw) ? raw : ((raw && (raw.products || raw.items || raw.data)) || []);
  const k = String(sku || '').trim().toUpperCase();
  const p = (list as any[]).find((x) => x && x.id && !x.is_archived && String(x.sku || '').trim().toUpperCase() === k);
  if (!p) return null;
  const units = (Array.isArray(p.units) ? p.units : []) as any[];
  const u = units.find((x) => x && x.is_base) || units[0];
  return { product_id: Number(p.id), product_unit_id: u && u.id ? Number(u.id) : null, has_units: units.length > 0 };
}
/* The account of a code in the chart of accounts, children included. */
export function accountOf(raw: any, code: string): number | null {
  const k = String(code || '').trim().toUpperCase();
  let hit: number | null = null;
  const walk = (list: any[]) => {
    for (const a of list || []) {
      if (!a || hit) continue;
      if (a.id && !a.is_archived && String(a.code || '').trim().toUpperCase() === k) { hit = Number(a.id); return; }
      if (Array.isArray(a.children)) walk(a.children);
    }
  };
  walk(Array.isArray(raw) ? raw : ((raw && (raw.items || raw.data)) || []));
  return hit;
}
/* The item a creator's bill is made on, from the Business settings the
   database answered: the product by its SKU, the account by its code. */
async function billItem(p: any): Promise<any> {
  const r = await bukku('GET', `/products?search=${encodeURIComponent(String(p.sku))}&page=1&page_size=100`);
  const prod = productOf(r, String(p.sku));
  if (!prod) return { error: 'no-product', sku: String(p.sku) };
  if (!prod.has_units) {
    const d = await bukku('GET', `/products/${prod.product_id}`);
    const again = productOf([(d && d.product) || {}], String(p.sku));
    if (again) prod.product_unit_id = again.product_unit_id;
  }
  const a = await bukku('POST', '/v2/lists', { lists: ['accounts'], params: {} });
  const acc = accountOf(a && a.accounts, String(p.account_code));
  if (!acc) return { error: 'no-bukku-account', code: String(p.account_code) };
  return { product_id: prod.product_id, product_unit_id: prod.product_unit_id, account_id: acc, classification_code: String(p.class_code) };
}
// ---- A quotation's invoices as Bukku drafts (2026-11-17) ---------------------
/* An invoice of the contact already holding the reference (the quotation's
   and the cycle's), drafts included, so a second press makes nothing. The
   reference is matched whole in one field: the service cycle's is the start
   of the advertising budget's (`… · Ads`), so a match inside a longer one
   would take the budget's invoice for the service's (review, 2026-11-17). */
async function invoiceHolding(contact: number, ref: string): Promise<{ id: number; number: string; amount: number | null } | null> {
  const key = (v: unknown) => String(v ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const k = key(ref);
  if (k.length < 6) return null;
  const r = await bukku('GET', `/sales/invoices?search=${encodeURIComponent(ref)}&contact_id=${contact}&page=1&page_size=100`);
  for (const x of ((r && r.transactions) || []) as any[]) {
    if (!x || Number(x.contact_id) !== contact || String(x.status || '') === 'void') continue;
    if ([x.number2, x.reference].some((f) => key(f) === k))
      /* Bukku's own total (the review of 2026-11-24): an invoice found there
         is filed at what Bukku holds, never the portal's sum. */
      return { id: Number(x.id || 0), number: String(x.number || x.id),
        amount: x.amount == null || x.amount === '' || !Number.isFinite(Number(x.amount)) ? null : cents(x.amount) };
  }
  return null;
}
/* The income account a Bukku product sells to, as Bukku's own form fills it. */
export function saleAccountOf(prod: any): number | null {
  if (!prod) return null;
  for (const k of ['sale_account_id', 'sales_account_id', 'income_account_id', 'revenue_account_id']) {
    const v = Number(prod[k] || (prod.sale && prod.sale[k.replace(/^sales?_/, '')]) || 0);
    if (v > 0) return v;
  }
  const s = prod.sale || prod.sales || null;
  if (s && Number(s.account_id) > 0) return Number(s.account_id);
  return null;
}
/* Each line's Bukku product by its Rate Card SKU, its base unit and the
   income account it sells to; a line with no SKU or no product is named. */
async function invoiceItems(lines: any[]): Promise<any> {
  const out: any[] = [];
  const seen: Record<string, any> = {};
  for (const l of lines) {
    const sku = String(l.sku || '').trim();
    if (!sku) return { error: 'no-sku', line: String(l.label || '') };
    if (!seen[sku]) {
      const r = await bukku('GET', `/products?search=${encodeURIComponent(sku)}&page=1&page_size=100`);
      const prod = productOf(r, sku);
      if (!prod) return { error: 'no-product', sku, line: String(l.label || '') };
      const d = await bukku('GET', `/products/${prod.product_id}`);
      const full = (d && d.product) || {};
      if (!prod.has_units) { const again = productOf([full], sku); if (again) prod.product_unit_id = again.product_unit_id; }
      prod.account_id = saleAccountOf(full);
      seen[sku] = prod;
    }
    out.push(seen[sku]);
  }
  return { items: out };
}
/* The invoice as Bukku's Create Invoice takes it: the reference in its
   second number, a line a service at its rate after the term percentage
   with its tax code, a draft for finance to check and post. */
export function invoiceBody(p: any, items: any[] | null, budgetAccount: number | null): Record<string, unknown> {
  const lines = (p.lines || []) as any[];
  const form = lines.map((l, i) => {
    const it: Record<string, unknown> = { description: String(l.label || '').slice(0, 255),
      unit_price: Number(l.unit), quantity: Number(l.qty || 1) };
    const pr = items && items[i];
    if (pr) {
      it.product_id = Number(pr.product_id);
      if (pr.product_unit_id) it.product_unit_id = Number(pr.product_unit_id);
      if (pr.account_id) it.account_id = Number(pr.account_id);
    }
    if (budgetAccount) it.account_id = budgetAccount;
    if (l.tax) it.tax_code_id = Number(l.tax);
    return it;
  });
  return {
    contact_id: Number(p.contact_id), number2: String(p.ref).slice(0, 50), date: String(p.date),
    currency_code: p.currency === 'SGD' ? 'SGD' : 'MYR', exchange_rate: p.currency === 'SGD' ? Number(p.fx) : 1,
    tax_mode: 'exclusive', description: String(p.description || '').slice(0, 200),
    status: 'draft', myinvois_action: 'NORMAL', form_items: form
  };
}
/* A creator bill's page in Bukku: found by its number among the bills the
   caller reads on the creator's Payment pane, then on the creator's contact. */
export function billWeb(sub: string, id: number): string | null {
  const s = String(sub || '').replace(/\.bukku\.my$/i, '');
  return /^[a-z0-9-]+$/i.test(s) && id > 0 ? `https://${s}.bukku.my/purchases/bills/${id}` : null;
}

// ---- A billing entity from Bukku (2026-10-29, one step 2026-10-30) ------------
/* Add entity's Bukku customers (the user, 2026-10-30: "just add and pull
   from Bukku instead of the multiple steps"). Held as the overdue invoices
   are (`invoice_scope`): Clients: Billing at Work, a contact linked to a
   client the colleague sees, any other only for a colleague who sees every
   client. `contacts` lists them once; `adopt` adds one to the client as a
   billing entity linked to it, then holds the link, so its details are
   Bukku's from the first read. */
async function contactsAction(action: string, body: Record<string, any>, db: any, origin: string | null): Promise<Response> {
  const sc = await db.rpc('invoice_scope');
  if (sc.error) return json({ error: 'needs-update' }, 200, origin);
  const scope = sc.data || {};
  if (scope.error) return json({ error: scope.error }, 200, origin);
  if (scope.send !== true) return json({ error: 'denied' }, 200, origin);
  const linked = new Set<number>((scope.links || []).map((l: any) => Number(l.contact)));
  const may = (id: number) => scope.all === true || linked.has(id);
  const customer = (c: any) => (c.types || []).includes('customer') && !c.is_archived;

  if (action === 'adopt') {
    const id = Number(body.contact), client = String(body.client || '');
    if (!(id > 0) || !/^[0-9a-f-]{36}$/i.test(client)) return json({ error: 'bad-request' }, 400, origin);
    if (!may(id)) return json({ error: 'denied' }, 200, origin);
    const c = await contactOf(id);
    if (!c || !customer(c)) return json({ error: 'bukku-gone' }, 200, origin);
    const vals = valuesOf(c);
    const { person: _person, ...entity } = vals;
    const r = await db.rpc('client_entity_from_bukku', { p_client: client, p_contact: id, p_code: c.contact_code || null, p_values: entity });
    if (r.error) return json({ error: 'needs-update' }, 200, origin);
    const d = r.data || {};
    if (d.error) return json(d, 200, origin);
    if (!d.held) {
      const m = await db.rpc('bukku_read_may', { p_kind: 'entity', p_id: d.id, p_level: 'work' });
      const md = (m.data || {}) as any;
      if (!m.error && md.linked) {
        const pr = md.portal || {};
        await take(md.me, 'entity', d.id, vals, await hashOf(vals), differs(pr, vals, pr.country === 'SG' ? 'SG' : 'MY'), 'hold');
      }
    }
    return json({ ok: true, id: d.id, main: d.main === true, held: d.held === true, code: c.contact_code || null }, 200, origin);
  }

  if (scope.all !== true && !linked.size) return json({ ok: true, contacts: [] }, 200, origin);
  const q = String(body.q || '').trim().slice(0, 80);
  const want = words(q).split(' ').filter(Boolean), reg = digits(q);
  if (q && (q.length < 2 || (!want.length && reg.length < 4))) return json({ ok: true, contacts: [] }, 200, origin);
  const hit = (c: any) => {
    if (!q) return true;
    const name = words(c.legal_name) + ' ' + words(c.other_name);
    return (want.length && want.every((w) => name.includes(w))) || (reg.length >= 4 && digits(c.reg_no).includes(reg));
  };
  const found = (await allContacts()).filter((c) => customer(c) && may(Number(c.id)) && hit(c))
    .sort((a, b) => String(a.legal_name).localeCompare(String(b.legal_name))).slice(0, q ? 8 : 2000)
    .map((c) => ({ id: c.id, code: c.contact_code, name: c.legal_name, other: c.other_name || null, reg_no: c.reg_no || null,
      held: linked.has(Number(c.id)) }));
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
  return { id: Number(inv.id), number: String(inv.number || ''), ref_no: refNo(inv), date: String(inv.date || ''), due: od.due, days,
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
/* A month's invoices (the content loop, phase 3, 2026-11-10): every invoice
   Bukku holds for the contacts asked, dated within the month's own span,
   paid or not, never a draft or a void. Read, never written. */
export async function monthInvoices(contacts: number[], from: string, to: string): Promise<any[]> {
  const want = new Set(contacts.map(Number));
  const out: any[] = [];
  for (const c of Array.from(want).slice(0, 10)) {
    for (let page = 1; page <= 10; page++) {
      const r = await bukku('GET', `/sales/invoices?contact_id=${c}&date_from=${from}&date_to=${to}&status=ready&page=${page}&page_size=100`);
      const rows = (r && r.transactions) || [];
      for (const x of rows) {
        const d = String(x && x.date || '').slice(0, 10);
        if (!x || !want.has(Number(x.contact_id)) || d < from || d > to || out.some((o) => o.id === Number(x.id))) continue;
        const link = String(x.short_link || '');
        out.push({ id: Number(x.id), number: String(x.number || '').slice(0, 60), date: d, amount: cents(x.amount),
          currency: /^[A-Z]{3}$/.test(String(x.currency_code || '')) ? String(x.currency_code) : 'MYR',
          paid: x.balance == null || x.balance === '' ? null : cents(x.balance) <= 0, link: LINK.test(link) ? link : null });
      }
      const per = Number(r && r.paging && r.paging.per_page) || rows.length || 100;
      const total = Number(r && r.paging && r.paging.total) || 0;
      if (!rows.length || page * per >= total || rows.length < per) break;
    }
  }
  return out.sort((a, b) => a.date.localeCompare(b.date) || a.number.localeCompare(b.number));
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
// ---- Payment patterns (2026-11-19) -------------------------------------------
/* What Clients' Payments view reads (`payment_analysis`): Bukku's sales
   invoices of the last 24 months and suppliers' purchase bills, kept in
   `bukku_docs` by the service role (`bukku_docs_take`), never written back.
   Each run, in the time it is given: the documents dated in the last 62
   days and every invoice still owing (the new and the moving), then a whole
   read of those whose due date or paid day is not yet known and of those
   that stopped owing since (paid, else voided: let go), twenty-four a run,
   then one month further back until 24 months are held. Bukku keeps a
   paid day nowhere in its lists: a document read alone lists what was
   applied to it, and the latest is the day it was paid (`paidOn`). */
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
export function addDay(d: string, n: number): string {
  return new Date(Date.parse(d + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10);
}
/* The first day of the month `back` months before the one holding d. */
export function monthStart(d: string, back = 0): string {
  const y = Number(d.slice(0, 4)), m = Number(d.slice(5, 7)) - 1 - back;
  return new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 10);
}
/* A document as `bukku_docs_take` keeps it. Its due date is its last
   instalment's, else (read whole, with no instalments) its date; a list row
   with no instalments leaves the one held. A paid day only from a whole
   read. */
export function docOf(x: any, whole = false): any | null {
  if (!x || !x.id || !x.contact_id) return null;
  const date = String(x.date || '').slice(0, 10);
  if (!DAY_RE.test(date)) return null;
  const terms = (Array.isArray(x.term_items) ? x.term_items : []).map((t: any) => String((t && t.date) || ''))
    .filter((t: string) => DAY_RE.test(t)).sort();
  const bal = x.balance == null || x.balance === '' ? null : cents(x.balance);
  return { id: Number(x.id), contact: Number(x.contact_id), name: String(x.contact_name || '').slice(0, 200),
    number: String(x.number || '').slice(0, 60), ref_no: refNo(x), date, due: terms.length ? terms[terms.length - 1] : whole ? date : null,
    amount: cents(x.amount), balance: bal, currency: /^[A-Z]{3}$/.test(String(x.currency_code || '')) ? String(x.currency_code) : 'MYR',
    paid_on: whole && bal != null && bal <= 0 ? paidOn(x, /invoice|bill|quot|order|deliver/) : null, gone: false };
}
const liveDoc = (x: any) => !!x && !['draft', 'void', 'voided', 'cancelled'].includes(String(x.status || ''));
async function listDocs(kind: string, query: string, keep: (c: number) => boolean, until: number): Promise<{ rows: any[]; done: boolean }> {
  const base = kind === 'invoice' ? '/sales/invoices' : '/purchases/bills';
  const out: any[] = [];
  for (let page = 1; page <= 60; page++) {
    if (Date.now() > until) return { rows: out, done: false };
    const r = await bukku('GET', `${base}?${query}&page=${page}&page_size=100`);
    const rows = (r && r.transactions) || [];
    for (const x of rows) if (liveDoc(x) && keep(Number(x.contact_id))) out.push(x);
    const per = Number(r && r.paging && r.paging.per_page) || rows.length || 100;
    const total = Number(r && r.paging && r.paging.total) || 0;
    if (!rows.length || page * per >= total || rows.length < per) break;
  }
  return { rows: out, done: true };
}
/* One supplier's bills of the last 24 months, read as it is linked
   (2026-11-22): the nightly run reads further back only once, so a contact
   linked later had its older bills read by no run. Each is kept as the
   nightly run keeps it; a paid day is read whole by the next run. */
export async function supplierBillsOf(contact: number, until: number): Promise<any> {
  const today = todayMY(), from = monthStart(today, 24);
  const got = await listDocs('bill', `contact_id=${contact}&date_from=${from}&date_to=${today}`, (c) => c === contact, until);
  const rows = got.rows.map((x) => docOf(x)).filter(Boolean);
  if (rows.length) {
    const t = await svcDb().rpc('bukku_docs_take', { p_kind: 'bill', p_rows: rows, p_back_to: null });
    if (t.error) throw new Error('not kept: ' + t.error.message);
  }
  return { ok: true, kept: rows.length, more: !got.done };
}
export async function payHistory(kind: 'invoice' | 'bill', until: number): Promise<any> {
  const svc = svcDb();
  const today = todayMY(), from = monthStart(today, 24);
  let keep = (_c: number) => true;
  if (kind === 'bill') {
    /* A supplier's bills alone: a creator's are `creator_bills`. */
    const sl = await svc.from('bukku_links').select('contact_id').eq('kind', 'supplier');
    if (sl.error) return { error: 'needs-update' };
    const set = new Set(((sl.data || []) as any[]).map((l) => Number(l.contact_id)));
    if (!set.size) return { ok: true, kept: 0, more: false };
    keep = (c: number) => set.has(c);
  }
  const take = async (rows: any[], back?: string) => {
    const t = await svc.rpc('bukku_docs_take', { p_kind: kind, p_rows: rows, p_back_to: back || null });
    if (t.error) throw new Error('not kept: ' + t.error.message);
    return Number((t.data && t.data.kept) || 0);
  };
  let kept = 0;
  /* The new and the moving: the last 62 days, and every invoice still owing. */
  const recent = await listDocs(kind, `date_from=${addDay(today, -62)}&date_to=${today}`, keep, until);
  const owing = new Set<number>();
  const fresh = new Map<number, any>();
  const add = (x: any) => { const d = docOf(x); if (d) fresh.set(d.id, d); };
  recent.rows.forEach(add);
  if (kind === 'invoice') {
    for (const ps of ['OUTSTANDING', 'OVERDUE']) {
      const o = await listDocs(kind, `payment_status=${ps}`, keep, until);
      for (const x of o.rows) { owing.add(Number(x.id)); add(x); }
    }
  }
  if (fresh.size) kept += await take(Array.from(fresh.values()));
  /* Read whole what is not yet known, or stopped owing, twenty-four a run. */
  const held: any[] = [];
  for (let at = 0; at < 20000; at += 1000) {
    const r = await svc.from('bukku_docs').select('doc_id, balance, paid_on, due_date').eq('kind', kind).eq('gone', false)
      .gte('doc_date', from).order('doc_id', { ascending: true }).range(at, at + 999);
    if (r.error) return { error: 'needs-update' };
    held.push(...(r.data || []));
    if ((r.data || []).length < 1000) break;
  }
  const settle = held.filter((h) => h.due_date == null || (Number(h.balance) <= 0 && !h.paid_on) ||
    (Number(h.balance) > 0 && (kind === 'bill' ? !fresh.has(Number(h.doc_id)) : !owing.has(Number(h.doc_id)))))
    .slice(0, 24);
  const base = kind === 'invoice' ? '/sales/invoices/' : '/purchases/bills/';
  const whole: any[] = [], gone: number[] = [];
  for (let i = 0; i < settle.length && Date.now() < until; i += 4) {
    const got = await Promise.all(settle.slice(i, i + 4).map((h) => bukku('GET', base + Number(h.doc_id))
      .then((r: any) => ({ h, x: (r && r.transaction) || null }))
      .catch((e: unknown) => { if (e instanceof BukkuError && e.status === 404) return { h, x: null }; throw e; })));
    for (const g of got) {
      if (!liveDoc(g.x)) { gone.push(Number(g.h.doc_id)); continue; }
      const d = docOf(g.x, true);
      if (d) whole.push(d);
    }
  }
  /* A document voided or gone from Bukku keeps its row, marked gone. */
  if (gone.length) {
    const g = await svc.from('bukku_docs').update({ gone: true }).eq('kind', kind).in('doc_id', gone);
    if (g.error) throw new Error('not kept: ' + g.error.message);
  }
  if (whole.length) kept += await take(whole);
  /* One month further back at a time, until 24 months are held: the month
     before the one read last, the current month first. */
  const mk = await svc.from('bukku_doc_marks').select('back_to').eq('kind', kind).maybeSingle();
  let back: string | null = (mk.data && mk.data.back_to) || null;
  let months = 0;
  while (Date.now() < until && (!back || back > from) && months < 25) {
    const start = back ? monthStart(back, 1) : monthStart(today);
    const end = back ? addDay(back, -1) : today;
    const got = await listDocs(kind, `date_from=${start}&date_to=${end}`, keep, until);
    if (!got.done) break;
    kept += await take(got.rows.map((x) => docOf(x)).filter(Boolean), start);
    back = start; months++;
  }
  return { ok: true, kept, settled: whole.length + gone.length, back_to: back,
    more: !back || back > from || settle.length >= 24 };
}

const money = (n: number, cur: string) => (cur === 'MYR' ? 'RM ' : cur === 'SGD' ? 'S$ ' : cur + ' ') +
  cents(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
const day = (d: string) => { const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(d || ''); return m ? Number(m[3]) + ' ' + MON[Number(m[2]) - 1] + ' ' + m[1] : ''; };
/* The invoices as the email's table: built here from Bukku's figures read at
   the send, never from a page. One invoice carries one button; several,
   each row its own View PDF. Totals are kept per currency. */
export function invoiceTable(lines: any[]): string {
  const cell = 'padding:10px 12px;border-top:1px solid #ececec;font-size:14px;line-height:1.4;color:#1a1a1a;';
  const head = 'padding:10px 12px;font-size:12px;font-weight:600;color:#515151;text-align:left;';
  const many = lines.length > 1;
  const rows = lines.map((l) => '<tr><td style="' + cell + '">' + esc(l.number) +
      (l.part ? '<br><span style="font-size:12px;color:#515151;">' + esc(partWord(l.part)) + '</span>' : '') + '</td>' +
    '<td class="hide-sm" style="' + cell + 'white-space:nowrap;">' + esc(day(l.date)) + '</td>' +
    '<td class="hide-sm" style="' + cell + 'white-space:nowrap;">' + esc(day(l.due)) + '</td>' +
    '<td style="' + cell + 'text-align:right;white-space:nowrap;">' + esc(money(l.amount, l.currency)) + '</td>' +
    (many ? '<td style="' + cell + 'text-align:right;white-space:nowrap;">' +
      (l.link ? '<a href="' + esc(l.link) + '" style="color:#0066cc;text-decoration:none;font-weight:500;font-size:13px;">View PDF</a>' : '') + '</td>' : '') +
    '</tr>').join('');
  const byCur: Record<string, number> = {};
  for (const l of lines) byCur[l.currency] = cents((byCur[l.currency] || 0) + l.amount);
  const tot = Object.keys(byCur).sort().map((c) => money(byCur[c], c)).join('<br>');
  const table = '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;background:#f5f5f5;border-radius:10px;border-collapse:separate;font-family:' + FONT + ';">' +
    '<tr><th style="' + head + '">Invoice</th><th class="hide-sm" style="' + head + '">Issued</th><th class="hide-sm" style="' + head + '">Due</th>' +
    '<th style="' + head + 'text-align:right;">Amount due</th>' + (many ? '<th style="' + head + '"></th>' : '') + '</tr>' + rows +
    '<tr><td style="' + cell + 'font-weight:600;">Total due</td><td class="hide-sm" style="' + cell + '"></td><td class="hide-sm" style="' + cell + '"></td>' +
    '<td style="' + cell + 'font-weight:600;text-align:right;white-space:nowrap;">' + tot + '</td>' + (many ? '<td style="' + cell + '"></td>' : '') + '</tr></table>';
  const one = !many && lines[0] && lines[0].link
    ? '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;"><tr><td style="background:#0071e3;border-radius:8px;"><a href="' + esc(lines[0].link) + '" style="display:inline-block;padding:7px 14px;text-align:center;font-family:' + FONT + ';font-size:13px;line-height:16px;font-weight:500;color:#ffffff;text-decoration:none;">View PDF</a></td></tr></table>'
    : '';
  return table + one;
}

/* A contact counts for a client where it is the client's own, or its
   company bills that client (`clients`, BUKKU BY ENTITY). */
export function billsFor(link: any, client: string): boolean {
  return !!link && (link.client === client || (Array.isArray(link.clients) && link.clients.includes(client)));
}

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
    /* Every company billing it (2026-10-29, Bukku by entity): a contact
       counts for each client its company bills (`clients`). */
    const forClient = /^[0-9a-f-]{36}$/i.test(String(body.client || '')) ? String(body.client) : null;
    const want = forClient ? new Set(Array.from(links.values()).filter((l) => billsFor(l, forClient)).map((l) => Number(l.contact))) : null;
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
      if (link) Object.assign(l, { client: link.client, client_name: link.name, client_code: link.code, client_slug: link.slug, to: link.to,
        company: link.company || null });
      else l.contact_email = l.contact_email || '';
      out.push(l);
    }
    out.sort((a, b) => b.days - a.days || a.number.localeCompare(b.number));
    const contacts = Array.from(new Set(out.map((l) => l.contact)));
    const rem = contacts.length ? await db.rpc('invoice_reminders', { p_contacts: contacts }) : { data: { rows: [] } };
    return json({ ok: true, today, send: scope.send === true, all: scope.all === true, rows: out,
      reminders: (rem.data && rem.data.rows) || [] }, 200, origin);
  }

  // action === 'remind', or 'deliver': an unpaid invoice sent by email
  // (2026-11-04), due or not, its own words and its own Sent recently.
  const deliver = action === 'deliver';
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
    let od = deliver ? dueOf(inv) : overdueOf(inv, today);
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
  if (!lines.length) return json({ error: deliver ? 'nothing-unpaid' : 'nothing-overdue', ...left }, 200, origin);
  lines.sort((a, b) => a.due.localeCompare(b.due) || a.number.localeCompare(b.number));
  const link = links.get(contact);
  /* Filed under the client it was sent from, where that client's company
     it is; else the one the contact is filed under. */
  const fromClient = link && /^[0-9a-f-]{36}$/i.test(String(body.client || '')) && billsFor(link, String(body.client)) ? String(body.client) : null;
  const bc = await bukku('GET', `/contacts/${contact}`).then((r) => (r && r.contact) || null).catch(() => null);
  const svc = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  /* To and Copy as chosen on the sheet (2026-11-04), held by the database
     to the client's own contacts and finance email; none chosen, as before. */
  const pickTo = typeof body.to === 'string' && body.to.trim() ? body.to.trim().slice(0, 254) : null;
  const pickCc = Array.isArray(body.ccs) ? body.ccs.filter((x: unknown) => typeof x === 'string').slice(0, 6).map((x: string) => x.trim().slice(0, 254)) : null;
  const begun = await svc.rpc('invoice_mail_begin', {
    p_purpose: deliver ? 'invoice' : 'reminder', p_to: pickTo, p_ccs: pickCc,
    p_actor: scope.me && scope.me.id, p_client: fromClient || (link ? link.client : null), p_contact: contact,
    p_name: String((bc && (bc.legal_name || bc.other_name)) || lines[0].contact_name || ''),
    p_email: String((bc && bc.email) || lines[0].contact_email || ''),
    p_invoices: lines.map((l) => ({ id: l.id, number: l.number, date: l.date, due: l.due, amount: l.amount, currency: l.currency,
      link: l.link, part: l.part })),
    p_cc: body.cc !== false, p_subject: String(body.subject || ''), p_body: String(body.body || ''), p_again: body.again === true });
  if (begun.error) return json({ error: 'needs-update' }, 200, origin);
  const b = begun.data || {};
  if (b.error) return json({ ...b, ...left }, 200, origin);
  const heading = String(b.subject || '').split(/\s+·\s+/)[0].trim() || (deliver ? 'Invoice' : 'Payment reminder');
  const html = layout({ heading, body: String(b.body || ''), preheader: String(b.subject || ''), block: invoiceTable(lines),
    fine: [String(b.legal || ''), String(b.disclaimer || '')] });
  const text = String(b.body || '').replace(/\{\s*invoices\s*\}/i, lines.map((l) => l.number + '  ' + money(l.amount, l.currency) +
    '  due ' + day(l.due) + (l.link ? '  ' + l.link : '')).join('\n'));
  const who = await sender('finance');
  const msg: Record<string, unknown> = { from: who.from, to: [String(b.to || '')], reply_to: who.reply_to,
    subject: String(b.subject || ''), html, text };
  const ccs = Array.isArray(b.cc_list) ? b.cc_list.map(String).filter(Boolean) : (b.cc ? [String(b.cc)] : []);
  if (ccs.length) msg.cc = ccs;
  const sent = await resend(msg, String(b.id), secret('RESEND_API_KEY'));
  const done = await svc.rpc('invoice_email_done', { p_id: b.id, p_status: sent.status, p_provider: sent.provider || null, p_error: sent.error || null });
  if (done.error) console.error('bukku-sync: reminder not closed', done.error.message);
  if (sent.status !== 'sent') console.error('bukku-sync: ' + (deliver ? 'invoice email' : 'reminder'), sent.status, sent.error);
  return json(sent.status === 'sent' ? { ok: true, id: b.id, to: b.to, cc: b.cc || null, ...left }
    : { error: sent.status === 'unknown' ? 'not-confirmed' : 'not-sent', ...left }, 200, origin);
}

/* Why a Bukku contact is offered for a record, or '' where it is not: the
   same registration no., the same name, or a name inside the other. */
/* A creator's Bukku contact found through their bills (2026-11-12, the
   user: KJ3105 on Gaby Low, whose Bukku contact is Low Chee Guan): each
   contact holding a purchase bill whose reference or number holds one of
   the creator's earlier job IDs, read as `creator_ref_key` reads them.
   Bukku's search is asked first; where it finds none, every bill is read,
   thirty pages at most. */
const refKey = (v: unknown) => String(v ?? '').replace(/[^0-9A-Za-z]/g, '').toUpperCase();
export function jobHits(rows: any[], jobs: string[]): Map<number, string> {
  const out = new Map<number, string>();
  const keys = jobs.map((j) => [j, refKey(j)] as [string, string]).filter(([, k]) => k.length >= 4);
  for (const x of rows) {
    if (!x || !x.contact_id) continue;
    const b = billOf(x), ref = refKey(b.ref), no = refKey(b.number);
    for (const [j, k] of keys) if ((ref.includes(k) || no.includes(k)) && !out.has(Number(x.contact_id))) out.set(Number(x.contact_id), j);
  }
  return out;
}
async function jobContacts(jobs: string[]): Promise<Map<number, string>> {
  const out = new Map<number, string>();
  const list = jobs.filter((j) => refKey(j).length >= 4).slice(0, 10);
  if (!list.length) return out;
  for (const j of list) {
    const r = await bukku('GET', `/purchases/bills?search=${encodeURIComponent(j)}&page=1&page_size=100`);
    for (const [c, w] of jobHits((r && r.transactions) || [], [j])) if (!out.has(c)) out.set(c, w);
  }
  if (out.size) return out;
  for (let page = 1; page <= 30; page++) {
    const r = await bukku('GET', `/purchases/bills?page=${page}&page_size=100`);
    const rows = (r && r.transactions) || [];
    for (const [c, w] of jobHits(rows, list)) if (!out.has(c)) out.set(c, w);
    const per = Number(r && r.paging && r.paging.per_page) || rows.length || 100;
    const total = Number(r && r.paging && r.paging.total) || 0;
    if (!rows.length || page * per >= total || rows.length < per) break;
  }
  return out;
}

function matchOf(p: Prep, c: any): string {
  const reg = digits(p.reg_no), name = words(p.legal_name), other = words(p.other_name);
  return reg && digits(c.reg_no) === reg ? 'brn'
    : name && words(c.legal_name) === name ? 'name'
    : other && (words(c.legal_name) === other || words(c.other_name) === other) ? 'name'
    : name && name.length > 3 && (words(c.legal_name).includes(name) || name.includes(words(c.legal_name)) && words(c.legal_name).length > 3) ? 'similar' : '';
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  if (!secret('BUKKU_TOKEN') || !secret('BUKKU_SUBDOMAIN')) return json({ error: 'bukku-not-set-up' }, 200, origin);
  let body: Record<string, any> = {};
  try { body = await req.json(); } catch { return json({ error: 'bad-request' }, 400, origin); }
  const action = String(body.action || '');
  if (action === 'match-creators') {
    try { return await matchCreators(req, origin); }
    catch (e) { console.error('bukku-sync: match-creators', String((e as Error).message || e));
      return json({ error: e instanceof BukkuError ? e.code : 'failed' }, 200, origin); }
  }
  if (action === 'nightly') {
    try { return await nightly(req, origin); }
    catch (e) { console.error('bukku-sync: nightly failed', String((e as Error).message || e)); return json({ error: 'failed' }, 200, origin); }
  }
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

    /* The accounts a creator's bill may post to (CREATOR FEES, 2026-11-13):
       the chart of accounts' expense and cost of sales accounts, read for
       Settings, Money, Bukku. Read only, asked of bukku_config as taxes is. */
    if (action === 'accounts') {
      const me = await db.rpc('bukku_config');
      if (me.error) return json({ error: 'needs-update' }, 200, origin);
      if (me.data && me.data.error) return json({ error: me.data.error }, 200, origin);
      const r = await bukku('POST', '/v2/lists', { lists: ['accounts'], params: {} });
      return json({ ok: true, accounts: expenseAccounts(r && r.accounts) }, 200, origin);
    }
    /* A creator's bill made in Bukku from the booking's fee (CREATOR FEES,
       2026-11-13): asked of creator_bill_prep as the caller, which holds the
       press ten minutes; Bukku asked first for a bill already holding the Job
       reference, so a second press makes nothing; the bills read back. */
    if (action === 'createbill') {
      const oid = String(body.option || '');
      if (!/^[0-9a-f-]{36}$/i.test(oid)) return json({ error: 'bad-request' }, 400, origin);
      const prep = await db.rpc('creator_bill_prep', { p_option: oid });
      if (prep.error) return json({ error: 'needs-update' }, 200, origin);
      const p = prep.data || {};
      if (p.error) return json({ error: p.error }, 200, origin);
      let made: string | null = null, had: string | null = null, madeId = 0, sent = false;
      try {
        had = await billHolding(Number(p.contact_id), String(p.ref));
        if (!had) {
          const item = await billItem(p);
          if (item.error) {
            await db.rpc('creator_bill_done', { p_option: oid, p_number: null });
            return json(item, 200, origin);
          }
          sent = true;
          const r = await bukku('POST', '/purchases/bills', billBody(p, item));
          made = String((r && r.transaction && r.transaction.number) || '') || 'Created';
          madeId = Number((r && r.transaction && r.transaction.id) || 0);
        }
      } catch (e) {
        /* The hold is let go only where no bill can have been made: before
           the bill was sent, or Bukku refusing it outright (a 4xx). A bill
           sent that timed out, or met a 5xx, may stand in Bukku: the hold
           keeps its ten minutes, so a second press makes no second bill
           (audit 2026-11-15). */
        const refused = e instanceof BukkuError && e.status >= 400 && e.status < 500;
        if (!sent || refused) await db.rpc('creator_bill_done', { p_option: oid, p_number: null });
        else return json({ error: 'not-confirmed' }, 200, origin);
        throw e;
      }
      /* The bill stands in Bukku once made: a failed read of the bills back
         never hides it (the review of 2026-11-24: it answered Bukku
         unreachable and never filed the bill made). The bill is filed
         either way, and the page told the list was not read. */
      let readBack = true;
      try {
        await creatorBills(String(p.creator), Number(p.contact_id), madeId > 0 ? { id: madeId, option: oid } : undefined);
      } catch (e) {
        if (!made) throw e;
        readBack = false;
        console.error('bukku-sync: bill made, its list not read', e instanceof Error ? e.message : String(e));
      }
      await db.rpc('creator_bill_done', { p_option: oid, p_number: made });
      if (!readBack) return json({ made, note: 'list-not-read' }, 200, origin);
      const list = await db.rpc('creator_bills_list', { p_creator: String(p.creator) });
      if (list.error) return json({ error: 'needs-update' }, 200, origin);
      return json(Object.assign({}, list.data || {}, had ? { error: 'in-bukku', number: had } : { made }), 200, origin);
    }
    /* A quotation's cycle made in Bukku as a draft invoice (2026-11-17):
       asked of quotation_invoice_prep as the caller, which holds the press
       ten minutes; Bukku asked first for an invoice holding the reference. */
    if (action === 'invoicecreate') {
      const qid = String(body.quotation || ''), cyc = Number(body.cycle), kind = String(body.kind || 'service');
      if (!/^[0-9a-f-]{36}$/i.test(qid) || !Number.isInteger(cyc) || cyc < 1 || cyc > 36 || !/^(service|budget)$/.test(kind))
        return json({ error: 'bad-request' }, 400, origin);
      const prep = await db.rpc('quotation_invoice_prep', { p_id: qid, p_cycle: cyc, p_kind: kind });
      if (prep.error) return json({ error: 'needs-update' }, 200, origin);
      const p = prep.data || {};
      if (p.error) return json({ error: p.error, number: p.number }, 200, origin);
      const letGo = () => db.rpc('quotation_invoice_done', { p_id: qid, p_cycle: cyc, p_kind: kind, p_bukku: null, p_number: null, p_amount: null });
      const total = ((p.lines || []) as any[]).reduce((t, l) => t + Math.round(Number(l.qty || 1) * Number(l.unit) * 100) / 100, 0);
      let sent = false;
      try {
        const had = await invoiceHolding(Number(p.contact_id), String(p.ref));
        if (had) {
          await db.rpc('quotation_invoice_done', { p_id: qid, p_cycle: cyc, p_kind: kind, p_bukku: had.id, p_number: had.number,
            p_amount: had.amount ?? total });
          return json({ ok: true, error: 'in-bukku', number: had.number }, 200, origin);
        }
        let items: any[] | null = null, budgetAccount: number | null = null;
        if (kind === 'budget') {
          const a = await bukku('POST', '/v2/lists', { lists: ['accounts'], params: {} });
          budgetAccount = accountOf(a && a.accounts, String(p.account_code));
          if (!budgetAccount) { await letGo(); return json({ error: 'no-bukku-account', code: String(p.account_code) }, 200, origin); }
        } else {
          const r = await invoiceItems(p.lines || []);
          if (r.error) { await letGo(); return json(r, 200, origin); }
          items = r.items;
        }
        sent = true;
        const made = await bukku('POST', '/sales/invoices', invoiceBody(p, items, budgetAccount));
        const t = (made && made.transaction) || {};
        const num = String(t.number || '') || 'Created';
        await db.rpc('quotation_invoice_done', { p_id: qid, p_cycle: cyc, p_kind: kind, p_bukku: Number(t.id || 0), p_number: num, p_amount: total });
        return json({ ok: true, made: num }, 200, origin);
      } catch (e) {
        const refused = e instanceof BukkuError && e.status >= 400 && e.status < 500;
        if (!sent || refused) await letGo();
        else return json({ error: 'not-confirmed' }, 200, origin);
        throw e;
      }
    }
    if (action === 'billlink') {
      const cid = String(body.creator || ''), num = String(body.number || '').trim();
      if (!/^[0-9a-f-]{36}$/i.test(cid) || !num || num.length > 60) return json({ error: 'bad-request' }, 400, origin);
      const list = await db.rpc('creator_bills_list', { p_creator: cid });
      if (list.error) return json({ error: 'needs-update' }, 200, origin);
      const L = list.data || {};
      if (L.error) return json({ error: L.error }, 200, origin);
      const seen = [...(L.jobs || []), ...(L.past || [])].map((x: any) => x && x.bill && x.bill.number)
        .concat((L.earlier || []).map((b: any) => b && b.number));
      if (!seen.includes(num)) return json({ error: 'not-found' }, 200, origin);
      const row = await svcDb().from('creator_bills').select('bill_id').eq('creator_id', cid).eq('number', num).limit(1);
      const id = Number(((row.data || [])[0] || {}).bill_id || 0);
      const url = billWeb(secret('BUKKU_SUBDOMAIN'), id);
      return url ? json({ ok: true, url }, 200, origin) : json({ error: 'not-found' }, 200, origin);
    }
    if (action === 'invoices' || action === 'remind' || action === 'deliver') return await invoiceAction(action, body, db, origin);
    /* Payments' Read from Bukku (2026-11-19): asked as the caller first
       (`payment_analysis`: Clients: Billing at Full control), then the
       history read for 25 seconds, kept by the service role. */
    if (action === 'payments') {
      const may = await db.rpc('payment_analysis', { p_currency: null });
      if (may.error) return json({ error: 'needs-update' }, 200, origin);
      if (may.data && may.data.error) return json({ error: may.data.error }, 200, origin);
      const at = Date.now();
      const inv = await payHistory('invoice', at + 20000);
      if (inv.error) return json({ error: inv.error }, 200, origin);
      const bill = await payHistory('bill', at + 25000);
      if (bill.error) return json({ error: bill.error }, 200, origin);
      return json({ ok: true, kept: (inv.kept || 0) + (bill.kept || 0), more: !!(inv.more || bill.more) }, 200, origin);
    }
    /* Suppliers' Payments view's Read from Bukku (SUPPLIER BILLS,
       2026-11-22): asked as the caller (`supplier_bills`, Suppliers Work),
       then the suppliers' bills alone read for 25 seconds and kept as the
       nightly run keeps them. */
    if (action === 'supplierbills') {
      const may = await db.rpc('supplier_bills', { p_supplier: null, p_paid_from: todayMY(), p_doc: null });
      if (may.error) return json({ error: 'needs-update' }, 200, origin);
      if (may.data && may.data.error) return json({ error: may.data.error }, 200, origin);
      if (!may.data || may.data.work !== true) return json({ error: 'denied' }, 200, origin);
      const bill = await payHistory('bill', Date.now() + 25000);
      if (bill.error) return json({ error: bill.error }, 200, origin);
      return json({ ok: true, kept: bill.kept || 0, more: !!bill.more }, 200, origin);
    }
    /* A supplier bill's page in Bukku: the bill named only where the caller
       reads it (`supplier_bills` with `p_doc`, Suppliers View). */
    if (action === 'supplierbilllink') {
      const id = Number(body.id || 0);
      if (!Number.isInteger(id) || id <= 0 || id > 1e15) return json({ error: 'bad-request' }, 400, origin);
      const r = await db.rpc('supplier_bills', { p_supplier: null, p_paid_from: null, p_doc: id });
      if (r.error) return json({ error: 'needs-update' }, 200, origin);
      if (r.data && r.data.error) return json({ error: r.data.error }, 200, origin);
      if (!((r.data && r.data.bills) || []).length) return json({ error: 'not-found' }, 200, origin);
      const url = billWeb(secret('BUKKU_SUBDOMAIN'), id);
      return url ? json({ ok: true, url }, 200, origin) : json({ error: 'not-found' }, 200, origin);
    }
    /* A completed month's invoice (2026-11-10): asked as the caller, read
       from Bukku, kept by the service role. */
    if (action === 'month') {
      const eid = String(body.engagement || '');
      if (!/^[0-9a-f-]{36}$/i.test(eid)) return json({ error: 'bad-request' }, 400, origin);
      const ask = await db.rpc('ops_month_invoice_ask', { p_engagement: eid });
      if (ask.error) return json({ error: 'needs-update' }, 200, origin);
      const a = ask.data || {};
      if (a.error) return json({ error: a.error }, 200, origin);
      const found = await monthInvoices((a.contacts || []).map(Number), String(a.from), String(a.to));
      const t = await svcDb().rpc('ops_month_invoice_take', { p_engagement: eid, p_invoices: found });
      if (t.error) return json({ error: 'failed' }, 200, origin);
      return json(t.data || { error: 'failed' }, 200, origin);
    }
    if (action === 'read' || action === 'hold' || action === 'save') {
      const k = String(body.kind || ''), rid = String(body.id || '');
      /* A supplier is read and its Bukku details used (2026-11-22); its
         details are saved in the portal, never straight to Bukku. */
      const kinds = action === 'save' ? ['client', 'entity'] : ['client', 'entity', 'supplier'];
      if (!kinds.includes(k) || !/^[0-9a-f-]{36}$/i.test(rid)) return json({ error: 'bad-request' }, 400, origin);
      return await billingAction(action, k, rid, body, db, origin);
    }
    if (action === 'contacts' || action === 'adopt') return await contactsAction(action, body, db, origin);
    if (action === 'bills') {
      const cid = String(body.creator || '');
      if (!/^[0-9a-f-]{36}$/i.test(cid)) return json({ error: 'bad-request' }, 400, origin);
      // Asked as the caller: the Creators List at View, and the creator's own link.
      const lk = await db.rpc('bukku_link_get', { p_kind: 'creator', p_id: cid });
      if (lk.error) return json({ error: 'needs-update' }, 200, origin);
      if (lk.data && lk.data.error) return json({ error: lk.data.error }, 200, origin);
      if (!lk.data || !lk.data.contact_id) return json({ error: 'not-linked' }, 200, origin);
      const r = await creatorBills(cid, Number(lk.data.contact_id));
      if (r.error) return json({ error: r.error }, 200, origin);
      const list = await db.rpc('creator_bills_list', { p_creator: cid });
      if (list.error) return json({ error: 'needs-update' }, 200, origin);
      return json(list.data || { error: 'failed' }, 200, origin);
    }

    const kind = String(body.kind || ''), id = String(body.id || '');
    if (!['client', 'supplier', 'entity', 'creator', 'member'].includes(kind) || !/^[0-9a-f-]{36}$/i.test(id)) return json({ error: 'bad-request' }, 400, origin);
    /* A name is a label a colleague may type on their own record, so a
       contact matched by name alone is offered and reached only by one who
       sees every client; the same registration no. or a bill holding the
       creator's job ID is offered to all (review 2026-11-24: renaming a
       record to a Bukku contact's name reached that contact). */
    let seesAll: boolean | null = null;
    const everyClient = async () => {
      if (seesAll === null) {
        const sc = await db.rpc('invoice_scope');
        seesAll = !sc.error && !!sc.data && sc.data.all === true;
      }
      return seesAll;
    };
    const prep = await db.rpc('bukku_prepare', { p_kind: kind, p_id: id });
    if (prep.error) return json({ error: 'needs-update' }, 200, origin);
    let p = prep.data as Prep;
    /* A creator is found and linked whatever their payment details
       (2026-11-12): by name, else through a bill holding an earlier job
       ID; Send still needs details approved. */
    let jobs: string[] = [];
    if (kind === 'creator' && (action === 'find' || action === 'link')) {
      const lp = await db.rpc('bukku_creator_link_prep', { p_id: id });
      if (!lp.error && lp.data && lp.data.ok) {
        jobs = (lp.data.jobs || []).map(String);
        if (!p || (p as any).error === 'no-details') p = lp.data as Prep;
      }
    }
    if (!p || p.error) return json(p || { error: 'bad-request' }, 200, origin);
    /* A colleague is an employee (HR-SPEC decision 12): no Bukku field
       holds an Employee ID, so none is asked. */
    if (!p.field_id && kind !== 'member') return json({ error: 'no-field' }, 200, origin);

    if (action === 'find') {
      if (p.contact_id) {
        const cur = await bukku('GET', `/contacts/${Number(p.contact_id)}`).then((r) => r && r.contact).catch(() => null);
        /* A supplier with no link of its own whose client is linked
           (2026-11-23, the user: "still no link button?"): its band reads
           Not linked, so its client's contact is offered to link, alone,
           never said to be linked already. */
        let own = true;
        if (cur && kind === 'supplier' && p.client_id) {
          const lg = await db.rpc('bukku_link_get', { p_kind: 'supplier', p_id: id });
          own = !lg.error && !!lg.data && lg.data.contact_id != null;
        }
        if (cur && !own) {
          return json({ ok: true, shared: true, candidates: [{ id: cur.id, code: cur.contact_code, name: cur.legal_name, reg_no: cur.reg_no || null,
            types: cur.types || [], archived: !!cur.is_archived, why: 'client' }], details: (p as any).details !== false }, 200, origin);
        }
        if (cur) return json({ ok: true, linked: { id: cur.id, code: cur.contact_code, name: cur.legal_name, types: cur.types || [] } }, 200, origin);
      }
      const all = await allContacts();
      const seen = new Set<number>();
      const found: any[] = [];
      const byJob = jobs.length ? await jobContacts(jobs) : new Map<number, string>();
      for (const c of all) {
        const j = byJob.get(Number(c.id));
        if (j && !seen.has(c.id)) {
          seen.add(c.id);
          found.push({ id: c.id, code: c.contact_code, name: c.legal_name, reg_no: c.reg_no || null, types: c.types || [],
            archived: !!c.is_archived, why: 'job', job: j });
        }
      }
      for (const c of all) {
        const why = matchOf(p, c);
        if (why && why !== 'brn' && !(await everyClient())) continue;
        if (why && !seen.has(c.id)) {
          seen.add(c.id);
          found.push({ id: c.id, code: c.contact_code, name: c.legal_name, reg_no: c.reg_no || null, types: c.types || [],
            archived: !!c.is_archived, why });
        }
      }
      const rank: Record<string, number> = { job: 0, brn: 1, name: 2, similar: 3 };
      found.sort((a, b) => rank[a.why] - rank[b.why]);
      return json({ ok: true, candidates: found.slice(0, 5), next_code: nextCode(all, p.legal_name), details: (p as any).details !== false }, 200, origin);
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
    /* A contact is read or written for a record only where find offers it
       for that record (the same registration no. or name), unless the
       colleague sees every client (security audit 2026-11-07): the id came
       from the page, and any other read the company's Bukku contacts
       whatever the colleague's own access. */
    if (cur && !p.contact_id && matchOf(p, cur) !== 'brn' && !(jobs.length && (await jobContacts(jobs)).has(Number(cur.id)))) {
      if (!(await everyClient())) return json({ error: 'not-offered' }, 200, origin);
    }
    /* Link only (2026-10-19): the contact as Bukku holds it, linked and
       nothing sent. */
    if (action === 'link') {
      if (!cur) return json({ error: 'bad-request' }, 400, origin);
      const l = await db.rpc('bukku_link_only', { p_kind: kind, p_id: id, p_contact: cur.id, p_code: cur.contact_code || String(cur.id) });
      if (l.error) return json({ error: 'needs-update' }, 200, origin);
      if (l.data && l.data.error) return json({ error: l.data.error }, 200, origin);
      /* A creator's bills are read at once, so their payments show; a
         supplier's too (2026-11-22), so its Bills never wait on the night. */
      if (kind === 'creator') {
        try { await creatorBills(id, Number(cur.id)); }
        catch (e) { console.error('bukku-sync: bills after link', String((e as Error).message || e)); }
      }
      if (kind === 'supplier') {
        try { await supplierBillsOf(Number(cur.id), Date.now() + 20000); }
        catch (e) { console.error('bukku-sync: supplier bills after link', String((e as Error).message || e)); }
      }
      return json({ ok: true, contact: cur.id, code: cur.contact_code || String(cur.id), linked: true }, 200, origin);
    }
    const every = cur ? null : await allContacts();
    /* A new entity made from the portal (2026-10-30): where Bukku already
       holds a customer of its registration no., that contact is linked as
       Bukku holds it, never a second one made. */
    if (action === 'send' && !cur && body.guard === true && kind === 'entity' && digits(p.reg_no).length >= 4) {
      const same = (every || []).find((c) => !c.is_archived && digits(c.reg_no) === digits(p.reg_no));
      if (same) {
        const l = await db.rpc('bukku_link_only', { p_kind: kind, p_id: id, p_contact: same.id, p_code: same.contact_code || null });
        if (l.error) return json({ error: 'needs-update' }, 200, origin);
        if (l.data && l.data.error) return json({ error: l.data.error }, 200, origin);
        return json({ ok: true, contact: same.id, code: same.contact_code || null, linked: true, existing: true }, 200, origin);
      }
    }
    const code = cur ? cur.contact_code : nextCode(every || [], p.legal_name);
    const terms = p.payment_term ? await termsOf() : [];
    const next = merged(p, cur, code, termFor(terms, p.payment_term));

    if (action === 'preview') {
      return json({ ok: true, code, rows: rowsOf(p, cur, next, terms) }, 200, origin);
    }
    if (action === 'send') {
      /* A new contact is made once: a second press while the first is out
         is refused, never a second contact (review 2026-11-24). */
      if (!cur) {
        const cl = await db.rpc('bukku_send_claim', { p_kind: kind, p_id: id });
        if (cl.error) return json({ error: 'needs-update' }, 200, origin);
        if (cl.data && cl.data.error) return json({ error: cl.data.error }, 200, origin);
      }
      try {
        return await sendIt();
      } finally {
        if (!cur) await db.rpc('bukku_send_release', { p_kind: kind, p_id: id }).then(() => null, () => null);
      }
    }
    return json({ error: 'bad-request' }, 400, origin);
    async function sendIt() {
      const r = cur ? await bukku('PUT', `/contacts/${contact}`, keepAsHeld(next, cur, body.skip)) : await bukku('POST', '/contacts', next);
      const saved = r && r.contact;
      if (!saved || !saved.id) return json({ error: 'bukku-refused', message: 'Bukku did not return the contact. Please try again.' }, 200, origin);
      const l = await db.rpc('bukku_linked', { p_kind: kind, p_id: id, p_contact: saved.id, p_code: saved.contact_code || code });
      if (l.error || (l.data && l.data.error)) {
        console.error('bukku-sync: sent but not filed', kind, id, saved.id, l.error ? l.error.message : l.data.error);
        return json({ error: 'not-filed', contact: saved.id, code: saved.contact_code }, 200, origin);
      }
      /* What was sent is what Bukku holds: a client's or an entity's link
         is held from here, the portal taking Bukku's read back. */
      if (kind === 'client' || kind === 'entity') {
        const m = await db.rpc('bukku_read_may', { p_kind: kind, p_id: id, p_level: 'work' });
        const md = (m.data || {}) as any;
        if (!m.error && md.linked) {
          const after = valuesOf(saved), pr = md.portal || {};
          const ch = takeAfterSend(differs(pr, after, pr.country === 'SG' ? 'SG' : 'MY'), body.skip);
          if (ch) await take(md.me, kind, id, after, await hashOf(after), ch, 'hold');
        }
      }
      return json({ ok: true, contact: saved.id, code: saved.contact_code || code, created: !cur }, 200, origin);
    }
  } catch (e) {
    if (e instanceof BukkuError) {
      console.error('bukku-sync:', e.code, e.status, e.message);
      return json({ error: e.code, status: e.status, message: e.code === 'bukku-refused' ? e.message : undefined }, 200, origin);
    }
    console.error('bukku-sync: failed', String((e as Error).message || e));
    return json({ error: 'failed' }, 200, origin);
  }
});
