/*
 * portal-login — makes the login for a client contact who has been given
 * portal access, so that granting access is all it takes.
 *
 * Sign-ups are closed on the project, which is what stops anyone with the
 * page open from making themselves an account. That also means a contact
 * whose login was never created is refused at the door, and until now the
 * only thing that created it was the console, at the moment access was
 * granted: one failed call there and the client hit a wall nobody could see.
 *
 * So the page asks here first. This function creates the login only for an
 * address the team has already marked `portal_access` on a live contact, and
 * refuses every other address. Nothing is emailed: the client gets the
 * ordinary sign-in link they asked for, one step later. The invitation in the
 * console is a separate, deliberate thing.
 *
 * Deploy:  supabase functions deploy portal-login
 *
 * Secrets: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the
 * platform. Nothing else is needed.
 *
 * Turn OFF "Verify JWT" for this function in the dashboard: it is called by
 * somebody who is not signed in yet, which is the whole point.
 *
 * It answers `{ ok: true }` to every well-formed request, whether or not it
 * made a login (2026-09-26). Anybody can call it, so an answer that differed
 * for a known and an unknown address would tell a stranger which addresses
 * are clients. What happened is written to the function's own log instead.
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

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);

  let body: { email?: string } = {};
  try { body = await req.json(); } catch { /* handled below */ }
  const email = String(body.email ?? '').trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ ok: true }, 200, origin);

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  /* The one question that decides it, asked of the database rather than of
     anything the browser sent: has the team given this address access to a
     client, and is that contact still live? */
  const { data: contact } = await admin.from('client_contacts')
    .select('id, name').ilike('email', email)
    .eq('portal_access', true).is('archived_at', null).limit(1).maybeSingle();
  if (!contact) return json({ ok: true }, 200, origin);

  /* Confirmed on creation, because the team confirmed them: the address came
     off the client record, not off a form somebody filled in. An address that
     already has a login is not an error, it is the ordinary case from the
     second sign-in onwards. */
  const { error } = await admin.auth.admin.createUser({
    email, email_confirm: true, user_metadata: { name: contact.name ?? '' }
  });
  if (error && !/already|exists|registered/i.test(error.message)) {
    console.error('portal-login: createUser failed', error.message);
  }
  return json({ ok: true }, 200, origin);
});
