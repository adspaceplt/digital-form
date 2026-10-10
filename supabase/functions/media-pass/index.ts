/*
 * media-pass — hands a browser the CloudFront signed cookies that open the
 * portal's media under `content/` for twelve hours (2026-10-03).
 *
 * Content Review files, creator drafts and everything else uploaded to S3 sit
 * under `content/`. Once the CloudFront behaviour for `content/*` trusts the
 * portal's key group (docs/S3-STORAGE.md §6), a file opens only with these
 * cookies: a raw address copied out of a page answers 403. The stored
 * addresses never change; the browser carries the pass to mycdn.adspace.me
 * because both hosts are on adspace.me.
 *
 * A pass is given only to a caller who proves one of the four ways in, with
 * the same functions the pages themselves are answered by:
 *   - { review: key, passcode }   a client's Content Review link (get_review_feed)
 *   - { campaign: key, passcode } a client's creator selection link (get_campaign)
 *   - { creator: code }           a creator's code (get_creator)
 *   - nothing, signed in          an active colleague (team_members), or a
 *                                 client contact with live portal access
 *                                 (the client portal, 2026-10-08)
 * Nothing here writes a record, and nothing deletes.
 *
 * Keys: the first call makes an RSA pair and keeps both halves in
 * `app_secrets` (`cf_media_private`, `cf_media_public`); the private half never
 * leaves the database. { publicKey: true } answers the public half, which is
 * pasted into CloudFront. CloudFront's ID for it is kept as `cf_media_key_id`;
 * until it is there every caller is answered { off: true } and the pages carry
 * on as before.
 *
 * Deploy with "Verify JWT" off: the client pages call it with the anon key
 * alone, and the platform check refuses the browser's CORS preflight.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

/* An email compared as itself, never as a pattern: `_` and `%` in an
   address are letters here, not wildcards (audit P2, 2026-10-10). */
const exactEmail = (s: string) => String(s).replace(/[\\%_]/g, (c) => '\\' + c);

const ALLOWED_ORIGINS = [
  'https://digital.adspace.me',
  'http://localhost:8899'
];

// Twelve hours: a working day, so a review left open does not lose its media.
const HOURS = 12;
const RESOURCE = 'https://mycdn.adspace.me/content/*';

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

function b64(buf: ArrayBuffer | Uint8Array): string {
  const u8 = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let s = '';
  for (let i = 0; i < u8.length; i++) s += String.fromCharCode(u8[i]);
  return btoa(s);
}
// CloudFront's own URL-safe alphabet: + → -, = → _, / → ~.
function cfSafe(s: string): string {
  return s.replace(/\+/g, '-').replace(/=/g, '_').replace(/\//g, '~');
}
function pem(kind: string, der: ArrayBuffer): string {
  const body = b64(der).replace(/(.{64})/g, '$1\n').replace(/\n$/, '');
  return `-----BEGIN ${kind}-----\n${body}\n-----END ${kind}-----\n`;
}
function unpem(text: string): Uint8Array {
  const body = text.replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, '');
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

const ALG = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-1' };

// deno-lint-ignore no-explicit-any
async function secrets(admin: any): Promise<Record<string, string>> {
  const { data } = await admin.from('app_secrets').select('key, value')
    .in('key', ['cf_media_private', 'cf_media_public', 'cf_media_key_id']);
  const out: Record<string, string> = {};
  (data || []).forEach((r: { key: string; value: string }) => { out[r.key] = r.value; });
  return out;
}

// The pair is made once. Two first calls at once both insert-if-absent and
// then read back whichever landed, so they agree on one key.
// deno-lint-ignore no-explicit-any
async function keys(admin: any): Promise<Record<string, string>> {
  let s = await secrets(admin);
  if (s.cf_media_private && s.cf_media_public) return s;
  const pair = await crypto.subtle.generateKey(
    { ...ALG, modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]) }, true, ['sign', 'verify']
  ) as CryptoKeyPair;
  const priv = pem('PRIVATE KEY', await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pub = pem('PUBLIC KEY', await crypto.subtle.exportKey('spki', pair.publicKey));
  await admin.from('app_secrets').upsert(
    [{ key: 'cf_media_private', value: priv }, { key: 'cf_media_public', value: pub }],
    { onConflict: 'key', ignoreDuplicates: true }
  );
  s = await secrets(admin);
  return s;
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);

  let body: { review?: string; campaign?: string; creator?: string; passcode?: string; publicKey?: boolean };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400, origin); }

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  if (body.publicKey) {
    const k = await keys(admin);
    return json({ publicKey: k.cf_media_public, keyId: k.cf_media_key_id || null }, 200, origin);
  }

  // 1. Who is asking, proved the way the page itself was answered.
  const pub = createClient(url, anon);
  const pass = body.passcode ? String(body.passcode) : null;
  const key = (v: unknown) => /^[A-Za-z0-9_-]{6,64}$/.test(String(v || ''));
  if (body.review) {
    if (!key(body.review)) return json({ error: 'bad_token' }, 400, origin);
    const { data, error } = await pub.rpc('get_review_feed', { p_token: String(body.review), p_passcode: pass });
    if (error || !data || data.error) return json({ error: 'not_allowed' }, 403, origin);
  } else if (body.campaign) {
    if (!key(body.campaign)) return json({ error: 'bad_token' }, 400, origin);
    const { data, error } = await pub.rpc('get_campaign', { p_token: String(body.campaign), p_passcode: pass });
    if (error || !data || data.error) return json({ error: 'not_allowed' }, 403, origin);
  } else if (body.creator) {
    const code = String(body.creator).toUpperCase();
    if (!/^[A-Z0-9]{8}$/.test(code)) return json({ error: 'bad_code' }, 400, origin);
    const { data, error } = await pub.rpc('get_creator', { p_code: code });
    if (error || !data || data.error) return json({ error: 'not_allowed' }, 403, origin);
  } else {
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const supa = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data: { user }, error: authErr } = await supa.auth.getUser();
    if (authErr || !user?.email) return json({ error: 'not_signed_in' }, 401, origin);
    const { data: member } = await admin.from('team_members')
      .select('active').ilike('email', exactEmail(user.email)).maybeSingle();
    if (!member || !member.active) {
      /* A client's contact signed in to the client portal (2026-10-08): their
         logos and reports sit under content/ too. Live portal access only,
         as portal_clients() answers it; an address that is also a colleague's
         was answered above. */
      if (member) return json({ error: 'not_team' }, 403, origin);
      const { data: contact } = await admin.from('client_contacts')
        .select('id').eq('portal_access', true).is('archived_at', null)
        .ilike('email', exactEmail(user.email)).limit(1);
      if (!contact || !contact.length) return json({ error: 'not_allowed' }, 403, origin);
    }
  }

  // 2. Not switched on yet: the pages carry on as before.
  const k = await keys(admin);
  if (!k.cf_media_key_id) return json({ off: true }, 200, origin);

  // 3. One custom policy over every file under content/, signed with the
  //    private half, in the three cookies CloudFront reads.
  const expires = Math.floor(Date.now() / 1000) + HOURS * 3600;
  const policy = JSON.stringify({
    Statement: [{ Resource: RESOURCE, Condition: { DateLessThan: { 'AWS:EpochTime': expires } } }]
  });
  const signer = await crypto.subtle.importKey('pkcs8', unpem(k.cf_media_private), ALG, false, ['sign']);
  const sig = await crypto.subtle.sign(ALG.name, signer, new TextEncoder().encode(policy));
  return json({
    policy: cfSafe(btoa(policy)),
    signature: cfSafe(b64(sig)),
    keyPairId: k.cf_media_key_id,
    expires
  }, 200, origin);
});
