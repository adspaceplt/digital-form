/*
 * wa-send — sends the portal's WhatsApp messages through the WhatsApp
 * Business Platform (Cloud API), each with a template Meta approved
 * (2026-10-09; 2026-10-09-whatsapp.sql, 2026-10-10-whatsapp-section.sql).
 *
 * Ways in:
 *   { action: 'drain' }        pg_net after a queued message commits
 *                              (`wa_kick`): the team's reminders and a
 *                              creator's booking confirmed (with the code
 *                              for the template's link button), claimed with the
 *                              service role (`wa_claim`) and closed
 *                              (`wa_done`); a refusal is tried again, three
 *                              times in all.
 *   { action: 'templates' }    a colleague at WhatsApp Work: the templates
 *                              Meta approved for the WhatsApp Business
 *                              Account (WHATSAPP_WABA_ID), each read into what
 *                              a send asks for (its header, its body's
 *                              variables, a link button's variable).
 *   { action: 'compose', to_kind, to_id, purpose, ref, template: { name,
 *     language }, values, header_value, button_value, pdf, filename }
 *                              a colleague, from the composer: the recipient
 *                              and the record asked of the database as the
 *                              caller (`wa_compose_prepare`), the template
 *                              read again from Meta (approved, as it stands
 *                              now), a record's PDF (a report, a quotation,
 *                              a Letter of Offer) uploaded as its Document
 *                              header, sent, and filed (`wa_sent`); the same
 *                              message sent recently (`wa_sent_recently`) answers
 *                              `recent` unless `again` is true.
 *   { action: 'report' | 'feedback', … }
 *                              the sends by hand from before the composer,
 *                              kept for a page loaded before it
 *                              (`wa_report_prepare`, `wa_feedback_prepare`,
 *                              `wa_record`).
 *
 * Secrets: WHATSAPP_PHONE_ID (the Phone number ID), WHATSAPP_WABA_ID (the
 *          WhatsApp Business Account ID, whose templates are read),
 *          WHATSAPP_TOKEN (a system user's token with
 *          whatsapp_business_messaging and whatsapp_business_management;
 *          unset, the Meta system user's META_SYSTEM_TOKEN), META_APP_SECRET
 *          (optional: each call then carries appsecret_proof),
 *          META_GRAPH_VERSION (unset v26.0), plus the platform's SUPABASE_URL,
 *          SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY.
 *          docs/WHATSAPP-SETUP.md.
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
const WABA = () => secret('WHATSAPP_WABA_ID');

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
/* A Graph address on the phone number, or on another node (the account). */
async function graphUrl(path: string, node?: string): Promise<string> {
  const url = new URL(GRAPH() + '/' + (node || PHONE()) + path);
  const p = await proof();
  if (p) url.searchParams.set('appsecret_proof', p);
  return url.toString();
}

type Sent = { ok: boolean; id?: string; error?: string };
type More = { names?: string[]; header?: { text: string; name?: string }; buttonIndex?: number; buttonName?: string };

function clean(p: string, max: number): string {
  return String(p || '-').replace(/\s*\n\s*/g, ' ').slice(0, max);
}

/* The template, its body variables in order, and a document header where
   one is given; a text header's variable and a link button's variable where
   the template has them (named where Meta holds it with named variables).
   Meta's own refusal is kept for the log, never shown. */
async function sendTemplate(to: string, name: string, lang: string, params: string[], doc?: { id: string; filename: string },
                            button?: string, more?: More): Promise<Sent> {
  const m = more || {};
  const components: unknown[] = [];
  if (doc) components.push({ type: 'header', parameters: [{ type: 'document', document: { id: doc.id, filename: doc.filename } }] });
  else if (m.header) {
    components.push({ type: 'header', parameters: [Object.assign({ type: 'text', text: clean(m.header.text, 60) },
      m.header.name ? { parameter_name: m.header.name } : {})] });
  }
  if (params.length) {
    components.push({ type: 'body', parameters: params.map((p, i) => Object.assign({ type: 'text', text: clean(p, 1000) },
      m.names && m.names[i] ? { parameter_name: m.names[i] } : {})) });
  }
  /* A link button's variable part (a creator's code for their own page). */
  if (button) {
    components.push({ type: 'button', sub_type: 'url', index: String(m.buttonIndex || 0),
      parameters: [Object.assign({ type: 'text', text: String(button).slice(0, 200) }, m.buttonName ? { parameter_name: m.buttonName } : {})] });
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

/* A document's bytes (audit S3, 2026-10-15): a report's are its kept PDF,
   read as the caller through sign-download for the version on the client
   portal, never what the page sends; a quotation's or a letter's are the
   page's drawing, and must be a PDF. Malformed base64 reads as nothing. */
const isPdf = (b: Uint8Array) => b.length > 4 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46;
function pdfFrom(b64: string): Uint8Array | null {
  if (!b64 || b64.length > 20 * 1024 * 1024) return null;
  try {
    const b = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    return isPdf(b) ? b : null;
  } catch { return null; }
}
/* A quotation's or a letter's PDF names its own reference (2026-10-15): the
   page draws it with the reference in the file's title, so a file that does
   not carry the record's reference is not that record's. pdf-lib keeps the
   title in a compressed object stream as UTF-16 hex, so each stream is
   inflated and searched as text and as that hex. */
const hexOf = (s: string) => Array.from(s).map((c) => c.charCodeAt(0).toString(16).padStart(4, '0')).join('').toUpperCase();
async function inflate(b: Uint8Array): Promise<string> {
  try {
    const out = new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream('deflate')));
    return new TextDecoder('latin1').decode(new Uint8Array(await out.arrayBuffer()));
  } catch { return ''; }
}
async function namesRef(b: Uint8Array, ref: string): Promise<boolean> {
  if (!ref) return false;
  const raw = new TextDecoder('latin1').decode(b);
  const hex = hexOf(ref), lit = '(' + ref;
  const hit = (t: string) => t.indexOf(lit) >= 0 || t.toUpperCase().replace(/\s+/g, '').indexOf(hex) >= 0;
  if (hit(raw)) return true;
  const re = /stream\r?\n/g;
  let m: RegExpExecArray | null, seen = 0;
  while ((m = re.exec(raw)) && seen < 400) {
    seen++;
    const start = m.index + m[0].length, end = raw.indexOf('endstream', start);
    if (end < 0) break;
    let stop = end;
    while (stop > start && (b[stop - 1] === 0x0a || b[stop - 1] === 0x0d)) stop--;
    if (stop - start > 4 * 1024 * 1024) continue;
    if (hit(await inflate(b.subarray(start, stop)))) return true;
  }
  return false;
}
async function refOf(db: any, purpose: string, id: string): Promise<string> {
  const r = purpose === 'quotation'
    ? await db.from('quotations').select('ref').eq('id', id).maybeSingle()
    : await db.from('client_documents').select('number').eq('id', id).maybeSingle();
  return r.error || !r.data ? '' : String(purpose === 'quotation' ? r.data.ref : r.data.number || '');
}
async function keptReport(db: any, auth: string, reportId: string): Promise<Uint8Array | null> {
  const v = await db.from('sm_report_versions').select('id, version_no, published_at, withdrawn_at')
    .eq('report_id', reportId).order('version_no', { ascending: false });
  const live = ((v.data || []) as Record<string, any>[]).filter((x) => x.published_at && !x.withdrawn_at)[0];
  if (v.error || !live) return null;
  const res = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/sign-download', {
    method: 'POST',
    headers: { 'Authorization': auth, 'apikey': Deno.env.get('SUPABASE_ANON_KEY')!, 'Content-Type': 'application/json' },
    body: JSON.stringify({ reportVersion: live.id })
  }).catch(() => null);
  if (!res || !res.ok) return null;
  const b = new Uint8Array(await res.arrayBuffer().catch(() => new ArrayBuffer(0)));
  return isPdf(b) ? b : null;
}

async function uploadPdf(bytes: Uint8Array, filename: string): Promise<{ id?: string; error?: string }> {
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
  if (/\b(132001|132015|132016)\b|template name does not exist/i.test(e)) return 'wa-template';
  if (/\b132000\b|number of parameters/i.test(e)) return 'wa-params';
  if (/\b131026\b|\b131030\b|not a valid WhatsApp|recipient/i.test(e)) return 'wa-recipient';
  if (/\b(4|80007|130429|131048|131056)\b|rate limit/i.test(e)) return 'wa-busy';
  return 'wa-failed';
}

/* ---- Templates ---------------------------------------------------------------
   A template as Meta holds it, read into what a send asks for: its header (a
   Document, or text with one variable), its body's variables in order
   (`{{1}}`… or named), and a link button whose address ends in a variable.
   A template with an image, video or location header, or a code to copy, is
   marked unsupported: the portal has nothing to put there. */
type Shape = {
  name: string; language: string; category: string; status: string; format: string;
  header: string; header_text: string; header_var: string;
  body: string; body_vars: string[]; footer: string;
  buttons: { type: string; text: string; url?: string }[];
  button_var: { index: number; url: string; name: string } | null;
  supported: boolean;
};
const VAR = /\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g;
function varsOf(text: string): string[] {
  const seen: string[] = [];
  for (const m of String(text || '').matchAll(VAR)) if (seen.indexOf(m[1]) < 0) seen.push(m[1]);
  /* Positional variables go in their number's order, whatever the text's. */
  if (seen.length && seen.every((v) => /^\d+$/.test(v))) seen.sort((a, b) => Number(a) - Number(b));
  return seen;
}
function shapeOf(t: Record<string, any>): Shape {
  const comps = (t.components || []) as Record<string, any>[];
  const kind = (c: Record<string, any>) => String(c.type || '').toUpperCase();
  const head = comps.filter((c) => kind(c) === 'HEADER')[0];
  const body = comps.filter((c) => kind(c) === 'BODY')[0] || {};
  const foot = comps.filter((c) => kind(c) === 'FOOTER')[0] || {};
  const btns = ((comps.filter((c) => kind(c) === 'BUTTONS')[0] || {}).buttons || []) as Record<string, any>[];
  const header = head ? String(head.format || 'TEXT').toUpperCase() : '';
  const headerVars = header === 'TEXT' ? varsOf(head.text) : [];
  let buttonVar: Shape['button_var'] = null;
  let supported = header === '' || header === 'DOCUMENT' || (header === 'TEXT' && headerVars.length <= 1);
  btns.forEach((b, i) => {
    const type = String(b.type || '').toUpperCase();
    if (['COPY_CODE', 'OTP', 'FLOW', 'CATALOG', 'MPM'].indexOf(type) > -1) supported = false;
    if (type === 'URL') {
      const v = varsOf(b.url);
      if (v.length > 1 || (v.length && buttonVar)) supported = false;
      else if (v.length) buttonVar = { index: i, url: String(b.url || ''), name: v[0] };
    }
  });
  return {
    name: String(t.name || ''), language: String(t.language || ''), category: String(t.category || '').toLowerCase(),
    status: String(t.status || '').toUpperCase(), format: String(t.parameter_format || 'POSITIONAL').toUpperCase(),
    header, header_text: header === 'TEXT' ? String(head.text || '') : '', header_var: headerVars[0] || '',
    body: String(body.text || ''), body_vars: varsOf(body.text), footer: String(foot.text || ''),
    buttons: btns.map((b) => ({ type: String(b.type || '').toUpperCase(), text: String(b.text || ''), url: b.url ? String(b.url) : undefined })),
    button_var: buttonVar, supported
  };
}
/* Every template the account holds, a hundred a page, or the one named. */
async function readTemplates(name?: string): Promise<{ list?: Shape[]; error?: string }> {
  const out: Shape[] = [];
  const first = new URL(await graphUrl('/message_templates', WABA()));
  first.searchParams.set('fields', 'name,language,status,category,components,parameter_format');
  first.searchParams.set('limit', '100');
  if (name) first.searchParams.set('name', name);
  let next: string | null = first.toString();
  for (let page = 0; next && page < 5; page++) {
    const res: Response | null = await fetch(next, { headers: { 'Authorization': 'Bearer ' + TOKEN() } }).catch(() => null);
    if (!res) return { error: 'wa-failed' };
    const body = await res.json().catch(() => ({})) as Record<string, any>;
    if (!res.ok || body.error) {
      const e = body.error || {};
      console.error('wa-send: templates refused', res.status, e.code, e.message);
      return { error: named([res.status, e.code, e.error_subcode, e.message].filter((x) => x != null && x !== '').join(' ')) };
    }
    ((body.data || []) as Record<string, any>[]).forEach((t) => out.push(shapeOf(t)));
    next = body.paging && body.paging.next ? String(body.paging.next) : null;
  }
  return { list: out };
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  const body = await req.json().catch(() => ({})) as Record<string, any>;
  const action = String(body.action || '');
  const missing = [!PHONE() && 'WHATSAPP_PHONE_ID', !TOKEN() && 'WHATSAPP_TOKEN'].filter(Boolean) as string[];

  if (action === 'drain') {
    if (missing.length) return json({ ok: false, missing }, 200, origin);
    const svc = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let sent = 0, failed = 0;
    for (let round = 0; round < 5; round++) {
      const got = await svc.rpc('wa_claim', { p_limit: 20 });
      const rows = (got.data || []) as Record<string, any>[];
      if (got.error || !rows.length) break;
      for (const r of rows) {
        const out = await sendTemplate(r.to_number, r.template, r.lang, (r.params || []) as string[], undefined, r.button || undefined);
        await svc.rpc('wa_done', { p_id: r.id, p_ok: out.ok, p_wa_id: out.id || null, p_error: out.error || null });
        if (out.ok) sent++; else { failed++; console.error('wa-send: refused', r.purpose, out.error); }
      }
    }
    return json({ ok: true, sent, failed }, 200, origin);
  }

  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });

  if (action === 'templates' || action === 'compose') {
    const lack = missing.concat(WABA() ? [] : ['WHATSAPP_WABA_ID']);
    if (lack.length) return json({ error: 'wa-not-set-up', missing: lack }, 200, origin);

    if (action === 'templates') {
      const may = await db.rpc('allowed', { p_section: 'whatsapp', p_level: 'work' });
      if (may.error) return json({ error: 'needs-update' }, 200, origin);
      if (may.data !== true) return json({ error: 'denied' }, 200, origin);
      const got = await readTemplates();
      if (got.error) return json({ error: got.error }, 200, origin);
      return json({ templates: (got.list || []).filter((t) => t.status === 'APPROVED') }, 200, origin);
    }

    /* The composer's send. Who it goes to, and that the record is theirs,
       are the database's answer, never the page's. */
    const uuid = /^[0-9a-f-]{36}$/i;
    const toKind = String(body.to_kind || ''), toId = String(body.to_id || ''), purpose = String(body.purpose || 'message');
    const ref = body.ref ? String(body.ref) : null;
    if (!uuid.test(toId) || (ref && !uuid.test(ref))) return json({ error: 'bad-request' }, 400, origin);
    const prep = await db.rpc('wa_compose_prepare', { p_to_kind: toKind, p_to: toId, p_purpose: purpose, p_ref: ref });
    if (prep.error) return json({ error: 'needs-update' }, 200, origin);
    const p = (prep.data || {}) as Record<string, any>;
    if (p.error) return json({ error: p.error }, 200, origin);
    const want = (body.template || {}) as Record<string, any>;
    const tname = String(want.name || ''), tlang = String(want.language || '');
    if (!/^[a-z0-9_]{1,512}$/.test(tname)) return json({ error: 'wa-template' }, 200, origin);
    /* Sent recently (2026-10-14): the same message to the same person about
       the same record within the window goes again only once the colleague
       answered Send again (`again`). A database without the function sends. */
    if (body.again !== true) {
      const rc = await db.rpc('wa_sent_recently', { p_to_kind: toKind, p_to: toId, p_purpose: purpose, p_ref: ref, p_template: tname });
      const rd = (rc.data || {}) as Record<string, any>;
      if (!rc.error && rd.recent === true) return json({ error: 'recent', recent: rd }, 200, origin);
    }
    const found = await readTemplates(tname);
    if (found.error) return json({ error: found.error }, 200, origin);
    const t = (found.list || []).filter((x) => x.name === tname && x.language === tlang && x.status === 'APPROVED')[0];
    if (!t) return json({ error: 'wa-template' }, 200, origin);
    if (!t.supported) return json({ error: 'wa-unsupported' }, 200, origin);
    /* A Document header is a record's PDF (a report, a quotation, a Letter
       of Offer), and those go in one. */
    const docPurpose = purpose === 'report' || purpose === 'quotation' || purpose === 'offer';
    if ((t.header === 'DOCUMENT') !== docPurpose) return json({ error: 'needs-report' }, 200, origin);

    const given = (body.values || {}) as Record<string, any>;
    const values = t.body_vars.map((v) => String(given[v] == null ? '' : given[v]).trim());
    const headerValue = String(body.header_value || '').trim();
    const buttonValue = String(body.button_value || '').trim();
    if (values.some((v) => !v) || (t.header_var && !headerValue) || (t.button_var && !buttonValue)) {
      return json({ error: 'wa-params-missing' }, 200, origin);
    }
    const isNamed = t.format === 'NAMED';
    const record = (ok: boolean, waId: string | null, error: string | null) => db.rpc('wa_sent', {
      p_to_kind: toKind, p_to: toId, p_purpose: purpose, p_ref: ref, p_template: t.name, p_lang: t.language,
      p_category: t.category, p_params: values, p_ok: ok, p_wa_id: waId, p_error: error });

    let doc: { id: string; filename: string } | undefined;
    if (t.header === 'DOCUMENT') {
      const filename = String(body.filename || 'Document.pdf').replace(/[\\/:*?"<>|]+/g, ' ').slice(0, 200);
      const bytes = purpose === 'report' ? await keptReport(db, auth, String(ref)) : pdfFrom(String(body.pdf || ''));
      if (!bytes) return json({ error: 'bad-file' }, 200, origin);
      if (purpose !== 'report' && !(await namesRef(bytes, await refOf(db, purpose, String(ref))))) {
        return json({ error: 'bad-file' }, 200, origin);
      }
      const up = await uploadPdf(bytes, filename);
      if (!up.id) {
        console.error('wa-send: upload refused', up.error);
        await record(false, null, 'upload: ' + (up.error || ''));
        return json({ error: 'bad-file' }, 200, origin);
      }
      doc = { id: up.id, filename };
    }
    const out = await sendTemplate(String(p.number), t.name, t.language, values, doc, t.button_var ? buttonValue : undefined, {
      names: isNamed ? t.body_vars : undefined,
      header: t.header_var ? { text: headerValue, name: isNamed ? t.header_var : undefined } : undefined,
      buttonIndex: t.button_var ? t.button_var.index : 0,
      buttonName: isNamed && t.button_var ? t.button_var.name : undefined
    });
    if (!out.ok) console.error('wa-send: refused', purpose, out.error);
    const filed = await record(out.ok, out.id || null, out.error || null);
    if (filed.error) console.error('wa-send: not filed', filed.error.message);
    return out.ok ? json({ ok: true, to: p.name || null }, 200, origin) : json({ error: named(out.error) }, 200, origin);
  }

  if (action !== 'report' && action !== 'feedback') return json({ error: 'bad-request' }, 400, origin);
  if (missing.length) return json({ error: 'wa-not-set-up', missing }, 200, origin);

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
    const filename = String(body.filename || 'Report.pdf').replace(/[\\/:*?"<>|]+/g, ' ').slice(0, 200);
    const bytes = await keptReport(db, auth, id);
    if (!bytes) return json({ error: 'bad-file' }, 200, origin);
    const up = await uploadPdf(bytes, filename);
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
