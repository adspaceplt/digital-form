/*
 * meta-import/shape.mjs — Meta's Graph answers, written as the exports the
 * report's own importers already read (2026-10-08).
 *
 * Nothing here calls Meta or the database: each function takes the JSON the
 * Graph API answered and gives back text in the shape a person would paste,
 * so the page runs it through the same importer, the same matching by Ad ID
 * or link and the same summary line (js/reports.js `parseAdRows`,
 * `parseRows`). Every figure is Meta's; nothing is estimated here.
 *
 *   adsText(account, ads)  Ads Manager's export: the account's own row first
 *                          (no ad name: reach counted once), then an ad a row.
 *   ageText(rows)          the same ads by age, for the age split.
 *   facebookText(posts)    Meta Business Suite's Facebook export, Lifetime.
 *   instagramText(media)   the same for Instagram.
 *
 * Plain JavaScript, so `node` drives it in tests/metashape.js and Deno
 * imports it in index.ts.
 */

const TZ_MY = 8 * 3600; // Malaysia keeps UTC+8 all year.

/* The report's period as Meta's since and until: Malaysian midnight on the
   first day to Malaysian midnight after the last, in Unix seconds. */
export function periodWindow(start, end) {
  const s = Date.parse(String(start).slice(0, 10) + 'T00:00:00Z') / 1000 - TZ_MY;
  const e = Date.parse(String(end).slice(0, 10) + 'T00:00:00Z') / 1000 - TZ_MY + 86400;
  return { since: s, until: e };
}

/* A moment as Malaysia reads it: YYYY-MM-DD HH:MM (the importer reads the
   day off the front). */
export function myTime(iso) {
  const t = Date.parse(String(iso || '').replace(/\+0000$/, 'Z'));
  if (isNaN(t)) return '';
  const d = new Date(t + TZ_MY * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return d.getUTCFullYear() + '-' + p(d.getUTCMonth() + 1) + '-' + p(d.getUTCDate()) + ' ' + p(d.getUTCHours()) + ':' + p(d.getUTCMinutes());
}

/* A cell for a line-split table (the ads importer): no tab or break. */
function flat(v) { return v == null ? '' : String(v).replace(/[\t\r\n]+/g, ' ').trim(); }
/* A cell for a quoted table (the posts importer): quoted where it holds a
   tab, a break or a quote, as a spreadsheet copies it. */
function cell(v) {
  const s = v == null ? '' : String(v);
  return /[\t\r\n"]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}
function num(v) {
  if (v == null || v === '') return null;
  const n = Number(v);
  return isNaN(n) ? null : n;
}
function figure(v, dp) {
  const n = num(v);
  if (n === null) return '';
  return dp ? n.toFixed(dp) : String(Math.round(n));
}

/* One action's count from an actions list (Meta sends them as strings). */
export function actionOf(list, types) {
  if (!Array.isArray(list)) return null;
  const want = [].concat(types);
  for (const t of want) {
    const hit = list.find((a) => a && a.action_type === t);
    if (hit && num(hit.value) !== null) return num(hit.value);
  }
  return null;
}
function total(list) {
  if (!Array.isArray(list) || !list.length) return null;
  return list.reduce((t, a) => t + (num(a && a.value) || 0), 0);
}

/* What Ads Manager counts as a result for an ad set's optimisation goal,
   for an answer that carries no `results` (an older ad, a goal Meta leaves
   out): the action it optimised for. */
const GOAL_ACTION = {
  LEAD_GENERATION: ['onsite_conversion.lead_grouped', 'lead', 'offsite_conversion.fb_pixel_lead'],
  QUALITY_LEAD: ['onsite_conversion.lead_grouped', 'lead'],
  CONVERSATIONS: ['onsite_conversion.messaging_conversation_started_7d'],
  LINK_CLICKS: ['link_click'],
  LANDING_PAGE_VIEWS: ['landing_page_view'],
  POST_ENGAGEMENT: ['post_engagement'],
  PAGE_LIKES: ['like'],
  OFFSITE_CONVERSIONS: ['offsite_conversion.fb_pixel_purchase', 'purchase'],
  VALUE: ['offsite_conversion.fb_pixel_purchase', 'purchase'],
  PROFILE_VISIT: ['profile_visit_view'],
  VISIT_INSTAGRAM_PROFILE: ['profile_visit_view']
};

/* An ad's result: Meta's own `results` (its indicator and count) and
   `cost_per_result`, else the goal's action, else reach for a reach goal. */
export function resultOf(row) {
  const r = Array.isArray(row.results) ? row.results[0] : null;
  if (r && r.indicator) {
    const v = Array.isArray(r.values) && r.values[0] ? num(r.values[0].value) : null;
    const c = Array.isArray(row.cost_per_result) ? row.cost_per_result.find((x) => x && x.indicator === r.indicator) || row.cost_per_result[0] : null;
    const cv = c && Array.isArray(c.values) && c.values[0] ? num(c.values[0].value) : null;
    return { label: r.indicator, results: v === null ? 0 : v, cpr: cv };
  }
  const goal = String(row.optimization_goal || '').toUpperCase();
  if (goal === 'REACH') return { label: 'reach', results: num(row.reach), cpr: null };
  if (goal === 'THRUPLAY') return { label: 'video_thruplay_watched_actions', results: total(row.video_thruplay_watched_actions), cpr: null };
  const types = GOAL_ACTION[goal];
  if (types) {
    const v = actionOf(row.actions, types);
    return { label: 'actions:' + types[0], results: v === null ? 0 : v, cpr: null };
  }
  return { label: '', results: null, cpr: null };
}

const AD_COLS = ['Account ID', 'Account name', 'Ad ID', 'Ad name', 'Ad set name', 'Objective', 'Result indicator', 'Results',
  'Reach', 'Impressions', 'Amount spent', 'CTR (all)', 'Cost per result', '3-second video plays', 'ThruPlays', 'Video plays',
  'Video plays at 25%', 'Video plays at 50%', 'Video plays at 75%', 'Video plays at 95%', 'Video plays at 100%',
  'Video average play time', 'Reporting starts', 'Reporting ends'];

/* Ads Manager's export for the period: the account's own row (no ad name)
   first, then an ad a row. `account` is the account-level insights row (or
   null), `ads` the ad-level rows. */
export function adsText(account, ads, period) {
  const lines = [AD_COLS.join('\t')];
  const ps = period && period.start ? String(period.start).slice(0, 10) : '';
  const pe = period && period.end ? String(period.end).slice(0, 10) : '';
  if (account) {
    const row = {};
    row['Account ID'] = account.account_id; row['Account name'] = account.account_name;
    row['Reach'] = figure(account.reach); row['Impressions'] = figure(account.impressions); row['Amount spent'] = figure(account.spend, 2);
    row['Reporting starts'] = ps; row['Reporting ends'] = pe;
    lines.push(AD_COLS.map((k) => flat(row[k])).join('\t'));
  }
  (ads || []).forEach((a) => {
    if (!a || !flat(a.ad_name)) return;
    const res = resultOf(a);
    const row = {
      'Account ID': a.account_id, 'Account name': a.account_name, 'Ad ID': a.ad_id, 'Ad name': a.ad_name,
      'Ad set name': a.adset_name, 'Objective': a.objective, 'Result indicator': res.label,
      'Results': figure(res.results), 'Reach': figure(a.reach), 'Impressions': figure(a.impressions),
      'Amount spent': figure(a.spend, 2), 'CTR (all)': figure(a.ctr, 2),
      'Cost per result': res.cpr === null ? '' : res.cpr.toFixed(2),
      '3-second video plays': figure(actionOf(a.actions, 'video_view')),
      'ThruPlays': figure(total(a.video_thruplay_watched_actions)),
      'Video plays': figure(total(a.video_play_actions)),
      'Video plays at 25%': figure(total(a.video_p25_watched_actions)),
      'Video plays at 50%': figure(total(a.video_p50_watched_actions)),
      'Video plays at 75%': figure(total(a.video_p75_watched_actions)),
      'Video plays at 95%': figure(total(a.video_p95_watched_actions)),
      'Video plays at 100%': figure(total(a.video_p100_watched_actions)),
      'Video average play time': figure(total(a.video_avg_time_watched_actions)),
      'Reporting starts': a.date_start || ps, 'Reporting ends': a.date_stop || pe
    };
    lines.push(AD_COLS.map((k) => flat(row[k])).join('\t'));
  });
  return lines.join('\n');
}

const AGE_COLS = ['Account ID', 'Ad ID', 'Ad name', 'Ad set name', 'Objective', 'Result indicator', 'Age', 'Results', 'Impressions'];

/* The same ads by age: the importer reads an Age column as the age split of
   ads it already holds (matched by Ad ID). */
export function ageText(rows) {
  const lines = [AGE_COLS.join('\t')];
  (rows || []).forEach((a) => {
    if (!a || !flat(a.ad_name) || !flat(a.age)) return;
    const res = resultOf(a);
    const row = { 'Account ID': a.account_id, 'Ad ID': a.ad_id, 'Ad name': a.ad_name, 'Ad set name': a.adset_name,
      'Objective': a.objective, 'Result indicator': res.label, 'Age': a.age, 'Results': figure(res.results), 'Impressions': figure(a.impressions) };
    lines.push(AGE_COLS.map((k) => flat(row[k])).join('\t'));
  });
  return lines.length > 1 ? lines.join('\n') : '';
}

/* A post's lifetime insight from an insights list (`{ data: [{ name, values: [{ value }] }] }`). */
export function insightOf(ins, name) {
  const list = ins && Array.isArray(ins.data) ? ins.data : Array.isArray(ins) ? ins : [];
  const hit = list.find((x) => x && x.name === name);
  if (!hit) return null;
  if (hit.total_value && hit.total_value.value != null) return num(hit.total_value.value);
  const v = Array.isArray(hit.values) && hit.values.length ? hit.values[hit.values.length - 1].value : null;
  return typeof v === 'object' && v !== null ? Object.values(v).reduce((t, x) => t + (num(x) || 0), 0) : num(v);
}

function fbType(p) {
  const att = p.attachments && Array.isArray(p.attachments.data) ? p.attachments.data[0] : null;
  const mt = String(att && att.media_type || '').toLowerCase();
  if (/\/reel\//.test(String(p.permalink_url || ''))) return 'Reels';
  if (mt === 'album') return 'Album';
  if (mt === 'video') return 'Videos';
  if (mt === 'photo') return 'Photos';
  if (mt === 'link') return 'Links';
  return /photo/.test(String(p.status_type || '')) ? 'Photos' : /video/.test(String(p.status_type || '')) ? 'Videos' : 'Status';
}
function countOf(o) { return o && o.summary && o.summary.total_count != null ? num(o.summary.total_count) : null; }

const FB_COLS = ['Post ID', 'Publish time', 'Description', 'Permalink', 'Post type', 'Date', 'Views', 'Reach',
  'Reactions, comments and shares', 'Reactions', 'Comments', 'Shares'];

/* A Page's posts as Meta Business Suite's Lifetime export. `insights` on a
   post is the metrics read for it ({ views, reach }), each null where Meta
   did not answer. */
export function facebookText(posts) {
  const lines = [FB_COLS.join('\t')];
  (posts || []).forEach((p) => {
    if (!p || !p.id) return;
    const r = countOf(p.reactions), c = countOf(p.comments), s = p.shares && p.shares.count != null ? num(p.shares.count) : (r !== null || c !== null ? 0 : null);
    const all = [r, c, s].some((x) => x !== null) ? (r || 0) + (c || 0) + (s || 0) : null;
    const m = p.metrics || {};
    const row = { 'Post ID': p.id, 'Publish time': myTime(p.created_time), 'Description': p.message || '', 'Permalink': p.permalink_url || '',
      'Post type': fbType(p), 'Date': 'Lifetime', 'Views': figure(m.views), 'Reach': figure(m.reach),
      'Reactions, comments and shares': figure(all), 'Reactions': figure(r), 'Comments': figure(c), 'Shares': figure(s) };
    lines.push(FB_COLS.map((k) => cell(row[k])).join('\t'));
  });
  return lines.length > 1 ? lines.join('\n') : '';
}

function igType(m) {
  const pt = String(m.media_product_type || '').toUpperCase(), mt = String(m.media_type || '').toUpperCase();
  if (pt === 'REELS') return 'IG reel';
  if (pt === 'STORY') return 'IG story';
  if (mt === 'CAROUSEL_ALBUM') return 'IG carousel';
  if (mt === 'VIDEO') return 'IG video';
  return 'IG image';
}

const IG_COLS = ['Post ID', 'Publish time', 'Description', 'Permalink', 'Post type', 'Date', 'Views', 'Reach',
  'Likes', 'Comments', 'Shares', 'Saves'];

/* An Instagram account's media as the Lifetime export. `metrics` on a media
   is what its insights answered ({ views, reach, likes, comments, shares,
   saved }); like_count and comments_count stand in where insights do not. */
export function instagramText(media) {
  const lines = [IG_COLS.join('\t')];
  (media || []).forEach((m) => {
    if (!m || !m.id) return;
    const x = m.metrics || {};
    const likes = x.likes != null ? x.likes : m.like_count, comments = x.comments != null ? x.comments : m.comments_count;
    const row = { 'Post ID': m.id, 'Publish time': myTime(m.timestamp), 'Description': m.caption || '', 'Permalink': m.permalink || '',
      'Post type': igType(m), 'Date': 'Lifetime', 'Views': figure(x.views), 'Reach': figure(x.reach),
      'Likes': figure(likes), 'Comments': figure(comments), 'Shares': figure(x.shares), 'Saves': figure(x.saved) };
    lines.push(IG_COLS.map((k) => cell(row[k])).join('\t'));
  });
  return lines.length > 1 ? lines.join('\n') : '';
}

/* Meta's refusal, named in the page's terms. Codes from the Graph API's
   error object: 190 the token, 10/200-299 a permission, 4/17/32/613/80000+
   a rate limit, 100 with subcode 33 an object the system user cannot see. */
export function refusalOf(err) {
  const e = (err && err.error) || err || {};
  const code = Number(e.code), sub = Number(e.error_subcode);
  if (code === 190 || code === 102) return 'token-refused';
  if ([4, 17, 32, 613].indexOf(code) > -1 || (code >= 80000 && code < 80100)) return 'rate-limited';
  if (code === 10 || (code >= 200 && code < 300)) return 'not-assigned';
  if (code === 100 && sub === 33) return 'not-assigned';
  return 'meta-failed';
}
