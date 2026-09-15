-- ===========================================================================
-- 2026-09-15  Least privilege on the CRM and campaign tables
--
-- WHAT WAS WRONG
--   Fifteen tables carried `for all to authenticated using (true) with check
--   (true)`. That was written when `authenticated` meant the team. It does
--   not any more: `/client/` signs a client in with a real Supabase account
--   (`portal-login`), and the anon key is public by design, so a signed-in
--   client holds a JWT that PostgREST accepts. With it they could read every
--   other client's record, contacts, content and approvals, every creator's
--   fee, and every campaign, and write to most of them.
--
--   The same policies ignored the user groups. A Sales member has
--   can_campaigns false and can_review false, and the console hides those
--   sections — but the database let them read and write every campaign,
--   creator, content set and approval. Hiding a section is not access
--   control.
--
-- WHAT THIS CHANGES
--   Each table is gated on the group flag that owns it, and SELECT, INSERT,
--   UPDATE and DELETE are separate policies, so read access and the right to
--   destroy a row are no longer the same grant.
--
--     batches, posts, reviews, drive_assets      review
--     campaigns, campaign_options,               campaigns
--     campaign_confirmations, option_posts,
--     option_reviews, creators, creator_profiles
--     client_contacts, client_touches            clients
--     links, link_qrs                            links
--
--   Two tables are also readable by a neighbouring section, because the
--   client record shows Engagements: `batches` and `campaigns` are readable
--   with `clients` as well. Writes stay with the owning section.
--
--   `client_contacts` DELETE asks for `remove` rather than `clients`. The
--   console already holds Delete permanently behind that switch; this is the
--   server agreeing.
--
--   Direct table privileges are revoked from `anon` as well. RLS already
--   denies it, because no policy here names that role, but a table it cannot
--   reach at all is one fewer thing resting on a policy being right.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE
--   No client-facing page loses anything. `/client/`, `/creators/`,
--   `/creator/` and `/review/` make no direct table call at all — every one
--   of them reads and writes through a security definer function, and those
--   run as the owner, are not subject to RLS, and do not need the caller to
--   hold any privilege on the tables they touch. Verified by inspection
--   (`from(` appears zero times in js/portal.js, js/creators.js,
--   js/creator.js and js/review.js) and by tests/rls.js, which calls a
--   definer function as `anon` after the revoke and requires it to answer.
--
-- HOW IT RUNS
--   Everything below is one `do $$` block inside one transaction. A `do`
--   block is a single statement, so the drops and the creates land together:
--   there is no instant in which a table is readable with no policy on it.
--   If the guard raises, the transaction rolls back and the database is
--   exactly as it was.
--
-- SAFETY GUARD
--   The block refuses to run if it finds a policy on one of these fifteen
--   tables that nobody has reviewed. Run `preflight.sql` first, read what is
--   there, and add any policy you have decided to discard to `reviewed_extra`
--   below. Nothing is deleted on trust.
--
-- ROLLBACK
--   At the foot, commented out. It restores the previous permissive policies
--   and the `anon` grants, which restores the exposure.
-- ===========================================================================

begin;

do $$
declare
  r record;
  p record;
  /* Every policy name this schema has ever created on these fifteen tables,
     read off supabase/schema.sql on 2026-09-15. Anything else is a surprise
     and stops the migration. */
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
  /* ---- 1. Refuse to delete anything nobody has looked at ---------------- */
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
     -- what this file itself creates, so a second run is not a surprise
     and x.policyname !~ ('^' || x.tablename || '_(sel|ins|upd|del)$');

  if odd is not null then
    raise exception
      'Unreviewed policy on a gated table, so nothing was changed: %. Read it, then add its name to reviewed_extra in this file and run again.', odd;
  end if;

  /* ---- 2. Replace ------------------------------------------------------- */
  /* One shape for all fifteen, so a table cannot quietly differ from its
     neighbour. `flag` is what may write, `also_read` is a neighbouring section
     that may read, and `del_flag` is what may delete.

     Every existing policy on these tables is dropped by what is actually
     there, not by a list of remembered names: policies are permissive and
     additive, so one left behind under an unlisted name keeps the table open,
     and that is the failure being repaired. The guard above is what makes
     that safe. */
  for r in
    select * from (values
      ('batches',                'review',    'clients',  'review'),
      ('posts',                  'review',    null,       'review'),
      ('reviews',                'review',    null,       'review'),
      ('drive_assets',           'review',    null,       'review'),
      ('campaigns',              'campaigns', 'clients',  'campaigns'),
      ('campaign_options',       'campaigns', null,       'campaigns'),
      ('campaign_confirmations', 'campaigns', null,       'campaigns'),
      ('option_posts',           'campaigns', null,       'campaigns'),
      ('option_reviews',         'campaigns', null,       'campaigns'),
      ('creators',               'campaigns', null,       'campaigns'),
      ('creator_profiles',       'campaigns', null,       'campaigns'),
      ('client_contacts',        'clients',   null,       'remove'),
      ('client_touches',         'clients',   null,       'clients'),
      ('links',                  'links',     null,       'links'),
      ('link_qrs',               'links',     null,       'links')
    ) as t(tbl, flag, also_read, del_flag)
  loop
    execute format('alter table public.%I enable row level security', r.tbl);

    for p in select policyname from pg_policies
              where schemaname = 'public' and tablename = r.tbl
    loop
      execute format('drop policy if exists %I on public.%I', p.policyname, r.tbl);
    end loop;

    execute format(
      'create policy %I on public.%I for select to authenticated using (%s)',
      r.tbl || '_sel', r.tbl,
      case when r.also_read is null
           then format('public.allowed(%L)', r.flag)
           else format('public.allowed(%L) or public.allowed(%L)', r.flag, r.also_read) end);

    execute format(
      'create policy %I on public.%I for insert to authenticated with check (public.allowed(%L))',
      r.tbl || '_ins', r.tbl, r.flag);

    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (public.allowed(%L)) with check (public.allowed(%L))',
      r.tbl || '_upd', r.tbl, r.flag, r.flag);

    execute format(
      'create policy %I on public.%I for delete to authenticated using (public.allowed(%L))',
      r.tbl || '_del', r.tbl, r.del_flag);

    /* ---- 3. Defence in depth ------------------------------------------- */
    /* Nothing anonymous reads these tables directly. The token and code pages
       go through security definer functions, which run as the owner and need
       no privilege from their caller. */
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
--    and p.policyname ~ ('^' || p.tablename || '_(sel|ins|upd|del)$')
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
--    and p.policyname !~ ('^' || p.tablename || '_(sel|ins|upd|del)$')
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
-- ROLLBACK (restores the exposure)
-- ---------------------------------------------------------------------------
-- begin;
-- do $$
-- declare r record;
-- begin
--   for r in select unnest(array['batches','posts','reviews','drive_assets','campaigns',
--     'campaign_options','campaign_confirmations','option_posts','option_reviews',
--     'creators','creator_profiles','client_contacts','client_touches','links','link_qrs']) as tbl
--   loop
--     execute format('drop policy if exists %I on public.%I', r.tbl || '_sel', r.tbl);
--     execute format('drop policy if exists %I on public.%I', r.tbl || '_ins', r.tbl);
--     execute format('drop policy if exists %I on public.%I', r.tbl || '_upd', r.tbl);
--     execute format('drop policy if exists %I on public.%I', r.tbl || '_del', r.tbl);
--     execute format('create policy %I on public.%I for all to authenticated '
--                    'using (true) with check (true)', r.tbl || '_open', r.tbl);
--     execute format('grant all on public.%I to anon', r.tbl);
--   end loop;
-- end $$;
-- commit;
