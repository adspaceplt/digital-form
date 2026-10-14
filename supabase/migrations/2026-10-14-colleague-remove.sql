-- ===========================================================================
-- COLLEAGUE REMOVE — Delete on a colleague: access ended for good, their data
-- kept or their personal details deleted (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-14: "when someone is removed from portal, could you
-- just make it as inactive users optionally delete the data"; then "to have
-- the option, delete button to either delete or keep their data")
--
-- WHAT IT ADDS
--   * `team_member_remove(p_member, p_erase, p_name)` (Team Full Access; never
--     one's own row (`own`), never a system account (`system-account`), never
--     the last admin with access (`last-admin`); the name typed back,
--     `bad-name`): the colleague is set inactive and stamped `removed_at`.
--     With `p_erase` their personal details go as well, and `erased_at` is
--     stamped: the mobile, the namecard (off, its short link freed), the
--     sign-in email and its login, their health check-ins, consents, log
--     and talks, their notification devices, guides met and section order.
--     Kept either way: their name, Employee ID and group on the row; their
--     name on past work and every document they issued or signed; their own
--     HR letters and performance records (the company's records). Filed
--     `team.changed` under the colleague. Their live work is handed over
--     first by `team_hand_over` (COLLEAGUE HAND-OVER).
--
-- Run in the SQL Editor (it removes rows, which the connector holds), after
-- 2026-10-14-colleague-hand-over.sql. Safe to run twice. Rollback: remove
-- the function.
-- ===========================================================================

create or replace function public.team_member_remove(p_member uuid, p_erase boolean, p_name text)
returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  me      public.team_members := public.ops_me();
  v_m     public.team_members;
  v_email text;
begin
  if me.id is null or not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_m from public.team_members x where x.id = p_member for update;
  if v_m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_m.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if coalesce(v_m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if lower(btrim(coalesce(p_name, ''))) <> lower(btrim(v_m.name)) then return jsonb_build_object('error', 'bad-name'); end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and v_m.active
     and not exists (select 1 from public.team_members x where x.id <> v_m.id and x.active
                       and (coalesce(x.is_admin, false) or x.role = 'admin')) then
    return jsonb_build_object('error', 'last-admin');
  end if;
  v_email := v_m.email;
  update public.team_members x set active = false, removed_at = coalesce(x.removed_at, now()), card_on = false
   where x.id = p_member;
  if coalesce(p_erase, false) then
    update public.team_members x
       set mobile = null, card_mobile = false, card_email = null, card_slug = null, email = null, erased_at = now()
     where x.id = p_member;
    delete from public.health_checkins h where h.team_member_id = p_member;
    delete from public.health_talks h where h.team_member_id = p_member;
    delete from public.health_consents h where h.team_member_id = p_member;
    delete from public.health_log h where h.team_member_id = p_member;
    delete from public.push_subscriptions s where s.team_member_id = p_member;
    delete from public.guide_seen g where g.team_member_id = p_member;
    delete from public.rail_orders o where o.member_id = p_member;
    if v_email is not null and not exists (select 1 from public.client_contacts k
                                             where lower(k.email) = lower(v_email) and k.archived_at is null) then
      delete from auth.users u where lower(u.email) = lower(v_email);
    end if;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', v_m.name,
          'Removed from the portal · ' || case when coalesce(p_erase, false) then 'personal details deleted' else 'their data kept' end);
  return jsonb_build_object('ok', true, 'erased', coalesce(p_erase, false));
end $$;
revoke all on function public.team_member_remove(uuid, boolean, text) from public, anon;
grant execute on function public.team_member_remove(uuid, boolean, text) to authenticated;

-- END OF COLLEAGUE REMOVE ----------------------------------------------------

select public.functions_tidy();
