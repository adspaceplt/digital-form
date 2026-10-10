-- ===========================================================================
-- CLIENT BRIEF — a client's content brief on its Brand pane: who the content
-- speaks to, their pain points, the content pillars, the tone, what to
-- avoid, the competitors and the hooks that worked. Write with AI reads it
-- for captions and scripts.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js runs it twice.
-- Runs after CLIENT BILLING COLUMNS.
--
-- WHAT CHANGED (the user, 2026-10-09: "content not interesting")
--   1. `clients.brief` (jsonb, an object of short texts keyed audience,
--      pains, pillars, tone, avoid, competitors, hooks; 8,000 characters in
--      all at most), readable to the team as every other non-billing
--      column, written with the Brand profile at Clients Work under the
--      client's scope (the guards already on the table).
--
-- ROLLBACK
--   alter table public.clients drop column brief; (in the SQL Editor)
-- ===========================================================================

alter table public.clients add column if not exists brief jsonb;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clients_brief_shape') then
    alter table public.clients add constraint clients_brief_shape
      check (brief is null or (jsonb_typeof(brief) = 'object' and char_length(brief::text) <= 8000));
  end if;
end $$;
grant select (brief) on table public.clients to authenticated;

-- END OF CLIENT BRIEF ---------------------------------------------------------
