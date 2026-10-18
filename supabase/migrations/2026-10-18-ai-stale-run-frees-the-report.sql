-- ===========================================================================
-- AI STALE RUN FREES THE REPORT — a run left `pending` by an edge function
-- stopped mid-run no longer holds the report until the next day.
-- 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the review of #538 to #550, item 4)
--   A press claims an `ai_drafts` row as `pending` before Claude is asked,
--   and the edge function files its outcome after. A function stopped
--   mid-run (a deploy, the platform's limit, a crash) leaves the row
--   `pending` for good, and the per-report same-day checks (`ai_draft_same`
--   for drafts, the report count in `ai_check_claim` / `ai_check_left` for
--   commentary checks) counted it: the colleague's one draft or check on
--   that report was spent until midnight, Try again refused. Those three
--   now leave out a row still `pending` ten minutes after it was claimed
--   (no run lasts three: report-draft's longest is under 150 seconds). A
--   run in flight keeps holding the report, so a second press is still
--   refused. The colleague's daily total (`person`, `admin`) is unchanged:
--   it still counts the stale row, as every run that reached the model.
--
-- ROLLBACK
--   Run the AI RETRY ON THE SAME REPORT section again
--   (supabase/migrations/2026-10-17-ai-retry-on-the-same-report.sql).
-- ===========================================================================

create or replace function public.ai_draft_same(p_report uuid)
returns setof public.ai_drafts
language sql stable security definer set search_path = public as $$
  select d.* from public.ai_drafts d
   /* A run that reached the model and ended with no answer (`incomplete`)
      counts against the day, never against the report: "Try again" is
      offered after it, and was refused (2026-10-17, the review's finding 5).
      Nor does a run still `pending` ten minutes on: its edge function was
      stopped before it filed an outcome (no run lasts three), and it held
      the report until the next day (2026-10-18). */
   where d.outcome not in ('failed', 'incomplete') and d.purpose = 'draft'
     and not (d.outcome = 'pending' and d.created_at < now() - interval '10 minutes')
     and (d.report_id = p_report
          or exists (select 1 from public.sm_reports r
                      where r.id = p_report and d.client_id = r.client_id and d.kind = r.kind
                        and d.brand_id is not distinct from r.brand_id
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
  lim_check integer;
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
  lim_member := public.ai_day_cap(m);
  if lim_member = 0 then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0);
  end if;
  lim_check := case when coalesce(m.is_admin, false) then public.ai_draft_limit('check_admin', 5)
                    else public.ai_draft_limit('check', 1) end;
  if (select count(*) from public.ai_drafts d
       where d.report_id = p_report and d.purpose = 'check' and d.outcome not in ('failed', 'incomplete')
         and not (d.outcome = 'pending' and d.created_at < now() - interval '10 minutes')
         and d.team_member_id = m.id and d.created_at >= since) >= lim_check then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'report_check', 'limit', lim_check, 'next', since + interval '1 day');
  end if;
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose in ('draft', 'check');
  if n_member >= lim_member then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'person', 'limit', lim_member, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (report_id, team_member_id, client_id, kind, period_start, period_end, purpose, version_no)
  values (p_report, m.id, r.client_id, r.kind, r.period_start, r.period_end, 'check', r.version_no) returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim_member - n_member - 1);
end $$;

create or replace function public.ai_check_left(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  r public.sm_reports;
  since timestamptz := public.ai_draft_day();
  is_adm boolean;
  n_member integer;
  l_report integer; l_member integer; l_min integer;
  lim_member integer;
  lim_check integer;
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_report;
  if r.id is null or not public.client_seen(r.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  is_adm := coalesce(m.is_admin, false);
  lim_member := public.ai_day_cap(m);
  lim_check := case when is_adm then public.ai_draft_limit('check_admin', 5) else public.ai_draft_limit('check', 1) end;
  l_report := greatest(0, lim_check - (select count(*) from public.ai_drafts d
    where d.report_id = p_report and d.purpose = 'check' and d.outcome not in ('failed', 'incomplete')
      and not (d.outcome = 'pending' and d.created_at < now() - interval '10 minutes')
      and d.team_member_id = m.id and d.created_at >= since)::integer);
  select count(*) into n_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at >= since and d.outcome <> 'failed' and d.purpose in ('draft', 'check');
  l_member := greatest(0, lim_member - n_member);
  l_min := least(l_report, l_member);
  v_scope := case when lim_member = 0 then 'stopped' when l_min = l_report then 'report_check' else 'person' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope, 'version', r.version_no,
    'limit', case v_scope when 'stopped' then 0 when 'report_check' then lim_check else lim_member end,
    'report', l_report, 'person', l_member, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope = 'stopped' then null else since + interval '1 day' end);
end $$;

revoke all on function public.ai_check_claim(uuid) from public, anon, authenticated;
revoke all on function public.ai_check_left(uuid) from public, anon, authenticated;
grant execute on function public.ai_check_claim(uuid) to authenticated;
grant execute on function public.ai_check_left(uuid) to authenticated;

-- END OF AI STALE RUN FREES THE REPORT ---------------------------------------

select public.functions_tidy();
