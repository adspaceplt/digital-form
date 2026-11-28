/*
 * The agency profile, the edge functions' one read of it (restructure
 * release 6, 2026-11-28): every value that names the agency (its names,
 * registration, address, domains, files) comes from the database's
 * `agency_profile_read()`, read with the platform's service role key, once
 * an instance. Never typed in a function.
 *
 *   agencyProfile()  the whole profile ({} where the database did not
 *                    answer; asked again on the next call)
 *   agency(key)      one value, '' where the profile holds none
 */
let held: Promise<Record<string, string>> | null = null;

async function read(): Promise<Record<string, string>> {
  const url = Deno.env.get('SUPABASE_URL'), key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return {};
  try {
    const res = await fetch(url + '/rest/v1/rpc/agency_profile_read', {
      method: 'POST', headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' }, body: '{}'
    });
    const d = res.ok ? await res.json().catch(() => null) : null;
    return d && typeof d === 'object' && !Array.isArray(d) ? d as Record<string, string> : {};
  } catch (_e) { return {}; }
}

export function agencyProfile(): Promise<Record<string, string>> {
  if (!held) held = read().then((d) => { if (!Object.keys(d).length) held = null; return d; });
  return held;
}

export async function agency(key: string): Promise<string> {
  const v = (await agencyProfile())[key];
  return v == null ? '' : String(v);
}
