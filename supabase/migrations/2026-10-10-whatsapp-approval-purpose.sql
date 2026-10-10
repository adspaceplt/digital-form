-- ===========================================================================
-- WHATSAPP APPROVAL PURPOSE — a fifth purpose a template is set for, the
-- approval reminder.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Run in the SQL Editor (it replaces a check, which the Supabase
-- connector stops on), before 2026-10-10-whatsapp-approval-reminder.sql.
--
-- WHAT CHANGED (the user, 2026-10-10: "yes" to the approval chaser)
--   1. `wa_templates.purpose` takes `approval` beside report, feedback,
--      reminder and creator, and its row is seeded switched off.
--
-- ROLLBACK
--   Pages first (Templates lists four purposes again), then delete the
--   `approval` row and put the check back without it.
-- ===========================================================================

alter table public.wa_templates drop constraint if exists wa_templates_purpose_check;
alter table public.wa_templates add constraint wa_templates_purpose_check
  check (purpose in ('report', 'feedback', 'reminder', 'creator', 'approval'));
insert into public.wa_templates (purpose) values ('approval') on conflict (purpose) do nothing;

-- END OF WHATSAPP APPROVAL PURPOSE --------------------------------------------
