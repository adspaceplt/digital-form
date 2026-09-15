-- ===========================================================================
-- 2026-09-15  Take anon's direct table privileges away
--
-- WHAT THIS DOES, AND ONLY THIS
--   Revokes every direct privilege the `anon` role holds on the fifteen
--   tables below. Nothing else. It creates no policy, drops no policy and
--   touches no row.
--
-- WHY IT IS THE ONLY THING LEFT
--   The preflight of 2026-09-15 read the live database: all sixty policies on
--   these tables are already correct, least privilege, gated per command on
--   the group flag that owns the table, with delete additionally asking for
--   `remove`. Row level security is on for all fifteen. There is nothing to
--   repair there, and dropping and recreating sixty correct policies to land
--   in the same place would be risk with no return.
--
--   What that preflight did find was `anon` holding DELETE, INSERT,
--   REFERENCES, SELECT, TRIGGER, TRUNCATE and UPDATE on all fifteen. Row
--   level security denies it, because no policy on these tables names that
--   role, so this is defence in depth and not a live hole. A table `anon`
--   cannot reach at all is one fewer thing resting on a policy being right.
--
-- WHAT IS NOT AFFECTED
--   `/client/`, `/creators/`, `/creator/` and `/review/` make no direct table
--   call at all — `from(` appears zero times in js/portal.js, js/creators.js,
--   js/creator.js and js/review.js — and reach their data through security
--   definer functions. Those run as the owner: they are not subject to row
--   level security and need no privilege from their caller. tests/rls.js
--   calls one as `anon` after this revoke and requires it to answer, for a
--   campaign token, a creator code and a review token.
--
--   The `authenticated` role keeps its grants. The team reaches these tables
--   through them, gated by the policies.
--
-- HOW IT RUNS
--   One `do` block inside one transaction, and idempotent: revoking a
--   privilege that is not held is a no-op, so running it twice, or after
--   somebody has already revoked by hand, changes nothing and raises nothing.
--
-- GUARD
--   It refuses to run if the policies are not in the state the preflight
--   verified. Taking privileges away while the policies are wrong could leave
--   a table nobody can reach.
--
-- BEFORE: run 2026-09-15-rls-preflight.sql. Its summary must read
--         `60 of 60 policies correct` and `safe to proceed`.
--
-- ROLLBACK: at the foot, commented out. It gives the grants back.
-- ===========================================================================

begin;

do $$
declare
  r record;
  n integer;
begin
  /* The policies must be right before anything is taken away. This is the
     same contract the preflight prints, counted rather than listed. */
  select count(*) into n
    from pg_policies p
   where p.schemaname = 'public'
     and p.tablename in ('batches','posts','reviews','drive_assets','campaigns',
       'campaign_options','campaign_confirmations','option_posts','option_reviews',
       'creators','creator_profiles','client_contacts','client_touches','links','link_qrs')
     and p.roles::text = '{authenticated}'
     and coalesce(p.qual, '') <> 'true'
     and coalesce(p.with_check, '') <> 'true'
     and p.policyname ~ ('^' || p.tablename || '_(read|write|edit|del)$');

  if n <> 60 then
    raise exception
      'Expected 60 correct policies on the gated tables, found %. Run 2026-09-15-rls-preflight.sql and read it before revoking anything.', n;
  end if;

  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and tablename in ('batches','posts','reviews','drive_assets','campaigns',
                  'campaign_options','campaign_confirmations','option_posts','option_reviews',
                  'creators','creator_profiles','client_contacts','client_touches','links','link_qrs')
                and (qual = 'true' or with_check = 'true')) then
    raise exception
      'An unrestricted policy still exists on a gated table. Nothing was revoked.';
  end if;

  for r in select unnest(array['batches','posts','reviews','drive_assets','campaigns',
    'campaign_options','campaign_confirmations','option_posts','option_reviews',
    'creators','creator_profiles','client_contacts','client_touches','links','link_qrs']) as tbl
  loop
    execute format('revoke all on public.%I from anon', r.tbl);
  end loop;
end $$;

commit;

-- ---------------------------------------------------------------------------
-- AFTERWARDS: this must return no rows.
-- ---------------------------------------------------------------------------
-- select table_name, string_agg(distinct privilege_type, ', ') as still_held
--   from information_schema.role_table_grants
--  where table_schema = 'public' and grantee = 'anon'
--    and table_name in ('batches','posts','reviews','drive_assets','campaigns',
--      'campaign_options','campaign_confirmations','option_posts','option_reviews',
--      'creators','creator_profiles','client_contacts','client_touches','links','link_qrs')
--  group by table_name;
--
-- Then open one /creators/ link, one /review/ link and one /creator/ link and
-- confirm each still loads. They go through security definer functions, so
-- they are unaffected, but it is thirty seconds to be sure.

-- ---------------------------------------------------------------------------
-- ROLLBACK: gives anon its direct table privileges back.
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
