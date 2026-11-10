-- ===========================================================================
-- TASK DATES IN THE PAST — a new task's dates may go back up to a set number
-- of days (2026-11-10; the user's team: "allow at least past 30 days")
-- ===========================================================================
-- * `task_past_days` (30), a Business setting from a day on (Settings, My
--   Work: Due dates): how far back the New task sheet takes a Draft due, Due
--   date or Post date; 0 takes none in the past. Read by the page alone: the
--   database never refused a past date. Seeded once. Safe to run twice.
-- ROLLBACK: delete from public.app_settings where key = 'task_past_days';
--   (the page then reads 30, its default).
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select 'task_past_days', date '2023-08-14', 30
 where not exists (select 1 from public.app_settings s where s.key = 'task_past_days');

-- END OF TASK DATES IN THE PAST ----------------------------------------------

select public.functions_tidy();
