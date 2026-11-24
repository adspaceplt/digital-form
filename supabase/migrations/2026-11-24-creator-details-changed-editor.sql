-- ===========================================================================
-- CREATOR DETAILS CHANGED, THE SQL EDITOR PART (2026-11-24) — run in the SQL
-- Editor after CREATOR DETAILS CHANGED: it widens the creator emails' and
-- the WhatsApp templates' purposes (a constraint is replaced by dropping
-- it, which the connector holds) and seeds Details changed (Settings,
-- Templates: Creator emails) and the WhatsApp row Payment details changed
-- (Settings, Messages: WhatsApp templates; off until a template approved by
-- Meta is chosen). Running it turns the notice on. Safe to run twice.
-- ROLLBACK: delete the `changed` template, its emails and the
-- `creator_changed` WhatsApp row, then put the checks back as before.
-- ===========================================================================

alter table public.creator_email_templates drop constraint if exists creator_email_templates_purpose_check;
alter table public.creator_email_templates add constraint creator_email_templates_purpose_check
  check (purpose in ('received', 'review', 'approved', 'changed', 'request', 'posted', 'paid'));
alter table public.creator_emails drop constraint if exists creator_emails_purpose_check;
alter table public.creator_emails add constraint creator_emails_purpose_check
  check (purpose in ('received', 'review', 'approved', 'changed', 'request', 'posted', 'paid'));
insert into public.creator_email_templates (purpose, subject, body, to_email) values
  ('changed', 'Payment details changed: {reference}',
   E'Dear {creator name},\n\nYour payment details were changed on {date}. If this was not you, please contact ap@adspacestudios.com.\n\n{changes}\n\n您的收款资料已于{chinese date}更改。如非本人操作，请联系 ap@adspacestudios.com。\n\nYours sincerely,\nADspace', null)
on conflict (purpose) do nothing;

alter table public.wa_templates drop constraint if exists wa_templates_purpose_check;
alter table public.wa_templates add constraint wa_templates_purpose_check
  check (purpose in ('report', 'feedback', 'reminder', 'creator', 'approval', 'quotation', 'offer', 'quote_ready', 'representative',
                     'creator_changed'));
insert into public.wa_templates (purpose) values ('creator_changed') on conflict (purpose) do nothing;

-- END OF CREATOR DETAILS CHANGED, THE SQL EDITOR PART ----------------------

select public.functions_tidy();
