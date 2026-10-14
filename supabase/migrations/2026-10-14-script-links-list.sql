-- ===========================================================================
-- SCRIPT LINKS LIST — every client's Video Scripts link for Short Links
-- (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-14, a screenshot of Short Links reading "Could not
-- load the Video Scripts links.")
--   Short Links lists every address the links host answers. A client's
--   Video Scripts key (`clients.script_key`) is withheld from the table and
--   handed out one client at a time by `script_link`, so the list's read of
--   the column was refused.
--
-- WHAT IT ADDS
--   * `script_links()`: the clients holding a Video Scripts key, each its id,
--     name, Client ID and key, for a colleague at Video Scripts View, held to
--     the clients they may see. Nothing is made or changed.
--
-- Safe to run twice. Rollback: drop function public.script_links().
-- ===========================================================================

create or replace function public.script_links()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('scripts', 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true, 'links', coalesce((
    select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'client_code', c.client_code, 'key', c.script_key)
                     order by c.name)
      from public.clients c
     where c.script_key is not null and public.client_seen(c.id, 'view')), '[]'::jsonb));
end $$;
revoke all on function public.script_links() from public, anon;
grant execute on function public.script_links() to authenticated;

-- END OF SCRIPT LINKS LIST ---------------------------------------------------
select public.functions_tidy();
