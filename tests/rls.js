/* Authorization, run against a real Postgres.
 *
 * Fifteen tables carried `for all to authenticated using (true)`, written when
 * `authenticated` meant the team. It has not since /client/ began signing
 * clients in with real Supabase accounts: a client's own JWT would have read
 * every other client's record, every creator's fee and every campaign.
 *
 * Nothing in the browser suites can test a policy, because the stand-in has no
 * RLS at all. This starts a throwaway cluster, applies the real policy block
 * from supabase/schema.sql, and then asks the same questions as six different
 * principals: an admin, a Marketing member, a Sales member, two clients at
 * different companies, and an anonymous visitor.
 *
 * Every account and record here is synthetic. No production address, client,
 * creator, token or access code appears in this file.
 */
const { execFileSync } = require('child_process');
const fs = require('fs');
const T = process.argv[2];
const PGBIN = '/usr/lib/postgresql/16/bin';
const DIR = '/tmp/pgrls';
const SOCK = '/tmp/pgrlssock';
const PORT = '55434';

let fails = 0;
const check = (name, ok, note) => {
  console.log((ok ? 'ok   ' : 'FAIL ') + name + (note ? '  ' + note : ''));
  if (!ok) fails++;
};
const asPg = (cmd) => execFileSync('su', ['postgres', '-s', '/bin/bash', '-c', cmd], { encoding: 'utf8' });
const sql = (q) => asPg(
  `psql -h ${SOCK} -p ${PORT} -U postgres -d rls -tAq -c ${JSON.stringify(q.replace(/\s+/g, ' ').trim())}`
).trim();

/* One question, asked as somebody. `set local` inside a transaction is how
   PostgREST hands a request its role and its claims, so this is the same
   shape a real call arrives in. */
const asRole = (role, email, q) => {
  const claims = email ? `set local request.jwt.claims = '${JSON.stringify({ email, role })}';` : '';
  return sql(`begin; set local role ${role}; ${claims} ${q}; rollback;`);
};
const denied = (role, email, q) => {
  try { const r = asRole(role, email, q); return r === '0' || r === ''; }
  catch (e) { return /permission denied|policy/i.test(String(e.stderr || e.message)); }
};
const refused = (role, email, q) => {
  try { asRole(role, email, q); return false; }
  catch (e) { return /policy|permission denied/i.test(String(e.stderr || e.message)); }
};

if (!fs.existsSync(PGBIN + '/initdb')) {
  console.log('SKIP no Postgres at ' + PGBIN + ': the policies are unverified in this environment');
  process.exit(0);
}

try {
  execFileSync('bash', ['-c', `rm -rf ${DIR} ${SOCK}; mkdir -p ${DIR} ${SOCK}; chown -R postgres:postgres ${DIR} ${SOCK}`]);
  asPg(`${PGBIN}/initdb -D ${DIR} -U postgres --auth=trust`);
  asPg(`${PGBIN}/pg_ctl -D ${DIR} -o "-p ${PORT} -k ${SOCK} -c listen_addresses=" -l ${DIR}/log start`);
  asPg(`psql -h ${SOCK} -p ${PORT} -U postgres -q -c "create database rls;"`);

  const whole = fs.readFileSync(T + '/../supabase/schema.sql', 'utf8');
  const cut = (from, to) => {
    const a = whole.indexOf(from);
    const b = to ? whole.indexOf(to) : whole.length;
    if (a < 0 || b < a) throw new Error('schema marker moved: ' + from);
    return whole.slice(a, b);
  };
  const runFile = (name, body) => {
    fs.writeFileSync(SOCK + '/' + name, body);
    execFileSync('bash', ['-c', `chmod 644 ${SOCK}/${name}`]);
    asPg(`psql -h ${SOCK} -p ${PORT} -U postgres -d rls -v ON_ERROR_STOP=1 -q -f ${SOCK}/${name}`);
  };

  // The two functions every policy below rests on, taken from the real file.
  const isTeam = cut('create or replace function public.is_team()', 'grant execute on function public.is_team()');
  const allowed = cut('create or replace function public.allowed(flag text)', 'grant execute on function public.allowed');
  const policies = cut('do $$\ndeclare\n  r record;');

  runFile('rls-setup.sql', `
create extension if not exists pgcrypto;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
end $$;

/* auth.jwt() as Supabase defines it: the request's claims, handed in by
   PostgREST as a setting. */
create schema if not exists auth;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;

create table public.team_members (
  id uuid primary key default gen_random_uuid(), name text not null, email text,
  role text not null default 'sales', active boolean not null default true,
  is_admin boolean not null default false,
  can_clients boolean not null default true, can_review boolean not null default false,
  can_campaigns boolean not null default false, can_links boolean not null default false,
  can_activity boolean not null default false, can_billing boolean not null default true,
  can_remove boolean not null default false);

create table public.clients (id uuid primary key default gen_random_uuid(), name text not null);
create table public.client_contacts (
  id uuid primary key default gen_random_uuid(), client_id uuid references public.clients(id),
  name text not null, email text, portal_access boolean not null default false,
  archived_at timestamptz);
create table public.client_touches (
  id uuid primary key default gen_random_uuid(), client_id uuid references public.clients(id), note text);
create table public.batches (
  id uuid primary key default gen_random_uuid(), client_id uuid references public.clients(id), title text);
create table public.posts (
  id uuid primary key default gen_random_uuid(), batch_id uuid references public.batches(id), caption text);
create table public.reviews (
  id uuid primary key default gen_random_uuid(), post_id uuid references public.posts(id), decision text);
create table public.drive_assets (id uuid primary key default gen_random_uuid(), name text);
create table public.creators (
  id uuid primary key default gen_random_uuid(), name text not null, client_rate numeric(12,2));
create table public.creator_profiles (
  id uuid primary key default gen_random_uuid(), creator_id uuid references public.creators(id),
  platform text, url text);
create table public.campaigns (
  id uuid primary key default gen_random_uuid(), client_id uuid references public.clients(id), title text);
create table public.campaign_options (
  id uuid primary key default gen_random_uuid(), campaign_id uuid references public.campaigns(id),
  creator_id uuid references public.creators(id), rate numeric(12,2), state text default 'option');
create table public.campaign_confirmations (
  id uuid primary key default gen_random_uuid(), campaign_id uuid references public.campaigns(id), person text);
create table public.option_posts (
  id uuid primary key default gen_random_uuid(), option_id uuid references public.campaign_options(id), platform text);
create table public.option_reviews (
  id uuid primary key default gen_random_uuid(), option_id uuid references public.campaign_options(id), decision text);
create table public.links (id uuid primary key default gen_random_uuid(), slug text, target text);
create table public.link_qrs (id uuid primary key default gen_random_uuid(), link_id uuid references public.links(id));

grant usage on schema public, auth to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
grant execute on all functions in schema auth to anon, authenticated;

` + isTeam + allowed + `
grant execute on function public.is_team() to anon, authenticated;
grant execute on function public.allowed(text) to anon, authenticated;
`);

  // Synthetic people. Two clients at different companies, three colleagues.
  sql(`insert into public.team_members (name, email, role, is_admin, can_clients, can_review,
        can_campaigns, can_links, can_remove) values
        ('Admin One',  'admin@example.test',     'admin', true,  true, true,  true,  true,  true),
        ('Mktg One',   'marketing@example.test', 'account', false, true, true,  true,  true,  false),
        ('Sales One',  'sales@example.test',     'sales', false, true, false, false, false, false),
        ('Left Us',    'former@example.test',    'account', false, true, true,  true,  true,  true)`);
  sql(`update public.team_members set active = false where email = 'former@example.test'`);
  sql(`insert into public.clients (name) values ('Client A Sdn Bhd'), ('Client B Sdn Bhd')`);
  const cA = sql(`select id from public.clients where name like 'Client A%'`);
  const cB = sql(`select id from public.clients where name like 'Client B%'`);
  sql(`insert into public.client_contacts (client_id, name, email, portal_access) values
        ('${cA}', 'Ah Meng', 'a.person@clienta.test', true),
        ('${cB}', 'Siti',    'b.person@clientb.test', true)`);
  sql(`insert into public.client_touches (client_id, note) values ('${cA}', 'Called about the retainer')`);
  sql(`insert into public.batches (client_id, title) values ('${cA}', 'Oct 2026')`);
  sql(`insert into public.posts (batch_id, caption) select id, 'A caption' from public.batches`);
  sql(`insert into public.reviews (post_id, decision) select id, 'approved' from public.posts`);
  sql(`insert into public.drive_assets (name) values ('a-file.jpg')`);
  sql(`insert into public.creators (name, client_rate) values ('Creator One', 360)`);
  sql(`insert into public.creator_profiles (creator_id, platform, url)
       select id, 'rednote', 'https://example.test/p' from public.creators`);
  sql(`insert into public.campaigns (client_id, title) values ('${cA}', 'Raya Launch')`);
  sql(`insert into public.campaign_options (campaign_id, creator_id, rate)
       select c.id, cr.id, 360 from public.campaigns c, public.creators cr`);
  sql(`insert into public.campaign_confirmations (campaign_id, person)
       select id, 'Ah Meng' from public.campaigns`);
  sql(`insert into public.option_posts (option_id, platform) select id, 'rednote' from public.campaign_options`);
  sql(`insert into public.option_reviews (option_id, decision) select id, 'changes' from public.campaign_options`);
  sql(`insert into public.links (slug, target) values ('demo', 'https://example.test')`);
  sql(`insert into public.link_qrs (link_id) select id from public.links`);

  const GATED = ['batches','posts','reviews','drive_assets','campaigns','campaign_options',
    'campaign_confirmations','option_posts','option_reviews','creators','creator_profiles',
    'client_contacts','client_touches','links','link_qrs'];

  /* ---- Before: every one of them wide open to any signed-in account -----
     Under the names production actually carries, so the guard below is asked
     the same question a real run asks it. */
  const LEGACY = {
    batches: 'team_all', posts: 'team_all', reviews: 'team_all', drive_assets: 'team_all',
    campaigns: 'campaigns_team', campaign_options: 'campaign_options_team',
    campaign_confirmations: 'campaign_conf_team', option_posts: 'option_posts_team',
    option_reviews: 'option_reviews_team', creators: 'creators_team',
    creator_profiles: 'creator_profiles_team', client_contacts: 'contacts staff',
    client_touches: 'touches staff', links: 'links_team', link_qrs: 'link_qrs_team'
  };
  runFile('rls-open.sql', GATED.map(t =>
    `alter table public.${t} enable row level security;
     drop policy if exists "${LEGACY[t]}" on public.${t};
     create policy "${LEGACY[t]}" on public.${t} for all to authenticated using (true) with check (true);
     grant all on public.${t} to anon, authenticated;`
  ).join('\n'));

  const clientSees = GATED.filter(t =>
    asRole('authenticated', 'a.person@clienta.test', `select count(*) from public.${t}`) !== '0');
  check('before: a signed-in client can read every gated table',
    clientSees.length === GATED.length, clientSees.length + ' of ' + GATED.length);
  check('before: and can read another client\'s contacts',
    asRole('authenticated', 'a.person@clienta.test',
      `select count(*) from public.client_contacts where client_id = '${cB}'`) === '1');
  check('before: and can read a creator\'s fee',
    asRole('authenticated', 'a.person@clienta.test',
      `select client_rate::text from public.creators`) === '360.00');

  /* A token page's way in, made before the fix so it can be called after it.
     Definer functions run as the owner: they are not subject to RLS and need
     no privilege from their caller, which is what makes revoking anon's table
     grants safe. */
  runFile('rls-definer.sql', `
create or replace function public.demo_token_read(p_token text)
returns jsonb language sql security definer stable set search_path = public as $$
  select case when p_token = 'goodtoken' then jsonb_build_object(
    'campaigns', (select count(*) from campaigns),
    'creators',  (select count(*) from creators),
    'posts',     (select count(*) from posts)) else jsonb_build_object('error','no') end
$$;
grant execute on function public.demo_token_read(text) to anon, authenticated;`);

  /* The guard: the migration drops by what is there, so it must refuse to run
     while something nobody has reviewed is sitting on a gated table. */
  sql(`create policy zz_unreviewed on public.links for select to authenticated using (true)`);
  let guarded = false;
  try { runFile('rls-policies.sql', policies); }
  catch (e) { guarded = /Unreviewed policy on a gated table/.test(String(e.stderr || e.message)); }
  check('an unreviewed policy stops the migration rather than being deleted', guarded);
  check('and nothing was changed when it stopped',
    sql(`select count(*) from pg_policies where schemaname='public'
         and tablename='links' and policyname='links_sel'`) === '0');
  sql(`drop policy zz_unreviewed on public.links`);

  // ---- The fix ----
  runFile('rls-policies.sql', policies);
  console.log('ok   the policy block applies to a real Postgres');
  runFile('rls-policies.sql', policies);
  console.log('ok   and applies again unchanged');

  check('no policy anywhere is left unrestricted',
    sql(`select count(*) from pg_policies where schemaname = 'public'
         and (qual = 'true' or with_check = 'true')`) === '0',
    sql(`select coalesce(string_agg(tablename || '.' || policyname, ', '), 'none')
         from pg_policies where schemaname='public' and (qual='true' or with_check='true')`));
  check('and each gated table separates its four commands',
    sql(`select count(*) from pg_policies where schemaname='public'
         and tablename = any(array[${GATED.map(t => `'${t}'`).join(',')}])`) === String(GATED.length * 4));

  // ---- An admin keeps everything ----
  const adminBlocked = GATED.filter(t =>
    asRole('authenticated', 'admin@example.test', `select count(*) from public.${t}`) === '0');
  check('an admin still reads every gated table', adminBlocked.length === 0, adminBlocked.join(', '));
  check('and can still write one',
    asRole('authenticated', 'admin@example.test',
      `insert into public.links (slug, target) values ('new', 'https://example.test') returning slug`) === 'new');
  check('and can still delete one',
    asRole('authenticated', 'admin@example.test',
      `delete from public.client_touches returning 1`) === '1');

  // ---- Marketing: its own sections, and not the switch it does not hold ----
  check('Marketing reads campaigns',
    asRole('authenticated', 'marketing@example.test', `select count(*) from public.campaign_options`) === '1');
  check('and reads content sets',
    asRole('authenticated', 'marketing@example.test', `select count(*) from public.posts`) === '1');
  check('but cannot delete a contact, which needs the remove switch',
    denied('authenticated', 'marketing@example.test', `delete from public.client_contacts returning 1`));
  check('while it can still edit one',
    asRole('authenticated', 'marketing@example.test',
      `update public.client_contacts set name = 'Ah Meng Jr' returning name`).includes('Ah Meng Jr'));

  // ---- Sales: the console hides those sections, and now so does the database ----
  check('Sales cannot read campaign options',
    denied('authenticated', 'sales@example.test', `select count(*) from public.campaign_options`));
  check('nor a creator fee',
    denied('authenticated', 'sales@example.test', `select count(*) from public.creators`));
  check('nor the content of a review',
    denied('authenticated', 'sales@example.test', `select count(*) from public.posts`));
  check('but still sees Engagements on a client record',
    asRole('authenticated', 'sales@example.test', `select count(*) from public.campaigns`) === '1');
  check('and the content sets listed beside them',
    asRole('authenticated', 'sales@example.test', `select count(*) from public.batches`) === '1');
  check('and cannot write a campaign it may read',
    refused('authenticated', 'sales@example.test',
      `insert into public.campaigns (client_id, title) values ('${cA}', 'Mine now')`));

  // ---- A client at Client A ----
  const aStill = GATED.filter(t =>
    asRole('authenticated', 'a.person@clienta.test', `select count(*) from public.${t}`) !== '0');
  check('a signed-in client reads nothing from any gated table',
    aStill.length === 0, aStill.join(', '));
  check('and cannot reach Client B\'s contacts',
    denied('authenticated', 'a.person@clienta.test',
      `select count(*) from public.client_contacts where client_id = '${cB}'`));
  check('and cannot reach a creator\'s fee',
    denied('authenticated', 'a.person@clienta.test', `select count(*) from public.creators`));
  check('and cannot write anything',
    refused('authenticated', 'a.person@clienta.test',
      `insert into public.links (slug, target) values ('theirs', 'https://example.test')`));

  // ---- A client at Client B, and a creator, who holds no account at all ----
  const bStill = GATED.filter(t =>
    asRole('authenticated', 'b.person@clientb.test', `select count(*) from public.${t}`) !== '0');
  check('a client at another company reads nothing either', bStill.length === 0, bStill.join(', '));
  check('an address on no list at all reads nothing',
    GATED.every(t => asRole('authenticated', 'someone@nowhere.test',
      `select count(*) from public.${t}`) === '0'));
  check('and a colleague who was stood down reads nothing',
    GATED.every(t => asRole('authenticated', 'former@example.test',
      `select count(*) from public.${t}`) === '0'));

  /* ---- Anonymous ----
     `denied` counts both answers: no rows, or refused outright. After the
     revoke it is refused, which is the stronger of the two. */
  const anonStill = GATED.filter(t => !denied('anon', null, `select count(*) from public.${t}`));
  check('an anonymous visitor reads nothing', anonStill.length === 0, anonStill.join(', '));
  check('and writes nothing',
    refused('anon', null, `insert into public.links (slug, target) values ('anon', 'https://example.test')`));

  /* ---- anon holds nothing directly, and the token pages still work ----- */
  check('anon holds no direct privilege on any gated table',
    sql(`select count(*) from information_schema.role_table_grants
         where table_schema='public' and grantee='anon'
           and table_name = any(array[${GATED.map(t => `'${t}'`).join(',')}])`) === '0',
    sql(`select coalesce(string_agg(distinct table_name, ', '), 'none')
         from information_schema.role_table_grants where table_schema='public'
         and grantee='anon' and table_name = any(array[${GATED.map(t => `'${t}'`).join(',')}])`));
  check('so a direct read as anon is refused outright',
    refused('anon', null, `select count(*) from public.creators`));

  // /creators/, /creator/ and /review/ all arrive this way and must still pass.
  check('a campaign token page still reads its campaign',
    asRole('anon', null, `select public.demo_token_read('goodtoken')->>'campaigns'`) === '1',
    'definer runs as the owner, so the revoke costs it nothing');
  check('a creator code page still reads its booking',
    asRole('anon', null, `select public.demo_token_read('goodtoken')->>'creators'`) === '1');
  check('a review token page still reads its posts',
    asRole('anon', null, `select public.demo_token_read('goodtoken')->>'posts'`) === '1');
  check('and a wrong token still gets nothing',
    asRole('anon', null, `select public.demo_token_read('wrong')->>'error'`) === 'no');
  check('a signed-in client page still reads through its own function',
    asRole('authenticated', 'a.person@clienta.test',
      `select public.demo_token_read('goodtoken')->>'creators'`) === '1');
} catch (e) {
  console.log('FAIL ' + (e.stderr ? String(e.stderr).slice(0, 900) : e.message));
  fails++;
} finally {
  try { asPg(`${PGBIN}/pg_ctl -D ${DIR} -m immediate stop`); } catch (e) {}
  try { execFileSync('bash', ['-c', `rm -rf ${DIR} ${SOCK}`]); } catch (e) {}
}

console.log(fails ? 'rls: PROBLEM (' + fails + ' fail)' : 'rls: ok');
process.exit(fails ? 1 : 0);
