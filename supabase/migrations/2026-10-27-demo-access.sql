-- ===========================================================================
-- DEMO ACCESS — a PIN typed in the sign-in's email box opens the console on
-- sample data (2026-10-27)
-- ===========================================================================
-- WHY (the user, 2026-10-27): "enter this pin will allow me access however
-- it will only show all fake populated data unable to add anything … so i
-- can sell ppl this portal"; "Just enter in the email input"; "the demo act
-- as one setting to control the pin (input or change) and active /
-- inactive".
--
-- WHAT IT CHANGES
--   One flag (`app_flags` key `demo`, on or off) and one secret
--   (`app_secrets` key `demo_pin`, the PIN as a bcrypt hash, never the PIN).
--   `demo_state()` answers whether it is on and whether a PIN is set, for
--     Business settings (`team.settings`).
--   `demo_set(p_on, p_pin)` turns it on or off and sets a new PIN (4 to 8
--     digits; empty keeps the one held), `team.settings` at Work; refused
--     `denied`, `bad-pin`, `no-pin` (on with none held). Filed
--     `team.changed` under Demo access, from and to, never the PIN.
--   `demo_pin_ok(p_pin)` (anon) answers true only while it is on and the
--     PIN is right. Wrong ones are counted as a link's passcode is
--     (`link_passcode`, kind `demo`): five within 15 minutes lock that
--     address out, longer each time, and the answer is false either way.
--   Nothing here reads or writes a client, a colleague or any record: the
--   demo's data lives in the visitor's browser alone (demo/engine.js).
--
-- ORDER: 2026-10-07-function-hygiene.sql again (its `open_to_anon` now
-- names `demo_pin_ok`), then this file (connector), then the pages. An old
-- page never asks.
--
-- ROLLBACK (SQL Editor):
--   drop function if exists public.demo_pin_ok(text);
--   drop function if exists public.demo_set(boolean, text);
--   drop function if exists public.demo_state();
--   delete from public.app_flags where key = 'demo';
--   delete from public.app_secrets where key = 'demo_pin';
-- ===========================================================================

create or replace function public.demo_state()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'on', coalesce((select f.on_now from public.app_flags f where f.key = 'demo'), false),
    'pin_set', exists (select 1 from public.app_secrets s where s.key = 'demo_pin' and coalesce(s.value, '') <> ''),
    'set_by', (select f.set_by from public.app_flags f where f.key = 'demo'),
    'set_at', (select f.set_at from public.app_flags f where f.key = 'demo'));
end $$;
revoke all on function public.demo_state() from public, anon;
grant execute on function public.demo_state() to authenticated;

create or replace function public.demo_set(p_on boolean, p_pin text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me public.team_members;
  v_was boolean;
  v_pin text := btrim(coalesce(p_pin, ''));
  v_held boolean;
  v_bits text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if v_pin <> '' and v_pin !~ '^[0-9]{4,8}$' then return jsonb_build_object('error', 'bad-pin'); end if;
  v_held := exists (select 1 from public.app_secrets s where s.key = 'demo_pin' and coalesce(s.value, '') <> '');
  if coalesce(p_on, false) and v_pin = '' and not v_held then return jsonb_build_object('error', 'no-pin'); end if;
  v_was := coalesce((select f.on_now from public.app_flags f where f.key = 'demo'), false);
  if v_pin <> '' then
    insert into public.app_secrets (key, value) values ('demo_pin', crypt(v_pin, gen_salt('bf', 8)))
    on conflict (key) do update set value = excluded.value, updated_at = now();
    v_bits := v_bits || 'PIN changed'::text;
  end if;
  if v_was is distinct from coalesce(p_on, false) then
    v_bits := array['Demo access: ' || case when v_was then 'On' else 'Off' end || ' → ' || case when p_on then 'On' else 'Off' end] || v_bits;
  end if;
  insert into public.app_flags as f (key, on_now, set_by, set_at)
  values ('demo', coalesce(p_on, false), coalesce(v_me.name, v_me.email), now())
  on conflict (key) do update set on_now = excluded.on_now,
    set_by = case when f.on_now is distinct from excluded.on_now or v_pin <> '' then excluded.set_by else f.set_by end,
    set_at = case when f.on_now is distinct from excluded.on_now or v_pin <> '' then excluded.set_at else f.set_at end;
  if array_length(v_bits, 1) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(v_me.name, v_me.email, 'admin'), 'team.changed', 'Demo access', array_to_string(v_bits, ' · '));
  end if;
  return public.demo_state();
end $$;
revoke all on function public.demo_set(boolean, text) from public, anon;
grant execute on function public.demo_set(boolean, text) to authenticated;

create or replace function public.demo_pin_ok(p_pin text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_hash text;
begin
  if not coalesce((select f.on_now from public.app_flags f where f.key = 'demo'), false) then return false; end if;
  select s.value into v_hash from public.app_secrets s where s.key = 'demo_pin';
  if coalesce(v_hash, '') = '' or coalesce(btrim(p_pin), '') !~ '^[0-9]{4,8}$' then return false; end if;
  return public.link_passcode('demo', 'demo', v_hash, crypt(btrim(p_pin), v_hash)) = 'ok';
end $$;
grant execute on function public.demo_pin_ok(text) to anon, authenticated;

-- END OF DEMO ACCESS ---------------------------------------------------------

select public.functions_tidy();
