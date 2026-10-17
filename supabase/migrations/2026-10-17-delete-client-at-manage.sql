-- ===========================================================================
-- DELETE CLIENT AT MANAGE — deleting a client is the team's alone, at
-- Clients Full Access, checked again inside the function. 2026-10-17. Safe
-- to run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/lettersql.js compares the
-- two. Runs after LETTERS HELD TO THEIR LINES.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding 1)
--   1. `delete_client`: the version of 2026-10-10 (filing its own entry,
--      audit R1) dropped the two refusals the first one held, so any
--      signed-in account (a client's portal login, a colleague at View)
--      could delete any client and everything filed under it. The function
--      refuses again, before anything is read, a caller who is not an active
--      colleague or who does not hold Clients at Manage ('Not allowed', as
--      the page shows it). Everything else is as it was: the delete code,
--      the client scope trigger on the removal, and the entry it files.
--
-- ROLLBACK
--   Run `delete_client` again from 2026-10-10-letters-held-to-their-lines.sql
--   (it reopens the finding; only to undo a fault in this file).
-- ===========================================================================

create or replace function public.delete_client(p_client uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  want text;
  who  text := auth.jwt() ->> 'email';
  cl   public.clients%rowtype;
  me   public.team_members%rowtype;
begin
  if who is null then
    raise exception 'Not signed in';
  end if;
  /* The team's alone, at Clients Full Access: a client's login holds no team
     row, and hiding the menu item is not access control. */
  if not public.is_team() or not public.allowed('clients', 'manage') then
    raise exception 'Not allowed';
  end if;

  select value into want from public.app_secrets where key = 'delete_code';

  -- No code set: the interface asks for the client's name instead, and has
  -- already checked it. Nothing more to enforce here.
  if want is not null and want <> '' then
    if p_code is null or p_code <> want then
      return 'wrong-code';
    end if;
  end if;

  select * into cl from public.clients where id = p_client;
  delete from public.clients where id = p_client;
  if not found then
    return 'not-found';
  end if;
  /* Filed here, in the same transaction, never by the page after the answer
     (audit R1, 2026-10-10): a reply lost on the way left no record. */
  select * into me from public.team_members where lower(email) = lower(who) and active limit 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, who), 'client.deleted', cl.name, coalesce(cl.client_code, ''));
  return 'deleted';
end $$;

revoke all on function public.delete_client(uuid, text) from public, anon;
grant execute on function public.delete_client(uuid, text) to authenticated;

-- END OF DELETE CLIENT AT MANAGE ---------------------------------------------

select public.functions_tidy();
