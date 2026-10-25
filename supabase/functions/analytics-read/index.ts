/*
 * analytics-read — Write with AI on Analytics (2026-10-25): an analysis of
 * the company's sales and client figures for management.
 *
 * Analytics (js/analytics.js) posts the period it shows, the figures it has
 * already worked out for it (totals, the period before, the changes and the
 * page's own verdicts, months, sources, reasons, industries, markets, the
 * forecast) and the colleague's optional notes. Nothing here reads a client:
 * the figures are counts and shares, never a client's name or a contact.
 * Claude answers a health read, the risks, what is working, whether the
 * forecast is credible, the actions to take and the caveats, held to its
 * fields by structured output.
 *
 * Every figure is the page's: Claude is told to quote only figures given,
 * and every number in its answer is checked against them. A point quoting
 * a number the figures do not hold is left out (counted in `basis`); a
 * headline or summary that does is refused as incomplete.
 *
 * Every press is counted by the database before Claude is asked
 * (`ai_analytics_claim`, team.analytics at Work), its tokens kept
 * (`ai_draft_tokens`) and marked done or failed (`ai_draft_done`); the
 * answer is kept as the next version with the figures it read
 * (`analytics_read_save`).
 *
 * Secrets: ANTHROPIC_API_KEY, ANALYTICS_MODEL (unset, claude-opus-5-5),
 * plus the platform's SUPABASE_URL and SUPABASE_ANON_KEY. Deploy with Verify
 * JWT off, as every console function.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import Anthropic from 'npm:@anthropic-ai/sdk';
import { cors, json } from '../_shared/cors.ts';

/* The answer once ready, the connection held open by a space every few
   seconds meanwhile (JSON allows leading whitespace). */
function held(work: Promise<unknown>, origin: string | null) {
  const enc = new TextEncoder();
  const stream = new ReadableStream({
    start(ctl) {
      const tick = setInterval(() => { try { ctl.enqueue(enc.encode(' ')); } catch { /* closed */ } }, 8000);
      work.then((b) => b, (e) => { console.error('analytics-read: failed', String((e as Error)?.message || e)); return { error: 'ai-failed' }; })
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

/* ---- What Claude is told ------------------------------------------------- */
const SYSTEM = `You are a senior commercial analyst writing for the management of ADspace, a digital marketing agency in Johor Bahru serving clients in Malaysia and Singapore. You read the company's own sales and client figures from its portal and say plainly whether the business is heading the right way, what is going wrong, what is working, and what to do next.

THE FIGURES
You are given JSON the portal worked out for one period and the same span before it: new leads, leads won and lost, win rate, days from lead to client, clients joined and left (churned), active clients, churn as a share of active clients a quarter, leads by source with their wins, why leads were lost, why clients paused or left, active clients by industry and market, how long active clients have stayed, monthly figures, and a forecast where one is drawn. Each comparison carries the portal's own verdict (better, worse or steady, judged against the change threshold given) and churn carries whether it is above the alert set by management. Never contradict a verdict the portal gives; explain it.

WHAT THE DATA CAN AND CANNOT SAY
Before the month named in leads_complete_from, the team entered only the clients it won, never the leads that came to nothing. Win rate, lost leads, lead sources and lead volume before that month are therefore not reliable; never draw a conclusion from them and say so in caveats where it matters. Client figures (joined, left, active, tenure) are reliable for the whole history. A small count (fewer than about five) is a signal to watch, never a trend; say so instead of overstating it.

QUOTING FIGURES
Quote only figures that appear in the data, written as they appear (a share as a whole percentage where the data gives a percentage). Never work out a new figure: no new percentages, differences, averages or projections. Refer to months and periods by name. Every number you write is checked against the data and a point quoting a number it does not hold is removed.

WHAT TO WRITE
health: good, mixed or poor, judged on churn first (above the alert is never good), then active clients, then new clients won, then leads.
headline: one sentence a director reads first, naming the most important movement.
summary: two to four sentences: where the business stands and why.
risks: the problems, most serious first, each with its figures (churn above the alert, more clients leaving than joining, a falling trend, a source drying up, one industry or market carrying too much, a recurring reason clients leave). severity high where it costs revenue now, medium where it will if left, low to watch.
working: what is going well and should be kept, with its figures.
forecast: whether the forecast is credible given the history held (credible, partly or not credible; not drawn where none is given) and why, in two sentences at most.
actions: three to five concrete steps an agency's management can take this month (retention calls with clients in an industry that is leaving, faster follow-up where days to win are long, more effort on the source that wins, a review of the reason clients leave), each with why, tied to a figure.
caveats: what the reader must keep in mind about the data, one sentence each, two at most.

STYLE
British English, formal and plain, short sentences, as a management report here is written. No dashes as punctuation. Never name a client or a person; none are given. ADspace is written exactly so.

Call submit_analysis once. Do not write the answer as text.`;

const SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['health', 'headline', 'summary', 'risks', 'working', 'forecast', 'actions', 'caveats'],
  properties: {
    health: { type: 'string', enum: ['good', 'mixed', 'poor'] },
    headline: { type: 'string' },
    summary: { type: 'string' },
    risks: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['title', 'detail', 'severity'],
      properties: { title: { type: 'string' }, detail: { type: 'string' }, severity: { type: 'string', enum: ['high', 'medium', 'low'] } } } },
    working: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['title', 'detail'],
      properties: { title: { type: 'string' }, detail: { type: 'string' } } } },
    forecast: { type: 'object', additionalProperties: false, required: ['verdict', 'detail'],
      properties: { verdict: { type: 'string', enum: ['credible', 'partly', 'not_credible', 'not_drawn'] }, detail: { type: 'string' } } },
    actions: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['action', 'why'],
      properties: { action: { type: 'string' }, why: { type: 'string' } } } },
    caveats: { type: 'array', items: { type: 'string' } }
  }
};

/* ---- Every number quoted is the figures' own ---------------------------------- */
/* The numbers the figures hold, as a reader may write them: the value, it
   rounded to a whole and to one and two places, a fraction as a percentage,
   and the small counts and years any sentence uses. */
function numbersOf(figures: unknown): Set<string> {
  const out = new Set<string>();
  const add = (v: number) => {
    if (!isFinite(v)) return;
    [v, Math.abs(v)].forEach((x) => {
      [0, 1, 2].forEach((d) => out.add(String(Number(x.toFixed(d)))));
      out.add(String(Math.round(x)));
      if (Math.abs(x) <= 1) [0, 1].forEach((d) => out.add(String(Number((x * 100).toFixed(d)))));
    });
  };
  const walk = (v: unknown): void => {
    if (typeof v === 'number') add(v);
    else if (typeof v === 'string') (v.match(/\d[\d,]*(?:\.\d+)?/g) || []).forEach((s) => add(Number(s.replace(/,/g, ''))));
    else if (Array.isArray(v)) v.forEach(walk);
    else if (v && typeof v === 'object') Object.values(v as Record<string, unknown>).forEach(walk);
  };
  walk(figures);
  for (let i = 0; i <= 24; i++) out.add(String(i));
  for (let y = 2020; y <= 2040; y++) out.add(String(y));
  return out;
}
function quotesOnly(s: string, known: Set<string>): boolean {
  return (s.match(/\d[\d,]*(?:\.\d+)?/g) || []).every((n) => known.has(String(Number(n.replace(/,/g, '')))));
}
// deno-lint-ignore no-explicit-any
function tidy(a: any, known: Set<string>) {
  let dropped = 0;
  const keep = (s: string) => { if (quotesOnly(s, known)) return true; dropped++; return false; };
  const t = (v: unknown, n: number) => text(v, n);
  const out = {
    health: ['good', 'mixed', 'poor'].indexOf(a && a.health) > -1 ? a.health : 'mixed',
    headline: t(a && a.headline, 300),
    summary: t(a && a.summary, 1200),
    // deno-lint-ignore no-explicit-any
    risks: (Array.isArray(a && a.risks) ? a.risks : []).slice(0, 6).map((r: any) => ({ title: t(r && r.title, 140), detail: t(r && r.detail, 600),
      severity: ['high', 'medium', 'low'].indexOf(r && r.severity) > -1 ? r.severity : 'medium' }))
      .filter((r: { title: string; detail: string }) => r.title && keep(r.title + ' ' + r.detail)),
    // deno-lint-ignore no-explicit-any
    working: (Array.isArray(a && a.working) ? a.working : []).slice(0, 5).map((r: any) => ({ title: t(r && r.title, 140), detail: t(r && r.detail, 600) }))
      .filter((r: { title: string; detail: string }) => r.title && keep(r.title + ' ' + r.detail)),
    forecast: {
      verdict: ['credible', 'partly', 'not_credible', 'not_drawn'].indexOf(a && a.forecast && a.forecast.verdict) > -1 ? a.forecast.verdict : 'not_drawn',
      detail: t(a && a.forecast && a.forecast.detail, 500)
    },
    // deno-lint-ignore no-explicit-any
    actions: (Array.isArray(a && a.actions) ? a.actions : []).slice(0, 5).map((r: any) => ({ action: t(r && r.action, 200), why: t(r && r.why, 500) }))
      .filter((r: { action: string; why: string }) => r.action && keep(r.action + ' ' + r.why)),
    caveats: (Array.isArray(a && a.caveats) ? a.caveats : []).slice(0, 3).map((x: unknown) => t(x, 400)).filter((x: string) => x && keep(x))
  };
  if (out.forecast.detail && !keep(out.forecast.detail)) out.forecast.detail = '';
  const whole = !!out.headline && !!out.summary && quotesOnly(out.headline + ' ' + out.summary, known);
  return { out, dropped, whole };
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  if (!secret('ANTHROPIC_API_KEY')) return json({ error: 'ai-not-set-up', missing: ['ANTHROPIC_API_KEY'] }, 200, origin);
  const model = secret('ANALYTICS_MODEL') || 'claude-opus-5-5';

  const body = await req.json().catch(() => ({}));
  const figures = body && typeof body.figures === 'object' && !Array.isArray(body.figures) ? body.figures : null;
  const period = text(body && body.period, 80);
  if (!figures || !period || JSON.stringify(figures).length > 60000) return json({ error: 'bad-request' }, 400, origin);
  const notes = scrub(text(body && body.notes, 2000));

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
  const claim = await db.rpc('ai_analytics_claim');
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const pressId = String(got.id || '');
  const done = (ok: boolean) => db.rpc('ai_draft_done', { p_id: pressId, p_ok: ok }).then(() => null, () => null);

  return held((async () => {
    const started = Date.now();
    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY') });
    const SUBMIT = { name: 'submit_analysis', description: 'Submit the analysis.', strict: true, input_schema: SCHEMA };
    let input = 0, output = 0, usedModel = model;
    // deno-lint-ignore no-explicit-any
    let answer: any = null;
    try {
      const res = await client.messages.create({
        model, max_tokens: 6000, system: SYSTEM, tools: [SUBMIT], tool_choice: { type: 'auto' },
        output_config: { effort: 'medium' },
        messages: [{ role: 'user', content: 'Analyse the figures for ' + period + '.' +
          (notes ? '\n\nManagement\'s notes: ' + notes : '') + '\n\nThe figures follow as JSON.\n\n' + JSON.stringify(figures) }]
      } as unknown as Anthropic.MessageCreateParamsNonStreaming, { timeout: 130000 });
      // deno-lint-ignore no-explicit-any
      const u: any = res.usage || {};
      input = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
      output = u.output_tokens || 0;
      usedModel = res.model || usedModel;
      // deno-lint-ignore no-explicit-any
      for (const b of res.content as any[]) if (b.type === 'tool_use' && b.name === 'submit_analysis') answer = b.input;
    } catch (e) {
      const err = e as { status?: number; message?: string; error?: { error?: { message?: string } } };
      const msg = err.error?.error?.message || err.message || '';
      console.error('analytics-read: Claude API refused', err.status, msg);
      await db.rpc('ai_draft_tokens', { p_id: pressId, p_in: input, p_out: output, p_model: usedModel }).then(() => null, () => null);
      await done(false);
      return { error: err.status === 401 || err.status === 403 ? 'ai-key' : err.status === 429 || err.status === 529 ? 'ai-busy'
        : /credit balance/i.test(msg) ? 'ai-credit' : err.status === 404 ? 'ai-model' : /timed? ?out/i.test(msg) ? 'ai-slow' : 'ai-failed' };
    }
    await db.rpc('ai_draft_tokens', { p_id: pressId, p_in: input, p_out: output, p_model: usedModel }).then(() => null, () => null);
    const t = answer ? tidy(answer, numbersOf(figures)) : null;
    if (!t || !t.whole) { await done(false); return { error: Date.now() - started > 120000 ? 'ai-slow' : 'ai-incomplete' }; }
    const analysis = { ...t.out, dropped: t.dropped, notes: notes || null };
    const saved = await db.rpc('analytics_read_save', { p_press: pressId, p_period: period, p_figures: figures,
      p_analysis: analysis, p_model: usedModel });
    const row = (saved.data || {}) as Record<string, unknown>;
    if (saved.error || row.error) { await done(false); return { error: saved.error ? 'needs-update' : String(row.error) }; }
    await done(true);
    return { read: row, left: got.left };
  })(), origin);
});
