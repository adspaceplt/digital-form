/*
 * wa-hook — Meta's webhook for the WhatsApp Business Account (2026-10-10;
 * 2026-10-10-whatsapp-section.sql). Records what Meta says became of each
 * message the portal sent: sent, delivered, read, or failed with Meta's
 * error, against the message id `wa-send` kept (`wa_outbox.wa_id`).
 *
 *   GET   Meta's verification when the callback URL is saved in the Meta
 *         app (WhatsApp → Configuration): `hub.mode` is subscribe and
 *         `hub.verify_token` equals WHATSAPP_VERIFY_TOKEN, so the page
 *         answers `hub.challenge` as it came. Anything else is refused.
 *   POST  A change Meta sends. The body is read raw and its
 *         X-Hub-Signature-256 (HMAC SHA-256 of the raw body, keyed by
 *         META_APP_SECRET) checked before anything in it is believed; a
 *         missing or wrong signature is refused. Each `statuses` entry is
 *         recorded through `wa_status_record` with the service role, which
 *         alone may call it. Messages a person sends to the business
 *         number, and the business app's own echoes (coexistence), are not
 *         read in this phase. Nothing is ever sent to an AI service.
 *
 * Secrets: WHATSAPP_VERIFY_TOKEN (any long random string, typed into the
 *          Meta app beside the callback URL), META_APP_SECRET (the app's
 *          secret, already set for Import from Meta), plus the platform's
 *          SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. docs/WHATSAPP-SETUP.md.
 *
 * Verify JWT is off: Meta calls with no session. Meta tries a delivery
 * again for a day while it is not answered 200, so a recorded change, an
 * unknown message and a change that is not a status all answer 200; only a
 * request that is not Meta's is refused.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
function text(body: string, status: number) {
  return new Response(body, { status, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
}

/* The signature Meta sends, `sha256=` and the hex HMAC of the raw body. */
async function signed(raw: Uint8Array, header: string | null): Promise<boolean> {
  const key = secret('META_APP_SECRET');
  const given = String(header || '').trim().toLowerCase();
  if (!key || !given.startsWith('sha256=')) return false;
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', k, raw));
  const want = 'sha256=' + Array.from(mac).map((b) => b.toString(16).padStart(2, '0')).join('');
  /* Compared in constant time, so the answer's timing says nothing. */
  if (want.length !== given.length) return false;
  let diff = 0;
  for (let i = 0; i < want.length; i++) diff |= want.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}

type Status = {
  id?: string; status?: string; timestamp?: string;
  errors?: { code?: number | string; title?: string; message?: string }[];
  pricing?: { category?: string };
};

Deno.serve(async (req) => {
  const url = new URL(req.url);

  if (req.method === 'GET') {
    const mode = url.searchParams.get('hub.mode');
    const token = url.searchParams.get('hub.verify_token') || '';
    const challenge = url.searchParams.get('hub.challenge') || '';
    const want = secret('WHATSAPP_VERIFY_TOKEN');
    if (mode === 'subscribe' && want && token === want && challenge) return text(challenge, 200);
    return text('Forbidden', 403);
  }
  if (req.method !== 'POST') return text('Method not allowed', 405);

  const raw = new Uint8Array(await req.arrayBuffer());
  if (!(await signed(raw, req.headers.get('X-Hub-Signature-256')))) return text('Forbidden', 403);

  let body: Record<string, any> = {};
  try { body = JSON.parse(new TextDecoder().decode(raw)); } catch { return text('ok', 200); }
  if (body.object !== 'whatsapp_business_account') return text('ok', 200);

  const statuses: Status[] = [];
  for (const entry of (body.entry || []) as Record<string, any>[]) {
    for (const change of (entry.changes || []) as Record<string, any>[]) {
      /* Only the delivery events of what the portal sent; incoming messages
         (`messages`) and the business app's echoes are left for a later
         phase. */
      if (change.field !== 'messages') continue;
      for (const s of ((change.value || {}).statuses || []) as Status[]) statuses.push(s);
    }
  }
  if (!statuses.length) return text('ok', 200);

  const svc = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  let kept = 0;
  for (const s of statuses) {
    const err = (s.errors && s.errors[0]) || {};
    const at = Number(s.timestamp) ? new Date(Number(s.timestamp) * 1000).toISOString() : new Date().toISOString();
    const got = await svc.rpc('wa_status_record', {
      p_wa_id: String(s.id || ''), p_status: String(s.status || ''), p_at: at,
      p_code: err.code == null ? null : String(err.code), p_title: err.title || err.message || null,
      p_category: (s.pricing && s.pricing.category) || null
    });
    if (got.error) console.error('wa-hook: not recorded', s.status, got.error.message);
    else if (got.data) kept++;
  }
  return text('ok ' + kept, 200);
});
