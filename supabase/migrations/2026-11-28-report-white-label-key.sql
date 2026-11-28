-- ===========================================================================
-- A REPORT'S WHITE LABEL KEY RESTORED (2026-11-28)
-- ===========================================================================
-- WHY: release 4 (`2026-11-28-foreign-keys-on-ids.sql`) added
-- `sm_reports_label_client_fkey`, a second foreign key from sm_reports to
-- clients. PostgREST then refused every bare `clients(...)` embed from
-- sm_reports as ambiguous (PGRST201), and the Dashboard and Reports read
-- "Reports could not be loaded". The key was dropped live as a stopgap.
-- The pages now name the key (`clients!sm_reports_client_id_fkey(...)`),
-- `tests/embedguard.js` holds every embed so, and this file puts the key back.
-- WHAT IT CHANGES
--   * sm_reports.label_client -> clients: on delete set null, added
--     `not valid`, then validated where no row names a client that is gone.
-- ORDER: the pages first (merged and deployed), then this file: a tab
-- served before the pages embeds `clients(...)` bare and fails once the
-- key stands, so it is applied only after the Pages deploy succeeds.
-- ROLLBACK: alter table public.sm_reports drop constraint if exists
-- sm_reports_label_client_fkey; (a tab served before the pages then reads
-- again). Safe to run twice.

-- A REPORT'S WHITE LABEL KEY RESTORED -----------------------------------------

alter table public.sm_reports drop constraint if exists sm_reports_label_client_fkey;
alter table public.sm_reports add constraint sm_reports_label_client_fkey
  foreign key (label_client) references public.clients(id) on delete set null not valid;

do $$
begin
  alter table public.sm_reports validate constraint sm_reports_label_client_fkey;
exception when foreign_key_violation then
  raise notice 'sm_reports_label_client_fkey stays not valid: rows point at nothing';
end $$;

notify pgrst, 'reload schema';

-- END OF A REPORT'S WHITE LABEL KEY RESTORED ----------------------------------

select public.functions_tidy();
