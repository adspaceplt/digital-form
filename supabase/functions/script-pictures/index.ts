/*
 * script-pictures — draws a frame for scenes of a video script: a line
 * drawing written by Claude (2026-11-06; the user: "Claude couldnt draw but
 * able to generate motions n clips right why not do that replace gemini",
 * the sample approved as a draft; it replaced Gemini's picture of
 * 2026-11-05).
 *
 * Draw with AI on a script's Scenes (js/scripts.js) posts the script's id and
 * the scenes to draw. The function reads the script, its scenes and its
 * client as the caller (Video Scripts at Work, the client in scope), counts
 * one picture a scene before Claude is asked (`ai_picture_claim`), and asks
 * for each scene one storyboard frame at the script's aspect ratio from what
 * the scene says: its shot size, angle and camera move (chosen by Claude
 * where the scene names none), what is seen, the setting and the cast's
 * roles. Never the client's name, a handle, a contact or a cast member's
 * name: the client's name and handles in the words read as "the brand".
 *
 * Claude answers by structured output: the shot it drew, the camera's move
 * from a fixed list, and the drawing as shapes, each a path of path commands
 * and numbers and a tone. Nothing is ever kept or drawn as markup: the frame
 * is kept as that data by `video_script_frame` (which checks it again) and
 * the page builds the drawing from it. A frame kept is answered with its
 * scene; one that did not come back is marked failed and not counted.
 *
 * `note` (every scene asked) and `notes` (one a scene, from Redraw) carry the
 * team's changes, 500 characters each, masked as the rest; a scene already
 * drawn is sent with its drawing and revised from it, so the storyboard goes
 * round by round until it is right (2026-11-07). The answer names the press
 * each frame was kept under (`presses`), which the page's Undo writes the
 * earlier drawing back with.
 *
 * `{ ping: true }` answers whether the function is set up, counting nothing,
 * so the page draws Draw with AI only where it can work.
 *
 * Frames are drawn four at a time, inside 130 seconds; a scene the time
 * leaves out is not counted. The answer is streamed, a space every few
 * seconds holding the connection open.
 *
 * Secrets: ANTHROPIC_API_KEY, and FRAME_MODEL (the model id; unset, it is
 *          claude-opus-5-5), plus the platform's SUPABASE_URL and
 *          SUPABASE_ANON_KEY. Verify JWT off: the caller is asked here.
 */
import Anthropic from 'npm:@anthropic-ai/sdk';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json } from '../_shared/cors.ts';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
const text = (v: unknown, n: number) => String(v ?? '').replace(/\r/g, '').trim().slice(0, n);
const escRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const ASPECTS: Record<string, [number, number]> = { '9:16': [180, 320], '1:1': [240, 240], '16:9': [320, 180] };
const MOVES = ['static', 'push in', 'pull out', 'pan left', 'pan right', 'tilt up', 'tilt down'];
const TONES = ['ink', 'light', 'fill', 'paper'];
const PATH = /^[MmLlHhVvCcSsQqTtAaZz0-9 .,eE+-]{2,4000}$/;
const BUDGET_MS = 130000;

const SYSTEM = `You draw storyboard frames for short social media videos made in Malaysia and Singapore, the way a storyboard artist sketches them: clean black line drawings on white paper.
You draw with shapes alone. Each shape is one SVG path: its "d" holds path commands (M, L, H, V, C, S, Q, T, A, Z, upper or lower case) and numbers only, and its tone is one of:
- ink: the main lines, people, furniture, objects (a 1.6 unit stroke, no fill);
- light: secondary lines, background detail, light rays, horizon, hatching (a thin grey stroke);
- fill: a soft grey shape for shadow, a screen, food or cloth (filled, no stroke);
- paper: a white shape with an ink edge, for something that sits in front of what is behind it.
Rules:
- The frame is the viewBox given; keep everything inside it, with a margin.
- Draw people as simple figures: a circle head, a body shape, simple arms and legs, no faces, no fingers, never a real or famous person. Draw what the scene says they do.
- Compose for the shot: a wide shows the whole place and small figures; a medium shows people from the waist; a close-up fills the frame with the subject; an over-the-shoulder puts a back in the foreground. Use the angle (low, high, eye level, overhead) for where the horizon and floor sit.
- Show the setting with a few telling objects (a window, a bed, a counter, a car), never a cluttered room.
- No words, letters, numbers, logos or signs anywhere.
- 20 to 80 shapes; keep the lines simple and the same style for every frame.
- Draw paper shapes before the ink lines that sit on them, background before foreground.
- Choose the camera's move from the list; where the scene names one, use the nearest. Where the scene names no shot size or angle, choose what suits it and say so.`;

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
  const key = secret('ANTHROPIC_API_KEY');
  const model = secret('FRAME_MODEL') || 'claude-opus-5-5';
  const started = Date.now();
  const body = await req.json().catch(() => ({}));
  if (body && body.ping) return json({ ready: Boolean(key) }, 200, origin);
  if (!key) return json({ error: 'ai-not-set-up', missing: ['ANTHROPIC_API_KEY'] }, 200, origin);

  const scriptId = String(body && body.script_id || '');
  if (!/^[0-9a-f-]{36}$/i.test(scriptId)) return json({ error: 'bad-request' }, 400, origin);
  const want = (Array.isArray(body && body.scenes) ? body.scenes : []).map(String).filter((x: string) => /^[0-9a-f-]{36}$/i.test(x)).slice(0, 30);
  if (!want.length) return json({ error: 'bad-request' }, 400, origin);
  /* The team's changes (2026-11-07; the user: rounds of changes until the
     storyboard is right): one note for every scene asked, and one a scene
     from Redraw. A scene already drawn is revised from its drawing. */
  const note = text(body && body.note, 500);
  const notes: Record<string, string> = {};
  const given = body && body.notes && typeof body.notes === 'object' ? body.notes as Record<string, unknown> : {};
  want.forEach((id: string) => { const n = text(given[id], 500); if (n) notes[id] = n; });

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
  const scs = await db.from('video_script_scenes').select('id, position, visual, line, shot_size, angle, camera_move, ai_frame')
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
  const aspect = ASPECTS[String(vs.data.aspect || '')] ? String(vs.data.aspect) : '9:16';
  const [W, H] = ASPECTS[aspect];
  const setting = mask(text(plan.locations, 300));
  const cast = mask(text(plan.cast, 300));
  const props = mask(text(plan.props, 300));
  const industry = text(c.industry, 60);

  const claim = await db.rpc('ai_picture_claim', { p_script: scriptId, p_count: scenes.length });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const ids = (Array.isArray(got.ids) ? got.ids : []) as string[];

  const promptOf = (sc: Record<string, unknown>) => [
    'Frame: viewBox 0 0 ' + W + ' ' + H + ' (' + aspect + ').',
    industry ? 'The business is in ' + industry + '.' : '',
    setting ? 'Locations: ' + setting : '',
    cast ? 'Cast roles: ' + cast : '',
    props ? 'Props: ' + props : '',
    'Scene ' + sc.position + '.',
    'Shot size: ' + (text(sc.shot_size, 60) || 'not set') + '. Angle: ' + (text(sc.angle, 60) || 'not set') + '. Camera move: ' + (text(sc.camera_move, 60) || 'not set') + '.',
    'What is seen: ' + mask(text(sc.visual, 900)),
    text(sc.line, 1) ? 'What is said: ' + mask(text(sc.line, 600)) : '',
    ...revision(sc)
  ].filter(Boolean).join('\n');
  function revision(sc: Record<string, unknown>): string[] {
    const asked = [notes[String(sc.id)], note].filter(Boolean).map((x) => mask(String(x)));
    if (!asked.length) return [];
    const was = sc.ai_frame && typeof sc.ai_frame === 'object' ? sc.ai_frame as Record<string, unknown> : null;
    const shapes = was && Array.isArray(was.shapes) ? JSON.stringify({ shot_size: was.shot_size, angle: was.angle, move: was.move, shapes: was.shapes }).slice(0, 30000) : '';
    return [
      shapes ? 'The current drawing of this scene: ' + shapes : '',
      shapes ? 'Redraw it with the changes the team asks for. Keep what they do not ask to change.' : 'Draw it with the changes the team asks for.',
      'Changes asked: ' + asked.join(' ')
    ].filter(Boolean);
  }

  const format = {
    type: 'object',
    properties: {
      shot_size: { type: 'string', description: 'The shot size drawn, two or three words' },
      angle: { type: 'string', description: 'The camera angle drawn, two or three words' },
      move: { type: 'string', enum: MOVES },
      shapes: { type: 'array', items: { type: 'object', properties: {
        d: { type: 'string', description: 'SVG path data: commands and numbers only' },
        t: { type: 'string', enum: TONES }
      }, required: ['d', 't'], additionalProperties: false } }
    },
    required: ['shot_size', 'angle', 'move', 'shapes'], additionalProperties: false
  };

  const done = (id: string, ok: boolean) => db.rpc('ai_draft_done', { p_id: id, p_ok: ok }).then(() => null, () => null);
  const kept = (id: string, i: number, o: number) => db.rpc('ai_draft_tokens', { p_id: id, p_in: i, p_out: o, p_model: model }).then(() => null, () => null);

  return held((async () => {
    const client = new Anthropic({ apiKey: key });
    const out: string[] = [];
    const presses: Record<string, string> = {};
    let refused = '';
    const one = async (sc: Record<string, unknown>, press: string) => {
      const left = BUDGET_MS - (Date.now() - started);
      if (left < 20000) { await done(press, false); return; }
      try {
        const res = await client.messages.create({
          model, max_tokens: 12000,
          system: [{ type: 'text', text: SYSTEM, cache_control: { type: 'ephemeral' } }],
          output_config: { effort: 'low', format: { type: 'json_schema', schema: format } },
          messages: [{ role: 'user', content: promptOf(sc) }]
        } as Anthropic.MessageCreateParamsNonStreaming, { timeout: Math.max(10000, left - 5000) });
        const u = (res.usage || {}) as unknown as Record<string, number | null | undefined>;
        await kept(press, (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0), u.output_tokens || 0);
        if (res.stop_reason === 'refusal' || res.stop_reason === 'max_tokens') { await done(press, false); return; }
        const said = res.content.filter((b) => b.type === 'text').map((b) => b.type === 'text' ? b.text : '').join('');
        // deno-lint-ignore no-explicit-any
        let f: any = null;
        try { f = JSON.parse(said); } catch { f = null; }
        // deno-lint-ignore no-explicit-any
        const shapes = (f && Array.isArray(f.shapes) ? f.shapes : []).filter((x: any) => x && PATH.test(String(x.d || '')) && TONES.includes(String(x.t)))
          // deno-lint-ignore no-explicit-any
          .slice(0, 160).map((x: any) => ({ d: String(x.d), t: String(x.t) }));
        if (shapes.length < 3) { await done(press, false); return; }
        const frame = { shot_size: text(f.shot_size, 60), angle: text(f.angle, 60), move: MOVES.includes(String(f.move)) ? String(f.move) : 'static', shapes };
        const saved = await db.rpc('video_script_frame', { p_script: scriptId, p_scene: sc.id, p_frame: frame, p_press: press });
        if (saved.error || !saved.data || saved.data.error) {
          console.error('script-pictures: not kept', JSON.stringify(saved.error || saved.data));
          await done(press, false);
          return;
        }
        await done(press, true);
        out.push(String(sc.id));
        presses[String(sc.id)] = press;
      } catch (e) {
        const st = Number((e as { status?: number })?.status || 0);
        console.error('script-pictures: no answer', st, String((e as Error)?.message || e).slice(0, 300));
        refused = st === 401 || st === 403 ? 'ai-key' : st === 404 ? 'ai-model' : st === 429 || st === 529 ? 'ai-busy' : refused;
        await done(press, false);
      }
    };
    /* Four at a time. */
    for (let i = 0; i < scenes.length; i += 4) {
      await Promise.all(scenes.slice(i, i + 4).map((sc, k) => one(sc, ids[i + k])));
    }
    if (!out.length) return { error: refused || 'ai-incomplete' };
    return { drawn: out, presses, missed: scenes.length - out.length, left: got.left };
  })(), origin);
});
