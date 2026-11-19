-- ===========================================================================
-- INTERVIEW TIMES IN FULL (2026-11-19)
-- ===========================================================================
-- WHY: the user, 2026-11-19: an interview's time with its day ("also add
-- day, eg. Monday Tuesday"), and "put more attention to the smallest
-- tiniest details". The candidate's page, the emails and the team's
-- notices all read Saturday, 21 November 2026, 10:00am: one form for all
-- of them.
--
-- WHAT IT CHANGES
--   * `hiring_when(p_at)`: Malaysia's time in full, the weekday, the day,
--     the month's whole name and the year, then the time (Saturday, 21
--     November 2026, 10:00am). Read by `hiring_mail_prepare` (the
--     invitation's times, the confirmation's time) and the hiring record's
--     and the bell's lines.
--
-- ORDER: this file, any time; nothing else depends on the order. Safe to
-- run twice.
--
-- ROLLBACK: run `hiring_when` from HIRING: INTERVIEWS again.
-- ===========================================================================

/* A time in words, Malaysia's: Saturday, 21 November 2026, 10:00am. */
create or replace function public.hiring_when(p_at timestamptz)
returns text language sql stable set search_path = public as $$
  select to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'FMDay') || ', '
    || to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'FMDD FMMonth YYYY') || ', '
    || ltrim(lower(to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'HH12:MIam')), '0');
$$;
revoke all on function public.hiring_when(timestamptz) from public, anon, authenticated;

-- END OF INTERVIEW TIMES IN FULL ------------------------------------------------

select public.functions_tidy();
