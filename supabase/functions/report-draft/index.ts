/*
 * report-draft — drafts a report's commentary from the report's own figures.
 *
 * Draft with AI on a report's Commentary step (js/reports.js) posts the
 * report's id here. The function reads the report as the caller, under the
 * caller's own access (a colleague with Reports at Work, the report still a
 * draft), builds a summary of its figures and sends only that to the Claude
 * API: the period, the account totals, the previous period, each ad or
 * post's figures, the notes the colleague typed for this draft, and the
 * client's last finished report's commentary. The client's name is masked
 * as "the brand" wherever the team's words carry it; no contact, image or
 * billing detail leaves the database. The answer is four fields of text,
 * which the page puts in the fields for the team to edit; nothing is saved
 * here and nothing is published.
 *
 * Secrets: ANTHROPIC_API_KEY and REPORT_DRAFT_MODEL (the model id), set in
 *          the Supabase dashboard (docs/REPORT-DRAFT-SETUP.md), plus the
 *          platform's SUPABASE_URL and SUPABASE_ANON_KEY.
 *
 * A refusal the person can act on (not set up, not allowed, not a draft,
 * nothing to write about) answers 200 with { error }, so the page names it;
 * a non-2xx is kept for a malformed request.
 *
 * Deploy with Verify JWT off, as for meet-create: the preflight carries no
 * Authorization header, and this function asks the database about the
 * caller itself.
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

/* The fields each kind of report holds, in the page's own keys. */
const FIELDS: Record<string, [string, string][]> = {
  ads: [['intro', 'Summary: two or three sentences on the month'], ['worked', 'What worked: one point a line'],
        ['fix', 'What to fix: one point a line'], ['focus', 'Focus for next month: one point a line']],
  social: [['intro', 'Summary: two or three sentences on the month'], ['performed_well', 'Key findings: one point a line'],
           ['underperformed', 'Areas to improve: one point a line'], ['next_actions', 'Next steps: one point a line']]
};

/* The house style, taken from the team's approved ads reports (the user,
   2026-10-01) and tightened where those reports were loosest: a reason for
   every fix, an action with a time for every recommendation, like compared
   only with like. The example is invented; no client's words are here. */
const SYSTEM = `You draft the commentary of a monthly social media advertising report that ADspace, a digital marketing agency in Johor Bahru and Singapore, sends its client. A colleague reads your draft, corrects it and sends it; write it ready to send.

VOICE
Polished, professional British English (optimisation, prioritising) for a business owner who is busy and not a marketer. Confident and specific, never hype, never generic. The agency is "we"; the client is "your" or the brand. Every point gives the figure, then what it means for the client ("showing that", "indicating that"), then, where it applies, what we will do about it.

TRUTH
Every figure comes from the data given. Never invent a number, a cause, an audience, a benchmark or a plan. A reason is stated only when the team's notes give it (a budget moved to Google Ads, a form changed, an ad paused, unspent budget carried forward); otherwise describe what the figures show and call it what it is ("suggests", "indicates"). Next month's budget, dates and new creatives are mentioned only when the notes give them. Where a figure is missing, say nothing about it.

READING THE FIGURES
Each ad is priced only by the result its objective was set to get: a leads ad by its cost per lead, a messaging ad by its cost per messaging conversation, a traffic ad by its cost per link click, an awareness ad by its reach and cost per 1,000 people reached. Compare cost per result only between ads counting the same result. CTR shows interest in clicking. Hook rate is how many stopped on the opening; hold rate is how many kept watching after it. A strong hook with a weak hold means the opening works and the middle loses people; a weak hook means the opening needs work. An age split leaning away from the intended audience is worth a sub-point. Spend lower but reach higher is better delivery; say so.

FIELDS
Summary (intro): one paragraph of three to five sentences. Total spend for the period and its change against the previous period in percent, with the reason when the notes give one; how reach and impressions moved; which objective took most of the budget and why; the strongest ad with its result count, cost per result and CTR. Lead with the client's goal when the notes name one.
What worked (worked): one point a line, grouped by objective, strongest first; each names the ad, its result count, cost per result and the one or two rates that explain it, then what that shows. A line starting with "- " is a sub-point under the line above, for a second ad in the same objective or a caveat.
What to fix (fix): one point a line for each ad that underdelivered: the figure that shows it, the likely reason drawn from its own rates, and the action (paused, refined, retargeted, a new opening). If one remedy covers several ads, end with one line saying so.
Focus for next month (focus): two to four points: how the budget splits across objectives (in percent where the notes or the data support it), which ads continue and where, what new creatives or audiences we will test, and the next period's dates and budget when the notes give them. Each point says "We will".

FORM
Ads are named exactly as in the data. Money as RM 12.23 (S$ for SGD). Percentages to two decimals for CTR and change, one or none for rates. Dates as 16 Sept to 15 Oct 2026. No dashes as punctuation, no emoji, no exclamation marks, no numbering or bullet characters (the report numbers the lines). Explain a platform term in plain words the first time it appears (ad recall lift: people Meta estimates would remember the ad). When last month's commentary is given, follow up on what it promised: say whether what we tested worked.

EXAMPLE (invented brand and figures, for tone and shape only)
intro: September spend was RM 2,140.50, 12.40% lower than August, as part of the budget moved to Google Ads. Reach still rose to 182,300 people, showing more efficient delivery. Leads took 70% of the budget and brought 64 leads, with 2609_OpenHouse the strongest at 31 leads for RM 14.20 each and a CTR of 3.85%.
worked: 2609_OpenHouse generated 31 leads at RM 14.20 cost per lead with the highest CTR of 3.85%, showing that the open house offer is the clearest reason to enquire.
- Its hold rate of 11.20% was also the strongest, so viewers stayed for the details as well as the opening.
For Awareness, 2608_Skyline reached 96,400 people at RM 2.05 per 1,000 reached, keeping the brand visible at low cost.
fix: 2609_Facilities recorded the highest cost per lead at RM 38.90. Its hook rate of 31% was strong but its hold rate fell to 4.80%, so viewers left once the opening ended; we will bring the key message into the first five seconds.
focus: We will keep about 80% of the budget on Leads and 20% on Awareness.
We will continue 2609_OpenHouse and pause 2609_Facilities until its new cut is ready.`;

/* The accounts report keeps the same voice and truth, on its own fields. */
const SOCIAL_SYSTEM = `You draft the commentary of a monthly social media accounts report that ADspace, a digital marketing agency in Johor Bahru and Singapore, sends its client. A colleague reads your draft, corrects it and sends it; write it ready to send.

VOICE
Polished, professional British English for a busy business owner who is not a marketer. Confident and specific, never hype, never generic. The agency is "we"; the client is "your" or the brand. Every point gives the figure, then what it means for the client, then, where it applies, what we will do.

TRUTH
Every figure comes from the data given. Never invent a number, a cause, an audience, a benchmark or a plan. A reason is stated only when the team's notes give it; otherwise describe what the figures show ("suggests", "indicates"). Compare with the previous period only where its figures are given.

FIELDS
Summary (intro): one paragraph of three to five sentences: how each account moved (followers, views, engagement), the strongest post with its figures, and what that says about the content.
Key findings (performed_well): one point a line, the posts and formats that did best, each with its figures and what made it work as far as the figures show.
Areas to improve (underperformed): one point a line, what fell short, its figure, the likely reason from the figures and what we will change.
Next steps (next_actions): two to four points, each starting "We will".

FORM
Posts are named by their title or date as in the data. Numbers with thousands separators. Dates as 12 Sept 2026. No dashes as punctuation, no emoji, no exclamation marks, no numbering or bullet characters. When last month's commentary is given, follow up on what it promised.`;

function num(v: unknown): number | null {
  const n = typeof v === 'number' ? v : v == null || v === '' ? NaN : Number(v);
  return Number.isFinite(n) ? n : null;
}
/* The team's creator code ending a name (_222) is the team's, never the client's. */
function adName(s: unknown): string { return String(s ?? '').trim().replace(/[\s_-]+(\d)\1\1$/, ''); }

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);

  const missing = ['ANTHROPIC_API_KEY', 'REPORT_DRAFT_MODEL'].filter((k) => !secret(k));
  if (missing.length) return json({ error: 'ai-not-set-up', missing }, 200, origin);

  const body = await req.json().catch(() => ({}));
  const id = String(body && body.report_id || '');
  /* What the team knows and the figures cannot show: reasons, changes made,
     the goal, next month's budget. Typed on the page, never stored. */
  const notes = String(body && body.notes || '').replace(/\r/g, '').trim().slice(0, 2000);
  if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: 'bad-request' }, 400, origin);

  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });

  const may = await db.rpc('allowed', { p_section: 'reports', p_level: 'work' });
  if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);

  const rep = await db.from('sm_reports')
    .select('id, kind, status, period_start, period_end, first_month, ads_totals, client_id')
    .eq('id', id).maybeSingle();
  if (rep.error || !rep.data) return json({ error: 'not-found' }, 200, origin);
  const r = rep.data as Record<string, unknown>;
  if (r.status !== 'draft') return json({ error: 'not-draft' }, 200, origin);
  const kind = r.kind === 'ads' ? 'ads' : 'social';

  /* The currency follows the client's market, as the page's money does. */
  const cl = await db.from('clients').select('market, name').eq('id', r.client_id as string).maybeSingle();
  const crow = (cl.data || {}) as Record<string, unknown>;
  const currency = String(crow.market || '').toUpperCase() === 'SG' ? 'SGD' : 'MYR';
  /* The client's name never leaves: wherever the team's words carry it, it
     reads as the brand. */
  const cname = String(crow.name || '').trim();
  const mask = (s: string) => cname.length > 1
    ? s.replace(new RegExp(cname.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), 'the brand') : s;

  const data: Record<string, unknown> = { kind, period: { start: r.period_start, end: r.period_end }, currency };
  if (notes) data.team_notes = mask(notes);

  /* Last period's commentary, so this month follows up on what was said. */
  const keys = FIELDS[kind].map(([k]) => k);
  const prev = await db.from('sm_reports')
    .select('period_start, period_end, intro, insights')
    .eq('client_id', r.client_id as string).eq('kind', r.kind as string)
    .neq('status', 'draft').lt('period_end', r.period_start as string)
    .order('period_end', { ascending: false }).limit(1).maybeSingle();
  if (!prev.error && prev.data) {
    const p = prev.data as Record<string, unknown>;
    const ins = (p.insights || {}) as Record<string, unknown>;
    const said: Record<string, string> = {};
    keys.forEach((k) => {
      const v = k === 'intro' ? [p.intro, ins.executive_summary].filter(Boolean).join('\n\n') : ins[k];
      if (typeof v === 'string' && v.trim()) said[k] = mask(v.trim()).slice(0, 1500);
    });
    if (Object.keys(said).length) data.last_period_commentary = { start: p.period_start, end: p.period_end, ...said };
  }
  if (kind === 'ads') {
    const ads = await db.from('sm_report_ads')
      .select('name, objective, result_label, audience, starts_on, ends_on, results, reach, impressions, spend, ctr, cpr, hook_rate, hold_rate, avg_play, age, retention')
      .eq('report_id', id).order('position', { ascending: true });
    if (ads.error) return json({ error: 'not-found' }, 200, origin);
    if (!(ads.data || []).length) return json({ error: 'no-ads' }, 200, origin);
    const t = (r.ads_totals || {}) as Record<string, unknown>;
    data.first_month = !!r.first_month;
    data.account = { reach: num(t.reach), impressions: num(t.impressions), spend: num(t.spend) };
    if (!r.first_month && t.prev_start) {
      data.previous = { start: t.prev_start, end: t.prev_end, reach: num(t.prev_reach),
        impressions: num(t.prev_impressions), spend: num(t.prev_spend), by_objective: t.prev_groups || null };
    }
    data.ads = (ads.data as Record<string, unknown>[]).map((a) => ({
      ad: mask(adName(a.name)), objective: a.objective, result: a.result_label, audience: a.audience,
      ran: a.starts_on ? [a.starts_on, a.ends_on] : null,
      results: num(a.results), reach: num(a.reach), impressions: num(a.impressions), spend: num(a.spend),
      ctr_pct: num(a.ctr), cost_per_result: num(a.cpr) ?? (num(a.spend) !== null && num(a.results) ? Math.round(num(a.spend)! / num(a.results)! * 100) / 100 : null),
      hook_rate_pct: num(a.hook_rate), hold_rate_pct: num(a.hold_rate), avg_play_s: num(a.avg_play),
      age_split_pct: a.age && Object.keys(a.age as object).length ? a.age : null,
      retention_pct: a.retention && Object.keys(a.retention as object).length ? a.retention : null
    }));
  } else {
    const pf = await db.from('sm_report_platforms').select('*').eq('report_id', id);
    const ps = await db.from('sm_report_posts')
      .select('platform_id, posted_on, title, content_type, views, reach, impressions, interactions, engagements, likes, comments, shares, saves')
      .eq('report_id', id).order('position', { ascending: true });
    if (pf.error || ps.error) return json({ error: 'not-found' }, 200, origin);
    if (!(ps.data || []).length) return json({ error: 'no-posts' }, 200, origin);
    /* An account's figures without its handle or notes. */
    data.accounts = (pf.data as Record<string, unknown>[]).map((p) => {
      const out: Record<string, unknown> = {};
      Object.keys(p).forEach((k) => {
        if (/^(id|report_id|handle|account_name|name|url|notes?|reason|created_at|position)$/.test(k)) return;
        if (p[k] !== null && p[k] !== '') out[k] = p[k];
      });
      out.ref = p.id;
      return out;
    });
    data.posts = (ps.data as Record<string, unknown>[]).map((p) => {
      const out: Record<string, unknown> = {};
      Object.keys(p).forEach((k) => {
        if (p[k] !== null && p[k] !== '') out[k === 'platform_id' ? 'account_ref' : k] = typeof p[k] === 'string' ? mask(p[k] as string) : p[k];
      });
      return out;
    });
  }

  const fields = FIELDS[kind];
  const schema = {
    type: 'object',
    properties: Object.fromEntries(fields.map(([k, d]) => [k, { type: 'string', description: d }])),
    required: fields.map(([k]) => k),
    additionalProperties: false
  };

  try {
    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY') });
    /* The answer is held to the schema by structured output, never a forced
       tool call: newer models refuse `tool_choice` of type tool. The model
       may think first, so the budget leaves room for that. */
    const res = await client.messages.create({
      model: secret('REPORT_DRAFT_MODEL'),
      max_tokens: 16000,
      system: kind === 'ads' ? SYSTEM : SOCIAL_SYSTEM,
      output_config: { format: { type: 'json_schema', schema } },
      messages: [{ role: 'user', content: 'Draft the commentary for this report. The report\'s figures follow as JSON, with the team\'s notes (team_notes) and last period\'s commentary (last_period_commentary) where there are any.\n\n' + JSON.stringify(data) }]
    } as Anthropic.MessageCreateParamsNonStreaming);
    if (res.stop_reason === 'refusal' || res.stop_reason === 'max_tokens') {
      console.error('report-draft: answer stopped short', res.stop_reason);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    const text = res.content.filter((b) => b.type === 'text').map((b) => b.type === 'text' ? b.text : '').join('');
    let draft: Record<string, unknown> | null = null;
    try { draft = JSON.parse(text); } catch { draft = null; }
    if (!draft || typeof draft !== 'object') {
      console.error('report-draft: no draft in the answer', res.stop_reason);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    const out: Record<string, string> = {};
    for (const [k] of fields) {
      if (typeof draft[k] !== 'string') return json({ error: 'ai-incomplete' }, 200, origin);
      out[k] = (draft[k] as string).replace(/\r/g, '').trim();
    }
    return json({ draft: out }, 200, origin);
  } catch (e) {
    /* The API's own type and message go to the function's log (never the
       key, which the SDK does not echo), so a refusal can be named. */
    const err = e as { status?: number; message?: string; error?: { error?: { type?: string; message?: string } } };
    const status = err.status;
    const type = err.error?.error?.type || '';
    const said = err.error?.error?.message || err.message || '';
    console.error('report-draft: Claude API refused', status, type, said);
    const code = status === 401 || status === 403 ? 'ai-key'
      : status === 429 || status === 529 ? 'ai-busy'
      : /credit balance/i.test(said) ? 'ai-credit'
      : status === 404 || type === 'not_found_error' ? 'ai-model'
      : 'ai-failed';
    return json({ error: code }, 200, origin);
  }
});
