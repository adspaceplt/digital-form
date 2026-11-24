-- ===========================================================================
-- OUTSTATION TRIP NUMBER #OS (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24: "the outstation #OS follow the similar serial
-- [as #WT] just that it follows the YYMMNN (not YYYY)". `OS/20261101` read
-- unlike every other number the team reads.
--
-- WHAT IT CHANGES
--   * `outstation_ref_take` gives `#OS{YYMM}{NN}` (`#OS261101`): the month
--     of check-in in Malaysia and its count from 01, two digits, more past
--     99. The months' counts (`outstation_ref_months`, keyed YYYYMM) stand.
--   * The trips standing are renamed `OS/YYYYMMNN` to `#OSYYMMNN`, the same
--     count, with the number guard (`outstation_trips_ref`) set aside for
--     that one update. A delete asked with the old number still matches
--     nothing; it is typed as the page now draws it.
--
-- ORDER: this file, then the pages (the page draws whatever number it is
-- given). Safe to run twice.
-- ROLLBACK: run OUTSTATION TRIP NUMBER AND DELETE's `outstation_ref_take`
-- again, and rename `#OSYYMMNN` back to `OS/20YYMMNN` the same way.
-- ===========================================================================

create or replace function public.outstation_ref_take(p_at timestamptz)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_m text := to_char(coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur', 'YYYYMM'); v_n integer;
begin
  insert into public.outstation_ref_months (month, last) values (v_m, 1)
  on conflict (month) do update set last = public.outstation_ref_months.last + 1
  returning last into v_n;
  return '#OS' || substr(v_m, 3) || lpad(v_n::text, greatest(2, length(v_n::text)), '0');
end $$;
revoke all on function public.outstation_ref_take(timestamptz) from public, anon, authenticated;

alter table public.outstation_trips disable trigger outstation_trips_ref;
update public.outstation_trips set ref = '#OS' || substr(ref, 6) where ref like 'OS/%';
alter table public.outstation_trips enable trigger outstation_trips_ref;

-- END OF OUTSTATION TRIP NUMBER #OS -----------------------------------------

select public.functions_tidy();
