-- ===========================================================================
-- PERIOD WORDS AS THE PAGE WRITES THEM — a report's period named the same
-- way by the database and the page.
-- 2026-10-13. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-13: Delete on a report of 16 September to
-- 10 October 2026 asked for "16 September to 10 October 2026" and refused
-- it typed back: "That does not match the period.")
--   `sm_period_word` named a period that is not a whole month as
--   "16 Sep 2026 to 10 Oct 2026", while the page (js/smreport.js
--   `periodWord`) shows and asks for "16 September to 10 October 2026", so
--   `sm_report_delete` refused every such report. It now writes the
--   page's words: a whole month "September 2026"; one month "1 to 15
--   September 2026"; one year "16 September to 10 October 2026"; across a
--   year "16 December 2025 to 10 January 2026". The Activity record's
--   report lines name the period the same way from now on.
--
-- ORDER
--   This file alone; no page change.
--
-- ROLLBACK
--   The definition in supabase/schema.sql's SOCIAL MEDIA REPORTS section
--   ("FMDD Mon YYYY" both sides), run on its own.
-- ===========================================================================

create or replace function public.sm_period_word(p_start date, p_end date)
returns text
language sql immutable set search_path = public as $$
  select case
    when p_start = date_trunc('month', p_start)::date
     and p_end = (date_trunc('month', p_start) + interval '1 month - 1 day')::date
      then trim(to_char(p_start, 'FMMonth YYYY'))
    when date_trunc('month', p_start) = date_trunc('month', p_end)
      then to_char(p_start, 'FMDD') || ' to ' || to_char(p_end, 'FMDD FMMonth YYYY')
    when extract(year from p_start) = extract(year from p_end)
      then to_char(p_start, 'FMDD FMMonth') || ' to ' || to_char(p_end, 'FMDD FMMonth YYYY')
    else to_char(p_start, 'FMDD FMMonth YYYY') || ' to ' || to_char(p_end, 'FMDD FMMonth YYYY')
  end
$$;

-- END OF PERIOD WORDS AS THE PAGE WRITES THEM ---------------------------------

select public.functions_tidy();
