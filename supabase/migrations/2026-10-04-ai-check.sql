-- ===========================================================================
-- AI CHECKS A REPORT AGAINST ITS FIGURES — on Check and submit, the
-- commentary as it stands (drafted or written by hand) is read against the
-- report's own figures, and what does not hold is listed for the team.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after DRAFT WITH AI RESETS AT MIDNIGHT.
--
-- WHAT CHANGED (the user, 2026-10-04: a check on the last step, reading the
-- draft as it stands, original or edited)
--   1. `ai_drafts.purpose` tells a draft from a check; `result` keeps a
--      check's findings and `basis` the commentary it read. A check that
--      came back is `drafted` (done), as a draft is.
--   2. `ai_check_claim(p_report)`: Reports Work, a report in draft or in
--      review the caller may see; it counts toward the colleague's day
--      (their own limit, else the standard) and never toward a report's
--      drafts.
--   3. `ai_check_done(p_id, p_ok, p_result, p_basis)`: the caller's own
--      pending check, written once.
--   4. `ai_check_last(p_report)`: Reports View on a report the caller may
--      see; the last check that came back, who ran it and when.
--   5. `ai_draft_same` counts drafts only.
--
-- ROLLBACK
--   Run the DRAFT WITH AI COUNTED BY SUBJECT section's ai_draft_same again;
--   then, in the SQL Editor, drop the three ai_check_ functions. The three
--   columns may stay.
-- ===========================================================================

alter table public.ai_drafts add column if not exists purpose text not null default 'draft'
  constraint ai_drafts_purpose check (purpose in ('draft', 'check'));
alter table public.ai_drafts add column if not exists result jsonb;
alter table public.ai_drafts add column if not exists basis jsonb;
create index if not exists ai_drafts_check_idx on public.ai_drafts (report_id, purpose, created_at);

create or replace function public.ai_draft_same(p_report uuid)
returns setof public.ai_drafts
language sql stable security definer set search_path = public as $$
  select d.* from public.ai_drafts d
   where d.outcome <> 'failed' and d.purpose = 'draft'
     and (d.report_id = p_report
          or exists (select 1 from public.sm_reports r
                      where r.id = p_report and d.client_id = r.client_id and d.kind = r.kind
                        and d.period_start <= r.period_end and d.period_end >= r.period_start))
$$;
revoke all on function public.ai_draft_same(uuid) from public, anon, authenticated;

create or replace function public.ai_check_claim(p_report uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  n_member integer;
  lim_member integer;
  new_id uuid;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null or not public.client_seen(r.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status not in ('draft', 'review') then return jsonb_build_object('error', 'not-open'); end if;
  -- One count at a time, with the drafts, so the last use is taken once.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim_member := public.ai_draft_limit(m.id::text, public.ai_draft_limit('person', 20));
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed';
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'person', 'limit', lim_member, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end, purpose)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end, 'check') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim_member - n_member - 1);
end $$;

create or replace function public.ai_check_done(p_id uuid, p_ok boolean, p_result jsonb, p_basis jsonb)
returns void
language sql security definer set search_path = public as $$
  update public.ai_drafts d
     set outcome = case when p_ok then 'drafted' else 'failed' end,
         result = case when p_ok then p_result end,
         basis = case when p_ok then p_basis end
   where d.id = p_id and d.purpose = 'check' and d.outcome = 'pending'
     and d.team_member_id = (public.ops_me()).id
$$;

create or replace function public.ai_check_last(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r public.sm_reports;
  c public.ai_drafts;
begin
  if not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null or not public.client_seen(r.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  select d.* into c from public.ai_drafts d
   where d.report_id = p_report and d.purpose = 'check' and d.outcome = 'drafted'
   order by d.created_at desc limit 1;
  if c.id is null then return jsonb_build_object('none', true); end if;
  return jsonb_build_object('at', c.created_at, 'result', c.result, 'basis', c.basis,
    'by', (select t.name from public.team_members t where t.id = c.team_member_id));
end $$;

revoke all on function public.ai_check_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_check_done(uuid, boolean, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.ai_check_last(uuid) from public, anon, authenticated;
grant execute on function public.ai_check_claim(uuid) to authenticated;
grant execute on function public.ai_check_done(uuid, boolean, jsonb, jsonb) to authenticated;
grant execute on function public.ai_check_last(uuid) to authenticated;

-- END OF AI CHECKS A REPORT AGAINST ITS FIGURES -----------------------------
