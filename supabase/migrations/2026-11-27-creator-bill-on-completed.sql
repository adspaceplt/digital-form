-- ===========================================================================
-- CREATOR BILL ON COMPLETED (2026-11-27)
-- ===========================================================================
-- WHY: the linked sections (the user, 27 Nov: "the link could proceed on",
-- flow 2 as recommended): a booking marked Completed with its creator fee
-- set makes the creator's draft bill in Bukku at once, in the colleague's
-- own session, through the same `bukku-sync` `createbill` as Create bill.
-- A Business setting turns it off.
--
-- WHAT CHANGES
--   * `creator_bill_on_completed` (0 Off, 1 On, from a day; seeded On),
--     read by `creator_bill_auto_on()`, set by `creator_bill_auto_set(p_on)`
--     (team.settings Work, filed `team.changed` under Settings).
--   * `creator_bill_auto_ok(p_option)`: asked by `bukku-sync` before a bill
--     made on Completed (`auto`), as the caller: `auto-off` with the
--     setting off, `not-completed` for a booking not Completed, `denied`
--     outside the team. `creator_bill_prep` then holds every other rule
--     (the fee, the link, the account, a bill already held).
--
-- ORDER: this file (connector), then `bukku-sync` (Management API, with its
-- _shared files, read back), then the pages (Pages deploy). An old page
-- never asks `auto`; a page served before the function answers nothing
-- for `auto` and the booking still completes.
-- Safe to run twice.
-- ROLLBACK: `creator_bill_auto_set(false)` stops it at once; the functions
-- and the setting may stay. To remove: drop the three functions and
-- `delete from app_settings where key = 'creator_bill_on_completed'`.
-- ===========================================================================

-- CREATOR BILL ON COMPLETED --------------------------------------------------

insert into public.app_settings (key, from_date, value)
select 'creator_bill_on_completed', date '2023-08-14', 1
 where not exists (select 1 from public.app_settings s where s.key = 'creator_bill_on_completed');

create or replace function public.creator_bill_auto_on()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.app_setting('creator_bill_on_completed', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) = 1
$$;
revoke all on function public.creator_bill_auto_on() from public, anon, authenticated;

create or replace function public.creator_bill_auto_set(p_on boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_was   numeric;
  v_to    numeric := case when coalesce(p_on, false) then 1 else 0 end;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_was := public.app_setting('creator_bill_on_completed', v_today);
  if v_was is not distinct from v_to then return jsonb_build_object('ok', true); end if;
  insert into public.app_settings (key, from_date, value, set_by, set_at)
  values ('creator_bill_on_completed', v_today, v_to, me.id, now())
  on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Settings',
          'Bill creators on Completed: ' || case when v_was = 1 then 'On' else 'Off' end || ' → ' ||
          case when v_to = 1 then 'On' else 'Off' end || ' · from ' || public.register_day(v_today));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_bill_auto_set(boolean) from public, anon, authenticated;
grant execute on function public.creator_bill_auto_set(boolean) to authenticated;

create or replace function public.creator_bill_auto_ok(p_option uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_state text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not public.creator_bill_auto_on() then return jsonb_build_object('error', 'auto-off'); end if;
  select o.state into v_state from public.campaign_options o where o.id = p_option;
  if v_state is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_state <> 'completed' then return jsonb_build_object('error', 'not-completed'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_bill_auto_ok(uuid) from public, anon, authenticated;
grant execute on function public.creator_bill_auto_ok(uuid) to authenticated;

-- END OF CREATOR BILL ON COMPLETED -------------------------------------------

select public.functions_tidy();
