-- ===========================================================================
-- COMPLETED, A REASON TO LEAVE
-- ===========================================================================
-- 2026-11-15. Safe to run twice. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-11-15: a one-time client whose project has
-- finished goes to Past, and the reasons held nothing for a job completed as
-- agreed, so the Dashboard and Analytics read it as a client lost)
--   1. `clients.stage_reason` takes `completed` (Completed), and only on
--      Past: a paused client is expected back. The page offers it only for
--      a move to Past of a client once Active; js/sales.js never counts it
--      as churn.
--   Nothing in the database counts churn; the figures are the page's.
--
-- ROLLBACK
--   Move any client whose stage_reason is `completed` to `other`, then put
--   the CLIENT LEAVE REASON section's check back (its constraint name is the
--   same; drop it first in the SQL Editor).
-- ===========================================================================

do $$
declare
  v_def text;
begin
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'public.clients'::regclass and c.conname = 'clients_stage_reason';
  if v_def is null or position('completed' in v_def) = 0 then
    if v_def is not null then
      execute 'alter table public.clients drop constraint clients_stage_reason';
    end if;
    alter table public.clients add constraint clients_stage_reason
      check (stage_reason is null
        or (stage_reason in ('budget', 'results', 'in_house', 'closed', 'no_reply', 'other'))
        or (stage_reason = 'completed' and stage = 'past'));
  end if;
end $$;

-- END OF COMPLETED, A REASON TO LEAVE ------------------------------------------

select public.functions_tidy();
