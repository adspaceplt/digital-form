/*
 * caption-draft — writes a post's caption for Content Review (2026-10-08).
 *
 * Write with AI beside a post's caption in the console (js/admin.js, Add
 * assets and a saved post's Edit) posts the set's id, the post's placement
 * and title, the colleague's notes for the caption and its one language
 * (English, Bahasa Melayu, Chinese, or English and Chinese in one caption;
 * 2026-10-10). The function reads the set and its client as the
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
import Anthropic from 'npm:@anthropic-ai/sdk@1.10.0';
import { cors, json } from '../_shared/cors.ts';
import { prompts, promptRefusal } from '../_shared/prompts.ts';

function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }

/* The placements Content Review offers (js/admin.js PLACEMENTS). */
const PLATFORM: Record<string, string> = { instagram: 'Instagram', facebook: 'Facebook', tiktok: 'TikTok', xhs: 'rednote' };
const FORMAT: Record<string, string> = {
  feed: 'feed post', carousel: 'carousel', reel: 'short video (Reels)', story: 'Story', multi: 'multi-photo post', note: 'post'
};

/* The house style (the user's own copy standards, 2026-10-08). The examples
   are invented; no client's words are here. */
const SYSTEM = 'ai.caption-draft.system';

/* XHS Safe Mode: only when the colleague ticks it (the user's rule: apply
   it only once confirmed). */
const SAFE = 'ai.caption-draft.safe';

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
  /* One caption a post (2026-10-10), in one of four languages; an older
     page's English with its Chinese tick reads as English and Chinese. */
  const LANG: Record<string, string> = { en: 'English', ms: 'Bahasa Melayu', zh: 'Chinese', en_zh: 'English and Chinese' };
  const asked = String(body && body.lang || 'en');
  const lang = LANG[asked] ? (asked === 'en' && body && body.zh ? 'en_zh' : asked) : 'en';
  const safe = platKey === 'xhs' && !!(body && body.safe);
  const notes = String(body && body.notes || '').replace(/\r/g, '').trim().slice(0, 2000);
  const title = String(body && body.title || '').replace(/\r/g, '').trim().slice(0, 200);

  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });

  const may = await db.rpc('allowed', { p_section: 'review.sets', p_level: 'work' });
  if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);
  /* Its prompts from the template store, before a press is counted. */
  let P: Record<string, string>;
  try { P = await prompts(db, [SYSTEM, SAFE]); }
  catch (e) { const no = promptRefusal(e); if (no) return json(no, 200, origin); throw e; }

  const set = await db.from('batches').select('id, title, client_id').eq('id', setId).maybeSingle();
  if (set.error || !set.data) return json({ error: 'not-found' }, 200, origin);
  const cl = await db.from('clients')
    .select('name, industry, market, handle_ig, handle_fb, handle_tiktok, handle_xhs')
    .eq('id', set.data.client_id as string).maybeSingle();
  if (cl.error || !cl.data) return json({ error: 'not-found' }, 200, origin);
  const c = cl.data as Record<string, unknown>;

  /* The client's brand first (2026-10-12): its Content brief's audience,
     pillars and tone, and a confirmed Brand analysis, asked before a use is
     claimed, so a refusal counts nothing. */
  const ready = await db.rpc('ai_brand_ready', { p_client: set.data.client_id as string });
  if (ready.error) return json({ error: 'needs-update' }, 200, origin);
  const rd = (ready.data || {}) as Record<string, unknown>;
  if (rd.error) return json({ error: String(rd.error) }, 200, origin);
  if (Array.isArray(rd.missing) && rd.missing.length) return json({ error: 'no-brief', missing: rd.missing }, 200, origin);
  if (rd.analysis !== true) return json({ error: 'no-analysis' }, 200, origin);

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

  /* The client's content brief and brand notes (2026-10-10), masked as
     the rest; read apart so a database without the column still drafts. */
  const br = await db.from('clients').select('brief, brand_notes').eq('id', set.data.client_id as string).maybeSingle();
  const briefIn = (!br.error && br.data) ? (br.data as Record<string, unknown>) : {};
  const brief: Record<string, string> = {};
  const rawBrief = (briefIn.brief && typeof briefIn.brief === 'object') ? briefIn.brief as Record<string, unknown> : {};
  for (const k of ['audience', 'pains', 'pillars', 'tone', 'avoid', 'competitors', 'hooks']) {
    const v = String(rawBrief[k] ?? '').trim();
    if (v) brief[k] = mask(v).slice(0, 1000);
  }
  const brandNotes = String(briefIn.brand_notes ?? '').trim();
  /* The client's latest confirmed brand analysis (2026-10-10): its
     positioning, audiences and pillars, masked as the rest; none where no
     analysis is confirmed or the database is older. */
  const ba = await db.rpc('brand_analysis_brief', { p_client: set.data.client_id as string });
  // deno-lint-ignore no-explicit-any
  const maskDeep = (v: any): any => typeof v === 'string' ? mask(v).slice(0, 800)
    : Array.isArray(v) ? v.slice(0, 6).map(maskDeep)
    : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, maskDeep(x)])) : v;
  const brandAnalysis = !ba.error && ba.data && typeof ba.data === 'object' ? maskDeep(ba.data) : null;

  const data: Record<string, unknown> = {
    platform, format,
    brief: Object.keys(brief).length ? brief : null,
    brand_notes: brandNotes ? mask(brandNotes).slice(0, 1500) : null,
    brand_analysis: brandAnalysis,
    market: String(c.market || '').toUpperCase() === 'SG' ? 'Singapore' : 'Malaysia',
    industry: String(c.industry || '').trim() || null,
    set: mask(String(set.data.title || '')),
    post_title: title ? mask(title) : null,
    notes: notes ? mask(notes) : null,
    language: LANG[lang]
  };

  const str = (d: string) => ({ type: 'string', description: d });
  const properties: Record<string, unknown> = { caption: str('The caption in the language named, ready to post') };
  const schema = { type: 'object', properties, required: Object.keys(properties), additionalProperties: false };

  const claim = await db.rpc('ai_caption_claim', { p_batch: setId });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const pressId = String(got.id || '');
  const done = (ok: boolean) => db.rpc('ai_draft_done', { p_id: pressId, p_ok: ok }).then(() => null, () => null);

  try {
    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY'), maxRetries: 0 });
    /* Held to the fields asked for by structured output; a caption is a
       short piece, so medium effort leaves room to think without waiting. */
    const res = await client.messages.create({
      model,
      max_tokens: 16000,
      system: P[SYSTEM] + (safe ? P[SAFE] : ''),
      output_config: { effort: 'medium', format: { type: 'json_schema', schema } },
      messages: [{ role: 'user', content: 'Write the caption for this post' +
        '. The post and the team\'s notes follow as JSON.\n\n' + JSON.stringify(data) }]
    } as Anthropic.MessageCreateParamsNonStreaming, { timeout: 110000, maxRetries: 0 });
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
    if (!out || typeof out.caption !== 'string') {
      console.error('caption-draft: no caption in the answer', res.stop_reason);
      await done(false);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    await done(true);
    const answer: Record<string, unknown> = { caption: clean(out.caption) };
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
