-- ===========================================================================
-- A WITHDRAWN TALK CAN BE DELETED — the colleague who asked for a talk and
-- withdrew it deletes it from their Talks (2026-10-24)
-- ===========================================================================
-- WHY (the user, 2026-10-24: "Health > Talks > Withdrawn (but not possible
-- to delete?"): whatever a person adds, they can delete where nothing names
-- it (2026-10-22). A withdrawn talk is the asker's alone: the colleague
-- asked and Team: Health no longer read it.
--
-- WHAT IT ADDS
--   * `health_talk_delete(p_id)`: behind the fresh proof
--     (`perf_mine_gate`); the asker alone (`not-found` for anyone else),
--     a withdrawn talk alone (`bad-status`, so an open or done talk, which
--     the colleague asked still reads, stays); answers `health_mine()`.
--     Nothing is filed: a talk never reaches the Activity record.
--
-- ORDER: this file in the SQL Editor (it holds a delete the connector holds
-- back), then the pages. A page served before it reads "This needs a
-- database update" at Delete. Safe to run twice. Rollback:
--   drop function if exists public.health_talk_delete(uuid);
-- ===========================================================================

create or replace function public.health_talk_delete(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; t public.health_talks;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  select * into t from public.health_talks where id = p_id for update;
  if t.id is null or t.team_member_id is distinct from m.id then
    return jsonb_build_object('error', 'not-found');
  end if;
  if t.status <> 'withdrawn' then return jsonb_build_object('error', 'bad-status'); end if;
  delete from public.health_talks where id = t.id;
  return public.health_mine();
end $$;

revoke all on function public.health_talk_delete(uuid) from public, anon, authenticated;
grant execute on function public.health_talk_delete(uuid) to authenticated;

-- END OF A WITHDRAWN TALK CAN BE DELETED --------------------------------------

select public.functions_tidy();
