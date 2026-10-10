-- ===========================================================================
-- ACCOUNT RESTRICTED — a client's social account restricted by its platform
-- is marked on the client, so the team sees it on the record and the
-- Overview before planning or posting.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js runs it twice.
-- Runs after CLIENT BILLING COLUMNS.
--
-- WHAT CHANGED (the user, 2026-10-09: "account restricted")
--   1. `clients.restricted_platform` (instagram, facebook, tiktok, xhs,
--      other), `restricted_since` (a day) and `restricted_note` (500
--      characters at most): all set or none. Readable to the team as every
--      other non-billing column; written on the client record at Clients
--      Work under the client's scope (the guards already on the table),
--      filed by the page under client.edited.
--
-- ROLLBACK
--   The columns may stay unread.
-- ===========================================================================

alter table public.clients add column if not exists restricted_platform text;
alter table public.clients add column if not exists restricted_since date;
alter table public.clients add column if not exists restricted_note text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clients_restricted_shape') then
    alter table public.clients add constraint clients_restricted_shape
      check ((restricted_platform is null) = (restricted_since is null)
         and (restricted_platform is null or restricted_platform in ('instagram', 'facebook', 'tiktok', 'xhs', 'other'))
         and (restricted_note is null or (restricted_platform is not null and char_length(restricted_note) <= 500)));
  end if;
end $$;
grant select (restricted_platform, restricted_since, restricted_note) on table public.clients to authenticated;

-- END OF ACCOUNT RESTRICTED ---------------------------------------------------
