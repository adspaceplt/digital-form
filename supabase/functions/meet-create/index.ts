/*
 * meet-create — puts a month's content meeting on the shared ADspace Google
 * calendar (adspacestudios@gmail.com) with a Google Meet link, moves it when
 * the meeting moves, and takes it off when the month has no meeting.
 *
 * The calendar is the shared account's, reached with a refresh token held in
 * this function's secrets, so nobody on the team signs in to Google and the
 * token never reaches a browser. A slot that already holds an event on that
 * calendar is refused and named, so two meetings cannot be booked into the
 * same half hour.
 *
 * Secrets: GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN
 *          (docs/GOOGLE-MEET-SETUP.md), plus the platform's SUPABASE_URL and
 *          SUPABASE_ANON_KEY.
 *
 * A refusal the person can act on (not set up, the slot taken, not allowed)
 * answers 200 with { error }, so the page reads the reason from the body; a
 * non-2xx is kept for a request that was malformed.
 *
 * Deploy:  supabase functions deploy meet-create
 * Turn OFF "Verify JWT" for this function, as for sign-upload: the browser's
 * preflight carries no Authorization header, and this function asks the
 * database about the caller itself.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const ALLOWED_ORIGINS = ['https://digital.adspace.me', 'http://localhost:8899'];
const TZ = 'Asia/Kuala_Lumpur';
const CAL = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';

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

/* A token for the shared account. The page is told which secret is missing
   by name, and what Google said when it refused, so a setup fault is fixed
   from the message rather than guessed at. Values are trimmed: a secret
   pasted with a trailing space or line break is otherwise refused by Google
   as a different secret. */
const SECRETS = ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_REFRESH_TOKEN'];
function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
async function googleToken(): Promise<{ token?: string; error?: string; missing?: string[]; reason?: string }> {
  const missing = SECRETS.filter((k) => !secret(k));
  if (missing.length) return { error: 'meet-not-set-up', missing };
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: secret('GOOGLE_CLIENT_ID'), client_secret: secret('GOOGLE_CLIENT_SECRET'),
      refresh_token: secret('GOOGLE_REFRESH_TOKEN'), grant_type: 'refresh_token' })
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok || !d.access_token) return { error: 'google-token', reason: String(d.error || r.status) };
  return { token: d.access_token };
}
/* What the Calendar API said, in one word the page can name. */
async function why(r: Response): Promise<string> {
  const d = await r.json().catch(() => ({}));
  const e = d && d.error;
  const first = e && Array.isArray(e.errors) && e.errors[0];
  return String((first && first.reason) || (e && e.status) || r.status);
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);

  let body: { engagementId?: string; action?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400, origin); }
  const eid = String(body.engagementId ?? '');
  const action = String(body.action ?? 'create');
  if (!/^[0-9a-f-]{36}$/.test(eid)) return json({ error: 'bad_engagement' }, 400, origin);
  if (!['create', 'update', 'delete'].includes(action)) return json({ error: 'bad_action' }, 400, origin);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
  /* Every question about the caller is asked as the caller: the database
     decides whether this person may work this month, as it does for every
     other write on it. */
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });
  const prep = await db.rpc('ops_engagement_meet_prepare', { p_engagement: eid });
  if (prep.error) return json({ error: 'denied', detail: prep.error.message }, 200, origin);
  const m = prep.data as Record<string, string | number | null>;
  if (!m || m.error) return json({ error: (m && m.error) || 'denied' }, 200, origin);

  const tok = await googleToken();
  if (!tok.token) return json({ error: tok.error, missing: tok.missing, reason: tok.reason }, 200, origin);
  const g = { Authorization: `Bearer ${tok.token}`, 'Content-Type': 'application/json' };

  const eventId = m.meeting_event_id ? String(m.meeting_event_id) : '';
  if (action === 'delete') {
    if (eventId) {
      const r = await fetch(`${CAL}/${encodeURIComponent(eventId)}`, { method: 'DELETE', headers: g });
      if (!r.ok && r.status !== 404 && r.status !== 410) return json({ error: 'google-refused', reason: await why(r) }, 200, origin);
    }
    await db.rpc('ops_engagement_set_meet', { p_engagement: eid, p_link: null, p_event: null });
    return json({ deleted: true }, 200, origin);
  }

  if (!m.meeting_at) return json({ error: 'no-date' }, 200, origin);
  const start = new Date(String(m.meeting_at));
  const end = new Date(start.getTime() + Number(m.meeting_minutes || 30) * 60000);

  /* The shared calendar says whether the slot is free. Anything on it that
     overlaps, other than this month's own event, refuses the booking and is
     named, so the person can pick another time. */
  const list = await fetch(`${CAL}?` + new URLSearchParams({
    timeMin: start.toISOString(), timeMax: end.toISOString(), singleEvents: 'true', maxResults: '10'
  }), { headers: g });
  if (!list.ok) return json({ error: 'google-refused', reason: await why(list) }, 200, origin);
  const clash = ((await list.json()).items || []).find((x: Record<string, unknown>) =>
    x.id !== eventId && x.status !== 'cancelled' && x.transparency !== 'transparent');
  if (clash) {
    return json({ error: 'slot-taken', summary: String(clash.summary || 'Busy'),
      start: (clash.start as Record<string, string>)?.dateTime || null,
      end: (clash.end as Record<string, string>)?.dateTime || null }, 200, origin);
  }

  const summary = `${m.client_name} · ${m.month_word} Content Discussion`;
  const event: Record<string, unknown> = {
    summary,
    description: `${m.month_word} Content Discussion\nBooked from the ADspace Digital Portal.`,
    start: { dateTime: start.toISOString(), timeZone: TZ },
    end: { dateTime: end.toISOString(), timeZone: TZ }
  };
  let r: Response;
  if (eventId) {
    r = await fetch(`${CAL}/${encodeURIComponent(eventId)}?conferenceDataVersion=1`,
      { method: 'PATCH', headers: g, body: JSON.stringify(event) });
  } else {
    event.conferenceData = { createRequest: { requestId: `${eid}-${Date.now()}`,
      conferenceSolutionKey: { type: 'hangoutsMeet' } } };
    r = await fetch(`${CAL}?conferenceDataVersion=1`, { method: 'POST', headers: g, body: JSON.stringify(event) });
  }
  if (!r.ok) return json({ error: 'google-refused', reason: await why(r) }, 200, origin);
  const made = await r.json();
  const link = made.hangoutLink || m.meeting_link || null;
  const saved = await db.rpc('ops_engagement_set_meet', { p_engagement: eid, p_link: link, p_event: made.id });
  if (saved.error || (saved.data && saved.data.error)) {
    return json({ error: 'not-saved', link, event: made.id }, 200, origin);
  }
  return json({ link, event: made.id, engagement: saved.data }, 200, origin);
});
