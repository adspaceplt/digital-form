/*
 * The one copy of who may call a portal edge function from a browser, and
 * of the answer's headers (2026-10-25; it stood copied in sixteen
 * functions). Sent with each function that imports it, in the same deploy
 * call, and read back beside it (CLAUDE.md §3).
 *
 * An origin not on the list is answered as the portal's own, so a browser
 * on another site is refused by its own CORS check. supabase-js sends
 * x-client-info and apikey as well: leaving them out fails the preflight,
 * which the page reads as "Failed to send a request".
 */
export const ALLOWED_ORIGINS = [
  'https://digital.adspace.me',
  'http://localhost:8899',
  'http://127.0.0.1:8899'
];

export function cors(origin: string | null) {
  const allow = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
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
