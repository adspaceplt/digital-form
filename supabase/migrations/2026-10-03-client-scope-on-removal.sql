-- ===========================================================================
-- CLIENT SCOPE ON REMOVAL — a record under a client is removed only by a
-- colleague who holds that client at Manage.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   The audit of 2026-10-03: `client_scope_guard` asks every insert and
--   update, and left removals to the functions that make them. Five of
--   them (`delete_client`, `letter_delete`, `document_delete`,
--   `sm_report_delete`, `ops_delete_engagement`) are security definer and
--   asked only the section's level, so a colleague on Own clients only, or
--   with Leads or Past clients below Manage, could remove a record they
--   cannot open. A guard before each removal on the five tables those
--   functions remove from now asks the same rule at Manage
--   (`client_row_seen`, `client_scope_ok`). A removal made by a cascade
--   (`pg_trigger_depth() > 1`) was already asked at the record it came
--   from; a caller who is not on the team, an admin, or one every client
--   reaches at Manage pays nothing (`client_scope_free`). A browser's own
--   removal already reaches only rows its read policy shows, and now meets
--   the same rule.
--
--   Holds the word delete (trigger events), so it is run in the SQL Editor.
--
-- ROLLBACK
--   For each table below: drop trigger if exists client_scope_removal on
--   public.<table>; then drop function public.client_scope_removal().
-- ===========================================================================

create or replace function public.client_scope_removal()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  kind text := tg_argv[0];
  col  text := tg_argv[1];
  o jsonb := to_jsonb(old);
begin
  if pg_trigger_depth() > 1 or public.client_scope_free('manage') then return old; end if;
  if (kind = 'self' and not public.client_row_seen(o ->> 'stage', o ->> 'owner', 'manage'))
     or (kind <> 'self' and not public.client_scope_ok(kind, (o ->> col)::uuid, 'manage')) then
    raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
  end if;
  return old;
end $$;
revoke all on function public.client_scope_removal() from public, anon, authenticated;

do $$
declare
  spec text[][] := array[
    ['clients', 'self', 'id'],
    ['client_documents', 'client', 'client_id'],
    ['documents', 'client', 'client_id'],
    ['sm_reports', 'client', 'client_id'],
    ['ops_engagements', 'client', 'client_id']];
  i int;
begin
  for i in 1 .. array_length(spec, 1) loop
    if to_regclass('public.' || spec[i][1]) is null then continue; end if;
    execute format('create or replace trigger client_scope_removal before delete on public.%I '
                   || 'for each row execute function public.client_scope_removal(%L, %L)',
                   spec[i][1], spec[i][2], spec[i][3]);
  end loop;
end $$;

-- END OF CLIENT SCOPE ON REMOVAL ---------------------------------------------
