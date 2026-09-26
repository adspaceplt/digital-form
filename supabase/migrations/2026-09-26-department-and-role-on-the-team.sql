-- ===========================================================================
-- DEPARTMENT AND ROLE ON THE TEAM — who a colleague is is kept where the
-- team keeps them, and Performance reads it from there.
-- 2026-09-26. Safe to run twice. Run after 2026-09-24-performance-code-always.sql.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/perf.js compares the two.
--
-- WHAT CHANGED. The user, on 2026-09-26: department and role are changed on
-- the Team page for each member and carried over to Performance. They were
-- kept on perf_people behind both performance locks, so a department was
-- typed into the designation on the Team page ("Creative, Production
-- Executive") and set again on the review sheet. `team_members` gains
-- `department` and `role_family` (the role standard); perf_json and
-- perf_month read them from the team row, and perf_profile_set keeps only
-- the two review settings (runs client ads, reviewed every month). The Team
-- page writes the columns under the policy that already governs that row.
--
-- THE DATA, ONCE. (1) Each colleague's department and role standard move
-- from perf_people to the team row where the team row has none, and are
-- cleared on perf_people, so a later run cannot put back a value somebody
-- has since cleared on the Team page. (2) A designation typed as a
-- department, a comma and a position ("Creative, Production Executive")
-- becomes the department Creative and the position Production Executive,
-- where the row has no department yet or names the same one; any other
-- designation is left as typed. The last statement lists every colleague
-- holding a department or a role afterwards.
--
-- ROLLBACK
--   update public.perf_people pp set department = t.department, role_family = t.role_family
--     from public.team_members t where t.id = pp.team_member_id;
--   then re-run perf_json, perf_month and perf_profile_set from
--   2026-09-24-performance-reviews.sql. The columns on team_members may stay.
--   A split designation is not put back by itself: the list at the foot of
--   the first run names who had one.
-- ===========================================================================

alter table public.team_members add column if not exists department text;
alter table public.team_members add column if not exists role_family text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'team_members_department_check') then
    alter table public.team_members add constraint team_members_department_check
      check (department in ('creative', 'marketing'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'team_members_role_family_check') then
    alter table public.team_members add constraint team_members_role_family_check
      check (role_family in ('visual', 'video', 'planner', 'account'));
  end if;
end $$;

/* (1) What the review sheet held moves to the team row, once. */
update public.team_members t
   set department = coalesce(t.department, pp.department),
       role_family = coalesce(t.role_family, pp.role_family)
  from public.perf_people pp
 where pp.team_member_id = t.id
   and (pp.department is not null or pp.role_family is not null);
update public.perf_people set department = null, role_family = null
 where department is not null or role_family is not null;

/* (2) "Creative, Production Executive" is a department and a position. */
update public.team_members t
   set department = lower(s.parts[1]), designation = btrim(s.parts[2])
  from (select id, regexp_match(designation, '^\s*(creative|marketing)\s*,\s*(\S.*)$', 'i') as parts
          from public.team_members) s
 where s.id = t.id and s.parts is not null
   and (t.department is null or t.department = lower(s.parts[1]));

/* Performance reads the team row. */
create or replace function public.perf_json(r public.perf_reviews, p_full boolean)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.team_members; pp public.perf_people; out jsonb;
begin
  select * into m from public.team_members where id = r.team_member_id;
  select * into pp from public.perf_people where team_member_id = r.team_member_id;
  out := jsonb_build_object(
    'id', r.id, 'team_member_id', r.team_member_id, 'period', r.period,
    'month', public.perf_month_word(r.period), 'status', r.status,
    'member', jsonb_build_object('name', m.name, 'staff_code', m.staff_code,
      'designation', m.designation, 'department', m.department,
      'role_family', m.role_family, 'runs_ads', coalesce(pp.runs_ads, false)),
    'scores', jsonb_build_object('output', r.s_output, 'accuracy', r.s_accuracy,
      'delivery', r.s_delivery, 'client', r.s_client, 'comms', r.s_comms,
      'initiative', r.s_initiative),
    'rates', jsonb_build_object('posting', r.r_posting, 'timeline', r.r_timeline,
      'satisfaction', r.r_satisfaction, 'pacing', r.r_pacing, 'sla', r.r_sla),
    'notes', r.notes, 'improvement', r.improvement, 'review_by', r.review_by,
    'reward_step', r.reward_step, 'serial', r.serial,
    'reviewer', (select name from public.team_members where id = r.reviewer_id),
    'released_at', r.released_at, 'dispute_until', r.dispute_until,
    'dispute_open', r.status = 'released' and r.dispute_until > now()
                    and not exists (select 1 from public.perf_disputes d
                                     where d.review_id = r.id and d.version = r.version),
    'acknowledged_at', r.acknowledged_at, 'finalised_at', r.finalised_at,
    'finalised_by', (select name from public.team_members where id = r.finalised_by),
    'version', r.version, 'rev', r.rev,
    'result', public.perf_calc(r),
    'breaches', public.perf_breaches_json(r.team_member_id, r.period, false),
    'disputes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', d.id, 'item', d.item, 'breach_id', d.breach_id, 'reason', d.reason,
        'breach_what', (select b.what from public.perf_breaches b where b.id = d.breach_id),
        'raised_at', d.raised_at, 'decision', d.decision, 'response', d.response,
        'before_value', d.before_value, 'after_value', d.after_value,
        'decided_by', (select name from public.team_members where id = d.decided_by),
        'decided_at', d.decided_at) order by d.raised_at)
        from public.perf_disputes d where d.review_id = r.id and d.version = r.version), '[]'::jsonb));
  if p_full then
    out := out || jsonb_build_object(
      'voided', (select coalesce(jsonb_agg(x), '[]'::jsonb)
                   from jsonb_array_elements(public.perf_breaches_json(r.team_member_id, r.period, true)) x
                  where x ->> 'voided_at' is not null),
      'ops', public.perf_ops_rate(r.team_member_id, r.period),
      'events', coalesce((select jsonb_agg(jsonb_build_object(
          'kind', e.kind, 'detail', e.detail, 'at', e.created_at,
          'by', coalesce((select name from public.team_members where id = e.actor_id), e.actor_email))
          order by e.created_at desc)
          from public.perf_events e where e.review_id = r.id), '[]'::jsonb));
  end if;
  return out;
end $$;

create or replace function public.perf_month(p_token text, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; p date := date_trunc('month', p_period)::date;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  return jsonb_build_object(
    'period', p, 'month', public.perf_month_word(p),
    'people', coalesce((select jsonb_agg(x order by x ->> 'name') from (
      select jsonb_build_object(
        'team_member_id', t.id, 'name', t.name, 'staff_code', t.staff_code,
        'designation', t.designation,
        'department', t.department, 'role_family', t.role_family,
        'runs_ads', coalesce(pp.runs_ads, false),
        'reviewed', public.perf_reviewed(t.id),
        'breaches', (select count(*) from public.perf_breaches b
                      where b.team_member_id = t.id and b.period = p and b.voided_at is null),
        'review', case when r.id is null then null else jsonb_build_object(
          'id', r.id, 'status', r.status, 'result', public.perf_calc(r),
          'open_disputes', (select count(*) from public.perf_disputes d
                             where d.review_id = r.id and d.version = r.version and d.decision is null),
          'dispute_until', r.dispute_until) end) as x
        from public.team_members t
        left join public.perf_people pp on pp.team_member_id = t.id
        left join public.perf_reviews r on r.team_member_id = t.id and r.period = p
       where t.active and t.id <> m.id) q), '[]'::jsonb));
end $$;

create or replace function public.perf_profile_set(p_token text, p_member uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; kept jsonb;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  /* Department and role are the Team page's now. A page from before this
     change may still send them; they are left out rather than refused, so
     its two ticks still save. */
  kept := coalesce(p_payload, '{}'::jsonb) - 'department' - 'role_family';
  insert into public.perf_people (team_member_id, runs_ads, reviewed)
  values (p_member, coalesce((kept ->> 'runs_ads')::boolean, false),
          case when kept ? 'reviewed' then (kept ->> 'reviewed')::boolean end)
  on conflict (team_member_id) do update set
    runs_ads = case when kept ? 'runs_ads' then coalesce((kept ->> 'runs_ads')::boolean, false) else perf_people.runs_ads end,
    reviewed = case when kept ? 'reviewed' then (kept ->> 'reviewed')::boolean else perf_people.reviewed end,
    updated_at = now();
  perform public.perf_log(null, p_member, 'profile', kept);
  return jsonb_build_object('ok', true);
end $$;

select name, department, role_family, designation from public.team_members
 where department is not null or role_family is not null order by name;

-- END OF DEPARTMENT AND ROLE ON THE TEAM -------------------------------------
