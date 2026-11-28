/*
 * meet-create — puts a month's content meeting on the agency's shared Google
 * calendar (the admin login's) with a Google Meet link, moves it when
 * the meeting moves, and takes it off when the month has no meeting.
 *
 * The calendar is the shared account's, reached with a refresh token held in
 * this function's secrets, so nobody on the team signs in to Google and the
 * token never reaches a browser. A slot that already holds another online
 * meeting on that calendar (a Meet link, or a Meet, Zoom or Teams address) is
 * refused by its time, so two calls cannot be booked into the same half hour;
 * the calendar's other events do not count. A record's event has one id,
 * made from the record's own (`eventIdOf`), so a second press finds the
 * event the first made (Google answers 409) and never books another.
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
import { cors, json } from '../_shared/cors.ts';
import { agencyProfile } from '../_shared/agency.ts';

const TZ = 'Asia/Kuala_Lumpur';
const CAL = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';

/* A token for the shared account. The page is told which secret is missing
   by name, and what Google said when it refused, so a setup fault is fixed
   from the message rather than guessed at. Values are trimmed: a secret
   pasted with a trailing space or line break is otherwise refused by Google
   as a different secret. */
const SECRETS = ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_REFRESH_TOKEN'];
function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
/* Every call to Google is held to 15 seconds (the review of 2026-11-25): a
   call cut off answers as Google refusing it, its reason `timeout`, so the
   page names it and the function never hangs. */
async function gfetch(url: string, init: RequestInit = {}): Promise<Response> {
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(15000) });
  } catch (e) {
    console.error('meet-create: Google did not answer', String(e));
    return new Response(JSON.stringify({ error: 'timeout' }), { status: 504, headers: { 'Content-Type': 'application/json' } });
  }
}
async function googleToken(): Promise<{ token?: string; error?: string; missing?: string[]; reason?: string }> {
  const missing = SECRETS.filter((k) => !secret(k));
  if (missing.length) return { error: 'meet-not-set-up', missing };
  const r = await gfetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: secret('GOOGLE_CLIENT_ID'), client_secret: secret('GOOGLE_CLIENT_SECRET'),
      refresh_token: secret('GOOGLE_REFRESH_TOKEN'), grant_type: 'refresh_token' })
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok || !d.access_token) return { error: 'google-token', reason: String(d.error || r.status) };
  return { token: d.access_token };
}
/* The Meet link on an event: the top-level one, else the video entry point. */
function meetLinkOf(ev: Record<string, unknown>): string | null {
  if (ev && typeof ev.hangoutLink === 'string' && ev.hangoutLink) return ev.hangoutLink;
  const cd = ev && ev.conferenceData as { entryPoints?: { entryPointType?: string; uri?: string }[] } | undefined;
  const v = cd && cd.entryPoints && cd.entryPoints.find((p) => p.entryPointType === 'video' && p.uri);
  return v && v.uri ? v.uri : null;
}
/* The one event a record may hold (the third audit, item 16): its id made
   from the record's, in Google's own letters (0-9 and a-v; a UUID's hex is
   inside them), so two presses at once, or a press after a save was lost,
   ask Google for the same event and the second is answered 409, never a
   second booking whose save orphans the first. */
type Kind = 'month' | 'touch' | 'hire';
function eventIdOf(kind: Kind, id: string): string {
  return (kind === 'touch' ? 'adtouch' : kind === 'hire' ? 'adhire' : 'admonth') + id.replace(/-/g, '').toLowerCase();
}
const MEETING = /https?:\/\/([a-z0-9-]+\.)*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com)\//i;
const online = (x: Record<string, unknown>) => Boolean(meetLinkOf(x)) ||
  MEETING.test(String(x.location || '')) || MEETING.test(String(x.description || ''));
/* What the Calendar API said, in one word the page can name. */
async function why(r: Response): Promise<string> {
  const d = await r.json().catch(() => ({}));
  const e = d && d.error;
  const first = e && Array.isArray(e.errors) && e.errors[0];
  return String((typeof e === 'string' && e) || (first && first.reason) || (e && e.status) || r.status);
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);

  let body: { engagementId?: string; touchId?: string; interviewId?: string; action?: string; from?: string; to?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400, origin); }
  /* A month's content meeting (engagementId), or a meeting a colleague
     logged in a client's Calls and visits outside any month (touchId,
     2026-10-05), or a candidate's interview (interviewId, 2026-11-17). Each
     has its own pair of database functions; the booking is the same. Busy
     answers the online meetings already on the calendar over a span, their
     times alone, for a colleague keying a candidate's interview times. */
  const action = String(body.action ?? 'create');
  const kind: Kind = body.interviewId != null ? 'hire' : body.touchId != null ? 'touch' : 'month';
  const touch = kind === 'touch';
  const eid = String((kind === 'hire' ? body.interviewId : touch ? body.touchId : body.engagementId) ?? '');
  if (action !== 'busy' && !/^[0-9a-f-]{36}$/.test(eid)) {
    return json({ error: kind === 'hire' ? 'bad_interview' : touch ? 'bad_touch' : 'bad_engagement' }, 400, origin);
  }
  const PREP = kind === 'hire' ? 'hiring_interview_meet_prepare' : touch ? 'client_touch_meet_prepare' : 'ops_engagement_meet_prepare';
  const SET = kind === 'hire' ? 'hiring_interview_set_meet' : touch ? 'client_touch_set_meet' : 'ops_engagement_set_meet';
  const KEY = kind === 'hire' ? 'p_interview' : touch ? 'p_touch' : 'p_engagement';
  if (!['create', 'update', 'delete', 'busy'].includes(action)) return json({ error: 'bad_action' }, 400, origin);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);

  if (action === 'busy') {
    const from = new Date(String(body.from || '')), to = new Date(String(body.to || ''));
    if (isNaN(from.getTime()) || isNaN(to.getTime()) || to <= from || to.getTime() - from.getTime() > 15 * 86400000) {
      return json({ error: 'bad_span' }, 400, origin);
    }
    const asker = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: auth } } });
    const may = await asker.rpc('hiring_busy_may');
    if (may.error || !may.data || (may.data as Record<string, unknown>).error) return json({ error: 'denied' }, 200, origin);
    const t = await googleToken();
    if (!t.token) return json({ error: t.error, missing: t.missing, reason: t.reason }, 200, origin);
    const got = await gfetch(`${CAL}?` + new URLSearchParams({
      timeMin: from.toISOString(), timeMax: to.toISOString(), singleEvents: 'true', orderBy: 'startTime', maxResults: '250'
    }), { headers: { Authorization: `Bearer ${t.token}` } });
    if (!got.ok) return json({ error: 'google-refused', reason: await why(got) }, 200, origin);
    /* The times alone: a title may name another client or candidate. */
    const busy = ((await got.json()).items || [])
      .filter((x: Record<string, unknown>) => x.status !== 'cancelled' && online(x))
      .map((x: Record<string, any>) => ({ start: x.start?.dateTime || null, end: x.end?.dateTime || null }))
      .filter((x: { start: string | null }) => x.start);
    return json({ busy }, 200, origin);
  }
  /* Every question about the caller is asked as the caller: the database
     decides whether this person may work this month, as it does for every
     other write on it. */
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } });
  const prep = await db.rpc(PREP, { [KEY]: eid });
  if (prep.error) return json({ error: 'denied', detail: prep.error.message }, 200, origin);
  const m = prep.data as Record<string, string | number | null>;
  if (!m || m.error) return json({ error: (m && m.error) || 'denied' }, 200, origin);

  const tok = await googleToken();
  if (!tok.token) return json({ error: tok.error, missing: tok.missing, reason: tok.reason }, 200, origin);
  const g = { Authorization: `Bearer ${tok.token}`, 'Content-Type': 'application/json' };

  /* Only the record's own event is ever moved or deleted (security audit
     2026-11-07): the stored id is the caller's to write, so one naming any
     other event (another client's month, the team's own) is never sent to
     Google. A delete then clears the record alone; a booking makes the
     record's own event. */
  const stored = m.meeting_event_id ? String(m.meeting_event_id) : '';
  const eventId = stored === eventIdOf(kind, eid) ? stored : '';
  if (action === 'delete') {
    if (eventId) {
      const r = await gfetch(`${CAL}/${encodeURIComponent(eventId)}`, { method: 'DELETE', headers: g });
      if (!r.ok && r.status !== 404 && r.status !== 410) return json({ error: 'google-refused', reason: await why(r) }, 200, origin);
    }
    /* The event is gone; a refused save leaves the link pointing at it, so
       it is said, never answered as deleted (2026-10-22, BE-8). Create
       Google Meet books a new one either way. */
    const cleared = await db.rpc(SET, { [KEY]: eid, p_link: null, p_event: null });
    if (cleared.error || (cleared.data && cleared.data.error)) return json({ error: 'not-saved', deleted: false }, 200, origin);
    return json({ deleted: true }, 200, origin);
  }

  if (!m.meeting_at) return json({ error: 'no-date' }, 200, origin);
  const start = new Date(String(m.meeting_at));
  const end = new Date(start.getTime() + Number(m.meeting_minutes || 30) * 60000);

  /* The shared calendar holds the team's other plans too, so only another
     online meeting in the same slot refuses the booking (the user,
     2026-10-01): an event carrying a Meet link, or a Meet, Zoom or Teams
     address. Its time is given, so the person can pick another; a shoot or a
     reminder in the slot is left alone. */
  const list = await gfetch(`${CAL}?` + new URLSearchParams({
    timeMin: start.toISOString(), timeMax: end.toISOString(), singleEvents: 'true', maxResults: '50'
  }), { headers: g });
  if (!list.ok) return json({ error: 'google-refused', reason: await why(list) }, 200, origin);
  const clash = ((await list.json()).items || []).find((x: Record<string, unknown>) =>
    x.id !== eventId && x.id !== eventIdOf(kind, eid) && x.status !== 'cancelled' && online(x));
  if (clash) {
    /* The clash's time alone: its title may be another client's meeting,
       which the colleague asking may not see (audit 2026-10-19, item 3). */
    return json({ error: 'slot-taken',
      start: (clash.start as Record<string, string>)?.dateTime || null,
      end: (clash.end as Record<string, string>)?.dateTime || null }, 200, origin);
  }

  /* An interview names its position alone: the calendar is shared, and a
     candidate's name stays with the people on the candidate. */
  const summary = kind === 'hire' ? `Interview · ${m.position}` : touch ? `${m.client_name} · Meeting` : `${m.client_name} · ${m.month_word} Content Discussion`;
  /* The agency's trading name, from its profile (`_shared/agency.ts`). */
  const agencyName = String((await agencyProfile()).trading_name || '');
  const event: Record<string, unknown> = {
    summary,
    description: (kind === 'hire' ? 'Interview' : touch ? 'Meeting' : `${m.month_word} Content Discussion`) + (agencyName ? '\nBooked from the ' + agencyName + ' Digital Portal.' : ''),
    start: { dateTime: start.toISOString(), timeZone: TZ },
    end: { dateTime: end.toISOString(), timeZone: TZ }
  };
  /* An event the portal made earlier without its link (Google had not
     finished making the Meet when it answered) is asked for one again. */
  const wantMeet = !eventId || !m.meeting_link;
  if (wantMeet) {
    event.conferenceData = { createRequest: { requestId: `${eid}-${Date.now()}`,
      conferenceSolutionKey: { type: 'hangoutsMeet' } } };
  }
  let r: Response;
  let made: Record<string, any> | null = null;
  if (eventId) {
    r = await gfetch(`${CAL}/${encodeURIComponent(eventId)}?conferenceDataVersion=1`,
      { method: 'PATCH', headers: g, body: JSON.stringify(event) });
  } else {
    const fixed = eventIdOf(kind, eid);
    r = await gfetch(`${CAL}?conferenceDataVersion=1`, { method: 'POST', headers: g, body: JSON.stringify({ id: fixed, ...event }) });
    if (r.status === 409) {
      /* Already booked: the event another press made is this record's, and
         is the answer. One taken off the calendar earlier (Delete, then
         Create Google Meet) keeps its id at Google, so it is put back with
         this booking's time and a Meet asked for again. */
      const had = await gfetch(`${CAL}/${encodeURIComponent(fixed)}?conferenceDataVersion=1`, { headers: g });
      if (!had.ok) return json({ error: 'google-refused', reason: await why(had) }, 200, origin);
      made = await had.json();
      if (made && made.status === 'cancelled') {
        made = null;
        event.status = 'confirmed';
        event.conferenceData = { createRequest: { requestId: `${eid}-${Date.now()}`,
          conferenceSolutionKey: { type: 'hangoutsMeet' } } };
        r = await gfetch(`${CAL}/${encodeURIComponent(fixed)}?conferenceDataVersion=1`,
          { method: 'PATCH', headers: g, body: JSON.stringify(event) });
      }
    }
  }
  if (!made) {
    if (!r.ok) return json({ error: 'google-refused', reason: await why(r) }, 200, origin);
    made = await r.json();
  }
  /* Google makes the Meet a moment after the event, so the first answer can
     carry the event and not yet its link. The event is read again, briefly,
     until the link is there. */
  let link = meetLinkOf(made!);
  for (let i = 0; !link && i < 8; i++) {
    await new Promise((ok) => setTimeout(ok, 750));
    const again = await gfetch(`${CAL}/${encodeURIComponent(made!.id)}?conferenceDataVersion=1`, { headers: g });
    if (again.ok) link = meetLinkOf(await again.json());
  }
  link = link || (eventId && m.meeting_link ? String(m.meeting_link) : null);
  if (!link) {
    /* The event is recorded without a link, so the next press asks Google
       for the Meet on this event rather than booking a second one. */
    await db.rpc(SET, { [KEY]: eid, p_link: null, p_event: made!.id });
    return json({ error: 'meet-pending', event: made!.id }, 200, origin);
  }
  const saved = await db.rpc(SET, { [KEY]: eid, p_link: link, p_event: made!.id });
  if (saved.error || (saved.data && saved.data.error)) {
    return json({ error: 'not-saved', link, event: made!.id }, 200, origin);
  }
  return json({ link, event: made!.id, [kind === 'hire' ? 'interview' : touch ? 'touch' : 'engagement']: saved.data }, 200, origin);
});
