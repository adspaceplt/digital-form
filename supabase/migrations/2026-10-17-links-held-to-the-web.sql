-- ===========================================================================
-- LINKS HELD TO THE WEB — a booking's draft link, a campaign's invoice and a
-- month's Drive folder are web addresses, never script. 2026-10-17. Safe to
-- run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding M)
--   1. `campaign_options.draft_url` (typed by the team, sent by
--      `get_campaign` to the client's selection page and drawn as a link
--      there and in the console) held anything: `javascript://%0aalert(1)`
--      passed the pages' own test for a scheme and ran on a press. A check
--      holds it to `http://` or `https://`.
--   2. `campaigns.invoice_url` (drawn as a link on the client's page and in
--      the console) is held to `https://` or a private key (`private/`).
--   3. `ops_engagements.drive_url` (a month's Drive folder, drawn as a link
--      in My Work) is held to `https://`.
--   Checked live on 2026-10-17 before adding them: no stored draft link
--   (none held), invoice (two, both https) or Drive folder (none held) fails.
--   The pages draw each only on http or https as well.
--
-- ROLLBACK
--   alter table public.campaign_options drop constraint if exists campaign_options_draft_url_web;
--   alter table public.campaigns drop constraint if exists campaigns_invoice_url_web;
--   alter table public.ops_engagements drop constraint if exists ops_engagements_drive_url_web;
-- ===========================================================================

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'campaign_options_draft_url_web') then
    alter table public.campaign_options add constraint campaign_options_draft_url_web
      check (draft_url is null or draft_url ~* '^https?://[^\s"''<>`\\]+$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'campaigns_invoice_url_web') then
    alter table public.campaigns add constraint campaigns_invoice_url_web
      check (invoice_url is null or invoice_url ~* '^(https://|private/)[^\s"''<>`\\]+$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ops_engagements_drive_url_web') then
    alter table public.ops_engagements add constraint ops_engagements_drive_url_web
      check (drive_url is null or drive_url ~* '^https://[^\s"''<>`\\]+$');
  end if;
end $$;

-- END OF LINKS HELD TO THE WEB -----------------------------------------------
