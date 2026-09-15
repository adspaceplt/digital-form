-- ===========================================================================
-- 2026-09-15  Preflight for the RLS tenant-isolation migration
--
-- READ ONLY. It changes nothing. Run it in the Supabase SQL editor and send
-- back the result before running the migration itself.
--
-- It answers two questions:
--
--   1. Will anybody lose the console?  The new policies rest on `is_team()`
--      and `allowed()`, which match an ACTIVE `team_members` row to the
--      address the person signs in with. A colleague whose stored address
--      does not match their login, or whose row is inactive, loses access the
--      moment the migration runs.
--
--   2. Is there a policy nobody has reviewed?  The migration drops every
--      policy on the fifteen gated tables. It refuses to run if it finds one
--      this schema did not create, so that nothing is deleted on trust. This
--      is where you see what is actually there.
--
-- Addresses are masked: the first two characters and the domain, which is
-- enough to tell whose row is wrong without copying anybody's address out of
-- the database.
-- ===========================================================================

with gated(tbl) as (values
  ('batches'),('posts'),('reviews'),('drive_assets'),('campaigns'),
  ('campaign_options'),('campaign_confirmations'),('option_posts'),
  ('option_reviews'),('creators'),('creator_profiles'),('client_contacts'),
  ('client_touches'),('links'),('link_qrs')),

known(policyname) as (values
  ('team_all'),('campaigns_team'),('campaign_options_team'),('campaign_conf_team'),
  ('option_posts_team'),('option_reviews_team'),('creators_team'),
  ('creator_profiles_team'),('contacts staff'),('touches staff'),
  ('links_team'),('link_qrs_team')),

people as (
  select
    '1. team member'                                        as section,
    t.name                                                  as subject,
    coalesce(t.role, '(none)')                              as detail_a,
    case when t.email is null or t.email = '' then '(no address)'
         else left(t.email, 2) || '***@' || split_part(t.email, '@', 2) end as detail_b,
    case when t.active then 'active' else 'INACTIVE' end    as detail_c,
    case when t.email is null or t.email = '' then 'NO ADDRESS ON THE ROW'
         when exists (select 1 from auth.users u
                       where lower(u.email) = lower(t.email)) then 'has login'
         else 'NO MATCHING LOGIN' end                       as verdict
  from public.team_members t),

policies as (
  select
    '2. policy on a gated table'                            as section,
    p.tablename || '.' || p.policyname                      as subject,
    p.cmd                                                   as detail_a,
    coalesce(p.roles::text, '(none)')                       as detail_b,
    'USING ' || coalesce(p.qual, '-') ||
      ' | WITH CHECK ' || coalesce(p.with_check, '-')       as detail_c,
    case when p.qual = 'true' or p.with_check = 'true' then 'UNRESTRICTED'
         when p.policyname in (select policyname from known) then 'known, will be replaced'
         when p.policyname ~ ('^' || p.tablename || '_(sel|ins|upd|del)$')
              then 'already the new shape'
         else 'UNREVIEWED, will stop the migration' end     as verdict
  from pg_policies p
  join gated g on g.tbl = p.tablename
 where p.schemaname = 'public'),

anon_grants as (
  select
    '3. anon privilege to be revoked'                       as section,
    g.table_name                                            as subject,
    string_agg(distinct g.privilege_type, ', ')             as detail_a,
    'anon'                                                  as detail_b,
    ''                                                      as detail_c,
    'direct table privilege, to be revoked'                 as verdict
  from information_schema.role_table_grants g
  join gated gt on gt.tbl = g.table_name
 where g.table_schema = 'public' and g.grantee = 'anon'
 group by g.table_name),

rls_state as (
  select
    '4. row level security'                                 as section,
    c.relname                                               as subject,
    '' as detail_a, '' as detail_b, '' as detail_c,
    case when c.relrowsecurity then 'enabled' else 'NOT ENABLED' end as verdict
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join gated g on g.tbl = c.relname
 where n.nspname = 'public')

select * from people
union all select * from policies
union all select * from anon_grants
union all select * from rls_state
order by section, subject;
