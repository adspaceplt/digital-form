/*
 * script-pictures — draws a picture for scenes of a video script with
 * Google's Gemini image model (2026-11-05; the user: the drawn frame, an AI
 * picture and the team's own photo, the AI pictures "together with … AI
 * usages"; Gemini Flash; the team's alone).
 *
 * Draw with AI on a script's Scenes (js/scripts.js) posts the script's id and
 * the scenes to draw. The function reads the script, its scenes and its
 * client as the caller (Video Scripts at Work, the client in scope), counts
 * one picture a scene before Gemini is asked (`ai_picture_claim`), and asks
 * for each scene one storyboard sketch at the script's aspect ratio from what
 * the scene says: its shot size, angle and camera move, what is seen, the
 * setting and the cast's roles. Never the client's name, a handle, a contact
 * or a cast member's name: the client's name and handles in the words read
 * as "the brand". A picture that comes back is answered as base64 with the
 * press it was counted under; one that does not is marked failed and not
 * counted. The page stores each picture in the client's folder and keeps it
 * on its scene (`video_script_picture`, kind `ai`).
 *
 * `{ ping: true }` answers whether the function is set up, counting nothing,
 * so the page draws Draw with AI only where it can work.
 *
 * Pictures are drawn three at a time, inside 130 seconds; a scene the time
 * leaves out is not counted. The answer is streamed, a space every few
 * seconds holding the connection open.
 *
 * Secrets: GEMINI_API_KEY (Google AI Studio, a project with billing on: the
 *          image models have no free tier), GEMINI_IMAGE_MODEL (unset,
 *          gemini-3.1-flash-image-preview), plus the platform's SUPABASE_URL
 *          and SUPABASE_ANON_KEY. Verify JWT off: the caller is asked here.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json } from '../_shared/cors.ts';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
const text = (v: unknown, n: number) => String(v ?? '').replace(/\r/g, '').trim().slice(0, n);
const escRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const ASPECTS = ['9:16', '1:1', '16:9'];
const BUDGET_MS = 130000;

function held(work: Promise<unknown>, origin: string | null) {
  const enc = new TextEncoder();
  const stream = new ReadableStream({
    start(ctl) {
      const tick = setInterval(() => { try { ctl.enqueue(enc.encode(' ')); } catch { /* closed */ } }, 8000);
      work.then((body) => body, (e) => { console.error('script-pictures: failed', String((e as Error)?.message || e)); return { error: 'ai-failed' }; })
        .then((body) => { clearInterval(tick); ctl.enqueue(enc.encode(JSON.stringify(body))); ctl.close(); });
    }
  });
  return new Response(stream, { status: 200, headers: { 'Content-Type': 'application/json', ...cors(origin) } });
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  const key = secret('GEMINI_API_KEY');
  const model = secret('GEMINI_IMAGE_MODEL') || 'gemini-3.1-flash-image-preview';
  const started = Date.now();
  const body = await req.json().catch(() => ({}));
  if (body && body.ping) return json({ ready: Boolean(key) }, 200, origin);
  if (!key) return json({ error: 'ai-not-set-up', missing: ['GEMINI_API_KEY'] }, 200, origin);

  const scriptId = String(body && body.script_id || '');
  if (!/^[0-9a-f-]{36}$/i.test(scriptId)) return json({ error: 'bad-request' }, 400, origin);
  const want = (Array.isArray(body && body.scenes) ? body.scenes : []).map(String).filter((x: string) => /^[0-9a-f-]{36}$/i.test(x)).slice(0, 30);
  if (!want.length) return json({ error: 'bad-request' }, 400, origin);

  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });
  const may = await db.rpc('allowed', { p_section: 'scripts', p_level: 'work' });
  if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);

  const vs = await db.from('video_scripts').select('id, client_id, aspect, plan').eq('id', scriptId).maybeSingle();
  if (vs.error || !vs.data) return json({ error: 'not-found' }, 200, origin);
  const cl = await db.from('clients').select('name, industry, handle_ig, handle_fb, handle_tiktok, handle_xhs')
    .eq('id', vs.data.client_id as string).maybeSingle();
  if (cl.error || !cl.data) return json({ error: 'client-scope' }, 200, origin);
  const scs = await db.from('video_script_scenes').select('id, position, visual, shot_size, angle, camera_move')
    .eq('script_id', scriptId).in('id', want).order('position');
  if (scs.error) return json({ error: 'not-found' }, 200, origin);
  const scenes = (scs.data || []) as Record<string, unknown>[];
  if (!scenes.length) return json({ error: 'not-found' }, 200, origin);

  /* The client's name and handles never leave. */
  const c = cl.data as Record<string, unknown>;
  const names = [String(c.name || ''), ...['handle_ig', 'handle_fb', 'handle_tiktok', 'handle_xhs'].map((k) => String(c[k] || '').replace(/^@/, ''))]
    .map((x) => x.trim()).filter((x) => x.length > 1).sort((a, b) => b.length - a.length);
  const mask = (s: string) => names.reduce((t, n) => t.replace(new RegExp('@?' + escRe(n), 'gi'), 'the brand'), s);
  const plan = (vs.data.plan && typeof vs.data.plan === 'object' ? vs.data.plan : {}) as Record<string, unknown>;
  const aspect = ASPECTS.includes(String(vs.data.aspect || '')) ? String(vs.data.aspect) : '9:16';
  const setting = mask(text(plan.locations, 300));
  const cast = mask(text(plan.cast, 300));
  const industry = text(c.industry, 60);

  const claim = await db.rpc('ai_picture_claim', { p_script: scriptId, p_count: scenes.length });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const ids = (Array.isArray(got.ids) ? got.ids : []) as string[];

  /* One storyboard sketch: a line drawing, so a set of frames reads as one
     storyboard, never a photograph of a real person or a product. */
  const promptOf = (sc: Record<string, unknown>) => [
    'A storyboard frame for a short social media video shoot in Malaysia.',
    'Style: a loose pencil sketch in black and grey line work on white paper, simple shading, the same style for every frame of this storyboard.',
    'No words, letters, captions, logos or watermarks in the picture. Draw people as simple sketched figures, never a real or famous person.',
    'Shot size: ' + (text(sc.shot_size, 60) || 'medium') + '. Camera angle: ' + (text(sc.angle, 60) || 'eye level') + '.' +
      (text(sc.camera_move, 60) ? ' Camera move (show it with a small arrow at the frame\'s edge): ' + text(sc.camera_move, 60) + '.' : ''),
    'What is seen: ' + mask(text(sc.visual, 900)),
    setting ? 'Setting: ' + setting : '',
    cast ? 'Cast roles: ' + cast : '',
    industry ? 'The business is in ' + industry + '.' : ''
  ].filter(Boolean).join('\n');

  const done = (id: string, ok: boolean) => db.rpc('ai_draft_done', { p_id: id, p_ok: ok }).then(() => null, () => null);
  const kept = (id: string) => db.rpc('ai_draft_tokens', { p_id: id, p_in: 0, p_out: 0, p_model: model }).then(() => null, () => null);

  return held((async () => {
    const out: Record<string, unknown>[] = [];
    let refused = '';
    const one = async (sc: Record<string, unknown>, press: string) => {
      const left = BUDGET_MS - (Date.now() - started);
      if (left < 15000) { await done(press, false); return; }
      try {
        const res = await fetch('https://generativelanguage.googleapis.com/v1beta/models/' + encodeURIComponent(model) + ':generateContent', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
          signal: AbortSignal.timeout(Math.min(left - 5000, 90000)),
          body: JSON.stringify({
            contents: [{ role: 'user', parts: [{ text: promptOf(sc) }] }],
            generationConfig: { responseModalities: ['IMAGE'], imageConfig: { aspectRatio: aspect, imageSize: '1K' } }
          })
        });
        if (!res.ok) {
          const t = await res.text().catch(() => '');
          console.error('script-pictures: Gemini refused', res.status, t.slice(0, 300));
          refused = res.status === 401 || res.status === 403 ? 'ai-key' : res.status === 404 ? 'ai-model'
            : res.status === 429 ? (/billing|free.?tier|quota/i.test(t) ? 'ai-billing' : 'ai-busy') : 'ai-failed';
          await done(press, false);
          return;
        }
        // deno-lint-ignore no-explicit-any
        const j: any = await res.json();
        // deno-lint-ignore no-explicit-any
        const parts: any[] = (((j.candidates || [])[0] || {}).content || {}).parts || [];
        const img = parts.find((p) => p && p.inlineData && /^image\//.test(String(p.inlineData.mimeType || '')));
        if (!img) { await done(press, false); return; }
        await kept(press);
        await done(press, true);
        out.push({ scene: sc.id, press, mime: String(img.inlineData.mimeType), data: String(img.inlineData.data) });
      } catch (e) {
        console.error('script-pictures: no answer', String((e as Error)?.message || e));
        await done(press, false);
      }
    };
    /* Three at a time. */
    for (let i = 0; i < scenes.length; i += 3) {
      await Promise.all(scenes.slice(i, i + 3).map((sc, k) => one(sc, ids[i + k])));
    }
    if (!out.length) return { error: refused || 'ai-incomplete' };
    return { pictures: out, missed: scenes.length - out.length, left: got.left };
  })(), origin);
});
