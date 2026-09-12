/*
 * invite-member — creates the login for a person an admin has just added to
 * the team, and emails them the sign-in link.
 *
 * Creating a login needs the service role key, which must never reach the
 * browser. So the Team page adds the team_members row itself and then asks
 * this function to do the one thing it cannot: invite the email address in
 * Supabase Authentication. The function refuses anyone who is not an active
 * admin on the team list, checked here against the database and not against
 * anything the browser sent.
 *
 * Deploy:  supabase functions deploy invite-member
 *
 * Secrets: SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are
 * provided by the platform. Nothing else is needed.
 *
 * Turn OFF "Verify JWT" for this function in the dashboard, for the same
 * reason as sign-upload: the browser's preflight carries no Authorization
 * header, and this function verifies the caller itself.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const ALLOWED_ORIGINS = [
  'https://digital.adspace.me',
  'http://localhost:8899',
  'http://127.0.0.1:8899'
];
const SIGN_IN_PAGE = 'https://digital.adspace.me/admin/';
const CLIENT_PAGE  = 'https://digital.adspace.me/client/';

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

  // 1. Who is asking, from their own token.
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
  const asCaller = createClient(
    Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } }
  );
  const { data: { user }, error: authErr } = await asCaller.auth.getUser();
  if (authErr || !user?.email) return json({ error: 'not_signed_in' }, 401, origin);

  // 2. Are they an active admin? Asked of the database with the service role,
  //    so a row the caller cannot see or forge still decides.
  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );
  const { data: caller } = await admin.from('team_members')
    .select('role, is_admin, active, can_clients').ilike('email', user.email).maybeSingle();
  if (!caller || !caller.active) return json({ error: 'not_admin' }, 403, origin);

  // 3. What they want. kind "client" invites a client contact to /client/
  //    (anyone on the team who works the Clients section may do that); a team
  //    invite stays an admin's alone.
  let body: { email?: string; name?: string; kind?: string } = {};
  try { body = await req.json(); } catch { /* handled below */ }
  const email = String(body.email ?? '').trim().toLowerCase();
  const name = String(body.name ?? '').trim();
  const kind = body.kind === 'client' ? 'client' : 'team';
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: 'bad_email' }, 400, origin);

  const isAdmin = caller.is_admin === true || caller.role === 'admin';
  if (kind === 'team' && !isAdmin) return json({ error: 'not_admin' }, 403, origin);
  if (kind === 'client') {
    if (!isAdmin && !caller.can_clients) return json({ error: 'not_admin' }, 403, origin);
    // Only an address the console has marked for portal access is invited.
    const { data: contact } = await admin.from('client_contacts')
      .select('id').ilike('email', email).eq('portal_access', true).is('archived_at', null).limit(1).maybeSingle();
    if (!contact) return json({ error: 'not_portal_contact' }, 403, origin);
  }

  // 4. Invite. Supabase sends the email with the magic link; the person clicks
  //    it and lands on the sign-in page already signed in. An address that
  //    already has a login is not an error: the row exists, they can sign in.
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { name },
    redirectTo: kind === 'client' ? CLIENT_PAGE : SIGN_IN_PAGE
  });
  if (error) {
    const already = /already|exists|registered/i.test(error.message);
    if (already) return json({ ok: true, already: true }, 200, origin);
    return json({ error: 'invite_failed', detail: error.message }, 500, origin);
  }
  return json({ ok: true, already: false, id: data.user?.id ?? null }, 200, origin);
});
