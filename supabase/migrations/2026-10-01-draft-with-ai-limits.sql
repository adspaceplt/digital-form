-- ===========================================================================
-- DRAFT WITH AI LIMITS — every press of Draft with AI is counted. A report
-- has one draft; drafting it again is an admin's (up to 5 a report in 24
-- hours). A colleague has 20 a day and the team 60, so a slip or a stuck
-- button cannot run up the AI bill. A draft that failed is not counted.
-- 2026-10-01. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `ai_drafts`: one row a press (the report, the colleague, when, and
--      pending, drafted or failed). Row level security on, no policy, every
--      grant revoked: only the two functions below read or write it.
--   2. `ai_draft_claim(p_report)`: Reports at Work. Counts under one lock
--      and answers `ai-limit` with the scope and when the next draft is
--      free: `redraft` where a colleague who is not an admin asks for a
--      report's second draft (no time: an admin redrafts it), `report` where
--      an admin passes 5 for the report in 24 hours, `person` past 20 and
--      `team` past 60 in 24 hours. Otherwise it records a pending press and
--      answers its id and how many the colleague has left today.
--   3. `ai_draft_done(p_id, p_ok)`: the `report-draft` function marks its
--      own press drafted or failed; only the colleague who pressed, only
--      while pending.
--
-- ROLLBACK
--   drop function if exists public.ai_draft_done(uuid, boolean);
--   drop function if exists public.ai_draft_claim(uuid);
--   drop table if exists public.ai_drafts;
-- ===========================================================================

create table if not exists public.ai_drafts (
  id             uuid primary key default gen_random_uuid(),
  report_id      uuid references public.sm_reports(id) on delete set null,
  team_member_id uuid references public.team_members(id) on delete set null,
  outcome        text not null default 'pending',
  created_at     timestamptz not null default now(),
  constraint ai_drafts_outcome check (outcome in ('pending', 'drafted', 'failed'))
);
create index if not exists ai_drafts_member_idx on public.ai_drafts (team_member_id, created_at);
create index if not exists ai_drafts_report_idx on public.ai_drafts (report_id, created_at);
create index if not exists ai_drafts_at_idx on public.ai_drafts (created_at);
alter table public.ai_drafts enable row level security;
revoke all on public.ai_drafts from public, anon, authenticated;

create or replace function public.ai_draft_claim(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
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
  -- One draft a report; a second and later is an admin's.
  if not coalesce(m.is_admin, false) and exists (
    select 1 from public.ai_drafts d where d.report_id = p_report and d.outcome <> 'failed') then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'redraft', 'limit', 1);
  end if;
  select count(*), min(d.created_at) into n_report, first_at from public.ai_drafts d
   where d.report_id = p_report and d.created_at > since and d.outcome <> 'failed';
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
  insert into public.ai_drafts (report_id, team_member_id) values (p_report, m.id) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', 20 - n_member - 1);
end $$;

create or replace function public.ai_draft_done(p_id uuid, p_ok boolean)
returns void
language sql security definer set search_path = public as $$
  update public.ai_drafts d
     set outcome = case when p_ok then 'drafted' else 'failed' end
   where d.id = p_id and d.outcome = 'pending'
     and d.team_member_id = (public.ops_me()).id
$$;

revoke all on function public.ai_draft_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_draft_done(uuid, boolean) from public, anon, authenticated;
grant execute on function public.ai_draft_claim(uuid) to authenticated;
grant execute on function public.ai_draft_done(uuid, boolean) to authenticated;

-- END OF DRAFT WITH AI LIMITS ------------------------------------------------
