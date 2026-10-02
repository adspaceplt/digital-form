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
 * AWS credentials are the upload key's (`AWS_ACCESS_KEY_ID`,
 * `AWS_SECRET_ACCESS_KEY`), which needs s3:GetObject on `private/*`
 * (docs/S3-STORAGE.md §5). They never reach the browser.
 *
 * Deploy with "Verify JWT" off, as sign-upload: the platform check refuses the
 * browser's CORS preflight, and this function checks the caller itself.
 */
import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const ALLOWED_ORIGINS = [
  'https://digital.adspace.me',
  'http://localhost:8899'
];

// Five minutes: long enough to open, short enough that a forwarded link dies.
const EXPIRES = 300;
const PRIVATE_KEY = /^private\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.pdf$/;
const UUID = /^[0-9a-f-]{36}$/;

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

  let body: { campaignId?: string; token?: string; passcode?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400, origin); }

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  let stored = '';

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
      .select('active').ilike('email', user.email).maybeSingle();
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
