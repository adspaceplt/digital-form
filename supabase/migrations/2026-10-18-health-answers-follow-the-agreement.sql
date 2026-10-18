-- ===========================================================================
-- HEALTH ANSWERS FOLLOW THE AGREEMENT — Team: Health reads only the check-ins
-- given since the colleague's agreement now standing (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 2): withdrawing takes a colleague's answers out of
-- Team: Health, but Agree again showed the last twelve half months once
-- more, answers given before the withdrawal included. Those were given under
-- an agreement the colleague ended; a new agreement covers what is answered
-- under it.
--
-- WHAT IT CHANGES
--   * `health_team()` sends a colleague's check-ins only where the check-in
--     was last saved on or after the current `agreed_at` (a half month's
--     check-in answered again after agreeing is the new answer). The
--     colleague still reads all of their own in My records.
--
-- ORDER: this file, then the pages (nothing on the page changes). Safe to
-- run twice. Rollback: run HEALTH TALK NOTES STAY BETWEEN THE TWO's
-- `health_team()` again.
-- ===========================================================================

create or replace function public.health_team()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; h date;
begin
  m := public.ops_me();
  if m.id is null or not public.ops_granted('team.health', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  h := public.health_half(public.health_today());
  return jsonb_build_object('half', h, 'half_end', public.health_half_end(h),
    'people', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'staff_code', t.staff_code, 'designation', t.designation,
        'department', t.department, 'role', t.role,
        'consent', case when c.team_member_id is null then null else jsonb_build_object(
          'agreed_at', c.agreed_at, 'withdrawn_at', c.withdrawn_at) end,
        'checkins', case when c.team_member_id is not null and c.withdrawn_at is null then coalesce((
            select jsonb_agg(public.health_checkin_json(x) order by x.half desc)
              from (select * from public.health_checkins k
                     where k.team_member_id = t.id and k.updated_at >= c.agreed_at
                     order by k.half desc limit 12) x), '[]'::jsonb) else '[]'::jsonb end)
        order by t.staff_code nulls last, t.name)
        from public.team_members t
        left join public.health_consents c on c.team_member_id = t.id
       where t.active), '[]'::jsonb),
    'talks', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'from', f.name, 'from_id', k.team_member_id, 'with', w.name, 'with_id', k.with_id,
        'status', k.status, 'at', k.created_at, 'closed_at', k.closed_at)
        order by (k.status = 'open') desc, k.created_at desc)
        from public.health_talks k
        join public.team_members f on f.id = k.team_member_id
        join public.team_members w on w.id = k.with_id
       where k.status <> 'withdrawn' and k.created_at > now() - interval '90 days'), '[]'::jsonb));
end $$;
revoke all on function public.health_team() from public, anon, authenticated;
grant execute on function public.health_team() to authenticated;

-- END OF HEALTH ANSWERS FOLLOW THE AGREEMENT ---------------------------------

select public.functions_tidy();
