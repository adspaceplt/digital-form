-- ===========================================================================
-- AGENCY PROFILE (2026-11-28)
-- ===========================================================================
-- WHY: the restructure's release 6 (docs/MAP.md §G). The values that name
-- the agency (its names, registration, address, domains, files) had no
-- store on the server: functions, emails and workers typed them, and the
-- pages read them from js/config.js alone. One install holds one agency,
-- and this is its one profile.
-- WHAT IT CHANGES
--   * `agency_profile` (key, value; RLS on, no policy, no grant): every
--     value that names the agency, seeded with what the pages print today
--     (js/config.js `ADspaceAgency`, which `tests/agencysql.js` holds equal
--     to this seed). The general mailbox is not copied here: it stays
--     `mail_boxes` `general`, answered as `email`.
--   * `agency(p_key)`: one value, the read every database function uses
--     (the service role's and other functions' alone).
--   * `agency_profile_read()`: the whole profile, for a colleague and the
--     edge functions (the service role; `_shared/agency.ts`), `denied` to
--     anyone else.
--   * `mail_senders`: the sending domain is the profile's `sender_domain`,
--     checked by a trigger on every write, in place of the domains its
--     address check typed.
-- ORDER: this file first, then `push-send` (it reads the profile through
-- `_shared/agency.ts`), then the pages (no page calls these functions). An
-- open tab meets the same answers throughout; `push-send` deployed before
-- this file would send a notice titled with nothing until it is applied.
-- ROLLBACK: drop trigger mail_senders_domain on public.mail_senders; drop
-- function public.mail_senders_domain(); put `mail_senders_address_check`
-- back as EVERY EMAIL FROM PORTAL@ states it; drop function
-- public.agency_profile_read(); drop function public.agency(text); drop
-- table public.agency_profile. Safe to run twice.

-- AGENCY PROFILE ------------------------------------------------------------

create table if not exists public.agency_profile (
  key        text primary key check (key ~ '^[a-z][a-z_]*[a-z]$' and key <> 'email'),
  value      text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.agency_profile enable row level security;
revoke all on public.agency_profile from public, anon, authenticated;

-- Each key the profile holds, seeded once: a key already set keeps its value.
insert into public.agency_profile (key, value) values
  ('trading_name', 'ADspace'),
  ('legal_name', 'ADSPACE PLT'),
  ('reg_no', '202304002162'),
  ('tax_no', 'J31-2401-32100002'),
  ('address', E'61-02 Jalan Mutiara Emas 2A\nTaman Mount Austin\n81100 Johor Bahru\nJohor, Malaysia'),
  ('phone', '60187625233'),
  ('website', 'adspacestudios.com'),
  ('map_url', 'https://hi.adspace.me/map'),
  ('portal_domain', 'digital.adspace.me'),
  ('link_domain', 'hi.adspace.me'),
  ('sender_domain', 'sc.adspace.me'),
  ('cdn_base', 'https://mycdn.adspace.me'),
  ('wordmark_url', 'https://mycdn.adspace.me/adspace-brandname.png'),
  ('monogram_url', '/css/adspace-mark.png'),
  ('favicon_url', '/favicon.ico'),
  ('touch_icon_url', '/img/apple-touch-icon.png'),
  ('icon_url', '/img/icon-512.png'),
  ('verify_url', 'digital.adspace.me/verify'),
  ('service_terms_url', 'hi.adspace.me/svc-terms'),
  ('ink_token', '--ink'),
  ('accent_token', '--action'),
  ('ground_token', '--page')
on conflict (key) do nothing;

create or replace function public.agency(p_key text)
returns text
language sql stable security definer set search_path = public as $$
  select case when p_key = 'email'
              then (select b.address from public.mail_boxes b where b.key = 'general')
              else (select a.value from public.agency_profile a where a.key = p_key) end;
$$;
revoke all on function public.agency(text) from public, anon, authenticated;
grant execute on function public.agency(text) to service_role;

create or replace function public.agency_profile_read()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_team() or coalesce(auth.jwt() ->> 'role', '') = 'service_role') then
    return jsonb_build_object('error', 'denied');
  end if;
  return coalesce((select jsonb_object_agg(a.key, a.value) from public.agency_profile a), '{}'::jsonb)
      || jsonb_build_object('email', (select b.address from public.mail_boxes b where b.key = 'general'));
end $$;
revoke all on function public.agency_profile_read() from public, anon;
grant execute on function public.agency_profile_read() to authenticated, service_role;

-- The address a section sends from is on the profile's sending domain.
alter table public.mail_senders drop constraint if exists mail_senders_address_check;
alter table public.mail_senders add constraint mail_senders_address_check
  check (address ~ '^[a-z][a-z0-9.]*@[a-z0-9-]+(\.[a-z0-9-]+)+$' and address !~ '^no-?reply');

create or replace function public.mail_senders_domain()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if split_part(new.address, '@', 2) is distinct from public.agency('sender_domain') then
    raise exception 'mail_senders: % is not on the sending domain %', new.address, public.agency('sender_domain')
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function public.mail_senders_domain() from public, anon, authenticated;
drop trigger if exists mail_senders_domain on public.mail_senders;
create trigger mail_senders_domain before insert or update on public.mail_senders
  for each row execute function public.mail_senders_domain();

-- END OF AGENCY PROFILE -----------------------------------------------------

select public.functions_tidy();
