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
--   `allowed()` returns true for any admin and false for anybody with no
--   active team row, so a client, a creator and an anonymous visitor all get
--   nothing from every table here.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE
--   No client-facing page loses anything. `/client/`, `/creators/`,
--   `/creator/` and `/review/` make no direct table call at all — every one
--   of them reads and writes through a security definer function, and those
--   run as the owner and are not subject to RLS. Verified by inspection:
--   `from(` appears zero times in js/portal.js, js/creators.js, js/creator.js
--   and js/review.js.
--
-- BEFORE YOU RUN THIS
--   These policies rest on `is_team()` and `allowed()`, which match an active
--   `team_members` row to the signed-in address. If a colleague's stored
--   address does not match the one they sign in with, they lose access the
--   moment this runs. Check first, in the SQL editor:
--
--     select t.name, t.email, t.role, t.active,
--            exists (select 1 from auth.users u
--                     where lower(u.email) = lower(t.email)) as has_login
--       from public.team_members t order by t.active desc, t.name;
--
--   Every person who needs the console must be active and show has_login
--   true. Fix any row before running the rest of this file.
--
-- ROLLBACK
--   At the foot, commented out. It restores the previous permissive policies
--   exactly, which restores the exposure.
-- ===========================================================================

/* One shape for all fifteen, so a table cannot quietly differ from its
   neighbour. `flag` is what may write, `also_read` is a neighbouring section
   that may read, and `del_flag` is what may delete.

   Every existing policy on these tables is dropped first, whatever it is
   called, rather than the handful of names this schema happens to remember.
   Policies are permissive and additive: one left behind under a name nobody
   listed keeps the table open, and that is the whole failure being repaired
   here. Idempotent, because the drop is driven by what is actually there. */
do $$
declare r record; p record;
begin
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
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Check it took. The first should return 0 rows. The second lists what each
-- table now asks for.
-- ---------------------------------------------------------------------------
-- select tablename, policyname, cmd, qual, with_check
--   from pg_policies
--  where schemaname = 'public' and (qual = 'true' or with_check = 'true')
--  order by tablename;
--
-- select tablename, cmd, policyname, qual from pg_policies
--  where schemaname = 'public'
--    and tablename in ('batches','posts','reviews','drive_assets','campaigns',
--      'campaign_options','campaign_confirmations','option_posts','option_reviews',
--      'creators','creator_profiles','client_contacts','client_touches','links','link_qrs')
--  order by tablename, cmd;

-- ---------------------------------------------------------------------------
-- ROLLBACK (restores the exposure)
-- ---------------------------------------------------------------------------
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
--   end loop;
-- end $$;
