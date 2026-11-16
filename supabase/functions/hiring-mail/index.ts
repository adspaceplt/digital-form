/*
 * hiring-mail (2026-11-17, release H2 step B): the emails a candidate is
 * sent about an interview, each sent at a colleague's press.
 *
 *   { interviewId, kind: 'invite' }   the times offered, with the button to
 *                                     the candidate's own page to choose one;
 *   { interviewId, kind: 'confirm' }  the time approved, with its Google Meet
 *                                     or the office's address;
 *   { candidateId, kind: 'outcome' }  the decision (step C): Keep in talent
 *                                     pool asks the candidate to agree on
 *                                     their page; Not proceed thanks them.
 *                                     Never the team's note on the decision.
 *   { docId, kind: 'doc' }            an Employment Offer or Contract waits
 *                                     on the candidate's page (step D):
 *                                     the reference and the day to answer,
 *                                     never the salary or the terms;
 *   { key, docId, kind: 'code', device }  the candidate's own press on their
 *                                     page, with no sign-in: a six-digit
 *                                     code to read that document, made by
 *                                     `hiring_doc_code` as the service role
 *                                     and sent to the candidate's own email
 *                                     alone; answered alike whatever befalls.
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
  const title = m.doc === 'contract' ? 'Employment Contract' : 'Employment Offer';
  if (m.kind === 'code') {
    return {
      subject: 'Your verification code for ' + m.ref,
      heading: 'Your verification code',
      body: 'Dear ' + m.name + ',\n\n' +
        'Please enter the code below on your application page to open your ' + title + ' ' + m.ref + '. The code expires in 15 minutes.\n\n{invoices}\n\n' +
        'If you did not request this code, please ignore this email.\n\nADspace',
      block: '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr>' +
        '<td style="background:#f5f5f5;border-radius:10px;padding:14px 22px;font-family:' + FONT + ';font-size:26px;font-weight:600;' +
        'letter-spacing:6px;color:#1a1a1a;text-align:center;" x-apple-data-detectors="false">' + esc(m.code) + '</td></tr></table>'
    };
  }
  if (m.kind === 'doc') {
    return {
      subject: title + ': ' + m.ref,
      heading: 'Your ' + title,
      body: 'Dear ' + m.name + ',\n\n' +
        (m.returned ? 'Your ' + title + ' ' + m.ref + ' has been returned to you ' + (m.doc === 'contract' ? 'for your signature again.' : 'for your reply again.')
          : 'ADspace is pleased to send you an ' + title + ' for the position of ' + m.position + ', reference ' + m.ref + '.') + '\n\n' +
        'Please read it on your application page and ' + (m.doc === 'contract' ? 'sign it' : 'reply') + ' by ' + m.reply_by + '. ' +
        'For your privacy, the page will ask for a code sent to this email address before it shows the document.\n\n{invoices}\n\n' + 'Yours sincerely,\n' + m.sender + '\nADspace',
      block: button(m.doc === 'contract' ? 'Read and sign' : 'Read your offer', PAGE + m.key)
    };
  }
  const where = m.mode === 'online' ? 'by Google Meet' : 'at our office';
  const close = 'Yours sincerely,\n' + m.sender + '\nADspace';
  if (m.kind === 'pool') {
    return {
      subject: 'Your application: ' + m.position,
      heading: 'Your application',
      body: 'Dear ' + m.name + ',\n\n' +
        'Thank you for your interest in the position of ' + m.position + ' and for the time you have given us. ' +
        'There is no suitable opening for you at this time. ADspace would like to keep your application for ' + m.months +
        ' months, so that we may contact you about future positions.\n\n' +
        'Please indicate on your application page whether you agree. If you do not agree, your details will be deleted.\n\n{invoices}\n\n' + close,
      block: button('Respond on your page', PAGE + m.key)
    };
  }
  if (m.kind === 'not') {
    return {
      subject: 'Your application: ' + m.position,
      heading: 'Your application',
      body: 'Dear ' + m.name + ',\n\n' +
        'Thank you for your interest in the position of ' + m.position + ' and for the time you have given us. ' +
        'After careful consideration, ADspace will not be proceeding with your application.\n\n' +
        'We wish you every success in your search.\n\n' + close,
      block: ''
    };
  }
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

/* The caller's address as Cloudflare saw it: never the first
   X-Forwarded-For entry, which the caller writes. */
function ipOf(req: Request): string {
  const cf = (req.headers.get('cf-connecting-ip') || '').trim();
  if (cf) return cf.slice(0, 64);
  const xff = (req.headers.get('x-forwarded-for') || '').split(',').map((x) => x.trim()).filter(Boolean);
  return (xff[xff.length - 1] || '').slice(0, 64);
}

/* The candidate's code: no sign-in, the link's key and the document; the
   address, the name and the reference are the database's. */
async function sendCode(req: Request, b: Record<string, any>, origin: string | null): Promise<Response> {
  const key = String(b.key || ''), doc = String(b.docId || '');
  if (!/^[a-z0-9]{8}$/.test(key) || !/^[0-9a-f-]{36}$/.test(doc)) return json({ error: 'bad-request' }, 400, origin);
  if (!secret('RESEND_API_KEY')) return json({ error: 'mail-not-set-up' }, 200, origin);
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const r = await db.rpc('hiring_doc_code', { p_key: key, p_doc: doc, p_device: String(b.device || '').slice(0, 200), p_ip: ipOf(req) || null });
  const m = r.data as Record<string, any>;
  if (r.error || !m) return json({ error: 'not-sent' }, 200, origin);
  if (m.error) return json({ error: m.error === 'too-many' ? 'too-many' : 'not_found' }, 200, origin);
  if (!EMAIL.test(String(m.to || m.email || ''))) return json({ error: 'not-sent' }, 200, origin);
  const w = words(Object.assign({ kind: 'code' }, m));
  const { status } = await resend({
    from: FROM(), to: [m.email], subject: w.subject,
    html: layout({ heading: w.heading, body: w.body, block: w.block, preheader: 'Your verification code' }),
    text: w.body.replace('{invoices}', m.code)
  }, 'hire-code-' + doc + '-' + crypto.randomUUID(), secret('RESEND_API_KEY'));
  return json(status === 'failed' ? { error: 'not-sent' } : { ok: true }, 200, origin);
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  let b: Record<string, any>;
  try { b = await req.json(); } catch { return json({ error: 'bad-request' }, 400, origin); }
  if (b && b.kind === 'code') return sendCode(req, b, origin);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
  const kind = String(b.kind || ''), outcome = kind === 'outcome', isDoc = kind === 'doc';
  const id = String((outcome ? b.candidateId : isDoc ? b.docId : b.interviewId) || '');
  if (!/^[0-9a-f-]{36}$/.test(id) || !['invite', 'confirm', 'outcome', 'doc'].includes(kind)) return json({ error: 'bad-request' }, 400, origin);
  if (!secret('RESEND_API_KEY')) return json({ error: 'mail-not-set-up' }, 200, origin);

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });
  const prep = outcome ? await db.rpc('hiring_outcome_mail_prepare', { p_id: id })
    : isDoc ? await db.rpc('hiring_doc_mail_prepare', { p_doc: id })
    : await db.rpc('hiring_mail_prepare', { p_interview: id, p_kind: kind });
  if (prep.error) return json({ error: 'denied' }, 200, origin);
  const m = prep.data as Record<string, any>;
  if (!m || m.error) return json({ error: (m && m.error) || 'denied' }, 200, origin);
  if (!EMAIL.test(String(m.to || ''))) return json({ error: 'bad-email' }, 200, origin);

  const w = words(m);
  const msg: Record<string, unknown> = {
    from: FROM(), to: [m.to], subject: w.subject,
    html: layout({ heading: w.heading, body: w.body, block: w.block || undefined, preheader: w.subject }),
    text: w.body.replace('{invoices}', PAGE + m.key)
  };
  if (EMAIL.test(String(m.reply_to || ''))) msg.reply_to = m.reply_to;
  /* A decision's key carries the decision's kind, so a reopened candidate
     decided again is emailed again. */
  /* A document's key carries its sending, so a document sent back is
     emailed again. */
  const { status, error } = await resend(msg, 'hire-' + (outcome ? m.kind : kind) + '-' + id + (isDoc ? '-' + String(m.sent_key || '') : ''), secret('RESEND_API_KEY'));
  if (isDoc) await db.rpc('hiring_doc_mail_done', { p_doc: id, p_status: status, p_error: error || null });
  else if (outcome) await db.rpc('hiring_outcome_mail_done', { p_id: id, p_status: status, p_error: error || null });
  else await db.rpc('hiring_mail_done', { p_interview: id, p_kind: kind, p_status: status, p_error: error || null });
  return json(status === 'sent' ? { ok: true } : { error: status === 'unknown' ? 'unknown' : 'not-sent' }, 200, origin);
});
