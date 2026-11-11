-- ===========================================================================
-- REPRESENTATIVE ON WHATSAPP, THE SQL EDITOR PART — run once in the SQL
-- Editor before REPRESENTATIVE ON WHATSAPP (2026-11-11; the connector holds
-- a statement naming drop). `wa_templates.purpose` takes `representative`,
-- its row seeded off (Settings, Messages: WhatsApp templates). Re-runnable.
-- Rollback: delete its row, then put the check back without it.

alter table public.wa_templates drop constraint if exists wa_templates_purpose_check;
alter table public.wa_templates add constraint wa_templates_purpose_check
  check (purpose in ('report', 'feedback', 'reminder', 'creator', 'approval', 'quotation', 'offer', 'quote_ready', 'representative'));
insert into public.wa_templates (purpose) values ('representative') on conflict (purpose) do nothing;

-- END OF REPRESENTATIVE ON WHATSAPP, THE SQL EDITOR PART ---------------------
