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
 * The email is the portal's one layout (the sign-in emails' white card on
 * the light grey page, docs/SIGN-IN-EMAILS.md): the subject as its heading,
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

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
const FROM = () => secret('MAIL_FROM') || 'ADspace <noreply-supplier@sc.adspace.me>';
const REPLY_TO = () => secret('MAIL_REPLY_TO') || 'ap@adspacestudios.com';
const SEND_TIMEOUT_MS = 25000;
/* Deno's words for a request that failed before it was sent. Anything else
   may have reached Resend, and is filed as not confirmed. */
const NEVER_LEFT = /client error \(Connect\)|dns error|failed to lookup address|name or service not known|no such host|connection refused|tcp connect error|network is unreachable|no route to host|invalid peer certificate|certificate verify failed|tls handshake|handshake failure/i;

// ---- The document's PDF, as wa-send reads a letter's ----------------------
function b64Of(b: Uint8Array): string {
  let s = '';
  for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000));
  return btoa(s);
}

// ---- The email --------------------------------------------------------------
const esc = (s: unknown) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' } as Record<string, string>)[c]);
const FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";
function paras(body: string): string[] {
  return String(body || '').replace(/\r/g, '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
}
export function layout(o: { heading: string; body: string; foot?: string; preheader?: string }): string {
  const ps = paras(o.body).map((p) =>
    '<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#524e47;">' + p.split('\n').map(esc).join('<br>') + '</p>').join('');
  return '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">' +
    '<meta name="x-apple-disable-message-reformatting"><title>' + esc(o.heading) + '</title>' +
    '<style>@media (max-width:600px){.card{padding:24px !important;}.foot{padding:24px 24px 0 !important;}h1{font-size:21px !important;}}</style></head>' +
    '<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">' +
    '<div style="display:none;max-height:0;overflow:hidden;opacity:0;">' + esc(o.preheader || o.heading) + '</div>' +
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">' +
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">' +
    '<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:32px;font-family:' + FONT + ';color:#1b1a17;">' +
    '<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="112" style="display:block;width:112px;height:auto;border:0;outline:none;">' +
    '<h1 style="margin:24px 0 16px;font-size:24px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">' + esc(o.heading) + '</h1>' +
    ps +
    (o.foot ? '<p style="margin:8px 0 0;padding-top:16px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">' + esc(o.foot) + '</p>' : '') +
    '</td></tr>' +
    '<tr><td class="foot" style="padding:24px 32px 0;font-family:' + FONT + ';font-size:12px;line-height:1.6;color:#6b6760;">' +
    'ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>' +
    '(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>' +
    '<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#6b6760;">This email and any attachments are confidential and may be privileged. ' +
    'If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.</p>' +
    '</td></tr></table></td></tr></table></body></html>';
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

  let status = 'failed', provider = '', error = '';
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), SEND_TIMEOUT_MS);
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST', signal: ctl.signal,
      headers: { 'Authorization': 'Bearer ' + secret('RESEND_API_KEY'), 'Content-Type': 'application/json',
        'Idempotency-Key': String(b.id) },
      body: JSON.stringify(msg)
    }).finally(() => clearTimeout(timer));
    const out = await res.json().catch(() => null) as Record<string, any> | null;
    if (res.ok && out && out.id) { status = 'sent'; provider = String(out.id); }
    else if (res.status >= 500 || (res.ok && !out)) { status = 'unknown'; error = ('unknown: ' + res.status + ' ' + ((out && out.message) || '')).trim(); }
    else error = [res.status, out && out.name, out && out.message].filter(Boolean).join(' ');
  } catch (e) {
    const m = String((e && (e as Error).message) || e);
    if (NEVER_LEFT.test(m)) error = 'not sent: ' + m;
    else { status = 'unknown'; error = 'unknown: ' + m; }
  }
  const done = await db.rpc('supplier_email_done', { p_id: b.id, p_status: status, p_provider: provider || null, p_error: error || null });
  if (done.error) console.error('supplier-mail: not closed', done.error.message);
  if (status !== 'sent') console.error('supplier-mail:', status, error);
  return json(status === 'sent' ? { ok: true, id: b.id } : { error: status === 'unknown' ? 'not-confirmed' : 'not-sent' }, 200, origin);
});
