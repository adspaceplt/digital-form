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
import { cors, json } from '../_shared/cors.ts';

/* An email compared as itself, never as a pattern: `_` and `%` in an
   address are letters here, not wildcards (audit P2, 2026-10-10). */
const exactEmail = (s: string) => String(s).replace(/[\\%_]/g, (c) => '\\' + c);

/* What the pages upload, and the one type each is stored as (audit
   2026-10-16, finding 4): a content set's videos and pictures and their cover
   frames, a client's logo, a creator's draft (pictures, videos, a PDF), the
   team's hand-in for a creator (and a ZIP), an invoice and a report's kept
   PDF. Nothing a browser would run (HTML, SVG, script) is signed. The type
   is signed into the PUT, so the uploader cannot choose another. */
const EXT_TYPE: Record<string, string> = {
  mp4: 'video/mp4', m4v: 'video/x-m4v', mov: 'video/quicktime', webm: 'video/webm',
  mkv: 'video/x-matroska', mpg: 'video/mpeg', mpeg: 'video/mpeg',
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', gif: 'image/gif',
  heic: 'image/heic', heif: 'image/heif', avif: 'image/avif',
  pdf: 'application/pdf', zip: 'application/zip'
};
/* A signed PUT is good for fifteen minutes from signing (aws4fetch's own
   default is a day); a long upload only has to start inside it. */
const PUT_EXPIRES = 900;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/* What a colleague may upload, and what each needs. `field` names the
   parent record in the request; `clientOf` reads it with the service role
   (its client, and its state where the purpose waits on one); `sections`
   are the sections or parts whose Work allows it; `kind` and `level` are
   the client scope asked of the database as the caller. */
type Owner = { client: string; state?: string } | null;
// deno-lint-ignore no-explicit-any
type Admin = any;
const one = async (q: Promise<{ data: unknown }>) => ((await q).data ?? null) as Record<string, unknown> | null;
const PURPOSES: Record<string, {
  field: string; sections: string[]; kind: string; level: string; private?: 'may' | 'must'; states?: string[];
  clientOf: (admin: Admin, id: string) => Promise<Owner>;
}> = {
  // A content set's assets, their cover frames and a post's replaced file.
  review: { field: 'batchId', sections: ['review.sets'], kind: 'batch', level: 'work',
    clientOf: async (a, id) => { const r = await one(a.from('batches').select('client_id').eq('id', id).maybeSingle());
      return r ? { client: String(r.client_id) } : null; } },
  // A client's logo, from its Brand (Content Review's sheet keeps the access code alone).
  logo: { field: 'clientId', sections: ['clients'], kind: 'client', level: 'work',
    clientOf: async (a, id) => { const r = await one(a.from('clients').select('id').eq('id', id).maybeSingle());
      return r ? { client: String(r.id) } : null; } },
  // A file the team hands in for a creator, while the draft is owed.
  campaign: { field: 'optionId', sections: ['campaigns.campaigns'], kind: 'option', level: 'work',
    states: ['pending_draft', 'changes', 'submitted'],
    clientOf: async (a, id) => { const r = await one(a.from('campaign_options').select('state, campaigns(client_id)').eq('id', id).maybeSingle());
      const c = r && (r.campaigns as Record<string, unknown> | null);
      return c ? { client: String(c.client_id), state: String(r!.state) } : null; } },
  // A campaign's invoice PDF, private once the bucket is set up for it.
  invoice: { field: 'campaignId', sections: ['campaigns.finance'], kind: 'campaign', level: 'work', private: 'may',
    clientOf: async (a, id) => { const r = await one(a.from('campaigns').select('client_id').eq('id', id).maybeSingle());
      return r ? { client: String(r.client_id) } : null; } },
  // A published report version's PDF, kept as it went out, kept private.
  report: { field: 'versionId', sections: ['reports'], kind: 'report', level: 'view', private: 'must',
    clientOf: async (a, id) => { const r = await one(a.from('sm_report_versions').select('report_id, sm_reports(client_id)').eq('id', id).maybeSingle());
      const c = r && (r.sm_reports as Record<string, unknown> | null);
      return c ? { client: String(c.client_id) } : null; } }
};
const MAX_BYTES = 2 * 1024 * 1024 * 1024;   // 2 GB, a sane ceiling for a review copy

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);

  let body: {
    ext?: string; clientId?: string; size?: number;
    creatorCode?: string; optionId?: string; private?: boolean;
    purpose?: string; batchId?: string; campaignId?: string; versionId?: string;
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
    // A removed colleague may share the address with one added again: the
    // active row answers (Team audit, item 10).
    const { data: member } = await admin.from('team_members')
      .select('active').ilike('email', exactEmail(user.email))
      .order('active', { ascending: false }).limit(1).maybeSingle();
    if (!member || !member.active) return json({ error: 'not_team' }, 403, origin);

    const clientId = String(body.clientId ?? '');
    if (!UUID.test(clientId)) return json({ error: 'bad_client' }, 400, origin);
    /* Every upload names what it is for and the record it belongs to, and
       is signed only for that (audit P1, 2026-10-10): the record exists and
       is the named client's, the caller holds Work in that purpose's own
       section or part, and their client scope reaches the record, each asked
       of the database as the caller. Work elsewhere signs nothing here. A
       page from before sends no purpose and is asked to reload. */
    const purpose = String(body.purpose ?? '');
    const rule = PURPOSES[purpose];
    if (!rule) return json({ error: 'Reload the page to upload.' }, 400, origin);
    const parent = String((body as Record<string, unknown>)[rule.field] ?? '');
    if (!UUID.test(parent)) return json({ error: 'bad_parent' }, 400, origin);
    const owner = await rule.clientOf(admin, parent);
    if (!owner || owner.client !== clientId) return json({ error: 'bad_parent' }, 400, origin);
    if (rule.states && !rule.states.includes(owner.state ?? '')) return json({ error: 'not_waiting' }, 403, origin);
    let mayUpload = false;
    for (const section of rule.sections) {
      const { data: ok } = await supa.rpc('allowed', { p_section: section, p_level: 'work' });
      if (ok === true) { mayUpload = true; break; }
    }
    if (!mayUpload) return json({ error: 'not_allowed' }, 403, origin);
    const { data: inScope, error: scopeErr } = await supa.rpc('client_scope_ok',
      { p_kind: rule.kind, p_id: parent, p_level: rule.level });
    if (scopeErr || inScope !== true) return json({ error: 'not_allowed' }, 403, origin);
    if (body.private === true && !rule.private) return json({ error: 'bad_private' }, 400, origin);
    if (rule.private === 'must' && body.private !== true) return json({ error: 'bad_private' }, 400, origin);
    scope = clientId;
  }

  // 2. Validate what they are asking to upload.
  const ext = String(body.ext ?? '').toLowerCase();
  const size = Number(body.size ?? 0);

  const contentType = Object.prototype.hasOwnProperty.call(EXT_TYPE, ext) ? EXT_TYPE[ext] : '';
  if (!contentType) return json({ error: 'bad_extension' }, 400, origin);
  if (!Number.isSafeInteger(size) || size < 1 || size > MAX_BYTES) return json({ error: 'too_large' }, 400, origin);

  // 3. Sign a PUT for one key we choose. The browser never picks the path.
  const bucket = Deno.env.get('S3_BUCKET')!;
  const region = Deno.env.get('S3_REGION')!;
  const prefix = Deno.env.get('S3_PREFIX') ?? 'content';
  const cdnBase = (Deno.env.get('CDN_BASE') ?? '').replace(/\/+$/, '');

  /* A private file (a campaign's invoice PDF, 2026-10-02) goes under
     `private/`, which CloudFront does not serve: it is opened only through a
     five-minute link from sign-download. Only the console asks for one, and
     only for a PDF. */
  const priv = body.private === true;
  if (priv && (creatorCode || ext !== 'pdf')) return json({ error: 'bad_private' }, 400, origin);
  const key = priv
    ? `private/${scope}/${crypto.randomUUID()}.pdf`
    : `${prefix}/${scope}/${crypto.randomUUID()}.${ext}`;
  const target = `https://${bucket}.s3.${region}.amazonaws.com/${key}`;

  const aws = new AwsClient({
    accessKeyId: Deno.env.get('AWS_ACCESS_KEY_ID')!,
    secretAccessKey: Deno.env.get('AWS_SECRET_ACCESS_KEY')!,
    region,
    service: 's3'
  });

  /* The type and the size claimed are signed into the PUT: S3 refuses a
     body of another length or another Content-Type, so the claim is the
     file (audit 2026-10-16, finding 4). The page sends `contentType` back
     exactly; the browser sets the length from the file itself. */
  const signed = await aws.sign(`${target}?X-Amz-Expires=${PUT_EXPIRES}`, {
    method: 'PUT',
    headers: { 'Content-Type': contentType, 'Content-Length': String(size) },
    aws: { signQuery: true, allHeaders: true }
  });

  return json({
    uploadUrl: signed.url,
    publicUrl: priv ? null : `${cdnBase}/${key}`,
    key,
    contentType
  }, 200, origin);
});
