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
  const repair = cut('-- TEAM LIST REPAIR', '-- ONE PERSON, ONE SIDE');
  const overlap = cut('create or replace function public.no_team_client_overlap',
                      '-- And if an overlap ever exists anyway');
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

  /* One person, one side. The two lists answer different questions, so
     nothing stopped an address sitting in both: that is exactly how a client
     contact became an Account with read and write over every client. */
  runFile('overlap.sql', overlap);
  const refuses = (q) => {
    try { sql(q); return false; } catch (e) { return /cannot also/.test(String(e.stderr || e.message)); }
  };
  check('a colleague cannot be given a client portal sign-in',
    refuses(`insert into public.client_contacts (name, email, portal_access)
             values ('Kaylyn', 'kaylyn@adspacestudios.com', true)`));
  check('and a client portal contact cannot be put on the team',
    refuses(`insert into public.team_members (name, email, active)
             values ('Sean', 'sean@example.com', true)`));
  // A contact may exist with the same address; it is turning access on that
  // is refused, because that is the moment the two sides would overlap.
  sql(`insert into public.client_contacts (name, email, portal_access)
       values ('Admin at a client', 'adspacestudios@gmail.com', false)`);
  check('a colleague may be listed as a contact without portal access',
    sql(`select portal_access from public.client_contacts where email='adspacestudios@gmail.com'`) === 'f');
  check('turning access on later is refused the same way',
    refuses(`update public.client_contacts set portal_access = true
             where email = 'adspacestudios@gmail.com'`));

  // An address on one side only is untouched, and so is an ordinary edit.
  sql(`insert into public.client_contacts (name, email, portal_access)
       values ('Ms Fresh', 'fresh@example.com', true)`);
  check('an address on one side only is let through',
    sql(`select portal_access from public.client_contacts where email='fresh@example.com'`) === 't');
  sql(`update public.client_contacts set name = 'Ms Fresher' where email = 'fresh@example.com'`);
  check('and an edit that does not touch access or the address still saves',
    sql(`select name from public.client_contacts where email='fresh@example.com'`) === 'Ms Fresher');

  // Standing a team row down is how the repair works, so it must stay allowed.
  check('a team row can still be stood down',
    sql(`update public.team_members set active = false where email = 'kaylyn@adspacestudios.com'
         returning active`) === 'f');

  /* ---- The rate card seeds once ----------------------------------------
   * An admin can now delete a rate card line for good, and the seed used to
   * run on every pass of the file, so the next schema change would have put
   * the deleted line straight back. `on conflict do nothing` does not save
   * it: the row is gone, so there is no conflict. Nothing in the browser
   * suites runs the seed, which is why this is here. */
  const seed = cut('-- The rate card is seeded once', '-- What a client asked for');
  runFile('rates-setup.sql', `
drop table if exists public.services cascade;
create table public.services (
  slug text primary key, category text not null, name text not null,
  rate numeric(12,2), unit text, position int not null default 0,
  active boolean not null default true, note text, detail text,
  min_months int not null default 1);
` + seed);
  const seeded = Number(sql('select count(*) from public.services'));
  check('the rate card seeds into an empty table', seeded > 20, seeded + ' lines');

  sql("delete from public.services where slug = 'urgent'");
  sql("update public.services set rate = 999 where slug = 'gif'");
  runFile('rates-again.sql', seed);
  check('a line an admin deleted stays deleted on the next run',
    sql("select count(*) from public.services where slug = 'urgent'") === '0');
  check('and a rate somebody corrected is not seeded back over',
    sql("select rate from public.services where slug = 'gif'") === '999.00');
  check('and the rest of the card is untouched',
    Number(sql('select count(*) from public.services')) === seeded - 1);

  /* ---- What a creator hands in ----------------------------------------
   * creator_add_file declared a variable called `id` and then looked the
   * booking up with an unqualified `where id = p_option`. PL/pgSQL raises
   * that ambiguity at run time, not at create time, so the schema applied
   * cleanly, every browser suite stayed green against the stand-in, and
   * every upload in production failed. The whole delivery path is run here
   * for real: sign the upload, record the file, submit, read it back. */
  const deliver = cut('-- CREATOR ACCESS AND DELIVERY', '-- Taking a code back.');
  runFile('creator-setup.sql', `
drop table if exists public.campaign_deliverables cascade;
drop table if exists public.campaign_options cascade;
drop table if exists public.creator_profiles cascade;
drop table if exists public.option_posts cascade;
drop table if exists public.campaigns cascade;
drop table if exists public.creators cascade;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
end $$;
create table public.creators (
  id uuid primary key default gen_random_uuid(), name text not null,
  access_code text, code_issued_at timestamptz, active boolean not null default true);
create table public.campaigns (
  id uuid primary key default gen_random_uuid(), client_id uuid references public.clients(id),
  title text not null, title_zh text, state text not null default 'open',
  brief text, brief_zh text, due_date date, push_format text);
create table public.campaign_options (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid references public.campaigns(id), creator_id uuid references public.creators(id),
  rate numeric(12,2), platforms text, state text not null default 'confirmed',
  is_replacement boolean default false, added_at timestamptz default now(), position int default 0,
  visit_date date, visit_time text, visit_location text, visit_pic text, visit_pic_phone text,
  tracking_no text, draft_url text, revision_round integer not null default 0,
  planned_publish date, drop_reason text);
create table public.creator_profiles (id uuid primary key default gen_random_uuid(),
  creator_id uuid references public.creators(id), platform text, url text);
create table public.option_posts (id uuid primary key default gen_random_uuid(),
  option_id uuid references public.campaign_options(id), platform text, post_url text,
  published_at date, window_days int, impressions bigint, engagements bigint, views bigint,
  measured_at timestamptz);
alter table public.clients add column if not exists logo_url text;
alter table public.clients add column if not exists market text default 'MY';
alter table public.clients add column if not exists sst_applies boolean default true;
create or replace function public.is_team() returns boolean language sql stable as $$ select true $$;
` + deliver);
  console.log('ok   the creator delivery block applies to a real Postgres');

  sql(`insert into public.creators (name) values ('Ah Girl')`);
  sql(`insert into public.clients (name) values ('HKL Lim')`);
  sql(`insert into public.campaigns (client_id, title) select id, 'Raya' from public.clients where name='HKL Lim'`);
  sql(`insert into public.campaign_options (campaign_id, creator_id, rate, platforms, state)
       select c.id, cr.id, 360, 'rednote, Instagram', 'pending_draft'
       from public.campaigns c, public.creators cr where cr.name = 'Ah Girl'`);
  const code = sql(`select access_code from public.creators where name='Ah Girl'`);
  const opt = sql(`select id from public.campaign_options limit 1`);
  check('every creator is issued a code', /^[A-Z0-9]{8}$/.test(code), code);
  check('the edge function is told the upload is allowed',
    sql(`select public.creator_may_upload('${code}', '${opt}')`) === 't');

  // The defect: this returned an ambiguity error, the page swallowed it, and
  // the creator watched a full progress bar over an empty submission.
  const added = sql(`select public.creator_add_file('${code}', '${opt}',
    'https://mycdn.adspace.me/content/creator/x.mp4', 'reel.mp4', 'video', 314572800)`);
  check('a file a creator uploads is recorded', /"id"/.test(added), added);
  check('and lands in the round being worked on',
    sql(`select round from public.campaign_deliverables`) === '1');
  check('the team reads it back off the table they query',
    sql(`select name from public.campaign_deliverables where removed_at is null`) === 'reel.mp4');

  // Several files per booking: a post is a cover and four slides.
  sql(`select public.creator_add_file('${code}', '${opt}', 'https://x/2.jpg', 'slide.jpg', 'image', 900)`);
  check('several files can be added to one booking',
    sql(`select count(*) from public.campaign_deliverables where removed_at is null`) === '2');

  check('submitting moves the step to reviewing',
    /"ok": true/.test(sql(`select public.creator_submit('${code}', '${opt}', 'Raya at home')`)));
  check('and the caption they wrote is kept',
    sql(`select draft_caption from public.campaign_options`) === 'Raya at home');
  check('and the team sees the step change',
    sql(`select state from public.campaign_options`) === 'reviewing');

  // Closed once it is in: a × on a submitted file would empty a review.
  check('a file cannot be taken back once it is submitted',
    /"error": "not-found"/.test(sql(`select public.creator_remove_file('${code}',
      (select id from public.campaign_deliverables limit 1))`)));
  check('and no further file can be added',
    /"error": "closed"/.test(sql(`select public.creator_add_file('${code}', '${opt}',
      'https://x/3.jpg', 'late.jpg', 'image', 900)`)));

  // An invalid code reaches nothing at all.
  check('an invalid code is refused',
    /"error": "not-found"/.test(sql(`select public.creator_add_file('ZZZZZZZZ', '${opt}',
      'https://x/4.jpg', 'no.jpg', 'image', 900)`)));
  check('and cannot sign an upload',
    sql(`select public.creator_may_upload('ZZZZZZZZ', '${opt}')`) === 'f');
} catch (e) {
  console.log('FAIL ' + (e.stderr ? String(e.stderr).slice(0, 600) : e.message));
  fails++;
} finally {
  try { asPg(`${PGBIN}/pg_ctl -D ${DIR} -m immediate stop`); } catch (e) {}
  try { execFileSync('bash', ['-c', `rm -rf ${DIR} ${SOCK}`]); } catch (e) {}
}

console.log(fails ? 'sql: PROBLEM (' + fails + ' fail)' : 'sql: ok');
process.exit(fails ? 1 : 0);
