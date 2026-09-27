/*
 * push-send — delivers the queued notifications (`push_outbox`) to the
 * devices that follow them, and makes the sender's keys on its first run.
 *
 * The database wakes it after a write commits (`push_kick`, through pg_net),
 * so a call carries nothing and needs nothing: it takes what is queued and
 * sends it. A call with nothing queued does nothing. Anybody may call it,
 * because all it can do is send what the database already queued.
 *
 * Keys: the first run makes the VAPID pair and keeps it in `app_secrets`
 * (`push_set_keys`); only the public half ever leaves the database. The
 * function reads the database with the platform's own service role key, so
 * there is no secret to set.
 *
 * Deploy:  supabase functions deploy push-send
 * Turn OFF "Verify JWT": the database's wake carries no token.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { send, vapidKeys } from './webpush.js';

const SUBJECT = 'mailto:advertise@adspacestudios.com';
const TTL = 86400;          // a day: a phone off for longer gets nothing stale
const ROUNDS = 5;           // at most 5 × 50 messages a wake; the next wake takes the rest

/* The push services the database accepts (push_endpoint_ok). Checked again
   here so this function never posts anywhere else, whatever a row holds. */
const HOST_OK = /^(fcm\.googleapis\.com|android\.googleapis\.com|([a-z0-9-]+\.)*push\.apple\.com|updates\.push\.services\.mozilla\.com|([a-z0-9-]+\.)*notify\.windows\.com)$/;

type Sub = { id: string; endpoint: string; p256dh: string; auth: string; lang: string };
type Msg = { id: string; message: Record<string, { title?: string; body?: string }>; url: string; tag: string | null; subs: Sub[] };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } });

  let { data: keys, error } = await db.rpc('push_keys');
  if (error) return json({ error: 'push-not-set-up', reason: error.message });
  if (!keys?.public || !keys?.private) {
    const made = await vapidKeys();
    const r = await db.rpc('push_set_keys', { p_public: made.publicKey, p_private: made.privateJwk });
    if (r.error) return json({ error: 'push-keys', reason: r.error.message });
    keys = r.data;
  }
  const pair = { publicKey: keys.public as string, privateJwk: keys.private as string };

  let sent = 0, failed = 0, messages = 0;
  for (let round = 0; round < ROUNDS; round++) {
    const { data: batch, error: e } = await db.rpc('push_claim', { p_limit: 50 });
    if (e) return json({ error: 'push-claim', reason: e.message, sent, failed });
    if (!Array.isArray(batch) || !batch.length) break;
    for (const m of batch as Msg[]) {
      let ok = 0, bad = 0;
      const dead: string[] = [];
      await Promise.all((m.subs || []).map(async (s) => {
        let host = '';
        try { host = new URL(s.endpoint).hostname; } catch (_) { /* refused below */ }
        if (!s.endpoint.startsWith('https://') || !HOST_OK.test(host)) { bad++; dead.push(s.id); return; }
        const words = m.message?.[s.lang] || m.message?.en || {};
        try {
          const r = await send(s, { title: words.title || 'ADspace', body: words.body || '', url: m.url, tag: m.tag },
            pair, SUBJECT, TTL);
          if (r.status >= 200 && r.status < 300) ok++;
          else {
            bad++;
            // The push service no longer knows the device: it unsubscribed,
            // or the browser's data was cleared.
            if (r.status === 404 || r.status === 410) dead.push(s.id);
          }
        } catch (_) { bad++; }
      }));
      await db.rpc('push_done', { p_outbox: m.id, p_sent: ok, p_failed: bad, p_dead: dead });
      sent += ok; failed += bad; messages++;
    }
  }
  return json({ ok: true, messages, sent, failed });
});
