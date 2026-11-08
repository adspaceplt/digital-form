/*
 * creator-mail — sends the creator emails the database queued (2026-11-08,
 * 2026-11-08-creator-payment-details.sql): Details received and Details
 * approved to the creator, Details to review to the finance address.
 *
 *   POST { action: 'drain' }  from the database alone (`creator_mail_kick`,
 *                          pg_cron `creator-mail-drain`), carrying the wake
 *                          secret as `x-adspace-wake`; the function asks
 *                          `wake_secret_ok` and answers anyone else 401.
 *                          Each queued email is claimed once
 *                          (`creator_mail_claim`), sent through Resend in
 *                          the portal's one layout and closed
 *                          (`creator_mail_done`): sent, failed, or not
 *                          confirmed where Resend's answer never came,
 *                          never sent again by itself. No send starts after
 *                          90 seconds; what is left waits for the next wake.
 *
 * The words are the database's, filled when the email was queued; the page
 * sends none. Resend's word on each reaches `creator_emails` through
 * supplier-mail's webhook (`supplier_email_status`).
 *
 * From MAIL_CREATOR_FROM (unset: ADspace <noreply-creator@sc.adspace.me>),
 * replies to MAIL_CREATOR_REPLY_TO (unset: ap@adspacestudios.com).
 * Secrets: RESEND_API_KEY, plus the platform's SUPABASE_URL and
 * SUPABASE_SERVICE_ROLE_KEY. Verify JWT is off: pg_net calls with no session.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { layout, resend } from '../_shared/mail.ts';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
const FROM = () => secret('MAIL_CREATOR_FROM') || 'ADspace <noreply-creator@sc.adspace.me>';
const REPLY_TO = () => secret('MAIL_CREATOR_REPLY_TO') || 'ap@adspacestudios.com';
const BUDGET = 90000;
const ROUNDS = 20;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

type Row = { id: string; purpose: string; to_email: string; subject: string; body: string };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } });
  const given = req.headers.get('x-adspace-wake') || '';
  const woken = given.length >= 32 ? await db.rpc('wake_secret_ok', { p_given: given }) : null;
  if (!woken || woken.error || woken.data !== true) return json({ error: 'denied' }, 401);

  const apiKey = secret('RESEND_API_KEY');
  if (!apiKey) return json({ error: 'mail-not-set-up' });

  let sent = 0, failed = 0;
  const began = Date.now();
  for (let round = 0; round < ROUNDS; round++) {
    if (Date.now() - began > BUDGET) break;
    const { data: batch, error } = await db.rpc('creator_mail_claim', { p_n: 1 });
    if (error) return json({ error: 'claim', reason: error.message, sent, failed });
    const rows = (Array.isArray(batch) ? batch : []) as Row[];
    if (!rows.length) break;
    for (const r of rows) {
      const out = await resend({
        from: FROM(), to: [r.to_email], reply_to: REPLY_TO(), subject: r.subject,
        html: layout({ heading: r.subject, body: r.body }),
        text: r.body
      }, 'creator-' + r.id, apiKey);
      await db.rpc('creator_mail_done', { p_id: r.id, p_status: out.status, p_provider: out.provider, p_error: out.error });
      if (out.status === 'sent') sent++; else failed++;
    }
  }
  return json({ ok: true, sent, failed });
});
