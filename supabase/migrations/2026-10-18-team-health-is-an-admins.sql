-- ===========================================================================
-- TEAM HEALTH IS AN ADMIN'S — Team: Health opens for an admin alone, behind
-- the Performance master code (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 11; the user: "only admin can view everyone else
-- health data"): `health_team()` asked only the granted part `team.health`,
-- which the group panel could give any group, and asked no code, while the
-- Performance reviews, less sensitive, are behind the master code.
--
-- WHAT IT CHANGES
--   * `health_check(p_token)`: null for an active admin holding a live
--     Performance unlock (`perf_unlock`, the master code, 15 minutes from
--     its last use, the same unlock Performance extends), else `denied`
--     (not an admin), `no-code` (no master code set) or `code-needed`.
--   * `health_team(p_token)` asks it first; everything it answers is as
--     before. The old `health_team()` stays for a page loaded before this
--     one and answers `code-needed` alone (no drop: the connector holds a
--     drop), so it reads nothing.
--   * `team.health` is no longer offered to a group; a group or colleague
--     holding it has it taken off their access map (it opened nothing for
--     anybody but an admin from now on).
--
-- ORDER: this file, then the pages (an old page meets `code-needed` and
-- reads Unable to load until it is reloaded). Safe to run twice.
-- Rollback: run HEALTH ANSWERS FOLLOW THE AGREEMENT's `health_team()`
-- again; `revoke` and `drop function public.health_team(text)` and
-- `public.health_check(text)` in the SQL Editor. The access maps are not
-- given the part back.
-- ===========================================================================

create or replace function public.health_check(p_token text)
returns text
language plpgsql security definer set search_path = public as $$
declare m public.team_members; n integer;
begin
  m := public.ops_me();
  if m.id is null then return 'not-team'; end if;
  if not (m.is_admin or m.role = 'admin') then return 'denied'; end if;
  if not public.perf_code_set() then return 'no-code'; end if;
  update public.perf_unlocks set expires_at = now() + interval '15 minutes'
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and team_member_id = m.id and expires_at > now();
  get diagnostics n = row_count;
  if n = 0 then return 'code-needed'; end if;
  return null;
end $$;
revoke all on function public.health_check(text) from public, anon, authenticated;

create or replace function public.health_team(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; h date; e text;
begin
  m := public.ops_me();
  e := public.health_check(p_token);
  if e is not null then return jsonb_build_object('error', e); end if;
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
revoke all on function public.health_team(text) from public, anon, authenticated;
grant execute on function public.health_team(text) to authenticated;

create or replace function public.health_team()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('error', 'code-needed')
$$;
revoke all on function public.health_team() from public, anon, authenticated;
grant execute on function public.health_team() to authenticated;

update public.team_roles set access = access - 'team.health' where access ? 'team.health';
update public.team_members set access = access - 'team.health' where access ? 'team.health';

-- END OF TEAM HEALTH IS AN ADMIN'S ------------------------------------------

select public.functions_tidy();
