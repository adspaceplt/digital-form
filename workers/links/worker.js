/*
 * The agency's short link redirector (its link domain)
 *
 * A Cloudflare Worker on a custom domain. It does one thing: take the first
 * path segment, ask the database where it goes, and send the visitor there.
 *
 * WHY THERE IS NO SERVICE ROLE KEY HERE
 * The plan recorded in supabase/schema.sql was for this to read the links
 * table with the service role. That would have put a key that can read and
 * write every table in the database into a Cloudflare secret so that a
 * redirector could look up one column. `link_resolve` is the narrower thing
 * that does the same job: one exact slug in, one destination and one state
 * out, with no listing, no search and no second column. The public anon key
 * is enough to call it, so nothing that can write ever leaves Supabase.
 * What this gives away is what a short link gives away by definition: hold
 * the slug, learn where it goes. That is the redirect itself.
 *
 * WHY 302 AND NOT 301
 * A 301 is cached by the browser more or less forever, so a destination
 * corrected in the console would never reach anybody who had already
 * followed the old one. The whole point of keeping these in a table is that
 * they can be changed. Every answer carries `no-store` for the same reason.
 *
 * The older QR host (README.md) is not served by this Worker and is
 * deliberately left alone: the QR codes already printed on slides encode
 * that whole address, so that host keeps redirecting through Rebrandly for
 * as long as those slides are in use. This host is what new links are built
 * with.
 *
 * The agency's values are the Worker's own settings, set equal to the
 * agency profile (restructure release 8, 2026-11-28; the Worker reads the
 * database with the public key alone, which the profile does not answer):
 * PORTAL_URL, HOME_URL, AGENCY_NAME (its trading name) and WORDMARK_URL.
 * None is typed here.
 *
 * Deploy: see README.md in this folder.
 */

/* The same shape the database constrains the column to (links_slug_shape),
   checked here so a request that cannot be a slug never costs a round trip. */
const SLUG = /^[a-z0-9][a-z0-9._-]{0,79}$/;

/* A client's review link as a short link (2026-10-12): /r/{review key} or
   /r/{review key}/{first eight characters of a content set's id}. Nothing is
   stored for it, so there is nothing to clean up: the address is the key the
   client already holds. A chat app reading it for its preview is answered a
   page that names the set and the brand (`review_link_preview`, the public
   key); everybody else is sent on to the review page, opened on that set. */
const REVIEW = /^r\/([A-Za-z0-9_-]{6,64})(?:\/([0-9a-f]{8}))?$/;
const PREVIEWER = /whatsapp|facebookexternalhit|facebot|twitterbot|slackbot|telegrambot|linkedinbot|discordbot|skypeuripreview|applebot|googlebot|bingbot|pinterest|redditbot|embedly|iframely|line\/|kakaotalk|viber|snapchat|microsoftpreview|teams/i;
const REVIEW_LINE = "This month's posts, shown the way they will appear on each platform. Approve, or tell us what to change.";
/* "{what} by {agency}", the agency's trading name from AGENCY_NAME. */
const by = (env, what) => what + ' by ' + (env.AGENCY_NAME || '');
const portal = (env) => String(env.PORTAL_URL || '').replace(/\/+$/, '');

async function reviewPreview(env, key, set) {
  const r = await fetch(env.SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/rpc/review_link_preview', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      apikey: env.SUPABASE_ANON_KEY,
      authorization: 'Bearer ' + env.SUPABASE_ANON_KEY
    },
    body: JSON.stringify({ p_key: key, p_set: set || null }),
    signal: AbortSignal.timeout(4000)
  });
  if (!r.ok) throw new Error('rpc ' + r.status);
  const d = await r.json();
  return d && typeof d === 'object' ? d : {};
}

/* "{Content set} {Brand} - Content Review Portal by {agency}", each part
   only where it is known. */
function reviewTitle(env, d) {
  const lead = [d.set, d.brand].filter(Boolean).join(' ');
  const name = by(env, 'Content Review Portal');
  return lead ? lead + ' - ' + name : name;
}

function previewPage(env, title, line, to) {
  const body = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="robots" content="noindex, nofollow">
<title>${esc(title)}</title>
<meta name="description" content="${esc(line)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="${esc(env.AGENCY_NAME || '')}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(line)}">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(line)}">
<meta http-equiv="refresh" content="0; url=${esc(to)}">
</head><body><a href="${esc(to)}">${esc(title)}</a></body></html>`;
  return new Response(body, {
    status: 200,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff'
    }
  });
}

async function review(request, env, key, set) {
  const to = portal(env) + '/review/?k=' + encodeURIComponent(key) + (set ? '#s-' + set : '');
  if (!PREVIEWER.test(request.headers.get('user-agent') || '')) return goTo(to);
  let d = {};
  try { d = await reviewPreview(env, key, set); }
  catch (e) { console.error('review_link_preview failed: ' + e.message); }
  return previewPage(env, reviewTitle(env, d), REVIEW_LINE, to);
}

/* The other links a client or a creator is sent, as short links
   (2026-10-13; the user: "video script and creator campaigns and creator
   portal … so we can show client brand name"). Re-lettered 2026-10-15 (the
   user: "use v for video script, take s back for selection", "C reserved
   for client portal"): /s/{key} a campaign's creator selection, /v/{key} a
   client's Video Scripts, /p/{code} a creator's own page, and /c alone the
   client portal's sign-in. A link sent before keeps working: an /s/ key
   that is a client's Video Scripts key opens their scripts (the two keys
   never overlap; `share_link_preview` `which` says which), and /c/{key}
   opens its campaign. As /r/, nothing is stored: the address is the key the
   link already carried. A chat app is answered a page naming the campaign
   and the brand where the key may show them (`share_link_preview`);
   everybody else is sent on to the page itself. */
const SHARE = /^([scvp])\/([A-Za-z0-9_-]{6,64})$/;
const PORTAL_ROUTE = /^c\/?$/;
const SHARE_KIND = {
  script: { kind: 'script', path: '/script/?k=', name: 'Video Scripts',
       line: 'The videos planned for the month, scene by scene.' },
  campaign: { kind: 'campaign', path: '/creators/?k=', name: 'Creator Selection',
       line: 'Choose the creators for this campaign, then follow their drafts and posts.' },
  creator: { kind: 'creator', path: '/creator/?k=', name: 'Creator Portal',
       line: 'The brief, the shoot and where to hand in the draft.' }
};
const LETTER_KIND = { v: 'script', c: 'campaign', p: 'creator' };

/* The visitor's own address, passed on beside the relay secret (the
   database's `ip_relay_secret`, kept on the Worker as IP_RELAY_SECRET), so a
   creator's code is counted against whoever asked, never against this
   Worker's one address (review 2026-10-29, 16: five bad lookups switched
   every creator preview off). Without the secret nothing is passed on. */
function relayHeaders(env, request) {
  const ip = request && (request.headers.get('cf-connecting-ip') || '');
  return env.IP_RELAY_SECRET && ip ? { 'x-adspace-relay': env.IP_RELAY_SECRET, 'x-adspace-ip': ip } : {};
}

async function sharePreview(env, kind, key, request) {
  const r = await fetch(env.SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/rpc/share_link_preview', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      apikey: env.SUPABASE_ANON_KEY,
      authorization: 'Bearer ' + env.SUPABASE_ANON_KEY,
      ...relayHeaders(env, request)
    },
    body: JSON.stringify({ p_kind: kind, p_key: key }),
    signal: AbortSignal.timeout(4000)
  });
  if (!r.ok) throw new Error('rpc ' + r.status);
  const d = await r.json();
  return d && typeof d === 'object' ? d : {};
}

/* Which kind an /s/ key is, kept a day at this edge (LNK-3, 2026-10-22):
   every visit, a person's as much as a previewer's, waited on the read
   before its 302. Only a kind the database named is kept; the two kinds'
   keys never overlap, and a key reset since reads as nothing on its page. */
const WHICH_TTL = 86400;
async function whichOf(env, key, request) {
  const store = typeof caches !== 'undefined' && caches.default ? caches.default : null;
  const slot = 'https://links.cache/which/' + encodeURIComponent(key);
  if (store) {
    try {
      const hit = await store.match(slot);
      if (hit) return (await hit.text()) || '';
    } catch (e) { console.error('which cache read failed: ' + e.message); }
  }
  let w = {};
  try { w = await sharePreview(env, 'which', key, request); }
  catch (e) { console.error('share_link_preview which failed: ' + e.message); return ''; }
  const kind = w.kind === 'script' || w.kind === 'campaign' ? w.kind : '';
  if (store && kind) {
    try {
      await store.put(slot, new Response(kind, { headers: { 'cache-control': 'max-age=' + WHICH_TTL } }));
    } catch (e) { console.error('which cache write failed: ' + e.message); }
  }
  return kind;
}

/* "{Campaign} {Brand} - Creator Selection by {agency}", each part only where
   it is known. */
async function share(request, env, letter, key) {
  let kind = LETTER_KIND[letter];
  if (letter === 's') {
    /* A selection key, else a Video Scripts link sent before 2026-10-15. A
       failed read sends it to the selection page, which says so if it is
       not one. */
    kind = (await whichOf(env, key, request)) === 'script' ? 'script' : 'campaign';
  }
  const k = SHARE_KIND[kind];
  const base = portal(env);
  const to = base + k.path + encodeURIComponent(key);
  if (!PREVIEWER.test(request.headers.get('user-agent') || '')) return goTo(to);
  let d = {};
  try { d = await sharePreview(env, k.kind, key, request); }
  catch (e) { console.error('share_link_preview failed: ' + e.message); }
  const lead = [d.title, d.brand].filter(Boolean).join(' ');
  const name = by(env, k.name);
  return previewPage(env, lead ? lead + ' - ' + name : name, k.line, to);
}

/* One page, four outcomes. The title says what happened and the line says
   what to do about it, which is the rule every cover in the portal follows;
   neither repeats the other. A short link is opened by people who are not
   our clients and have no account manager, so the line names the agency alone
   (the user, 2026-10-27). */
const SAY = {
  missing: ['Link not recognised', 'Please contact {agency}.'],
  paused:  ['Link expired', 'Please contact {agency}.'],
  revoked: ['Code withdrawn', 'Please contact {agency}.'],
  failed:  ['Unable to load', 'Please try again in a moment.']
};

const STATUS = { missing: 404, paused: 404, revoked: 410, failed: 502 };

function esc(s) {
  return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

/* Flat, quiet, one column, the portal's own neutrals and no framework. The
   mark sits in a bar at the top left, as the portal's 404 draws it (the
   user, 2026-10-27): the portal's bar height, its rule under it, the mark
   at 26px on the 24px edge (16 on a phone); the panel on the optical centre
   of what is left; no foot. The mark is the only fetch on the page and the
   wordmark stands in if it fails, exactly as js/chrome.js does. */
function page(env, kind) {
  const [title, said] = SAY[kind] || SAY.missing;
  const line = said.replace('{agency}', env.AGENCY_NAME || '');
  const body = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<meta name="theme-color" content="#ffffff">
<title>${esc(title)}</title>
<style>
  :root { color-scheme: light; --head-h: 64px; }
  * { box-sizing: border-box; }
  html, body { height: 100%; }
  body {
    margin: 0; display: flex; flex-direction: column; background: #fff;
    color: #1a1a1a;
    font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }
  .bar {
    height: var(--head-h); flex: 0 0 auto; display: flex; align-items: center;
    padding: 0 24px; border-bottom: 1px solid #e0e0e0;
  }
  .bar img { height: 26px; width: auto; display: block;
    object-fit: contain; object-position: left center; }
  .bar b { font-weight: 600; font-size: 19px; }
  main {
    flex: 1 1 auto; display: flex; align-items: center; justify-content: center;
    padding: 24px 24px calc(24px + var(--head-h) / 2);
  }
  .panel { max-width: 420px; width: 100%; text-align: center; }
  h1 { margin: 0 0 8px; font-size: 24px; font-weight: 600; letter-spacing: -.02em; line-height: 1.3; }
  p { margin: 0; color: #666666; font-size: 15px; }
  @media (max-width: 640px) {
    :root { --head-h: 56px; }
    .bar { padding: 0 16px; }
    main { padding: 20px 16px calc(20px + var(--head-h) / 2); }
  }
</style>
</head><body>
  <header class="bar">
    <img src="${esc(env.WORDMARK_URL || '')}" alt="${esc(env.AGENCY_NAME || '')}"
         onerror="this.replaceWith(Object.assign(document.createElement('b'),{textContent:'${esc(String(env.AGENCY_NAME || '').replace(/[\\']/g, '\\$&'))}'}))">
  </header>
  <main>
    <div class="panel">
      <h1>${esc(title)}</h1>
      <p>${esc(line)}</p>
    </div>
  </main>
</body></html>`;
  return new Response(body, {
    status: STATUS[kind] || 404,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff'
    }
  });
}

function goTo(url) {
  return new Response(null, {
    status: 302,
    headers: { location: url, 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' }
  });
}

/* Whatever the visitor arrived with, minus the code that got them here.
   A client who appends ?utm_source to a printed link expects it to reach the
   page, and a redirector that eats it loses the attribution the link was
   printed for. The target's own parameters win: they were set deliberately
   in the console, the incoming ones were appended by whoever shared it. */
function carryQuery(target, from) {
  let out;
  try { out = new URL(target); } catch { return target; }
  for (const [k, v] of from) {
    if (k === 'q') continue;
    if (!out.searchParams.has(k)) out.searchParams.append(k, v);
  }
  return out.toString();
}

async function resolve(env, slug, code) {
  const r = await fetch(env.SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/rpc/link_resolve', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      apikey: env.SUPABASE_ANON_KEY,
      authorization: 'Bearer ' + env.SUPABASE_ANON_KEY
    },
    body: JSON.stringify({ p_slug: slug, p_qr: code || null }),
    /* A redirect nobody is waiting for is worse than one that fails fast:
       the visitor is looking at a blank tab until this answers. */
    signal: AbortSignal.timeout(5000)
  });
  if (!r.ok) throw new Error('rpc ' + r.status);
  const rows = await r.json();
  return Array.isArray(rows) && rows.length ? rows[0] : { url: null, state: 'missing' };
}

/* A day's visit counted after the visitor is on their way (SHORT LINK
   CLICKS, 2026-11-27): the redirect never waits on it, and a count that
   fails is lost, never retried. Counts only: the slug and the QR code,
   nothing about the visitor. */
async function hit(env, slug, code) {
  try {
    await fetch(env.SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/rpc/link_hit', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        apikey: env.SUPABASE_ANON_KEY,
        authorization: 'Bearer ' + env.SUPABASE_ANON_KEY
      },
      body: JSON.stringify({ p_slug: slug, p_qr: code || null }),
      signal: AbortSignal.timeout(5000)
    });
  } catch (e) {
    console.error('link_hit failed for ' + slug + ': ' + e.message);
  }
}

export default {
  async fetch(request, env, ctx) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405, headers: { allow: 'GET, HEAD' } });
    }

    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/+|\/+$/g, '');

    /* The bare host is not a link. Somebody who types it has half a URL, so
       they go to the website rather than to a refusal. */
    if (!path) return goTo(env.HOME_URL);

    /* A short link host has nothing worth indexing and a slug is not meant
       to be discoverable, so nothing here is crawled. */
    if (path === 'robots.txt') {
      return new Response('User-agent: *\nDisallow: /\n', {
        headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'public, max-age=86400' }
      });
    }
    if (path === 'favicon.ico') return new Response(null, { status: 204 });

    const rv = REVIEW.exec(path);
    if (rv) return review(request, env, rv[1], rv[2]);
    const sh = SHARE.exec(path);
    if (sh) return share(request, env, sh[1], sh[2]);
    /* /c alone is the client portal, which signs in by email (2026-10-15). */
    if (PORTAL_ROUTE.test(path)) return goTo(portal(env) + '/client/');

    /* A slug is one segment. Anything deeper is not a link we issued, and
       asking the database about it would only be a slower way to say so. */
    const slug = path.toLowerCase();
    if (!SLUG.test(slug)) return page(env, 'missing');

    let row;
    try {
      row = await resolve(env, slug, (url.searchParams.get('q') || '').trim());
    } catch (e) {
      /* The database's own words never reach a visitor. The console is where
         a message somebody can act on belongs; here it is one line and a
         retry. */
      console.error('link_resolve failed for ' + slug + ': ' + e.message);
      return page(env, 'failed');
    }

    if (row.state !== 'ok' || !row.url) return page(env, row.state === 'ok' ? 'missing' : row.state);
    /* A person's visit is counted; a HEAD (a link checker) is not. */
    if (request.method === 'GET' && ctx && ctx.waitUntil) ctx.waitUntil(hit(env, slug, (url.searchParams.get('q') || '').trim()));
    return goTo(carryQuery(row.url, url.searchParams));
  }
};
