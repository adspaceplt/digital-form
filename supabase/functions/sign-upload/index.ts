/*
 * sign-upload — hands the browser a short lived permission to PUT one file
 * into the ADspace S3 bucket, so large videos never pass through Supabase.
 *
 * AWS credentials live in this function's secrets and never reach the browser.
 * A signed URL is issued to someone signed in to /admin/, or to a creator
 * holding the code for a booking we are waiting on a draft for.
 *
 * Deploy:  supabase functions deploy sign-upload
 *
 * Turn OFF "Verify JWT" for this function in the dashboard. The platform check
 * rejects the browser's CORS preflight, which carries no Authorization header,
 * and this function verifies the caller itself below.
 */
import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const ALLOWED_ORIGINS = [
  'https://digital.adspace.me',
  'http://localhost:8899'
];

const EXT_OK = /^[a-z0-9]{1,5}$/;
const MAX_BYTES = 2 * 1024 * 1024 * 1024;   // 2 GB, a sane ceiling for a review copy

function cors(origin: string | null) {
  const allow = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allow,
    // supabase-js sends x-client-info and apikey as well. Leaving them out makes
    // the browser preflight fail, which surfaces as "Failed to send a request".
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin'
  };
}

function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...cors(origin) }
  });
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);

  let body: {
    ext?: string; clientId?: string; size?: number;
    creatorCode?: string; optionId?: string;
  };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400, origin); }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  /* Two callers, one bucket. The console signs in; a creator holds a code and
     no account at all, so their claim is checked against the booking rather
     than against a session: the code has to name a live creator, the booking
     has to be theirs, and we have to be waiting for that draft. The key is
     built from the option id checked here and never from anything the browser
     sent, so a real code cannot be pointed at another booking's folder. */
  const creatorCode = String(body.creatorCode ?? '').toUpperCase();
  const optionId = String(body.optionId ?? '');
  let scope = '';

  if (creatorCode) {
    if (!/^[A-Z0-9]{8}$/.test(creatorCode)) return json({ error: 'bad_code' }, 400, origin);
    if (!/^[0-9a-f-]{36}$/.test(optionId)) return json({ error: 'bad_option' }, 400, origin);
    const { data: ok } = await admin.rpc('creator_may_upload', {
      p_code: creatorCode, p_option: optionId
    });
    if (!ok) return json({ error: 'not_allowed' }, 403, origin);
    scope = `creator/${optionId}`;
  } else {
    // Only a signed in team member gets a signed URL for a client's folder.
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);

    const supa = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: auth } } }
    );
    const { data: { user }, error: authErr } = await supa.auth.getUser();
    if (authErr || !user?.email) return json({ error: 'not_signed_in' }, 401, origin);

    // Clients sign in to /client/ with the same Authentication, so a login by
    // itself is not enough: the person has to be an active member of the team,
    // asked of the database with the service role.
    const { data: member } = await admin.from('team_members')
      .select('active').ilike('email', user.email).maybeSingle();
    if (!member || !member.active) return json({ error: 'not_team' }, 403, origin);

    const clientId = String(body.clientId ?? '');
    if (!/^[0-9a-f-]{36}$/.test(clientId)) return json({ error: 'bad_client' }, 400, origin);
    scope = clientId;
  }

  // 2. Validate what they are asking to upload.
  const ext = String(body.ext ?? '').toLowerCase();
  const size = Number(body.size ?? 0);

  if (!EXT_OK.test(ext)) return json({ error: 'bad_extension' }, 400, origin);
  if (!size || size > MAX_BYTES) return json({ error: 'too_large' }, 400, origin);

  // 3. Sign a PUT for one key we choose. The browser never picks the path.
  const bucket = Deno.env.get('S3_BUCKET')!;
  const region = Deno.env.get('S3_REGION')!;
  const prefix = Deno.env.get('S3_PREFIX') ?? 'portal';
  const cdnBase = (Deno.env.get('CDN_BASE') ?? '').replace(/\/+$/, '');

  const key = `${prefix}/${scope}/${crypto.randomUUID()}.${ext}`;
  const target = `https://${bucket}.s3.${region}.amazonaws.com/${key}`;

  const aws = new AwsClient({
    accessKeyId: Deno.env.get('AWS_ACCESS_KEY_ID')!,
    secretAccessKey: Deno.env.get('AWS_SECRET_ACCESS_KEY')!,
    region,
    service: 's3'
  });

  const signed = await aws.sign(new Request(target, { method: 'PUT' }), {
    aws: { signQuery: true, allHeaders: false },
    headers: {}
  });

  return json({
    uploadUrl: signed.url,
    publicUrl: `${cdnBase}/${key}`,
    key
  }, 200, origin);
});
