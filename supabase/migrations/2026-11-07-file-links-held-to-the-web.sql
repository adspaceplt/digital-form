-- ===========================================================================
-- FILE LINKS HELD TO THE WEB (2026-11-07)
-- ===========================================================================
-- WHY (security audit, 2026-11-07; the user: "fix all"):
-- A booking's file and a hand-added document's file link could hold a
-- javascript: address, drawn or opened as a link.
--
-- WHAT IT CHANGES
--   Checks `campaign_deliverables_url_web` (https) and `documents_file_url_web`
--   (http or https).
--
-- ORDER: this file, then the pages (which also open them only on http or https). Safe to run twice.
--
-- ROLLBACK: alter table public.campaign_deliverables drop constraint if exists campaign_deliverables_url_web; alter table public.documents drop constraint if exists documents_file_url_web; (SQL Editor).
-- ===========================================================================

-- FILE LINKS HELD TO THE WEB -------------------------------------------------

/* A booking's file and a hand-added document's file link are web addresses,
   never script (security audit 2026-11-07, the two leads LINKS HELD TO THE
   WEB did not reach): `campaign_deliverables.url`, which a colleague at
   Campaigns Work writes and the selection page and the creator's page draw
   as a link, is held to `https://`; `documents.file_url`, typed in Add
   existing document and opened by the console, to `http://` or `https://`.
   Checked live on 2026-11-07 before adding them: none of 28 files or 155
   documents fails. The pages open each only on http or https as well. */
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'campaign_deliverables_url_web') then
    alter table public.campaign_deliverables add constraint campaign_deliverables_url_web
      check (url ~* '^https://[^\s"''<>`\\]+$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'documents_file_url_web') then
    alter table public.documents add constraint documents_file_url_web
      check (file_url is null or file_url ~* '^https?://[^\s"''<>`\\]+$');
  end if;
end $$;

-- END OF FILE LINKS HELD TO THE WEB ------------------------------------------

select public.functions_tidy();
