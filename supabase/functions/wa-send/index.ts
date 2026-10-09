/*
 * wa-send — sends the portal's WhatsApp messages through the WhatsApp
 * Business Platform (Cloud API), each with a template Meta approved
 * (2026-10-09; 2026-10-09-whatsapp.sql).
 *
 * Three ways in:
 *   { action: 'drain' }        pg_net after a queued message commits
 *                              (`wa_kick`): the team's reminders and a
 *                              creator's booking steps, claimed with the
 *                              service role (`wa_claim`) and closed
 *                              (`wa_done`); a refusal is tried again, three
 *                              times in all.
 *   { action: 'report', report_id, pdf, filename }
 *                              a colleague, from a published report: the PDF
 *                              (base64, drawn by the page from the kept file)
 *                              uploaded to WhatsApp and sent to the client's
 *                              main contact as the template's document header.
 *   { action: 'feedback', client_id }
 *                              a colleague, from the client's record: the
 *                              feedback template to the main contact.
 * By hand, the database is asked as the caller (`wa_report_prepare`,
 * `wa_feedback_prepare`) and the outcome filed (`wa_record`).
 *
 * Secrets: WHATSAPP_PHONE_ID (the Phone number ID), WHATSAPP_TOKEN (a system
 *          user's token with whatsapp_business_messaging; unset, the Meta
 *          system user's META_SYSTEM_TOKEN), META_APP_SECRET (optional: each
 *          call then carries appsecret_proof), META_GRAPH_VERSION (unset v26.0),
 *          plus the platform's SUPABASE_URL, SUPABASE_ANON_KEY and
 *          SUPABASE_SERVICE_ROLE_KEY. docs/WHATSAPP-SETUP.md.
 *
 * Verify JWT is off: pg_net calls with no session. A refusal the person can
 * act on answers 200 with { error }.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const ALLOWED_ORIGINS = ['https://digital.adspace.me', 'http://localhost:8899'];
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
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...cors(origin) } });
}
function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }

const GRAPH = () => 'https://graph.facebook.com/' + (secret('META_GRAPH_VERSION') || 'v26.0');
const TOKEN = () => secret('WHATSAPP_TOKEN') || secret('META_SYSTEM_TOKEN');
const PHONE = () => secret('WHATSAPP_PHONE_ID');

/* With "Require app secret" on in the Meta app, every Graph call carries
   appsecret_proof (HMAC-SHA256 of the token keyed by META_APP_SECRET), as
   meta-import's do. Unset, nothing is added. */
async function proof(): Promise<string> {
  const s = secret('META_APP_SECRET');
  if (!s) return '';
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(s), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(TOKEN()));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
async function graphUrl(path: string): Promise<string> {
  const url = new URL(GRAPH() + '/' + PHONE() + path);
  const p = await proof();
  if (p) url.searchParams.set('appsecret_proof', p);
  return url.toString();
}

type Sent = { ok: boolean; id?: string; error?: string };

/* The template, its body variables in order, and a document header where
   one is given. Meta's own refusal is kept for the log, never shown. */
async function sendTemplate(to: string, name: string, lang: string, params: string[], doc?: { id: string; filename: string }): Promise<Sent> {
  const components: unknown[] = [];
  if (doc) components.push({ type: 'header', parameters: [{ type: 'document', document: { id: doc.id, filename: doc.filename } }] });
  if (params.length) {
    components.push({ type: 'body', parameters: params.map((p) => ({ type: 'text', text: String(p || '-').replace(/\s*\n\s*/g, ' ').slice(0, 1000) })) });
  }
  const res = await fetch(await graphUrl('/messages'), {
    method: 'POST',
    headers: { 'Authorization': 'Bearer ' + TOKEN(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ messaging_product: 'whatsapp', to, type: 'template',
      template: { name, language: { code: lang }, components } })
  }).catch((e) => ({ ok: false, status: 0, json: () => Promise.resolve({ error: { message: String(e) } }) } as unknown as Response));
  const body = await res.json().catch(() => ({})) as Record<string, any>;
  if (!res.ok || body.error) {
    const e = body.error || {};
    return { ok: false, error: [res.status, e.code, e.error_subcode, e.message].filter((x) => x != null && x !== '').join(' ').slice(0, 480) };
  }
  return { ok: true, id: (body.messages && body.messages[0] && body.messages[0].id) || '' };
}

async function uploadPdf(b64: string, filename: string): Promise<{ id?: string; error?: string }> {
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const form = new FormData();
  form.append('messaging_product', 'whatsapp');
  form.append('type', 'application/pdf');
  form.append('file', new Blob([bytes], { type: 'application/pdf' }), filename);
  const res = await fetch(await graphUrl('/media'), {
    method: 'POST', headers: { 'Authorization': 'Bearer ' + TOKEN() }, body: form
  }).catch(() => null);
  if (!res) return { error: 'upload' };
  const body = await res.json().catch(() => ({})) as Record<string, any>;
  if (!res.ok || !body.id) return { error: [res.status, body.error && body.error.message].filter(Boolean).join(' ').slice(0, 480) };
  return { id: String(body.id) };
}

/* A Graph refusal in the team's words. */
function named(err?: string): string {
  const e = String(err || '');
  if (/\b(190|401)\b|OAuth|access token/i.test(e)) return 'wa-token';
  if (/\b132001\b|template name does not exist/i.test(e)) return 'wa-template';
  if (/\b132000\b|number of parameters/i.test(e)) return 'wa-params';
  if (/\b131026\b|\b131030\b|not a valid WhatsApp|recipient/i.test(e)) return 'wa-recipient';
  if (/\b(4|80007|130429|131048|131056)\b|rate limit/i.test(e)) return 'wa-busy';
  return 'wa-failed';
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  const body = await req.json().catch(() => ({})) as Record<string, any>;
  const action = String(body.action || '');
  const missing = [!PHONE() && 'WHATSAPP_PHONE_ID', !TOKEN() && 'WHATSAPP_TOKEN'].filter(Boolean);

  if (action === 'drain') {
    if (missing.length) return json({ ok: false, missing }, 200, origin);
    const svc = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let sent = 0, failed = 0;
    for (let round = 0; round < 5; round++) {
      const got = await svc.rpc('wa_claim', { p_limit: 20 });
      const rows = (got.data || []) as Record<string, any>[];
      if (got.error || !rows.length) break;
      for (const r of rows) {
        const out = await sendTemplate(r.to_number, r.template, r.lang, (r.params || []) as string[]);
        await svc.rpc('wa_done', { p_id: r.id, p_ok: out.ok, p_wa_id: out.id || null, p_error: out.error || null });
        if (out.ok) sent++; else { failed++; console.error('wa-send: refused', r.purpose, out.error); }
      }
    }
    return json({ ok: true, sent, failed }, 200, origin);
  }

  if (action !== 'report' && action !== 'feedback') return json({ error: 'bad-request' }, 400, origin);
  if (missing.length) return json({ error: 'wa-not-set-up', missing }, 200, origin);
  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });

  const id = String(action === 'report' ? body.report_id || '' : body.client_id || '');
  if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: 'bad-request' }, 400, origin);
  const prep = await db.rpc(action === 'report' ? 'wa_report_prepare' : 'wa_feedback_prepare',
    action === 'report' ? { p_id: id } : { p_client: id });
  if (prep.error) return json({ error: 'needs-update' }, 200, origin);
  const p = (prep.data || {}) as Record<string, any>;
  if (p.error) return json({ error: p.error }, 200, origin);

  /* The body's variables, as many as the template takes: the contact's first
     name, then the client (a report's brand), then for a report its title. */
  const values = [p.first || p.name || 'there', p.client || '', String(body.title || '').slice(0, 200)].slice(0, Number(p.params) || 0);
  let doc: { id: string; filename: string } | undefined;
  if (action === 'report') {
    const b64 = String(body.pdf || '');
    const filename = String(body.filename || 'Report.pdf').replace(/[\\/:*?"<>|]+/g, ' ').slice(0, 200);
    if (!b64 || b64.length > 20 * 1024 * 1024) return json({ error: 'bad-file' }, 200, origin);
    const up = await uploadPdf(b64, filename);
    if (!up.id) {
      console.error('wa-send: upload refused', up.error);
      await db.rpc('wa_record', { p_purpose: 'report', p_ref: id, p_client: p.client_id, p_number: p.number, p_name: p.name,
        p_template: p.template, p_params: values, p_ok: false, p_wa_id: null, p_error: 'upload: ' + (up.error || '') });
      return json({ error: named(up.error) }, 200, origin);
    }
    doc = { id: up.id, filename };
  }
  const out = await sendTemplate(p.number, p.template, p.lang, values, doc);
  if (!out.ok) console.error('wa-send: refused', action, out.error);
  await db.rpc('wa_record', { p_purpose: action, p_ref: action === 'report' ? id : null, p_client: p.client_id, p_number: p.number,
    p_name: p.name, p_template: p.template, p_params: values, p_ok: out.ok, p_wa_id: out.id || null, p_error: out.error || null });
  return out.ok ? json({ ok: true, to: p.name || null }, 200, origin) : json({ error: named(out.error) }, 200, origin);
});
