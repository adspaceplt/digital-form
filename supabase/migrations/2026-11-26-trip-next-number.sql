-- ===========================================================================
-- TRIP NEXT NUMBER IN SETTINGS (2026-11-26)
-- ===========================================================================
-- WHY: Settings' Outstation trip numbers read Next #OS261101 after
-- #OS261101 was taken (F2 of the handover of 2026-11-26):
-- the page drew the month's first number, since the month's count
-- (`outstation_ref_months.last`) is closed to the team and
-- `id_formats_list()` answered the trip row's unused `next_no`.
--
-- WHAT IT CHANGES
--   * `id_formats_list()`: the trip row's `next` is this Malaysian month's
--     count plus one (1 while no trip is numbered this month), the number
--     `outstation_ref_take` will give next. Every other row and refusal
--     stands; `id_format_set` still keeps no next number for a trip.
--
-- ORDER: this file, then the page (an open tab reads `next` from the old
-- function as 1, the line it drew before). Safe to run twice. Holds no
-- drop or delete.
-- ROLLBACK: run OUTSTATION TRIP NUMBERS IN SETTINGS' `id_formats_list()`
-- again (`next` as `f.next_no`).
-- ===========================================================================

-- TRIP NEXT NUMBER IN SETTINGS ----------------------------------------------

create or replace function public.id_formats_list()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.is_team() then coalesce(jsonb_agg(jsonb_build_object(
           'kind', f.kind, 'prefix', f.prefix, 'width', f.width,
           'next', case when f.kind = 'trip'
                        then coalesce((select m.last from public.outstation_ref_months m
                                        where m.month = to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMM')), 0) + 1
                        else f.next_no end,
           'pattern', f.pattern)
           order by array_position(array['creator', 'campaign', 'job', 'trip'], f.kind)), '[]'::jsonb)
         else '[]'::jsonb end
    from public.id_formats f
$$;
revoke all on function public.id_formats_list() from public, anon;
grant execute on function public.id_formats_list() to authenticated;

-- END OF TRIP NEXT NUMBER IN SETTINGS ---------------------------------------
