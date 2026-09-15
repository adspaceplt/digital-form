-- ===========================================================================
-- 2026-09-15  Bring the repository in line with the live policies, and take
--             anon's direct table privileges away
--
-- WHAT THE PREFLIGHT FOUND
--   The live database is NOT in the state supabase/schema.sql describes. The
--   fifteen tables below were hardened there already, under the names _read,
--   _write, _edit and _del, gated on the group flag that owns each table,
--   with delete additionally asking for `remove`. No permissive
--   `using (true)` policy exists on any of them.
--
--   The repository still carried the permissive policies those replaced. That
--   is the live risk this file closes: a full re-run of supabase/schema.sql,
--   for any reason, would have recreated `for all to authenticated using
--   (true)` on all fifteen and reinstated the exposure — every other client's
--   record, contacts, content and approvals, and every creator's fee,
--   readable by any signed-in account, because /client/ signs clients in with
--   real Supabase accounts and the anon key is public by design.
--
-- WHAT THIS DOES
--   1. Reproduces the live policies exactly, so the schema file can no longer
--      weaken them. For a database already in that state this half is a
--      no-op: it drops each policy and makes the same one again.
--   2. Revokes anon's direct table privileges. The preflight shows anon still
--      holds DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE and UPDATE
--      on all fifteen. Row level security denies it today, because no policy
--      names that role, but a table it cannot reach at all is one fewer thing
--      resting on a policy being right. This half is the only change to
--      behaviour.
--
-- WHAT IT DOES NOT DO
--   It does not loosen anything. An earlier draft of this file gave delete
--   the section flag alone; the live policies ask for the section AND
--   `remove`, which is stricter, and that is what is reproduced here.
--
--   No client-facing page loses anything. /client/, /creators/, /creator/ and
--   /review/ make no direct table call at all — `from(` appears zero times in
--   js/portal.js, js/creators.js, js/creator.js and js/review.js — and reach
--   their data through security definer functions, which run as the owner and
--   need no privilege from their caller. tests/rls.js calls one as anon after
--   the revoke and requires it to answer.
--
-- HOW IT RUNS
--   One `do` block inside one transaction. A `do` block is a single
--   statement, so the drops and the creates land together: there is no
--   instant in which a table is readable with no policy on it, and a raise
--   rolls the whole thing back.
--
-- SAFETY GUARD
--   It refuses to run if it meets a policy on one of these tables that nobody
--   has reviewed. Run 2026-09-15-rls-preflight.sql first, read what is there,
--   and add anything you have decided to discard to `reviewed_extra`.
--
-- ROLLBACK
--   At the foot, commented out. It restores anon's grants. It does not
--   restore the permissive policies, because those are the defect.
-- ===========================================================================

begin;

/* The policies this database actually carries, reproduced so that re-running
   this file can never replace them with something weaker.

   The fifteen tables below were hardened in the live database before this
   block existed, under the names _read, _write, _edit and _del. The earlier
   sections of this file still create the permissive `using (true)` policies
   they replaced, so a full re-run without this block would reinstate the
   exposure: every other client's record, contacts, content and approvals, and
   every creator's fee, readable by any signed-in account, because /client/
   signs clients in with real Supabase accounts and the anon key is public by
   design.

   Select, insert, update and delete are four separate policies, so reading a
   row and destroying it are not one grant, and delete additionally asks for
   `remove` — the switch the console already holds Delete permanently behind.

   One `do` block is one statement, so the drops and the creates land
   together: there is no instant in which a table is readable with no policy
   on it. It refuses to run at all if it meets a policy nobody has reviewed,
   because it drops by what is there rather than by a list of remembered
   names. */
do $$
declare
  r record;
  p record;
  /* Every policy name this schema, or the hardening already applied to the
     live database, has created on these fifteen tables. Anything else stops
     the migration so that a person looks at it first. */
  reviewed constant text[] := array[
    'team_all', 'campaigns_team', 'campaign_options_team', 'campaign_conf_team',
    'option_posts_team', 'option_reviews_team', 'creators_team',
    'creator_profiles_team', 'contacts staff', 'touches staff',
    'links_team', 'link_qrs_team'
  ];
  /* Add a policy name here once you have looked at it in the preflight output
     and decided it should go. Leave it empty until then. */
  reviewed_extra constant text[] := array[]::text[];
  odd text;
begin
  select string_agg(format('%s.%s (%s %s)', x.tablename, x.policyname, x.cmd,
                           coalesce(x.roles::text, '')), ', ' order by x.tablename)
    into odd
    from pg_policies x
   where x.schemaname = 'public'
     and x.tablename in ('batches','posts','reviews','drive_assets','campaigns',
       'campaign_options','campaign_confirmations','option_posts','option_reviews',
       'creators','creator_profiles','client_contacts','client_touches','links','link_qrs')
     and not (x.policyname = any(reviewed))
     and not (x.policyname = any(reviewed_extra))
     -- what this block itself creates, so a second run is not a surprise
     and x.policyname !~ ('^' || x.tablename || '_(read|write|edit|del)$');

  if odd is not null then
    raise exception
      'Unreviewed policy on a gated table, so nothing was changed: %. Read it, then add its name to reviewed_extra in this file and run again.', odd;
  end if;

  for r in
    select * from (values
      ('batches',                'review'),
      ('posts',                  'review'),
      ('reviews',                'review'),
      ('drive_assets',           'review'),
      ('campaigns',              'campaigns'),
      ('campaign_options',       'campaigns'),
      ('campaign_confirmations', 'campaigns'),
      ('option_posts',           'campaigns'),
      ('option_reviews',         'campaigns'),
      ('creators',               'campaigns'),
      ('creator_profiles',       'campaigns'),
      ('client_contacts',        'clients'),
      ('client_touches',         'clients'),
      ('links',                  'links'),
      ('link_qrs',               'links')
    ) as t(tbl, flag)
  loop
    execute format('alter table public.%I enable row level security', r.tbl);

    for p in select policyname from pg_policies
              where schemaname = 'public' and tablename = r.tbl
    loop
      execute format('drop policy if exists %I on public.%I', p.policyname, r.tbl);
    end loop;

    execute format(
      'create policy %I on public.%I for select to authenticated using (public.allowed(%L))',
      r.tbl || '_read', r.tbl, r.flag);

    execute format(
      'create policy %I on public.%I for insert to authenticated with check (public.allowed(%L))',
      r.tbl || '_write', r.tbl, r.flag);

    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (public.allowed(%L)) with check (public.allowed(%L))',
      r.tbl || '_edit', r.tbl, r.flag, r.flag);

    /* Destroying a row asks for the section AND the remove switch, which is
       what the console already holds Delete permanently behind. */
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using (public.allowed(%L) and public.allowed(''remove''))',
      r.tbl || '_del', r.tbl, r.flag);

    /* Nothing anonymous reads these tables directly: the token and code pages
       go through security definer functions, which run as the owner and need
       no privilege from their caller. Row level security already denies anon,
       because no policy here names that role, but a table it cannot reach at
       all is one fewer thing resting on a policy being right. */
    execute format('revoke all on public.%I from anon', r.tbl);
  end loop;
end $$;

commit;

-- ---------------------------------------------------------------------------
-- AFTERWARDS: run this. Every row must read `pass`.
-- ---------------------------------------------------------------------------
-- with t(tbl) as (values
--   ('batches'),('posts'),('reviews'),('drive_assets'),('campaigns'),
--   ('campaign_options'),('campaign_confirmations'),('option_posts'),
--   ('option_reviews'),('creators'),('creator_profiles'),('client_contacts'),
--   ('client_touches'),('links'),('link_qrs'))
-- select 'the four expected policies exist on all fifteen' as check,
--        case when count(*) = 60 then 'pass' else 'FAIL ' || count(*) || ' of 60' end as result
--   from pg_policies p join t on t.tbl = p.tablename
--  where p.schemaname = 'public'
--    and p.policyname ~ ('^' || p.tablename || '_(read|write|edit|del)$')
-- union all
-- select 'no unrestricted policy anywhere in public',
--        case when count(*) = 0 then 'pass'
--             else 'FAIL ' || string_agg(tablename || '.' || policyname, ', ') end
--   from pg_policies where schemaname = 'public' and (qual = 'true' or with_check = 'true')
-- union all
-- select 'no unexpected policy on a gated table',
--        case when count(*) = 0 then 'pass'
--             else 'FAIL ' || string_agg(p.tablename || '.' || p.policyname, ', ') end
--   from pg_policies p join t on t.tbl = p.tablename
--  where p.schemaname = 'public'
--    and p.policyname !~ ('^' || p.tablename || '_(read|write|edit|del)$')
-- union all
-- select 'delete still asks for the remove switch on all fifteen',
--        case when count(*) = 15 then 'pass' else 'FAIL ' || count(*) || ' of 15' end
--   from pg_policies p join t on t.tbl = p.tablename
--  where p.schemaname = 'public' and p.cmd = 'DELETE' and p.qual like '%remove%'
-- union all
-- select 'row level security is on for all fifteen',
--        case when count(*) = 15 then 'pass' else 'FAIL ' || count(*) || ' of 15' end
--   from pg_class c join pg_namespace n on n.oid = c.relnamespace
--   join t on t.tbl = c.relname
--  where n.nspname = 'public' and c.relrowsecurity
-- union all
-- select 'anon holds no direct privilege on the fifteen',
--        case when count(*) = 0 then 'pass'
--             else 'FAIL ' || string_agg(distinct table_name, ', ') end
--   from information_schema.role_table_grants g join t on t.tbl = g.table_name
--  where g.table_schema = 'public' and g.grantee = 'anon';

-- ---------------------------------------------------------------------------
-- ROLLBACK: gives anon its direct table privileges back. The policies are not
-- restored to the permissive form, because that form is the defect.
-- ---------------------------------------------------------------------------
-- begin;
-- do $$
-- declare r record;
-- begin
--   for r in select unnest(array['batches','posts','reviews','drive_assets','campaigns',
--     'campaign_options','campaign_confirmations','option_posts','option_reviews',
--     'creators','creator_profiles','client_contacts','client_touches','links','link_qrs']) as tbl
--   loop
--     execute format('grant all on public.%I to anon', r.tbl);
--   end loop;
-- end $$;
-- commit;
