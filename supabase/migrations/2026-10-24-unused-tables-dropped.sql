-- ===========================================================================
-- UNUSED TABLES DROPPED — five tables nothing reads or writes any more
-- (2026-10-24)
-- ===========================================================================
-- WHY (the cleanup audit of 2026-10-24, R5; the user: "Ok yes")
--   Five tables stood in the database with no page, function, view or
--   policy of another table reading them: `activity_viewers` (the old
--   Activity switch, replaced by the access map; one row), `ops_kpi_targets`
--   (never filled), `report_partners` and `report_partner_clients` (white
--   label moved onto the client, 2026-10-07; their functions dropped
--   2026-10-19) and `video_script_reviews` (the client's link decides
--   nothing since 2026-10-09; `script_decide` answers `closed`).
--   `sm_reports.partner_id` (set on no report) goes with `report_partners`.
--   `ops_engagement_events` is kept: it is a month's change history.
--
-- WHAT CHANGED
--   * `sm_report_brand` no longer clears `partner_id`.
--   * `sm_reports.partner_id` is dropped, then the five tables.
--
-- ORDER
--   This file in the SQL Editor (it holds drops the connector holds back).
--   No page reads any of them, so an open page meets nothing.
--
-- Safe to run twice. Rollback: run REPORT PARTNERS, WHITE LABEL ON THE
-- REPORT, the ACTIVITY VIEWERS, OPS KPI TARGETS and VIDEO SCRIPTS table
-- sections of schema.sql again (empty tables; the one activity_viewers row
-- is not restored), and WHITE LABEL BRANDS' sm_report_brand.
-- ===========================================================================

create or replace function public.sm_report_brand(p_id uuid, p_brand uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  b public.client_brands;
begin
  if me.id is null or not public.ops_granted('reports.whitelabel', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.status = 'published' then return jsonb_build_object('error', 'published'); end if;
  select * into c from public.clients where id = r.client_id;
  if p_brand is not null then
    select * into b from public.client_brands where id = p_brand;
    if b.id is null or b.client_id <> r.client_id or not b.active or not c.white_label or c.report_logo is null then
      return jsonb_build_object('error', 'bad-brand');
    end if;
  end if;
  if r.brand_id is not distinct from p_brand then return jsonb_build_object('ok', true); end if;
  if exists (select 1 from public.sm_reports x
              where x.client_id = r.client_id and x.kind = r.kind and x.id <> r.id
                and x.period_start = r.period_start and x.period_end = r.period_end
                and x.brand_id is not distinct from p_brand) then
    return jsonb_build_object('error', 'exists');
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  begin
    update public.sm_reports
       set brand_id = b.id, brand_name = b.name,
           label_client = case when b.id is not null then r.client_id end
     where id = p_id;
  exception when unique_violation then
    perform set_config('adspace.sm_fn', 'off', true);
    return jsonb_build_object('error', 'index-pending');
  end;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.saved',
    'White label: ' || coalesce(r.brand_name, 'not set') || ' → ' || coalesce(b.name, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.sm_report_brand(uuid, uuid) from public, anon;
grant execute on function public.sm_report_brand(uuid, uuid) to authenticated;

alter table public.sm_reports drop column if exists partner_id;
drop table if exists public.report_partner_clients;
drop table if exists public.report_partners;
drop table if exists public.video_script_reviews;
drop table if exists public.ops_kpi_targets;
drop table if exists public.activity_viewers;

-- END OF UNUSED TABLES DROPPED -----------------------------------------------

select public.functions_tidy();
