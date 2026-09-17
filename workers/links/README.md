# hi.adspace.me — the short link redirector

A Cloudflare Worker on a custom domain. `worker.js` is the whole thing: take
the first path segment, ask `link_resolve` where it goes, send the visitor
there. The list it serves is managed in the console under Short Links.

## What is where

| Thing | Value |
|---|---|
| Cloudflare account | ADspace, `d6256817c1b5ab6dffa93b30e68902d5` |
| Zone | `adspace.me`, `1920dc7ba9f24093edfdb4edc414aede` |
| Worker | `adspace-links` |
| Custom domain | `hi.adspace.me` (Cloudflare creates the DNS record and the certificate) |
| Database | `public.link_resolve(p_slug, p_qr)` in `supabase/schema.sql` |

`go.adspace.me` is **not** served by this Worker and is deliberately left
alone. Every QR code already printed on a slide encodes that whole address,
so that host keeps redirecting through Rebrandly for as long as those slides
are in use. `ADSPACE_CONFIG.linkHost` decides what the *next* link is built
with, and that is `hi.adspace.me`.

## The three variables

Plain text vars on the Worker, not secrets, because none of them is one:

- `SUPABASE_URL` — the project URL
- `SUPABASE_ANON_KEY` — the public key, the same one `js/config.js` carries
- `HOME_URL` — where the bare host sends somebody, `https://adspacestudios.com`

There is no service role key here, and that is the point. See the comment at
the top of `worker.js`: `link_resolve` answers one exact slug with one
destination, so the public key is enough and nothing that can write ever
leaves Supabase.

## What it answers

| Case | Answer |
|---|---|
| Live slug | `302` to the destination, `Cache-Control: no-store` |
| Live slug, live `?q=` code | the same `302` |
| Slug we never issued, or a path with more than one segment | `404`, "Link not recognised" |
| Slug the team has paused | `404`, "Link paused" |
| `?q=` code that is revoked, or belongs to another slug | `410`, "Code withdrawn" |
| The database could not be reached | `502`, "Unable to load" |
| The bare host | `302` to `HOME_URL` |
| `robots.txt` | `Disallow: /` |

302 and never 301: a 301 is cached by the browser more or less forever, so a
destination corrected in the console would never reach anybody who had
already followed the old one. The whole reason these live in a table is that
they can be changed.

Query parameters a visitor arrived with are carried onto the destination,
minus `q`. A client who appends `?utm_source=` to a printed link expects it
to reach the page. The destination's own parameters win, because those were
set deliberately in the console.

## Deploying a change

The Worker was uploaded through the Cloudflare API. With Wrangler installed,
from this folder:

```
npx wrangler deploy worker.js --name adspace-links --compatibility-date 2026-09-01
```

The variables are already set on the Worker and survive a redeploy of the
code. If they ever need to be set again, they are three plain text vars in
the dashboard under Workers > adspace-links > Settings > Variables.

## Checking it

```
curl -sSI https://hi.adspace.me/<a live slug>     # 302, and the Location
curl -sSI https://hi.adspace.me/definitely-not    # 404
curl -sSI https://hi.adspace.me/                  # 302 to adspacestudios.com
```

A `502` on every slug means `link_resolve` is not in the database yet: run
`supabase/migrations/2026-09-20-link-resolve-for-the-redirector.sql`.
