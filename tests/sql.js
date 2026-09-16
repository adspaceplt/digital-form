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
  brief text, brief_zh text, due_date date, push_format text,
  purpose text, purpose_zh text, slots int default 4, backups_open boolean default false,
  deadline date, deliverable text, invoice_no text, invoice_url text,
  access_token text, passcode text);
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
drop table if exists public.option_reviews cascade;
create table public.option_reviews (
  id uuid primary key default gen_random_uuid(),
  option_id uuid references public.campaign_options(id), round int, decision text,
  note text, reviewer text, at timestamptz not null default now());
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

  check('submitting reaches the team, not the client',
    /"ok": true/.test(sql(`select public.creator_submit('${code}', '${opt}', 'Raya at home')`)));
  check('and the caption they wrote is kept',
    sql(`select draft_caption from public.campaign_options`) === 'Raya at home');
  check('and the step is Submitted, which is ours',
    sql(`select state from public.campaign_options`) === 'submitted');

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

  /* The migration that ships this fix is applied by hand, so it has to stand
     on its own and be safe to run twice. Re-running the whole schema for one
     function would also re-apply fifteen unrelated data migrations and drop
     and recreate fifty-six policies and triggers on a live database, which is
     why the narrow file exists. */
  const mig = fs.readFileSync(T + '/../supabase/migrations/2026-09-15-creator-add-file.sql', 'utf8');
  runFile('creator-migration.sql', mig);
  runFile('creator-migration.sql', mig);
  sql(`update public.campaign_options set state = 'pending_draft'`);
  check('the migration applies on its own, and again',
    /"id"/.test(sql(`select public.creator_add_file('${code}', '${opt}',
      'https://mycdn.adspace.me/content/creator/big.mp4', 'again.mp4', 'video', 314572800)`)));
  check('and a 300 MB file is recorded to the byte',
    sql(`select bytes from public.campaign_deliverables where name = 'again.mp4'`) === '314572800');
  check('and the grant survives the replace',
    sql(`select has_function_privilege('anon',
      'public.creator_add_file(text, uuid, text, text, text, bigint)', 'execute')`) === 't');

  /* ---- The team releases the draft, not the creator --------------------
   * creator_submit used to move the step straight to `reviewing`, which on
   * the client's page reads "Your approval": the chip asked them to decide
   * the moment a creator uploaded, while the files are team-only and there
   * was nothing there for them to open. What the client may not see is
   * withheld by get_campaign, so it is get_campaign that is asserted. */
  const release = fs.readFileSync(
    T + '/../supabase/migrations/2026-09-15-team-releases-the-draft.sql', 'utf8');
  runFile('release.sql', release);
  runFile('release.sql', release);
  console.log('ok   the release migration applies on its own, and again');

  sql(`update public.campaigns set access_token = 'TOK1'`);
  sql(`update public.campaign_options set state = 'pending_draft', revision_round = 0,
       changes_by = null, draft_url = null`);
  sql(`select public.creator_submit('${code}', '${opt}', 'Raya at home')`);
  check('a creator submitting lands on Submitted',
    sql(`select state from public.campaign_options`) === 'submitted');

  const shown = () => sql(`select public.get_campaign('TOK1')->'options'->0->>'state'`);
  const files = () => sql(`select jsonb_array_length(public.get_campaign('TOK1')->'options'->0->'files')`);
  const cap = () => sql(`select public.get_campaign('TOK1')->'options'->0->>'caption'`);

  check('the client is told Pending draft, not that it is theirs to approve',
    shown() === 'pending_draft', shown());
  check('and is sent none of the files', files() === '0', files());
  check('and none of the caption', cap() === '', JSON.stringify(cap()));

  // The team sends it back. The client must not learn the round happened.
  sql(`update public.campaign_options
          set state = 'changes', changes_by = 'team', revision_round = 2,
              drop_reason = 'Reshoot the opening'`);
  check('a round the team sent back still reads Pending draft to the client',
    shown() === 'pending_draft', shown());
  check('and still carries no files', files() === '0');

  // The creator uploads again into round 2 and submits; the team releases.
  sql(`select public.creator_add_file('${code}', '${opt}',
       'https://mycdn.adspace.me/content/creator/r2.mp4', 'round-two.mp4', 'video', 2048)`);
  sql(`select public.creator_submit('${code}', '${opt}', 'Second cut')`);
  check('re-submitting clears whose round it was',
    sql(`select coalesce(changes_by, 'none') from public.campaign_options`) === 'none');
  check('and the client still sees Pending draft',
    shown() === 'pending_draft', shown());

  sql(`update public.campaign_options set state = 'reviewing'`);   // the team releases
  check('once released the client is asked to approve', shown() === 'reviewing', shown());
  check('and is sent the newest round only', files() === '1', files());
  check('and it is the round two file',
    sql(`select public.get_campaign('TOK1')->'options'->0->'files'->0->>'name'`) === 'round-two.mp4');
  check('and the caption that goes out with it', cap() === 'Second cut');

  // The client's own rejection is theirs, and stays on their page.
  check('the client can rule on a released draft',
    /"ok": true/.test(sql(`select public.review_draft('TOK1', '${opt}', 'changes', 'Brighter', 'Ms Lim')`)));
  check('and it is stamped as theirs',
    sql(`select changes_by from public.campaign_options`) === 'client');
  check('so their page keeps the Changes requested chip', shown() === 'changes', shown());
  check('and they can still see what they turned down', files() === '1');

  // A draft still with the team cannot be ruled on at all.
  sql(`update public.campaign_options set state = 'submitted', changes_by = null`);
  check('a draft the team has not released cannot be approved by the client',
    /"error": "not-reviewing"/.test(
      sql(`select public.review_draft('TOK1', '${opt}', 'approved', null, 'Ms Lim')`)));

  /* The team sends it back: the creator must land somewhere they can work,
     with what they already sent still there and the note readable. Losing a
     creator's files to a round of feedback is how a reshoot gets billed
     twice. */
  const before = sql(`select count(*) from public.campaign_deliverables where removed_at is null`);
  sql(`update public.campaign_options
          set state = 'changes', changes_by = 'team', revision_round = 3,
              drop_reason = 'Reshoot the opening two seconds'`);
  check('a creator sent back can upload again',
    sql(`select public.creator_can_deliver(state) from public.campaign_options`) === 't');
  check('and keeps every file they had sent',
    sql(`select count(*) from public.campaign_deliverables where removed_at is null`) === before,
    before);
  check('and can take one of them back off',
    /"ok": true/.test(sql(`select public.creator_remove_file('${code}',
      (select id from public.campaign_deliverables where removed_at is null limit 1))`)));
  check('and reads the note the team wrote',
    sql(`select public.get_creator('${code}')->'bookings'->0->>'change_note'`)
      === 'Reshoot the opening two seconds');
  check('while the client is still told Pending draft', shown() === 'pending_draft', shown());
  check('and is sent none of it', files() === '0');

  /* ---- The letter and the service are two lifecycles ---------------------
     A letter is issued for the services somebody chose, and only a verified
     signature confirms them. Before this, `client_services.state` was both
     the commercial state and the selection set for the next letter, so a line
     already sent on one letter was silently carried into the next. Every rule
     operations stated is asserted here against the real functions. */
  const letters = cut('-- THE LETTER AND THE SERVICE ARE TWO LIFECYCLES');
  fs.writeFileSync(SOCK + '/letters.sql', `
drop table if exists public.client_documents cascade;
drop table if exists public.client_services cascade;
drop table if exists public.client_contacts cascade;
create table public.client_contacts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete cascade,
  name text, role text, phone text, email text, is_primary boolean default false,
  portal_access boolean not null default false,
  archived_at timestamptz);
create table public.client_services (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete cascade,
  service_slug text, label text not null, qty numeric(10,2) not null default 1,
  rate numeric(12,2) not null default 0, unit text, detail text, note text,
  state text not null default 'enquired', tenure int not null default 1, start_on text,
  created_at timestamptz not null default now(), archived_at timestamptz);
create table public.client_documents (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete cascade,
  kind text not null, number text not null unique,
  issued_at date not null default current_date, market text not null default 'MY',
  subtotal numeric(12,2) not null default 0, tax numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0, bill_to jsonb, lines jsonb not null default '[]'::jsonb,
  issued_by text, created_at timestamptz not null default now(), voided_at timestamptz);
alter table public.clients add column if not exists legal_name text;
alter table public.clients add column if not exists company_no text;
alter table public.clients add column if not exists company_no_old text;
alter table public.clients add column if not exists tin text;
alter table public.clients add column if not exists sst_no text;
alter table public.clients add column if not exists billing_address text;
alter table public.clients add column if not exists finance_email text;
alter table public.clients add column if not exists bill_contact_id uuid;
-- The permission gate and the signed-in address, as the live database has
-- them. Flipped per assertion below, so the refusals are real refusals.
create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(), actor text, action text not null,
  subject text, detail text, created_at timestamptz not null default now());
create table if not exists public.t_who (email text, clients boolean, billing boolean, admin boolean,
                                        remove boolean default false, doc_void boolean default false);
insert into public.t_who values ('sales@adspacestudios.com', true, true, false, false, false);
create or replace function public.allowed(flag text) returns boolean
  language sql stable set search_path = public as $$
  select case flag when 'clients'  then w.clients
                   when 'billing'  then w.billing
                   when 'remove'   then coalesce(w.remove, false)
                   when 'doc_void' then coalesce(w.doc_void, false)
                   else false end
    from public.t_who w limit 1 $$;
create schema if not exists auth;
create or replace function auth.jwt() returns jsonb
  language sql stable as $$ select jsonb_build_object('email', (select email from public.t_who limit 1)) $$;
alter table public.team_members add column if not exists is_admin boolean default false;
insert into public.team_members (name, email, active, role, is_admin)
  values ('Qiao Rou', 'sales@adspacestudios.com', true, 'sales', false)
  on conflict do nothing;
` + letters);
  execFileSync('bash', ['-c', `chmod 644 ${SOCK}/letters.sql`]);
  asPg(`psql -h ${SOCK} -p ${PORT} -U postgres -d clock -v ON_ERROR_STOP=1 -q -f ${SOCK}/letters.sql`);
  console.log('ok   the letter lifecycle applies to a real Postgres');

  sql(`insert into public.clients (name) values ('Laman Citra')`);
  const LC = sql(`select id from public.clients where name='Laman Citra'`);
  const mkSvc = (label, rate, state) => {
    sql(`insert into public.client_services (client_id, label, rate, tenure, state)
         values ('${LC}', '${label}', ${rate}, 6, '${state}')`);
    return sql(`select id from public.client_services where client_id='${LC}' and label='${label}'`);
  };
  const issue = (ids, extra) => sql(`select public.issue_letter('${LC}',
    array[${ids.map(i => `'${i}'::uuid`).join(',')}], ${extra && extra.idem ? `'${extra.idem}'` : 'null'},
    1000, 80, 1080, '{}'::jsonb,
    ${extra && extra.replaces ? `'${extra.replaces}'::uuid` : 'null'},
    ${extra && extra.renewal ? 'true' : 'false'})`);
  const stateOf = id => sql(`select state from public.client_services where id='${id}'`);

  // 14. The Client ID: blocking, normalising, uniqueness, bad characters.
  const svOld = mkSvc('Social media management', 3200, 'confirmed');
  const svNew = mkSvc('Paid advertising', 1500, 'quoted');
  const svOther = mkSvc('SEO retainer', 800, 'quoted');
  check('a letter is refused while the client has no Client ID',
    /no-client-code/.test(issue([svNew])), issue([svNew]));
  check('a Client ID with a slash in it is refused by the database',
    /violates check constraint/.test(
      (() => { try { sql(`update public.clients set client_code='AQL/1' where id='${LC}'`); return 'accepted'; }
               catch (e) { return String(e.stderr || e.message); } })()));
  check('and one with a space in it is refused too',
    /violates check constraint/.test(
      (() => { try { sql(`update public.clients set client_code='AC 180' where id='${LC}'`); return 'accepted'; }
               catch (e) { return String(e.stderr || e.message); } })()));
  sql(`update public.clients set client_code='AC180' where id='${LC}'`);
  sql(`insert into public.clients (name) values ('Second')`);
  check('a Client ID is unique across clients',
    /duplicate key|unique constraint/.test(
      (() => { try { sql(`update public.clients set client_code='AC180' where name='Second'`); return 'accepted'; }
               catch (e) { return String(e.stderr || e.message); } })()));

  // 13. The serial, exactly as operations wrote it.
  const r1 = issue([svNew], { idem: 'k1' });
  const ym = sql(`select to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM')`);
  check('the first letter of the month reads AQL/AC180/' + ym + '01',
    new RegExp('"number" *: *"AQL/AC180/' + ym + '01"').test(r1), r1);
  const doc1 = sql(`select id from public.client_documents where number like 'AQL/%' order by created_at limit 1`);

  // 1. and 3. Only the chosen line, and issuing confirms nothing.
  check('the letter carries only the service that was chosen',
    sql(`select count(*) from public.client_document_services where document_id='${doc1}'`) === '1');
  check('and it is the new line, not the confirmed one',
    sql(`select service_id from public.client_document_services where document_id='${doc1}'`) === svNew);
  check('issuing confirms nothing', stateOf(svNew) === 'quoted', stateOf(svNew));
  check('the old confirmed line is untouched', stateOf(svOld) === 'confirmed');
  check('and a To quote line that was not on it stays To quote', stateOf(svOther) === 'quoted');

  // 10. One submission, one letter, one serial.
  const again = issue([svNew], { idem: 'k1' });
  check('the same submission twice returns the first letter',
    /"repeat" *: *true/.test(again) && new RegExp('AQL/AC180/' + ym + '01').test(again), again);
  check('and spends no second serial',
    sql(`select count(*) from public.client_documents where number like 'AQL/%'`) === '1');

  // 2. A line already on a live letter is not silently offered again.
  check('a line already on a live letter is refused, not re-quoted',
    /already-quoted/.test(issue([svNew], { idem: 'k2' })), issue([svNew], { idem: 'k2' }));

  // 4. Signing confirms nothing.
  check('marking signed is accepted', /"ok" *: *true/.test(sql(`select public.letter_set_signed('${doc1}', true)`)));
  check('and confirms nothing', stateOf(svNew) === 'quoted', stateOf(svNew));

  // 5. and 6. Verification confirms only what the letter mapped.
  const ver = sql(`select public.verify_letter('${doc1}')`);
  check('verifying confirms the letter\'s own line', /"confirmed" *: *1/.test(ver), ver);
  check('and that line is now Confirmed', stateOf(svNew) === 'confirmed');
  check('the other To quote line is untouched', stateOf(svOther) === 'quoted');
  check('and the already confirmed one is untouched', stateOf(svOld) === 'confirmed');
  check('verifying twice confirms nothing more',
    /"repeat" *: *true/.test(sql(`select public.verify_letter('${doc1}')`)));

  // 8. Voiding is its own authority, applies to a verified letter, and needs
  //    a reason. Nobody without can_doc_void reaches it at all.
  check('voiding is refused without the capability',
    /not-allowed/.test(sql(`select public.letter_set_void('${doc1}', 'wrong client')`)));
  sql(`update public.t_who set doc_void=true`);
  check('and refused with the capability but no reason',
    /reason-required/.test(sql(`select public.letter_set_void('${doc1}', '   ')`)));
  sql(`update public.t_who set doc_void=false`);

  // 12. The sequence is per client and per month, and never reused.
  const r2 = issue([svOther], { idem: 'k3' });
  check('the next letter for this client takes 02',
    new RegExp('AQL/AC180/' + ym + '02').test(r2), r2);
  sql(`update public.clients set client_code='ZZ9' where name='Second'`);
  const S2 = sql(`select id from public.clients where name='Second'`);
  sql(`insert into public.client_services (client_id, label, rate, state) values ('${S2}', 'Shoot', 900, 'quoted')`);
  const s2sv = sql(`select id from public.client_services where client_id='${S2}'`);
  const r3 = sql(`select public.issue_letter('${S2}', array['${s2sv}'::uuid], 'k4', 10, 1, 11)`);
  check('another client starts its own month at 01',
    new RegExp('AQL/ZZ9/' + ym + '01').test(r3), r3);
  check('a serial is never reused once spent',
    sql(`select next_val from public.client_document_seq where client_id='${LC}'`) === '3');

  // 4. Two digits is the floor, not the ceiling.
  sql(`update public.client_document_seq set next_val = 100 where client_id='${S2}'`);
  sql(`insert into public.client_services (client_id, label, rate, state) values ('${S2}', 'Extra', 10, 'quoted')`);
  const s2b = sql(`select id from public.client_services where client_id='${S2}' and label='Extra'`);
  const wide = sql(`select public.issue_letter('${S2}', array['${s2b}'::uuid], 'k5', 10, 1, 11)`);
  check('the hundredth letter of a month widens rather than wrapping',
    new RegExp('AQL/ZZ9/' + ym + '100').test(wide), wide);

  // 15. A letter from before this change has no mappings and is not verifiable.
  sql(`insert into public.client_documents (client_id, kind, number, lines, signed_at)
       values ('${LC}', 'offer', 'AQT/INT/2603001',
         '[{"label":"Old line","qty":1,"rate":100}]'::jsonb, now())`);
  const legacy = sql(`select id from public.client_documents where number='AQT/INT/2603001'`);
  check('a legacy letter cannot be verified by accident',
    /no-mapping/.test(sql(`select public.verify_letter('${legacy}')`)));
  check('and is still readable exactly as it was',
    sql(`select lines->0->>'label' from public.client_documents where id='${legacy}'`) === 'Old line');

  // 9. Editing a service afterwards does not rewrite the snapshot.
  sql(`update public.client_services set label='Renamed', rate=9999 where id='${svNew}'`);
  check('editing a service does not rewrite the issued snapshot',
    sql(`select lines->0->>'label' from public.client_documents where id='${doc1}'`) === 'Paid advertising');

  // 3. A confirmed line is never carried in by itself, and only on a renewal.
  check('a confirmed line is refused unless the renewal path is taken',
    /bad-lines/.test(issue([svOld], { idem: 'k6' })));
  check('and is accepted when a renewal is asked for deliberately',
    /"ok" *: *true/.test(issue([svOld], { idem: 'k7', renewal: true })));

  // 16. Permissions: the gate is the database's, not the page's.
  sql(`update public.t_who set clients=false, billing=false`);
  check('somebody without Clients cannot issue',
    /not-allowed/.test(sql(`select public.issue_letter('${LC}', array['${svOther}'::uuid], 'k8', 1, 0, 1)`)));
  check('nor mark a letter signed',
    /not-allowed/.test(sql(`select public.letter_set_signed('${doc1}', false)`)));
  sql(`update public.t_who set clients=true, billing=false`);
  const doc2 = sql(`select id from public.client_documents where number like '%${ym}02'`);
  sql(`select public.letter_set_signed('${doc2}', true)`);
  check('and somebody without Billing cannot verify',
    /not-allowed/.test(sql(`select public.verify_letter('${doc2}')`)));
  check('the admin override refuses a non-admin',
    /not-allowed/.test(sql(`select public.override_service_state('${svOther}', 'confirmed', 'legacy')`)));
  sql(`update public.t_who set admin=true`);
  sql(`update public.team_members set is_admin=true where email='sales@adspacestudios.com'`);
  check('and refuses an admin who gives no reason',
    /reason-required/.test(sql(`select public.override_service_state('${svOther}', 'enquired', '  ')`)));
  check('but lets an admin through with one',
    /"ok" *: *true/.test(sql(`select public.override_service_state('${svOther}', 'enquired', 'legacy tidy-up')`)));
  check('and writes the reason to the activity record',
    /legacy tidy-up/.test(sql(`select detail from public.activity_log where action='service.override' limit 1`)));

  // 11. Two issuances racing: consecutive serials, no retry, no collision.
  sql(`update public.t_who set clients=true, billing=true`);
  sql(`insert into public.client_services (client_id, label, rate, state)
       select '${LC}', 'Race ' || g, 100, 'quoted' from generate_series(1,2) g`);
  const raceA = sql(`select id from public.client_services where label='Race 1'`);
  const raceB = sql(`select id from public.client_services where label='Race 2'`);
  const both = sql(`select string_agg(n, ',' order by n) from (
      select public.issue_letter('${LC}', array['${raceA}'::uuid], 'r1', 1, 0, 1)->>'number' as n
      union all
      select public.issue_letter('${LC}', array['${raceB}'::uuid], 'r2', 1, 0, 1)->>'number') q`);
  check('two issuances produce distinct consecutive serials',
    both.split(',').length === 2 && both.split(',')[0] !== both.split(',')[1], both);

  // ---- 17. Voiding and deleting a letter -----------------------------------
  //      Two authorities. A void reverses a confirmation and needs a reason;
  //      a deletion is the portal's hard-delete authority and needs the serial
  //      typed back. Neither may touch a service line another live letter is
  //      still holding confirmed.
  sql(`update public.t_who set clients=true, billing=true, remove=false, doc_void=false, admin=false`);
  sql(`update public.team_members set is_admin=false where email='sales@adspacestudios.com'`);

  // A client whose two verified letters both confirm one shared line, so the
  // "only what this letter alone confirmed" rule has something to get wrong.
  sql(`insert into public.clients (name, market, client_code) values ('Voidco', 'MY', 'VD1')`);
  const VD = sql(`select id from public.clients where name='Voidco'`);
  sql(`insert into public.client_contacts (client_id, name, is_primary)
       values ('${VD}', 'Lim', true)`);
  const mk = (label) => {
    sql(`insert into public.client_services (client_id, label, rate, tenure, state)
         values ('${VD}', '${label}', 500, 6, 'quoted')`);
    return sql(`select id from public.client_services where client_id='${VD}' and label='${label}'`);
  };
  const vSole = mk('Sole line');
  const vShared = mk('Shared line');

  const issueVD = (ids, idem, renewal) =>
    sql(`select public.issue_letter('${VD}', array[${ids.map(i => `'${i}'::uuid`).join(',')}], '${idem}', 10, 1, 11, null, null, ${renewal ? 'true' : 'false'})`);

  const vA = JSON.parse(issueVD([vSole, vShared], 'v1'));
  const docA = sql(`select id from public.client_documents where number='${vA.number}'`);
  sql(`select public.letter_set_signed('${docA}', true)`);
  sql(`select public.verify_letter('${docA}')`);
  check('both lines are confirmed by the first letter',
    stateOf(vSole) === 'confirmed' && stateOf(vShared) === 'confirmed');

  // A second verified letter that also carries the shared line, as a renewal.
  const vB = JSON.parse(issueVD([vShared], 'v2', true));
  const docB = sql(`select id from public.client_documents where number='${vB.number}'`);
  sql(`select public.letter_set_signed('${docB}', true)`);
  sql(`select public.verify_letter('${docB}')`);

  // An ordinary user reaches neither action, whatever the letter's state.
  check('an ordinary user cannot void a verified letter',
    /not-allowed/.test(sql(`select public.letter_set_void('${docA}', 'mistake')`)));
  check('and cannot delete one',
    /not-allowed/.test(sql(`select public.letter_delete('${docA}', '${vA.number}', 'mistake')`)));

  // Void: the capability, a reason, and only what this letter alone held.
  sql(`update public.t_who set doc_void=true`);
  const vr = sql(`select public.letter_set_void('${docA}', 'Client changed the scope')`);
  check('a user with the void capability voids a verified letter',
    /"ok" *: *true/.test(vr), vr);
  check('and it reverts the line only this letter confirmed',
    stateOf(vSole) === 'quoted', stateOf(vSole));
  check('while the line another verified letter still holds stays confirmed',
    stateOf(vShared) === 'confirmed', stateOf(vShared));
  check('the void records who and why',
    sql(`select voided_by || '|' || void_reason from public.client_documents where id='${docA}'`)
      === 'sales@adspacestudios.com|Client changed the scope');
  check('and writes the reason to the activity record',
    /Client changed the scope/.test(
      sql(`select detail from public.activity_log where action='document.voided' order by created_at desc limit 1`)));
  check('voiding twice changes nothing more',
    /"repeat" *: *true/.test(sql(`select public.letter_set_void('${docA}', 'again')`)));
  check('the void capability alone does not permit deletion',
    /not-allowed/.test(sql(`select public.letter_delete('${docA}', '${vA.number}', 'tidy')`)));

  // An issued letter has confirmed nothing, so there is nothing to void.
  const vC = JSON.parse(issueVD([vSole], 'v3'));
  const docC = sql(`select id from public.client_documents where number='${vC.number}'`);
  check('an issued letter cannot be voided, only deleted',
    /not-verified/.test(sql(`select public.letter_set_void('${docC}', 'keyed in twice')`)));

  // Deletion: can_remove, the exact serial, and a reason.
  sql(`update public.t_who set remove=true`);
  check('deletion refuses a serial that does not match',
    /confirm-mismatch/.test(sql(`select public.letter_delete('${docC}', 'AQL/VD1/000000', 'typo')`)));
  check('and refuses an empty reason',
    /reason-required/.test(sql(`select public.letter_delete('${docC}', '${vC.number}', '  ')`)));
  const del = sql(`select public.letter_delete('${docC}', '${vC.number}', 'Issued against the wrong client')`);
  check('an issued letter is deleted with the serial and a reason',
    /"ok" *: *true/.test(del), del);
  check('and the row is gone',
    sql(`select count(*) from public.client_documents where id='${docC}'`) === '0');
  check('its mapping went with it',
    sql(`select count(*) from public.client_document_services where document_id='${docC}'`) === '0');

  // The audit event: enough to explain the gap, none of the document.
  const au = sql(`select number || '|' || actor || '|' || reason from public.client_document_deletions where document_id='${docC}'`);
  check('a deletion leaves a minimal audit event',
    au === vC.number + '|sales@adspacestudios.com|Issued against the wrong client', au);
  check('and that audit event carries no document content',
    sql(`select count(*) from information_schema.columns
          where table_name='client_document_deletions'
            and column_name in ('lines','bill_to','total','subtotal','tax')`) === '0');

  // A voided letter may still be deleted, and the shared line survives both.
  const del2 = sql(`select public.letter_delete('${docA}', '${vA.number}', 'Removing the voided duplicate')`);
  check('a voided letter can be permanently deleted', /"ok" *: *true/.test(del2), del2);
  check('and the shared line is still confirmed by the letter that remains',
    stateOf(vShared) === 'confirmed', stateOf(vShared));

  // Deleting the last letter holding a line does revert it.
  const del3 = sql(`select public.letter_delete('${docB}', '${vB.number}', 'Cancelled engagement')`);
  check('deleting the last verified letter reverts the line it alone held',
    /"ok" *: *true/.test(del3) && stateOf(vShared) === 'quoted', stateOf(vShared));

  // Serials are spent for ever, voided and deleted alike.
  const after = JSON.parse(issueVD([vSole], 'v4'));
  check('a deleted serial is never handed out again',
    after.number !== vA.number && after.number !== vB.number && after.number !== vC.number,
    [vA.number, vB.number, vC.number, after.number].join(' '));

  // Losing the permission between opening the dialog and pressing the button.
  sql(`update public.t_who set remove=false, doc_void=false`);
  const docD = sql(`select id from public.client_documents where number='${after.number}'`);
  check('a permission removed before submission refuses the delete',
    /not-allowed/.test(sql(`select public.letter_delete('${docD}', '${after.number}', 'late')`)));

  // ---- 18. A letter is signed by a person, never by a permission ----------
  sql(`update public.t_who set clients=true, billing=true`);
  sql(`update public.team_members set name='Superadmin' where email='sales@adspacestudios.com'`);
  const bad = sql(`select public.issue_letter('${VD}', array['${vShared}'::uuid], 'v5', 10, 1, 11)`);
  check('a letter is refused when the issuer is named for a role',
    /issuer-name/.test(bad), bad);
  sql(`update public.team_members set name='Qiao Rou' where email='sales@adspacestudios.com'`);
  const good = sql(`select public.issue_letter('${VD}', array['${vShared}'::uuid], 'v6', 10, 1, 11)`);
  check('but issued once the name is a person\'s',
    /"ok" *: *true/.test(good), good);
  check('and the letter is signed with that name',
    sql(`select issued_by from public.client_documents order by created_at desc limit 1`) === 'Qiao Rou');
} catch (e) {
  console.log('FAIL ' + (e.stderr ? String(e.stderr).slice(0, 600) : e.message));
  fails++;
} finally {
  try { asPg(`${PGBIN}/pg_ctl -D ${DIR} -m immediate stop`); } catch (e) {}
  try { execFileSync('bash', ['-c', `rm -rf ${DIR} ${SOCK}`]); } catch (e) {}
}

console.log(fails ? 'sql: PROBLEM (' + fails + ' fail)' : 'sql: ok');
process.exit(fails ? 1 : 0);
