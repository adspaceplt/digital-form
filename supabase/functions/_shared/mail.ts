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
 *     confidentiality line), in a lighter grey.
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

function paras(body: string): string[] {
  return String(body || '').replace(/\r/g, '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
}
export const BLOCK = /^\{\s*invoices\s*\}$/i;
/* `{invoices}` set in a line of its own words stands as its own paragraph,
   so the table is drawn wherever it was typed (review 2026-10-29, 3). */
const TOKEN = /\{\s*invoices\s*\}/i;

export function layout(o: { heading: string; body: string; foot?: string; preheader?: string; block?: string; fine?: string[] }): string {
  const body = o.block ? String(o.body || '').replace(TOKEN, '\n\n{invoices}\n\n') : o.body;
  const ps = paras(body).map((p) => (o.block && BLOCK.test(p)) ? o.block :
    '<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#1b1a17;">' + p.split('\n').map(esc).join('<br>') + '</p>').join('');
  const fine = (o.fine && o.fine.filter(Boolean).length ? o.fine.filter(Boolean) : [CONFIDENTIAL])
    .map((t) => '<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#a19d97;">' + esc(t) + '</p>').join('');
  return '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">' +
    '<meta name="x-apple-disable-message-reformatting"><title>' + esc(o.heading) + '</title>' +
    '<style>@media (max-width:600px){.card{padding:24px !important;}.foot{padding:24px 24px 0 !important;}h1{font-size:21px !important;}.hide-sm{display:none !important;}}</style></head>' +
    '<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">' +
    '<div style="display:none;max-height:0;overflow:hidden;opacity:0;">' + esc(o.preheader || o.heading) + '</div>' +
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">' +
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">' +
    '<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:32px;font-family:' + FONT + ';color:#1b1a17;">' +
    '<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="91" height="26" style="display:block;width:91px;height:26px;border:0;outline:none;">' +
    '<h1 style="margin:24px 0 16px;font-size:24px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">' + esc(o.heading) + '</h1>' +
    ps +
    (o.foot ? '<p style="margin:8px 0 0;padding-top:16px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">' + esc(o.foot) + '</p>' : '') +
    '</td></tr>' +
    '<tr><td class="foot" style="padding:24px 32px 0;font-family:' + FONT + ';font-size:12px;line-height:1.6;color:#6b6760;">' +
    'ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>' +
    '(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>' +
    fine +
    '</td></tr></table></td></tr></table></body></html>';
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
