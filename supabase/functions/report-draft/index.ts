/*
 * report-draft — drafts a report's commentary from the report's own figures.
 *
 * Draft with AI on a report's Commentary step (js/reports.js) posts the
 * report's id here. The function reads the report as the caller, under the
 * caller's own access (a colleague with Reports at Work, the report still a
 * draft), builds a summary of its figures and sends only that to the Claude
 * API: the period, the account totals, the previous period, and each ad or
 * post's figures. No client name, contact, note or image leaves the
 * database. The answer is four fields of text, which the page puts in the
 * fields for the team to edit; nothing is saved here and nothing is
 * published.
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

const SYSTEM = [
  'You draft the commentary of a monthly social media report that a Malaysian and Singaporean digital marketing agency sends its client.',
  'Write in polished, professional British English for a business owner: clear, specific and benefit-first, never hype, never generic.',
  'Every point rests on a figure in the data given; name the figure. Never invent a number, a cause, an audience or a benchmark that the data does not show.',
  'Compare with the previous period only where its figures are given. Where a figure is missing, say nothing about it.',
  'Ads are named as they are in the data. Use the currency shown. Write dates as 12 Sept 2026.',
  'No dashes as punctuation, no emoji, no exclamation marks, no first person singular. Refer to the agency as "we" and to the client as "your".',
  'Bullet fields are one point a line with no bullet characters; a line starting with a dash is a sub-point, used sparingly.',
  'Keep each field short: the summary two or three sentences, each list two to four points.'
].join('\n');

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
  const cl = await db.from('clients').select('market').eq('id', r.client_id as string).maybeSingle();
  const currency = String((cl.data as Record<string, unknown> | null)?.market || '').toUpperCase() === 'SG' ? 'SGD' : 'MYR';

  const data: Record<string, unknown> = { kind, period: { start: r.period_start, end: r.period_end }, currency };
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
      ad: adName(a.name), objective: a.objective, result: a.result_label, audience: a.audience,
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
      Object.keys(p).forEach((k) => { if (p[k] !== null && p[k] !== '') out[k === 'platform_id' ? 'account_ref' : k] = p[k]; });
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
      system: SYSTEM,
      output_config: { format: { type: 'json_schema', schema } },
      messages: [{ role: 'user', content: 'Draft the commentary for this report.\n\n' + JSON.stringify(data) }]
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
