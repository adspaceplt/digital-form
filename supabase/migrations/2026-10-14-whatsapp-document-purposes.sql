-- ===========================================================================
-- WHATSAPP DOCUMENT PURPOSES — two more purposes a template is set for: a
-- quotation and a Letter of Offer sent to the client.
-- 2026-10-14. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Run in the SQL Editor (it replaces a check, which the Supabase
-- connector stops on), before 2026-10-14-whatsapp-documents.sql.
--
-- WHAT CHANGED (the user, 2026-10-14: "whatsapp template for sending
-- quotation / letter of offer once decided to proceed")
--   1. `wa_templates.purpose` takes `quotation` and `offer` beside report,
--      feedback, reminder, creator and approval, each row seeded switched
--      off.
--
-- ROLLBACK
--   Pages first (Templates lists five purposes again), then delete the two
--   rows and put the check back without them.
-- ===========================================================================

alter table public.wa_templates drop constraint if exists wa_templates_purpose_check;
alter table public.wa_templates add constraint wa_templates_purpose_check
  check (purpose in ('report', 'feedback', 'reminder', 'creator', 'approval', 'quotation', 'offer'));
insert into public.wa_templates (purpose) values ('quotation') on conflict (purpose) do nothing;
insert into public.wa_templates (purpose) values ('offer') on conflict (purpose) do nothing;

-- END OF WHATSAPP DOCUMENT PURPOSES -------------------------------------------
