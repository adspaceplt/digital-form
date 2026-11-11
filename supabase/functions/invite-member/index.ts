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
 * provided by the platform; RESEND_API_KEY sends the invitation to an
 * address that already has a login (MAIL_INVITE_FROM, else the sign-in
 * emails' sender).
 *
 * Turn OFF "Verify JWT" for this function in the dashboard, for the same
 * reason as sign-upload: the browser's preflight carries no Authorization
 * header, and this function verifies the caller itself.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json } from '../_shared/cors.ts';
import { esc, layout, resend, FONT } from '../_shared/mail.ts';

/* An email compared as itself, never as a pattern: `_` and `%` in an
   address are letters here, not wildcards (audit P2, 2026-10-10). */
const exactEmail = (s: string) => String(s).replace(/[\\%_]/g, (c) => '\\' + c);

const SIGN_IN_PAGE = 'https://digital.adspace.me/admin/';
const CLIENT_PAGE  = 'https://digital.adspace.me/client/';
/* The invitation an address with a login is sent by the portal itself,
   from the sender Supabase's own sign-in emails use. */
const FROM = () => Deno.env.get('MAIL_INVITE_FROM') || 'ADspace Digital Portal <noreply@sc.adspace.me>';

/* The invitation as Supabase's Invite user template words it
   (docs/SIGN-IN-EMAILS.md), for an address that already has a login, which
   Supabase will not invite (2026-11-11: two invitations the user sent went
   nowhere). Its button is a one-time sign-in link. */
function invitation(kind: string, greeting: string, link: string) {
  const client = kind === 'client';
  const button = '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr>' +
    '<td style="background:#0071e3;border-radius:10px;"><a href="' + esc(link) + '" style="display:inline-block;min-width:52px;' +
    'padding:12px 32px;text-align:center;font-family:' + FONT + ';font-size:16px;font-weight:500;color:#ffffff;text-decoration:none;">' +
    (client ? 'Open Client Portal' : 'Sign in') + '</a></td></tr></table>';
  const dear = 'Dear ' + greeting + ',';
  const body = client
    ? [dear, 'Thank you for choosing ADspace. Your Client Portal is now ready. It brings together your services and resources with ADspace all in one place.',
       'Please use the button below to open your Client Portal.', '{invoices}',
       'After this first visit, you may sign in at any time with a code sent to this email address. Should you have any questions, please contact your ADspace account manager.',
       'Yours sincerely,\nADspace']
    : [dear, 'ADspace has given you access to the ADspace Digital Portal. Please use the button below to sign in.', '{invoices}',
       'After this first visit, you may sign in at any time with a code sent to this email address.', 'Yours sincerely,\nADspace'];
  const subject = client ? 'Welcome to your ADspace Client Portal' : 'Your access to the ADspace Digital Portal';
  return {
    subject,
    html: layout({
      heading: subject, body: body.join('\n\n'), block: button,
      preheader: client ? 'Your invitation to the ADspace Client Portal.' : 'You have been given access to the ADspace Digital Portal.',
      foot: 'This link may be used once and expires shortly. If you were not expecting this invitation, please disregard this email.'
    /* The foot's second sentence on a line of its own, as the template
       sets it (the user, 2026-11-11). */
    }).replace('expires shortly. If you were', 'expires shortly.<br>If you were')
  };
}

const SALUTATIONS = ["Dato' Sri", "Datin Sri", 'Tan Sri', 'Puan Sri', 'Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof',
  "Dato'", 'Datin', 'Datuk', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik'];
function greetingOf(salutation: string | null | undefined, name: string): string {
  let n = String(name || '').trim();
  const sal = String(salutation || '').trim();
  if (sal) {
    /* A name that opens on a salutation gives way to the one set. */
    for (const s of SALUTATIONS) {
      const re = new RegExp('^' + s.replace(/[.'*+?^${}()|[\]\\]/g, '\\$&') + '\\.?\\s+', 'i');
      if (re.test(n)) { n = n.replace(re, ''); break; }
    }
    n = n ? sal + ' ' + n : '';
  }
  return n || 'Sir or Madam';
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
  // A removed colleague may share the address with one added again: the
  // active row answers (Team audit, item 10).
  const { data: caller } = await admin.from('team_members')
    .select('id, role, is_admin, active').ilike('email', exactEmail(user.email))
      .order('active', { ascending: false }).limit(1).maybeSingle();
  if (!caller || !caller.active) return json({ error: 'not_admin' }, 403, origin);

  // 3. What they want. kind "client" invites a client contact to /client/
  //    (anyone on the team who works the Clients section may do that); a team
  //    invite is Team: Send invitation.
  let body: { email?: string; name?: string; kind?: string; notify?: boolean } = {};
  try { body = await req.json(); } catch { /* handled below */ }
  const email = String(body.email ?? '').trim().toLowerCase();
  const name = String(body.name ?? '').trim();
  const kind = body.kind === 'client' ? 'client' : 'team';
  // The login is always created; only the email is a choice. A contact who is
  // given access without an invitation must still be able to sign in later,
  // and signInWithOtp cannot make an account of its own while sign-ups are
  // closed, so "do not send" creates the account silently rather than
  // creating nothing at all.
  const notify = body.notify !== false;
  /* How the invitation greets them: a client contact with their salutation
     and whole name, said once, as a client letter does (contact_greeting);
     a colleague by their whole name; nobody named, Sir or Madam. */
  let greeting = greetingOf('', name);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: 'bad_email' }, 400, origin);

  const isAdmin = caller.is_admin === true || caller.role === 'admin';
  // A team invite is Team: Send invitation (2026-10-07), an admin's by itself
  // and any other group's once set, asked as the caller.
  if (kind === 'team' && !isAdmin) {
    const { data: mayInvite } = await asCaller.rpc('ops_granted', { p_key: 'team.invite', p_level: 'work' });
    if (mayInvite !== true) return json({ error: 'not_admin' }, 403, origin);
  }
  if (kind === 'client') {
    // Contacts at Work, asked as the caller (the retired `can_clients` switch
    // answered for nobody on the levels), and the contact read as the caller
    // too, so a client outside their reach (Own clients only, a band below
    // its level) invites nobody.
    const { data: may } = await asCaller.rpc('allowed', { p_section: 'clients.contacts', p_level: 'work' });
    if (!isAdmin && may !== true) return json({ error: 'not_admin' }, 403, origin);
    // Only an address the console has marked for portal access is invited.
    const { data: contact } = await asCaller.from('client_contacts')
      .select('id, name, salutation').ilike('email', exactEmail(email)).eq('portal_access', true).is('archived_at', null).limit(1).maybeSingle();
    if (!contact) return json({ error: 'not_portal_contact' }, 403, origin);
    greeting = greetingOf(contact.salutation, contact.name || name);
  }

  // A team login is made only for an address an active colleague holds, so
  // the function never mints a login for somebody who is not on the team
  // (Team audit, item 8).
  if (kind === 'team') {
    const { data: member } = await admin.from('team_members')
      .select('id').ilike('email', exactEmail(email)).eq('active', true).limit(1).maybeSingle();
    if (!member) return json({ error: 'not_team_member' }, 403, origin);
  }
  // Twenty invitations a day each, counted by the database before a login is
  // made; a database that cannot count makes none.
  const { data: claim, error: claimErr } = await admin.rpc('team_invite_claim',
    { p_caller: caller.id, p_email: email, p_kind: kind });
  if (claimErr) return json({ error: 'invite_failed', detail: 'This needs a database update.' }, 500, origin);
  if (claim && claim.error) return json({ error: claim.error === 'too-many' ? 'too_many' : claim.error }, 429, origin);

  // 4. Make the login. Invited, Supabase sends the magic link and the person
  //    clicks it straight into the page, already signed in: there is no form
  //    to fill in and no password to choose. Unnotified, the account is made
  //    the same way but nothing leaves the building, and the first magic link
  //    they ask for signs them in. An address that already has a login is not
  //    an error either way: the account exists, they can sign in.
  const { data, error } = notify
    ? await admin.auth.admin.inviteUserByEmail(email, {
        /* The one Invite user template words a client's welcome and a
           colleague's access each its own way (docs/SIGN-IN-EMAILS.md). */
        data: { name, kind, greeting },
        redirectTo: kind === 'client' ? CLIENT_PAGE : SIGN_IN_PAGE
      })
    : await admin.auth.admin.createUser({
        email, email_confirm: true, user_metadata: { name }
      });
  if (error) {
    const already = /already|exists|registered/i.test(error.message);
    if (already && !notify) return json({ ok: true, already: true, sent: false }, 200, origin);
    if (already) {
      /* Asked to invite an address that already has a login: the
         invitation goes all the same, from the portal, its button a
         one-time sign-in link to the right page. */
      const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
        type: 'magiclink', email, options: { redirectTo: kind === 'client' ? CLIENT_PAGE : SIGN_IN_PAGE }
      });
      const href = link?.properties?.action_link;
      const apiKey = Deno.env.get('RESEND_API_KEY');
      if (linkErr || !href || !apiKey) {
        console.error('invite-member: no link or key', linkErr?.message ?? '', !!apiKey);
        return json({ error: 'invite_failed', detail: 'The invitation could not be sent.' }, 500, origin);
      }
      const mail = invitation(kind, greeting, href);
      const sent = await resend({ from: FROM(), to: [email], subject: mail.subject, html: mail.html },
        'invite:' + kind + ':' + email + ':' + Math.floor(Date.now() / 60000), apiKey);
      if (sent.status === 'failed') {
        console.error('invite-member: send failed', sent.error);
        return json({ error: 'invite_failed', detail: 'The invitation could not be sent.' }, 500, origin);
      }
      return json({ ok: true, already: true, sent: true }, 200, origin);
    }
    return json({ error: 'invite_failed', detail: error.message }, 500, origin);
  }
  return json({ ok: true, already: false, sent: notify, id: data.user?.id ?? null }, 200, origin);
});
