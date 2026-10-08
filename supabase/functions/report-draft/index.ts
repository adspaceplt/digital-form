/*
 * report-draft — drafts a report's commentary from the report's own figures.
 *
 * Write draft on a report's Commentary step (js/reports.js) posts the
 * report's id here. The function reads the report as the caller, under the
 * caller's own access (a colleague with Reports at Work, the report still a
 * draft), builds a summary of its figures and sends only that to the Claude
 * API: the period, the account totals, the previous period, each ad or
 * post's figures, the notes the colleague typed for this draft, and the
 * client's last finished report's commentary. The client's name is masked
 * as {brand} wherever the team's words carry it, and the drafts name the
 * client by {brand}, filled with the brand's name only once the answer is
 * back (`brandIn`); no contact, image or
 * billing detail leaves the database. The answer is four fields of text,
 * which the page puts in the fields for the team to edit; nothing is saved
 * here and nothing is published.
 *
 * With `mode: 'check'` (Check and submit, 2026-10-04) it reads the
 * commentary as it stands, drafted or written by hand, against the same
 * figures, and answers what does not hold: a figure that is not in the
 * data, a claim the figures contradict, a comparison across result types or
 * platforms, a word against our own work. The findings and the text read
 * are kept (`ai_check_done`), so the reviewer sees the same check. A report
 * in draft or in review may be checked; nothing in it is changed.
 *
 * Every call's input and output tokens and model are kept on its own
 * `ai_drafts` row (`ai_draft_tokens`, 2026-10-08), drafted or failed, so the
 * AI usage page can price the month.
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
        ['fix', 'Areas to improve: one point a line'], ['focus', 'Focus for next month: one point a line']],
  social: [['intro', 'Summary: two or three sentences on the month'], ['performed_well', 'Key findings: one point a line'],
           ['underperformed', 'Areas to improve: one point a line'], ['next_actions', 'Next steps: one point a line']]
};

/* The words a report never uses (the user, 2026-10-07): none that call the
   work we made for the client bad ("cannot say things like Creative is
   bad, since we're the one providing creatives"), and none that make it
   read too good to be true ("Totally no errors our services always perfect
   ... It sounds fake and unreal"): no praise a figure does not carry, no
   comfort phrase in place of a figure. The draft keeps to them and the
   check finds them, in English and in Chinese. */
const AVOID = `Never said of our creative, design, copy, caption, content plan or targeting: bad, poor, weak, boring, unclear, confusing, failed, flopped, useless or a mistake; never "wasted" of spend. In Chinese: 素材差, 创意差, 文案不吸引, 没有吸引力, 失败, 浪费, 白花. Judge the result instead, with its figure.
Never as praise: excellent, outstanding, exceptional, remarkable, impressive, amazing, incredible, perfect, flawless, seamless, phenomenal, a huge success, all goals achieved, every ad performed well, no issues, as always, consistently strong. In Chinese: 完美, 卓越, 出色, 优异, 非常成功, 圆满成功, 全面提升, 毫无问题, 零失误, 一如既往, 持续优秀. Give the figure instead.
Never as comfort in place of a figure: room to grow, valuable insights, valuable learnings, a learning opportunity, a clear signal, laid a strong foundation, positive momentum, despite the challenges. In Chinese: 仍有提升空间, 宝贵经验, 学习机会, 打下坚实基础, 积极势头, 尽管面临挑战. Say what fell short, by how much, and what we will change.
No word that colours a figure up or down, before or around it: only, just, merely, a mere, as few as, barely, a whopping, as many as, unfortunately, sadly, thankfully, encouragingly. In Chinese: 仅, 仅仅, 仅有, 只, 只有, 才, 高达, 足足, 竟, 竟然, 遗憾, 可惜, 幸好. Give the figure plainly ("278 views and 10 engagements", "获得278次观看与10次互动").
A rank or a place (first, second, third, the most viewed, the cheapest, 第一, 第二, 居首) is said only as the data's own rank fields give it (rank_views, rank_engagements, cost_rank), never worked out by reading the figures.`;

/* What every draft keeps to (the user, 2026-10-01): only what a client
   needs, short, and never a word against the work we made for them; nor,
   since 2026-10-07, a word that makes the month read better than its
   figures: candid both ways, so the client can believe the good news. */
const SHARED = `

HONEST BOTH WAYS
The report is a partner's: as plain about what fell short as about what worked, so the client can trust both. Never write as if every ad worked, nothing went wrong or results are always strong: that reads as fake. Never write a good month down either: give each result its figure and its real weight.
A month weaker than the one before is called weaker, with its figures, in the summary, never left for the reader to find.
What worked: the figure, then the choice behind it (the offer we led with, the hook, the format, the audience we picked). Praise only what a figure shows, in plain words ("the strongest", "the lowest cost per lead", "rose by 18%").
What fell short: the figure and how far short (against the other ads of its objective, the other posts on its platform or the previous period), then what we will change ("2609_Facilities brought 6 leads at RM 38.90 each, nearly three times the cost of 2609_OpenHouse; we will pause it and rework the offer"). Areas to improve names what truly delivered least, even in a good month, and never invents a shortfall.
Judge the result, never the work: we made the creatives, copy, captions, content plan, schedule and targeting, so never call them bad or blame them; say what the audience did and what we will change.
Where the figures show why, say so; where they do not, say that plainly ("the figures do not point to a single cause") and what we will test to find out. Never explain a shortfall away with a reason the notes do not give: no blaming the client (their product, price, stock or reply time), the platform, the algorithm or the season unless the notes say so.
When the notes say something went wrong on our side (a late launch, a broken link, an ad paused in error, a budget set wrongly), say so in one plain sentence, with what it affected where the figures show it and what we have done about it. Never hide it, never dramatise it, never invent one.
Never promise a result ("this will double the leads"); say what we will test or change.

WORDS
Plain words for a shortfall, always with its figure: lower, fell, fewer, cost more, below, did not reach, short of, the least efficient, weaker than. In Chinese: 下降, 减少, 低于, 未达到, 成本较高, 不及, 较弱, 未达预期.
${AVOID}

LENGTH
Write only what the client needs to understand the month and the next step; the tables already show every figure, so a point repeats a figure only to explain a decision. Pick the few ads or posts that matter most, never one point per ad. Each point is one sentence of at most 35 words; a sub-point only where it is essential, at most one under a point. Keep to the counts given for each field.`;

const ZH = `

LANGUAGE
This replaces the British English named above: write every field in Simplified Chinese for a business owner in Malaysia or Singapore: formal, natural written business Chinese (书面语), composed in Chinese and never translated word for word from English. The agency is 我们. Name the client by the placeholder {brand}, written exactly so with its braces (it is replaced with the brand's own name): "{brand}本月的潜在客户成本下降". Never 贵公司, 貴公司, 贵司, 貴司, 贵品牌, 貴品牌, 贵方, 贵企业 or 您公司: these honorifics read stiff to a Malaysian or Singaporean business owner. Use 您 sparingly, never in place of {brand}. Keep ad names, post titles and abbreviations such as CTR exactly as given; platforms as Facebook, Instagram, TikTok and 小红书. Money as RM 12.23 (S$ for SGD), numbers with thousands separators, dates as 2026年9月16日. Full-width Chinese punctuation. One point a line, as in English.`;

/* The house style, taken from the team's approved ads reports (the user,
   2026-10-01) and tightened where those reports were loosest: a reason for
   every fix, an action with a time for every recommendation, like compared
   only with like. The example is invented; no client's words are here. */
const SYSTEM = `You draft the commentary of a monthly social media advertising report that ADspace, a digital marketing agency in Johor Bahru and Singapore, sends its client. A colleague reads your draft, corrects it and sends it; write it ready to send.

VOICE
Formal, corporate and client-facing British English (optimisation, prioritising), written for a business owner who is busy and not a marketer: complete sentences, measured, candid and confident, never casual, never hype, never defensive, never generic. No contractions, no slang, no internal shorthand. The agency is "we". Name the client by the placeholder {brand}, written exactly so with its braces (it is replaced with the brand's own name): "{brand}'s cost per lead fell", "reach for {brand} rose". Never "your company", "your business", "the client" or "the brand"; "you" and "your" only where a sentence plainly needs them, and never as the only way the client is named. Every point gives the figure, then what it means for the client ("showing that", "indicating that"), then, where it applies, what we will do about it.

TRUTH
Every figure comes from the data given. Never invent a number, a cause, an audience, a benchmark or a plan. A reason is stated only when the team's notes give it (a budget moved to Google Ads, a form changed, an ad paused, unspent budget carried forward); otherwise describe what the figures show and call it what it is ("suggests", "indicates"). Next month's budget, dates and new creatives are mentioned only when the notes give them. Where a figure is missing, say nothing about it.

READING THE FIGURES
Each ad carries cost_rank, its place by cost per result among the ads of its platform, objective and result type (1 is the cheapest; out of ads_in_group), worked out for you: say an ad is the cheapest, the second or the dearest only from it. Each ad is priced only by the result its objective was set to get: a leads ad by its cost per lead, a messaging ad by its cost per messaging conversation, a traffic ad by its cost per link click, an awareness ad by its reach and cost per 1,000 people reached. Compare cost per result only between ads counting the same result. CTR shows interest in clicking. Hook rate is how many stopped on the opening; hold rate is how many kept watching after it. A strong hook with a weak hold means the opening works and the middle loses people; a weak hook means few stopped on the opening, so the opening is what we change first. An age split leaning away from the intended audience is worth a sub-point. Spend lower but reach higher is better delivery; say so.
Where the ads run on both Meta and TikTok, each ad names its platform and the account figures are given per platform: treat them as two platforms, never add reach or results across them, and compare cost per result only within one platform. On TikTok the hook rate is 2-second views over impressions and the hold rate 6-second views over 2-second views.

FIELDS
Summary (intro): one paragraph of two or three sentences. Total spend for the period and its change against the previous period in percent, with the reason when the notes give one; how results, cost per result and reach moved against the previous period where it is given, said plainly whichever way they went; which objective took most of the budget and why; the strongest ad with its result count, cost per result and CTR. Lead with the client's goal when the notes name one.
What worked (worked): two to four points, one a line, grouped by objective, strongest first; each names the ad, its result count, cost per result and the one or two rates that explain it, then what that shows. A line starting with "- " is a sub-point under the line above, for a second ad in the same objective or a caveat.
Areas to improve (fix): one to three points, one a line, on the ads that delivered least: the figure that shows it and how far short it fell (against the other ads of its objective or the previous period), what its own rates suggest about the audience, and what we will change (pause, rework the offer, retarget, a new opening). If one step covers several ads, say so once.
Focus for next month (focus): two or three points: how the budget splits across objectives (in percent where the notes or the data support it), which ads continue and where, what new creatives or audiences we will test, and the next period's dates and budget when the notes give them. Each point says "We will".

FORM
Ads are named exactly as in the data. Money as RM 12.23 (S$ for SGD). Percentages to two decimals for CTR and change, one or none for rates. Dates as 16 Sept to 15 Oct 2026. No dashes as punctuation, no emoji, no exclamation marks, no numbering or bullet characters (the report numbers the lines). Explain a platform term in plain words the first time it appears (ad recall lift: people Meta estimates would remember the ad). When last month's commentary is given, follow up on what it promised: say whether what we tested worked.

EXAMPLE (invented brand, figures and notes, for tone and shape only; the notes said part of the budget moved to Google Ads)
intro: September spend was RM 2,140.50, 12.40% lower than August, as part of the budget moved to Google Ads, while reach rose to 182,300 people. Leads took 70% of the budget and brought 64 leads, down from 81, at RM 23.41 each against RM 21.12 in August, so the month delivered fewer enquiries at a higher cost. 2609_OpenHouse was the strongest ad, with 31 leads at RM 14.20 each and a CTR of 3.85%.
worked: 2609_OpenHouse generated 31 leads at RM 14.20 cost per lead with the highest CTR of 3.85%, showing that the open house offer is the clearest reason to enquire.
- Its hold rate of 11.20% was also the strongest, so viewers stayed for the details as well as the opening.
For Awareness, 2608_Skyline reached 96,400 people at RM 2.05 per 1,000 reached, keeping {brand} visible at low cost.
fix: 2609_Facilities brought 6 leads at RM 38.90 each, nearly three times the cost of 2609_OpenHouse; 31% stopped for its opening but few enquired, so we will pause it and rework the offer.
Messaging cost RM 9.80 per conversation against RM 6.40 in August; the figures do not point to a single cause, so we will test a broader audience to find out.
focus: We will keep about 80% of the budget on Leads and 20% on Awareness.
We will continue 2609_OpenHouse and pause 2609_Facilities until its new cut is ready.`;

/* The accounts report keeps the same voice and truth, read platform by
   platform (the user, 2026-10-01: each platform's algorithm works
   differently), with remarks on each platform's top posts and the content
   to plan next. */
const SOCIAL_SYSTEM = `You draft the commentary of a monthly social media accounts report that ADspace, a digital marketing agency in Johor Bahru and Singapore, sends its client. A colleague reads your draft, corrects it and sends it; write it ready to send.

VOICE
Formal, corporate and client-facing British English, written for a busy business owner who is not a marketer: complete sentences, measured, candid and confident, never casual, never hype, never defensive, never generic. No contractions, no slang, no internal shorthand. The agency is "we". Name the client by the placeholder {brand}, written exactly so with its braces (it is replaced with the brand's own name). Never "your company", "your business", "the client" or "the brand"; "you" and "your" only where a sentence plainly needs them. Every point gives the figure, then what it means for the client, then, where it applies, what we will do.

TRUTH
Every figure comes from the data given. Never invent a number, a cause, an audience or a benchmark. A reason is stated only when the team's notes give it; otherwise describe what the figures show ("suggests", "indicates"). Compare with the previous period only where its figures are given. Recommendations may draw on how each platform works (TikTok rewards watch time and a strong first two seconds; Instagram Reels reach beyond followers while carousels earn saves; rednote rewards saves, searchable titles and an authentic first-person voice; Facebook rewards shares and community conversation), but never present that as a measured result.

READ EACH PLATFORM ON ITS OWN
Platforms are never ranked against each other and their figures are never added into one judgement: each has its own audience and algorithm. Compare a post only with posts on the same platform. Each post carries its place on its platform, worked out for you: rank_views and rank_engagements (1 is the highest; equal figures share a place) out of posts_on_platform. Say a post's place only from these.

FIELDS
intro: one paragraph of two or three sentences across the whole report: what the month achieved on each platform in one clause each, the standout result, and the direction for next month.
platforms (one entry for each ref given):
  summary: one sentence, the platform's month in a line.
  worked: two or three points, one a line, on what performed and why as far as the figures show (formats, topics, timing, hooks).
  improve: one or two points, one a line, on what fell short or grew least on this platform: its figure and against what, what it suggests about the audience, and what we will change.
  actions: two or three points, one a line, each starting "We will": the content we will plan for next month on this platform (formats, themes, series, posting rhythm, hooks, captions or keywords), built on what worked.
posts (one entry for each ref given): remark: one sentence on why the post stood out on its platform, from its figures, its format and its caption (the hook, the topic, the offer), never inventing what the data does not show.

FORM
Posts are named by their title or date as in the data. Numbers with thousands separators. Dates as 12 Sept 2026. No dashes as punctuation, no emoji, no exclamation marks, no numbering or bullet characters. When last month's commentary is given, follow up on what it promised.`;

/* The check (the user, 2026-10-04): the commentary read against the
   figures before it goes for review. Only what is wrong is listed; style is
   the writer's. */
const CHECK = `You check the commentary of a monthly social media report that ADspace, a digital marketing agency in Johor Bahru and Singapore, is about to send its client. A colleague wrote it, by hand or from a draft, and reads your findings before submitting it. You are given the report's figures as JSON and the commentary as parts, each with a ref and the place it sits.

LIST ONLY WHAT IS WRONG
1. A figure that is not in the data or does not match it: a count, an amount, a percentage, a change against the previous period, a currency, a date or period, an ad or post name.
2. A claim the figures contradict or do not support: a rise that is a fall, the best or the strongest that is not, a result credited to the wrong ad, post, objective or platform, a place (first, second, third, the cheapest) that is not the rank the data gives (rank_views, rank_engagements, cost_rank).
3. A comparison the figures do not allow: cost per result compared between different result types; platforms ranked against each other or their figures added into one judgement; a post compared with a post on another platform.
4. A word against our own work: the creatives, copy, captions, content plan, schedule and targeting are ours, so calling any of them bad, poor, weak, unclear, ineffective, a mistake or a problem, or blaming them for a result, is a finding.
5. A word or phrase from these lists, in English or Chinese; the fix gives the plain words and the figure instead:
${AVOID}
6. A picture brighter than the figures: praise or certainty they do not support; every ad or platform said to have done well, or nothing said to have gone wrong, while one fell short; a fall described as good news; a summary that reads as all good while a main figure (results, cost per result, reach or views) got worse against the previous period. The fix says it plainly with its figure, no harsher than the figures.
7. A result blamed on the client's own business (their product, price, stock or reply time): even where true it reads as blame in a report from us; the fix says what the figures show and what we will do.
Nothing else: never comment on style, tone, length, order or any other word choice, never on a reason, plan or budget the figures cannot show (the writer may know it), and never on a figure the data does not hold one way or the other. When every part holds, return no findings.

EACH FINDING
ref: the part it is in. quote: the exact words that are wrong, copied from the part, at most 30 words. issue: one sentence in plain British English naming what the figures show, with the figure. fix: the corrected words, ready to paste in place of the quote, in the part's own language and voice; empty where the words should simply go.
The client is named {brand} in the commentary: keep {brand} exactly as it is in a quote and a fix.
At most 10 findings, the most serious first. No dashes as punctuation, no emoji.`;

/* What a press cost, kept on its own row (`ai_draft_tokens`, 2026-10-08):
   every token read, cached or not, and every token written, across every
   call the press made (a draft and its own check), so the AI usage page
   can price the month. Never fails the answer. */
// deno-lint-ignore no-explicit-any
function keepTokens(db: any, id: string, spent: Anthropic.Message[]): Promise<null> {
  let input = 0, output = 0;
  spent.forEach((res) => {
    const u = (res && res.usage || {}) as unknown as Record<string, number | null | undefined>;
    input += (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
    output += u.output_tokens || 0;
  });
  return db.rpc('ai_draft_tokens', { p_id: id, p_in: input, p_out: output, p_model: spent[0] && spent[0].model || null })
    .then(() => null, () => null);
}

function num(v: unknown): number | null {
  const n = typeof v === 'number' ? v : v == null || v === '' ? NaN : Number(v);
  return Number.isFinite(n) ? n : null;
}
/* The team's creator code ending a name (_222) is the team's, never the client's. */
function adName(s: unknown): string { return String(s ?? '').trim().replace(/[\s_-]+(\d)\1\1$/, ''); }

/* The client named by the brand itself (the user, 2026-10-07: "avoid using
   贵公司 / 貴司 all these very strong chinese wordings. use brand name to
   mention our client straight. also applies into english"): {brand} is
   filled with the name, and a Chinese honorific that slipped through is put
   back to the name too. With no name held, {brand} reads 品牌 or the brand. */
function brandIn(s: string, name: string): string {
  const zh = /[\u4e00-\u9fff]/.test(s);
  const n = name || (zh ? '品牌' : 'the brand');
  return s.replace(/\{\s*brand\s*\}/gi, n)
    .replace(/(贵|貴)(公司|司|品牌|企业|企業|方)|您公司/g, n);
}

/* The parts of the commentary as they stand, each with the place a reader
   finds it: the report's own fields, each platform's block and each top
   post's remark. The same map is kept with the findings (`basis`), so the
   page can tell when the commentary has changed since. */
const LABEL: Record<string, string> = {
  intro: 'Summary', worked: 'What worked', fix: 'Areas to improve', focus: 'Focus for next month',
  performed_well: 'Key findings', underperformed: 'Areas to improve', next_actions: 'Next steps'
};
const PLAT: [string, string][] = [['summary', 'Summary line'], ['worked', 'What worked'], ['improve', 'Areas to improve'], ['actions', 'Focus for next month']];
const PLAT_WORD: Record<string, string> = { instagram: 'Instagram', facebook: 'Facebook', tiktok: 'TikTok', xhs: 'rednote', rednote: 'rednote' };

/* The check itself: the parts read against the figures, the findings as
   the model gives them (ref, quote, issue, fix), or null where no answer
   came back. Used by Check, and by every draft on its own words before it
   is returned (the user, 2026-10-09: "draft with AI already should have
   taken note of" what the check flags). */
async function askCheck(client: Anthropic, data: Record<string, unknown>, parts: { ref: string; where: string; text: string }[],
  mask: (s: string) => string, maxTokens: number, spent: Anthropic.Message[]): Promise<Record<string, unknown>[] | null> {
  const refs = parts.map((p) => p.ref);
  const str = (d: string) => ({ type: 'string', description: d });
  const schema = { type: 'object', additionalProperties: false, required: ['findings'], properties: {
    findings: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['ref', 'quote', 'issue', 'fix'],
      properties: { ref: { type: 'string', enum: refs }, quote: str('The exact words that are wrong'),
        issue: str('What the figures show, one sentence'), fix: str('The corrected words, or empty') } } } } };
  const res = await client.messages.create({
    model: secret('REPORT_DRAFT_MODEL'),
    max_tokens: maxTokens,
    system: CHECK,
    output_config: { format: { type: 'json_schema', schema } },
    messages: [{ role: 'user', content: 'Check this commentary against the report\'s figures.\n\nFIGURES\n' + JSON.stringify(data) +
      '\n\nCOMMENTARY\n' + JSON.stringify(parts.map((p) => ({ ref: p.ref, place: p.where, text: mask(p.text) }))) }]
  } as Anthropic.MessageCreateParamsNonStreaming);
  spent.push(res);
  if (res.stop_reason === 'refusal' || res.stop_reason === 'max_tokens') return null;
  const text = res.content.filter((b) => b.type === 'text').map((b) => b.type === 'text' ? b.text : '').join('');
  let got: Record<string, unknown> | null = null;
  try { got = JSON.parse(text); } catch { got = null; }
  if (!got || !Array.isArray(got.findings)) return null;
  return (got.findings as Record<string, unknown>[]).filter((f) => refs.includes(String(f.ref)));
}

/* A word that colours a figure, taken out where it stands before a figure
   (仅以278次观看, 只获得1次, only 278 views): the plain figure is the house
   style, and the check flags the word. Never 不仅 or "not only". */
function plainFigures(t: string): string {
  return t
    .replace(/(?<!不)(仅仅|仅有|仅|只有|只)(?=(?:以|有|获得|取得|录得|收获|带来|吸引|达到|达|为)?\s*[0-9０-９一二两三四五六七八九十])/g, '')
    .replace(/(?<!\bnot\s)\b(only|just|merely|a mere|a whopping|as few as|barely)\s+(?=(?:RM|S\$)?\s?[0-9])/gi, '');
}

// deno-lint-ignore no-explicit-any
async function runCheck(db: any, id: string, kind: string, r: Record<string, unknown>, data: Record<string, unknown>,
  mask: (s: string) => string, origin: string | null, forName: string) {
  const parts: { ref: string; where: string; text: string }[] = [];
  const add = (ref: string, where: string, v: unknown) => {
    const t = String(v ?? '').replace(/\r/g, '').trim();
    if (t) parts.push({ ref, where, text: t.slice(0, 4000) });
  };
  const ins = (r.insights || {}) as Record<string, unknown>;
  add('intro', 'Summary', r.intro);
  (kind === 'ads' ? ['worked', 'fix', 'focus'] : ['performed_well', 'underperformed', 'next_actions'])
    .forEach((k) => add(k, LABEL[k], ins[k]));
  if (kind !== 'ads') {
    const pf = await db.from('sm_report_platforms').select('id, platform, group_label, summary, worked, improve, actions').eq('report_id', id).order('position', { ascending: true });
    const ps = await db.from('sm_report_posts').select('id, title, posted_on, platform_id, notable').eq('report_id', id).not('notable', 'is', null).order('position', { ascending: true });
    if (pf.error || ps.error) return json({ error: 'not-found' }, 200, origin);
    const platName: Record<string, string> = {};
    (pf.data as Record<string, unknown>[]).forEach((p) => {
      const name = String(p.group_label || PLAT_WORD[String(p.platform)] || p.platform || 'Platform');
      platName[String(p.id)] = name;
      PLAT.forEach(([k, w]) => add('p:' + p.id + ':' + k, name + ' · ' + w, p[k]));
    });
    (ps.data as Record<string, unknown>[]).forEach((p) => {
      add('n:' + p.id, (platName[String(p.platform_id)] ? platName[String(p.platform_id)] + ' · ' : '') + 'Top post' +
        (p.title ? ': ' + String(p.title).slice(0, 60) : p.posted_on ? ', ' + p.posted_on : ''), p.notable);
    });
  }
  if (!parts.length) return json({ error: 'no-text' }, 200, origin);
  const basis: Record<string, string> = {};
  parts.forEach((p) => { basis[p.ref] = p.text; });

  const claim = await db.rpc('ai_check_claim', { p_report: id });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const pressId = String(got.id || '');
  const done = (ok: boolean, result: unknown) => db.rpc('ai_check_done', { p_id: pressId, p_ok: ok, p_result: result, p_basis: ok ? basis : null })
    .then(() => null, () => null);

  const spent: Anthropic.Message[] = [];
  try {
    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY') });
    const got2 = await askCheck(client, data, parts, mask, 16000, spent);
    if (!got2) {
      console.error('report-draft check: no findings came back');
      await done(false, null);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    const clean = (v: unknown, n: number) => String(v ?? '').replace(/\r/g, '').trim().slice(0, n);
    const findings = got2.slice(0, 10)
      .map((f) => ({ ref: String(f.ref), where: parts.find((p) => p.ref === String(f.ref))!.where,
        quote: brandIn(clean(f.quote, 400), forName), issue: brandIn(clean(f.issue, 600), forName), fix: brandIn(clean(f.fix, 1200), forName) }))
      .filter((f) => f.issue);
    const result = { findings };
    await done(true, result);
    return json({ check: result, basis, left: got.left }, 200, origin);
  } catch (e) {
    const err = e as { status?: number; message?: string; error?: { error?: { type?: string; message?: string } } };
    const status = err.status;
    const type = err.error?.error?.type || '';
    const said = err.error?.error?.message || err.message || '';
    console.error('report-draft check: Claude API refused', status, type, said);
    await done(false, null);
    const code = status === 401 || status === 403 ? 'ai-key'
      : status === 429 || status === 529 ? 'ai-busy'
      : /credit balance/i.test(said) ? 'ai-credit'
      : status === 404 || type === 'not_found_error' ? 'ai-model'
      : 'ai-failed';
    return json({ error: code }, 200, origin);
  } finally {
    if (spent.length) await keepTokens(db, pressId, spent);
  }
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);

  const missing = ['ANTHROPIC_API_KEY', 'REPORT_DRAFT_MODEL'].filter((k) => !secret(k));
  if (missing.length) return json({ error: 'ai-not-set-up', missing }, 200, origin);

  const body = await req.json().catch(() => ({}));
  const id = String(body && body.report_id || '');
  const check = body && body.mode === 'check';
  /* What the team knows and the figures cannot show: reasons, changes made,
     the goal, next month's budget. Typed on the page, never stored. */
  /* The language the client reads: English, or Chinese written as Chinese. */
  const lang = body && body.lang === 'zh' ? 'zh' : 'en';
  const notes = String(body && body.notes || '').replace(/\r/g, '').trim().slice(0, 2000);
  /* The accounts report names the platforms and top posts its Commentary
     step shows, so the draft answers for exactly those. */
  const wantPlat = Array.isArray(body && body.platforms) ? (body.platforms as unknown[]).map(String).slice(0, 20) : [];
  const wantPost = Array.isArray(body && body.posts) ? (body.posts as unknown[]).map(String).slice(0, 60) : [];
  if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: 'bad-request' }, 400, origin);

  const auth = req.headers.get('Authorization') ?? '';
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });

  const may = await db.rpc('allowed', { p_section: 'reports', p_level: 'work' });
  if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);

  const rep = await db.from('sm_reports')
    .select('id, kind, status, period_start, period_end, first_month, ads_totals, client_id, intro, insights, brand_name')
    .eq('id', id).maybeSingle();
  if (rep.error || !rep.data) return json({ error: 'not-found' }, 200, origin);
  const r = rep.data as Record<string, unknown>;
  if (check ? r.status !== 'draft' && r.status !== 'review' : r.status !== 'draft') {
    return json({ error: check ? 'not-open' : 'not-draft' }, 200, origin);
  }
  const kind = r.kind === 'ads' ? 'ads' : 'social';


  /* The currency follows the client's market, as the page's money does. */
  const cl = await db.from('clients').select('market, name').eq('id', r.client_id as string).maybeSingle();
  const crow = (cl.data || {}) as Record<string, unknown>;
  const currency = String(crow.market || '').toUpperCase() === 'SG' ? 'SGD' : 'MYR';
  /* The client's name never leaves: wherever the team's words carry it (or
     a white-label report's brand), it reads as {brand}, and the answer's
     {brand} is filled with the name the report is for once it is back. */
  const cname = String(crow.name || '').trim();
  const bname = String(r.brand_name || '').trim();
  const forName = bname || cname;
  const mask = (s: string) => [bname, cname].filter((n) => n.length > 1).reduce((t, n) =>
    t.replace(new RegExp(n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), '{brand}'), s);

  const data: Record<string, unknown> = { kind, period: { start: r.period_start, end: r.period_end }, currency };
  const targets: { platforms: string[]; posts: string[] } = { platforms: [], posts: [] };
  if (notes) data.team_notes = mask(notes);

  /* Last period's commentary, so this month follows up on what was said. */
  const keys = FIELDS[kind].map(([k]) => k);
  const prev = check ? { error: null, data: null } : await db.from('sm_reports')
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
      .select('name, objective, result_label, audience, starts_on, ends_on, results, reach, impressions, spend, ctr, cpr, hook_rate, hold_rate, avg_play, age, retention, platform')
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
    // Meta and TikTok in one report (2026-10-05): each platform's figures
    // apart, since reach is never added across platforms.
    const tk = (t.tiktok || {}) as Record<string, unknown>;
    if ((ads.data as Record<string, unknown>[]).some((a) => a.platform === 'tiktok')) {
      data.account = { meta: data.account, tiktok: { reach: num(tk.reach), impressions: num(tk.impressions), spend: num(tk.spend) } };
      if (data.previous) {
        data.previous = { ...data.previous as Record<string, unknown>,
          tiktok: { reach: num(tk.prev_reach), impressions: num(tk.prev_impressions), spend: num(tk.prev_spend) } };
      }
    }
    /* Each ad's place by cost per result among its platform, objective and
       result type, worked out here so neither the draft nor the check
       counts it (the user, 2026-10-09). */
    const adRows = ads.data as Record<string, unknown>[];
    const cprOf = (a: Record<string, unknown>) => num(a.cpr) ?? (num(a.spend) !== null && num(a.results) ? num(a.spend)! / num(a.results)! : null);
    const groupOf = (a: Record<string, unknown>) => [a.platform || 'meta', a.objective || '', a.result_label || ''].join('|');
    const rankAd = (a: Record<string, unknown>) => {
      const mine = cprOf(a);
      const peers = adRows.filter((b) => groupOf(b) === groupOf(a) && num(b.results) && cprOf(b) !== null);
      if (mine === null || !num(a.results)) return { cost_rank: null, ads_in_group: peers.length };
      return { cost_rank: 1 + peers.filter((b) => cprOf(b)! < mine - 0.0001).length, ads_in_group: peers.length };
    };
    data.ads = adRows.map((a) => ({
      ...rankAd(a),
      ad: mask(adName(a.name)), platform: a.platform === 'tiktok' ? 'TikTok' : 'Meta', objective: a.objective, result: a.result_label, audience: a.audience,
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
      .select('id, platform_id, posted_on, title, caption, content_type, views, reach, impressions, interactions, engagements, likes, comments, shares, saves')
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
      out.platform = p.group_label || p.platform;
      return out;
    });
    /* Each post's place on its own platform by views and by engagements,
       worked out here so neither the draft nor the check counts it (the
       user, 2026-10-09: a draft said second where the figures say third). */
    const postRows = ps.data as Record<string, unknown>[];
    const engOf = (p: Record<string, unknown>) => num(p.engagements) ?? num(p.interactions);
    const placeOf = (p: Record<string, unknown>, f: (x: Record<string, unknown>) => number | null) => {
      const mine = f(p);
      if (mine === null) return null;
      return 1 + postRows.filter((q) => q.platform_id === p.platform_id && (f(q) ?? -1) > mine).length;
    };
    data.posts = postRows.map((p) => {
      const out: Record<string, unknown> = {
        rank_views: placeOf(p, (x) => num(x.views)), rank_engagements: placeOf(p, engOf),
        posts_on_platform: postRows.filter((q) => q.platform_id === p.platform_id).length
      };
      Object.keys(p).forEach((k) => {
        if (k === 'id' || p[k] === null || p[k] === '') return;
        const v = typeof p[k] === 'string' ? mask(p[k] as string) : p[k];
        out[k === 'platform_id' ? 'account_ref' : k] = k === 'caption' ? String(v).slice(0, 800) : v;
      });
      out.ref = p.id;
      return out;
    });
    const platIds = new Set((pf.data as Record<string, unknown>[]).map((p) => String(p.id)));
    const postIds = new Set((ps.data as Record<string, unknown>[]).map((p) => String(p.id)));
    targets.platforms = wantPlat.filter((x) => platIds.has(x));
    targets.posts = wantPost.filter((x) => postIds.has(x));
    data.platforms_to_write = targets.platforms;
    data.posts_to_remark = targets.posts;
  }

  if (check) return runCheck(db, id, kind, r, data, mask, origin, forName);

  const fields = kind === 'ads' ? FIELDS.ads : [FIELDS.social[0]];
  const str = (d: string) => ({ type: 'string', description: d });
  const properties: Record<string, unknown> = Object.fromEntries(fields.map(([k, d]) => [k, str(d)]));
  if (kind !== 'ads' && targets.platforms.length) {
    properties.platforms = { type: 'array', items: { type: 'object', additionalProperties: false,
      required: ['ref', 'summary', 'worked', 'improve', 'actions'],
      properties: { ref: { type: 'string', enum: targets.platforms }, summary: str('One sentence'), worked: str('What worked, one point a line'),
        improve: str('Areas to improve, one point a line'), actions: str('Focus for next month: the content we will plan, one point a line') } } };
  }
  if (kind !== 'ads' && targets.posts.length) {
    properties.posts = { type: 'array', items: { type: 'object', additionalProperties: false, required: ['ref', 'remark'],
      properties: { ref: { type: 'string', enum: targets.posts }, remark: str('Why the post stood out, one or two sentences') } } };
  }
  const schema = { type: 'object', properties, required: Object.keys(properties), additionalProperties: false };

  /* Every press is counted by the database once the report has something
     to draft from and before Claude is asked: a report has one draft and
     drafting it again is an admin's (5 a report in 24 hours); 20 a
     colleague and 60 the team in 24 hours. A press that fails is marked
     failed and not counted. */
  const claim = await db.rpc('ai_draft_claim', { p_report: id });
  if (claim.error) return json({ error: 'needs-update' }, 200, origin);
  const got = (claim.data || {}) as Record<string, unknown>;
  if (got.error) return json(got, 200, origin);
  const pressId = String(got.id || '');
  const done = (ok: boolean) => db.rpc('ai_draft_done', { p_id: pressId, p_ok: ok }).then(() => null, () => null);

  const started = Date.now();
  const spent: Anthropic.Message[] = [];
  try {
    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY') });
    /* The answer is held to the schema by structured output, never a forced
       tool call: newer models refuse `tool_choice` of type tool. The model
       may think first, so the budget leaves room for that. */
    const res = await client.messages.create({
      model: secret('REPORT_DRAFT_MODEL'),
      max_tokens: 16000,
      system: (kind === 'ads' ? SYSTEM : SOCIAL_SYSTEM) + SHARED + (lang === 'zh' ? ZH : ''),
      output_config: { format: { type: 'json_schema', schema } },
      messages: [{ role: 'user', content: 'Draft the commentary for this report. The report\'s figures follow as JSON, with the team\'s notes (team_notes), last period\'s commentary (last_period_commentary), and for an accounts report the platforms to write for (platforms_to_write) and the posts to remark on (posts_to_remark), where there are any.\n\n' + JSON.stringify(data) }]
    } as Anthropic.MessageCreateParamsNonStreaming);
    spent.push(res);
    if (res.stop_reason === 'refusal' || res.stop_reason === 'max_tokens') {
      console.error('report-draft: answer stopped short', res.stop_reason);
      await done(false);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    const text = res.content.filter((b) => b.type === 'text').map((b) => b.type === 'text' ? b.text : '').join('');
    let draft: Record<string, unknown> | null = null;
    try { draft = JSON.parse(text); } catch { draft = null; }
    if (!draft || typeof draft !== 'object') {
      console.error('report-draft: no draft in the answer', res.stop_reason);
      await done(false);
      return json({ error: 'ai-incomplete' }, 200, origin);
    }
    const clean = (v: unknown) => brandIn(String(v ?? '').replace(/\r/g, '').trim(), forName);
    const out: Record<string, unknown> = {};
    for (const [k] of fields) {
      if (typeof draft[k] !== 'string') { await done(false); return json({ error: 'ai-incomplete' }, 200, origin); }
      out[k] = clean(draft[k]);
    }
    if (Array.isArray(draft.platforms)) {
      out.platforms = (draft.platforms as Record<string, unknown>[]).filter((x) => targets.platforms.includes(String(x.ref)))
        .map((x) => ({ ref: String(x.ref), summary: clean(x.summary), worked: clean(x.worked), improve: clean(x.improve), actions: clean(x.actions) }));
    }
    if (Array.isArray(draft.posts)) {
      out.posts = (draft.posts as Record<string, unknown>[]).filter((x) => targets.posts.includes(String(x.ref)))
        .map((x) => ({ ref: String(x.ref), remark: clean(x.remark) }));
    }
    /* The draft is read by the figures check before it is handed over, and
       what the check would flag is put right in it, so a draft and its check
       agree (the user, 2026-10-09). Part of the same press, never one of the
       day's checks; skipped where the draft itself took long, so the press
       stays inside the function's time. Then the words that colour a figure
       are taken out wherever they still stand. */
    const parts: { ref: string; where: string; text: string }[] = [];
    const put = (ref: string, where: string, v: unknown) => { const t = String(v ?? '').trim(); if (t) parts.push({ ref, where, text: t }); };
    for (const [k] of fields) put(k, LABEL[k] || k, out[k]);
    ((out.platforms || []) as Record<string, string>[]).forEach((pl) => PLAT.forEach(([k, w]) => put('p:' + pl.ref + ':' + k, w, pl[k])));
    ((out.posts || []) as Record<string, string>[]).forEach((pp) => put('n:' + pp.ref, 'Top post', pp.remark));
    let fixed = 0;
    if (parts.length && Date.now() - started < 70000) {
      const found = await askCheck(client, data, parts, mask, 8000, spent).catch((e) => { console.error('report-draft: self-check failed', String(e)); return null; });
      (found || []).forEach((f) => {
        const ref = String(f.ref), quote = brandIn(String(f.quote ?? '').trim(), forName), fix = brandIn(String(f.fix ?? '').trim(), forName);
        if (!quote) return;
        const swap = (t: string) => {
          if (t.indexOf(quote) < 0) return t;
          fixed++;
          const u = t.replace(quote, fix);
          return fix ? u : u.replace(/[ \t]{2,}/g, ' ').replace(/ ([,.;:，。；：])/g, '$1');
        };
        let m: RegExpExecArray | null;
        if ((m = /^p:(.+):(summary|worked|improve|actions)$/.exec(ref))) {
          const pl = ((out.platforms || []) as Record<string, string>[]).find((x) => x.ref === m![1]);
          if (pl) pl[m[2]] = swap(pl[m[2]]);
        } else if ((m = /^n:(.+)$/.exec(ref))) {
          const pp = ((out.posts || []) as Record<string, string>[]).find((x) => x.ref === m![1]);
          if (pp) pp.remark = swap(pp.remark);
        } else if (typeof out[ref] === 'string') out[ref] = swap(out[ref] as string);
      });
    }
    for (const [k] of fields) out[k] = plainFigures(String(out[k]));
    ((out.platforms || []) as Record<string, string>[]).forEach((pl) => PLAT.forEach(([k]) => { pl[k] = plainFigures(pl[k]); }));
    ((out.posts || []) as Record<string, string>[]).forEach((pp) => { pp.remark = plainFigures(pp.remark); });
    if (fixed) console.log('report-draft: the self-check put right', fixed, 'points');
    await done(true);
    return json({ draft: out, left: got.left }, 200, origin);
  } catch (e) {
    /* The API's own type and message go to the function's log (never the
       key, which the SDK does not echo), so a refusal can be named. */
    const err = e as { status?: number; message?: string; error?: { error?: { type?: string; message?: string } } };
    const status = err.status;
    const type = err.error?.error?.type || '';
    const said = err.error?.error?.message || err.message || '';
    console.error('report-draft: Claude API refused', status, type, said);
    await done(false);
    const code = status === 401 || status === 403 ? 'ai-key'
      : status === 429 || status === 529 ? 'ai-busy'
      : /credit balance/i.test(said) ? 'ai-credit'
      : status === 404 || type === 'not_found_error' ? 'ai-model'
      : 'ai-failed';
    return json({ error: code }, 200, origin);
  } finally {
    if (spent.length) await keepTokens(db, pressId, spent);
  }
});
