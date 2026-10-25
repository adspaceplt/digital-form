-- ===========================================================================
-- PURCHASE VALUE AND ROAS — an ad's purchase value, as Meta reports it, so
-- an Advertising Report reads its Sales ads' return on ad spend. 2026-10-25.
-- Safe to run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/smsql.js compares the two.
--
-- WHY (the user, 2026-10-25, of Roro's September report: "does it show and
-- include the roas data and commentary?"): a Sales ad held its purchases and
-- its cost per purchase, never what the purchases were worth, so no return
-- could be read.
--
-- WHAT CHANGED
--   1. `sm_report_ads.purchase_value`: the value of the purchases Meta
--      attributes to the ad over the period, in the account's currency; 0 or
--      more, empty where not given. Written by the page on a draft, as every
--      other figure of the row (the draft guard and the policies hold it).
--      ROAS is worked out from it (purchase value over amount spent), never
--      stored. The snapshot carries it, so a published version prints as it
--      was published; one published before holds none and prints none.
--   2. `sm_report_meta_print` takes it into the figures' print where a row
--      holds one, so a value changed after a match holds the report again,
--      and a report holding none keeps the print it had (no match undone).
--
-- ROLLBACK
--   alter table public.sm_report_ads drop constraint if exists sm_report_ads_purchase_value_chk;
--   alter table public.sm_report_ads drop column if exists purchase_value;
--   then run sm_report_meta_print from REPORT AUDIT again.
-- ===========================================================================

alter table public.sm_report_ads add column if not exists purchase_value numeric(14,2);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sm_report_ads_purchase_value_chk') then
    alter table public.sm_report_ads add constraint sm_report_ads_purchase_value_chk
      check (purchase_value is null or purchase_value >= 0);
  end if;
end $$;

create or replace function public.sm_report_meta_print(p_id uuid)
returns text
language sql stable security definer set search_path = public as $$
  select md5(case when r.kind = 'ads' then
      coalesce((select string_agg((jsonb_build_array(a.id, a.result_label, a.results, a.reach, a.impressions, a.spend,
                  a.ctr, a.cpr, a.hook_rate, a.hold_rate, a.avg_play, a.retention, a.age, a.ad_ids)
                  || case when a.purchase_value is null then '[]'::jsonb else jsonb_build_array(a.purchase_value) end)::text,
                  ';' order by a.id)
                  from public.sm_report_ads a
                 where a.report_id = r.id and coalesce(a.platform, 'meta') = 'meta'), '')
      || '#' || jsonb_build_object('reach', r.ads_totals -> 'reach', 'impressions', r.ads_totals -> 'impressions',
                                   'spend', r.ads_totals -> 'spend')::text
    else
      coalesce((select string_agg(jsonb_build_array(p.id, p.url, p.views, p.reach, p.impressions, p.interactions,
                  p.engagements, p.likes, p.comments, p.shares, p.saves)::text, ';' order by p.id)
                  from public.sm_report_posts p
                  join public.sm_report_platforms f on f.id = p.platform_id
                 where p.report_id = r.id and f.platform in ('facebook', 'instagram')), '')
    end)
  from public.sm_reports r where r.id = p_id
$$;
revoke all on function public.sm_report_meta_print(uuid) from public, anon, authenticated;

-- END OF PURCHASE VALUE AND ROAS ---------------------------------------------

select public.functions_tidy();
