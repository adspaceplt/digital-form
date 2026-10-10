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
 * Once CloudFront serves `private/*` behind the portal's key group
 * (docs/S3-STORAGE.md §5d) and `cf_private_ready` reads `on` in
 * `app_secrets`, the link is a CloudFront signed URL on mycdn.adspace.me,
 * signed with the media pass's key (`cf_media_private`, `cf_media_key_id`).
 * Until then it is an S3 presigned link.
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

/* An email compared as itself, never as a pattern: `_` and `%` in an
   address are letters here, not wildcards (audit P2, 2026-10-10). */
const exactEmail = (s: string) => String(s).replace(/[\\%_]/g, (c) => '\\' + c);

const ALLOWED_ORIGINS = [
  'https://digital.adspace.me',
  'http://localhost:8899'
];

// Five minutes: long enough to open, short enough that a forwarded link dies.
const EXPIRES = 300;
const PRIVATE_KEY = /^private\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.pdf$/;
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
    .in('key', ['cf_private_ready', 'cf_media_private', 'cf_media_key_id']);
  const s: Record<string, string> = {};
  (data || []).forEach((r: { key: string; value: string }) => { s[r.key] = r.value; });
  if (s.cf_private_ready !== 'on' || !s.cf_media_private || !s.cf_media_key_id) return null;
  const resource = `${CDN}/${path}`;
  const expires = Math.floor(Date.now() / 1000) + EXPIRES;
  const policy = JSON.stringify({
    Statement: [{ Resource: resource, Condition: { DateLessThan: { 'AWS:EpochTime': expires } } }]
  });
  const key = await crypto.subtle.importKey('pkcs8', unpem(s.cf_media_private), ALG, false, ['sign']);
  const sig = await crypto.subtle.sign(ALG.name, key, new TextEncoder().encode(policy));
  return `${resource}?Expires=${expires}&Signature=${cfSafe(b64(sig))}&Key-Pair-Id=${s.cf_media_key_id}`;
}

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
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...cors(origin) }
  });
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);

  let body: { campaignId?: string; token?: string; passcode?: string; reportVersion?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400, origin); }

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  let stored = '';

  if (body.reportVersion) {
    // A report's kept PDF: the database answers the caller as themselves.
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const version = String(body.reportVersion);
    if (!UUID.test(version)) return json({ error: 'bad_version' }, 400, origin);
    const supa = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data, error } = await supa.rpc('sm_report_file_key', { p_version: version });
    if (error || !data) return json({ error: 'not_allowed' }, 403, origin);
    if (data.error) return json({ error: data.error === 'not-kept' ? 'none' : 'not_allowed' }, data.error === 'not-kept' ? 404 : 403, origin);
    const key = String(data.key || '');
    if (!PRIVATE_KEY.test(key)) return json({ error: 'bad_key' }, 400, origin);
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
  }

  if (body.token) {
    // The client's page: the same answer the page itself was given.
    const token = String(body.token);
    if (!/^[A-Za-z0-9_-]{6,64}$/.test(token)) return json({ error: 'bad_token' }, 400, origin);
    const pub = createClient(url, anon);
    const { data, error } = await pub.rpc('get_campaign', {
      p_token: token, p_passcode: body.passcode ? String(body.passcode) : null
    });
    if (error || !data || data.error) return json({ error: 'not_allowed' }, 403, origin);
    stored = String((data.campaign && data.campaign.invoice_url) || '');
  } else {
    // The console: a signed-in, active colleague, reading the row as themselves.
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const supa = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data: { user }, error: authErr } = await supa.auth.getUser();
    if (authErr || !user?.email) return json({ error: 'not_signed_in' }, 401, origin);

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: member } = await admin.from('team_members')
      .select('active').ilike('email', exactEmail(user.email)).maybeSingle();
    if (!member || !member.active) return json({ error: 'not_team' }, 403, origin);

    const campaignId = String(body.campaignId ?? '');
    if (!UUID.test(campaignId)) return json({ error: 'bad_campaign' }, 400, origin);
    const { data: row, error } = await supa.from('campaigns')
      .select('invoice_url').eq('id', campaignId).maybeSingle();
    if (error || !row) return json({ error: 'not_allowed' }, 403, origin);
    stored = String(row.invoice_url || '');
  }

  if (!stored) return json({ error: 'none' }, 404, origin);
  // An invoice from before is a public address; it opens as it always has.
  if (/^https:\/\//.test(stored)) return json({ url: stored }, 200, origin);
  if (!PRIVATE_KEY.test(stored)) return json({ error: 'bad_key' }, 400, origin);

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
