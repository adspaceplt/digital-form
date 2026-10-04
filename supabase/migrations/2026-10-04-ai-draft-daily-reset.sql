-- ===========================================================================
-- DRAFT WITH AI RESETS AT MIDNIGHT — a colleague's drafts are counted from
-- 12:00 am Malaysia time and start again each midnight; the team's and a
-- group's totals are the sum of their colleagues' limits.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after DRAFT WITH AI ALLOWANCES.
--
-- WHAT CHANGED (the user, 2026-10-04: reset at midnight, like a usage page;
-- set only each person's limit and let the totals add up)
--   1. `ai_draft_claim` and `ai_draft_left` count a colleague's drafts and a
--      report's from today's 12:00 am MYT, not the last 24 hours; the next
--      draft is free at the next midnight. The team's own cap is gone: the
--      team can draft only what its colleagues' limits add up to.
--   2. `ai_draft_usage()` answers the reset (`resets_at`) and, for every
--      colleague who may draft or drafted in 30 days, today's count, the
--      limit that applies (`cap`, their own else the standard) and their
--      group; the page adds up the team and each group.
--   3. `ai_draft_set_limit` takes `person` (the standard) or a colleague's
--      id; `team` is refused (`bad-scope`).
--
-- ROLLBACK
--   Run the DRAFT WITH AI ALLOWANCES section's ai_draft_claim,
--   ai_draft_left, ai_draft_usage and ai_draft_set_limit again.
-- ===========================================================================

-- Today's 12:00 am in Malaysia, the start of every count.
create or replace function public.ai_draft_day()
returns timestamptz
language sql stable set search_path = public as $$
  select (date_trunc('day', now() at time zone 'Asia/Kuala_Lumpur')) at time zone 'Asia/Kuala_Lumpur'
$$;
revoke all on function public.ai_draft_day() from public, anon, authenticated;

create or replace function public.ai_draft_claim(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  n_report integer;
  n_member integer;
  lim_member integer;
  new_id uuid;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  -- One count at a time, so two presses together cannot both take the last draft.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  select * into r from public.sm_reports where id = p_report;
  lim_member := public.ai_draft_limit(m.id::text, public.ai_draft_limit('person', 20));
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  -- One draft a subject; a second and later is an admin's.
  if not coalesce(m.is_admin, false) and exists (select 1 from public.ai_draft_same(p_report)) then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'redraft', 'limit', 1);
  end if;
  select count(*) into n_report from public.ai_draft_same(p_report) s where s.created_at >= since;
  if n_report >= 5 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report', 'limit', 5, 'next', since + interval '1 day');
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed';
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'person', 'limit', lim_member, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim_member - n_member - 1);
end $$;

create or replace function public.ai_draft_left(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  is_adm boolean;
  n_report integer; n_member integer;
  l_report integer; l_member integer; l_min integer;
  lim_member integer;
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  is_adm := coalesce(m.is_admin, false);
  lim_member := public.ai_draft_limit(m.id::text, public.ai_draft_limit('person', 20));
  select count(*) into n_report from public.ai_draft_same(p_report) s where s.created_at >= since;
  if is_adm then
    l_report := greatest(0, 5 - n_report);
  elsif exists (select 1 from public.ai_draft_same(p_report)) then
    l_report := 0;
  else
    l_report := 1;
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed';
  l_member := greatest(0, lim_member - n_member);
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped'
                  when l_min = l_report then case when is_adm then 'report' else 'redraft' end
                  else 'person' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope,
    'limit', case v_scope when 'stopped' then 0 when 'redraft' then 1 when 'report' then 5 else lim_member end,
    'report', l_report, 'person', l_member, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope in ('redraft', 'stopped') then null else since + interval '1 day' end);
end $$;

revoke all on function public.ai_draft_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_draft_left(uuid) from public, anon, authenticated;
grant execute on function public.ai_draft_claim(uuid) to authenticated;
grant execute on function public.ai_draft_left(uuid) to authenticated;

-- Every colleague's use today against their limit, for an admin.
create or replace function public.ai_draft_usage()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
  v_std integer := public.ai_draft_limit('person', 20);
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'person', v_std,
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false),
        'day', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed'),
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed'),
        'limit', (select l.daily from public.ai_draft_limits l where l.scope = t.id::text),
        'cap', coalesce((select l.daily from public.ai_draft_limits l where l.scope = t.id::text), v_std)) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or exists (select 1 from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month))
    ) s), '[]'::jsonb));
end $$;
revoke all on function public.ai_draft_usage() from public, anon, authenticated;
grant execute on function public.ai_draft_usage() to authenticated;

-- A colleague's limit a day, or the standard for everyone. Null puts the
-- standard back.
create or replace function public.ai_draft_set_limit(p_scope text, p_daily integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_who text;
  v_name text;
  v_was integer;
  v_def integer;
  v_scope text := btrim(coalesce(p_scope, ''));
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  if p_daily is not null and (p_daily < 0 or p_daily > 500) then
    return jsonb_build_object('error', 'bad-limit');
  end if;
  if v_scope = 'person' then
    v_name := 'Each colleague'; v_def := 20;
  elsif v_scope = 'team' then
    return jsonb_build_object('error', 'bad-scope');
  else
    select t.name into v_name from public.team_members t where t.id::text = v_scope;
    if v_name is null then return jsonb_build_object('error', 'not-found'); end if;
    v_def := public.ai_draft_limit('person', 20);
  end if;
  select l.daily into v_was from public.ai_draft_limits l where l.scope = v_scope;
  if v_was is not distinct from p_daily then return jsonb_build_object('ok', true, 'same', true); end if;
  select coalesce(t.name, t.email) into v_who from public.team_members t
   where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1;
  insert into public.ai_draft_limits (scope, daily, set_by, set_at)
  values (v_scope, p_daily, v_who, now())
  on conflict (scope) do update set daily = excluded.daily, set_by = excluded.set_by, set_at = excluded.set_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'Draft with AI',
          v_name || ': ' ||
          case when v_was is null then 'standard, ' || v_def || ' a day' when v_was = 0 then 'stopped' else v_was || ' a day' end ||
          ' → ' ||
          case when p_daily is null then 'standard, ' || v_def || ' a day' when p_daily = 0 then 'stopped' else p_daily || ' a day' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.ai_draft_set_limit(text, integer) from public, anon, authenticated;
grant execute on function public.ai_draft_set_limit(text, integer) to authenticated;

-- END OF DRAFT WITH AI RESETS AT MIDNIGHT -------------------------------------
