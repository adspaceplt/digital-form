/*
 * outstation-geo — the place and the road distance of a driver's trip
 * (OUTSTATION RECORD, 2026-11-23).
 *
 *   { stop: id }  the stop's address and zone (Johor, Singapore or Beyond
 *                 Johor) from OpenStreetMap Nominatim, asked once a stop,
 *                 one request a second across the portal
 *                 (`outstation_geo_turn`), credited on the page.
 *   { trip: id }  the road km of each leg from openrouteservice: the office
 *                 to the first stop, each stop to the next and, once the
 *                 trip is checked out, back to the office.
 *
 * Only the driver asks (`outstation_geo_may`, as the caller); the reading
 * is the stop's own, never the browser's. The figures are written by the
 * service role (`outstation_stop_place`, `outstation_route_set`). With no
 * `ORS_API_KEY` secret stored the route answers `{ off: true }` and the
 * page says the distance is not available. Never an IP geolocation.
 *
 * Deploy with Verify JWT off: the preflight carries no Authorization
 * header; the caller is checked here.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { cors, json } from '../_shared/cors.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const AGENT = 'ADspace-Digital-Portal/1.0 (+https://digital.adspace.me)';

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

/* Johor, Singapore, else Beyond Johor, from the address OpenStreetMap
   holds for the point. */
function zoneOf(addr: Record<string, string>): string | null {
  const cc = String(addr.country_code || '').toLowerCase();
  if (cc === 'sg') return 'singapore';
  if (!cc) return null;
  if (cc === 'my' && /johor/i.test(String(addr.state || ''))) return 'johor';
  return 'beyond';
}
function addressOf(d: Record<string, unknown>): string {
  const a = (d.address || {}) as Record<string, string>;
  const road = [a.house_number, a.road].filter(Boolean).join(' ');
  const parts = [road || a.building || a.amenity, a.suburb || a.neighbourhood || a.quarter, a.city || a.town || a.village || a.county, a.postcode, a.state]
    .filter((x, i, all) => x && all.indexOf(x) === i);
  return (parts.length ? parts.join(', ') : String(d.display_name || '')).slice(0, 300);
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);
  let body: { stop?: string; trip?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400, origin); }
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

  if (stop) {
    const { data: s } = await admin.from('outstation_stops').select('lat, lng').eq('id', stop).maybeSingle();
    if (!s) return json({ error: 'not_found' }, 404, origin);
    const { data: wait } = await admin.rpc('outstation_geo_turn');
    if (Number(wait) > 0) await new Promise((r) => setTimeout(r, Math.min(Number(wait), 8000)));
    const q = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&addressdetails=1&lat=${Number(s.lat)}&lon=${Number(s.lng)}`;
    let d: Record<string, unknown>;
    try {
      const r = await fetch(q, { headers: { 'User-Agent': AGENT, 'Referer': 'https://digital.adspace.me/', 'Accept-Language': 'en' } });
      if (!r.ok) throw new Error('nominatim ' + r.status);
      d = await r.json();
    } catch (e) {
      console.error('outstation-geo: reverse failed', String((e as Error)?.message || e));
      return json({ error: 'geo_failed' }, 502, origin);
    }
    if (d.error) return json({ error: 'geo_failed' }, 502, origin);
    const address = addressOf(d);
    const zone = zoneOf((d.address || {}) as Record<string, string>);
    const { data: put, error: putErr } = await admin.rpc('outstation_stop_place', { p_stop: stop, p_address: address, p_zone: zone });
    if (putErr || put?.error) return json({ error: 'not_saved' }, 500, origin);
    return json({ ok: true, address, zone }, 200, origin);
  }

  const key = (Deno.env.get('ORS_API_KEY') ?? '').trim();
  if (!key) return json({ off: true }, 200, origin);
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
  let segs: { distance: number }[] = [];
  try {
    const r = await fetch('https://api.openrouteservice.org/v2/directions/driving-car', {
      method: 'POST',
      headers: { 'Authorization': key, 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ coordinates: coords, units: 'km', instructions: false })
    });
    if (!r.ok) throw new Error('ors ' + r.status + ' ' + (await r.text()).slice(0, 200));
    const d = await r.json();
    segs = (d.routes && d.routes[0] && d.routes[0].segments) || [];
  } catch (e) {
    console.error('outstation-geo: route failed', String((e as Error)?.message || e));
    return json({ error: 'route_failed' }, 502, origin);
  }
  if (segs.length !== coords.length - 1) return json({ error: 'route_failed' }, 502, origin);
  const legs = segs.slice(0, stops.length).map((g) => Math.round(Number(g.distance) * 10) / 10);
  const back = closed ? Math.round(Number(segs[segs.length - 1].distance) * 10) / 10 : null;
  const { data: put, error: putErr } = await admin.rpc('outstation_route_set', { p_trip: tripId, p_legs: legs, p_back: back });
  if (putErr || put?.error) return json({ error: 'not_saved' }, 500, origin);
  return json({ ok: true, legs, back }, 200, origin);
});
