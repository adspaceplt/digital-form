-- ===========================================================================
-- TERM TOTAL FROM ITS PARTS (2026-11-17)
-- ===========================================================================
-- WHY: tests/pricediff.js (2026-11-17), random quotations priced by
-- quote_totals: where a monthly line runs fewer months than the term, Total
-- for the term rounded the adjustment and SST in one step over the whole
-- span, so it could read a sen under First month incl. SST (3 x RM 399.59
-- for one month on a 6-month term at 15% and SST 6%: 1,461.30 against
-- 1,461.31).
--
-- WHAT IT CHANGES
--   * `quote_totals`: each span's adjustment is rounded to the sen, then SST
--     once a rate on the spans of that rate, as a month's incl. is worked.
--     `span_incl` and the commitment move by a sen at most, and only where a
--     monthly line runs months other than the term. Every other figure is
--     unchanged. A quotation already made keeps the totals it was made with.
--
-- ORDER: this file (connector), then the pages (the stand-in's copy). Safe
-- to run twice.
--
-- ROLLBACK: run quote_totals from QUOTATION PER-LINE TERMS again.
-- ===========================================================================

create or replace function public.quote_totals(p_lines jsonb, p_term int, p_pct numeric, p_sst numeric)
returns jsonb
language sql immutable set search_path = public as $$
  /* Each monthly line takes its own term percentage (`pct`, 2026-11-15),
     else the quotation's (`p_pct`): a quotation made before keeps its
     figures. Each percentage's adjustment is rounded once, and SST once a
     rate, on the subtotal and the adjustments of that rate. */
  with l as (
    select e->>'basis' = 'month' as m,
           coalesce((e->>'qty')::numeric, 0) * coalesce((e->>'rate')::numeric, 0) as v,
           greatest(1, coalesce((e->>'months')::int, p_term, 1)) as mo,
           coalesce((e->>'sst')::numeric, p_sst) as r,
           case when e->>'basis' = 'month' then coalesce((e->>'pct')::numeric, p_pct, 0) else 0 end as p
      from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
  ), gp as (
    -- a rate and a percentage's own subtotals
    select r, p,
           coalesce(sum(v) filter (where m), 0) as gsub,
           coalesce(sum(round(v, 2) * mo) filter (where m), 0) as gspan,
           coalesce(sum(v) filter (where not m), 0) as gonce,
           min(mo) filter (where m) as mmin, max(mo) filter (where m) as mmax
      from l group by r, p
  ), gq as (
    select r, p, gsub, gspan, gonce, mmin, mmax, round(gsub * p / 100, 2) as goff,
           round(gspan * (1 + p / 100), 2) as gse from gp
  ), gt as (
    select coalesce(sum(round(x.sub_r * x.r / 100, 2)), 0) as sst
      from (select r, sum(gsub + goff) as sub_r from gq group by r) x
  ), go as (
    select coalesce(sum(round(gonce * r / 100, 2)), 0) as osst
      from (select r, sum(gonce) as gonce from gq group by r) y
  ), gs as (
    -- the term's total is its parts added: each span's adjustment rounded,
    -- then SST once a rate, as a month's incl. is worked (2026-11-17)
    select coalesce(sum(gse), 0) + coalesce((select sum(round(z.se * z.r / 100, 2))
             from (select r, sum(gse) as se from gq group by r) z), 0) as span_incl,
           coalesce(sum(gse), 0) as span_excl,
           coalesce(sum(goff), 0) as off
      from gq
  ), tp as (
    -- the adjustment a percentage, for its own row where they differ
    select coalesce(jsonb_agg(jsonb_build_object('pct', p, 'amount', a,
             'months', case when lo = hi then lo end) order by p), '[]'::jsonb) as terms
      from (select p, sum(goff) as a, min(mmin) as lo, max(mmax) as hi
              from gq where gsub > 0 and p <> 0 group by p) z
  ), s as (
    select coalesce(sum(v) filter (where m), 0) as sub,
           coalesce(bool_and(mo = p_term) filter (where m), true) as even,
           coalesce(bool_or(m), false) as month,
           coalesce(sum(v) filter (where not m), 0) as once
      from l
  ), u as (
    select s.*, gt.sst, go.osst, gs.span_incl, gs.span_excl, gs.off, tp.terms
      from s, gt, go, gs, tp
  )
  select jsonb_build_object(
    'month', case when month then jsonb_build_object('subtotal', sub, 'term', off, 'excl', sub + off, 'sst', sst, 'incl', sub + off + sst) end,
    'once', case when once > 0 then jsonb_build_object('subtotal', once, 'sst', osst, 'incl', once + osst) end,
    'even', even, 'span_excl', case when month then span_excl else 0 end, 'span_incl', case when month then span_incl else 0 end,
    'term_rows', terms,
    'commitment', case when not month then 0 when even then (sub + off + sst) * p_term else span_incl end + once + osst)
  from u
$$;
revoke all on function public.quote_totals(jsonb, integer, numeric, numeric) from public, anon, authenticated;

-- END OF TERM TOTAL FROM ITS PARTS -------------------------------------------

select public.functions_tidy();
