/*
 * The portal's one email (2026-10-28): its layout and its send through
 * Resend, shared by supplier-mail (a supplier's email) and bukku-sync (an
 * overdue invoice reminder), so the two never drift apart.
 *
 *   layout({ heading, body, foot, preheader, block, fine })
 *     the sign-in emails' white card on the light grey page
 *     (docs/SIGN-IN-EMAILS.md): the wordmark, the heading, the message as
 *     typed (escaped, a blank line between paragraphs), `block` (HTML the
 *     server built, never a page's) in place of a paragraph reading
 *     `{invoices}`, then `foot` under a hairline; under the card the
 *     company's line and the fine print (`fine`, else the standing
 *     confidentiality line) in the palette's light grey #a1a1a1, very light
 *     as fine print reads (the user, 2026-11-11), the company's line in the
 *     dark grey. Text is #1a1a1a, never true black, the rest the palette's
 *     #515151, #f5f5f5 and #ffffff (the user, 2026-11-09); the address breaks before its postcode, and Apple
 *     Mail's number and address detection is kept from recolouring it.
 *   resend(msg, key)
 *     posts one email with an idempotency key; answers sent with Resend's
 *     id, failed, or unknown where the answer never came (filed as Not
 *     confirmed, never sent again by itself). A request that never left
 *     (DNS, connect, TLS) is failed with `not sent:`.
 */
export const esc = (s: unknown) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' } as Record<string, string>)[c]);
export const FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";
const CONFIDENTIAL = 'This email and any attachments are confidential and may be privileged. ' +
  'If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.';

/* A currency and its figure never part at a line's end: RM and S$ are
   joined to the figure by a no-break space, made from its code so the
   deployed copy reads as the repo's (an escape is rewritten by the
   connector, the character itself looks like a space). */
const NBSP = String.fromCharCode(160);
export const joinMoney = (t: string) => String(t).replace(/\b(RM|S\$) +(?=[-\d])/g, '$1' + NBSP);
function paras(body: string): string[] {
  return String(body || '').replace(/\r/g, '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
}
/* The public page a document is checked on: the server's copy of
   ADSPACE_ORG.verifyUrl (js/config.js), which a function cannot read;
   `tests/mailfn.js` holds the two alike. */
export const VERIFY_URL = 'digital.adspace.me/verify';
export const BLOCK = /^\{\s*invoices\s*\}$/i;
/* `{invoices}` set in a line of its own words stands as its own paragraph,
   so the table is drawn wherever it was typed (review 2026-10-29, 3). */
const TOKEN = /\{\s*invoices\s*\}/i;

export function layout(o: { heading: string; body: string; foot?: string; preheader?: string; block?: string; fine?: string[] }): string {
  const body = o.block ? String(o.body || '').replace(TOKEN, '\n\n{invoices}\n\n') : o.body;
  const ps = paras(body).map((p) => (o.block && BLOCK.test(p)) ? o.block :
    '<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#1a1a1a;">' + p.split('\n').map((l) => joinMoney(esc(l))).join('<br>') + '</p>').join('');
  const fine = (o.fine && o.fine.filter(Boolean).length ? o.fine.filter(Boolean) : [CONFIDENTIAL])
    .map((t) => '<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#a1a1a1;">' + esc(t) + '</p>').join('');
  return '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">' +
    '<meta name="x-apple-disable-message-reformatting"><meta name="format-detection" content="telephone=no,date=no,address=no,email=no"><title>' + esc(o.heading) + '</title>' +
    '<style>a[x-apple-data-detectors]{color:inherit !important;text-decoration:none !important;font:inherit !important;}@media (max-width:600px){.card{padding:24px !important;}.foot{padding:24px 24px 0 !important;}h1{font-size:21px !important;}.hide-sm{display:none !important;}}</style></head>' +
    '<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">' +
    '<div style="display:none;max-height:0;overflow:hidden;opacity:0;">' + esc(o.preheader || o.heading) + '</div>' +
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">' +
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">' +
    '<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:32px;font-family:' + FONT + ';color:#1a1a1a;">' +
    '<a href="https://adspace.me" style="display:inline-block;text-decoration:none;border:0;"><img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="91" height="26" style="display:block;width:91px;height:26px;border:0;outline:none;"></a>' +
    '<h1 style="margin:24px 0 16px;font-size:24px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1a1a1a;">' + esc(o.heading) + '</h1>' +
    ps +
    (o.foot ? '<p style="margin:8px 0 0;padding-top:16px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#515151;">' + esc(o.foot) + '</p>' : '') +
    '</td></tr>' +
    '<tr><td class="foot" style="padding:24px 32px 0;font-family:' + FONT + ';font-size:12px;line-height:1.6;color:#515151;">' +
    'ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin,<br>81100 Johor Bahru, Johor, Malaysia<br>' +
    '(60)18 762 5233 · <a href="https://adspace.me" style="color:#515151;text-decoration:none;">adspace.me</a>' +
    fine +
    /* The portal's own line (the user, 2026-11-18), a row under the fine
       print in its light grey: the year is Malaysia's at the send. */
    '<p style="margin:24px 0 0;font-size:11px;line-height:1.5;color:#a1a1a1;">&copy; ' +
      new Date(Date.now() + 8 * 3600e3).getUTCFullYear() + ' ADSPACE PLT. All Rights Reserved.</p>' +
    '</td></tr></table></td></tr></table></body></html>';
}

/* The email's one button (the action blue, words in white, 15/500, 12px
   24px, the 10px corner), shared by every function that sends one
   (supplier-mail, creator-mail, hiring-mail, invite-member, bukku-sync;
   unslop 2, 2026-11-26), drawn where a paragraph reads `{invoices}` through
   `layout`'s `block`. `margin` sets the space around it. */
export function button(a: { label: string; url: string; margin?: string }): string {
  return '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:' + (a.margin || '8px 0 16px') + ';"><tr><td style="background:#0071e3;border-radius:10px;">' +
    '<a href="' + esc(a.url) + '" style="display:inline-block;padding:12px 24px;text-align:center;font-family:' + FONT + ';font-size:15px;line-height:20px;font-weight:500;color:#ffffff;text-decoration:none;">' +
    esc(a.label) + '</a></td></tr></table>';
}

/* Deno's words for a request that failed before it was sent. Anything else
   may have reached Resend, and is filed as not confirmed. */
const NEVER_LEFT = /client error \(Connect\)|dns error|failed to lookup address|name or service not known|no such host|connection refused|tcp connect error|network is unreachable|no route to host|invalid peer certificate|certificate verify failed|tls handshake|handshake failure/i;
const SEND_TIMEOUT_MS = 25000;

export async function resend(msg: Record<string, unknown>, key: string, apiKey: string): Promise<{ status: string; provider: string; error: string }> {
  let status = 'failed', provider = '', error = '';
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), SEND_TIMEOUT_MS);
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST', signal: ctl.signal,
      headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json', 'Idempotency-Key': key },
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
  return { status, provider, error };
}

/* The Verification code email (VERIFICATION CODE TEMPLATE, 2026-11-17): the
   one template every code the portal sends goes out in, its words the
   team's (Settings, Messages, Email templates, Sign-in and codes). {name},
   {minutes} and {purpose} are filled as words; {code} stands in the shaded
   box where it has a paragraph of its own, else as its digits. The code is
   never in the subject or the preview line a lock screen shows. */
export const CODE_WORDS = {
  subject: 'Your ADspace verification code {purpose}',
  body: 'Dear {name},\n\nPlease enter the following code {purpose}:\n\n{code}\n\nThe code expires in {minutes} minutes.\n\nYours sincerely,\nADspace',
  foot: 'The code may be used once. If you did not request it, please disregard this email; nothing is signed without the code.'
};
export function codeEmail(t: { subject?: string; body?: string; foot?: string } | null,
  v: { name: string; code: string; minutes: number | string; purpose: string }): { subject: string; html: string; text: string } {
  const w = { subject: (t && t.subject) || CODE_WORDS.subject, body: (t && t.body) || CODE_WORDS.body, foot: t && typeof t.foot === 'string' ? t.foot : CODE_WORDS.foot };
  const fill = (s: string) => s.replace(/\{\s*name\s*\}/gi, () => v.name).replace(/\{\s*minutes\s*\}/gi, () => String(v.minutes))
    .replace(/\{\s*purpose\s*\}/gi, () => v.purpose).replace(/\s+([.,:;])/g, '$1');
  const subject = fill(w.subject.replace(/\{\s*code\s*\}/gi, '')).replace(/\s+/g, ' ').trim();
  const body = fill(w.body);
  const foot = fill(w.foot).trim();
  const box = '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;border-radius:10px;margin:4px 0 24px;"><tr><td align="center" style="padding:16px 24px 16px 28px;text-align:center;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:28px;line-height:1.2;font-weight:600;letter-spacing:4px;color:#1a1a1a;">' + esc(v.code) + '</td></tr></table>';
  const own = paras(body).some((p) => /^\{\s*code\s*\}$/i.test(p));
  const html = layout({
    heading: 'Your verification code', preheader: subject + '.', block: own ? box : undefined,
    body: own ? body.replace(/\{\s*code\s*\}/i, '{invoices}').replace(/\{\s*code\s*\}/gi, () => v.code) : body.replace(/\{\s*code\s*\}/gi, () => v.code),
    foot: foot || undefined
  });
  const text = body.replace(/\{\s*code\s*\}/gi, () => v.code) + (foot ? '\n\n' + foot : '');
  return { subject, html, text };
}
/* Who an email is from and where its replies go (EVERY EMAIL IN MESSAGES,
   2026-11-17): Settings, Messages: Reply-to mailboxes, a company mailbox
   for each section (`mail_senders`, `mail_boxes`), never a colleague's own
   address. Read as the service role; a database that cannot answer sends
   from portal@sc.adspace.me replying to the general mailbox. */
async function rpcAsService(fn: string, args: Record<string, unknown>): Promise<unknown> {
  const url = Deno.env.get('SUPABASE_URL'), key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return null;
  const res = await fetch(url + '/rest/v1/rpc/' + fn, {
    method: 'POST', headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
    body: JSON.stringify(args)
  });
  return res.ok ? await res.json().catch(() => null) : null;
}
export async function sender(key: string): Promise<{ from: string; reply_to: string }> {
  try {
    const d = await rpcAsService('mail_sender', { p_key: key }) as Record<string, string> | null;
    if (d && d.from && d.reply_to) return { from: d.from, reply_to: d.reply_to };
  } catch (_e) { /* the fallback below */ }
  return { from: 'ADspace <portal@sc.adspace.me>', reply_to: 'advertise@adspacestudios.com' };
}
/* An email no other log keeps, filed for Messages' Email log once Resend
   has answered (`system_email_file`). Never a code or a sign-in link's
   words. A filing that fails never fails the send. */
export async function fileSent(row: Record<string, unknown>): Promise<void> {
  try { await rpcAsService('system_email_file', { p: row }); } catch (_e) { /* the email has gone either way */ }
}
/* The email the caller signed in with, from their token (already checked
   by the database's own reads before any email is sent). */
export function callerEmail(auth: string): string {
  try {
    const part = (auth.replace(/^Bearer\s+/i, '').split('.')[1] || '').replace(/-/g, '+').replace(/_/g, '/');
    return String(JSON.parse(atob(part + '==='.slice((part.length + 3) % 4))).email || '');
  } catch (_e) { return ''; }
}
