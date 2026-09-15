-- ===========================================================================
-- 2026-09-15  Preflight for the RLS work
--
-- READ ONLY. It creates nothing, changes nothing and locks nothing. Run it in
-- the Supabase SQL editor and send the result back.
--
-- It checks every policy on the fifteen gated tables against the contract it
-- is supposed to meet, rather than against its name. For each one it compares
-- the table, the policy name, the role, the command, the USING condition, the
-- WITH CHECK condition, the feature permission the condition must ask for,
-- and, for DELETE, the additional `remove` requirement.
--
-- A policy is `correct` only when all of those match. A policy with the right
-- name and the wrong condition — `using (true)` under the name
-- `links_read`, say — is reported UNSAFE, because the name is not what
-- grants anything.
--
-- It also reports:
--   1. whether any colleague would lose the console (the policies rest on
--      `allowed()`, which matches an ACTIVE team_members row to the address
--      the person signs in with);
--   3. the direct table privileges `anon` still holds;
--   4. whether row level security is on;
--   5. one summary line.
--
-- Addresses are masked to the first two characters and the domain, which is
-- enough to find a row that will lock somebody out without copying anybody's
-- address out of the database.
--
-- The first version of this file compared policy NAMES against a pattern of
-- its own and reported forty-five correct least-privilege policies as
-- UNREVIEWED. It compares conditions now.
-- ===========================================================================

with gated(tbl, flag) as (values
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
  ('link_qrs',               'links')),

-- The contract. One row per policy that must exist, with what it must say.
want(tbl, flag, policyname, cmd, want_using, want_check, needs) as (
  select tbl, flag, tbl || '_read',  'SELECT',
         'allowed(''' || flag || '''::text)', null,
         flag from gated
  union all
  select tbl, flag, tbl || '_write', 'INSERT',
         null, 'allowed(''' || flag || '''::text)',
         flag from gated
  union all
  select tbl, flag, tbl || '_edit',  'UPDATE',
         'allowed(''' || flag || '''::text)', 'allowed(''' || flag || '''::text)',
         flag from gated
  union all
  select tbl, flag, tbl || '_del',   'DELETE',
         '(allowed(''' || flag || '''::text) and allowed(''remove''::text))', null,
         flag || ' + remove' from gated),

-- What is actually there, with the conditions flattened so that whitespace,
-- case and a `public.` prefix cannot make a matching policy look different.
act as (
  select p.tablename, p.policyname, p.cmd, p.roles::text as roles,
         btrim(regexp_replace(lower(replace(p.qual,       'public.', '')), '\s+', ' ', 'g')) as q,
         btrim(regexp_replace(lower(replace(p.with_check, 'public.', '')), '\s+', ' ', 'g')) as c,
         p.qual as raw_q, p.with_check as raw_c
    from pg_policies p
   where p.schemaname = 'public'),

people as (
  select
    '1. team member'                                         as section,
    t.name                                                   as subject,
    coalesce(t.role, '(none)')                               as expected,
    case when t.email is null or t.email = '' then '(no address)'
         else left(t.email, 2) || '***@' || split_part(t.email, '@', 2) end as role_or_who,
    case when t.active then 'active' else 'INACTIVE' end     as actual,
    case when t.email is null or t.email = '' then 'UNSAFE: no address on the row'
         when not t.active then 'inactive, will have no access'
         when exists (select 1 from auth.users u
                       where lower(u.email) = lower(t.email)) then 'correct: has login'
         else 'UNSAFE: no matching login, will lose the console' end as verdict
  from public.team_members t),

policy_contract as (
  select
    '2. policy contract'                                     as section,
    w.tbl || '.' || w.policyname                             as subject,
    w.cmd || ' · needs ' || w.needs                          as expected,
    coalesce(a.roles, '(missing)')                           as role_or_who,
    case when a.policyname is null then '(no such policy)'
         else 'USING ' || coalesce(a.raw_q, '-') ||
              ' | WITH CHECK ' || coalesce(a.raw_c, '-') end as actual,
    case
      when a.policyname is null
        then 'UNSAFE: missing'
      when a.q = 'true' or a.c = 'true'
        then 'UNSAFE: unrestricted, the name grants nothing'
      when a.roles <> '{authenticated}'
        then 'UNSAFE: role is ' || a.roles
      when a.cmd <> w.cmd
        then 'UNSAFE: command is ' || a.cmd || ', not ' || w.cmd
      when coalesce(a.q, '') <> coalesce(w.want_using, '')
        then 'UNSAFE: USING must be ' || coalesce(w.want_using, '(none)')
      when coalesce(a.c, '') <> coalesce(w.want_check, '')
        then 'UNSAFE: WITH CHECK must be ' || coalesce(w.want_check, '(none)')
      else 'correct'
    end                                                      as verdict
  from want w
  left join act a on a.tablename = w.tbl and a.policyname = w.policyname),

-- Anything on a gated table that the contract does not ask for. Permissive
-- policies are additive, so one of these can hold a table open on its own.
policy_extra as (
  select
    '2b. policy not in the contract'                         as section,
    a.tablename || '.' || a.policyname                       as subject,
    a.cmd                                                    as expected,
    a.roles                                                  as role_or_who,
    'USING ' || coalesce(a.raw_q, '-') ||
      ' | WITH CHECK ' || coalesce(a.raw_c, '-')             as actual,
    case when a.q = 'true' or a.c = 'true'
         then 'UNSAFE: unrestricted and unexpected'
         else 'unexpected, will stop the migration until reviewed' end as verdict
  from act a
  join gated g on g.tbl = a.tablename
 where not exists (select 1 from want w
                    where w.tbl = a.tablename and w.policyname = a.policyname)),

anon_grants as (
  select
    '3. anon privilege'                                      as section,
    g.table_name                                             as subject,
    'none'                                                   as expected,
    'anon'                                                   as role_or_who,
    string_agg(distinct g.privilege_type, ', ')              as actual,
    'to be revoked'                                          as verdict
  from information_schema.role_table_grants g
  join gated gt on gt.tbl = g.table_name
 where g.table_schema = 'public' and g.grantee = 'anon'
 group by g.table_name),

rls_state as (
  select
    '4. row level security'                                  as section,
    c.relname                                                as subject,
    'enabled'                                                as expected,
    ''                                                       as role_or_who,
    case when c.relrowsecurity then 'enabled' else 'not enabled' end as actual,
    case when c.relrowsecurity then 'correct' else 'UNSAFE: not enabled' end as verdict
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join gated g on g.tbl = c.relname
 where n.nspname = 'public'),

everything as (
  select * from people
  union all select * from policy_contract
  union all select * from policy_extra
  union all select * from anon_grants
  union all select * from rls_state),

summary as (
  select
    '5. summary'                                             as section,
    'overall'                                                as subject,
    '60 correct policies, nothing unsafe'                    as expected,
    ''                                                       as role_or_who,
    (select count(*)::text from policy_contract where verdict = 'correct')
      || ' of 60 policies correct'                           as actual,
    case when exists (select 1 from everything where verdict like 'UNSAFE%')
         then 'STOP: ' || (select string_agg(subject, ', ')
                             from everything where verdict like 'UNSAFE%')
         else 'safe to proceed' end                          as verdict)

select * from everything
union all select * from summary
order by section, subject;
