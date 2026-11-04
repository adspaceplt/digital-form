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
 *   POST { manual: true, audience, client, supplier, template, to, ccs,
 *          subject, body, key, file }
 *                          a New email from Messages, Email (2026-11-04,
 *                          2026-11-04-new-email.sql) at Messages Work: To and
 *                          Copy a client's or a supplier's own addresses, or
 *                          one typed (`other`); `email_new_begin` holds them,
 *                          fills the words and files it before it goes, one
 *                          key a sheet. A file is optional, 10 MB at most, of
 *                          the kinds ATTACH names, a PDF that is a PDF. From
 *                          MAIL_CLIENT_FROM, a supplier's from MAIL_FROM;
 *                          replies to the colleague who sends.
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
      const at = String(ev.created_at || new Date().toISOString());
      const r = await svc.rpc('supplier_email_status', { p_provider: emailId, p_event: String(ev.type || ''), p_at: at });
      if (r.error) console.error('supplier-mail: status not recorded', r.error.message);
      /* A status can arrive before its sender has closed the email (the
         provider id is kept only then): asked again for ten minutes, so the
         webhook's retry finds it; an email no log holds is let go after
         that (audit 2026-11-04). */
      const fresh = Date.now() - new Date(at).getTime() < 10 * 60 * 1000;
      if (!r.error && (r.data || {}).error === 'not-found' && fresh) return new Response('retry', { status: 503 });
    }
    return new Response('ok', { status: 200 });
  }

  if (!secret('RESEND_API_KEY')) return json({ error: 'mail-not-set-up' }, 200, origin);
  let body: Record<string, any> = {};
  try { body = await req.json(); } catch { return json({ error: 'bad-request' }, 400, origin); }
  const uuid = /^[0-9a-f-]{36}$/i;
  if (body.manual === true) return manualMail(req, body, origin, uuid);
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

/* A New email (2026-11-04): the file read and checked before anything is
   filed, then filed, sent and closed as a client's document email is. */
const ATTACH: Record<string, string> = {
  pdf: 'application/pdf', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp',
  doc: 'application/msword', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ppt: 'application/vnd.ms-powerpoint', pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  csv: 'text/csv'
};
const ATTACH_MAX = 10 * 1024 * 1024;
export function fileOf(f: unknown): { filename: string; content: string } | 'bad-file' | 'too-big' | null {
  if (!f || typeof f !== 'object') return null;
  const o = f as Record<string, unknown>;
  const name = String(o.name || '').replace(/[\\/:*?"<>|\x00-\x1f]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 200);
  const ext = ((name.match(/\.([a-z0-9]+)$/i) || [])[1] || '').toLowerCase();
  if (!name || !ATTACH[ext]) return 'bad-file';
  const data = String(o.data || '');
  if (data.length > Math.ceil(ATTACH_MAX / 3) * 4 + 4) return 'too-big';
  let bytes: Uint8Array;
  try { bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0)); } catch { return 'bad-file'; }
  if (!bytes.length) return 'bad-file';
  if (bytes.length > ATTACH_MAX) return 'too-big';
  if (ext === 'pdf' && !(bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46)) return 'bad-file';
  return { filename: name, content: b64Of(bytes) };
}
async function manualMail(req: Request, body: Record<string, any>, origin: string | null, uuid: RegExp): Promise<Response> {
  const audience = String(body.audience || '');
  const client = body.client ? String(body.client) : null, supplier = body.supplier ? String(body.supplier) : null;
  const template = body.template ? String(body.template) : null;
  if (!['client', 'supplier', 'other'].includes(audience) || (client && !uuid.test(client)) || (supplier && !uuid.test(supplier)) ||
      (template && !uuid.test(template))) {
    return json({ error: 'bad-request' }, 400, origin);
  }
  const file = fileOf(body.file);
  if (file === 'bad-file' || file === 'too-big') return json({ error: file }, 200, origin);
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
  const ccs = Array.isArray(body.ccs) ? body.ccs.filter((x: unknown) => typeof x === 'string').slice(0, 6) : [];
  const begun = await db.rpc('email_new_begin', { p_audience: audience, p_client: client, p_supplier: supplier, p_template: template,
    p_to: String(body.to || ''), p_ccs: ccs, p_subject: String(body.subject || ''), p_body: String(body.body || ''),
    p_attachment: file ? file.filename : null, p_idem: String(body.key || '') });
  if (begun.error) return json({ error: 'needs-update' }, 200, origin);
  const b = (begun.data || {}) as Record<string, any>;
  if (b.error) return json(b, 200, origin);
  const html = layout({ heading: String(b.subject || ''), body: String(b.body || ''), preheader: String(b.subject || '') });
  const msg: Record<string, unknown> = {
    from: audience === 'supplier' ? FROM() : CLIENT_FROM(), to: [String(b.to || '')],
    reply_to: String(b.reply_to || '') || (audience === 'supplier' ? REPLY_TO() : CLIENT_REPLY_TO()),
    subject: String(b.subject || ''), html, text: String(b.body || '')
  };
  const cc = Array.isArray(b.cc_list) ? b.cc_list.map(String).filter(Boolean) : [];
  if (cc.length) msg.cc = cc;
  if (file) msg.attachments = [file];
  const { status, provider, error } = await resend(msg, String(b.id), secret('RESEND_API_KEY'));
  const done = await db.rpc('email_new_done', { p_id: b.id, p_status: status, p_provider: provider || null, p_error: error || null });
  if (done.error) console.error('supplier-mail: new email not closed', done.error.message);
  if (status !== 'sent') console.error('supplier-mail:', status, error);
  return json(status === 'sent' ? { ok: true, id: b.id, to: b.to, cc: b.cc || null } : { error: status === 'unknown' ? 'not-confirmed' : 'not-sent' }, 200, origin);
}
