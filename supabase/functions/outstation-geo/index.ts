/*
 * outstation-geo — the place and the road distance of a driver's trip
 * (OUTSTATION RECORD, 2026-11-23).
 *
 *   { stop: id }  the stop's address and zone (Johor, Singapore or Beyond
 *                 Johor) from openrouteservice's geocoder (OpenStreetMap's
 *                 data), asked once a stop, one request a second across the
 *                 portal (`outstation_geo_turn`), credited on the page.
 *                 Nominatim refused the function's servers outright (403,
 *                 2026-11-24), so the one key serves both.
 *   { near: { lat, lng } }  the place the geocoder names for a reading the
 *                 driver holds, before a stop is saved (2026-11-24), so the
 *                 Check in and Next stop forms show it; nothing is written,
 *                 and the stop's own address is looked up again once saved.
 *                 Asked of a colleague who may record trips (My Work at
 *                 Work), on the same one request a second.
 *   { trip: id }  the road km of each leg from openrouteservice's matrix:
 *                 the office to the first stop, each stop to the next and,
 *                 once the trip is checked out, back to the office. (The
 *                 directions answer, asked without instructions, carried no
 *                 legs, and every trip read Not available; 2026-11-24.)
 *                 With the distance the matrix answers the drive's time:
 *                 a trip checked out at the office takes its last stop's
 *                 end from it (`outstation_back_drive`, 2026-11-25).
 *
 * Only the driver asks (`outstation_geo_may`, as the caller); the reading
 * is the stop's own, never the browser's. The figures are written by the
 * service role (`outstation_stop_place`, `outstation_route_set`). With no
 * `ORS_API_KEY` secret stored each answers `{ off: true }` and the page
 * says the place or the distance is not available. Never an IP
 * geolocation.
 *
 * Deploy with Verify JWT off: the preflight carries no Authorization
 * header; the caller is checked here.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json } from '../_shared/cors.ts';

/* openrouteservice's one address (HeiGIT moved it off
   api.openrouteservice.org on 2026-11-24, which answers 410 since): the
   matrix at /openrouteservice/v2, the geocoder at /pelias/v1, each with
   the key in the Authorization header, never in the address. */
const ORS_BASE = 'https://api.heigit.org';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/* A Business setting as app_setting(key, at) answers it: the newest row
   from on or before the day (app_settings_read lists them by key and day).
   app_setting itself is closed to a caller's session. */
function settingsAt(data: unknown, test: RegExp): Record<string, number> {
  const d = (data || {}) as Record<string, unknown>;
  const day = String(d.today || new Date(Date.now() + 8 * 36e5).toISOString().slice(0, 10));
  const out: Record<string, number> = {};
  for (const r of (Array.isArray(d.settings) ? d.settings : []) as { key: string; from: string; value: number }[]) {
    if (test.test(r.key) && String(r.from).slice(0, 10) <= day) out[r.key] = Number(r.value);
  }
  return out;
}

/* Johor, Singapore, else Beyond Johor, from the place the geocoder names. */
type Feature = { properties?: Record<string, string> };
function zoneOf(p: Record<string, string>): string | null {
  const cc = String(p.country_code || '').toLowerCase(), a3 = String(p.country_a || '').toUpperCase();
  if (cc === 'sg' || a3 === 'SGP') return 'singapore';
  if (!cc && !a3) return null;
  if ((cc === 'my' || a3 === 'MYS') && /johor/i.test(String(p.region || ''))) return 'johor';
  return 'beyond';
}
function addressOf(p: Record<string, string>): string {
  const road = [p.housenumber, p.street].filter(Boolean).join(' ');
  const parts = [p.name, road, p.neighbourhood, p.locality || p.localadmin || p.county, p.postalcode, p.region]
    .filter((x, i, all) => x && all.indexOf(x) === i);
  return (parts.length ? parts.join(', ') : String(p.label || '')).slice(0, 300);
}
/* The place for a point, or null; one request a second across the portal. */
async function placeOf(admin: ReturnType<typeof createClient>, key: string, lat: number, lng: number) {
  const { data: wait } = await admin.rpc('outstation_geo_turn');
  if (Number(wait) > 0) await new Promise((r) => setTimeout(r, Math.min(Number(wait), 8000)));
  try {
    const r = await fetch(`${ORS_BASE}/pelias/v1/reverse?point.lat=${lat}&point.lon=${lng}&size=1`,
      { headers: { 'Authorization': key, 'Accept': 'application/json' } });
    if (!r.ok) throw new Error('geocode ' + r.status + ' ' + (await r.text()).slice(0, 200));
    const d = await r.json();
    const f = ((d.features || []) as Feature[])[0];
    if (!f || !f.properties) { console.error('outstation-geo: no place', lat, lng); return null; }
    return { address: addressOf(f.properties), zone: zoneOf(f.properties) };
  } catch (e) {
    console.error('outstation-geo: reverse failed', String((e as Error)?.message || e));
    return null;
  }
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);
  let body: { stop?: string; trip?: string; near?: { lat?: unknown; lng?: unknown } };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400, origin); }
  if (body.near) {
    const lat = Number(body.near.lat), lng = Number(body.near.lng);
    if (!isFinite(lat) || !isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180 || body.stop || body.trip) return json({ error: 'bad_request' }, 400, origin);
    const auth0 = req.headers.get('Authorization') ?? '';
    if (!auth0.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
    const url0 = Deno.env.get('SUPABASE_URL')!;
    const supa0 = createClient(url0, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth0 } } });
    const { data: may0, error: mayErr0 } = await supa0.rpc('allowed', { p_section: 'ops', p_level: 'work' });
    if (mayErr0 || may0 !== true) return json({ error: 'not_allowed' }, 403, origin);
    const key0 = (Deno.env.get('ORS_API_KEY') ?? '').trim();
    if (!key0) return json({ off: true }, 200, origin);
    const admin0 = createClient(url0, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const pl0 = await placeOf(admin0, key0, lat, lng);
    if (!pl0) return json({ error: 'geo_failed' }, 502, origin);
    return json({ ok: true, address: pl0.address, zone: pl0.zone }, 200, origin);
  }
  const stop = body.stop ? String(body.stop) : null;
  const trip = body.trip ? String(body.trip) : null;
  if ((stop && !UUID.test(stop)) || (trip && !UUID.test(trip)) || (!stop === !trip)) return json({ error: 'bad_request' }, 400, origin);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'not_signed_in' }, 401, origin);
  const url = Deno.env.get('SUPABASE_URL')!;
  const supa = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } } });
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: tripId, error: mayErr } = await supa.rpc('outstation_geo_may', { p_stop: stop, p_trip: trip });
  if (mayErr || !tripId) return json({ error: 'not_allowed' }, 403, origin);

  const key = (Deno.env.get('ORS_API_KEY') ?? '').trim();
  if (!key) return json({ off: true }, 200, origin);
  if (stop) {
    const { data: s } = await admin.from('outstation_stops').select('lat, lng').eq('id', stop).maybeSingle();
    if (!s) return json({ error: 'not_found' }, 404, origin);
    const pl = await placeOf(admin, key, Number(s.lat), Number(s.lng));
    if (!pl) return json({ error: 'geo_failed' }, 502, origin);
    const { data: put, error: putErr } = await admin.rpc('outstation_stop_place', { p_stop: stop, p_address: pl.address, p_zone: pl.zone });
    if (putErr || put?.error) return json({ error: 'not_saved' }, 500, origin);
    return json({ ok: true, address: pl.address, zone: pl.zone }, 200, origin);
  }

  const { data: t } = await admin.from('outstation_trips').select('state').eq('id', tripId).maybeSingle();
  const { data: stops } = await admin.from('outstation_stops').select('seq, lat, lng').eq('trip_id', tripId).order('seq');
  if (!t || !stops || !stops.length) return json({ error: 'not_found' }, 404, origin);
  const { data: setRead } = await supa.rpc('app_settings_read');
  const set = settingsAt(setRead, /^outstation_office_/);
  const office = [Number(set.outstation_office_lng), Number(set.outstation_office_lat)];
  if (!isFinite(office[0]) || !isFinite(office[1])) return json({ error: 'no_office' }, 500, origin);
  const coords = [office, ...stops.map((s: { lat: number; lng: number }) => [Number(s.lng), Number(s.lat)])];
  const closed = t.state === 'closed';
  if (closed) coords.push(office);
  /* Each leg is the road distance from one point to the next: the
     matrix's row i, column i (sources 0..n-2, destinations 1..n-1). */
  const n = coords.length;
  let km: (number | null)[] = [];
  let mins: (number | null)[] = [];
  try {
    const r = await fetch(`${ORS_BASE}/openrouteservice/v2/matrix/driving-car`, {
      method: 'POST',
      headers: { 'Authorization': key, 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ locations: coords, metrics: ['distance', 'duration'], units: 'km',
        sources: Array.from({ length: n - 1 }, (_, i) => i), destinations: Array.from({ length: n - 1 }, (_, i) => i + 1) })
    });
    if (!r.ok) throw new Error('ors ' + r.status + ' ' + (await r.text()).slice(0, 200));
    const d = await r.json();
    const m = (d.distances || []) as (number | null)[][];
    km = Array.from({ length: n - 1 }, (_, i) => (m[i] && m[i][i] != null ? Math.round(Number(m[i][i]) * 10) / 10 : null));
    const du = (d.durations || []) as (number | null)[][];
    mins = Array.from({ length: n - 1 }, (_, i) => (du[i] && du[i][i] != null ? Math.round(Number(du[i][i]) / 6) / 10 : null));
  } catch (e) {
    console.error('outstation-geo: route failed', String((e as Error)?.message || e));
    return json({ error: 'route_failed' }, 502, origin);
  }
  if (km.length !== n - 1 || km.some((x) => x == null)) {
    console.error('outstation-geo: route incomplete', JSON.stringify(km));
    return json({ error: 'route_failed' }, 502, origin);
  }
  const legs = km.slice(0, stops.length) as number[];
  const back = closed ? km[km.length - 1] : null;
  const { data: put, error: putErr } = await admin.rpc('outstation_route_set', { p_trip: tripId, p_legs: legs, p_back: back });
  if (putErr || put?.error) return json({ error: 'not_saved' }, 500, origin);
  /* The drive back's minutes: the database keeps a last stop left at the
     office that much before the arrival (never before its last activity);
     any other trip it leaves as it stands. */
  const backMins = closed ? mins[mins.length - 1] : null;
  if (closed && backMins != null) {
    const { error: bdErr } = await admin.rpc('outstation_back_drive', { p_trip: tripId, p_mins: backMins });
    if (bdErr) console.error('outstation-geo: back drive not saved', bdErr.message);
  }
  return json({ ok: true, legs, back, back_mins: backMins }, 200, origin);
});
