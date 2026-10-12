-- 2026-10-12 · The Report audit counts nothing while the period runs.
-- Safe to run twice. Rollback is in the band's head.

-- AUDIT WHILE THE PERIOD RUNS — Meta's figures keep moving until a report's
-- period has ended (the user, 2026-10-12: the audit of a report whose period
-- ended that day read 101 differences, nearly all ads still spending since
-- the export), so nothing is counted against them until the day after its
-- last day (Malaysia time).
--   1. `sm_report_running(p_id)`: whether the report's period has not yet
--      ended, today in Malaysia time on or before its last day.
--   2. `sm_report_audit_blocks(p_id, p_after)`: while the period runs,
--      Submit is not held by Meta (p_after null); Publish of an Advertising
--      Report, read again since confirmation, is refused `period-running`
--      until the day after the period's last day.
--   3. `sm_report_audit_last(p_id)` adds `running` and `counts_from` (the
--      first day the audit counts), so the card says so.
-- Rollback: run sm_report_audit_blocks and sm_report_audit_last as the
-- REPORT AUDIT section defines them, then
--   drop function if exists public.sm_report_running(uuid);
create or replace function public.sm_report_running(p_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select r.period_end >= (now() at time zone 'Asia/Kuala_Lumpur')::date
                     from public.sm_reports r where r.id = p_id), false)
$$;
revoke all on function public.sm_report_running(uuid) from public, anon, authenticated;

create or replace function public.sm_report_audit_blocks(p_id uuid, p_after timestamptz default null)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  r public.sm_reports;
  a public.sm_report_audits;
begin
  select * into r from public.sm_reports where id = p_id;
  if r.id is null or not public.sm_report_audit_needed(p_id) then return null; end if;
  if public.sm_report_running(p_id) then
    return case when p_after is null then null else 'period-running' end;
  end if;
  select * into a from public.sm_report_audits x
   where x.report_id = p_id and x.version_no = r.version_no
   order by x.read_at desc, x.id desc limit 1;
  if a.id is null or a.read_at < coalesce(p_after, '-infinity'::timestamptz) then return 'meta-audit'; end if;
  if a.outcome not in ('match', 'override') then return 'meta-audit'; end if;
  if a.print is distinct from public.sm_report_meta_print(p_id) then return 'meta-audit'; end if;
  return null;
end $$;
revoke all on function public.sm_report_audit_blocks(uuid, timestamptz) from public, anon, authenticated;

create or replace function public.sm_report_audit_last(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  a public.sm_report_audits;
  v_print text;
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen(c.stage, c.owner, 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_print := public.sm_report_meta_print(p_id);
  select * into a from public.sm_report_audits x
   where x.report_id = p_id and x.version_no = r.version_no
   order by x.read_at desc, x.id desc limit 1;
  return jsonb_build_object(
    'needed', public.sm_report_audit_needed(p_id),
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin',
    'blocks', public.sm_report_audit_blocks(p_id, null),
    'running', public.sm_report_running(p_id),
    'counts_from', r.period_end + 1,
    'held', exists (select 1 from public.sm_report_audits x where x.report_id = p_id and x.version_no = r.version_no),
    'print_since', (select min(x.read_at) from public.sm_report_audits x
                     where x.report_id = p_id and x.version_no = r.version_no and x.print = v_print),
    'print_moved', exists (select 1 from public.sm_report_audits x
                            where x.report_id = p_id and x.version_no = r.version_no and x.print is distinct from v_print),
    'last', case when a.id is null then null else jsonb_build_object(
      'at', a.read_at, 'by', a.by_name, 'outcome', a.outcome, 'rows', a.diffs, 'note', a.note,
      'current', a.print is not distinct from v_print) end);
end $$;
revoke all on function public.sm_report_audit_last(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_audit_last(uuid) to authenticated;
-- END OF AUDIT WHILE THE PERIOD RUNS ----------------------------------------

select public.functions_tidy();
