-- ===========================================================================
-- FUNCTION HYGIENE — every function names its search path, and anonymous
-- visitors run only the functions the public pages call.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two. schema.sql runs `select public.functions_tidy();` as its last
-- statement, and so does every migration that adds or replaces a function.
--
-- WHAT CHANGED
--   Supabase's Security Advisor read 430 warnings (the user, 2026-10-07).
--   None was an open door; two kinds are closed here as a second lock.
--   1. A function that names no search path finds the names it uses through
--      its caller's. 35 small helpers and triggers named none (none runs with
--      raised rights). Each is given `search_path = public`, as every other
--      function already states.
--   2. Postgres lets everyone (PUBLIC) run a new function, and Supabase grants
--      anon besides, so an anonymous visitor could call every function that
--      runs with raised rights. Each already refuses, inside, a caller who is
--      not the right person. Now anon runs only those the public pages call:
--      `open_to_anon` below, exactly the functions this file grants to anon
--      (tests/sql.js holds the two equal): the review link, the selection and
--      creator pages, /verify/, a namecard, short links, upgrade mode,
--      announcements, the business figures, notifications and the
--      minute's one check and the video scripts page (both added
--      2026-10-09). Signed-in
--      callers (the team, a client's login) and the server keep what they
--      had. A function named by a policy anon meets stays open.
--   `functions_tidy()` does both and answers how many it changed; a second
--   run changes nothing. Only the database's owner runs it.
--
-- ROLLBACK
--   Give anon its calls back, then remove functions_tidy():
--     do $$ declare f record; begin
--       for f in select p.oid::regprocedure as sig from pg_proc p
--                 where p.pronamespace = 'public'::regnamespace and p.prosecdef
--       loop execute format('grant execute on routine %s to public, anon', f.sig); end loop;
--     end $$;
--   The search paths stay: they change no answer.
-- ===========================================================================
create or replace function public.functions_tidy()
returns jsonb language plpgsql set search_path = public as $$
declare
  open_to_anon constant text[] := array[
    'announcement_now', 'app_settings_read', 'confirm_selection', 'confirm_selection_with', 'creator_add_file',
    'creator_may_upload', 'creator_post_save', 'creator_rate', 'creator_remove_file',
    'creator_set_profiles', 'creator_submit', 'get_campaign', 'get_creator',
    'get_review_feed', 'link_moved', 'link_resolve', 'maintenance_state',
    'get_scripts', 'namecard_get', 'page_pulse', 'post_link_ok', 'post_platform_key',
    'profile_of', 'push_public_key', 'push_status', 'push_subscribe', 'push_unsubscribe',
    'review_draft', 'save_selection', 'script_decide', 'script_shot_link', 'submit_review', 'verify_serial'];
  has_server constant boolean := exists (select 1 from pg_roles r where r.rolname = 'service_role');
  f record;
  sig text;
  signed_in boolean;
  server boolean;
  pathed integer := 0;
  closed integer := 0;
begin
  -- 1. A search path on every function of ours that names none.
  for f in
    select p.oid, p.proname from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
       and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c where c like 'search_path=%')
       and not exists (select 1 from pg_depend d
                        where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
  loop
    sig := format('public.%I(%s)', f.proname, pg_get_function_identity_arguments(f.oid));
    execute format('alter routine %s set search_path = public', sig);
    pathed := pathed + 1;
  end loop;

  -- 2. Anon runs a function with raised rights only where a public page calls it.
  for f in
    select p.oid, p.proname from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prosecdef
       and not (p.proname = any (open_to_anon))
       and has_function_privilege('anon', p.oid, 'execute')
       and not exists (select 1 from pg_depend d
                        where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
       and not exists (select 1 from pg_policies q
                        where ('public' = any (q.roles) or 'anon' = any (q.roles))
                          and (coalesce(q.qual, '') || ' ' || coalesce(q.with_check, '')) ~ ('\m' || p.proname || '\('))
  loop
    sig := format('public.%I(%s)', f.proname, pg_get_function_identity_arguments(f.oid));
    signed_in := has_function_privilege('authenticated', f.oid, 'execute');
    server := false;
    if has_server then server := has_function_privilege('service_role', f.oid, 'execute'); end if;
    execute format('revoke execute on routine %s from public, anon', sig);
    if signed_in then execute format('grant execute on routine %s to authenticated', sig); end if;
    if server then execute format('grant execute on routine %s to service_role', sig); end if;
    closed := closed + 1;
  end loop;

  return jsonb_build_object('search_path', pathed, 'closed_to_anon', closed);
end $$;
revoke all on function public.functions_tidy() from public, anon, authenticated;

-- END OF FUNCTION HYGIENE -----------------------------------------------------

select public.functions_tidy();
