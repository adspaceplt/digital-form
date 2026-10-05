-- ===========================================================================
-- ADS ON TWO PLATFORMS — one advertising report holds Meta's ads and
-- TikTok's, each ad naming its platform.
-- 2026-10-05. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-05: "one report for both platforms")
--   1. `sm_report_ads.platform`: 'meta' (every row before today) or
--      'tiktok', checked.
--   2. `sm_reports.ads_totals` keeps Meta's figures where they always were;
--      TikTok's sit under its `tiktok` key (reach, impressions, spend and the
--      previous period's), since reach is never added across platforms.
--   3. `sm_report_create` carries the earlier report's figures forward per
--      platform: Meta's from Meta's ads and figures, TikTok's under
--      `tiktok` only where the earlier report had TikTok. Otherwise
--      unchanged.
--
-- ROLLBACK
--   Run the FIRST MONTH OF ADS UNTICKED section's sm_report_create again, then
--   alter table public.sm_report_ads drop constraint if exists sm_report_ads_platform_chk;
--   alter table public.sm_report_ads drop column if exists platform;
-- ===========================================================================

alter table public.sm_report_ads add column if not exists platform text not null default 'meta';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'sm_report_ads_platform_chk') then
    alter table public.sm_report_ads add constraint sm_report_ads_platform_chk check (platform in ('meta', 'tiktok'));
  end if;
end $$;

create or replace function public.sm_report_create(p_client uuid, p_start date, p_end date, p_kind text default 'social')
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
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_client is null or not exists (select 1 from public.clients where id = p_client) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if p_start is null or p_end is null or p_end < p_start then return jsonb_build_object('error', 'bad-period'); end if;
  if coalesce(p_kind, '') not in ('social', 'ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select id into rid from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start = p_start and period_end = p_end;
  if rid is not null then return jsonb_build_object('error', 'exists', 'id', rid); end if;
  select id into prev from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start < p_start
   order by period_start desc limit 1;
  perform set_config('adspace.sm_fn', 'on', true);
  if p_kind = 'ads' then
    if prev is not null then
      select * into pr from public.sm_reports where id = prev;
      select coalesce(jsonb_object_agg(g.objective, jsonb_build_object('results',
               coalesce(nullif(pr.ads_totals #>> array['groups', g.objective, 'results'], '')::numeric, g.results),
               'spend', g.spend)), '{}'::jsonb)
        into pgroups
        from (select a.objective, sum(a.results) as results, sum(a.spend) as spend
                from public.sm_report_ads a where a.report_id = prev and a.platform = 'meta' group by a.objective) g;
      -- TikTok's figures carry forward under their own key, only where the
      -- earlier report had TikTok ads or TikTok figures of its own.
      if exists (select 1 from public.sm_report_ads where report_id = prev and platform = 'tiktok')
         or coalesce(pr.ads_totals #>> '{tiktok,reach}', pr.ads_totals #>> '{tiktok,impressions}',
                     pr.ads_totals #>> '{tiktok,spend}') is not null then
        ptk := jsonb_strip_nulls(jsonb_build_object(
          'prev_reach', nullif(pr.ads_totals #>> '{tiktok,reach}', '')::numeric,
          'prev_impressions', coalesce(nullif(pr.ads_totals #>> '{tiktok,impressions}', '')::numeric,
                                       (select sum(impressions) from public.sm_report_ads where report_id = prev and platform = 'tiktok')),
          'prev_spend', coalesce(nullif(pr.ads_totals #>> '{tiktok,spend}', '')::numeric,
                                 (select sum(spend) from public.sm_report_ads where report_id = prev and platform = 'tiktok'))));
      end if;
      totals := jsonb_strip_nulls(jsonb_build_object(
        'prev_start', pr.period_start, 'prev_end', pr.period_end,
        'prev_reach', nullif(pr.ads_totals ->> 'reach', '')::numeric,
        'prev_impressions', coalesce(nullif(pr.ads_totals ->> 'impressions', '')::numeric,
                                     (select sum(impressions) from public.sm_report_ads where report_id = prev and platform = 'meta')),
        'prev_spend', coalesce(nullif(pr.ads_totals ->> 'spend', '')::numeric,
                               (select sum(spend) from public.sm_report_ads where report_id = prev and platform = 'meta')),
        'prev_groups', pgroups,
        'tiktok', ptk));
    else
      -- No earlier report here: most clients advertised before the portal, so
      -- the period before is prefilled for the team to type its figures.
      if date_trunc('month', p_start)::date = p_start and (p_start + interval '1 month' - interval '1 day')::date = p_end then
        totals := jsonb_build_object('prev_start', (p_start - interval '1 month')::date, 'prev_end', p_start - 1);
      else
        totals := jsonb_build_object('prev_start', p_start - (p_end - p_start + 1), 'prev_end', p_start - 1);
      end if;
    end if;
    insert into public.sm_reports (client_id, kind, title, period_start, period_end, created_by, first_month, ads_totals)
    values (p_client, p_kind, 'Social Media Advertising Report', p_start, p_end, me.id, false, totals)
    returning id into rid;
  else
    insert into public.sm_reports (client_id, kind, period_start, period_end, created_by)
    values (p_client, p_kind, p_start, p_end, me.id) returning id into rid;
    if prev is not null then
      insert into public.sm_report_platforms (report_id, platform, account_name, handle, group_key, group_label,
        position, metrics, followers_start, er_basis, metric_notes)
      select rid, p.platform, p.account_name, p.handle, p.group_key, p.group_label, p.position, p.metrics,
             coalesce(p.followers_end, case when p.followers_start is not null and p.growth_override is not null
                                            then p.followers_start + p.growth_override end),
             p.er_basis, p.metric_notes
        from public.sm_report_platforms p where p.report_id = prev;
    end if;
  end if;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(rid, 'report.created');
  return jsonb_build_object('ok', true, 'id', rid, 'carried', prev is not null);
end $$;
grant execute on function public.sm_report_create(uuid, date, date, text) to authenticated;

-- END OF ADS ON TWO PLATFORMS ------------------------------------------------
