-- ===========================================================================
-- A TASK MAY BE MADE FOR A PAST CLIENT — the Client scope takes active and
-- paused clients, and past ones when asked.
-- 2026-09-24. Safe to run twice. Run after 2026-09-23-operations-phase4.sql.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/ops.js compares the two.
--
-- WHAT CHANGED. The new task sheet offered "Include paused clients"; the
-- user asked for "Include past clients" (2026-09-24). A paused client is
-- still a client, so paused is offered by default and the tick adds past
-- clients, whose renewal and wind-down work is still work. The check is
-- still made once, at creation.
--
-- ROLLBACK
--   re-run ops_scope_error from 2026-09-23-operations-phase4.sql.
-- ===========================================================================

create or replace function public.ops_scope_error(p_scope text, p_client uuid)
returns text
language plpgsql stable as $$
declare st text;
begin
  if p_scope = 'internal' then return null; end if;
  if p_scope not in ('client', 'lead') then return 'bad-scope'; end if;
  if p_client is null then return 'client-required'; end if;
  select stage into st from public.clients where id = p_client;
  if st is null then return 'client-required'; end if;
  if p_scope = 'client' and st not in ('active', 'paused', 'past') then return 'client-not-active'; end if;
  if p_scope = 'lead' and st not in ('lead', 'contacted', 'proposal') then return 'not-a-lead'; end if;
  return null;
end $$;

-- END OF A TASK MAY BE MADE FOR A PAST CLIENT --------------------------------
