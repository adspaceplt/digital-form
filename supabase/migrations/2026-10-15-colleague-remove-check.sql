-- ===========================================================================
-- COLLEAGUE REMOVE CHECK — removing a colleague asks who may be removed
-- before any of their work is handed over (2026-10-15)
-- ===========================================================================
-- WHY (audit, 2026-10-15): the removal handed a colleague's work over first and
-- asked `team_member_remove` second, so a refusal it alone knew (the last
-- admin with access) left their work moved and the colleague in place.
--
-- WHAT IT ADDS
--   * `team_member_remove_check(p_member)` (Team Full Access): the same
--     refusals `team_member_remove` gives before it writes (`denied`,
--     `not-found`, `own`, `system-account`, `last-admin`), answering
--     `{ok: true}` where none applies. It writes nothing. The page asks it
--     before the hand-over; `team_member_remove` still asks every one of
--     them itself.
--
-- Run after 2026-10-14-colleague-remove.sql. Safe to run twice. Rollback:
-- remove the function (the page then hands over first, as before).
-- ===========================================================================

create or replace function public.team_member_remove_check(p_member uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  v_m public.team_members;
begin
  if me.id is null or not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_m from public.team_members x where x.id = p_member;
  if v_m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_m.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if coalesce(v_m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and v_m.active
     and not exists (select 1 from public.team_members x where x.id <> v_m.id and x.active
                       and (coalesce(x.is_admin, false) or x.role = 'admin')) then
    return jsonb_build_object('error', 'last-admin');
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_member_remove_check(uuid) from public, anon;
grant execute on function public.team_member_remove_check(uuid) to authenticated;

-- END OF COLLEAGUE REMOVE CHECK ----------------------------------------------

select public.functions_tidy();
