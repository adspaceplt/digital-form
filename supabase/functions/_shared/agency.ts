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

/*
 * How a profile's values read in an email or a message, made from the
 * values alone so an install's own profile reads the same way.
 *   addressLines(a)  the address, a line a part
 *   addressLocal(a)  on one line, less its country (the last line's last part)
 *   phoneLine(a)     the phone as the issuer's lines print it: (cc)NN NNN NNNN
 *   mailSite(a)      the site an email names and opens: the sending domain's
 *                    own domain (sc.example.com → example.com)
 *   portalUrl(a)     https:// and the portal's domain
 */
type Profile = Record<string, string>;
export const addressLines = (a: Profile): string[] =>
  String(a.address || '').split('\n').map((l) => l.trim()).filter(Boolean);
export function addressLocal(a: Profile): string {
  const ls = addressLines(a);
  if (!ls.length) return '';
  const last = ls[ls.length - 1], cut = last.lastIndexOf(',');
  return ls.slice(0, -1).concat(cut > 0 ? [last.slice(0, cut).trim()] : []).join(', ');
}
export function phoneLine(a: Profile): string {
  const d = String(a.phone || '').replace(/\D/g, '');
  const m = /^(\d{2})(1\d)(\d{3,4})(\d{4})$/.exec(d);
  return m ? '(' + m[1] + ')' + m[2] + ' ' + m[3] + ' ' + m[4] : (d ? '+' + d : '');
}
export function mailSite(a: Profile): string {
  const parts = String(a.sender_domain || '').split('.').filter(Boolean);
  return (parts.length > 2 ? parts.slice(1) : parts).join('.');
}
export const portalUrl = (a: Profile): string => a.portal_domain ? 'https://' + a.portal_domain : '';
