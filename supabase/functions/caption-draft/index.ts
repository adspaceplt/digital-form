/*
 * caption-draft — writes a post's caption for Content Review (2026-10-08).
 *
 * Write caption beside a post's caption fields in the console (js/admin.js,
 * Add assets and a saved post's Edit) posts the set's id, the post's
 * placement and title, the colleague's notes for the caption and the
 * languages asked for. The function reads the set and its client as the
 * caller, under the caller's own access (Content Review: Sets at Work, a
 * client the colleague sees), and sends Claude only what a caption needs:
 * the platform and format, the set's and the post's titles, the notes, and
 * the client's industry and market. Never an image, a contact or the
 * client's name: the name reads {brand} and a handle {handle} wherever the
 * team's words carry them, and the page fills both back in.
 *
 * Every press is counted by the database before Claude is asked
 * (`ai_caption_claim`: the colleague's captions a day, apart from the
 * reports'), marked done or failed after (`ai_draft_done`), and what the
 * call cost is kept on its row (`ai_draft_tokens`). Nothing is saved here:
 * the page puts the words in the fields and the post's own Save keeps them.
 *
 * Secrets: ANTHROPIC_API_KEY, and CAPTION_MODEL (the model id; unset, it is
 *          claude-opus-5-5), set in the Supabase dashboard
 *          (docs/CAPTION-WRITER-SETUP.md), plus the platform's SUPABASE_URL
 *          and SUPABASE_ANON_KEY.
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

/* The placements Content Review offers (js/admin.js PLACEMENTS). */
const PLATFORM: Record<string, string> = { instagram: 'Instagram', facebook: 'Facebook', tiktok: 'TikTok', xhs: 'rednote' };
const FORMAT: Record<string, string> = {
  feed: 'feed post', carousel: 'carousel', reel: 'short video (Reels)', story: 'Story', multi: 'multi-photo post', note: 'post'
};

/* The house style (the user's own copy standards, 2026-10-08). The examples
   are invented; no client's words are here. */
const SYSTEM = `You write social media captions for ADspace, a digital marketing agency in Johor Bahru serving clients in Malaysia and Singapore across property, F&B, retail, wellness, lifestyle, automotive and tech. A colleague reads your caption, corrects it and puts it in front of the client for approval; write it ready to post.

WHAT MAKES THE CAPTION
Benefit first, never feature first: say what the customer gains, feels, solves or avoids, then the feature that makes it true. Weak: "This tissue has lotion." Better: "Enjoy a softer touch every time your skin needs extra care."
Open with a strong hook in the first line: the line a thumb stops on, about the reader, their moment or their problem, never about the brand.
Where it suits the platform and the post, lead with a title line: one emoji, a space, then a short title written in Unicode bold letters (for example ✨ 𝗪𝗲𝗲𝗸𝗲𝗻𝗱 𝗕𝗿𝘂𝗻𝗰𝗵 𝗦𝗼𝗿𝘁𝗲𝗱), then a blank line and the body. Only Latin letters and digits take bold letters; Chinese and Malay accented letters stay as they are.
End with one clear call to action that fits the post (visit, book, message, save, share, comment), never two competing ones.
Short paragraphs with a blank line between them. Emoji only where they help the reader scan, never more than one a line. Hashtags only where the notes ask for them, at most five, at the end.
No dashes as punctuation in the copy: write the sentence another way.

LOCAL
Write for Malaysia or Singapore as the market given: local life, places, habits and buying moments, prices in RM or S$ when the notes give a price. Use a festive season (Chinese New Year, Hari Raya Aidilfitri, Deepavali, Christmas, Mid-Autumn, the year-end sales, 11.11, 12.12) only when the notes or the set name it, never invent one.

PLATFORM
Instagram: lifestyle storytelling, a moment the reader can see themselves in, brand image; a carousel caption invites a swipe, a Reel caption backs the video's hook.
Facebook: community trust and local relevance, conversion friendly: what it is, why it matters to the reader, how to get it.
TikTok: a fast hook and an entertainment first, relatable scenario; short, spoken, playful lines.
rednote: soft selling and authentic discovery in a first person, benefit led, trust building voice, like a note shared by someone who tried it; never a hard sell.

TRUTH
Say only what the notes, the titles and the client's industry support. Never invent a price, an offer, a date, an address, an award, a figure or a claim. Where the notes give no offer, the call to action invites the reader to find out more.
Name the client only as the placeholder {brand} and its account only as {handle}, written exactly so with their braces; they are filled in afterwards. Never write a guessed brand name.
These brand names are always written exactly so: S P Setia, CraftStone, Home Leader, The Mill International, EV SUN, Foodince, Furiku Matcha, HKL Lim, HKL Lim Motorsport, Star Living, Niro Granite, Dale & Cecil, Dale, ADspace.

LANGUAGES
caption is written in the main language named: British English, or Bahasa Melayu as Malaysians write it on social media (natural, warm, never stiff or translated).
caption_zh, when asked for, is Simplified Chinese written as Chinese for Malaysian and Singaporean readers: composed in Chinese for the platform, never translated word for word from the other caption; it may lead with its own hook. Full width Chinese punctuation. The two captions say the same offer and call to action.`;

/* XHS Safe Mode: only when the colleague ticks it (the user's rule: apply
   it only once confirmed). */
const SAFE = `

XHS SAFE MODE (rednote's content rules; apply to every word)
Never use: absolute claims (best, number one, 100%, 最, 第一, 顶级, 绝对), authority endorsements (doctor, expert or official recommended), clickbait, panic urgency (last chance, hurry, 手慢无), medical or treatment claims (cures, heals, treats, 治疗, 疗效), exaggerated beauty or cosmetic claims (instant whitening, removes wrinkles), superstition (luck, feng shui promises), aggressive diversion to other platforms (WhatsApp me, link in another app, 加微信), vulgarity, flaunting wealth, cyberbullying, or over retouching language.
Use instead: soft, benefit first wording; neutral calls to action (save this for later, tell us what you think, 欢迎收藏); lifestyle storytelling; an authentic user's voice (I tried, I noticed, 亲测); gentle urgency (while the season lasts); social proof phrasing (many readers asked about this).`;

/* What a call cost, kept on its own row, drafted or failed. */
// deno-lint-ignore no-explicit-any
function keepTokens(db: any, id: string, res: Anthropic.Message): Promise<null> {
  const u = (res && res.usage || {}) as unknown as Record<string, number | null | undefined>;
  const input = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
  return db.rpc('ai_draft_tokens', { p_id: id, p_in: input, p_out: u.output_tokens || 0, p_model: res.model || null })
    .then(() => null, () => null);
}

const escRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);

  if (!secret('ANTHROPIC_API_KEY')) return json({ error: 'ai-not-set-up', missing: ['ANTHROPIC_API_KEY'] }, 200, origin);
  const model = secret('CAPTION_MODEL') || 'claude-opus-5-5';

  const body = await req.json().catch(() => ({}));
  const setId = String(body && body.set_id || '');
  if (!/^[0-9a-f-]{36}$/i.test(setId)) return json({ error: 'bad-request' }, 400, origin);
  const [platKey, fmtKey] = String(body && body.placement || 'instagram:feed').split(':');
  const platform = PLATFORM[platKey] || 'Instagram';
  const format = FORMAT[fmtKey] || 'post';
  const lang = body && body.lang === 'ms' ? 'ms' : 'en';
  const zh = !!(body && body.zh);
  const safe = platKey === 'xhs' && !!(body && body.safe);
  const notes = String(body && body.notes || '').replace(/\r/g, '').trim().slice(0, 2000);
  const title = String(body && body.title || '').replace(/\r/g, '').trim().slice(0, 200);

  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });

  const may = await db.rpc('allowed', { p_section: 'review.sets', p_level: 'work' });
  if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);

  const set = await db.from('batches').select('id, title, client_id').eq('id', setId).maybeSingle();
  if (set.error || !set.data) return json({ error: 'not-found' }, 200, origin);
  const cl = await db.from('clients')
    .select('name, industry, market, handle_ig, handle_fb, handle_tiktok, handle_xhs')
    .eq('id', set.data.client_id as string).maybeSingle();
  if (cl.error || !cl.data) return json({ error: 'not-found' }, 200, origin);
  const c = cl.data as Record<string, unknown>;

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

  const data: Record<string, unknown> = {
    platform, format,
    market: String(c.market || '').toUpperCase() === 'SG' ? 'Singapore' : 'Malaysia',
    industry: String(c.industry || '').trim() || null,
    set: mask(String(set.data.title || '')),
    post_title: title ? mask(title) : null,
    notes: notes ? mask(notes) : null,
    main_language: lang === 'ms' ? 'Bahasa Melayu' : 'English'
  };

  const str = (d: string) => ({ type: 'string', description: d });
  const properties: Record<string, unknown> = { caption: str('The caption in the main language, ready to post') };
  if (zh) properties.caption_zh = str('The caption in Simplified Chinese, written as Chinese');
  const schema = { type: 'object', properties, required: Object.keys(properties), additionalProperties: false };

  const claim = await db.rpc('ai_caption_claim', { p_batch: setId });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const pressId = String(got.id || '');
  const done = (ok: boolean) => db.rpc('ai_draft_done', { p_id: pressId, p_ok: ok }).then(() => null, () => null);

  try {
    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY') });
    /* Held to the fields asked for by structured output; a caption is a
       short piece, so medium effort leaves room to think without waiting. */
    const res = await client.messages.create({
      model,
      max_tokens: 16000,
      system: SYSTEM + (safe ? SAFE : ''),
      output_config: { effort: 'medium', format: { type: 'json_schema', schema } },
      messages: [{ role: 'user', content: 'Write the caption for this post' + (zh ? ', and its Chinese caption' : '') +
        '. The post and the team\'s notes follow as JSON.\n\n' + JSON.stringify(data) }]
    } as Anthropic.MessageCreateParamsNonStreaming);
    await keepTokens(db, pressId, res);
    if (res.stop_reason === 'refusal' || res.stop_reason === 'max_tokens') {
      console.error('caption-draft: answer stopped short', res.stop_reason);
      await done(false);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    const text = res.content.filter((b) => b.type === 'text').map((b) => b.type === 'text' ? b.text : '').join('');
    let out: Record<string, unknown> | null = null;
    try { out = JSON.parse(text); } catch { out = null; }
    const clean = (v: unknown) => String(v ?? '').replace(/\r/g, '').trim().slice(0, 5000);
    if (!out || typeof out.caption !== 'string' || (zh && typeof out.caption_zh !== 'string')) {
      console.error('caption-draft: no caption in the answer', res.stop_reason);
      await done(false);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    await done(true);
    const answer: Record<string, unknown> = { caption: clean(out.caption) };
    if (zh) answer.caption_zh = clean(out.caption_zh);
    return json({ draft: answer, left: got.left }, 200, origin);
  } catch (e) {
    /* The API's own type and message go to the function's log (never the
       key), so a refusal can be named. */
    const err = e as { status?: number; message?: string; error?: { error?: { type?: string; message?: string } } };
    const status = err.status;
    const type = err.error?.error?.type || '';
    const said = err.error?.error?.message || err.message || '';
    console.error('caption-draft: Claude API refused', status, type, said);
    await done(false);
    const code = status === 401 || status === 403 ? 'ai-key'
      : status === 429 || status === 529 ? 'ai-busy'
      : /credit balance/i.test(said) ? 'ai-credit'
      : status === 404 || type === 'not_found_error' ? 'ai-model'
      : 'ai-failed';
    return json({ error: code }, 200, origin);
  }
});
