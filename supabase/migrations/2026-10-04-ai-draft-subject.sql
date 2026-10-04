-- ===========================================================================
-- DRAFT WITH AI BY SUBJECT — a report's one draft is counted by what the
-- report is about, so deleting it and starting it again does not free a
-- second draft.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `ai_drafts` keeps the report's subject on every press: its client,
--      its kind and its period. A deleted report's link is set to null, so
--      the count by report alone came back to nothing and a new report for
--      the same client and month took a fresh draft. The subject stays.
--      Earlier presses are filled in from their reports; a press whose
--      report is already gone has none.
--   2. `ai_draft_claim(p_report)` and `ai_draft_left(p_report)` count, for
--      the report's one draft and an admin's five a day, every press on the
--      report or on any report of the same client and kind whose period
--      shares a day with it, deleted or not. The colleague's twenty and the
--      team's sixty a day are unchanged, as is a failed press not counting.
--
-- ROLLBACK
--   Run the DRAFT WITH AI LIMITS section's ai_draft_claim and the DRAFT WITH
--   AI LEFT section's ai_draft_left again, then
--   drop function if exists public.ai_draft_same(uuid);
--   alter table public.ai_drafts drop column if exists period_end,
--     drop column if exists period_start, drop column if exists kind,
--     drop column if exists client_id;
-- ===========================================================================

alter table public.ai_drafts add column if not exists client_id uuid;
alter table public.ai_drafts add column if not exists kind text;
alter table public.ai_drafts add column if not exists period_start date;
alter table public.ai_drafts add column if not exists period_end date;
create index if not exists ai_drafts_subject_idx on public.ai_drafts (client_id, kind, period_start, period_end);

update public.ai_drafts d
   set client_id = r.client_id, kind = r.kind, period_start = r.period_start, period_end = r.period_end
  from public.sm_reports r
 where r.id = d.report_id and d.client_id is null;

-- The presses on a report's subject: the report itself, or any report of the
-- same client and kind whose period shares a day with it.
create or replace function public.ai_draft_same(p_report uuid)
returns setof public.ai_drafts
language sql stable security definer set search_path = public as $$
  select d.* from public.ai_drafts d
   where d.outcome <> 'failed'
     and (d.report_id = p_report
          or exists (select 1 from public.sm_reports r
                      where r.id = p_report and d.client_id = r.client_id and d.kind = r.kind
                        and d.period_start <= r.period_end and d.period_end >= r.period_start))
$$;
revoke all on function public.ai_draft_same(uuid) from public, anon, authenticated;

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
  first_at timestamptz;
  new_id uuid;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  -- One count at a time, so two presses together cannot both take the last draft.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  select * into r from public.sm_reports where id = p_report;
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
  if n_member >= 20 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'person', 'limit', 20, 'next', first_at + interval '24 hours');
  end if;
  select count(*), min(d.created_at) into n_team, first_at from public.ai_drafts d
   where d.created_at > since and d.outcome <> 'failed';
  if n_team >= 60 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'team', 'limit', 60, 'next', first_at + interval '24 hours');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', 20 - n_member - 1);
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
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  is_adm := coalesce(m.is_admin, false);
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
  l_member := greatest(0, 20 - n_member);
  select count(*), min(d.created_at) into n_team, at_team from public.ai_drafts d
   where d.created_at > since and d.outcome <> 'failed';
  l_team := greatest(0, 60 - n_team);
  l_min := least(l_report, l_member, l_team);
  v_scope := case when l_min = l_report then case when is_adm then 'report' else 'redraft' end
                  when l_min = l_member then 'person' else 'team' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope,
    'limit', case v_scope when 'redraft' then 1 when 'report' then 5 when 'person' then 20 else 60 end,
    'report', l_report, 'person', l_member, 'team', l_team, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope = 'redraft' then null
                 when v_scope = 'report' then at_report + interval '24 hours'
                 when v_scope = 'person' then at_member + interval '24 hours'
                 else at_team + interval '24 hours' end);
end $$;

revoke all on function public.ai_draft_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_draft_left(uuid) from public, anon, authenticated;
grant execute on function public.ai_draft_claim(uuid) to authenticated;
grant execute on function public.ai_draft_left(uuid) to authenticated;

-- END OF DRAFT WITH AI BY SUBJECT --------------------------------------------
