/*
 * s3-sweep — removes from the bucket the files nothing points at any more.
 *
 * Once a day (pg_cron, see docs/S3-STORAGE.md) this lists `content/`, leaves
 * alone anything younger than seven days, asks the database which of the
 * rest are still referenced (`s3_keys_in_use`: any row anywhere, a
 * soft-removed draft for 30 days), and deletes the others. Every run files
 * one row in `s3_sweeps`. The portal's pages never delete from S3; this is
 * the only thing that does.
 *
 * A dry run unless the secret S3_SWEEP_DELETE is exactly "on". Even then a
 * run is held, deleting nothing, when the answer looks wrong (see decide()).
 *
 * Secrets (Supabase → Edge Functions → Secrets; they are project wide, so the
 * sweeper's key has names of its own and sign-upload never reads them):
 *   S3_SWEEP_KEY_ID, S3_SWEEP_SECRET   the sweeper IAM user's access key
 *   S3_SWEEP_TOKEN                     what the scheduled call must carry
 *   S3_SWEEP_DELETE                    "on" to delete; anything else is a dry run
 *   S3_SWEEP_MAX                       optional, the most one run may delete (500)
 *   S3_BUCKET, S3_REGION, S3_PREFIX    shared with sign-upload
 *
 * Deploy:  supabase functions deploy s3-sweep --no-verify-jwt
 * "Verify JWT" OFF: the caller is pg_cron with the sweep's own token, which
 * is not a JWT; the function checks it itself below.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import {
  sign, amzDateOf, parseList, deleteBody, parseDeleteResult, md5, base64,
  plan, judged, decide, report, chunk, sameToken, uriEncode, DEFAULT_MAX
} from './logic.mjs';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  if (!sameToken(auth.replace(/^Bearer\s+/i, ''), Deno.env.get('S3_SWEEP_TOKEN'))) {
    return json({ error: 'not_allowed' }, 403);
  }
  let body: { dryRun?: boolean } = {};
  try { body = await req.json(); } catch { /* an empty body is a normal run */ }

  const bucket = Deno.env.get('S3_BUCKET')!;
  const region = Deno.env.get('S3_REGION')!;
  const prefix = (Deno.env.get('S3_PREFIX') ?? 'content').replace(/\/+$/, '');
  const accessKeyId = Deno.env.get('S3_SWEEP_KEY_ID') ?? '';
  const secretAccessKey = Deno.env.get('S3_SWEEP_SECRET') ?? '';
  const max = Number(Deno.env.get('S3_SWEEP_MAX')) || DEFAULT_MAX;
  const host = `${bucket}.s3.${region}.amazonaws.com`;
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  const file = async (row: Record<string, unknown>) => {
    const { error } = await db.from('s3_sweeps').insert(row);
    return error ? error.message : null;
  };
  const fail = async (note: string) => {
    const filed = await file({ mode: 'failed', prefix, note });
    return json({ ok: false, mode: 'failed', note, filed: !filed, fileError: filed }, 500);
  };
  if (!bucket || !region || !accessKeyId || !secretAccessKey) {
    return fail('missing secret: ' + ['S3_BUCKET', 'S3_REGION', 'S3_SWEEP_KEY_ID', 'S3_SWEEP_SECRET']
      .filter((n) => !Deno.env.get(n)).join(', '));
  }

  const s3 = async (method: string, query: Record<string, string>, payload = '', headers: Record<string, string> = {}) => {
    const s = await sign({ method, host, path: '/', query, headers, body: payload, accessKeyId, secretAccessKey,
      region, service: 's3', amzDate: amzDateOf(new Date()), s3: true });
    const qs = Object.entries(query).map(([k, v]) => uriEncode(k) + '=' + uriEncode(v)).join('&');
    const r = await fetch(`https://${host}/?${qs}`, { method, headers: s.headers, body: payload || undefined });
    const text = await r.text();
    if (!r.ok) throw new Error(`S3 ${method} answered ${r.status}: ${text.slice(0, 300)}`);
    return text;
  };

  // 1. Everything under the prefix, page by page.
  const objects: { key: string; size: number; lastModified: string }[] = [];
  try {
    let token: string | null = null;
    do {
      const q: Record<string, string> = { 'list-type': '2', prefix: prefix + '/', 'max-keys': '1000' };
      if (token) q['continuation-token'] = token;
      const page = parseList(await s3('GET', q));
      objects.push(...page.objects);
      token = page.truncated ? page.next : null;
    } while (token);
  } catch (e) {
    return fail('list: ' + (e as Error).message);
  }

  // 2. Which of the old enough keys are still referenced. A failed answer
  //    deletes nothing.
  const now = new Date();
  const inUse = new Set<string>();
  for (const part of chunk(judged(objects, now, prefix), 500)) {
    const { data, error } = await db.rpc('s3_keys_in_use', { p_keys: part });
    if (error || !Array.isArray(data)) return fail('in-use check: ' + (error?.message ?? 'no answer'));
    data.forEach((k: string) => inUse.add(k));
  }
  const sorted = plan({ objects, inUse, now, prefix });
  const decision = decide({ kept: sorted.kept, orphans: sorted.orphans,
    deleteFlag: Deno.env.get('S3_SWEEP_DELETE'), forceDry: body.dryRun === true, max });

  // 3. The deletes, 500 keys a call.
  const deletedKeys: string[] = [];
  const failures: { key: string; code: string }[] = [];
  let note: string | null = null;
  if (decision.mode === 'delete') {
    for (const part of chunk(sorted.orphans.map((o) => o.key), 500)) {
      const xml = deleteBody(part);
      try {
        const res = parseDeleteResult(await s3('POST', { delete: '' }, xml, {
          'content-md5': base64(md5(xml)), 'content-type': 'application/xml'
        }));
        const bad = new Set(res.errors.map((x) => x.key));
        res.errors.forEach((x) => failures.push({ key: x.key ?? '', code: x.code ?? '' }));
        part.forEach((k) => { if (!bad.has(k)) deletedKeys.push(k); });
      } catch (e) {
        note = 'delete: ' + (e as Error).message;
        part.forEach((k) => failures.push({ key: k, code: 'request' }));
      }
    }
  }

  const row = report({ prefix, sorted, decision, deletedKeys, failures, note });
  const fileError = await file(row);
  return json({ ok: true, ...row, filed: !fileError, fileError });
});
