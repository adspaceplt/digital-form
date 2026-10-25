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
 * Verify JWT is on: the sign-in page calls it through supabase-js with the
 * project's public key, which passes the check, so a caller holding no key
 * is turned away before the function runs (2026-10-25).
 *
 * It answers `{ ok: true }` to every well-formed request, whether or not it
 * made a login (2026-09-26). Anybody can call it, so an answer that differed
 * for a known and an unknown address would tell a stranger which addresses
 * are clients. What happened is written to the function's own log instead.
 * Every answer also takes the same least time (FLOOR_MS): a known client's
 * address does a second call to the login service, and an answer that came
 * back later would say the same thing as one that differed (2026-10-25).
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json } from '../_shared/cors.ts';

/* An email compared as itself, never as a pattern: `_` and `%` in an
   address are letters here, not wildcards (audit P2, 2026-10-10). */
const exactEmail = (s: string) => String(s).replace(/[\\%_]/g, (c) => '\\' + c);

/* Longer than the slowest ordinary run (a read and a createUser), so a
   known address and an unknown one answer alike. */
const FLOOR_MS = 900;

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);
  const started = Date.now();
  /* A fault is logged, never answered: a 500 would differ from ok. */
  try { await work(req); } catch (e) { console.error('portal-login: failed', String(e)); }
  const wait = FLOOR_MS - (Date.now() - started);
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  return json({ ok: true }, 200, origin);
});

/* What a request does; its outcome is never the caller's to see. */
async function work(req: Request): Promise<void> {
  let body: { email?: string } = {};
  try { body = await req.json(); } catch { /* handled below */ }
  const email = String(body.email ?? '').trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return;

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  /* The one question that decides it, asked of the database rather than of
     anything the browser sent: has the team given this address access to a
     client, and is that contact still live? */
  const { data: contact, error: readError } = await admin.from('client_contacts')
    .select('id, name').ilike('email', exactEmail(email))
    .eq('portal_access', true).is('archived_at', null).limit(1).maybeSingle();
  /* A failed read is logged: the client is told to check their email
     either way, so the log is the only trace of an outage. */
  if (readError) console.error('portal-login: contact read failed', readError.message);
  if (!contact) return;

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
}
