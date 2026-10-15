/*
 * checklist-draft — Write with AI on a client's Pre-Advertising Checklist
 * (2026-10-15).
 *
 * The checklist's Write with AI (js/checklists.js) posts the client's id,
 * what the team knows up front (the monthly ad budget, the objective, where
 * the ads send people, the ad account, the countries) and the colleague's
 * optional notes. The function reads, as the caller and under the caller's
 * own access (Clients at Work on a client in scope): the client (industry,
 * market, website, the brief), the checklist as it stands (open, ver. r1.2
 * or the template it began with), the latest confirmed Brand analysis (it
 * refuses `no-analysis` without one), the Ad benchmarks (Business settings)
 * and whether the client links Meta ad accounts. Claude answers every field
 * the checklist asks that is not a tick, held to the template's own choices
 * by structured output, following the team's client analysis playbook's
 * Meta rules. Nothing is written: the page shows the answers for the
 * colleague to choose, and saves those chosen item by item through
 * `client_checklist_set` after the AI declaration.
 *
 * The client's name goes to Claude as {brand} and comes back as {brand},
 * filled on the page; an email address or a number typed into the team's
 * words or the analysis is masked; no contact is read. No web search.
 *
 * Every press is counted by the database before Claude is asked
 * (`ai_checklist_claim`), marked done or failed after (`ai_draft_done`), and
 * its tokens kept (`ai_draft_tokens`).
 *
 * Secrets: ANTHROPIC_API_KEY, CHECKLIST_MODEL (unset, claude-opus-5-5),
 * plus the platform's SUPABASE_URL and SUPABASE_ANON_KEY. Deploy with Verify
 * JWT off, as every console function.
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
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...cors(origin) } });
}
/* The answer once ready, the connection held open by a space every few
   seconds meanwhile (JSON allows leading whitespace). */
function held(work: Promise<unknown>, origin: string | null) {
  const enc = new TextEncoder();
  const stream = new ReadableStream({
    start(ctl) {
      const tick = setInterval(() => { try { ctl.enqueue(enc.encode(' ')); } catch { /* closed */ } }, 8000);
      work.then((b) => b, (e) => { console.error('checklist-draft: failed', String((e as Error)?.message || e)); return { error: 'ai-failed' }; })
        .then((b) => { clearInterval(tick); ctl.enqueue(enc.encode(JSON.stringify(b))); ctl.close(); });
    }
  });
  return new Response(stream, { status: 200, headers: { 'Content-Type': 'application/json', ...cors(origin) } });
}
function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
const text = (v: unknown, n: number) => String(v ?? '').replace(/\r/g, '').trim().slice(0, n);
const scrub = (s: string) => s
  .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, '[email]')
  .replace(/(\+?\d[\d\s-]{7,}\d)/g, '[number]');
const words = (v: unknown, n: number) => scrub(text(v, n));
const reEsc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/* ---- What Claude is told ------------------------------------------------- */
const SYSTEM = `You are a senior performance marketer at ADspace, a digital marketing agency in Johor Bahru serving clients in Malaysia and Singapore. You fill in a client's Pre-Advertising Checklist for the team: the campaign readiness check completed before ads go live. A colleague reads every answer, keeps the ones that are right and confirms them. Answer from the confirmed brand analysis, the brief, the team's inputs and the benchmarks given; never from a guess.

FIELDS
Fill every field the schema asks. A field with choices takes only those choices. Leave a field empty ("" or []) where nothing given supports an answer, and say what to confirm in Other Remarks instead.
Campaign Details, Main Objective: the objectives this campaign runs, the team's objective first.
Meta Campaign Setup, Campaign Setup: one row an ad set, two to five rows. Item names the ad set (objective and place, for example "Leads, Johor Bahru 10 km"); Details says what runs in it (formats, the hook or angle, how many creatives); Audience says who it reaches (age band, place, interests or the custom audience); CTA is Meta's call to action button (Learn More, Send Message, Get Quote, Sign Up, Book Now, Shop Now, Call Now); A/Spend is the ad spend a month for that ad set in RM.
Targeting: Age Group, Ethnicity (only where the brand analysis or the brief supports it, else empty), Country, Ad Frequency, Ad Scheduling, Ad Placement, Ad Re-Targeting.
Tracking: what the pixel or analytics connects to, the external site where there is one, what is tracked, and how often the ads are reported.
Competitor Analysis: direct, indirect, legacy and disruptor competitors from the brand analysis's competitor map; Strengths, Weaknesses, Opportunities and Threats from its SWOT; Product, Price, Promotion and Place, comparing the competitors' approach with the client's position. One point a line.
Other Remarks: what must be fixed before paid traffic is sent, the budget realism, and what is still to confirm with the client, one point a line.

META RULES (from the team's playbook; apply them)
1. The budget given is inclusive of Meta's tax: the ad spend that reaches Meta (A/Spend) is the budget times the ad spend share given in the benchmarks. The A/Spend of the rows adds up to that figure, never to the whole budget.
2. Each ad set takes at least the least daily budget given in the benchmarks (RM a day, about 30 days a month). Never plan more ad sets than the ad spend carries; merge them instead.
3. An ad set needs about 50 results a week to leave the learning phase; at the benchmark cost per result, say in Other Remarks whether the budget reaches it.
4. A frequency cap is set only on a Reach objective; otherwise Ad Frequency says to let Meta optimise and to watch frequency above 3 a week.
5. Split ad sets by geography where the places differ in price, distance or language (for example Johor Bahru and Singapore), never by tiny audiences.
6. An awareness objective brings incidental leads; never promise leads from it.
7. A new ad account starts with conservative budgets and broad audiences; a mature one may use lookalikes and retargeting of past engagers.
8. Retargeting excludes leads already in the client's CRM where a list exists.
9. A lead form is an Instant Form with higher intent questions, synced to the CRM within 5 minutes; a WhatsApp destination needs someone answering within working hours.
10. Placements are Advantage+ or Facebook and Instagram feeds, Stories and Reels; Audience Network is excluded.
11. The pixel and Conversions API are installed and the domain verified before conversion objectives run.

STANDARDS
Specific to this client and its market (Malaysia and Singapore), never generic. Use the benchmarks as benchmarks, never as the client's own results. Never invent a figure; a figure comes from the inputs, the benchmarks or the brand analysis. Never name a person who works for the client or a customer; never give a phone number or an email address. The client is called {brand}; write {brand} where its name belongs.
Style: British English, plain and professional, short. No dashes as punctuation. These names are always written exactly so: S P Setia, CraftStone, Home Leader, The Mill International, EV SUN, Foodince, Furiku Matcha, HKL Lim, HKL Lim Motorsport, Star Living, Niro Granite, Dale & Cecil, Dale, Gadang Holdings Berhad, ADspace.

Call submit_checklist once with every field. Do not write the answer as text.`;

// deno-lint-ignore no-explicit-any
type Item = { key: string; kind: string; label: string; choices?: string[]; columns?: [string, string][] };
/* The schema is the template's own: every field that is not a tick, its
   choices an enum, a table's rows its own columns. */
// deno-lint-ignore no-explicit-any
function schemaOf(sections: any[], off: string[]) {
  const props: Record<string, unknown> = {};
  const fields: Record<string, Item> = {};
  sections.forEach((s) => {
    if (off.indexOf(s.key) > -1) return;
    (s.items || []).forEach((it: Item) => {
      if (it.kind === 'tick') return;
      const k = s.key + '.' + it.key;
      fields[k] = it;
      const d = s.title + ': ' + it.label;
      if (it.kind === 'text') props[k] = { type: 'string', description: d };
      else if (it.kind === 'choice') props[k] = { type: 'string', enum: ['', ...(it.choices || [])], description: d };
      else if (it.kind === 'multi') props[k] = { type: 'array', items: { type: 'string', enum: it.choices || [] }, description: d };
      else if (it.kind === 'table') {
        const cols = it.columns || [];
        props[k] = { type: 'array', description: d + ', one row an ad set', items: {
          type: 'object', additionalProperties: false, required: cols.map((c) => c[0]),
          properties: Object.fromEntries(cols.map((c) => [c[0], { type: 'string', description: c[1] }])) } };
      }
    });
  });
  return { schema: { type: 'object', properties: props, required: Object.keys(props), additionalProperties: false }, fields };
}
/* The answer held to the template, whatever came back. */
// deno-lint-ignore no-explicit-any
function tidy(ans: any, fields: Record<string, Item>) {
  const out: Record<string, unknown> = {};
  Object.keys(fields).forEach((k) => {
    const it = fields[k], v = ans ? ans[k] : null;
    if (it.kind === 'text') { const t = text(v, 4000); if (t) out[k] = t; }
    else if (it.kind === 'choice') { const t = text(v, 200); if (t && (it.choices || []).indexOf(t) > -1) out[k] = t; }
    else if (it.kind === 'multi') {
      const arr = (Array.isArray(v) ? v : []).map((x) => text(x, 200)).filter((x, i, a) => (it.choices || []).indexOf(x) > -1 && a.indexOf(x) === i);
      if (arr.length) out[k] = arr;
    } else if (it.kind === 'table') {
      const cols = (it.columns || []).map((c) => c[0]);
      // deno-lint-ignore no-explicit-any
      const rows = (Array.isArray(v) ? v : []).slice(0, 12).map((r: any) => Object.fromEntries(cols.map((c) => [c, text(r && r[c], 400)])))
        .filter((r: Record<string, string>) => cols.some((c) => r[c]));
      if (rows.length) out[k] = rows;
    }
  });
  return out;
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  if (!secret('ANTHROPIC_API_KEY')) return json({ error: 'ai-not-set-up', missing: ['ANTHROPIC_API_KEY'] }, 200, origin);
  const model = secret('CHECKLIST_MODEL') || 'claude-opus-5-5';

  const body = await req.json().catch(() => ({}));
  const clientId = String(body && body.client_id || '');
  if (!/^[0-9a-f-]{36}$/i.test(clientId)) return json({ error: 'bad-request' }, 400, origin);
  const notes = words(body && body.notes, 3000);
  const inRaw = (body && typeof body.inputs === 'object' && body.inputs) || {};
  const pick = (v: unknown, ok: string[]) => (ok.indexOf(String(v || '')) > -1 ? String(v) : null);
  const budgetIn = Number(inRaw.budget);
  const inputs = {
    objective: pick(inRaw.objective, ['Awareness', 'Leads', 'Sales', 'Traffic']),
    destination: pick(inRaw.destination, ['Instant Form', 'WhatsApp', 'Messenger', 'Website']),
    monthly_ad_budget_rm: isFinite(budgetIn) && budgetIn > 0 && budgetIn <= 10000000 ? Math.round(budgetIn * 100) / 100 : null,
    ad_account: pick(inRaw.account, ['new', 'mature']) === 'new' ? 'New ad account' : pick(inRaw.account, ['new', 'mature']) === 'mature' ? 'Ad account that has run ads before' : null,
    countries: (Array.isArray(inRaw.countries) ? inRaw.countries : []).map((x: unknown) => text(x, 60)).slice(0, 4)
  };

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
  const may = await db.rpc('allowed', { p_section: 'clients', p_level: 'work' });
  if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);
  const cl = await db.from('clients').select('id, name, industry, market, website, brief').eq('id', clientId).maybeSingle();
  if (cl.error || !cl.data) return json({ error: 'client-scope' }, 200, origin);
  const c = cl.data as Record<string, unknown>;

  /* The checklist as it stands: open and the colleague's to change. */
  const ck = await db.rpc('client_checklist', { p_client: clientId, p_kind: 'pre_ads' });
  if (ck.error) return json({ error: 'needs-update' }, 200, origin);
  const d = (ck.data || {}) as Record<string, unknown>;
  if (d.error) return json({ error: String(d.error) }, 200, origin);
  if (d.status !== 'open' || d.can_work !== true) return json({ error: 'locked' }, 200, origin);

  /* The confirmed Brand analysis, before anything is counted. */
  const ba = await db.rpc('brand_analyses_list', { p_client: clientId });
  const vers = (ba.data && (ba.data as Record<string, unknown>).versions) as Record<string, unknown>[] | undefined;
  if (ba.error || !Array.isArray(vers)) return json({ error: 'needs-update' }, 200, origin);
  const confirmed = vers.find((v) => v.confirmed_at);
  if (!confirmed) return json({ error: 'no-analysis' }, 200, origin);

  const claim = await db.rpc('ai_checklist_claim', { p_client: clientId });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const pressId = String(got.id || '');
  const done = (ok: boolean) => db.rpc('ai_draft_done', { p_id: pressId, p_ok: ok }).then(() => null, () => null);

  return held((async () => {
    const started = Date.now();
    const name = text(c.name, 160);
    const mask = (s: string) => name ? s.replace(new RegExp(reEsc(name), 'gi'), '{brand}') : s;
    const clean = (v: unknown): unknown => typeof v === 'string' ? mask(scrub(v))
      : Array.isArray(v) ? v.map(clean) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, clean(x)])) : v;

    const benchmarks: Record<string, number> = {};
    const st = await db.rpc('app_settings_read');
    if (!st.error && st.data && Array.isArray((st.data as Record<string, unknown>).settings)) {
      const today = String((st.data as Record<string, unknown>).today || new Date(Date.now() + 8 * 36e5).toISOString().slice(0, 10));
      ((st.data as Record<string, unknown>).settings as { key: string; from: string; value: number }[])
        .filter((r) => /^bench_/.test(r.key) && r.from <= today).sort((x, y) => (x.from < y.from ? -1 : 1))
        .forEach((r) => { benchmarks[r.key] = Number(r.value); });
    }
    const lk = await db.rpc('meta_links_list', { p_client: clientId });
    const link = lk && !lk.error && lk.data && !(lk.data as Record<string, unknown>).error
      ? (((lk.data as Record<string, unknown>).links || []) as Record<string, unknown>[]).find((x) => !x.brand_id) : null;

    const sections = (d.sections || []) as Record<string, unknown>[];
    const off = (d.sections_na || []) as string[];
    const { schema, fields } = schemaOf(sections, off);
    const answers = (d.answers || {}) as Record<string, { value?: unknown }>;
    const now: Record<string, unknown> = {};
    Object.keys(fields).forEach((k) => { if (answers[k] && answers[k].value != null) now[k] = answers[k].value; });
    const brief = (c.brief && typeof c.brief === 'object') ? c.brief as Record<string, unknown> : {};

    const data = clean({
      industry: text(c.industry, 120) || null,
      market: String(c.market || '').toUpperCase() === 'SG' ? 'Singapore' : 'Malaysia',
      website: text(c.website, 300) || null,
      brief: Object.fromEntries(['audience', 'pains', 'pillars', 'tone', 'competitors'].map((k) => [k, text(brief[k], 1000)]).filter(([, v]) => v)),
      team_inputs: inputs, team_notes: notes || null,
      brand_analysis: confirmed.analysis, analysis_is_hypothesis: !!confirmed.hypothesis,
      benchmarks, meta_ad_accounts_linked: link ? ((link.ad_accounts || []) as unknown[]).length : 0,
      checklist_now: now
    });

    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY') });
    const SUBMIT = { name: 'submit_checklist', description: 'Submit every field of the checklist.', strict: true, input_schema: schema };
    let input = 0, output = 0, usedModel = model;
    // deno-lint-ignore no-explicit-any
    let answer: any = null;
    try {
      const res = await client.messages.create({
        model, max_tokens: 12000, system: SYSTEM, tools: [SUBMIT], tool_choice: { type: 'auto' },
        output_config: { effort: 'medium' },
        messages: [{ role: 'user', content: 'Fill in the Pre-Advertising Checklist for {brand}. What is known follows as JSON.\n\n' + JSON.stringify(data) }]
      } as unknown as Anthropic.MessageCreateParamsNonStreaming, { timeout: 130000 });
      // deno-lint-ignore no-explicit-any
      const u: any = res.usage || {};
      input = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
      output = u.output_tokens || 0;
      usedModel = res.model || usedModel;
      // deno-lint-ignore no-explicit-any
      for (const b of res.content as any[]) if (b.type === 'tool_use' && b.name === 'submit_checklist') answer = b.input;
    } catch (e) {
      const err = e as { status?: number; message?: string; error?: { error?: { message?: string } } };
      const msg = err.error?.error?.message || err.message || '';
      console.error('checklist-draft: Claude API refused', err.status, msg);
      await db.rpc('ai_draft_tokens', { p_id: pressId, p_in: input, p_out: output, p_model: usedModel }).then(() => null, () => null);
      await done(false);
      return { error: err.status === 401 || err.status === 403 ? 'ai-key' : err.status === 429 || err.status === 529 ? 'ai-busy'
        : /credit balance/i.test(msg) ? 'ai-credit' : err.status === 404 ? 'ai-model' : /timed? ?out/i.test(msg) ? 'ai-slow' : 'ai-failed' };
    }
    await db.rpc('ai_draft_tokens', { p_id: pressId, p_in: input, p_out: output, p_model: usedModel }).then(() => null, () => null);
    const fill = tidy(answer, fields);
    if (!answer || !Object.keys(fill).length) { await done(false); return { error: Date.now() - started > 120000 ? 'ai-slow' : 'ai-incomplete' }; }
    await done(true);
    return { fill, left: got.left };
  })(), origin);
});
