/*
 * report-thumbs-move — moves a Social Media Report's pictures out of the
 * database once (REPORT PICTURES ON S3, 2026-11-20). A post or ad picture
 * kept as a data URL in `thumb_data` is put on S3 under its report's
 * client's `private/{client}/thumbs/{id}.jpg`, and the row then names the
 * key; each published version's snapshot is rewritten to name the same key
 * where it held the same picture. Nothing is deleted from S3, and a row
 * changed meanwhile (its `thumb_data` no longer the picture read) is left.
 *
 * Asked by hand, never by a page: POST with the header `x-move-token`
 * holding `app_secrets.thumbs_move_token` (set for the run, removed after),
 * compared in constant time. Body: { batch?: number (1 to 100, 50 by
 * default), versions?: true }. Each call moves one batch of rows and
 * answers { moved, failed, left }; once `left` is 0, call with
 * { versions: true } until its `left` is 0, which rewrites ten snapshots a
 * call (`sm_report_thumb_versions`).
 *
 * Deploy with Verify JWT off: the token is its own check. AWS credentials
 * are the upload key's, which writes `private/*` (docs/S3-STORAGE.md §5).
 */
import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const KEY = /^private\/[0-9a-f-]{36}\/thumbs\/[0-9a-f-]{36}\.jpg$/;
const say = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

function same(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}
function bytesOf(dataUrl: string): Uint8Array | null {
  const m = /^data:image\/[a-z+.-]+;base64,(.+)$/i.exec(dataUrl);
  if (!m) return null;
  const bin = atob(m[1]);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return say({ error: 'method_not_allowed' }, 405);
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: tok } = await admin.from('app_secrets').select('value').eq('key', 'thumbs_move_token').maybeSingle();
  const given = req.headers.get('x-move-token') ?? '';
  if (!tok || !tok.value || String(tok.value).length < 24 || !same(given, String(tok.value))) return say({ error: 'not_allowed' }, 403);

  let body: { batch?: number; versions?: boolean } = {};
  try { body = await req.json(); } catch { /* defaults */ }

  const aws = new AwsClient({
    accessKeyId: Deno.env.get('AWS_ACCESS_KEY_ID')!,
    secretAccessKey: Deno.env.get('AWS_SECRET_ACCESS_KEY')!,
    region: Deno.env.get('S3_REGION')!,
    service: 's3'
  });
  const bucket = `https://${Deno.env.get('S3_BUCKET')!}.s3.${Deno.env.get('S3_REGION')!}.amazonaws.com`;

  if (body.versions) {
    /* Each snapshot still holding a data URL takes the key of the row it
       came from (by id); a picture no row holds any more (a row removed
       since) is put on S3 itself, once a snapshot for the same picture. */
    const { data: list, error } = await admin.rpc('sm_report_thumb_versions', { p_limit: 10 });
    if (error || !list) return say({ error: 'read_failed', detail: error && error.message }, 500);
    let rewritten = 0, failed = 0;
    /* Why a snapshot was not rewritten, by reason (review 2026-11-24: one
       whose report has no client was answered every call, so `left` never
       reached 0); the database skips those and counts them as `stuck`. */
    const why: Record<string, number> = {};
    const miss = (k: string) => { failed++; why[k] = (why[k] || 0) + 1; };
    for (const id of (list.ids || []) as string[]) {
      const { data: v } = await admin.from('sm_report_versions').select('id, report_id, snapshot, sm_reports(client_id)').eq('id', id).maybeSingle();
      if (!v) { miss('not-found'); continue; }
      const client = String(((v.sm_reports as Record<string, unknown> | null) || {}).client_id || '');
      if (!/^[0-9a-f-]{36}$/.test(client)) { miss('no-client'); continue; }
      const snap = v.snapshot as Record<string, unknown>;
      const [{ data: ps }, { data: as }] = await Promise.all([
        admin.from('sm_report_posts').select('id, thumb_data').eq('report_id', v.report_id),
        admin.from('sm_report_ads').select('id, thumb_data').eq('report_id', v.report_id)
      ]);
      const byId: Record<string, string> = {};
      for (const r of [...(ps || []), ...(as || [])]) if (r.thumb_data && KEY.test(r.thumb_data)) byId[r.id] = r.thumb_data;
      const byData: Record<string, string> = {};
      let ok = true;
      for (const part of ['posts', 'ads']) {
        for (const r of ((snap[part] as Record<string, unknown>[]) || [])) {
          const u = r && typeof r.thumb_url === 'string' ? r.thumb_url as string : '';
          if (!u.startsWith('data:image/')) continue;
          let k = byId[String(r.id)] || byData[u];
          if (!k) {
            const bytes = bytesOf(u);
            if (!bytes) { ok = false; continue; }
            k = `private/${client}/thumbs/${crypto.randomUUID()}.jpg`;
            const put = await aws.fetch(`${bucket}/${k}`, { method: 'PUT', body: bytes, headers: { 'Content-Type': 'image/jpeg' } });
            if (!put.ok) { ok = false; continue; }
          }
          byData[u] = k;
          r.thumb_url = k;
        }
      }
      const { error: ue } = await admin.from('sm_report_versions').update({ snapshot: snap }).eq('id', v.id);
      if (ue) miss('write-failed'); else if (!ok) miss('picture-failed'); else rewritten++;
    }
    const { data: after } = await admin.rpc('sm_report_thumb_versions', { p_limit: 1 });
    return say({ rewritten, failed, why, left: after ? after.left : null, stuck: after ? after.stuck : null });
  }

  const n = Math.min(100, Math.max(1, Number(body.batch) || 50));
  let moved = 0, failed = 0;
  /* Why a row was not moved, counted by reason, so a failed run says so. */
  const why: Record<string, number> = {};
  const miss = (k: string) => { failed++; why[k] = (why[k] || 0) + 1; };
  for (const table of ['sm_report_posts', 'sm_report_ads']) {
    if (moved + failed >= n) break;
    const { data: rows, error } = await admin.from(table).select('id, report_id, thumb_data, sm_reports(client_id)')
      .like('thumb_data', 'data:image/%').limit(n - moved - failed);
    if (error) return say({ error: 'read_failed', detail: error.message }, 500);
    for (const r of rows || []) {
      const client = String(((r.sm_reports as Record<string, unknown> | null) || {}).client_id || '');
      const bytes = bytesOf(String(r.thumb_data));
      if (!/^[0-9a-f-]{36}$/.test(client)) { miss('no_client'); continue; }
      if (!bytes) { miss('not_a_picture'); continue; }
      const key = `private/${client}/thumbs/${crypto.randomUUID()}.jpg`;
      const put = await aws.fetch(`${bucket}/${key}`, { method: 'PUT', body: bytes, headers: { 'Content-Type': 'image/jpeg' } });
      if (!put.ok) { miss('s3_' + put.status); continue; }
      /* A published report's rows are held by its guard; the database's
         own function makes this one swap (A REPORT PICTURE MOVED TO S3). */
      const { data: done, error: ue } = await admin.rpc('sm_report_thumb_set',
        { p_kind: table === 'sm_report_posts' ? 'post' : 'ad', p_id: r.id, p_key: key });
      if (ue) miss('update_' + (ue.code || 'error')); else if (done === true) moved++; else miss('changed_meanwhile');
    }
  }
  const [{ count: lp }, { count: la }] = await Promise.all([
    admin.from('sm_report_posts').select('id', { count: 'exact', head: true }).like('thumb_data', 'data:image/%'),
    admin.from('sm_report_ads').select('id', { count: 'exact', head: true }).like('thumb_data', 'data:image/%')
  ]);
  return say({ moved, failed, why, left: (lp ?? 0) + (la ?? 0) });
});
