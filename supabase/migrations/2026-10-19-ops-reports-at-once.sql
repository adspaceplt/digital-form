-- ===========================================================================
-- OPS REPORTS AT ONCE — the Dashboard's work figures in one request.
-- 2026-10-19. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/ops.js compares
-- the two.
--
-- WHAT CHANGED (the third audit, item 19)
--   The Dashboard asked ops_report eight times a visit: the period, the
--   period before it, and each of the last six months for the on-time line
--   and the deliveries. ops_reports(p_ranges) takes the spans as a list
--   (`[{ "from": …, "to": … }, …]`, twelve at most) and answers ops_report's
--   own answer for each, in order, so every figure is the one ops_report
--   gives and the page makes one request. It runs as the caller, so
--   ops_report's own check (My Work: Reports, `denied`) answers as before.
--
-- ROLLBACK
--   drop function if exists public.ops_reports(jsonb);
--   (pages served before this ask ops_report a span at a time)
-- ===========================================================================

create or replace function public.ops_reports(p_ranges jsonb)
returns jsonb
language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(public.ops_report((x.r ->> 'from')::timestamptz, (x.r ->> 'to')::timestamptz) order by x.n), '[]'::jsonb)
    from jsonb_array_elements(case when jsonb_typeof(p_ranges) = 'array' then p_ranges else '[]'::jsonb end)
         with ordinality x(r, n)
   where x.n <= 12
$$;

revoke all on function public.ops_reports(jsonb) from public, anon;
grant execute on function public.ops_reports(jsonb) to authenticated;

-- END OF OPS REPORTS AT ONCE -------------------------------------------------

select public.functions_tidy();
