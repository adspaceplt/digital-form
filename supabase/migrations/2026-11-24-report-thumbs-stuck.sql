-- ===========================================================================
-- REPORT PICTURES: A SNAPSHOT WITH NO CLIENT IS SET ASIDE (2026-11-24)
-- ===========================================================================
-- WHY: the review of 2026-11-24 (C3). `report-thumbs-move` rewrites a
-- published version's pictures under its client's folder; a version whose
-- report holds no client could never be moved, yet `sm_report_thumb_versions`
-- answered it on every call, so `left` never reached 0.
--
-- WHAT IT CHANGES
--   * `sm_report_thumb_versions(p_limit)` answers only versions whose report
--     holds a client, `left` counts those alone, and `stuck` counts the ones
--     set aside, for the team to look at by hand.
--
-- ORDER: this migration, then `report-thumbs-move` (which reads `stuck` and
-- counts a refusal by reason). The function from before reads `left` alone.
--
-- ROLLBACK: run `sm_report_thumb_versions` as REPORT PICTURES ON S3 stated
-- it (its previous definition in schema.sql).
-- ===========================================================================

create or replace function public.sm_report_thumb_versions(p_limit integer default 10)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ids', coalesce((select jsonb_agg(x.id) from (select v.id from public.sm_report_versions v
                       join public.sm_reports r on r.id = v.report_id
                       where strpos(v.snapshot::text, '"thumb_url": "data:image/') > 0 and r.client_id is not null
                       order by v.published_at limit greatest(1, least(coalesce(p_limit, 10), 50))) x), '[]'::jsonb),
    'left', (select count(*) from public.sm_report_versions v join public.sm_reports r on r.id = v.report_id
              where strpos(v.snapshot::text, '"thumb_url": "data:image/') > 0 and r.client_id is not null),
    'stuck', (select count(*) from public.sm_report_versions v left join public.sm_reports r on r.id = v.report_id
               where strpos(v.snapshot::text, '"thumb_url": "data:image/') > 0 and r.client_id is null))
$$;
revoke all on function public.sm_report_thumb_versions(integer) from public, anon, authenticated;

-- END OF REPORT PICTURES: A SNAPSHOT WITH NO CLIENT IS SET ASIDE ------------

select public.functions_tidy();
