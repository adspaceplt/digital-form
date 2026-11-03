-- ===========================================================================
-- A report's record of changes (2026-11-03)
-- ===========================================================================
-- WHY: the user, of a report's Key dates: "can the key dates be like activity
-- log who did it what they did when and optional why … full set". A line of
-- the Activity record named its client and period alone, so two reports of
-- one period could not be told apart.
--
-- WHAT IT CHANGES
--   `activity_log.ref`: the record a line is about (a report's id), indexed.
--   `sm_report_log`: as before, filing the report's id with the line.
--   `sm_report_history(p_id)`: the report's lines, newest first (500 at
--   most), at Reports View on a client in scope.
--   Lines filed before take their report where only one report of the
--   client holds the period they name (577 of 1,073 on 2026-11-03; 225 sat
--   on two reports of one period and are left as they were).
--
-- ORDER: this file, then the pages (the page asks sm_report_history and
-- files `ref`; before this file it draws the key steps alone). Safe to run
-- twice.
-- ROLLBACK
--   drop function if exists public.sm_report_history(uuid);
--   restate sm_report_log without ref (2026-10-01-activity-reports-tab.sql);
--   alter table public.activity_log drop column if exists ref;
-- ===========================================================================

-- REPORT RECORD -------------------------------------------------------------

alter table public.activity_log add column if not exists ref uuid;
create index if not exists activity_log_ref_idx on public.activity_log (ref) where ref is not null;

create or replace function public.sm_report_log(p_id uuid, p_action text, p_extra text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.sm_reports;
  who text;
  cname text;
begin
  select * into r from public.sm_reports where id = p_id;
  select c.name into cname from public.clients c where c.id = r.client_id;
  who := coalesce((public.ops_me()).name, auth.jwt() ->> 'email');
  insert into public.activity_log (actor, action, subject, detail, ref)
  values (who, p_action, cname,
          public.sm_period_word(r.period_start, r.period_end) || ' · v' || r.version_no
          || coalesce(' · ' || nullif(btrim(p_extra), ''), ''), p_id);
end $$;
revoke all on function public.sm_report_log(uuid, text, text) from public, anon, authenticated;

/* A report's own record: every line filed against it, newest first, read
   by anyone at Reports View on a client they see, whatever their Activity
   record access (the record is the report's, not the section's). */
create or replace function public.sm_report_history(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  rep public.sm_reports;
  cl public.clients;
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into rep from public.sm_reports where id = p_id;
  if rep.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into cl from public.clients where id = rep.client_id;
  if not public.client_row_seen_by(cl.stage, cl.owner, cl.sales_by, 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object('actor', a.actor, 'action', a.action, 'subject', a.subject,
             'detail', a.detail, 'created_at', a.created_at) order by a.created_at desc)
      from (select * from public.activity_log x where x.ref = p_id order by x.created_at desc limit 500) a
  ), '[]'::jsonb));
end $$;
revoke all on function public.sm_report_history(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_history(uuid) to authenticated;

/* Lines filed before they named their report take it where only one
   report of that client holds the period they name; two reports of one
   period (an Accounts and an Advertising Report) are left as they were. */
with m as (
  select a.id as aid, (array_agg(rep.id))[1] as rid, count(*) as n
    from public.activity_log a
    join public.clients cl on cl.name = a.subject
    join public.sm_reports rep on rep.client_id = cl.id
     and a.detail like public.sm_period_word(rep.period_start, rep.period_end) || ' · v%'
     and a.created_at >= rep.created_at - interval '1 minute'
   where a.action like 'report.%' and a.ref is null
   group by a.id
)
update public.activity_log a set ref = m.rid from m where m.aid = a.id and m.n = 1;

-- END OF REPORT RECORD ------------------------------------------------------

select public.functions_tidy();
