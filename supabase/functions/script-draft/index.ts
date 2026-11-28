/*
 * script-draft — writes a video's script for Video Scripts (2026-10-09),
 * then has it read cold by a reviewer before the colleague sees it
 * (2026-11-05, the Video Script Generator spec: two calls, a writer and a
 * fresh reviewer, one rewrite on a failed review).
 *
 * Write with AI in the script's editor (js/scripts.js) posts the video's
 * id, the type of script, the facts the editor holds (title, platform,
 * language, aspect ratio, length, venue, the cast's count), the script's
 * brief (offer, objective, audience, key message, call to action, must
 * include, must avoid, tone, format and the shoot's limits: locations,
 * cast, shoot hours), the colleague's notes and whatever script the editor
 * already holds. The function reads the video and its client as the caller,
 * under the caller's own access (Video Scripts at Work, a client the
 * colleague works on), and sends Claude only what a script needs. Never a
 * cast member's name, a contact or the client's name: the name reads
 * {brand} and a handle {handle} wherever the team's words carry them, and
 * the page fills both back in.
 *
 * 1. The writer drafts the script as a shot table: each scene's timing, shot
 *    size, angle, camera move, what is seen, the words said, on-screen text
 *    and sound; with the core message, the concept, the hook, the cast's
 *    roles, the locations, the props, the music mood, the call to action and
 *    the facts the brief is missing (open questions).
 * 2. A fresh call reads it with the brief alone (never the writer's
 *    reasoning) and returns every problem with its shot, a fix, its severity
 *    and how sure it is, and a verdict: PASS only with no critical problem.
 * 3. On FAIL the writer gets the problems once and returns the whole script
 *    again, which the reviewer reads again; still FAIL, it is flagged for the
 *    colleague. Each review is answered with the script, the first one kept
 *    where there was a rewrite, so the colleague sees what was flagged and
 *    what was fixed.
 *
 * Every press is counted by the database before Claude is asked
 * (`ai_script_claim`: the colleague's scripts a day), marked done or failed
 * after (`ai_draft_done`), and what its calls cost is kept on its row once
 * (`ai_draft_tokens`, every call added up). Nothing is saved here: the page
 * puts the words in the editor and the script's own Save keeps them, with
 * the review.
 *
 * The answer can take two minutes, so it is streamed: a space every few
 * seconds holds the connection open, then the JSON (140 seconds at most;
 * the rewrite is left out where the time would run past it).
 *
 * Secrets: ANTHROPIC_API_KEY, and SCRIPT_MODEL (the model id; unset, it is
 *          claude-opus-5-5), set in the Supabase dashboard, plus the
 *          platform's SUPABASE_URL and SUPABASE_ANON_KEY.
 *
 * A refusal the person can act on answers 200 with { error }, so the page
 * names it; a non-2xx is kept for a malformed request.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import Anthropic from 'npm:@anthropic-ai/sdk@1.10.0';
import { cors, json } from '../_shared/cors.ts';
import { prompts, promptRefusal } from '../_shared/prompts.ts';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }

/* The kinds, platforms and languages the editor offers (js/scripts.js). */
const KIND: Record<string, string> = {
  scenes: 'Detailed scenes', products: 'Products and scenes', story: 'Story and voice-over'
};
const PLATFORMS = ['Instagram', 'TikTok', 'Facebook', 'rednote', 'YouTube'];
const LANGS = ['English', 'Chinese', 'Malay', 'English and Chinese'];
const LENGTHS = [15, 30, 60, 120];
const ASPECTS = ['9:16', '1:1', '16:9'];
const OBJECTIVE: Record<string, string> = {
  awareness: 'Awareness', traffic: 'Traffic', leads: 'Leads', sales: 'Sales', app_install: 'App install'
};
const FORMAT: Record<string, string> = {
  talking_head: 'Talking head', skit: 'Skit', ugc: 'UGC style', demo: 'Product demo',
  testimonial: 'Testimonial', montage: 'Voiceover montage'
};
const BUDGET_MS = 140000;

/* The house style (the user's own copy standards, 2026-10-08, written for
   video) with the Video Script Generator's rules (the user, 2026-11-05).
   The examples are invented; no client's words are here. */
const SYSTEM = 'ai.script-draft.system';

/* XHS Safe Mode: only when the colleague ticks it (the user's rule: apply
   it only once confirmed). */
const SAFE = 'ai.script-draft.safe';

/* The reviewer: a fresh reader with the brief and the script alone. */
const REVIEW = 'ai.script-draft.review';

/* What a press cost, every call added up, kept on its own row once. */
type Use = { input: number; output: number; model: string | null };
function add(u: Use, res: Anthropic.Message) {
  const x = (res && res.usage || {}) as unknown as Record<string, number | null | undefined>;
  u.input += (x.input_tokens || 0) + (x.cache_creation_input_tokens || 0) + (x.cache_read_input_tokens || 0);
  u.output += x.output_tokens || 0;
  u.model = res.model || u.model;
}
// deno-lint-ignore no-explicit-any
function keepTokens(db: any, id: string, u: Use): Promise<null> {
  if (!u.input && !u.output) return Promise.resolve(null);
  return db.rpc('ai_draft_tokens', { p_id: id, p_in: u.input, p_out: u.output, p_model: u.model })
    .then(() => null, () => null);
}

/* The answer once it is ready, the connection held open by a space every
   few seconds meanwhile (JSON allows leading whitespace). */
function held(work: Promise<unknown>, origin: string | null) {
  const enc = new TextEncoder();
  const stream = new ReadableStream({
    start(ctl) {
      const tick = setInterval(() => { try { ctl.enqueue(enc.encode(' ')); } catch { /* closed */ } }, 8000);
      work.then((body) => body, (e) => { console.error('script-draft: failed', String((e as Error)?.message || e)); return { error: 'ai-failed' }; })
        .then((body) => { clearInterval(tick); ctl.enqueue(enc.encode(JSON.stringify(body))); ctl.close(); });
    }
  });
  return new Response(stream, { status: 200, headers: { 'Content-Type': 'application/json', ...cors(origin) } });
}

const escRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const text = (v: unknown, n: number) => String(v ?? '').replace(/\r/g, '').trim().slice(0, n);
const secs = (v: unknown) => { const n = Math.round(Number(v)); return Number.isFinite(n) && n >= 0 && n <= 600 ? n : null; };

/* The brief as the editor holds it, held to its keys. */
// deno-lint-ignore no-explicit-any
function briefOf(b: any): Record<string, string | number> {
  const out: Record<string, string | number> = {};
  if (!b || typeof b !== 'object') return out;
  for (const k of ['offer', 'audience', 'key_message', 'cta', 'must_include', 'must_avoid', 'tone']) {
    const v = text(b[k], 500);
    if (v) out[k] = v;
  }
  if (OBJECTIVE[String(b.objective || '')]) out.objective = String(b.objective);
  if (FORMAT[String(b.format || '')]) out.format = String(b.format);
  const lim: Record<string, number> = { max_locations: 10, max_cast: 50, max_shoot_hours: 24 };
  for (const k of Object.keys(lim)) {
    const n = Math.floor(Number(b[k]));
    if (Number.isFinite(n) && n >= 1 && n <= lim[k]) out[k] = n;
  }
  return out;
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);

  if (!secret('ANTHROPIC_API_KEY')) return json({ error: 'ai-not-set-up', missing: ['ANTHROPIC_API_KEY'] }, 200, origin);
  const model = secret('SCRIPT_MODEL') || 'claude-opus-5-5';
  const started = Date.now();

  const body = await req.json().catch(() => ({}));
  const scriptId = String(body && body.script_id || '');
  if (!/^[0-9a-f-]{36}$/i.test(scriptId)) return json({ error: 'bad-request' }, 400, origin);
  const kind = KIND[String(body && body.kind || '')] ? String(body.kind) : 'scenes';
  const platform = PLATFORMS.includes(String(body && body.platform || '')) ? String(body.platform) : 'Instagram';
  const language = LANGS.includes(String(body && body.language || '')) ? String(body.language) : 'English';
  const seconds = LENGTHS.includes(Number(body && body.length)) ? Number(body.length) : 30;
  const aspect = ASPECTS.includes(String(body && body.aspect || '')) ? String(body.aspect)
    : (platform === 'Facebook' ? '1:1' : '9:16');
  const safe = platform === 'rednote' && !!(body && body.safe);
  const notes = text(body && body.notes, 3000);
  const title = text(body && body.title, 200);
  const venue = text(body && body.venue, 200);
  const cast = Math.max(0, Math.min(20, Math.floor(Number(body && body.cast) || 0)));
  const brief0 = briefOf(body && body.brief);
  // deno-lint-ignore no-explicit-any
  const now: any = body && typeof body.current === 'object' && body.current ? body.current : {};

  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });

  const may = await db.rpc('allowed', { p_section: 'scripts', p_level: 'work' });
  if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);
  /* Its prompts from the template store, before a press is counted. */
  let P: Record<string, string>;
  try { P = await prompts(db, [SYSTEM, SAFE, REVIEW]); }
  catch (e) { const no = promptRefusal(e); if (no) return json(no, 200, origin); throw e; }

  const vid = await db.from('video_scripts').select('id, client_id, period').eq('id', scriptId).maybeSingle();
  if (vid.error || !vid.data) return json({ error: 'not-found' }, 200, origin);
  const cl = await db.from('clients')
    .select('name, industry, market, handle_ig, handle_fb, handle_tiktok, handle_xhs')
    .eq('id', vid.data.client_id as string).maybeSingle();
  if (cl.error || !cl.data) return json({ error: 'client-scope' }, 200, origin);
  const c = cl.data as Record<string, unknown>;

  /* The client's brand first (2026-10-12): its Content brief's audience,
     pillars and tone, and a confirmed Brand analysis, asked before a use is
     claimed, so a refusal counts nothing. */
  const ready = await db.rpc('ai_brand_ready', { p_client: vid.data.client_id as string });
  if (ready.error) return json({ error: 'needs-update' }, 200, origin);
  const rd = (ready.data || {}) as Record<string, unknown>;
  if (rd.error) return json({ error: String(rd.error) }, 200, origin);
  if (Array.isArray(rd.missing) && rd.missing.length) return json({ error: 'no-brief', missing: rd.missing }, 200, origin);
  if (rd.analysis !== true) return json({ error: 'no-analysis' }, 200, origin);
  const ownHandle = String(c[({ Instagram: 'handle_ig', TikTok: 'handle_tiktok', Facebook: 'handle_fb', rednote: 'handle_xhs' } as
    Record<string, string>)[platform] || ''] || '').trim().replace(/^@/, '');
  /* The month's other scripts for this client (scripts-by-month). */
  const sibs = await db.from('video_scripts').select('code, title')
    .eq('client_id', vid.data.client_id as string).eq('period', vid.data.period as string).neq('id', scriptId).order('seq');

  /* The client's name and handles never leave: they read {brand} and
     {handle}, longest first, so a handle holding the name is masked whole. */
  const handles = ['handle_ig', 'handle_fb', 'handle_tiktok', 'handle_xhs']
    .map((k) => String(c[k] || '').trim().replace(/^@/, '')).filter((h) => h.length > 1);
  const name = String(c.name || '').trim();
  const masks: [string, string][] = [
    ...handles.map((h) => ['@?' + escRe(h), '{handle}'] as [string, string]),
    ...(name.length > 1 ? [[escRe(name), '{brand}'] as [string, string]] : [])
  ].sort((a, b) => b[0].length - a[0].length);
  const mask = (s: string) => masks.reduce((t, [re, to]) => t.replace(new RegExp(re, 'gi'), to), s);

  /* The draft so far, as the editor holds it, masked like the rest. */
  const nowScenes = (Array.isArray(now.scenes) ? now.scenes : []).slice(0, 60)
    // deno-lint-ignore no-explicit-any
    .map((x: any) => ({
      start_s: secs(x && x.t_from), end_s: secs(x && x.t_to),
      shot_size: text(x && x.shot_size, 60), angle: text(x && x.angle, 60), camera_move: text(x && x.camera_move, 60),
      visual: mask(text(x && x.visual, 2000)), line: kind === 'scenes' ? mask(text(x && x.line, 2000)) : '',
      on_screen: mask(text(x && x.on_screen, 120)), sound: mask(text(x && x.sound, 200))
    }))
    .filter((x: { visual: string; line: string }) => x.visual || x.line);
  const draft: Record<string, unknown> = {};
  if (text(now.context, 4000)) draft.context = mask(text(now.context, 4000));
  if (nowScenes.length) draft.scenes = nowScenes;
  if (kind === 'story' && text(now.vo, 4000)) draft.vo = mask(text(now.vo, 4000));

  /* The client's content brief and brand notes (2026-10-10), masked as
     the rest; read apart so a database without the column still drafts. */
  const br = await db.from('clients').select('brief, brand_notes').eq('id', vid.data.client_id as string).maybeSingle();
  const briefIn = (!br.error && br.data) ? (br.data as Record<string, unknown>) : {};
  const content: Record<string, string> = {};
  const rawBrief = (briefIn.brief && typeof briefIn.brief === 'object') ? briefIn.brief as Record<string, unknown> : {};
  for (const k of ['audience', 'pains', 'pillars', 'tone', 'avoid', 'competitors', 'hooks']) {
    const v = String(rawBrief[k] ?? '').trim();
    if (v) content[k] = mask(v).slice(0, 1000);
  }
  const brandNotes = String(briefIn.brand_notes ?? '').trim();
  /* The client's latest confirmed brand analysis (2026-10-10). */
  const ba = await db.rpc('brand_analysis_brief', { p_client: vid.data.client_id as string });
  // deno-lint-ignore no-explicit-any
  const maskDeep = (v: any): any => typeof v === 'string' ? mask(v).slice(0, 800)
    : Array.isArray(v) ? v.slice(0, 6).map(maskDeep)
    : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, maskDeep(x)])) : v;
  const brandAnalysis = !ba.error && ba.data && typeof ba.data === 'object' ? maskDeep(ba.data) : null;

  /* The script's own brief, as both calls read it: the facts of the video,
     the brief's words masked, the limits as numbers or not given. */
  const word = (k: string) => typeof brief0[k] === 'string' ? mask(String(brief0[k])) : null;
  const limit = (k: string) => typeof brief0[k] === 'number' ? brief0[k] : 'not given';
  const brief: Record<string, unknown> = {
    client: '{brand}', industry: String(c.industry || '').trim() || null,
    market: String(c.market || '').toUpperCase() === 'SG' ? 'Singapore' : 'Malaysia',
    type: KIND[kind], platform, aspect_ratio: aspect, length_seconds: seconds, language,
    title: title ? mask(title) : null,
    product_or_offer: word('offer'), objective: brief0.objective ? OBJECTIVE[String(brief0.objective)] : null,
    target_audience: word('audience'), key_message: word('key_message'), mandatory_call_to_action: word('cta'),
    must_include: word('must_include'), must_avoid: word('must_avoid'), tone: word('tone'),
    format: brief0.format ? FORMAT[String(brief0.format)] : null,
    venue: venue ? mask(venue) : null, cast_named: cast || null,
    limits: { locations: limit('max_locations'), on_screen_talent: limit('max_cast'), shoot_hours: limit('max_shoot_hours') },
    notes: notes ? mask(notes) : null
  };
  const data: Record<string, unknown> = {
    brief,
    content_brief: Object.keys(content).length ? content : null,
    brand_notes: brandNotes ? mask(brandNotes).slice(0, 1500) : null,
    brand_analysis: brandAnalysis,
    other_videos_this_month: (sibs.data || []).map((x: Record<string, unknown>) =>
      String(x.code || '') + (x.title ? ' · ' + mask(String(x.title)) : '')),
    draft_so_far: Object.keys(draft).length ? draft : null
  };

  /* The writer's answer: the plan, then the shot table, then what is
     missing from the brief. */
  const str = (d: string) => ({ type: 'string', description: d });
  const num = (d: string) => ({ type: 'integer', description: d });
  const sceneProps: Record<string, unknown> = {
    start_s: num('Second the scene starts'), end_s: num('Second the scene ends'),
    shot_size: str('Shot size'), angle: str('Camera angle'), camera_move: str('Camera move, with its reason where it is static'),
    visual: str('What happens on screen, with screen left and right')
  };
  if (kind === 'scenes') sceneProps.line = str('The words spoken over it, or empty');
  sceneProps.on_screen = str('On-screen text, 7 words at most, or empty');
  sceneProps.sound = str('Sound effect or music cue, or empty');
  const scene = { type: 'object', properties: sceneProps, required: Object.keys(sceneProps), additionalProperties: false };
  const properties: Record<string, unknown> = {
    core_message: str('What the viewer should remember, one sentence'),
    concept: str('The concept in two or three sentences'),
    hook: str('What the viewer sees and hears from 0 to 3 seconds'),
    cast: str('Each on-screen role and its description, one a line'),
    locations: str('Each location, one a line'),
    props: str('Every prop, one a line'),
    music: str('The music mood'),
    cta: str('The call to action')
  };
  if (kind === 'products') properties.context = str('Products and context');
  if (kind === 'story') properties.context = str('Hook and story');
  properties.scenes = { type: 'array', description: 'The scenes in order', items: scene };
  if (kind === 'story') properties.vo = str('The whole voice-over, read across the scenes');
  properties.open_questions = { type: 'array', description: 'Facts missing from the brief', items: { type: 'string' } };
  const schema = { type: 'object', properties, required: Object.keys(properties), additionalProperties: false };
  const reviewSchema = {
    type: 'object',
    properties: {
      understood_story: str('The story as understood, one or two sentences'),
      core_message: str('The core message as understood, one sentence'),
      issues: { type: 'array', items: { type: 'object', properties: {
        shot: num('Scene number, 0 for the whole script'), problem: str('The problem'), fix: str('A suggested fix'),
        severity: { type: 'string', enum: ['critical', 'minor'] }, certainty: { type: 'string', enum: ['sure', 'possible'] }
      }, required: ['shot', 'problem', 'fix', 'severity', 'certainty'], additionalProperties: false } },
      verdict: { type: 'string', enum: ['PASS', 'FAIL'] }
    },
    required: ['understood_story', 'core_message', 'issues', 'verdict'], additionalProperties: false
  };

  const claim = await db.rpc('ai_script_claim', { p_script: scriptId });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const pressId = String(got.id || '');
  const done = (ok: boolean) => db.rpc('ai_draft_done', { p_id: pressId, p_ok: ok }).then(() => null, () => null);
  const use: Use = { input: 0, output: 0, model: null };

  return held((async () => {
    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY'), maxRetries: 0 });
    const left = () => BUDGET_MS - (Date.now() - started);
    // deno-lint-ignore no-explicit-any
    const call = async (system: string, messages: any[], format: unknown, effort: string): Promise<any> => {
      const res = await client.messages.create({
        model, max_tokens: 16000, system,
        output_config: { effort, format: { type: 'json_schema', schema: format } },
        messages
      } as Anthropic.MessageCreateParamsNonStreaming, { timeout: Math.max(5000, left()) });
      add(use, res);
      if (res.stop_reason === 'refusal' || res.stop_reason === 'max_tokens') {
        console.error('script-draft: answer stopped short', res.stop_reason);
        return null;
      }
      const said = res.content.filter((b) => b.type === 'text').map((b) => b.type === 'text' ? b.text : '').join('');
      try { return JSON.parse(said); } catch { return null; }
    };
    // deno-lint-ignore no-explicit-any
    const clean = (out: any) => {
      if (!out || !Array.isArray(out.scenes)) return null;
      // deno-lint-ignore no-explicit-any
      const scenes = out.scenes.slice(0, 40).map((x: any) => {
        let a = secs(x && x.start_s), b = secs(x && x.end_s);
        if (a != null && b != null && b <= a) b = null;
        if (b === 0) b = null;
        return {
          t_from: a, t_to: b,
          shot_size: text(x && x.shot_size, 60), angle: text(x && x.angle, 60), camera_move: text(x && x.camera_move, 60),
          visual: text(x && x.visual, 2000), line: kind === 'scenes' ? text(x && x.line, 2000) : '',
          on_screen: text(x && x.on_screen, 120), sound: text(x && x.sound, 200)
        };
      }).filter((x: { visual: string; line: string }) => x.visual || x.line);
      if (!scenes.length || (kind !== 'scenes' && typeof out.context !== 'string') || (kind === 'story' && typeof out.vo !== 'string')) return null;
      const w: Record<string, unknown> = {
        scenes,
        plan: {
          core_message: text(out.core_message, 2000), concept: text(out.concept, 2000), hook: text(out.hook, 2000),
          cast: text(out.cast, 2000), locations: text(out.locations, 2000), props: text(out.props, 2000),
          music: text(out.music, 2000), cta: text(out.cta, 2000)
        },
        questions: (Array.isArray(out.open_questions) ? out.open_questions : []).slice(0, 12)
          .map((q: unknown) => text(q, 300)).filter(Boolean)
      };
      if (kind !== 'scenes') w.context = text(out.context, 4000);
      if (kind === 'story') w.vo = text(out.vo, 4000);
      return w;
    };
    /* The script as the reviewer reads it: the answer alone, never the
       writer's reasoning. */
    // deno-lint-ignore no-explicit-any
    const forReview = (w: any) => ({
      ...w.plan, ...(w.context != null ? { context: w.context } : {}), ...(w.vo != null ? { voice_over: w.vo } : {}),
      // deno-lint-ignore no-explicit-any
      scenes: w.scenes.map((x: any, i: number) => ({ scene: i + 1, ...x }))
    });
    // deno-lint-ignore no-explicit-any
    const review = async (w: any) => {
      const r = await call(P[REVIEW] + (safe ? P[SAFE] : ''), [{ role: 'user', content:
        'The brief and the script follow as JSON. Review the script.\n\nBRIEF\n' + JSON.stringify(brief) +
        '\n\nSCRIPT\n' + JSON.stringify(forReview(w)) }], reviewSchema, 'low');
      if (!r || !Array.isArray(r.issues)) return null;
      // deno-lint-ignore no-explicit-any
      const issues = r.issues.slice(0, 30).map((x: any) => ({
        shot: Math.max(0, Math.min(60, Math.floor(Number(x && x.shot) || 0))),
        problem: text(x && x.problem, 600), fix: text(x && x.fix, 600),
        severity: x && x.severity === 'critical' ? 'critical' : 'minor',
        certainty: x && x.certainty === 'possible' ? 'possible' : 'sure'
      })).filter((x: { problem: string }) => x.problem);
      const critical = issues.some((x: { severity: string }) => x.severity === 'critical');
      return {
        verdict: r.verdict === 'PASS' && !critical ? 'pass' : 'fail',
        story: text(r.understood_story, 800), core_message: text(r.core_message, 400), issues
      };
    };

    try {
      const ask = [{ role: 'user', content: 'Write the script for this video. The brief and the team\'s notes follow as JSON.\n\n' + JSON.stringify(data) }];
      let w = clean(await call(P[SYSTEM] + (safe ? P[SAFE] : ''), ask, schema, 'medium'));
      if (!w) { await keepTokens(db, pressId, use); await done(false); return { error: 'ai-incomplete' }; }
      // deno-lint-ignore no-explicit-any
      let rv: any = left() > 25000 ? await review(w).catch(() => null) : null;
      // deno-lint-ignore no-explicit-any
      let first: any = null;
      /* One rewrite on a failed review, where the time allows a second
         write and a second read. */
      if (rv && rv.verdict === 'fail' && left() > 70000) {
        const again = clean(await call(P[SYSTEM] + (safe ? P[SAFE] : ''), [...ask,
          { role: 'assistant', content: JSON.stringify(forReview(w)) },
          { role: 'user', content: 'A reviewer who read this script cold found these problems. Fix every critical one and every minor one you agree with, keeping to every rule, and return the whole script again.\n\n' +
            JSON.stringify(rv.issues) }], schema, 'medium').catch(() => null));
        if (again) {
          const rv2 = left() > 15000 ? await review(again).catch(() => null) : null;
          if (rv2) { first = rv; w = again; rv = rv2; }
        }
      }
      await keepTokens(db, pressId, use);
      await done(true);
      /* {brand} and {handle} come back as written; the page fills them, the
         handle being the platform's own (the page cannot always read it). */
      const reviewOut = rv ? { ...rv, first, questions: w.questions } : null;
      return { draft: w, review: reviewOut, handle: ownHandle ? '@' + ownHandle : null, left: got.left };
    } catch (e) {
      /* The API's own type and message go to the function's log (never the
         key), so a refusal can be named. */
      const err = e as { status?: number; name?: string; message?: string; error?: { error?: { type?: string; message?: string } } };
      const status = err.status;
      const type = err.error?.error?.type || '';
      const msg = err.error?.error?.message || err.message || '';
      console.error('script-draft: Claude API refused', status, type, msg);
      /* Our own timeout cut off a request the model was already running
         (audit 2026-11-15): it is counted as incomplete, never failed, so a
         long run cannot be pressed again without limit. One token marks it
         (ai_draft_done reads a row with input as incomplete); a refusal (a
         status) or a request that never left stays failed. */
      if (!status && (err.name === 'APIConnectionTimeoutError' || /timed? ?out/i.test(msg)) && !use.input) use.input = 1;
      await keepTokens(db, pressId, use);
      await done(false);
      const code = status === 401 || status === 403 ? 'ai-key'
        : status === 429 || status === 529 ? 'ai-busy'
        : /credit balance/i.test(msg) ? 'ai-credit'
        : status === 404 || type === 'not_found_error' ? 'ai-model'
        : 'ai-failed';
      return { error: code };
    }
  })(), origin);
});
