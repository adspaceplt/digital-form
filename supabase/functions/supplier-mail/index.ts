/*
 * supplier-mail — emails a supplier from its record, sent by hand through
 * Resend (2026-10-18; 2026-10-18-supplier-emails.sql).
 *
 *   POST { supplier, purpose, document, cc, subject, body, again, pdf,
 *          filename }      a colleague at Suppliers Work, from the Send
 *                          email sheet. Who it goes to, the fields filled
 *                          into the words and the document are the
 *                          database's answer as the colleague
 *                          (`supplier_email_begin`, which files the send
 *                          before it goes and refuses `recent` unless
 *                          `again`), never the page's. A document's PDF is
 *                          the page's drawing, and must be a PDF naming the
 *                          document's own reference. The send is closed
 *                          (`supplier_email_done`) as sent, failed, or not
 *                          confirmed where Resend's answer never came.
 *   POST from Resend       its webhook (svix-id, svix-timestamp and
 *                          svix-signature headers): the body is believed
 *                          only with its signature, keyed by
 *                          RESEND_WEBHOOK_SECRET, and no older than five
 *                          minutes; delivered, opened, bounced and
 *                          complained reach `supplier_email_status` with the
 *                          service role, which alone may call it.
 *
 *   POST { client: true, kind, ref, contact, cc, subject, body, again, pdf,
 *          filename }      a client's quotation, Letter of Offer or client
 *                          letter (2026-10-31,
 *                          2026-10-31-client-document-emails.sql), from the
 *                          Send by email sheet: the record's part at Work
 *                          and the client in scope. The recipient, the copy
 *                          and the reply-to (the colleague who sends) are
 *                          `client_email_begin`'s answer; the PDF is the
 *                          page's drawing and must name the record's own
 *                          reference. From MAIL_CLIENT_FROM (unset:
 *                          ADspace <noreply-client@sc.adspace.me>).
 *
 * The email is the portal's one layout (_shared/mail.ts, the sign-in
 * emails' white card on the light grey page, docs/SIGN-IN-EMAILS.md): the subject as its heading,
 * then the message the colleague wrote in the Send email sheet, word for
 * word as plain paragraphs, escaped; nothing else is added but a document's
 * verify line (the user, 2026-10-27: one content box, sent as it was typed). From MAIL_FROM (unset: ADspace <noreply-supplier@sc.adspace.me>),
 * replies to MAIL_REPLY_TO (unset: ap@adspacestudios.com).
 *
 * Secrets: RESEND_API_KEY, RESEND_WEBHOOK_SECRET (the webhook's signing
 *          secret, whsec_…), optionally MAIL_FROM and MAIL_REPLY_TO, plus the
 *          platform's SUPABASE_URL, SUPABASE_ANON_KEY and
 *          SUPABASE_SERVICE_ROLE_KEY. docs/SUPPLIER-EMAIL-SETUP.md.
 *
 * Verify JWT is off: Resend calls with no session. A refusal the person can
 * act on answers 200 with { error }.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { pdfFrom, namesRef } from '../_shared/pdfref.ts';
import { cors, json } from '../_shared/cors.ts';
import { layout, resend } from '../_shared/mail.ts';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
const FROM = () => secret('MAIL_FROM') || 'ADspace <noreply-supplier@sc.adspace.me>';
const REPLY_TO = () => secret('MAIL_REPLY_TO') || 'ap@adspacestudios.com';
const CLIENT_FROM = () => secret('MAIL_CLIENT_FROM') || 'ADspace <noreply-client@sc.adspace.me>';
/* A client email with no colleague's address to reply to goes to the
   account manager's (MAIL_CLIENT_REPLY_TO, unset: js/config.js's
   accountEmail). */
const CLIENT_REPLY_TO = () => secret('MAIL_CLIENT_REPLY_TO') || 'marketing@adspacestudios.com';
// ---- The document's PDF, as wa-send reads a letter's ----------------------
function b64Of(b: Uint8Array): string {
  let s = '';
  for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000));
  return btoa(s);
}

// ---- Resend's webhook -------------------------------------------------------
/* Svix's signature: `v1,` and the base64 HMAC-SHA256 of `id.timestamp.body`,
   keyed by the secret after its `whsec_`. Any of the signatures given may
   match; the time must be within five minutes. */
async function svixOk(raw: string, id: string, ts: string, sigs: string): Promise<boolean> {
  const s = secret('RESEND_WEBHOOK_SECRET');
  if (!s || !id || !ts || !sigs) return false;
  const t = Number(ts);
  if (!Number.isFinite(t) || Math.abs(Date.now() / 1000 - t) > 300) return false;
  let keyBytes: Uint8Array;
  try { keyBytes = Uint8Array.from(atob(s.replace(/^whsec_/, '')), (c) => c.charCodeAt(0)); } catch { return false; }
  const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(id + '.' + ts + '.' + raw)));
  const want = b64Of(mac);
  return sigs.split(' ').some((x) => {
    const g = x.split(',')[1] || '';
    if (g.length !== want.length) return false;
    let diff = 0;
    for (let i = 0; i < want.length; i++) diff |= want.charCodeAt(i) ^ g.charCodeAt(i);
    return diff === 0;
  });
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);

  const svixId = req.headers.get('svix-id');
  if (svixId) {
    const raw = await req.text();
    if (!(await svixOk(raw, svixId, req.headers.get('svix-timestamp') || '', req.headers.get('svix-signature') || ''))) {
      return new Response('Forbidden', { status: 403 });
    }
    let ev: Record<string, any> = {};
    try { ev = JSON.parse(raw); } catch { return new Response('ok', { status: 200 }); }
    const emailId = String((ev.data || {}).email_id || '');
    if (emailId) {
      const svc = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
      const r = await svc.rpc('supplier_email_status', { p_provider: emailId, p_event: String(ev.type || ''),
        p_at: String(ev.created_at || new Date().toISOString()) });
      if (r.error) console.error('supplier-mail: status not recorded', r.error.message);
    }
    return new Response('ok', { status: 200 });
  }

  if (!secret('RESEND_API_KEY')) return json({ error: 'mail-not-set-up' }, 200, origin);
  let body: Record<string, any> = {};
  try { body = await req.json(); } catch { return json({ error: 'bad-request' }, 400, origin); }
  const uuid = /^[0-9a-f-]{36}$/i;
  if (body.client === true) return clientMail(req, body, origin, uuid);
  const supplier = String(body.supplier || ''), purpose = String(body.purpose || '');
  const document = body.document ? String(body.document) : null;
  if (!uuid.test(supplier) || (document && !uuid.test(document)) || !['approved', 'document'].includes(purpose)) {
    return json({ error: 'bad-request' }, 400, origin);
  }
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });

  /* A document's PDF is read before anything is filed, so a wrong file
     files nothing. */
  let attach: { filename: string; content: string } | null = null;
  if (purpose === 'document') {
    const prep = await db.rpc('supplier_email_prepare', { p_supplier: supplier, p_purpose: purpose, p_document: document });
    if (prep.error) return json({ error: 'needs-update' }, 200, origin);
    const p = (prep.data || {}) as Record<string, any>;
    if (p.error) return json({ error: p.error }, 200, origin);
    const bytes = pdfFrom(String(body.pdf || ''));
    if (!bytes || !(await namesRef(bytes, String((p.document || {}).serial || '')))) return json({ error: 'bad-file' }, 200, origin);
    const filename = String(body.filename || 'Document.pdf').replace(/[\\/:*?"<>|]+/g, ' ').slice(0, 200);
    attach = { filename: /\.pdf$/i.test(filename) ? filename : filename + '.pdf', content: b64Of(bytes) };
  }

  const begun = await db.rpc('supplier_email_begin', { p_supplier: supplier, p_purpose: purpose, p_document: document,
    p_cc: body.cc === true, p_subject: String(body.subject || ''), p_body: String(body.body || ''), p_again: body.again === true });
  if (begun.error) return json({ error: 'needs-update' }, 200, origin);
  const b = (begun.data || {}) as Record<string, any>;
  if (b.error) return json(b, 200, origin);

  const doc = (b.document || null) as Record<string, string> | null;
  /* The heading is the subject as sent, less its closing " · ADspace" (the
     wordmark above it says so). */
  const heading = String(b.subject || '').replace(/\s*[·|-]\s*ADspace\s*$/i, '').trim() ||
    (purpose === 'approved' ? 'Supplier registration approved' : String((doc && doc.kind) || 'Document'));
  const html = layout({
    heading,
    body: String(b.body || ''),
    foot: doc ? 'Verify this document at digital.adspace.me/verify.' : '',
    preheader: String(b.subject || '')
  });
  const msg: Record<string, unknown> = {
    from: FROM(), to: [String((b.to || {}).email || '')], reply_to: REPLY_TO(),
    subject: String(b.subject || ''), html, text: String(b.body || '')
  };
  if (b.cc) msg.cc = [String(b.cc)];
  if (attach) msg.attachments = [attach];

  const { status, provider, error } = await resend(msg, String(b.id), secret('RESEND_API_KEY'));
  const done = await db.rpc('supplier_email_done', { p_id: b.id, p_status: status, p_provider: provider || null, p_error: error || null });
  if (done.error) console.error('supplier-mail: not closed', done.error.message);
  if (status !== 'sent') console.error('supplier-mail:', status, error);
  return json(status === 'sent' ? { ok: true, id: b.id } : { error: status === 'unknown' ? 'not-confirmed' : 'not-sent' }, 200, origin);
});

/* A client's quotation, Letter of Offer or client letter, emailed by hand
   (2026-10-31): the PDF read and checked before anything is filed, then
   filed, sent and closed as the supplier's email is. */
async function clientMail(req: Request, body: Record<string, any>, origin: string | null, uuid: RegExp): Promise<Response> {
  const kind = String(body.kind || ''), ref = String(body.ref || '');
  const contact = body.contact ? String(body.contact) : null;
  if (!['quotation', 'offer', 'letter'].includes(kind) || !uuid.test(ref) || (contact && !uuid.test(contact))) {
    return json({ error: 'bad-request' }, 400, origin);
  }
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
  const prep = await db.rpc('client_email_prepare', { p_kind: kind, p_ref: ref, p_contact: contact });
  if (prep.error) return json({ error: 'needs-update' }, 200, origin);
  const p = (prep.data || {}) as Record<string, any>;
  if (p.error) return json({ error: p.error }, 200, origin);
  const bytes = pdfFrom(String(body.pdf || ''));
  if (!bytes || !(await namesRef(bytes, String((p.document || {}).serial || '')))) return json({ error: 'bad-file' }, 200, origin);
  const filename = String(body.filename || 'Document.pdf').replace(/[\\/:*?"<>|]+/g, ' ').slice(0, 200);
  const attach = { filename: /\.pdf$/i.test(filename) ? filename : filename + '.pdf', content: b64Of(bytes) };

  const begun = await db.rpc('client_email_begin', { p_kind: kind, p_ref: ref, p_contact: contact, p_cc: body.cc === true,
    p_subject: String(body.subject || ''), p_body: String(body.body || ''), p_again: body.again === true });
  if (begun.error) return json({ error: 'needs-update' }, 200, origin);
  const b = (begun.data || {}) as Record<string, any>;
  if (b.error) return json(b, 200, origin);

  const doc = (b.document || {}) as Record<string, string>;
  const heading = String(b.subject || '').replace(/\s*[·|-]\s*ADspace\s*$/i, '').trim() || String(doc.title || 'Document');
  const html = layout({
    heading,
    body: String(b.body || ''),
    foot: kind === 'quotation' ? '' : 'Verify this document at digital.adspace.me/verify.',
    preheader: String(b.subject || '')
  });
  const msg: Record<string, unknown> = {
    from: CLIENT_FROM(), to: [String((b.to || {}).email || '')], reply_to: String(b.reply_to || '') || CLIENT_REPLY_TO(),
    subject: String(b.subject || ''), html, text: String(b.body || ''), attachments: [attach]
  };
  if (b.cc) msg.cc = [String(b.cc)];

  const { status, provider, error } = await resend(msg, String(b.id), secret('RESEND_API_KEY'));
  const done = await db.rpc('client_email_done', { p_id: b.id, p_status: status, p_provider: provider || null, p_error: error || null });
  if (done.error) console.error('supplier-mail: client email not closed', done.error.message);
  if (status !== 'sent') console.error('supplier-mail:', status, error);
  return json(status === 'sent' ? { ok: true, id: b.id } : { error: status === 'unknown' ? 'not-confirmed' : 'not-sent' }, 200, origin);
}
