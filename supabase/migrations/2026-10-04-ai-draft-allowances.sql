-- ===========================================================================
-- DRAFT WITH AI ALLOWANCES — an admin sees every colleague's use of Draft
-- with AI and sets how many drafts a day each may take, the team's included.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `ai_draft_limits` holds the day's allowances: `team` (60 unless set),
--      `person` (each colleague's, 20 unless set) and one row a colleague
--      set apart from it (the colleague's id). A null daily reads the default;
--      0 stops Draft with AI. RLS on, no policy, no grants.
--   2. `ai_draft_claim` and `ai_draft_left` read them: a colleague at 0 is
--      refused `stopped`, a team at 0 `team` with no time the next is free.
--      A report's one draft and an admin's five a report a day are unchanged.
--   3. `ai_draft_usage()` (admin): each colleague who may draft or drafted in
--      the last 30 days, with the last 24 hours, 30 days, failed presses,
--      the last press and the allowance; the team's figures and defaults.
--   4. `ai_draft_set_limit(p_scope, p_daily)` (admin): `team`, `person` or a
--      colleague's id; null puts the default back. Filed `team.changed`
--      under subject Draft with AI, from and to; a set that changes nothing
--      files nothing.
--
-- ROLLBACK
--   Run the DRAFT WITH AI BY SUBJECT section's ai_draft_claim and
--   ai_draft_left again, then remove the functions ai_draft_usage(),
--   ai_draft_set_limit(text, integer) and ai_draft_limit(text, integer), and
--   the table ai_draft_limits.
-- ===========================================================================

create table if not exists public.ai_draft_limits (
  scope   text primary key,
  daily   integer check (daily is null or daily between 0 and 500),
  set_by  text,
  set_at  timestamptz not null default now()
);
alter table public.ai_draft_limits enable row level security;
revoke all on table public.ai_draft_limits from public, anon, authenticated;

-- A scope's allowance a day, else the default given.
create or replace function public.ai_draft_limit(p_scope text, p_default integer)
returns integer
language sql stable security definer set search_path = public as $$
  select coalesce((select l.daily from public.ai_draft_limits l where l.scope = p_scope), p_default)
$$;
revoke all on function public.ai_draft_limit(text, integer) from public, anon, authenticated;

create or replace function public.ai_draft_claim(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := now() - interval '24 hours';
  n_report integer;
  n_member integer;
  n_team integer;
  lim_member integer;
  lim_team integer;
  first_at timestamptz;
  new_id uuid;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  -- One count at a time, so two presses together cannot both take the last draft.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  select * into r from public.sm_reports where id = p_report;
  lim_member := public.ai_draft_limit(m.id::text, public.ai_draft_limit('person', 20));
  lim_team := public.ai_draft_limit('team', 60);
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  if lim_team = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'team', 'limit', 0);
  end if;
  -- One draft a subject; a second and later is an admin's.
  if not coalesce(m.is_admin, false) and exists (select 1 from public.ai_draft_same(p_report)) then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'redraft', 'limit', 1);
  end if;
  select count(*), min(s.created_at) into n_report, first_at from public.ai_draft_same(p_report) s
   where s.created_at > since;
  if n_report >= 5 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report', 'limit', 5, 'next', first_at + interval '24 hours');
  end if;
  select count(*), min(d.created_at) into n_member, first_at from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at > since and d.outcome <> 'failed';
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'person', 'limit', lim_member, 'next', first_at + interval '24 hours');
  end if;
  select count(*), min(d.created_at) into n_team, first_at from public.ai_drafts d
   where d.created_at > since and d.outcome <> 'failed';
  if n_team >= lim_team then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'team', 'limit', lim_team, 'next', first_at + interval '24 hours');
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
  since timestamptz := now() - interval '24 hours';
  is_adm boolean;
  n_report integer; n_member integer; n_team integer;
  at_report timestamptz; at_member timestamptz; at_team timestamptz;
  l_report integer; l_member integer; l_team integer; l_min integer;
  lim_member integer; lim_team integer;
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  is_adm := coalesce(m.is_admin, false);
  lim_member := public.ai_draft_limit(m.id::text, public.ai_draft_limit('person', 20));
  lim_team := public.ai_draft_limit('team', 60);
  select count(*), min(s.created_at) into n_report, at_report from public.ai_draft_same(p_report) s
   where s.created_at > since;
  if is_adm then
    l_report := greatest(0, 5 - n_report);
  elsif exists (select 1 from public.ai_draft_same(p_report)) then
    l_report := 0;
  else
    l_report := 1;
  end if;
  select count(*), min(d.created_at) into n_member, at_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at > since and d.outcome <> 'failed';
  l_member := greatest(0, lim_member - n_member);
  select count(*), min(d.created_at) into n_team, at_team from public.ai_drafts d
   where d.created_at > since and d.outcome <> 'failed';
  l_team := greatest(0, lim_team - n_team);
  l_min := least(l_report, l_member, l_team);
  v_scope := case when lim_member = 0 then 'stopped'
                  when lim_team = 0 then 'team'
                  when l_min = l_report then case when is_adm then 'report' else 'redraft' end
                  when l_min = l_member then 'person' else 'team' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope,
    'limit', case v_scope when 'stopped' then 0 when 'redraft' then 1 when 'report' then 5
                          when 'person' then lim_member else lim_team end,
    'report', l_report, 'person', l_member, 'team', l_team, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope in ('redraft', 'stopped') or lim_team = 0 then null
                 when v_scope = 'report' then at_report + interval '24 hours'
                 when v_scope = 'person' then at_member + interval '24 hours'
                 else at_team + interval '24 hours' end);
end $$;

revoke all on function public.ai_draft_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_draft_left(uuid) from public, anon, authenticated;
grant execute on function public.ai_draft_claim(uuid) to authenticated;
grant execute on function public.ai_draft_left(uuid) to authenticated;

-- Every colleague's use and allowance, for an admin.
create or replace function public.ai_draft_usage()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := now() - interval '24 hours';
  v_month timestamptz := now() - interval '30 days';
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'person', public.ai_draft_limit('person', 20),
    'team', public.ai_draft_limit('team', 60),
    'team_day', (select count(*) from public.ai_drafts d where d.created_at > v_day and d.outcome <> 'failed'),
    'team_month', (select count(*) from public.ai_drafts d where d.created_at > v_month and d.outcome <> 'failed'),
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name,
        'admin', coalesce(t.is_admin, false),
        'day', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_day and d.outcome <> 'failed'),
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed'),
        'failed', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome = 'failed'),
        'last', (select max(d.created_at) from public.ai_drafts d where d.team_member_id = t.id and d.outcome <> 'failed'),
        'limit', (select l.daily from public.ai_draft_limits l where l.scope = t.id::text)) as x
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

-- An allowance a day: the team's, each colleague's, or one colleague's.
-- Null puts the default back.
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
  if v_scope = 'team' then
    v_name := 'Team'; v_def := 60;
  elsif v_scope = 'person' then
    v_name := 'Each colleague'; v_def := 20;
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
          case when v_was is null then 'default, ' || v_def || ' a day' when v_was = 0 then 'stopped' else v_was || ' a day' end ||
          ' → ' ||
          case when p_daily is null then 'default, ' || v_def || ' a day' when p_daily = 0 then 'stopped' else p_daily || ' a day' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.ai_draft_set_limit(text, integer) from public, anon, authenticated;
grant execute on function public.ai_draft_set_limit(text, integer) to authenticated;

-- END OF DRAFT WITH AI ALLOWANCES --------------------------------------------
