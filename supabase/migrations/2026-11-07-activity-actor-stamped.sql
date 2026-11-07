-- ===========================================================================
-- ACTIVITY ACTOR STAMPED (2026-11-07)
-- ===========================================================================
-- WHY (security audit, 2026-11-07; the user: "fix all"):
-- A colleague could file an Activity record line, a report's Record of
-- changes included, in another person's name or on another day.
--
-- WHAT IT CHANGES
--   Trigger `activity_log_stamp` sets the actor and time of a line a page
--   inserts from the sign-in; a function's own line keeps its actor.
--
-- ORDER: this file alone; the console already sends the sign-in address. Safe to run twice.
--
-- ROLLBACK: drop trigger activity_log_stamp on public.activity_log; drop function public.activity_log_stamp(); (SQL Editor: the connector holds a drop).
-- ===========================================================================

-- ACTIVITY ACTOR STAMPED -----------------------------------------------------

/* Who filed a line is the database's word (security audit 2026-11-07): a
   page's own insert into the Activity record took its actor and its time
   from the page, so a colleague could file a line in another's name, or on
   another day. A line a page inserts is stamped with the address the caller
   signed in with and the moment it arrived; a function's own line (its
   owner the writer) and a scheduled job's keep the actor they name. */
create or replace function public.activity_log_stamp()
returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.actor := coalesce(nullif(lower(auth.jwt() ->> 'email'), ''), 'unknown');
    new.created_at := now();
  end if;
  return new;
end $$;
revoke all on function public.activity_log_stamp() from public, anon, authenticated;
create or replace trigger activity_log_stamp before insert on public.activity_log
  for each row execute function public.activity_log_stamp();

-- END OF ACTIVITY ACTOR STAMPED ----------------------------------------------

select public.functions_tidy();
