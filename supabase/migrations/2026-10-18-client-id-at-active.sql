-- ===========================================================================
-- A CLIENT ID AT ACTIVE — a client becomes Active only holding its Client ID,
-- the next number offered (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18): a lead, contacted or proposal may come to no
-- deal, so a Client ID is given when a client turns Active; the move asks
-- for it, the next number offered, as a new supplier's Supplier ID is.
--
-- WHAT IT CHANGES
--   * `client_code_next()`: the next free AC number, one past the highest
--     `AC` + digits held by any client, written as wide as that one (AC188
--     → AC189), at Clients Work. Read across every client, whatever the
--     caller's client scope, and the number alone leaves it.
--   * Trigger `clients_active_code`: a client written into Active, or kept
--     Active, with no Client ID is refused (`active-needs-code`).
--
-- ORDER: this file, then the pages. Safe to run twice.
-- Rollback: drop the trigger and the function; the pages from before.
-- ===========================================================================

create or replace function public.client_code_next()
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_n bigint := 0;
  v_w int := 3;
  r record;
begin
  if not public.allowed('clients', 'work') then
    raise exception 'denied';
  end if;
  for r in
    select substring(c.client_code from '^AC(\d+)$') as d
      from public.clients c
     where c.client_code ~ '^AC\d+$'
  loop
    if r.d::bigint >= v_n then
      v_n := r.d::bigint;
      v_w := greatest(3, length(r.d));
    end if;
  end loop;
  return 'AC' || lpad((v_n + 1)::text, v_w, '0');
end $$;
revoke all on function public.client_code_next() from public, anon;
grant execute on function public.client_code_next() to authenticated;

create or replace function public.clients_active_code()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.stage = 'active' and coalesce(btrim(new.client_code), '') = '' then
    raise exception 'active-needs-code';
  end if;
  return new;
end $$;
revoke all on function public.clients_active_code() from public, anon, authenticated;
create or replace trigger clients_active_code before insert or update of stage, client_code on public.clients
  for each row execute function public.clients_active_code();

-- END OF A CLIENT ID AT ACTIVE ----------------------------------------------
select public.functions_tidy();
