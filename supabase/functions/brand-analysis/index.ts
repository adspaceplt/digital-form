/*
 * brand-analysis — an AI analysis of a client's brand for its Brand pane
 * (2026-10-10).
 *
 * Run analysis on a client's Brand pane (js/crm.js) posts the client's id and
 * the colleague's optional notes. The function reads, as the caller and under
 * the caller's own access (Clients View on a client the colleague sees): the
 * client (its brand name, industry, market, website, handles, content brief,
 * brand notes, the services it holds), its published reports' commentary and
 * figures, My Work's post results, and, where the client links Meta and Meta
 * checks are on for the caller (`meta_checks_on()`), Meta itself through the
 * system user's token as `meta-import` does: the last six months' Instagram
 * and Facebook posts with their figures, the Instagram followers by age,
 * gender and city, and the ad accounts' results by objective and age band.
 * A part the caller may not read, or Meta refusing, is left out and said in
 * `basis`.
 *
 * Claude is given the brand name (the user allowed it for this function
 * alone, 2026-10-10, so it can research the brand on the web) and never a
 * contact's name, phone or email: no contact is read, and an address or a
 * number typed into the team's words is masked. Claude's web search (capped)
 * reads the brand's own site and public pages and its competitors' public
 * presence; the pages it used come back as sources, kept only where the
 * search returned them.
 *
 * Every press is counted by the database before Claude is asked
 * (`ai_analysis_claim`: the colleague's analyses a day, apart from every
 * other AI use), marked done or failed after (`ai_draft_done`), and what it
 * cost is kept on its row (`ai_draft_tokens`, `ai_draft_searches`). The
 * analysis is kept as the next version (`brand_analysis_save`); it stays a
 * draft until a colleague declares it read and confirmed on the page.
 *
 * The answer can take a minute or two, so the response is streamed: a space
 * every few seconds keeps the connection open, then the JSON.
 *
 * Secrets: ANTHROPIC_API_KEY, ANALYSIS_MODEL (the model id; unset, it is
 *          claude-opus-5-5), META_SYSTEM_TOKEN, META_APP_SECRET and
 *          META_GRAPH_VERSION (as meta-import; without the token Meta is
 *          left out), plus the platform's SUPABASE_URL and SUPABASE_ANON_KEY.
 *
 * A refusal the person can act on answers 200 with { error }, so the page
 * names it; a non-2xx is kept for a malformed request. Deploy with Verify JWT
 * off, as every console function.
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
/* The answer once it is ready, the connection held open by a space every
   few seconds meanwhile (JSON allows leading whitespace). */
function held(work: Promise<unknown>, origin: string | null) {
  const enc = new TextEncoder();
  const stream = new ReadableStream({
    start(ctl) {
      const tick = setInterval(() => { try { ctl.enqueue(enc.encode(' ')); } catch { /* closed */ } }, 8000);
      work.then((body) => body, (e) => { console.error('brand-analysis: failed', String((e as Error)?.message || e)); return { error: 'ai-failed' }; })
        .then((body) => { clearInterval(tick); ctl.enqueue(enc.encode(JSON.stringify(body))); ctl.close(); });
    }
  });
  return new Response(stream, { status: 200, headers: { 'Content-Type': 'application/json', ...cors(origin) } });
}
function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }

const text = (v: unknown, n: number) => String(v ?? '').replace(/\r/g, '').trim().slice(0, n);
/* No contact detail leaves: an email address or a phone number typed into
   the team's words, a caption or a brief is masked. */
const scrub = (s: string) => s
  .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, '[email]')
  .replace(/(\+?\d[\d\s-]{7,}\d)/g, '[number]');
const words = (v: unknown, n: number) => scrub(text(v, n));

/* ---- Meta, read as meta-import reads it ---------------------------------- */
class MetaError extends Error {
  body: unknown;
  constructor(body: unknown) { super('meta'); this.body = body; }
}
const TOKEN = () => secret('META_SYSTEM_TOKEN');
const VERSION = () => (secret('META_GRAPH_VERSION') || 'v26.0').replace(/^(\d)/, 'v$1');
let proof: string | null | undefined;
async function appProof(): Promise<string | null> {
  if (proof !== undefined) return proof;
  const key = secret('META_APP_SECRET');
  if (!key) { proof = null; return proof; }
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(TOKEN()));
  proof = Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('');
  return proof;
}
async function graph(path: string, params: Record<string, string> = {}, token = TOKEN()): Promise<Record<string, unknown>> {
  const url = /^https:/.test(path) ? new URL(path) : new URL('https://graph.facebook.com/' + VERSION() + '/' + path.replace(/^\//, ''));
  Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  if (!url.searchParams.get('access_token')) url.searchParams.set('access_token', token);
  const p = token === TOKEN() ? await appProof() : null;
  if (p && !url.searchParams.get('appsecret_proof')) url.searchParams.set('appsecret_proof', p);
  const res = await fetch(url.toString());
  const body = await res.json().catch(() => ({}));
  if (!res.ok || (body && (body as Record<string, unknown>).error)) throw new MetaError(body);
  return body as Record<string, unknown>;
}
async function all(path: string, params: Record<string, string>, max: number, token?: string, stop?: (row: Record<string, unknown>) => boolean) {
  const out: Record<string, unknown>[] = [];
  let next: string | null = path, first = true;
  for (let i = 0; next && i < max; i++) {
    const body = await graph(next, first ? params : {}, token);
    first = false;
    let done = false;
    for (const r of (body.data || []) as Record<string, unknown>[]) { if (stop && stop(r)) { done = true; break; } out.push(r); }
    const pg = body.paging as Record<string, unknown> | undefined;
    next = !done && pg && typeof pg.next === 'string' ? pg.next : null;
  }
  return out;
}
/* A lifetime metric for many media at once, left out where Meta refuses it. */
async function metric(ids: string[], name: string): Promise<Record<string, number | null>> {
  const out: Record<string, number | null> = {};
  for (let i = 0; i < ids.length; i += 50) {
    const part = ids.slice(i, i + 50);
    try {
      const body = await graph('', { ids: part.join(','), fields: 'insights.metric(' + name + ')' });
      part.forEach((id) => {
        // deno-lint-ignore no-explicit-any
        const d: any = ((body[id] || {}) as Record<string, unknown>).insights;
        const v = d && d.data && d.data[0] && d.data[0].values && d.data[0].values[0] ? Number(d.data[0].values[0].value) : null;
        out[id] = v != null && isFinite(v) ? v : null;
      });
    } catch { part.forEach((id) => { out[id] = null; }); }
  }
  return out;
}
/* Instagram's followers by one breakdown: the top answers with their counts. */
async function followersBy(ig: string, breakdown: string, top: number) {
  const body = await graph(ig + '/insights', { metric: 'follower_demographics', period: 'lifetime', metric_type: 'total_value', breakdown });
  // deno-lint-ignore no-explicit-any
  const res: any[] = ((((body.data || []) as any[])[0] || {}).total_value?.breakdowns?.[0]?.results) || [];
  return res.map((r) => ({ [breakdown]: (r.dimension_values || []).join(' '), followers: Number(r.value) || 0 }))
    .sort((a, b) => b.followers - a.followers).slice(0, top);
}
// deno-lint-ignore no-explicit-any
function actionsOf(row: any): Record<string, number> {
  const out: Record<string, number> = {};
  (Array.isArray(row && row.actions) ? row.actions : []).forEach((a: { action_type?: string; value?: string }) => {
    if (a && a.action_type) out[a.action_type] = (out[a.action_type] || 0) + (Number(a.value) || 0);
  });
  return out;
}
const round = (n: number, d = 2) => Math.round(n * Math.pow(10, d)) / Math.pow(10, d);

/* ---- What Claude is told ------------------------------------------------- */
const SYSTEM = `You are a senior marketing strategist at ADspace, a digital marketing agency in Johor Bahru serving clients in Malaysia and Singapore across property, F&B, retail, wellness, lifestyle, automotive and tech. You write a brand analysis of one client for the team: a colleague reads it, checks it and confirms it, and the team then plans content and ads from it. Write it ready to act on, never as a generic marketing lesson.

RESEARCH
Use web search to research the brand in depth before you write: its own website, its social pages, reviews and listings (Google reviews, marketplaces, property portals, food guides where relevant), recent news, and the public presence of two to four of its closest competitors in the same market (their positioning, offers, content and visible ads). Search in the market given, and in Chinese or Malay as well where the brand or its audience uses them. Prefer the brand's own pages and recent sources. Cite only pages you actually read in sources, each with its address and a short title.

WHAT TO WRITE
Brand positioning: what the brand stands for now, in a sentence or two from what you read; what it could own, one sharper position that is credible and not already taken by a competitor; the competitors you compared it with.
Target audiences: two or three segments, each with who they are (age, life stage, location in the market), their pain points, their motivations to buy, and the platforms and times they are most reachable (for example weekday evenings 8pm to 11pm on Instagram).
SWOT: three to five points in each. Tie each point to a figure, a post, a review or a page wherever one exists (for example "Reels average 4,200 views against 900 for photos"). Strengths and weaknesses are the brand's own advantages and disadvantages against its competitors; opportunities and threats come from the market, the competitors and the season.
Content: what worked and what did not, from the post figures and the reports given (name the post or the format and its figure); the content pillars to lean on (three to five, each one line naming the angle, not a topic word); the formats to lean on, each with why.
Ad targeting: the objectives to run and why; the age bands to target, from the follower and ad figures where given; interests and behaviours to target, specific to Meta's targeting; placements; a budget split by objective as whole percentages adding up to 100; one line on what to test first.

STANDARDS
Specific, local and ownable. Never generic advice such as "post product photos", "run a giveaway", "share testimonials" or "create awareness" unless it is developed into a sharp idea with its hook and its reason. Benefit first: say what the customer gains, feels or avoids. Consider Malaysia and Singapore buying behaviour, bilingual audiences (English, Chinese, Malay) and the festive calendar (Chinese New Year, Hari Raya Aidilfitri, Deepavali, Christmas, Mid-Autumn, the year-end sales, 11.11, 12.12) where they matter to this brand.
Truth: never invent a figure, a price, an award, a review or a claim. A figure comes from the data given or a page you cite. Where the data does not show something, say what to test rather than guess. Never name or describe a person who works for the client or a customer; never give a phone number or an email address.
Where the data shows little history (no reports, no post results, no Meta figures), write the same sections from the brief, the industry, the market and your research, as a starting hypothesis to test, and say in each section what to measure first.
Style: British English, plain and professional, short points, one idea a point. No dashes as punctuation. These brand names are always written exactly so: S P Setia, CraftStone, Home Leader, The Mill International, EV SUN, Foodince, Furiku Matcha, HKL Lim, HKL Lim Motorsport, Star Living, Niro Granite, Dale & Cecil, Dale, ADspace.

When the research is done, call submit_analysis once with the whole analysis. Do not write the analysis as text.`;

const str = (d: string) => ({ type: 'string', description: d });
const list = (d: string) => ({ type: 'array', description: d, items: { type: 'string' } });
const obj = (properties: Record<string, unknown>) => ({ type: 'object', properties, required: Object.keys(properties), additionalProperties: false });
const SCHEMA = obj({
  positioning: obj({ now: str('What the brand stands for now'), could_own: str('The sharper position it could own'),
    competitors: list('The competitors compared, by name') }),
  audiences: { type: 'array', description: 'Two or three segments', items: obj({
    name: str('A short name for the segment'), who: str('Who they are'), pains: str('Their pain points'),
    motivations: str('Their motivations to buy'), reach: str('The platforms and times they are most reachable') }) },
  swot: obj({ strengths: list('Strengths'), weaknesses: list('Weaknesses'), opportunities: list('Opportunities'), threats: list('Threats') }),
  content: obj({ worked: list('What worked, with its figure'), not_worked: list('What did not work, with its figure'),
    pillars: list('Content pillars to lean on'), formats: list('Formats to lean on, each with why') }),
  ads: obj({ objectives: list('Objectives to run, each with why'), ages: list('Age bands to target'),
    interests: list('Interests and behaviours to target'), placements: list('Placements'),
    budget: { type: 'array', description: 'Budget split by objective, whole percentages adding up to 100', items: obj({
      objective: str('The objective'), share: { type: 'integer', description: 'Percent of the budget' } }) },
    test: str('What to test first') }),
  sources: { type: 'array', description: 'The web pages read and used', items: obj({ url: str('The address'), title: str('A short title') }) }
});
const SUBMIT = { name: 'submit_analysis', description: 'Submit the finished brand analysis.', strict: true, input_schema: SCHEMA };

const cap = (v: unknown, n: number, len: number) => (Array.isArray(v) ? v : []).map((x) => text(x, len)).filter(Boolean).slice(0, n);
/* The answer held to its shape and its lengths, whatever came back. */
// deno-lint-ignore no-explicit-any
function tidy(a: any) {
  a = a || {};
  const p = a.positioning || {}, s = a.swot || {}, c = a.content || {}, d = a.ads || {};
  const budget = (Array.isArray(d.budget) ? d.budget : []).slice(0, 8)
    // deno-lint-ignore no-explicit-any
    .map((b: any) => ({ objective: text(b && b.objective, 80), share: Math.max(0, Math.min(100, Math.round(Number(b && b.share) || 0))) }))
    .filter((b: { objective: string; share: number }) => b.objective && b.share > 0);
  const sum = budget.reduce((t: number, b: { share: number }) => t + b.share, 0);
  if (sum > 0 && sum !== 100) {
    budget.forEach((b: { share: number }) => { b.share = Math.round(b.share * 100 / sum); });
    const drift = 100 - budget.reduce((t: number, b: { share: number }) => t + b.share, 0);
    if (budget.length) budget[0].share += drift;
  }
  return {
    positioning: { now: text(p.now, 1200), could_own: text(p.could_own, 1200), competitors: cap(p.competitors, 6, 120) },
    // deno-lint-ignore no-explicit-any
    audiences: (Array.isArray(a.audiences) ? a.audiences : []).slice(0, 3).map((x: any) => ({
      name: text(x && x.name, 120), who: text(x && x.who, 600), pains: text(x && x.pains, 800),
      motivations: text(x && x.motivations, 800), reach: text(x && x.reach, 600) })).filter((x: { name: string }) => x.name),
    swot: { strengths: cap(s.strengths, 6, 500), weaknesses: cap(s.weaknesses, 6, 500),
            opportunities: cap(s.opportunities, 6, 500), threats: cap(s.threats, 6, 500) },
    content: { worked: cap(c.worked, 6, 500), not_worked: cap(c.not_worked, 6, 500), pillars: cap(c.pillars, 6, 300), formats: cap(c.formats, 6, 400) },
    ads: { objectives: cap(d.objectives, 6, 400), ages: cap(d.ages, 6, 200), interests: cap(d.interests, 12, 200),
           placements: cap(d.placements, 8, 200), budget, test: text(d.test, 600) }
  };
}
const urlKey = (u: string) => u.replace(/^https?:\/\/(www\.)?/i, '').replace(/[?#].*$/, '').replace(/\/$/, '').toLowerCase();

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);

  if (!secret('ANTHROPIC_API_KEY')) return json({ error: 'ai-not-set-up', missing: ['ANTHROPIC_API_KEY'] }, 200, origin);
  const model = secret('ANALYSIS_MODEL') || 'claude-opus-5-5';

  const body = await req.json().catch(() => ({}));
  const clientId = String(body && body.client_id || '');
  if (!/^[0-9a-f-]{36}$/i.test(clientId)) return json({ error: 'bad-request' }, 400, origin);
  const notes = words(body && body.notes, 3000);

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });

  const may = await db.rpc('allowed', { p_section: 'clients', p_level: 'view' });
  if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);
  const cl = await db.from('clients')
    .select('id, name, industry, market, website, handle_ig, handle_fb, handle_tiktok, handle_xhs, brand_notes, brief, stage')
    .eq('id', clientId).maybeSingle();
  if (cl.error || !cl.data) return json({ error: 'client-scope' }, 200, origin);
  const c = cl.data as Record<string, unknown>;

  /* Count the press before anything is read past the client itself. */
  const claim = await db.rpc('ai_analysis_claim', { p_client: clientId });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const pressId = String(got.id || '');
  const done = (ok: boolean) => db.rpc('ai_draft_done', { p_id: pressId, p_ok: ok }).then(() => null, () => null);

  return held((async () => {
    const started = Date.now();
    const basis: Record<string, unknown> = {};
    const market = String(c.market || '').toUpperCase() === 'SG' ? 'Singapore' : 'Malaysia';
    const since = new Date(Date.now() - 182 * 864e5);

    /* Each part read as the caller; one refused is left out. */
    const svc = await db.from('client_services').select('label, state').eq('client_id', clientId).is('archived_at', null);
    const services = svc.error ? [] : (svc.data || []).filter((x: Record<string, unknown>) => x.state !== 'enquired')
      .map((x: Record<string, unknown>) => text(x.label, 120) + ' · ' + String(x.state || ''));

    const rp = await db.from('sm_reports').select('id, kind, period_start, period_end, intro, insights, ads_totals')
      .eq('client_id', clientId).eq('status', 'published').order('period_end', { ascending: false }).limit(6);
    const reps = rp.error ? [] : (rp.data || []) as Record<string, unknown>[];
    basis.reports = rp.error ? 'not-read' : reps.length;
    const ids = reps.map((r) => String(r.id));
    // deno-lint-ignore no-explicit-any
    let plats: any[] = [], ads: any[] = [], posts: any[] = [];
    if (ids.length) {
      const pf = await db.from('sm_report_platforms').select('report_id, platform, platform_name, metrics, followers_start, followers_end, summary, worked, improve, actions').in('report_id', ids);
      plats = pf.error ? [] : pf.data || [];
      const ad = await db.from('sm_report_ads').select('report_id, name, objective, result_label, spend, results, reach, impressions, ctr, cpr, age, platform').in('report_id', ids).limit(120);
      ads = ad.error ? [] : ad.data || [];
      const po = await db.from('sm_report_posts').select('report_id, posted_on, title, caption, content_type, views, reach, engagements').in('report_id', ids).order('views', { ascending: false }).limit(40);
      posts = po.error ? [] : po.data || [];
    }
    const reports = reps.map((r) => ({
      kind: r.kind === 'ads' ? 'Advertising report' : 'Social media accounts report',
      period: String(r.period_start).slice(0, 10) + ' to ' + String(r.period_end).slice(0, 10),
      summary: words(r.intro, 2000) || null,
      insights: r.insights && typeof r.insights === 'object'
        ? Object.fromEntries(Object.entries(r.insights as Record<string, unknown>).map(([k, v]) => [k, words(v, 1500)]).filter(([, v]) => v)) : null,
      totals: r.kind === 'ads' ? r.ads_totals || null : null,
      platforms: plats.filter((p) => p.report_id === r.id).map((p) => ({
        platform: p.platform_name || p.platform, metrics: p.metrics || null, followers: [p.followers_start, p.followers_end],
        summary: words(p.summary, 800) || null, worked: words(p.worked, 800) || null, improve: words(p.improve, 800) || null })),
      ads: ads.filter((a) => a.report_id === r.id).slice(0, 25).map((a) => ({
        ad: text(a.name, 120).replace(/_\d{3}$/, ''), objective: a.objective, result: a.result_label, spend: a.spend, results: a.results,
        reach: a.reach, impressions: a.impressions, ctr: a.ctr, cost_per_result: a.cpr, age: a.age, platform: a.platform })),
      top_posts: posts.filter((p) => p.report_id === r.id).slice(0, 8).map((p) => ({
        day: p.posted_on, type: p.content_type, title: words(p.title, 120) || null, caption: words(p.caption, 300) || null,
        views: p.views, reach: p.reach, engagements: p.engagements }))
    }));

    const rs = await db.from('ops_tasks').select('title, content_desc, deliverable_type, live_at, result_views, result_engagements')
      .eq('client_id', clientId).not('result_views', 'is', null).order('live_at', { ascending: false }).limit(40);
    const results = rs.error ? [] : (rs.data || []).map((t: Record<string, unknown>) => ({
      post: words(t.content_desc || t.title, 160), format: t.deliverable_type || null, live: String(t.live_at || '').slice(0, 10) || null,
      views: t.result_views, engagements: t.result_engagements }));
    basis.post_results = rs.error ? 'not-read' : results.length;

    /* Meta, only where the switch and the part allow it for the caller and
       the client links what is read. */
    const meta: Record<string, unknown> = {};
    const on = await db.rpc('meta_checks_on');
    const lk = on.data === true && TOKEN() ? await db.rpc('meta_links_list', { p_client: clientId }) : null;
    const link = lk && !lk.error && lk.data && !(lk.data as Record<string, unknown>).error
      ? (((lk.data as Record<string, unknown>).links || []) as Record<string, unknown>[]).find((x) => !x.brand_id) : null;
    const metaSaid: Record<string, string> = {};
    if (!link) basis.meta = on.data === true && TOKEN() ? 'not-linked' : 'off';
    else {
      const ig = link.instagram as { id: string } | null, page = link.page as { id: string } | null;
      const acts = ((link.ad_accounts || []) as { id: string; name: string }[]).slice(0, 3);
      if (ig && ig.id) {
        try {
          const acc = await graph(ig.id, { fields: 'username,followers_count,media_count,biography' });
          const media = await all(ig.id + '/media', { fields: 'id,caption,media_type,media_product_type,timestamp,like_count,comments_count', limit: '60' }, 3, undefined,
            (x) => Date.parse(String(x.timestamp).replace(/\+0000$/, 'Z')) < since.getTime());
          const list = media.slice(0, 60), mids = list.map((x) => String(x.id));
          const views = mids.length ? await metric(mids, 'views') : {}, reach = mids.length ? await metric(mids, 'reach') : {};
          const saved = mids.length ? await metric(mids, 'saved') : {};
          meta.instagram = {
            followers: acc.followers_count, posts_in_all: acc.media_count, bio: words(acc.biography, 400) || null,
            posts: list.map((x) => ({ day: String(x.timestamp).slice(0, 10), type: x.media_product_type === 'REELS' ? 'Reel' : String(x.media_type || '').toLowerCase(),
              caption: words(x.caption, 280), likes: x.like_count, comments: x.comments_count,
              views: views[String(x.id)] ?? null, reach: reach[String(x.id)] ?? null, saves: saved[String(x.id)] ?? null }))
          };
          const demo: Record<string, unknown> = {};
          for (const [b, n] of [['age', 8], ['gender', 3], ['city', 6]] as [string, number][]) {
            try { demo[b] = await followersBy(ig.id, b, n); } catch { /* left out */ }
          }
          if (Object.keys(demo).length) meta.instagram_followers = demo;
        } catch (e) { metaSaid.instagram = 'refused'; console.error('brand-analysis: Instagram', JSON.stringify((e as MetaError).body || {}).slice(0, 300)); }
      }
      if (page && page.id) {
        try {
          const pg = await graph(page.id, { fields: 'access_token,name,followers_count,about' });
          const ptoken = String(pg.access_token || '');
          if (ptoken) {
            const fb = await all(page.id + '/published_posts', {
              fields: 'created_time,message,status_type,shares,reactions.summary(total_count).limit(0),comments.summary(total_count).limit(0)',
              since: String(Math.floor(since.getTime() / 1000)), limit: '50'
            }, 2, ptoken);
            meta.facebook = {
              followers: pg.followers_count, about: words(pg.about, 400) || null,
              // deno-lint-ignore no-explicit-any
              posts: fb.slice(0, 50).map((x: any) => ({ day: String(x.created_time).slice(0, 10), type: x.status_type || null, message: words(x.message, 280),
                reactions: x.reactions?.summary?.total_count ?? null, comments: x.comments?.summary?.total_count ?? null, shares: x.shares?.count ?? 0 }))
            };
          } else metaSaid.facebook = 'not-assigned';
        } catch (e) { metaSaid.facebook = 'refused'; console.error('brand-analysis: Facebook', JSON.stringify((e as MetaError).body || {}).slice(0, 300)); }
      }
      if (acts.length) {
        const range = JSON.stringify({ since: since.toISOString().slice(0, 10), until: new Date().toISOString().slice(0, 10) });
        const byObj: Record<string, Record<string, { spend: number; impressions: number; clicks: number; actions: Record<string, number> }>> = {};
        try {
          for (const a of acts) {
            const rows = await all('act_' + a.id + '/insights', { level: 'campaign', time_range: range, breakdowns: 'age',
              fields: 'objective,spend,impressions,clicks,actions', limit: '500' }, 6);
            rows.forEach((r) => {
              const o = String(r.objective || 'Other'), age = String(r.age || 'Unknown');
              const cell = ((byObj[o] = byObj[o] || {})[age] = byObj[o][age] || { spend: 0, impressions: 0, clicks: 0, actions: {} });
              cell.spend += Number(r.spend) || 0; cell.impressions += Number(r.impressions) || 0; cell.clicks += Number(r.clicks) || 0;
              Object.entries(actionsOf(r)).forEach(([k, v]) => { cell.actions[k] = (cell.actions[k] || 0) + v; });
            });
          }
          meta.ads_last_six_months = Object.entries(byObj).map(([objective, ages]) => ({
            objective,
            by_age: Object.entries(ages).sort((x, y) => x[0].localeCompare(y[0])).map(([age, v]) => ({
              age, spend: round(v.spend), impressions: v.impressions, clicks: v.clicks,
              ctr: v.impressions ? round(v.clicks / v.impressions * 100) : null,
              top_actions: Object.fromEntries(Object.entries(v.actions).sort((x, y) => y[1] - x[1]).slice(0, 3)) }))
          }));
        } catch (e) { metaSaid.ads = 'refused'; console.error('brand-analysis: ads', JSON.stringify((e as MetaError).body || {}).slice(0, 300)); }
      }
      basis.meta = {
        instagram: meta.instagram ? ((meta.instagram as Record<string, unknown[]>).posts || []).length : metaSaid.instagram || null,
        followers: !!meta.instagram_followers,
        facebook: meta.facebook ? ((meta.facebook as Record<string, unknown[]>).posts || []).length : metaSaid.facebook || null,
        ads: meta.ads_last_six_months ? (meta.ads_last_six_months as unknown[]).length : metaSaid.ads || null
      };
    }

    const igPosts = meta.instagram ? ((meta.instagram as Record<string, unknown[]>).posts || []).length : 0;
    const fbPosts = meta.facebook ? ((meta.facebook as Record<string, unknown[]>).posts || []).length : 0;
    const hypothesis = !reps.length && !results.length && !igPosts && !fbPosts && !meta.ads_last_six_months;

    const brief: Record<string, string> = {};
    const rawBrief = (c.brief && typeof c.brief === 'object') ? c.brief as Record<string, unknown> : {};
    for (const k of ['audience', 'pains', 'pillars', 'tone', 'avoid', 'competitors', 'hooks']) {
      const v = words(rawBrief[k], 1000);
      if (v) brief[k] = v;
    }
    const handles: Record<string, string> = {};
    ([['instagram', 'handle_ig'], ['facebook', 'handle_fb'], ['tiktok', 'handle_tiktok'], ['rednote', 'handle_xhs']] as [string, string][])
      .forEach(([k, f]) => { const h = text(c[f], 120); if (h) handles[k] = h; });
    const data = {
      brand: text(c.name, 160), industry: text(c.industry, 120) || null, market,
      website: text(c.website, 300) || null, handles,
      stage: c.stage || null, services,
      brief: Object.keys(brief).length ? brief : null,
      brand_notes: words(c.brand_notes, 1500) || null,
      team_notes: notes || null,
      history: hypothesis ? 'little' : 'some',
      published_reports: reports, post_results: results, meta
    };

    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY') });
    const tools = [
      { type: 'web_search_20260209', name: 'web_search', max_uses: 8,
        user_location: { type: 'approximate', country: market === 'Singapore' ? 'SG' : 'MY',
          timezone: market === 'Singapore' ? 'Asia/Singapore' : 'Asia/Kuala_Lumpur' } },
      SUBMIT
    ];
    // deno-lint-ignore no-explicit-any
    const messages: any[] = [{ role: 'user', content: 'Research and analyse this brand. Its record, reports, post results and Meta figures follow as JSON.\n\n' + JSON.stringify(data) }];
    let input = 0, output = 0, searches = 0, usedModel = model, nudged = false;
    // deno-lint-ignore no-explicit-any
    let answer: any = null;
    const found: Record<string, string> = {};
    try {
      for (let turn = 0; turn < 6 && !answer; turn++) {
        const left = 140000 - (Date.now() - started);
        if (left < 15000) break;
        const res = await client.messages.create({
          model, max_tokens: 16000, system: SYSTEM, tools, tool_choice: { type: 'auto' },
          output_config: { effort: 'medium' }, messages
        } as unknown as Anthropic.MessageCreateParamsNonStreaming, { timeout: left });
        // deno-lint-ignore no-explicit-any
        const u: any = res.usage || {};
        input += (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
        output += u.output_tokens || 0;
        searches += (u.server_tool_use && u.server_tool_use.web_search_requests) || 0;
        usedModel = res.model || usedModel;
        // deno-lint-ignore no-explicit-any
        for (const b of res.content as any[]) {
          if (b.type === 'web_search_tool_result' && Array.isArray(b.content)) {
            b.content.forEach((r: { url?: string; title?: string }) => { if (r && r.url) found[urlKey(r.url)] = text(r.title, 200); });
          }
          if (b.type === 'tool_use' && b.name === 'submit_analysis') answer = b.input;
        }
        if (answer) break;
        if (res.stop_reason === 'pause_turn') { messages.push({ role: 'assistant', content: res.content }); continue; }
        if (res.stop_reason === 'end_turn' && !nudged) {
          nudged = true;
          messages.push({ role: 'assistant', content: res.content });
          messages.push({ role: 'user', content: 'Submit the analysis now with submit_analysis.' });
          continue;
        }
        console.error('brand-analysis: answer stopped short', res.stop_reason);
        break;
      }
    } catch (e) {
      const err = e as { status?: number; message?: string; error?: { error?: { type?: string; message?: string } } };
      const msg = err.error?.error?.message || err.message || '';
      console.error('brand-analysis: Claude API refused', err.status, err.error?.error?.type || '', msg);
      await db.rpc('ai_draft_tokens', { p_id: pressId, p_in: input, p_out: output, p_model: usedModel }).then(() => null, () => null);
      await db.rpc('ai_draft_searches', { p_id: pressId, p_n: searches }).then(() => null, () => null);
      await done(false);
      return { error: err.status === 401 || err.status === 403 ? 'ai-key' : err.status === 429 || err.status === 529 ? 'ai-busy'
        : /credit balance/i.test(msg) ? 'ai-credit' : err.status === 404 ? 'ai-model' : /timed? ?out/i.test(msg) ? 'ai-slow' : 'ai-failed' };
    }
    await db.rpc('ai_draft_tokens', { p_id: pressId, p_in: input, p_out: output, p_model: usedModel }).then(() => null, () => null);
    await db.rpc('ai_draft_searches', { p_id: pressId, p_n: searches }).then(() => null, () => null);
    if (!answer) { await done(false); return { error: Date.now() - started > 120000 ? 'ai-slow' : 'ai-incomplete' }; }

    const analysis = tidy(answer);
    if (!analysis.positioning.now || !analysis.audiences.length) { await done(false); return { error: 'ai-incomplete' }; }
    /* Only pages the search returned are kept as sources. */
    const seen: Record<string, boolean> = {};
    const sources = (Array.isArray(answer.sources) ? answer.sources : [])
      // deno-lint-ignore no-explicit-any
      .map((s: any) => ({ url: text(s && s.url, 500), title: text(s && s.title, 200) }))
      .filter((s: { url: string }) => /^https:\/\//i.test(s.url) && Object.prototype.hasOwnProperty.call(found, urlKey(s.url)) &&
        !seen[urlKey(s.url)] && (seen[urlKey(s.url)] = true))
      .map((s: { url: string; title: string }) => ({ url: s.url, title: s.title || found[urlKey(s.url)] || s.url }))
      .slice(0, 15);
    basis.web_searches = searches;

    const saved = await db.rpc('brand_analysis_save', { p_press: pressId, p_analysis: analysis, p_sources: sources,
      p_basis: basis, p_hypothesis: hypothesis, p_model: usedModel });
    const row = (saved.data || {}) as Record<string, unknown>;
    if (saved.error || row.error) { await done(false); return { error: saved.error ? 'needs-update' : String(row.error) }; }
    await done(true);
    return { analysis: row, left: got.left };
  })(), origin);
});
