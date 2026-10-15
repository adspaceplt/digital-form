/*
 * quote-request — the quotation website's one write that makes a record
 * (2026-10-14): a prospect's selection and details become a lead (or the
 * lead they already are) and a quotation kept as sent, priced by the
 * database from the live rate card. Nothing here prices or decides: the
 * database function `quote_website_create` checks every field, the limit of
 * five a contact a day and the selection, and answers the reference and
 * the quotation's key. Reading it back and requesting the Letter of Offer
 * are the page's own anon calls (`quote_website_read`,
 * `quote_website_request`), gated by that key.
 *
 * Cloudflare Turnstile: with the secret `TURNSTILE_SECRET` set (the same
 * secret key as the dashboard's CAPTCHA protection, docs/SIGN-IN-SECURITY.md)
 * a request without a token Cloudflare accepts is refused (`captcha`). With
 * the secret unset every request is refused (`captcha`): the database's
 * five-a-day count is per contact, and a contact is whatever is typed, so it
 * is never the only guard (audit S1, 2026-10-15).
 *
 * Deploy:  supabase functions deploy quote-request
 * Secrets: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (the platform's);
 *          TURNSTILE_SECRET (required, above).
 * Verify JWT: OFF. It is called by somebody who has no account.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const ALLOWED_ORIGINS = [
  'https://digital.adspace.me',
  'http://localhost:8899',
  'http://127.0.0.1:8899'
];

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
  return new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json', ...cors(origin) }
  });
}

async function human(token: string, ip: string | null): Promise<boolean> {
  const secret = Deno.env.get('TURNSTILE_SECRET');
  if (!secret) {
    console.error('quote-request: TURNSTILE_SECRET is not set; refusing');
    return false;
  }
  if (!token) return false;
  const form = new FormData();
  form.append('secret', secret);
  form.append('response', token);
  if (ip) form.append('remoteip', ip);
  try {
    const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body: form });
    const a = await r.json();
    return Boolean(a && a.success);
  } catch (e) {
    console.error('quote-request: siteverify failed', String(e));
    return false;
  }
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);

  let body: { sel?: unknown; contact?: unknown; idem?: string; token?: string } = {};
  try { body = await req.json(); } catch { return json({ error: 'bad-request' }, 400, origin); }
  if (!body || typeof body.sel !== 'object' || typeof body.contact !== 'object') {
    return json({ error: 'bad-request' }, 400, origin);
  }
  const ip = req.headers.get('CF-Connecting-IP') || (req.headers.get('X-Forwarded-For') || '').split(',')[0].trim() || null;
  if (!(await human(String(body.token || ''), ip))) return json({ error: 'captcha' }, 200, origin);

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data, error } = await admin.rpc('quote_website_create', {
    p_sel: body.sel, p_contact: body.contact, p_idem: String(body.idem || '')
  });
  if (error) {
    console.error('quote-request: quote_website_create failed', error.message);
    return json({ error: 'failed' }, 200, origin);
  }
  return json(data, 200, origin);
});
