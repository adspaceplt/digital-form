/*
 * sign-download — hands the browser a link to a private file in the ADspace
 * S3 bucket that lasts five minutes. Today that file is a campaign's invoice
 * PDF (2026-10-02): new invoices are uploaded under `private/`, which
 * CloudFront does not serve, so the only way in is a link signed here.
 *
 * The browser never names the file. It names the campaign it may already
 * read, and the function finds the file from that:
 *   - a colleague signed in to /admin/ sends { campaignId }; the row is read
 *     with their own token, so the database's own policy decides;
 *   - a client on the selection page sends { token, passcode }; the file is
 *     the one `get_campaign` hands that link, which withholds the invoice until
 *     a creator is confirmed.
 * An older invoice is a public CloudFront address and is handed back as it
 * is. Nothing here writes or deletes.
 *
 * A report's kept PDF (2026-10-07) comes back through here as bytes, never
 * as a link: the caller sends { reportVersion } with their own sign-in (a
 * colleague, or the client's portal contact), the key is what
 * `sm_report_file_key` answers them, and the file is read from the bucket
 * with the upload key and streamed back, so the page saves it under its own
 * name exactly as it went out.
 *
 * A signed quotation's sealed copy (2026-11-17) comes back the same way: a
 * colleague sends { quotation } with their sign-in (`quotation_seal_key`
 * answers them as themselves); the client's link sends { quoteKey } and the
 * service role reads the quotation the link shows (`quote_seal_key`, once
 * ADspace has confirmed it). The key is always under the quotation's own
 * client's folder.
 *
 * A report's pictures (2026-11-20) are kept under `private/{client}/thumbs/`
 * and come back as S3 links signed for an hour, many in one call: the
 * caller sends { thumbs: { report, keys } } with their own sign-in, and
 * `sm_report_thumbs` answers them, as themselves, which of those keys the
 * report names and they may read (a colleague at Reports or Clients View
 * in scope, or the client's portal contact for a live version). The links
 * are S3's, never CloudFront's, so the report PDF drawn in the browser can
 * read the bytes (the bucket's CORS allows GET from the portal).
 *
 * Once CloudFront serves `private/*` behind the portal's key group
 * (docs/S3-STORAGE.md §5d) and `cf_private_ready` reads `on` in
 * `app_secrets`, the link is a CloudFront signed URL on mycdn.adspace.me,
 * signed with private/'s own key (`cf_private_files_private`,
 * `cf_private_files_key_id`; CloudFront key group `adspace-portal-private`),
 * never the media pass's, so a pass for content/ can open nothing here
 * (2026-11-21, the open CloudFront finding); the media pass's key
 * (`cf_media_private`, `cf_media_key_id`) only while private/'s own is not
 * yet stored. Until then it is an S3 presigned link.
 *
 * AWS credentials are the upload key's (`AWS_ACCESS_KEY_ID`,
 * `AWS_SECRET_ACCESS_KEY`), which needs s3:GetObject on `private/*`
 * (docs/S3-STORAGE.md §5). They never reach the browser.
 *
 * Deploy with "Verify JWT" off, as sign-upload: the platform check refuses the
 * browser's CORS preflight, and this function checks the caller itself.
 */
import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json as send } from '../_shared/cors.ts';

/* Every answer is no-store: it carries a signed pass or link. */
const json = (body: unknown, status: number, origin: string | null) =>
  send(body, status, origin, { 'Cache-Control': 'no-store' });

/* An email compared as itself, never as a pattern: `_` and `%` in an
   address are letters here, not wildcards (audit P2, 2026-10-10). */
const exactEmail = (s: string) => String(s).replace(/[\\%_]/g, (c) => '\\' + c);

// Five minutes: long enough to open, short enough that a forwarded link dies.
const EXPIRES = 300;
const PRIVATE_KEY = /^private\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.pdf$/;
const THUMB_KEY = /^private\/[0-9a-f-]{36}\/thumbs\/[0-9a-f-]{36}\.jpg$/;
// A report picture's link: an hour, so a report open for a while keeps them.
const THUMB_EXPIRES = 3600;
const UUID = /^[0-9a-f-]{36}$/;
const CDN = 'https://mycdn.adspace.me';
const ALG = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-1' };

function b64(buf: ArrayBuffer): string {
  const u8 = new Uint8Array(buf);
  let s = '';
  for (let i = 0; i < u8.length; i++) s += String.fromCharCode(u8[i]);
  return btoa(s);
}
// CloudFront's own URL-safe alphabet: + → -, = → _, / → ~.
function cfSafe(s: string): string {
  return s.replace(/\+/g, '-').replace(/=/g, '_').replace(/\//g, '~');
}
function unpem(text: string): Uint8Array {
  const bin = atob(text.replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, ''));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// A CloudFront signed URL with a canned policy: this one file, five minutes.
// null while CloudFront is not yet set up to serve private/.
async function cdnLink(path: string): Promise<string | null> {
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data } = await admin.from('app_secrets').select('key, value')
    .in('key', ['cf_private_ready', 'cf_private_files_private', 'cf_private_files_key_id', 'cf_media_private', 'cf_media_key_id']);
  const s: Record<string, string> = {};
  (data || []).forEach((r: { key: string; value: string }) => { s[r.key] = r.value; });
  const own = !!(s.cf_private_files_private && s.cf_private_files_key_id);
  const pem = own ? s.cf_private_files_private : s.cf_media_private;
  const keyId = own ? s.cf_private_files_key_id : s.cf_media_key_id;
  if (s.cf_private_ready !== 'on' || !pem || !keyId) return null;
  const resource = `${CDN}/${path}`;
  const expires = Math.floor(Date.now() / 1000) + EXPIRES;
  const policy = JSON.stringify({
    Statement: [{ Resource: resource, Condition: { DateLessThan: { 'AWS:EpochTime': expires } } }]
  });
  const key = await crypto.subtle.importKey('pkcs8', unpem(pem), ALG, false, ['sign']);
  const sig = await crypto.subtle.sign(ALG.name, key, new TextEncoder().encode(policy));
  return `${resource}?Expires=${expires}&Signature=${cfSafe(b64(sig))}&Key-Pair-Id=${keyId}`;
}

/* The caller's own address, passed on when this function asks for the
   link as the page did, so a wrong access code counts against the person
   who typed it and never against this function's own address, which every
   client shares (second audit, item 4). It is the address Cloudflare saw
   (`cf-connecting-ip`, else the last X-Forwarded-For entry, the one the
   gateway appended), never the first, which the caller writes (audit
   2026-10-18, item 1). Cloudflare stamps this function's own address on
   the call it makes, so the caller's rides in `x-adspace-ip` beside the
   relay secret, the only way `request_ip()` takes it. */
// deno-lint-ignore no-explicit-any
async function callerHeaders(req: Request, admin: any): Promise<Record<string, string>> {
  const xff = (req.headers.get('x-forwarded-for') || '').split(',');
  const ip = (req.headers.get('cf-connecting-ip') || '').trim() || xff[xff.length - 1].trim();
  if (!/^[0-9A-Fa-f.:]{3,45}$/.test(ip)) return {};
  const { data } = await admin.from('app_secrets').select('value').eq('key', 'ip_relay_secret').maybeSingle();
  return data && data.value ? { 'x-adspace-ip': ip, 'x-adspace-relay': String(data.value) } : {};
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);

  let body: { campaignId?: string; token?: string; passcode?: string; reportVersion?: string; quotation?: string; quoteKey?: string;
    thumbs?: { report?: string; keys?: unknown };
    personnel?: { member?: string | null; kind?: string };
    outstation?: { photo?: string } };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400, origin); }

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  let stored = '';
  let owner = '';

  /* A kept file comes back as bytes, read from the bucket with the upload
     key, so the page saves it under its own name exactly as it went out. */
  const stream = async (key: string, owner?: string) => {
    if (!PRIVATE_KEY.test(key)) return json({ error: 'bad_key' }, 400, origin);
    if (owner && !key.startsWith(`private/${owner}/`)) return json({ error: 'bad_key' }, 400, origin);
    const aws = new AwsClient({
      accessKeyId: Deno.env.get('AWS_ACCESS_KEY_ID')!,
      secretAccessKey: Deno.env.get('AWS_SECRET_ACCESS_KEY')!,
      region: Deno.env.get('S3_REGION')!,
      service: 's3'
    });
    const got = await aws.fetch(`https://${Deno.env.get('S3_BUCKET')!}.s3.${Deno.env.get('S3_REGION')!}.amazonaws.com/${key}`);
    if (!got.ok || !got.body) return json({ error: 'none' }, 404, origin);
    return new Response(got.body, {
      status: 200,
      headers: { 'Content-Type': 'application/octet-stream', 'Cache-Control': 'no-store', ...cors(origin) }
    });
  };
  // deno-lint-ignore no-explicit-any
  const kept = (data: any, error: unknown, owned = false) => {
    if (error || !data) return json({ error: 'not_allowed' }, 403, origin);
    if (data.error) return json({ error: data.error === 'not-kept' ? 'none' : 'not_allowed' }, data.error === 'not-kept' ? 404 : 403, origin);
    return stream(String(data.key || ''), owned ? String(data.client || '') : undefined);
  };

  if (body.thumbs) {
    /* A report's pictures: the database answers which of the keys asked
       for this caller may read, every one under the report's own client. */
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const report = String(body.thumbs.report ?? '');
    const asked = Array.isArray(body.thumbs.keys) ? (body.thumbs.keys as unknown[]).map(String) : [];
    if (!UUID.test(report) || !asked.length || asked.length > 400 || asked.some((k) => !THUMB_KEY.test(k))) {
      return json({ error: 'bad_request' }, 400, origin);
    }
    const supa = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data, error } = await supa.rpc('sm_report_thumbs', { p_report: report, p_keys: asked });
    if (error || !data) return json({ error: 'not_allowed' }, 403, origin);
    if (data.error) return json({ error: 'not_allowed' }, 403, origin);
    const client = String(data.client || '');
    const ok = (Array.isArray(data.keys) ? data.keys : []).map(String)
      .filter((k: string) => THUMB_KEY.test(k) && k.startsWith(`private/${client}/thumbs/`));
    const bucket = Deno.env.get('S3_BUCKET')!;
    const region = Deno.env.get('S3_REGION')!;
    const aws = new AwsClient({
      accessKeyId: Deno.env.get('AWS_ACCESS_KEY_ID')!,
      secretAccessKey: Deno.env.get('AWS_SECRET_ACCESS_KEY')!,
      region,
      service: 's3'
    });
    const urls: Record<string, string> = {};
    for (const k of ok) {
      const target = new URL(`https://${bucket}.s3.${region}.amazonaws.com/${k}`);
      target.searchParams.set('X-Amz-Expires', String(THUMB_EXPIRES));
      const signed = await aws.sign(new Request(target.toString(), { method: 'GET' }), {
        aws: { signQuery: true, allHeaders: false },
        headers: {}
      });
      urls[k] = signed.url;
    }
    return json({ urls, expires_in: THUMB_EXPIRES }, 200, origin);
  }

  if (body.reportVersion) {
    // A report's kept PDF: the database answers the caller as themselves.
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const version = String(body.reportVersion);
    if (!UUID.test(version)) return json({ error: 'bad_version' }, 400, origin);
    const supa = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data, error } = await supa.rpc('sm_report_file_key', { p_version: version });
    return kept(data, error);
  }

  /* A signed quotation's sealed copy (SIGNED DOCUMENT SEAL, 2026-11-17):
     a colleague names the quotation and the database answers them as
     themselves; the client's link names its key and the service role reads
     the quotation that link shows, once ADspace has confirmed it. Either
     way the file is the quotation's own client's. */
  if (body.quotation) {
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const id = String(body.quotation);
    if (!UUID.test(id)) return json({ error: 'bad_quotation' }, 400, origin);
    const supa = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data, error } = await supa.rpc('quotation_seal_key', { p_id: id });
    return kept(data, error, true);
  }
  if (body.quoteKey) {
    const qk = String(body.quoteKey);
    if (!/^[a-z0-9]{8}$/.test(qk)) return json({ error: 'bad_key' }, 400, origin);
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data, error } = await admin.rpc('quote_seal_key', { p_key: qk });
    return kept(data, error, true);
  }

  if (body.outstation) {
    /* A trip's photo (OUTSTATION RECORD, 2026-11-23), as bytes: the key is
       what `outstation_photo_key` answers the caller (who drove the trip,
       who joined it, or `ops.outstation`), under that trip's own folder. */
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const photo = String(body.outstation.photo ?? '');
    if (!UUID.test(photo)) return json({ error: 'bad_request' }, 400, origin);
    const supa = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data, error } = await supa.rpc('outstation_photo_key', { p_photo: photo });
    if (error || !data) return json({ error: 'not_allowed' }, 403, origin);
    if (data.error) return json({ error: data.error === 'not-kept' ? 'none' : 'not_allowed' }, data.error === 'not-kept' ? 404 : 403, origin);
    const key = String(data.key || ''), trip = String(data.trip || '');
    const m = key.match(/^private\/outstation\/([0-9a-f-]{36})\/[0-9a-f-]{36}\.jpg$/);
    if (!m || m[1] !== trip) return json({ error: 'bad_key' }, 400, origin);
    const aws = new AwsClient({
      accessKeyId: Deno.env.get('AWS_ACCESS_KEY_ID')!,
      secretAccessKey: Deno.env.get('AWS_SECRET_ACCESS_KEY')!,
      region: Deno.env.get('S3_REGION')!,
      service: 's3'
    });
    const got = await aws.fetch(`https://${Deno.env.get('S3_BUCKET')!}.s3.${Deno.env.get('S3_REGION')!}.amazonaws.com/${key}`);
    if (!got.ok || !got.body) return json({ error: 'none' }, 404, origin);
    return new Response(got.body, {
      status: 200,
      /* As octet-stream: supabase-js hands the page a file only for
         octet-stream or a PDF, and an image/jpeg answer reached it as text
         (2026-11-24); the page names the type (`ADspaceAPI.fileOf`). */
      headers: { 'Content-Type': 'application/octet-stream', 'Cache-Control': 'no-store', ...cors(origin) }
    });
  }

  if (body.personnel) {
    /* A colleague's employee record file (2026-11-16), as bytes: the key is
       what `personnel_file_key` answers the caller (their own behind the
       fresh proof, or anyone's at Personnel), under that colleague's own
       private folder. */
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const want = body.personnel.member ? String(body.personnel.member) : null;
    const kind = String(body.personnel.kind ?? '');
    if ((want !== null && !UUID.test(want)) || !['nric_front', 'nric_back', 'photo'].includes(kind)) return json({ error: 'bad_request' }, 400, origin);
    const supa = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data, error } = await supa.rpc('personnel_file_key', { p_member: want, p_kind: kind });
    if (error || !data) return json({ error: 'not_allowed' }, 403, origin);
    if (data.error) return json({ error: data.error === 'not-kept' ? 'none' : 'not_allowed' }, data.error === 'not-kept' ? 404 : 403, origin);
    const key = String(data.key || ''), who = String(data.member || '');
    const m = key.match(/^private\/personnel\/([0-9a-f-]{36})\/[0-9a-f-]{36}\.(jpg|png|pdf)$/);
    if (!m || m[1] !== who) return json({ error: 'bad_key' }, 400, origin);
    const aws = new AwsClient({
      accessKeyId: Deno.env.get('AWS_ACCESS_KEY_ID')!,
      secretAccessKey: Deno.env.get('AWS_SECRET_ACCESS_KEY')!,
      region: Deno.env.get('S3_REGION')!,
      service: 's3'
    });
    const got = await aws.fetch(`https://${Deno.env.get('S3_BUCKET')!}.s3.${Deno.env.get('S3_REGION')!}.amazonaws.com/${key}`);
    if (!got.ok || !got.body) return json({ error: 'none' }, 404, origin);
    /* A picture as octet-stream, as a trip's photo (2026-11-24). */
    const type = m[2] === 'pdf' ? 'application/pdf' : 'application/octet-stream';
    return new Response(got.body, {
      status: 200,
      headers: { 'Content-Type': type, 'Cache-Control': 'no-store', ...cors(origin) }
    });
  }

  if (body.token) {
    // The client's page: the same answer the page itself was given.
    const token = String(body.token);
    if (!/^[A-Za-z0-9_-]{6,64}$/.test(token)) return json({ error: 'bad_token' }, 400, origin);
    const relay = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const pub = createClient(url, anon, { global: { headers: await callerHeaders(req, relay) } });
    const { data, error } = await pub.rpc('get_campaign', {
      p_token: token, p_passcode: body.passcode ? String(body.passcode) : null
    });
    if (error || !data || data.error) return json({ error: 'not_allowed' }, 403, origin);
    stored = String((data.campaign && data.campaign.invoice_url) || '');
    const { data: own } = await relay.from('campaigns').select('client_id').eq('access_token', token).maybeSingle();
    owner = String((own && own.client_id) || '');
  } else {
    // The console: a signed-in, active colleague, reading the row as themselves.
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const supa = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data: { user }, error: authErr } = await supa.auth.getUser();
    if (authErr || !user?.email) return json({ error: 'not_signed_in' }, 401, origin);

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    // A removed colleague may share the address with one added again: the
    // active row answers (Team audit, item 10).
    const { data: member } = await admin.from('team_members')
      .select('active').ilike('email', exactEmail(user.email))
      .order('active', { ascending: false }).limit(1).maybeSingle();
    if (!member || !member.active) return json({ error: 'not_team' }, 403, origin);

    const campaignId = String(body.campaignId ?? '');
    if (!UUID.test(campaignId)) return json({ error: 'bad_campaign' }, 400, origin);
    const { data: row, error } = await supa.from('campaigns')
      .select('invoice_url, client_id').eq('id', campaignId).maybeSingle();
    if (error || !row) return json({ error: 'not_allowed' }, 403, origin);
    stored = String(row.invoice_url || '');
    owner = String(row.client_id || '');
  }

  if (!stored) return json({ error: 'none' }, 404, origin);
  // An invoice from before is a public address; it opens as it always has.
  if (/^https:\/\//.test(stored)) return json({ url: stored }, 200, origin);
  if (!PRIVATE_KEY.test(stored)) return json({ error: 'bad_key' }, 400, origin);
  // The file is the campaign's own client's: a key written under another
  // client's folder is never signed (audit 2026-10-18, item 3).
  if (!owner || !stored.startsWith(`private/${owner}/`)) return json({ error: 'bad_key' }, 400, origin);

  const cdn = await cdnLink(stored);
  if (cdn) return json({ url: cdn, expires_in: EXPIRES }, 200, origin);

  const bucket = Deno.env.get('S3_BUCKET')!;
  const region = Deno.env.get('S3_REGION')!;
  const target = new URL(`https://${bucket}.s3.${region}.amazonaws.com/${stored}`);
  target.searchParams.set('X-Amz-Expires', String(EXPIRES));
  target.searchParams.set('response-content-type', 'application/pdf');
  target.searchParams.set('response-content-disposition', 'inline; filename="invoice.pdf"');

  const aws = new AwsClient({
    accessKeyId: Deno.env.get('AWS_ACCESS_KEY_ID')!,
    secretAccessKey: Deno.env.get('AWS_SECRET_ACCESS_KEY')!,
    region,
    service: 's3'
  });
  const signed = await aws.sign(new Request(target.toString(), { method: 'GET' }), {
    aws: { signQuery: true, allHeaders: false },
    headers: {}
  });
  return json({ url: signed.url, expires_in: EXPIRES }, 200, origin);
});
