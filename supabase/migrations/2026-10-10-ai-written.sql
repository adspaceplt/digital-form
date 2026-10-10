-- ===========================================================================
-- AI WRITTEN — whether Write with AI drafted a report's commentary, so its
-- Submit asks the colleague to declare it read and checked.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after DRAFT WITH AI LIMITS and SCRIPT WRITER.
--
-- WHAT CHANGED (the user, 2026-10-10: "a warning dialog for all AI assisted
-- write out … if they proceed to submit or confirm, they declare that the
-- contents are read and confirmed")
--   1. `ai_written(p_report)` (Reports View) answers whether a draft written
--      with AI was saved to the report. The page asks the declaration in
--      Submit's own question and files it with the report; a caption or a
--      script asks it before its own Save.
--
-- ROLLBACK
--   Nothing calls it but the page; it may stay.
-- ===========================================================================

create or replace function public.ai_written(p_report uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.allowed('reports', 'view') and exists (
    select 1 from public.ai_drafts d
     where d.report_id = p_report and d.purpose = 'draft' and d.outcome = 'drafted')
$$;
grant execute on function public.ai_written(uuid) to authenticated;

-- END OF AI WRITTEN -----------------------------------------------------------

select public.functions_tidy();
