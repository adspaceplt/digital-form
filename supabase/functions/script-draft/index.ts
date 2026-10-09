/*
 * script-draft — writes a video's script for Video Scripts (2026-10-09).
 *
 * Write script in the script's Edit sheet (js/scripts.js) posts the video's
 * id, the type of script and the facts the sheet holds (title, platform,
 * language, venue, how many in the cast), the video's length, the
 * colleague's notes for the script and whatever script the sheet already
 * holds. The function reads the video and its client as the caller, under
 * the caller's own access (Video Scripts at Work, a client the colleague
 * works on), and sends Claude only what a script needs: the type, the
 * platform, the length, the language, the notes, the other videos' titles in
 * the same shoot, and the client's industry and market. Never a cast
 * member's name, a contact or the client's name: the name reads {brand} and
 * a handle {handle} wherever the team's words carry them, and the page fills
 * both back in.
 *
 * Every press is counted by the database before Claude is asked
 * (`ai_script_claim`: the colleague's scripts a day, apart from the reports'
 * and the captions'), marked done or failed after (`ai_draft_done`), and what
 * the call cost is kept on its row (`ai_draft_tokens`). Nothing is saved
 * here: the page puts the words in the sheet and the script's own Save keeps
 * them.
 *
 * Secrets: ANTHROPIC_API_KEY, and SCRIPT_MODEL (the model id; unset, it is
 *          claude-opus-5-5), set in the Supabase dashboard, plus the
 *          platform's SUPABASE_URL and SUPABASE_ANON_KEY.
 *
 * A refusal the person can act on answers 200 with { error }, so the page
 * names it; a non-2xx is kept for a malformed request.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import Anthropic from 'npm:@anthropic-ai/sdk';

const ALLOWED_ORIGINS = ['https://digital.adspace.me', 'http://localhost:8899'];

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
    status, headers: { 'Content-Type': 'application/json', ...cors(origin) }
  });
}
function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }

/* The kinds, platforms and languages the sheet offers (js/scripts.js). */
const KIND: Record<string, string> = {
  scenes: 'Detailed scenes', products: 'Products and scenes', story: 'Story and voice-over'
};
const PLATFORMS = ['Instagram', 'TikTok', 'Facebook', 'rednote', 'YouTube'];
const LANGS = ['English', 'Chinese', 'Malay', 'English and Chinese'];
const LENGTHS = [15, 30, 60, 120];

/* The house style (the user's own copy standards, 2026-10-08, written for
   video). The examples are invented; no client's words are here. */
const SYSTEM = `You write short video scripts for ADspace, a digital marketing agency in Johor Bahru serving clients in Malaysia and Singapore across property, F&B, retail, wellness, lifestyle, automotive and tech. A colleague reads your script, corrects it and shares it with the client for approval, and the crew films from it on the day; write it ready to shoot.

WHAT MAKES THE SCRIPT
The first two seconds carry the hook: a moment, a question or a problem the viewer recognises, about the viewer, never the brand's name or a logo.
Benefit first, never feature first: each scene shows what the customer gains, feels, solves or avoids, and the feature is how it is true. Weak: "Our tissue has lotion." Better: "A softer touch every time your skin needs extra care."
One idea a video. End with one clear call to action that fits the video (visit, book, message, save, follow), never two competing ones.
Fit the length given: about one scene for every three to five seconds, and spoken words a person can say in that time (about two to three English words, or four to five Chinese characters, a second).
Every visual is one shot the crew can film: who is in frame, what they do, where, and the camera (close up, wide, top down, over the shoulder, a slow pan, a handheld follow). Text shown on screen goes in the visual as On screen: "…". Never a shot that needs what the notes do not offer (a drone, a celebrity, a crowd, a second location) unless the notes ask for it, and never more people than the cast given.
Spoken words are written to be said aloud: short sentences, everyday words, no directions inside them.
No dashes as punctuation in any line: write the sentence another way.

THE THREE TYPES
Detailed scenes: each scene a visual and the words spoken over it (an empty line where the scene has no words).
Products and scenes: context first (the products to feature, what each gives the customer, the setting and the mood, in a few short lines), then each scene a visual, any words spoken or shown inside the visual.
Story and voice-over: hook and story first (the opening moment, the story in a few sentences, how it ends), then each scene a visual, then the whole voice-over as one script read by one voice across the scenes.
Where a draft so far is given, build on it: keep what works, complete what is missing, and correct what breaks these rules.

LOCAL
Write for Malaysia or Singapore as the market given: local life, places, habits and buying moments, prices in RM or S$ when the notes give a price. Use a festive season (Chinese New Year, Hari Raya Aidilfitri, Deepavali, Christmas, Mid-Autumn, the year-end sales, 11.11, 12.12) only when the notes or the title name it, never invent one.

PLATFORM
Instagram: a Reel; lifestyle storytelling, a moment the viewer can see themselves in, polished but natural.
TikTok: a fast hook, entertainment first, a relatable scenario, spoken to camera, playful.
Facebook: community trust and local relevance, clear on what it is, why it matters to the viewer and how to get it.
rednote: soft selling and authentic discovery in a first person voice, like a video shared by someone who tried it; never a hard sell.
YouTube: a Short; a clear hook, one useful idea, a clean ending.

TRUTH
Say only what the notes, the title and the client's industry support. Never invent a price, an offer, a date, an address, an award, a figure or a claim. Where the notes give no offer, the call to action invites the viewer to find out more.
Name the client only as the placeholder {brand} and its account only as {handle}, written exactly so with their braces; they are filled in afterwards. Never write a guessed brand name, and never name a cast member: say the host, the customer, the chef.
These brand names are always written exactly so: S P Setia, CraftStone, Home Leader, The Mill International, EV SUN, Foodince, Furiku Matcha, HKL Lim, HKL Lim Motorsport, Star Living, Niro Granite, Dale & Cecil, Dale, ADspace.

LANGUAGE
English: British English. Malay: Bahasa Melayu as Malaysians speak it on social media (natural, warm, never stiff or translated). Chinese: Simplified Chinese written as Chinese for Malaysian and Singaporean viewers, spoken naturally, never translated word for word. Every part of the script is in the language given, except English and Chinese: there the context and the visuals are in English, and each spoken line, and the voice-over, is written in English and then in Chinese on the next line, the Chinese composed as Chinese and saying the same thing.`;

/* XHS Safe Mode: only when the colleague ticks it (the user's rule: apply
   it only once confirmed). */
const SAFE = `

XHS SAFE MODE (rednote's content rules; apply to every word, spoken or on screen)
Never use: absolute claims (best, number one, 100%, 最, 第一, 顶级, 绝对), authority endorsements (doctor, expert or official recommended), clickbait, panic urgency (last chance, hurry, 手慢无), medical or treatment claims (cures, heals, treats, 治疗, 疗效), exaggerated beauty or cosmetic claims (instant whitening, removes wrinkles), superstition (luck, feng shui promises), aggressive diversion to other platforms (WhatsApp me, link in another app, 加微信), vulgarity, flaunting wealth, cyberbullying, or over retouching language.
Use instead: soft, benefit first wording; neutral calls to action (save this for later, tell us what you think, 欢迎收藏); lifestyle storytelling; an authentic user's voice (I tried, I noticed, 亲测); gentle urgency (while the season lasts); social proof phrasing (many viewers asked about this).`;

/* What a call cost, kept on its own row, drafted or failed. */
// deno-lint-ignore no-explicit-any
function keepTokens(db: any, id: string, res: Anthropic.Message): Promise<null> {
  const u = (res && res.usage || {}) as unknown as Record<string, number | null | undefined>;
  const input = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
  return db.rpc('ai_draft_tokens', { p_id: id, p_in: input, p_out: u.output_tokens || 0, p_model: res.model || null })
    .then(() => null, () => null);
}

const escRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const text = (v: unknown, n: number) => String(v ?? '').replace(/\r/g, '').trim().slice(0, n);

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);

  if (!secret('ANTHROPIC_API_KEY')) return json({ error: 'ai-not-set-up', missing: ['ANTHROPIC_API_KEY'] }, 200, origin);
  const model = secret('SCRIPT_MODEL') || 'claude-opus-5-5';

  const body = await req.json().catch(() => ({}));
  const scriptId = String(body && body.script_id || '');
  if (!/^[0-9a-f-]{36}$/i.test(scriptId)) return json({ error: 'bad-request' }, 400, origin);
  const kind = KIND[String(body && body.kind || '')] ? String(body.kind) : 'scenes';
  const platform = PLATFORMS.includes(String(body && body.platform || '')) ? String(body.platform) : 'Instagram';
  const language = LANGS.includes(String(body && body.language || '')) ? String(body.language) : 'English';
  const seconds = LENGTHS.includes(Number(body && body.length)) ? Number(body.length) : 30;
  const safe = platform === 'rednote' && !!(body && body.safe);
  const notes = text(body && body.notes, 3000);
  const title = text(body && body.title, 200);
  const venue = text(body && body.venue, 200);
  const cast = Math.max(0, Math.min(20, Math.floor(Number(body && body.cast) || 0)));
  // deno-lint-ignore no-explicit-any
  const now: any = body && typeof body.current === 'object' && body.current ? body.current : {};

  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });

  const may = await db.rpc('allowed', { p_section: 'scripts', p_level: 'work' });
  if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);

  const vid = await db.from('video_scripts').select('id, client_id, series_id, video_no').eq('id', scriptId).maybeSingle();
  if (vid.error || !vid.data) return json({ error: 'not-found' }, 200, origin);
  const cl = await db.from('clients')
    .select('name, industry, market, handle_ig, handle_fb, handle_tiktok, handle_xhs')
    .eq('id', vid.data.client_id as string).maybeSingle();
  if (cl.error || !cl.data) return json({ error: 'client-scope' }, 200, origin);
  const c = cl.data as Record<string, unknown>;
  const ownHandle = String(c[({ Instagram: 'handle_ig', TikTok: 'handle_tiktok', Facebook: 'handle_fb', rednote: 'handle_xhs' } as
    Record<string, string>)[platform] || ''] || '').trim().replace(/^@/, '');
  const sibs = await db.from('video_scripts').select('video_no, title')
    .eq('series_id', vid.data.series_id as string).neq('id', scriptId).order('video_no');

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

  /* The draft so far, as the sheet holds it, masked like the rest. */
  const nowScenes = (Array.isArray(now.scenes) ? now.scenes : []).slice(0, 60)
    // deno-lint-ignore no-explicit-any
    .map((x: any) => ({ visual: mask(text(x && x.visual, 2000)), line: mask(text(x && x.line, 2000)) }))
    .filter((x: { visual: string; line: string }) => x.visual || x.line);
  const draft: Record<string, unknown> = {};
  if (text(now.context, 4000)) draft.context = mask(text(now.context, 4000));
  if (nowScenes.length) draft.scenes = kind === 'scenes' ? nowScenes : nowScenes.map((x: { visual: string }) => ({ visual: x.visual }));
  if (kind === 'story' && text(now.vo, 4000)) draft.vo = mask(text(now.vo, 4000));

  const data: Record<string, unknown> = {
    type: KIND[kind], platform, length_seconds: seconds, language,
    market: String(c.market || '').toUpperCase() === 'SG' ? 'Singapore' : 'Malaysia',
    industry: String(c.industry || '').trim() || null,
    title: title ? mask(title) : null,
    venue: venue ? mask(venue) : null,
    cast: cast || null,
    notes: notes ? mask(notes) : null,
    other_videos_in_this_shoot: (sibs.data || []).map((x: Record<string, unknown>) =>
      'V' + x.video_no + (x.title ? ' · ' + mask(String(x.title)) : '')),
    draft_so_far: Object.keys(draft).length ? draft : null
  };

  const str = (d: string) => ({ type: 'string', description: d });
  const scene = kind === 'scenes'
    ? { type: 'object', properties: { visual: str('The shot'), line: str('The words spoken over it, or empty') },
        required: ['visual', 'line'], additionalProperties: false }
    : { type: 'object', properties: { visual: str('The shot, with any words spoken or shown in it') },
        required: ['visual'], additionalProperties: false };
  const properties: Record<string, unknown> = {};
  if (kind === 'products') properties.context = str('Products and context');
  if (kind === 'story') properties.context = str('Hook and story');
  properties.scenes = { type: 'array', description: 'The scenes in order', items: scene };
  if (kind === 'story') properties.vo = str('The whole voice-over, read across the scenes');
  const schema = { type: 'object', properties, required: Object.keys(properties), additionalProperties: false };

  const claim = await db.rpc('ai_script_claim', { p_script: scriptId });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const pressId = String(got.id || '');
  const done = (ok: boolean) => db.rpc('ai_draft_done', { p_id: pressId, p_ok: ok }).then(() => null, () => null);

  try {
    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY') });
    /* Held to the type's fields by structured output; medium effort leaves
       room to plan the scenes without a long wait. */
    const res = await client.messages.create({
      model,
      max_tokens: 16000,
      system: SYSTEM + (safe ? SAFE : ''),
      output_config: { effort: 'medium', format: { type: 'json_schema', schema } },
      messages: [{ role: 'user', content: 'Write the script for this video. The video and the team\'s notes follow as JSON.\n\n' +
        JSON.stringify(data) }]
    } as Anthropic.MessageCreateParamsNonStreaming);
    await keepTokens(db, pressId, res);
    if (res.stop_reason === 'refusal' || res.stop_reason === 'max_tokens') {
      console.error('script-draft: answer stopped short', res.stop_reason);
      await done(false);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    const said = res.content.filter((b) => b.type === 'text').map((b) => b.type === 'text' ? b.text : '').join('');
    // deno-lint-ignore no-explicit-any
    let out: any = null;
    try { out = JSON.parse(said); } catch { out = null; }
    const scenes = out && Array.isArray(out.scenes)
      // deno-lint-ignore no-explicit-any
      ? out.scenes.slice(0, 40).map((x: any) => ({ visual: text(x && x.visual, 2000), line: kind === 'scenes' ? text(x && x.line, 2000) : '' }))
          .filter((x: { visual: string; line: string }) => x.visual || x.line)
      : [];
    if (!scenes.length || (kind !== 'scenes' && typeof out.context !== 'string') || (kind === 'story' && typeof out.vo !== 'string')) {
      console.error('script-draft: no script in the answer', res.stop_reason);
      await done(false);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    await done(true);
    /* {brand} and {handle} come back as written; the page fills them, the
       handle being the platform's own (the page cannot always read it). */
    const answer: Record<string, unknown> = { scenes };
    if (kind !== 'scenes') answer.context = text(out.context, 4000);
    if (kind === 'story') answer.vo = text(out.vo, 4000);
    return json({ draft: answer, handle: ownHandle ? '@' + ownHandle : null, left: got.left }, 200, origin);
  } catch (e) {
    /* The API's own type and message go to the function's log (never the
       key), so a refusal can be named. */
    const err = e as { status?: number; message?: string; error?: { error?: { type?: string; message?: string } } };
    const status = err.status;
    const type = err.error?.error?.type || '';
    const msg = err.error?.error?.message || err.message || '';
    console.error('script-draft: Claude API refused', status, type, msg);
    await done(false);
    const code = status === 401 || status === 403 ? 'ai-key'
      : status === 429 || status === 529 ? 'ai-busy'
      : /credit balance/i.test(msg) ? 'ai-credit'
      : status === 404 || type === 'not_found_error' ? 'ai-model'
      : 'ai-failed';
    return json({ error: code }, 200, origin);
  }
});
