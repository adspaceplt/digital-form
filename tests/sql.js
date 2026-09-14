/* The schema, run against a real Postgres.
 *
 * Everything else in tests/ drives a browser against a stand-in, so a trigger
 * written in PL/pgSQL was the one part of this portal nothing checked. That is
 * exactly where the stage clock broke: the trigger forced the old values back
 * on every update, which silently threw away the migration's own backfill, and
 * every suite stayed green because none of them runs SQL.
 *
 * This starts a throwaway cluster, applies the stage clock section of
 * supabase/schema.sql, and asserts what the trigger is for. It skips loudly
 * rather than quietly when Postgres is not installed, because a check that
 * disappears without saying so is worse than no check.
 */
const { execFileSync } = require('child_process');
const fs = require('fs');
const T = process.argv[2];
const PGBIN = '/usr/lib/postgresql/16/bin';
const DIR = '/tmp/pgclock';
const SOCK = '/tmp/pgclocksock';
const PORT = '55433';

let fails = 0;
const check = (name, ok, note) => {
  console.log((ok ? 'ok   ' : 'FAIL ') + name + (note ? '  ' + note : ''));
  if (!ok) fails++;
};
const asPg = (cmd) => execFileSync('su', ['postgres', '-s', '/bin/bash', '-c', cmd], { encoding: 'utf8' });
// Flattened: JSON.stringify would hand psql a literal backslash-n, which it
// reads as the start of a meta-command rather than as whitespace.
const sql = (q) => asPg(
  `psql -h ${SOCK} -p ${PORT} -U postgres -d clock -tAq -c ${JSON.stringify(q.replace(/\s+/g, ' ').trim())}`
).trim();

if (!fs.existsSync(PGBIN + '/initdb')) {
  console.log('SKIP no Postgres at ' + PGBIN + ': the schema is unverified in this environment');
  process.exit(0);
}

try {
  execFileSync('bash', ['-c', `rm -rf ${DIR} ${SOCK}; mkdir -p ${DIR} ${SOCK}; chown -R postgres:postgres ${DIR} ${SOCK}`]);
  asPg(`${PGBIN}/initdb -D ${DIR} -U postgres --auth=trust`);
  asPg(`${PGBIN}/pg_ctl -D ${DIR} -o "-p ${PORT} -k ${SOCK} -c listen_addresses=" -l ${DIR}/log start`);
  asPg(`psql -h ${SOCK} -p ${PORT} -U postgres -q -c "create database clock;"`);

  // Just the clock, on a clients table with the columns it touches. The rest
  // of the schema expects a live Supabase to already carry its tables.
  const whole = fs.readFileSync(T + '/../supabase/schema.sql', 'utf8');
  /* Each section is taken by the words that head it, so a section that moves
     or is renamed fails the suite loudly instead of testing an empty string. */
  const cut = (from, to) => {
    const a = whole.indexOf(from);
    const b = to ? whole.indexOf(to) : whole.length;
    if (a < 0 || b < a) throw new Error('schema marker moved: ' + from);
    return whole.slice(a, b);
  };
  const block = cut('-- STAGE TIMING', '-- TEAM LIST REPAIR');
  const setup = `drop table if exists public.clients cascade;
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  stage text not null default 'lead',
  created_at timestamptz not null default now()
);
` + block;
  fs.writeFileSync(SOCK + '/clock.sql', setup);
  execFileSync('bash', ['-c', `chmod 644 ${SOCK}/clock.sql`]);
  asPg(`psql -h ${SOCK} -p ${PORT} -U postgres -d clock -v ON_ERROR_STOP=1 -q -f ${SOCK}/clock.sql`);
  console.log('ok   the stage clock applies to a real Postgres');

  // A client that predates the clock: created five days ago, nothing stamped.
  sql(`alter table public.clients disable trigger clients_stage_clock`);
  sql(`insert into public.clients (name, stage, created_at, stage_since, stage_log)
       values ('Old', 'lead', now() - interval '5 days', null, '[]'::jsonb)`);
  sql(`alter table public.clients enable trigger clients_stage_clock`);

  // The backfill, exactly as the migration runs it. This is the assertion the
  // original bug would have failed: the trigger overwrote it and the clock
  // never started.
  const backfill = block.slice(block.indexOf('update public.clients set stage_since = created_at'));
  fs.writeFileSync(SOCK + '/backfill.sql', backfill);
  execFileSync('bash', ['-c', `chmod 644 ${SOCK}/backfill.sql`]);
  asPg(`psql -h ${SOCK} -p ${PORT} -U postgres -d clock -v ON_ERROR_STOP=1 -q -f ${SOCK}/backfill.sql`);

  check('the backfill survives the trigger and starts the clock',
    sql(`select round(extract(epoch from (now() - stage_since))/86400) from public.clients where name='Old'`) === '5',
    'days in stage: ' + sql(`select round(extract(epoch from (now() - stage_since))/86400) from public.clients where name='Old'`));
  check('and the history begins when the client did',
    sql(`select (stage_log->0->>'at')::date = created_at::date from public.clients where name='Old'`) === 't');

  // A save that does not mention the stage must leave the clock alone, or a
  // stalled lead looks freshly worked every time somebody opens it.
  sql(`update public.clients set name = 'Old two' where name = 'Old'`);
  check('a plain save does not restart the clock',
    sql(`select round(extract(epoch from (now() - stage_since))/86400) from public.clients where name='Old two'`) === '5');

  // A real move does restart it, and appends.
  sql(`update public.clients set stage = 'contacted' where name = 'Old two'`);
  check('a real move restarts the clock',
    sql(`select round(extract(epoch from (now() - stage_since))/86400) from public.clients where name='Old two'`) === '0');
  check('and appends to the history rather than replacing it',
    sql(`select jsonb_array_length(stage_log) || ':' || (stage_log->0->>'stage') || '>' || (stage_log->1->>'stage')
         from public.clients where name='Old two'`) === '2:lead>contacted');

  // A row damaged by the original bug: its history starts at the move, not at
  // its creation. Re-running the schema repairs it.
  sql(`alter table public.clients disable trigger clients_stage_clock`);
  sql(`insert into public.clients (name, stage, created_at, stage_since, stage_log)
       values ('Damaged', 'contacted', now() - interval '5 days', now(),
               jsonb_build_array(jsonb_build_object('stage','contacted','at', now())))`);
  sql(`alter table public.clients enable trigger clients_stage_clock`);
  asPg(`psql -h ${SOCK} -p ${PORT} -U postgres -d clock -v ON_ERROR_STOP=1 -q -f ${SOCK}/backfill.sql`);
  check('re-running the schema repairs a history that began at the migration',
    sql(`select jsonb_array_length(stage_log) || ':' || (stage_log->0->>'stage') || '@' ||
                ((stage_log->0->>'at')::date = created_at::date)
         from public.clients where name='Damaged'`) === '2:lead@true');

  // And it is idempotent: running it twice must not prepend a second lead.
  asPg(`psql -h ${SOCK} -p ${PORT} -U postgres -d clock -v ON_ERROR_STOP=1 -q -f ${SOCK}/backfill.sql`);
  check('and running it again changes nothing',
    sql(`select jsonb_array_length(stage_log) from public.clients where name='Damaged'`) === '2');

  /* The team list, and who is allowed onto it.
   *
   * Clients have logins now, so auth.users is not a list of colleagues. The
   * cutover sweep took every address in it, which handed a client's contact
   * an active team row the moment they were granted portal access: read and
   * write over every client, and a name in the Person in charge list. Both
   * the guard and the repair are asserted here against a real Postgres,
   * because both are plain SQL that nothing in the browser suites can run. */
  const sweep = cut('/* The cutover, and only the cutover', '-- The first admin.');
  const repair = cut('-- TEAM LIST REPAIR');
  const runFile = (name, body) => {
    fs.writeFileSync(SOCK + '/' + name, body);
    execFileSync('bash', ['-c', `chmod 644 ${SOCK}/${name}`]);
    asPg(`psql -h ${SOCK} -p ${PORT} -U postgres -d clock -v ON_ERROR_STOP=1 -q -f ${SOCK}/${name}`);
  };

  runFile('team-setup.sql', `
create schema if not exists auth;
drop table if exists auth.users cascade;
create table auth.users (id uuid primary key default gen_random_uuid(),
  email text, raw_user_meta_data jsonb);
drop table if exists public.team_members cascade;
create table public.team_members (
  id uuid primary key default gen_random_uuid(), name text not null, email text,
  role text not null default 'sales', active boolean not null default true,
  is_admin boolean not null default false, can_clients boolean not null default true,
  created_at timestamptz not null default now());
drop table if exists public.client_contacts cascade;
create table public.client_contacts (
  id uuid primary key default gen_random_uuid(), name text not null, email text,
  portal_access boolean not null default false, archived_at timestamptz);
insert into auth.users (email, raw_user_meta_data) values
  ('adspacestudios@gmail.com', '{"name":"Admin"}'::jsonb),
  ('sean@example.com', '{"name":"Sean"}'::jsonb);
insert into public.client_contacts (name, email, portal_access) values
  ('Sean', 'sean@example.com', true);
`);

  runFile('team-sweep.sql', sweep);
  check('the cutover sweep never takes a client contact onto the team',
    sql(`select count(*) from public.team_members where lower(email)='sean@example.com'`) === '0');
  check('and it still carries the team across on a fresh database',
    sql(`select name from public.team_members`) === 'Admin');

  // A second run must not resurrect anyone: the team list is no longer empty,
  // so the sweep is finished for good.
  sql(`insert into auth.users (email, raw_user_meta_data) values ('gone@example.com', '{}'::jsonb)`);
  runFile('team-sweep.sql', sweep);
  check('and it does not run again once the team list exists',
    sql(`select count(*) from public.team_members`) === '1');

  // The damage the old sweep already did, and the two rows the repair must
  // not touch: an admin, and one of our own addresses.
  sql(`insert into public.team_members (name, email, role, is_admin) values
        ('Sean', 'sean@example.com', 'account', false),
        ('Boss', 'boss@example.com', 'admin', true),
        ('Kaylyn', 'kaylyn@adspacestudios.com', 'account', false)`);
  sql(`insert into public.client_contacts (name, email, portal_access) values
        ('Boss', 'boss@example.com', true),
        ('Kaylyn', 'kaylyn@adspacestudios.com', true)`);
  runFile('team-repair.sql', repair);
  check('the repair stands a client contact down off the team',
    sql(`select active from public.team_members where email='sean@example.com'`) === 'f');
  check('and leaves an admin and one of our own addresses active',
    sql(`select count(*) from public.team_members where active and email in
         ('boss@example.com','kaylyn@adspacestudios.com')`) === '2');

  runFile('team-repair.sql', repair);
  check('and running the repair again changes nothing',
    sql(`select count(*) from public.team_members where active`) === '3');
} catch (e) {
  console.log('FAIL ' + (e.stderr ? String(e.stderr).slice(0, 600) : e.message));
  fails++;
} finally {
  try { asPg(`${PGBIN}/pg_ctl -D ${DIR} -m immediate stop`); } catch (e) {}
  try { execFileSync('bash', ['-c', `rm -rf ${DIR} ${SOCK}`]); } catch (e) {}
}

console.log(fails ? 'sql: PROBLEM (' + fails + ' fail)' : 'sql: ok');
process.exit(fails ? 1 : 0);
