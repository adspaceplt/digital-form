-- ===========================================================================
-- SERVICE CONFIRM GUARD — a service line becomes Confirmed only through a
-- verified signed letter or the admin's reasoned override (audit S1,
-- 2026-10-10). 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored
-- byte for byte in supabase/schema.sql under the same banner;
-- tests/smsql.js compares the two.
--
-- WHAT CHANGED
--   The service sheet offered Confirmed and wrote it straight to the table,
--   while the line's own control refused it. `client_services_confirm_guard`
--   refuses a row inserted as Confirmed, or moved into Confirmed, by a page
--   (the `authenticated` and `anon` roles): `verify_letter` and
--   `override_service_state` run as their owner and pass. A line already
--   Confirmed is untouched, and its other fields stay editable as before.
--
-- ROLLBACK
--   Pages first is not needed (the page no longer offers Confirmed); remove
--   the trigger and its function.
-- ===========================================================================

create or replace function public.client_services_confirm_guard()
returns trigger
language plpgsql
set search_path = public as $$
begin
  if new.state = 'confirmed'
     and (tg_op = 'INSERT' or old.state is distinct from 'confirmed')
     and current_user in ('authenticated', 'anon') then
    raise exception 'confirm-needs-letter' using errcode = 'P0001',
      hint = 'A service is confirmed when its signed letter is verified.';
  end if;
  return new;
end $$;
revoke all on function public.client_services_confirm_guard() from public, anon, authenticated;

create or replace trigger client_services_confirm_guard
  before insert or update of state on public.client_services
  for each row execute function public.client_services_confirm_guard();

-- END OF SERVICE CONFIRM GUARD -------------------------------------------------

select public.functions_tidy();
