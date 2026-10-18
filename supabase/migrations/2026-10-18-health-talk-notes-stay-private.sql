-- ===========================================================================
-- HEALTH TALK NOTES STAY BETWEEN THE TWO — a talk's note is read by the
-- colleague who asked and the colleague asked, never by Team: Health
-- (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 1; the user, 2026-10-18: management never reads a
-- talk's note): `health_team()` sent each talk's note, with both names, to
-- whoever reads Team: Health. Health is sensitive personal data (PDPA 2010);
-- the note is written for the colleague asked alone, who reads it in My
-- records (`health_mine()`, `asked_me`), as the asker does (`asked`).
--
-- WHAT IT CHANGES
--   * `health_team()` sends a talk's names, state and dates, never its note.
--     Everything else it answers is unchanged.
--
-- ORDER: this file, then the pages (an older page draws a note only where
-- one is sent, so it simply draws none). Safe to run twice.
-- Rollback: run the HEALTH CHECK-INS section's `health_team()` again.
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
              from (select * from public.health_checkins k where k.team_member_id = t.id
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

-- END OF HEALTH TALK NOTES STAY BETWEEN THE TWO -----------------------------

select public.functions_tidy();
