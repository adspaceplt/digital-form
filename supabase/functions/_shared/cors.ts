/*
 * The one copy of who may call a portal edge function from a browser, and
 * of the answer's headers (2026-10-25; it stood copied in sixteen
 * functions). Sent with each function that imports it, in the same deploy
 * call, and read back beside it (CLAUDE.md §3).
 *
 * The portal's own origin is the install's, never typed here (restructure
 * release 9, 2026-11-28): the function setting PORTAL_ORIGIN, set equal to
 * `https://` and the agency profile's `portal_domain` (several origins,
 * comma separated, where an install answers on more than one). Read at
 * each call, so it stays synchronous. Unset, only the test server's two
 * origins are answered, and every browser on the portal is refused: the
 * setting is made before a function carrying this file is deployed.
 *
 * An origin not on the list is answered as the portal's own, so a browser
 * on another site is refused by its own CORS check. supabase-js sends
 * x-client-info and apikey as well: leaving them out fails the preflight,
 * which the page reads as "Failed to send a request".
 */
const LOCAL_ORIGINS = ['http://localhost:8899', 'http://127.0.0.1:8899'];

export function portalOrigins(): string[] {
  return String(Deno.env.get('PORTAL_ORIGIN') ?? '').split(',')
    .map((o) => o.trim().replace(/\/+$/, '')).filter((o) => /^https:\/\/[a-z0-9.-]+(:\d+)?$/i.test(o));
}

export function allowedOrigins(): string[] {
  return portalOrigins().concat(LOCAL_ORIGINS);
}

export function cors(origin: string | null) {
  const list = allowedOrigins();
  const allow = origin && list.includes(origin) ? origin : list[0];
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin'
  };
}

/* A JSON answer with the CORS headers; `extra` adds headers of the
   function's own (media-pass and sign-download: no-store). */
export function json(body: unknown, status: number, origin: string | null, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json', ...extra, ...cors(origin) }
  });
}
