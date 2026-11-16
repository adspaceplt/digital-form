/*
 * hiring-mail (2026-11-17, release H2 step B): the emails a candidate is
 * sent about an interview, each sent at a colleague's press.
 *
 *   { interviewId, kind: 'invite' }   the times offered, with the button to
 *                                     the candidate's own page to choose one;
 *   { interviewId, kind: 'confirm' }  the time approved, with its Google Meet
 *                                     or the office's address.
 *
 * Every question is asked as the caller (`hiring_mail_prepare`, the part or
 * the candidate's Owner); the address, the words' facts and the link are the
 * database's, never the page's. The outcome is filed by `hiring_mail_done`.
 * Sent through Resend in the portal's one layout (_shared/mail.ts), from
 * MAIL_CAREERS_FROM (unset: ADspace <noreply-careers@sc.adspace.me>),
 * replying to the colleague who sends it. No candidate data goes to AI.
 *
 * Secrets: RESEND_API_KEY, optionally MAIL_CAREERS_FROM. Verify JWT off: the
 * function asks the caller's own token of the database.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json } from '../_shared/cors.ts';
import { layout, resend, esc, FONT } from '../_shared/mail.ts';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
const FROM = () => secret('MAIL_CAREERS_FROM') || 'ADspace <noreply-careers@sc.adspace.me>';
const PAGE = 'https://digital.adspace.me/careers/?k=';
const OFFICE = '61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor';
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function button(label: string, href: string): string {
  return '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr>' +
    '<td style="background:#0071e3;border-radius:10px;"><a href="' + esc(href) + '" style="display:inline-block;padding:12px 22px;' +
    'font-family:' + FONT + ';font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;">' + esc(label) + '</a></td></tr></table>';
}

/* The words, as a formal letter (DESIGN.md §6): a fact a paragraph. */
export function words(m: Record<string, any>): { subject: string; heading: string; body: string; block: string } {
  const where = m.mode === 'online' ? 'by Google Meet' : 'at our office';
  if (m.kind === 'invite') {
    const times = (m.times || []).map((t: string) => '• ' + t + ' (Malaysia time)').join('\n');
    return {
      subject: 'Interview invitation: ' + m.position,
      heading: 'Interview invitation',
      body: 'Dear ' + m.name + ',\n\n' +
        'Thank you for your application for the position of ' + m.position + '. ADspace would like to invite you to an interview of ' +
        m.minutes + ' minutes ' + where + ' at one of the following times:\n\n' + times + '\n\n' +
        (m.note ? m.note + '\n\n' : '') +
        'Please choose a time on your application page. If none of these times suits you, please say so on the same page.\n\n{invoices}\n\n' +
        'Yours sincerely,\n' + m.sender + '\nADspace',
      block: button('Choose a time', PAGE + m.key)
    };
  }
  const place = m.mode === 'online' ? 'The interview will be held by Google Meet:\n' + m.link
    : 'The interview will be held at our office:\nADSPACE PLT\n' + OFFICE;
  return {
    subject: 'Interview confirmed: ' + m.position,
    heading: 'Interview confirmed',
    body: 'Dear ' + m.name + ',\n\n' +
      'Your interview for the position of ' + m.position + ' is confirmed for ' + m.when + ' (Malaysia time), for ' + m.minutes + ' minutes.\n\n' +
      place + '\n\n' + (m.note ? m.note + '\n\n' : '') +
      'The details are also on your application page.\n\n{invoices}\n\n' +
      'Yours sincerely,\n' + m.sender + '\nADspace',
    block: button('View your application', PAGE + m.key)
  };
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
  let b: { interviewId?: string; kind?: string };
  try { b = await req.json(); } catch { return json({ error: 'bad-request' }, 400, origin); }
  const id = String(b.interviewId || ''), kind = String(b.kind || '');
  if (!/^[0-9a-f-]{36}$/.test(id) || !['invite', 'confirm'].includes(kind)) return json({ error: 'bad-request' }, 400, origin);
  if (!secret('RESEND_API_KEY')) return json({ error: 'mail-not-set-up' }, 200, origin);

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });
  const prep = await db.rpc('hiring_mail_prepare', { p_interview: id, p_kind: kind });
  if (prep.error) return json({ error: 'denied' }, 200, origin);
  const m = prep.data as Record<string, any>;
  if (!m || m.error) return json({ error: (m && m.error) || 'denied' }, 200, origin);
  if (!EMAIL.test(String(m.to || ''))) return json({ error: 'bad-email' }, 200, origin);

  const w = words(m);
  const msg: Record<string, unknown> = {
    from: FROM(), to: [m.to], subject: w.subject,
    html: layout({ heading: w.heading, body: w.body, block: w.block, preheader: w.subject }),
    text: w.body.replace('{invoices}', PAGE + m.key)
  };
  if (EMAIL.test(String(m.reply_to || ''))) msg.reply_to = m.reply_to;
  const { status, error } = await resend(msg, 'hire-' + kind + '-' + id, secret('RESEND_API_KEY'));
  await db.rpc('hiring_mail_done', { p_interview: id, p_kind: kind, p_status: status, p_error: error || null });
  return json(status === 'sent' ? { ok: true } : { error: status === 'unknown' ? 'unknown' : 'not-sent' }, 200, origin);
});
