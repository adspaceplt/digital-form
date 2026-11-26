/*
 * hiring-mail (2026-11-17, release H2 step B): the emails a candidate is
 * sent about an interview, each sent at a colleague's press.
 *
 *   { interviewId, kind: 'invite' }   the times offered, with the button to
 *                                     the candidate's own page to choose one;
 *   { interviewId, kind: 'confirm' }  the time approved, with its Google Meet
 *                                     or the office's address;
 *   { interviewId, kind: 'rescheduled' } the time changed (Change interview
 *                                     time, 2026-11-22): the previous time
 *                                     and the new one, which stands, with
 *                                     the new time's Google Meet or the
 *                                     office's address; sent by the page as
 *                                     the move succeeds;
 *   { interviewId, kind: 'held' }     the interview held (2026-11-20): the
 *                                     candidate thanked and told by when
 *                                     ADspace will inform them of the
 *                                     outcome;
 *   { interviewId, kind: 'moved' }    that date changed, with the team's
 *                                     note to the candidate;
 *   { candidateId, kind: 'outcome' }  the decision (step C): Keep in talent
 *                                     pool asks the candidate to agree on
 *                                     their page; Not proceed thanks them.
 *                                     Never the team's note on the decision.
 *   { docId, kind: 'doc' }            an Employment Offer or Contract waits
 *                                     on the candidate's page (step D):
 *                                     the reference and the day to answer,
 *                                     never the salary or the terms;
 *   { docId, kind: 'confirmed' }      that offer or contract confirmed and
 *                                     countersigned by ADSPACE PLT
 *                                     (2026-11-20): its name and reference
 *                                     and the candidate's page, never the
 *                                     terms or the salary, no attachment;
 *   { interviewId, kind: 'cancelled' } a confirmed interview cancelled
 *                                     (2026-11-20): its time, that the
 *                                     earlier Google Meet link no longer
 *                                     applies, and that ADspace will
 *                                     contact them to arrange another time;
 *   { action: 'drain' }              from the database alone (2026-11-20,
 *                                     `hiring_mail_kick`, after
 *                                     `hiring_docs_expire`, and every minute
 *                                     a decision email is due), carrying
 *                                     the wake secret as `x-adspace-wake`
 *                                     (`wake_secret_ok`, anyone else 401):
 *                                     each offer or contract that expired
 *                                     with no reply, claimed once
 *                                     (`hiring_expire_mail_claim`), emailed
 *                                     to the candidate with the careers
 *                                     mailbox to contact, and closed
 *                                     (`hiring_expire_mail_done`); and each
 *                                     decision email queued 30 seconds
 *                                     before (`hiring_outcome_mail_claim`,
 *                                     `hiring_outcome_mail_close`);
 *   againOf (with any of these)    the Email log's Send again: the same
 *                                     email drawn afresh, filed as sent again;
 *   byHand (with any of these)     a card's Email candidate where the email
 *                                     did not go: a send by hand.
 *
 * Automatic, or by hand (CANDIDATE EMAILS, 2026-11-21): each step's email,
 * and the expiry drain's, is an automatic email, its words the candidate
 * template's (`hiring_email_templates`, Settings, Messages: Email
 * templates, Candidates), sent only while `hiring_mail_gate` reads the
 * portal's Email, Automatic emails and the template on; else it is filed Not
 * sent (`off: ...`) and the step stands. againOf and byHand ask the gate's
 * `hand` (the portal's Email, Send by email and the group's Send email).
 *   { key, docId, kind: 'code', device }  the candidate's own press on their
 *                                     page, with no sign-in: a six-digit
 *                                     code to read that document, made by
 *                                     `hiring_doc_code` as the service role
 *                                     and sent to the candidate's own email
 *                                     alone, in the one Verification code
 *                                     email (`codeEmail`); answered alike
 *                                     whatever befalls.
 *
 * Every question is asked as the caller (`hiring_mail_prepare`, the part or
 * the candidate's Owner); the address, the words' facts and the link are the
 * database's, never the page's. The outcome is filed by `hiring_mail_done`.
 * Sent through Resend in the portal's one layout (_shared/mail.ts), from
 * Careers' sender, replying to its company mailbox (`mail_sender('careers')`,
 * Settings, Messages: Reply-to mailboxes; never a colleague's own address),
 * and filed for Messages' Email log (`system_email_file`; a code's words never
 * kept). No candidate data goes to AI.
 *
 * Secrets: RESEND_API_KEY. Verify JWT off: the
 * function asks the caller's own token of the database.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json } from '../_shared/cors.ts';
import { layout, resend, esc, FONT, button as mailButton, codeEmail, sender, fileSent, callerEmail } from '../_shared/mail.ts';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
const PAGE = 'https://digital.adspace.me/careers/?k=';
const OFFICE = '61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor';
const MAP = 'https://hi.adspace.me/map';
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/* The portal's one email button (`_shared/mail.ts`), 24px under it. */
const button = (label: string, href: string) => mailButton({ label, url: href, margin: '8px 0 24px' });

/* The close: the colleague who sent it over ADspace, or, sent by a system
   account (the super admin, named ADspace), the ADspace Hiring Team alone,
   never the account's name twice (2026-11-20). */
function signOff(m: Record<string, any>): string {
  return m.system || !String(m.sender || '').trim() ? 'Yours sincerely,\nADspace Hiring Team' : 'Yours sincerely,\n' + m.sender + '\nADspace';
}

/* Each email's name, as Settings, Messages: Email templates lists it. */
export const NAMES: Record<string, string> = {
  invite: 'Interview invitation', confirm: 'Interview confirmed', rescheduled: 'Interview time changed', cancelled: 'Interview cancelled',
  held: 'Thank you for your interview', moved: 'Decision date changed', pool: 'Talent pool', not: 'Application unsuccessful',
  doc: 'Employment document', doc_again: 'Employment document sent again', confirmed: 'Document confirmed', expired: 'Document expired'
};
/* The template an email is written from (CANDIDATE EMAILS, 2026-11-21). */
export function templateOf(m: Record<string, any>): string {
  return m.kind === 'doc' ? (m.returned ? 'doc_again' : 'doc') : String(m.kind || '');
}

/* The fields hiring-mail fills (`template_fields('candidate')`), from the
   database's answer alone. */
export function fields(m: Record<string, any>): Record<string, string> {
  const contract = m.doc === 'contract';
  return {
    'candidate name': String(m.name || ''),
    position: String(m.position || ''),
    'interview length': m.minutes == null ? '' : String(m.minutes),
    where: m.mode === 'online' ? 'on Google Meet' : 'at the ADspace office',
    times: (m.times || []).map((t: string) => '• ' + t + ' (Malaysia time)').join('\n'),
    'reply by': String(m.reply_by || ''),
    note: String((m.kind === 'moved' ? m.decide_note : m.kind === 'invite' || m.kind === 'confirm' ? m.note : '') || ''),
    time: String(m.when || ''),
    /* The time changed (2026-11-22): the time it held before, and the new. */
    'previous time': m.kind === 'rescheduled' ? String(m.was || '') : '',
    'new time': m.kind === 'rescheduled' ? String(m.when || '') : '',
    /* The office as the candidate's page names it, with its directions on our
       own short link, the sending domain's (2026-11-19); in the confirmation
       alone, never before the team confirms the time, whatever a template
       holds (2026-11-22); the time changed confirms the new one. */
    place: m.kind !== 'confirm' && m.kind !== 'rescheduled' ? '' : m.mode === 'online' ? 'The interview will be held on Google Meet:\n' + String(m.link || '')
      : 'The interview will be held at the ADspace office:\n' + OFFICE + '\nDirections: ' + MAP,
    'google meet notice': m.mode === 'online' ? 'The Google Meet link sent earlier no longer applies.' : '',
    'decision date': String(m.decide_by || ''),
    months: m.months == null ? '' : String(m.months),
    document: contract ? 'Employment Contract' : 'Employment Offer',
    reference: String(m.ref || ''),
    'requested action': contract ? 'sign it' : 'reply',
    purpose: contract ? 'for your signature' : 'for your reply',
    reason: m.returned_note ? 'Reason: ' + m.returned_note : '',
    'document date': String(m.sent || ''),
    contact: String(m.contact || ''),
    'sign-off': signOff(m),
    /* The button's place, which the layout lays as a block. */
    button: '{invoices}'
  };
}

/* A template's words with its fields filled: a field left empty that
   stands as its own paragraph leaves with it, and an invitation or a
   document with no reply-by or position drops the words naming it, so the
   words read as hiring-mail wrote them before they were editable. A field
   it does not fill stays as typed (the editor refuses one on save). */
export function fill(text: string, v: Record<string, string>): string {
  const key = (k: string) => k.toLowerCase().replace(/\s+/g, ' ').trim();
  let t = String(text || '');
  t = t.replace(/\n\n\{\s*([^{}]*?)\s*\}(?=\n\n|$)/g, (all, k) => v[key(k)] === '' ? '' : all);
  if (!v['reply by']) t = t.replace(/ by \{\s*reply by\s*\}( \(Malaysia time\))?/gi, '');
  if (!v.position) t = t.replace(/ for the position of \{\s*position\s*\}/gi, '');
  t = t.replace(/\{\s*([^{}]*?)\s*\}/g, (all, k) => { const x = v[key(k)]; return x == null ? all : x; });
  return t.replace(/[ \t]+\n/g, '\n');
}

/* The words, as a formal letter (DESIGN.md §6): the template's subject and
   message (Settings, Messages: Email templates, Candidates), the heading and
   the button the email's own. */
export function words(m: Record<string, any>, tpl: { subject: string; body: string }): { subject: string; heading: string; body: string; block: string } {
  const v = fields(m), title = v.document;
  const subject = fill(tpl.subject, v).replace(/\s+/g, ' ').trim(), body = fill(tpl.body, v);
  const heading = ({
    doc: 'Your ' + title, expired: title + ' expired', confirmed: title + ' confirmed', cancelled: 'Interview cancelled',
    held: 'Thank you for your interview', moved: 'Decision date changed', pool: 'Your application', not: 'Your application',
    invite: 'Interview invitation', confirm: 'Interview confirmed', rescheduled: 'Interview time changed'
  } as Record<string, string>)[String(m.kind)] || 'Your application';
  const block = m.kind === 'doc' ? button(m.doc === 'contract' ? 'View contract' : 'View offer', PAGE + m.key)
    : m.kind === 'invite' ? button('Choose a time', PAGE + m.key)
    : m.kind === 'expired' || m.kind === 'cancelled' || m.kind === 'not' ? ''
    : button('View your application', PAGE + m.key);
  return { subject, heading, body, block };
}

/* The caller's address as Cloudflare saw it: never the first
   X-Forwarded-For entry, which the caller writes. */
function ipOf(req: Request): string {
  const cf = (req.headers.get('cf-connecting-ip') || '').trim();
  if (cf) return cf.slice(0, 64);
  const xff = (req.headers.get('x-forwarded-for') || '').split(',').map((x) => x.trim()).filter(Boolean);
  return (xff[xff.length - 1] || '').slice(0, 64);
}

/* The candidate's code: no sign-in, the link's key and the document; the
   address, the name and the reference are the database's. */
async function sendCode(req: Request, b: Record<string, any>, origin: string | null): Promise<Response> {
  const key = String(b.key || ''), doc = String(b.docId || '');
  if (!/^[a-z0-9]{8}$/.test(key) || !/^[0-9a-f-]{36}$/.test(doc)) return json({ error: 'bad-request' }, 400, origin);
  if (!secret('RESEND_API_KEY')) return json({ error: 'mail-not-set-up' }, 200, origin);
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const r = await db.rpc('hiring_doc_code', { p_key: key, p_doc: doc, p_device: String(b.device || '').slice(0, 200), p_ip: ipOf(req) || null });
  const m = r.data as Record<string, any>;
  /* Answered alike whatever befalls (the audit of 2026-11-24): a wrong key
     or document, a failed send and a sent code all read Sent, so nobody
     can tell which documents exist; a failed send is in the Email log. Ten
     wrong codes in a Malaysian day lock the document until the next, and
     the page says so in its own words. */
  const alike = () => json({ ok: true }, 200, origin);
  if (r.error || !m) return alike();
  if (m.error === 'too-many' || m.error === 'locked-today') return json({ error: m.error }, 200, origin);
  if (m.error) return alike();
  if (!EMAIL.test(String(m.to || m.email || ''))) return alike();
  /* The one Verification code email (CLAUDE.md, VERIFICATION CODE
     TEMPLATE): the team's words, the code in its box, never in the subject. */
  const tpl = await db.rpc('code_email_template_read');
  const title = m.doc === 'contract' ? 'Employment Contract' : 'Employment Offer';
  const mail = codeEmail(tpl.error ? null : (tpl.data as Record<string, string> | null),
    { name: m.name, code: m.code, minutes: 15, purpose: 'to open your ' + title + ' ' + m.ref });
  const who = await sender('careers');
  const { status, provider, error } = await resend({
    from: who.from, reply_to: who.reply_to, to: [m.email], subject: mail.subject, html: mail.html, text: mail.text
  }, 'hire-code-' + doc + '-' + crypto.randomUUID(), secret('RESEND_API_KEY'));
  await fileSent({ kind: 'hiring_code', ref: doc, to: m.email, to_name: m.name, subject: mail.subject, reference: m.ref,
    status, provider, error });
  return alike();
}

/* Why an automatic email is not sent, as the Email log files it: the
   portal's Email or Automatic emails off, or its own template off. */
export function offOf(g: Record<string, any>, tpl: Record<string, any>, kind: string): string {
  if (!g.auto) return 'off: Automatic emails are off.';
  if (!tpl.on) return 'off: ' + (NAMES[kind] || 'This email') + ' is turned off in Email templates.';
  return '';
}

/* The emails the database queued: an offer or contract expired with no reply
   (2026-11-20), and a decision once its 30 seconds of Undo pass (Keep in
   talent pool, Not proceed; DECISION EMAILS QUEUED, 2026-11-24). Woken by the
   database alone; each claimed once and closed; a send is never repeated by
   itself. The gate is asked before anything is claimed (the review of
   2026-11-24): a gate that failed once marked every claimed email failed for
   good, so on a gate error nothing is claimed and the next wake asks again. */
async function drain(req: Request, origin: string | null): Promise<Response> {
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const given = req.headers.get('x-adspace-wake') || '';
  const woken = given.length >= 32 ? await db.rpc('wake_secret_ok', { p_given: given }) : null;
  if (!woken || woken.error || woken.data !== true) return json({ error: 'denied' }, 401, origin);
  if (!secret('RESEND_API_KEY')) return json({ error: 'mail-not-set-up' }, 200, origin);
  /* An automatic email (CANDIDATE EMAILS, 2026-11-21): sent only while the
     portal's Email, Automatic emails and its own template are on; else
     filed Not sent, never sent later. */
  const gate = await db.rpc('hiring_mail_gate', { p_kinds: ['expired', 'pool', 'not'] });
  const g = (gate.data || {}) as Record<string, any>;
  if (gate.error || g.error || !g.tpl) return json({ error: 'gate' }, 200, origin);
  const who = await sender('careers');
  let sent = 0;
  /* One email, sent or filed Not sent, and closed through `close`. */
  const one = async (m: Record<string, any>, tk: string, close: (st: string, err: string | null) => Promise<unknown>) => {
    const tpl = g.tpl[tk];
    if (!EMAIL.test(String(m.to || '')) || !tpl) { await close('failed', 'not sent: no address or template'); return; }
    const w = words(m, tpl);
    const off = offOf(g, tpl, tk);
    if (off) {
      await fileSent({ kind: 'hiring_' + tk, ref: m.id, to: m.to, to_name: m.name, subject: w.subject,
        body: w.body.replace('{invoices}', PAGE + '…'), reference: m.ref || m.position, status: 'failed', error: off });
      await close('failed', off);
      return;
    }
    const r = await resend({
      from: who.from, reply_to: who.reply_to, to: [m.to], subject: w.subject,
      html: layout({ heading: w.heading, body: w.body, block: w.block || undefined, preheader: w.subject }),
      text: w.body.replace('{invoices}', PAGE + m.key)
    }, 'hire-' + tk + '-' + m.id, secret('RESEND_API_KEY'));
    await fileSent({ kind: 'hiring_' + tk, ref: m.id, to: m.to, to_name: m.name, subject: w.subject,
      body: w.body.replace('{invoices}', PAGE + '…'), reference: m.ref || m.position,
      status: r.status, provider: r.provider, error: r.error });
    await close(r.status, r.error || null);
    if (r.status === 'sent') sent++;
  };
  const exp = await db.rpc('hiring_expire_mail_claim');
  for (const m of (exp.error ? [] : (exp.data as Record<string, any>[]) || [])) {
    await one(m, 'expired', (st) => db.rpc('hiring_expire_mail_done', { p_doc: m.id, p_status: st }));
  }
  const dec = await db.rpc('hiring_outcome_mail_claim');
  for (const m of (dec.error ? [] : (dec.data as Record<string, any>[]) || [])) {
    await one(m, String(m.kind), (st, err) => db.rpc('hiring_outcome_mail_close', { p_id: m.id, p_status: st, p_error: err }));
  }
  return json({ ok: true, sent }, 200, origin);
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  let b: Record<string, any>;
  try { b = await req.json(); } catch { return json({ error: 'bad-request' }, 400, origin); }
  if (b && b.kind === 'code') return sendCode(req, b, origin);
  if (b && b.action === 'drain') return drain(req, origin);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
  const kind = String(b.kind || ''), outcome = kind === 'outcome', isDoc = kind === 'doc', isConfirmed = kind === 'confirmed';
  const id = String((outcome ? b.candidateId : isDoc || isConfirmed ? b.docId : b.interviewId) || '');
  if (!/^[0-9a-f-]{36}$/.test(id) || !['invite', 'confirm', 'rescheduled', 'held', 'moved', 'cancelled', 'outcome', 'doc', 'confirmed'].includes(kind)) return json({ error: 'bad-request' }, 400, origin);
  if (!secret('RESEND_API_KEY')) return json({ error: 'mail-not-set-up' }, 200, origin);

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });
  const prep = outcome ? await db.rpc('hiring_outcome_mail_prepare', { p_id: id })
    : isDoc ? await db.rpc('hiring_doc_mail_prepare', { p_doc: id })
    : isConfirmed ? await db.rpc('hiring_confirmed_mail_prepare', { p_doc: id })
    : await db.rpc('hiring_mail_prepare', { p_interview: id, p_kind: kind });
  if (prep.error) return json({ error: 'denied' }, 200, origin);
  const m = prep.data as Record<string, any>;
  if (!m || m.error) return json({ error: (m && m.error) || 'denied' }, 200, origin);
  if (!EMAIL.test(String(m.to || ''))) return json({ error: 'bad-email' }, 200, origin);

  /* Automatic, or by hand (CANDIDATE EMAILS, 2026-11-21): a step's email is
     an automatic email, sent only while the portal's Email, Automatic emails
     and its own template are on, else filed Not sent and the step left done;
     Send again in the Email log and Email candidate on a card are sends by
     hand, asking the portal's Email, Send by email and the group's Send
     email. */
  const again = /^[0-9a-f-]{36}$/.test(String(b.againOf || '')) ? String(b.againOf) : '';
  const byHand = Boolean(again) || b.byHand === true;
  const tk = templateOf(m);
  const gate = await db.rpc('hiring_mail_gate', { p_kinds: [tk] });
  const g = (gate.data || {}) as Record<string, any>, tpl = g.tpl && g.tpl[tk];
  if (gate.error || g.error || !tpl) return json({ error: gate.error ? 'needs-update' : g.error || 'needs-update' }, 200, origin);
  if (byHand && !g.hand) return json({ error: 'send-off' }, 200, origin);
  const w = words(m, tpl);
  const off = byHand ? '' : offOf(g, tpl, tk);
  const done = (st: string, err: string | null) => isDoc ? db.rpc('hiring_doc_mail_done', { p_doc: id, p_status: st, p_error: err })
    : isConfirmed ? db.rpc('hiring_confirmed_mail_done', { p_doc: id, p_status: st, p_error: err })
    : outcome ? db.rpc('hiring_outcome_mail_done', { p_id: id, p_status: st, p_error: err })
    : db.rpc('hiring_mail_done', { p_interview: id, p_kind: kind, p_status: st, p_error: err });
  if (off) {
    await fileSent({ kind: 'hiring_' + (outcome ? m.kind : kind), ref: id, to: m.to, to_name: m.name, subject: w.subject,
      body: w.body.replace('{invoices}', PAGE + '…'), reference: m.ref || m.position, by: callerEmail(auth), status: 'failed', error: off });
    await done('failed', off);
    return json({ ok: true, skipped: g.auto ? 'template-off' : 'auto-off' }, 200, origin);
  }
  const who = await sender('careers');
  const msg: Record<string, unknown> = {
    from: who.from, reply_to: who.reply_to, to: [m.to], subject: w.subject,
    html: layout({ heading: w.heading, body: w.body, block: w.block || undefined, preheader: w.subject }),
    text: w.body.replace('{invoices}', PAGE + m.key)
  };
  /* A decision's key carries the decision's kind, so a reopened candidate
     decided again is emailed again. */
  /* A document's key carries its sending, so a document sent back is
     emailed again. */
  /* Sent again from Messages' Email log (SEND AGAIN, 2026-11-18): a key of
     its own, so Resend never answers it with the first send, and filed as
     sending that email again. */
  /* A decision date's key carries the date, so a date moved is emailed
     again; a confirmation's carries the interview's time, so a time changed
     is confirmed again (Change interview time, 2026-11-22); the time
     changed carries the move's own moment, so each move is emailed once and
     a second move emails again. */
  const { status, provider, error } = await resend(msg, 'hire-' + (outcome ? m.kind : kind) + '-' + id + (isDoc ? '-' + String(m.sent_key || '') : '') +
    (kind === 'held' || kind === 'moved' ? '-' + String(m.decide_by || '').replace(/[^0-9a-z]/gi, '') : '') +
    (kind === 'confirm' ? '-' + String(m.when || '').replace(/[^0-9a-z]/gi, '') : '') +
    (kind === 'rescheduled' ? '-' + String(m.when || '').replace(/[^0-9a-z]/gi, '') + '-' + String(m.moved_key || '') : '') +
    (again ? '-again-' + crypto.randomUUID() : ''), secret('RESEND_API_KEY'));
  await fileSent({ kind: 'hiring_' + (outcome ? m.kind : kind), ref: id, to: m.to, to_name: m.name, subject: w.subject,
    body: w.body.replace('{invoices}', PAGE + '…'), reference: m.ref || m.position, by: callerEmail(auth), status, provider, error,
    again_of: again || undefined });
  await done(status, error || null);
  return json(status === 'sent' ? { ok: true } : { error: status === 'unknown' ? 'unknown' : 'not-sent' }, 200, origin);
});
