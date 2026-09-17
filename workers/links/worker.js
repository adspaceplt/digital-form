/*
 * hi.adspace.me — the ADspace short link redirector
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
 * go.adspace.me is not served by this Worker and is deliberately left alone:
 * the QR codes already printed on slides encode that whole address, so that
 * host keeps redirecting through Rebrandly for as long as those slides are
 * in use. This host is what new links are built with.
 *
 * Deploy: see README.md in this folder.
 */

/* The same shape the database constrains the column to (links_slug_shape),
   checked here so a request that cannot be a slug never costs a round trip. */
const SLUG = /^[a-z0-9][a-z0-9._-]{0,79}$/;

/* One page, four outcomes. The title says what happened and the line says
   what to do about it, which is the rule every cover in the portal follows;
   neither repeats the other. A short link is opened by people who are not
   our clients, so the line names the account manager rather than assuming
   the reader knows who we are. */
const SAY = {
  missing: ['Link not recognised', 'Please check the link or contact your ADspace account manager.'],
  paused:  ['Link paused', 'Please contact your ADspace account manager.'],
  revoked: ['Code withdrawn', 'Please contact your ADspace account manager.'],
  failed:  ['Unable to load', 'Please try again in a moment.']
};

const STATUS = { missing: 404, paused: 404, revoked: 410, failed: 502 };

function esc(s) {
  return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

/* Flat, quiet, one column, the portal's own neutrals and no framework. The
   mark is the only fetch on the page and the wordmark stands in if it fails,
   exactly as js/chrome.js does. */
function page(kind) {
  const [title, line] = SAY[kind] || SAY.missing;
  const body = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${esc(title)}</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: flex; align-items: center;
    justify-content: center; padding: 24px 16px; background: #f5f5f5;
    color: #1b1a17; line-height: 1.55;
    font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }
  .panel {
    background: #fff; border: 1px solid #e2dfd8; border-radius: 14px;
    box-shadow: 0 1px 2px rgba(19, 24, 26, .05);
    padding: 32px 28px; max-width: 420px; width: 100%; text-align: center;
  }
  .mark { height: 22px; width: auto; margin-bottom: 20px; }
  h1 { margin: 0 0 8px; font-size: 24px; font-weight: 600; letter-spacing: -.02em; }
  p { margin: 0; color: #6b6760; font-size: 15px; }
</style>
</head><body>
  <main class="panel">
    <img class="mark" src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace"
         onerror="this.replaceWith(Object.assign(document.createElement('b'),{textContent:'ADspace'}))">
    <h1>${esc(title)}</h1>
    <p>${esc(line)}</p>
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

export default {
  async fetch(request, env) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405, headers: { allow: 'GET, HEAD' } });
    }

    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/+|\/+$/g, '');

    /* The bare host is not a link. Somebody who types it has half a URL, so
       they go to the website rather than to a refusal. */
    if (!path) return goTo(env.HOME_URL || 'https://adspacestudios.com');

    /* A short link host has nothing worth indexing and a slug is not meant
       to be discoverable, so nothing here is crawled. */
    if (path === 'robots.txt') {
      return new Response('User-agent: *\nDisallow: /\n', {
        headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'public, max-age=86400' }
      });
    }
    if (path === 'favicon.ico') return new Response(null, { status: 204 });

    /* A slug is one segment. Anything deeper is not a link we issued, and
       asking the database about it would only be a slower way to say so. */
    const slug = path.toLowerCase();
    if (!SLUG.test(slug)) return page('missing');

    let row;
    try {
      row = await resolve(env, slug, (url.searchParams.get('q') || '').trim());
    } catch (e) {
      /* The database's own words never reach a visitor. The console is where
         a message somebody can act on belongs; here it is one line and a
         retry. */
      console.error('link_resolve failed for ' + slug + ': ' + e.message);
      return page('failed');
    }

    if (row.state !== 'ok' || !row.url) return page(row.state === 'ok' ? 'missing' : row.state);
    return goTo(carryQuery(row.url, url.searchParams));
  }
};
