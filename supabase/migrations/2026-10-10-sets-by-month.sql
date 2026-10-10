-- ===========================================================================
-- SETS BY MONTH — a content set names its content month (2026-10-10, the
-- user: a client's sets grow without end; they are listed by month, as
-- Video Scripts and Reports are).
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   `batches.period` (YYYY-MM, the content month; empty is Ad hoc). It is
--   added once and, that first time only, each set takes the month it was
--   made in (Malaysia time), so a second run never undoes a set the team
--   has since made Ad hoc. A new set takes this month on the page; the set's
--   menu changes it (`set.month`, from and to).
--
-- ROLLBACK
--   Remove the constraint batches_period_shape and the column period.
-- ===========================================================================

do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'batches' and column_name = 'period') then
    alter table public.batches add column period text;
    update public.batches set period = to_char(created_at at time zone 'Asia/Kuala_Lumpur', 'YYYY-MM');
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'batches_period_shape') then
    alter table public.batches add constraint batches_period_shape
      check (period is null or period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$');
  end if;
end $$;

-- END OF SETS BY MONTH ---------------------------------------------------------
