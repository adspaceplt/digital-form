-- 2026-11-17-ads-report-compares-with.sql
-- Safe to run twice. Rollback: run sm_report_create_for as the REPORTS ON
-- REQUEST section of supabase/schema.sql defines it.
-- AN ADVERTISING REPORT COMPARES WITH A PUBLISHED ONE -------------------------
-- 2026-11-17, the user: Huna's 16 Oct to 15 Nov Advertising Report could
-- take a report asked for in between as its previous period. A new
-- Advertising Report now compares with the latest published one of the
-- client (and brand) that was not asked for and ends before it starts, its
-- figures read from the version the client was shown, and keeps which
-- report they came from (`ads_totals.prev_from`); Step 1 lets the team pick
-- another published report or type the figures. Every refusal and the
-- Accounts Report's carry-forward are as before.
create or replace function public.sm_report_create_for(p_client uuid, p_start date, p_end date, p_kind text, p_brand uuid,
                                                       p_on_request boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  rid uuid;
  prev uuid;
  pr public.sm_reports;
  totals jsonb := '{}'::jsonb;
  pgroups jsonb;
  ptk jsonb;
  pa uuid;
  snap jsonb;
  pt jsonb;
  c public.clients;
  b public.client_brands;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.clients where id = p_client;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_start is null or p_end is null or p_end < p_start then return jsonb_build_object('error', 'bad-period'); end if;
  if coalesce(p_kind, '') not in ('social', 'ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_brand is not null then
    if not public.ops_granted('reports.whitelabel', 'work') then return jsonb_build_object('error', 'denied'); end if;
    select * into b from public.client_brands where id = p_brand;
    if b.id is null or b.client_id <> p_client or not b.active or not c.white_label or c.report_logo is null then
      return jsonb_build_object('error', 'bad-brand');
    end if;
  end if;
  select id into rid from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start = p_start and period_end = p_end
     and brand_id is not distinct from p_brand;
  if rid is not null then return jsonb_build_object('error', 'exists', 'id', rid); end if;
  /* The month's report carries on from the month's before it, never from
     one asked for; one asked for carries its accounts from the latest. */
  select id into prev from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start < p_start and brand_id is not distinct from p_brand
     and (coalesce(p_on_request, false) or not on_request)
   order by period_start desc limit 1;
  perform set_config('adspace.sm_fn', 'on', true);
  begin
    if p_kind = 'ads' then
      /* An Advertising Report asked for compares with the same length just
         before it, typed by the team. */
      /* It compares with the latest published Advertising Report that was
         not asked for and ends before this one starts, read from what the
         client was shown (its newest version not withdrawn); never a report
         asked for in between (2026-11-17, Huna). */
      if not coalesce(p_on_request, false) then
        select v.report_id, v.snapshot into pa, snap
          from public.sm_reports x
          join lateral (select vv.report_id, vv.snapshot from public.sm_report_versions vv
                         where vv.report_id = x.id and vv.withdrawn_at is null
                         order by vv.version_no desc limit 1) v on true
         where x.client_id = p_client and x.kind = 'ads' and x.period_end < p_start and not x.on_request
           and x.brand_id is not distinct from p_brand
         order by x.period_end desc, x.period_start desc limit 1;
      end if;
      if pa is not null then
        pt := coalesce(snap #> '{report,ads_totals}', '{}'::jsonb);
        select coalesce(jsonb_object_agg(g.objective, jsonb_build_object('results',
                 coalesce(nullif(pt #>> array['groups', g.objective, 'results'], '')::numeric, g.results),
                 'spend', g.spend)), '{}'::jsonb)
          into pgroups
          from (select e ->> 'objective' as objective,
                       sum(nullif(e ->> 'results', '')::numeric) as results, sum(nullif(e ->> 'spend', '')::numeric) as spend
                  from jsonb_array_elements(coalesce(snap -> 'ads', '[]'::jsonb)) e
                 where coalesce(e ->> 'platform', 'meta') = 'meta' group by 1) g;
        if exists (select 1 from jsonb_array_elements(coalesce(snap -> 'ads', '[]'::jsonb)) e where e ->> 'platform' = 'tiktok')
           or coalesce(pt #>> '{tiktok,reach}', pt #>> '{tiktok,impressions}', pt #>> '{tiktok,spend}') is not null then
          ptk := jsonb_strip_nulls(jsonb_build_object(
            'prev_reach', nullif(pt #>> '{tiktok,reach}', '')::numeric,
            'prev_impressions', coalesce(nullif(pt #>> '{tiktok,impressions}', '')::numeric,
              (select sum(nullif(e ->> 'impressions', '')::numeric) from jsonb_array_elements(snap -> 'ads') e where e ->> 'platform' = 'tiktok')),
            'prev_spend', coalesce(nullif(pt #>> '{tiktok,spend}', '')::numeric,
              (select sum(nullif(e ->> 'spend', '')::numeric) from jsonb_array_elements(snap -> 'ads') e where e ->> 'platform' = 'tiktok'))));
        end if;
        totals := jsonb_strip_nulls(jsonb_build_object(
          'prev_from', pa,
          'prev_start', snap #>> '{report,period_start}', 'prev_end', snap #>> '{report,period_end}',
          'prev_reach', nullif(pt ->> 'reach', '')::numeric,
          'prev_impressions', coalesce(nullif(pt ->> 'impressions', '')::numeric,
            (select sum(nullif(e ->> 'impressions', '')::numeric) from jsonb_array_elements(coalesce(snap -> 'ads', '[]'::jsonb)) e
              where coalesce(e ->> 'platform', 'meta') = 'meta')),
          'prev_spend', coalesce(nullif(pt ->> 'spend', '')::numeric,
            (select sum(nullif(e ->> 'spend', '')::numeric) from jsonb_array_elements(coalesce(snap -> 'ads', '[]'::jsonb)) e
              where coalesce(e ->> 'platform', 'meta') = 'meta')),
          'prev_groups', pgroups,
          'tiktok', ptk));
      else
        if date_trunc('month', p_start)::date = p_start and (p_start + interval '1 month' - interval '1 day')::date = p_end then
          totals := jsonb_build_object('prev_start', (p_start - interval '1 month')::date, 'prev_end', p_start - 1);
        else
          totals := jsonb_build_object('prev_start', p_start - (p_end - p_start + 1), 'prev_end', p_start - 1);
        end if;
      end if;
      insert into public.sm_reports (client_id, kind, title, period_start, period_end, created_by, first_month, ads_totals,
                                     brand_id, brand_name, label_client, on_request)
      values (p_client, p_kind, 'Social Media Advertising Report', p_start, p_end, me.id, false, totals,
              b.id, b.name, case when b.id is not null then p_client end, coalesce(p_on_request, false))
      returning id into rid;
    else
      insert into public.sm_reports (client_id, kind, period_start, period_end, created_by, brand_id, brand_name, label_client,
                                     on_request)
      values (p_client, p_kind, p_start, p_end, me.id, b.id, b.name, case when b.id is not null then p_client end,
              coalesce(p_on_request, false))
      returning id into rid;
      if prev is not null then
        insert into public.sm_report_platforms (report_id, platform, platform_name, account_name, handle, group_key, group_label,
          position, metrics, followers_start, er_basis, metric_notes)
        select rid, p.platform, p.platform_name, p.account_name, p.handle, p.group_key, p.group_label, p.position, p.metrics,
               coalesce(p.followers_end, case when p.followers_start is not null and p.growth_override is not null
                                              then p.followers_start + p.growth_override end),
               p.er_basis, p.metric_notes
          from public.sm_report_platforms p where p.report_id = prev;
      end if;
    end if;
  exception when unique_violation then
    perform set_config('adspace.sm_fn', 'off', true);
    return jsonb_build_object('error', 'index-pending');
  end;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(rid, 'report.created', nullif(concat_ws(' · ',
    case when b.id is not null then 'White label: ' || b.name end,
    case when p_on_request then 'On request' end), ''));
  return jsonb_build_object('ok', true, 'id', rid, 'carried', prev is not null);
end $$;
revoke all on function public.sm_report_create_for(uuid, date, date, text, uuid, boolean) from public, anon;
grant execute on function public.sm_report_create_for(uuid, date, date, text, uuid, boolean) to authenticated;

-- END OF AN ADVERTISING REPORT COMPARES WITH A PUBLISHED ONE ------------------

select public.functions_tidy();
