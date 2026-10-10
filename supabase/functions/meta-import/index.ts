/*
 * meta-import — a report's figures straight from Meta (2026-10-08).
 *
 * The team works in ADspace's own Meta business portfolio; clients share
 * their ad accounts, Pages and Instagram accounts with it as a partner, and a
 * system user ("ADspace Portal") is assigned every one. Its token reads them
 * here and nowhere else: it never reaches a browser.
 *
 * Actions (POST { action, … }):
 *   assets               what the system user can see, for the picker on a
 *                        client's Brand (Clients at Work).
 *   ads { report_id, account }
 *                        the period's ad-level insights, the account's own
 *                        row (reach counted once) and the ads by age, written
 *                        as Ads Manager's export (shape.mjs), for the page's
 *                        own importer. Reports at Work, an Advertising Report
 *                        in draft, the account one the report's client (or
 *                        brand) has linked.
 *   posts { report_id, source: 'facebook' | 'instagram' }
 *                        the linked Page's posts or Instagram account's media
 *                        published in the period with their lifetime
 *                        insights, as Meta Business Suite's export. Reports
 *                        at Work, a Social Media Accounts Report in draft.
 *   pictures { report_id, urls }
 *                        the pictures the ads or posts read named (2026-10-10:
 *                        a post's image or cover frame, an ad's creative),
 *                        fetched from Meta's own image hosts alone (at most
 *                        six, 4 MB each) and answered as base64, so the page
 *                        draws them down to its 320px thumbnail and keeps
 *                        them: Meta's addresses expire within days. Reports
 *                        at Work, a draft.
 *   `audit: true` on either (the Report audit, 2026-10-09) reads the same for
 *                        the page to compare, never to import: an Advertising
 *                        Report in review or confirmed too, since Meta is
 *                        read again before Publish. An Accounts Report is
 *                        read in draft alone (a post's figures are lifetime
 *                        totals; the reading it was submitted on stands).
 *
 * The caller is checked as report-draft checks it: the database is asked as
 * the caller (`allowed`, the report read under its own policies and client
 * scope, the links through `meta_links_list`), so a colleague outside the
 * client's scope reads nothing. Every figure is Meta's; nothing is written
 * here: the page imports through the importer a paste goes through.
 *
 * Secrets: META_SYSTEM_TOKEN (the system user's token; until it is set every
 * action answers `not-connected`), META_APP_SECRET (optional: each call then
 * carries appsecret_proof), META_GRAPH_VERSION (optional, default v26.0),
 * plus the platform's SUPABASE_URL and SUPABASE_ANON_KEY. docs/META-SETUP.md.
 *
 * A refusal answers 200 with { error } in the page's terms: not-connected,
 * token-refused, not-assigned, rate-limited, meta-failed, no-mapping,
 * denied, not-found, not-draft, wrong-kind. Meta's own words go to the log,
 * never to the page.
 *
 * Deploy with Verify JWT off, as every console function: the preflight
 * carries no Authorization header, and this function asks the database
 * about the caller itself.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { adsText, ageText, facebookText, instagramText, periodWindow, refusalOf, insightOf } from './shape.mjs';

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
function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }

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

/* One Graph call. A path or a full `paging.next` address. */
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
/* Every page of an edge, up to a bound. */
async function all(path: string, params: Record<string, string>, max = 20, token?: string, stop?: (row: Record<string, unknown>) => boolean) {
  const out: Record<string, unknown>[] = [];
  let next: string | null = path, first = true;
  for (let i = 0; next && i < max; i++) {
    const body = await graph(next, first ? params : {}, token);
    first = false;
    const rows = (body.data || []) as Record<string, unknown>[];
    let done = false;
    for (const r of rows) { if (stop && stop(r)) { done = true; break; } out.push(r); }
    const pg = body.paging as Record<string, unknown> | undefined;
    next = !done && pg && typeof pg.next === 'string' ? pg.next : null;
  }
  return out;
}

const AD_FIELDS = ['account_id', 'account_name', 'ad_id', 'ad_name', 'adset_name', 'objective', 'optimization_goal', 'reach', 'impressions',
  'spend', 'ctr', 'actions', 'video_play_actions', 'video_thruplay_watched_actions', 'video_p25_watched_actions', 'video_p50_watched_actions',
  'video_p75_watched_actions', 'video_p95_watched_actions', 'video_p100_watched_actions', 'video_avg_time_watched_actions'];
const RESULT_FIELDS = ['results', 'cost_per_result'];

async function adInsights(act: string, range: string, extra: Record<string, string>, fields: string[]) {
  const ask = (f: string[]) => all(act + '/insights', { level: 'ad', time_range: range, fields: f.join(','), limit: '500', ...extra }, 40);
  try { return await ask(fields.concat(RESULT_FIELDS)); } catch (e) {
    /* An API version that names no `results` field refuses the whole call:
       the goal's own action stands in (shape.mjs resultOf). */
    const b = (e as MetaError).body as Record<string, Record<string, unknown>> | undefined;
    if (b && b.error && Number(b.error.code) === 100 && /result/i.test(String(b.error.message || ''))) return ask(fields);
    throw e;
  }
}

/* A metric for many objects at once (`?ids=`), each metric asked on its
   own so a metric Meta has retired drops only its own column. */
async function metricFor(ids: string[], metric: string, token?: string, period?: string): Promise<Record<string, number | null>> {
  const out: Record<string, number | null> = {};
  for (let i = 0; i < ids.length; i += 50) {
    const part = ids.slice(i, i + 50);
    const body = await graph('', { ids: part.join(','), fields: 'insights.metric(' + metric + ')' + (period ? '.period(' + period + ')' : '') }, token);
    part.forEach((id) => { out[id] = insightOf(((body[id] || {}) as Record<string, unknown>).insights, metric); });
  }
  return out;
}
async function metrics(ids: string[], names: Record<string, string>, token?: string, period?: string) {
  const got: Record<string, Record<string, number | null>> = {};
  ids.forEach((id) => { got[id] = {}; });
  for (const [key, metric] of Object.entries(names)) {
    try {
      const m = await metricFor(ids, metric, token, period);
      ids.forEach((id) => { got[id][key] = m[id]; });
    } catch (e) {
      const kind = refusalOf((e as MetaError).body);
      if (kind === 'token-refused' || kind === 'rate-limited') throw e;
      console.error('meta-import: metric left out', metric, JSON.stringify((e as MetaError).body || {}).slice(0, 300));
    }
  }
  return got;
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const action = String(body.action || '');
  if (['assets', 'ads', 'posts', 'pictures'].indexOf(action) < 0) return json({ error: 'bad-request' }, 400, origin);

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });

  if (action === 'assets') {
    const may = await db.rpc('allowed', { p_section: 'clients', p_level: 'work' });
    if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);
  }
  if (!TOKEN()) return json({ error: 'not-connected' }, 200, origin);

  try {
    if (action === 'assets') {
      const byName = (a: { name: string }, b: { name: string }) => a.name.localeCompare(b.name);
      const acts = await all('me/adaccounts', { fields: 'account_id,name', limit: '200' });
      const pages = await all('me/accounts', { fields: 'id,name,instagram_business_account{id,username,name}', limit: '200' });
      const ig: Record<string, { id: string; name: string }> = {};
      pages.forEach((p) => {
        const i = p.instagram_business_account as Record<string, string> | undefined;
        if (i && i.id) ig[i.id] = { id: String(i.id), name: String(i.username || i.name || i.id) };
      });
      return json({
        ad_accounts: acts.map((a) => ({ id: String(a.account_id || String(a.id || '').replace(/^act_/, '')), name: String(a.name || a.account_id) })).sort(byName),
        pages: pages.map((p) => ({ id: String(p.id), name: String(p.name || p.id) })).sort(byName),
        instagram: Object.values(ig).sort(byName)
      }, 200, origin);
    }

    const id = String(body.report_id || '');
    if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: 'bad-request' }, 400, origin);
    const may = await db.rpc('allowed', { p_section: 'reports', p_level: 'work' });
    if (may.error || may.data !== true) return json({ error: 'denied' }, 200, origin);
    /* Meta checks (2026-10-10): the Business setting on and the caller
       holding Reports: Meta import and audit, as the database answers it. */
    const on = await db.rpc('meta_checks_on');
    if (on.error || on.data !== true) return json({ error: 'meta-off' }, 200, origin);
    const rep = await db.from('sm_reports').select('id, kind, status, period_start, period_end, client_id, brand_id').eq('id', id).maybeSingle();
    if (rep.error || !rep.data) return json({ error: 'not-found' }, 200, origin);
    const r = rep.data as Record<string, string | null>;
    const audit = body.audit === true && action === 'ads' && (r.status === 'review' || r.status === 'confirmed');
    if (r.status !== 'draft' && !audit) return json({ error: 'not-draft' }, 200, origin);
    if (action === 'pictures') {
      /* Only Meta's own image hosts are fetched: the addresses came from
         this report's own read, and nothing else is reached from here. */
      const urls = (Array.isArray(body.urls) ? body.urls : []).map(String)
        .filter((u) => { try { const h = new URL(u); return h.protocol === 'https:' && /(^|\.)(fbcdn\.net|cdninstagram\.com)$/.test(h.hostname); } catch { return false; } })
        .slice(0, 6);
      const pictures = await Promise.all(urls.map(async (u) => {
        try {
          const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 10000);
          const res = await fetch(u, { signal: ctl.signal }); clearTimeout(t);
          const type = res.headers.get('content-type') || '';
          if (!res.ok || !/^image\//.test(type)) return { url: u, error: 'not-read' };
          const buf = new Uint8Array(await res.arrayBuffer());
          if (buf.length > 4 * 1024 * 1024) return { url: u, error: 'too-large' };
          let bin = '';
          for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
          return { url: u, type: type.split(';')[0], b64: btoa(bin) };
        } catch { return { url: u, error: 'not-read' }; }
      }));
      return json({ pictures }, 200, origin);
    }
    if ((action === 'ads') !== (r.kind === 'ads')) return json({ error: 'wrong-kind' }, 200, origin);
    const lk = await db.rpc('meta_links_list', { p_client: r.client_id });
    const ld = (lk.data || {}) as Record<string, unknown>;
    if (lk.error || ld.error) return json({ error: lk.error ? 'needs-update' : 'denied' }, 200, origin);
    const mine = ((ld.links || []) as Record<string, unknown>[]).find((x) => (x.brand_id || null) === (r.brand_id || null)) || {};

    if (action === 'ads') {
      const accounts = (mine.ad_accounts || []) as { id: string; name: string }[];
      const acc = accounts.find((a) => a.id === String(body.account || '').replace(/^act_/, ''));
      if (!acc) return json({ error: 'no-mapping' }, 200, origin);
      const act = 'act_' + acc.id;
      const range = JSON.stringify({ since: String(r.period_start).slice(0, 10), until: String(r.period_end).slice(0, 10) });
      const head = await graph(act + '/insights', { level: 'account', time_range: range, fields: 'account_id,account_name,reach,impressions,spend' });
      const account = ((head.data || []) as Record<string, unknown>[])[0] || null;
      const ads = await adInsights(act, range, {}, AD_FIELDS);
      const ages = await adInsights(act, range, { breakdowns: 'age' }, ['account_id', 'ad_id', 'ad_name', 'adset_name', 'objective', 'optimization_goal', 'impressions', 'reach', 'actions', 'video_thruplay_watched_actions']);
      const period = { start: r.period_start, end: r.period_end };
      /* Each ad's creative picture, for its thumbnail (2026-10-10); a read
         Meta refuses leaves the ads without, never the import. */
      const pics: Record<string, string> = {};
      if (!audit) {
        const ids = [...new Set(ads.map((a) => String(a.ad_id || '')).filter(Boolean))];
        for (let i = 0; i < ids.length; i += 50) {
          try {
            const got = await graph('', { ids: ids.slice(i, i + 50).join(','), fields: 'creative{image_url,thumbnail_url}' });
            for (const id of ids.slice(i, i + 50)) {
              const c = ((got[id] || {}) as Record<string, Record<string, string>>).creative || {};
              if (c.image_url || c.thumbnail_url) pics[id] = c.image_url || c.thumbnail_url;
            }
          } catch (e) { console.error('meta-import: pictures left out', JSON.stringify((e as MetaError).body || {}).slice(0, 300)); }
        }
      }
      return json({ account: acc, ads: ads.length, text: ads.length || account ? adsText(account, ads, period) : '', age: ageText(ages), pics }, 200, origin);
    }

    const source = body.source === 'instagram' ? 'instagram' : 'facebook';
    const link = mine[source === 'instagram' ? 'instagram' : 'page'] as { id: string; name: string } | null | undefined;
    if (!link || !link.id) return json({ error: 'no-mapping' }, 200, origin);
    const win = periodWindow(r.period_start, r.period_end);
    if (source === 'facebook') {
      const pg = await graph(link.id, { fields: 'access_token,name' });
      const ptoken = String(pg.access_token || '');
      if (!ptoken) return json({ error: 'not-assigned' }, 200, origin);
      const posts = await all(link.id + '/published_posts', {
        fields: 'id,created_time,message,permalink_url,full_picture,status_type,attachments{media_type},shares,reactions.summary(total_count).limit(0),comments.summary(total_count).limit(0)',
        since: String(win.since), until: String(win.until), limit: '100'
      }, 10, ptoken);
      const m = posts.length ? await metrics(posts.map((p) => String(p.id)), { views: 'post_media_view', reach: 'post_impressions_unique' }, ptoken, 'lifetime') : {};
      posts.forEach((p) => { (p as Record<string, unknown>).metrics = m[String(p.id)] || {}; });
      const pics: Record<string, string> = {};
      posts.forEach((p) => { if (p.permalink_url && p.full_picture) pics[String(p.permalink_url)] = String(p.full_picture); });
      return json({ source, name: link.name, posts: posts.length, text: facebookText(posts), pics }, 200, origin);
    }
    /* Instagram lists media newest first; the walk stops at the first one
       before the period. */
    const media = (await all(link.id + '/media', {
      fields: 'id,caption,media_type,media_product_type,permalink,media_url,thumbnail_url,timestamp,like_count,comments_count', limit: '100'
    }, 10, undefined, (x) => Date.parse(String(x.timestamp).replace(/\+0000$/, 'Z')) / 1000 < win.since))
      .filter((x) => Date.parse(String(x.timestamp).replace(/\+0000$/, 'Z')) / 1000 < win.until);
    const m = media.length ? await metrics(media.map((x) => String(x.id)),
      { views: 'views', reach: 'reach', likes: 'likes', comments: 'comments', shares: 'shares', saved: 'saved' }) : {};
    media.forEach((x) => { (x as Record<string, unknown>).metrics = m[String(x.id)] || {}; });
    const pics: Record<string, string> = {};
    media.forEach((x) => { const u = x.thumbnail_url || (x.media_type !== 'VIDEO' ? x.media_url : null); if (x.permalink && u) pics[String(x.permalink)] = String(u); });
    return json({ source, name: link.name, posts: media.length, text: instagramText(media), pics }, 200, origin);
  } catch (e) {
    const b = e instanceof MetaError ? e.body : { message: String((e as Error).message || e) };
    console.error('meta-import: Meta refused', action, JSON.stringify(b || {}).slice(0, 500));
    return json({ error: e instanceof MetaError ? refusalOf(b) : 'meta-failed' }, 200, origin);
  }
});
