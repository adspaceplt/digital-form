-- ===========================================================================
-- PERFORMANCE REVIEWS — the monthly score, the breach log, the dispute and
-- the signed record: each person reads their own, and management reads
-- everyone's behind a master code.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/perf.js compares the two.
--
-- WHAT THIS IS.
--
--   The ADspace Performance Framework v2.0 and its calculator workbook, as a
--   record: six categories out of 100, breaches that deduct (capped at 35),
--   grade caps for a Level 3 or 4 breach, the five grades, reward
--   eligibility, the development and accountability paths. Decided with the
--   user on 2026-09-24:
--     - Grades read Distinction, Strong, Baseline, Needs Guidance,
--       Performance Review.
--     - Grade C is reward eligible, unless the month before was also C; a
--       Level 3 or 4 breach that month makes any month not eligible.
--     - The member sees nothing of a month, breaches included, until it is
--       released, which happens at the monthly 1-1.
--     - A released month may be disputed for 3 days, one dispute a version,
--       item by item, each with a reason; management answers each with a
--       reason; the member acknowledges; management finalises.
--     - Budget pacing counts only for somebody who runs client ads.
--
-- WHO READS WHAT, AND HOW THE DATABASE MAKES IT TRUE.
--
--   Every table below has row level security on and NO policy at all, so a
--   browser reads and writes nothing directly, whatever it sends. Everything
--   goes through the functions:
--     - `perf_mine()` and the member's own acts answer only for the signed-in
--       person's own released months.
--     - Every management function asks `team.performance` (granted, never
--       inherited: `ops_granted()` reads the exact key, so a group given Team
--       does not get this) AND a live unlock token, which only the master
--       code produces. An admin passes the first test and still needs the
--       second.
--     - Nobody acts on their own review, and the management list leaves the
--       caller out: their own months are in My performance like everybody's.
--   The master code is stored as a bcrypt hash in `app_secrets`, which no
--   browser can read. Five wrong tries lock that person out for 15 minutes;
--   an unlock lasts 15 minutes from the last use.
--
-- SET OR CHANGE THE MASTER CODE (in the Supabase SQL editor, never in chat):
--   select public.perf_code_reset('your code here');
-- Changing it ends every open unlock.
--
-- ROLLBACK
--   drop function if exists public.perf_code_reset(text), public.perf_code_set(),
--     public.perf_unlock(text), public.perf_lock(text), public.perf_gate_info(),
--     public.perf_month(text, date), public.perf_open(text, uuid, date),
--     public.perf_save(text, uuid, date, jsonb, integer), public.perf_release(text, uuid, integer),
--     public.perf_unrelease(text, uuid, text), public.perf_decide(text, uuid, text, text, numeric),
--     public.perf_finalise(text, uuid), public.perf_reopen(text, uuid, text),
--     public.perf_breach_log(text, uuid, jsonb), public.perf_breach_void(text, uuid, text),
--     public.perf_profile_set(text, uuid, jsonb), public.perf_mine(),
--     public.perf_dispute(uuid, jsonb), public.perf_acknowledge(uuid),
--     public.perf_printed(uuid, text), public.perf_check(text, text),
--     public.perf_log(uuid, uuid, text, jsonb), public.perf_calc(public.perf_reviews),
--     public.perf_json(public.perf_reviews, boolean), public.perf_ops_rate(uuid, date),
--     public.perf_breaches_json(uuid, date, boolean), public.perf_notify(uuid, text, text, text),
--     public.perf_grade_of(numeric), public.perf_grade_word(text), public.perf_band(numeric, numeric),
--     public.perf_pacing_band(numeric), public.perf_deduction(integer, boolean, boolean),
--     public.perf_month_word(date), public.perf_reviewed(uuid) cascade;
--   drop table if exists public.perf_events, public.perf_disputes, public.perf_breaches,
--     public.perf_reviews, public.perf_people, public.perf_unlocks, public.perf_attempts cascade;
--   delete from public.app_secrets where key = 'perf_code';
-- ===========================================================================

create table if not exists public.app_secrets (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now()
);

-- 1. The record ---------------------------------------------------------------------
/* Who is reviewed and how. A row exists only once somebody has set it; a
   colleague with none is reviewed, unless they are an admin, which is the
   owner's own account. */
create table if not exists public.perf_people (
  team_member_id uuid primary key references public.team_members(id) on delete cascade,
  department     text check (department in ('creative', 'marketing')),
  role_family    text check (role_family in ('visual', 'video', 'planner', 'account')),
  runs_ads       boolean not null default false,
  reviewed       boolean,
  updated_at     timestamptz not null default now()
);

create table if not exists public.perf_reviews (
  id              uuid primary key default gen_random_uuid(),
  team_member_id  uuid not null references public.team_members(id) on delete cascade,
  period          date not null check (extract(day from period) = 1),
  status          text not null default 'draft'
                  check (status in ('draft', 'released', 'disputed', 'resolved', 'acknowledged', 'final')),
  s_output        numeric(4,1) check (s_output between 0 and 25),
  s_accuracy      numeric(4,1) check (s_accuracy between 0 and 15),
  s_delivery      numeric(4,1) check (s_delivery between 0 and 15),
  s_client        numeric(4,1) check (s_client between 0 and 20),
  s_comms         numeric(4,1) check (s_comms between 0 and 15),
  s_initiative    numeric(4,1) check (s_initiative between 0 and 10),
  r_posting       numeric(5,1) check (r_posting between 0 and 100),
  r_timeline      numeric(5,1) check (r_timeline between 0 and 100),
  r_satisfaction  numeric(5,1) check (r_satisfaction between 0 and 100),
  r_pacing        numeric(6,1) check (r_pacing between 0 and 1000),
  r_sla           numeric(5,1) check (r_sla between 0 and 100),
  notes           jsonb not null default '{}'::jsonb,
  improvement     text,
  review_by       date,
  reward_step     text,
  serial          text,
  reviewer_id     uuid references public.team_members(id) on delete set null,
  released_at     timestamptz,
  dispute_until   timestamptz,
  acknowledged_at timestamptz,
  finalised_at    timestamptz,
  finalised_by    uuid references public.team_members(id) on delete set null,
  result          jsonb,
  version         integer not null default 1,
  rev             integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (team_member_id, period)
);
create unique index if not exists perf_reviews_serial_idx
  on public.perf_reviews(serial) where serial is not null;

create table if not exists public.perf_breaches (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  occurred_on    date not null,
  period         date not null,
  category       text not null check (category in ('client', 'delivery', 'compliance', 'asset')),
  severity       integer not null check (severity between 1 and 4),
  repeated       boolean not null default false,
  late           boolean not null default false,
  what           text not null,
  evidence       text,
  logged_by      uuid references public.team_members(id) on delete set null,
  logged_at      timestamptz not null default now(),
  voided_at      timestamptz,
  voided_by      uuid references public.team_members(id) on delete set null,
  void_reason    text
);
create index if not exists perf_breaches_member_idx on public.perf_breaches(team_member_id, period);

create table if not exists public.perf_disputes (
  id           uuid primary key default gen_random_uuid(),
  review_id    uuid not null references public.perf_reviews(id) on delete cascade,
  version      integer not null default 1,
  item         text not null check (item in ('output', 'accuracy', 'delivery', 'client', 'comms', 'initiative', 'breach')),
  breach_id    uuid references public.perf_breaches(id) on delete set null,
  reason       text not null,
  raised_at    timestamptz not null default now(),
  decision     text check (decision in ('upheld', 'partly', 'not_upheld')),
  response     text,
  before_value numeric(4,1),
  after_value  numeric(4,1),
  decided_by   uuid references public.team_members(id) on delete set null,
  decided_at   timestamptz
);
create index if not exists perf_disputes_review_idx on public.perf_disputes(review_id);

/* Append only: what happened to a review, who did it and when, including
   every unlock and every printed copy. Nothing here is read by the member. */
create table if not exists public.perf_events (
  id             uuid primary key default gen_random_uuid(),
  review_id      uuid references public.perf_reviews(id) on delete cascade,
  team_member_id uuid references public.team_members(id) on delete cascade,
  actor_id       uuid,
  actor_email    text,
  kind           text not null,
  detail         jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
create index if not exists perf_events_review_idx on public.perf_events(review_id, created_at desc);

create table if not exists public.perf_unlocks (
  token_hash     text primary key,
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null
);
create table if not exists public.perf_attempts (
  team_member_id uuid primary key references public.team_members(id) on delete cascade,
  failures       integer not null default 0,
  locked_until   timestamptz
);

-- 2. Nobody reads a table directly -------------------------------------------------
alter table public.app_secrets enable row level security;
alter table public.perf_people enable row level security;
alter table public.perf_reviews enable row level security;
alter table public.perf_breaches enable row level security;
alter table public.perf_disputes enable row level security;
alter table public.perf_events enable row level security;
alter table public.perf_unlocks enable row level security;
alter table public.perf_attempts enable row level security;
revoke all on public.app_secrets, public.perf_people, public.perf_reviews, public.perf_breaches,
  public.perf_disputes, public.perf_events, public.perf_unlocks, public.perf_attempts
  from anon, authenticated;
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies
            where schemaname = 'public'
              and tablename in ('perf_people', 'perf_reviews', 'perf_breaches', 'perf_disputes',
                                'perf_events', 'perf_unlocks', 'perf_attempts') loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

create or replace function public.perf_events_frozen()
returns trigger language plpgsql as $$
begin
  if pg_trigger_depth() > 1 then return coalesce(old, new); end if;
  raise exception 'perf-events-append-only';
end $$;
drop trigger if exists perf_events_frozen on public.perf_events;
create trigger perf_events_frozen before update or delete on public.perf_events
  for each row execute function public.perf_events_frozen();

-- 3. The rules, stated once ----------------------------------------------------------
create or replace function public.perf_grade_of(p_score numeric)
returns text language sql immutable as $$
  select case when p_score >= 90 then 'A' when p_score >= 80 then 'B'
              when p_score >= 70 then 'C' when p_score >= 60 then 'D' else 'E' end
$$;
create or replace function public.perf_grade_word(p_grade text)
returns text language sql immutable as $$
  select case p_grade when 'A' then 'Distinction' when 'B' then 'Strong' when 'C' then 'Baseline'
                      when 'D' then 'Needs Guidance' when 'E' then 'Performance Review' end
$$;
create or replace function public.perf_deduction(p_severity integer, p_repeated boolean, p_late boolean)
returns integer language sql immutable as $$
  select (case p_severity when 1 then -3 when 2 then -7 when 3 then -15 when 4 then -30 else 0 end)
       + (case when p_repeated then -5 else 0 end) + (case when p_late then -5 else 0 end)
$$;
/* Green at the target, amber within 10% of it, red below that. */
create or replace function public.perf_band(p_rate numeric, p_target numeric)
returns text language sql immutable as $$
  select case when p_rate is null then null when p_rate >= p_target then 'green'
              when p_rate >= p_target * 0.9 then 'amber' else 'red' end
$$;
/* Budget pacing is a variance, so lower is better: within 10% green, within
   20% amber, the workbook's own rule. */
create or replace function public.perf_pacing_band(p_variance numeric)
returns text language sql immutable as $$
  select case when p_variance is null then null when p_variance <= 10 then 'green'
              when p_variance <= 20 then 'amber' else 'red' end
$$;
create or replace function public.perf_month_word(p_period date)
returns text language sql immutable as $$
  select trim(to_char(p_period, 'FMMonth YYYY'))
$$;

/* Is this colleague on the monthly review? Their own setting where one was
   made, else everybody but an admin. */
create or replace function public.perf_reviewed(p_member uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select pp.reviewed from public.perf_people pp where pp.team_member_id = m.id),
                  not (m.is_admin or m.role = 'admin'))
    from public.team_members m where m.id = p_member
$$;

-- 4. The gate -----------------------------------------------------------------------
create or replace function public.perf_code_set()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_secrets where key = 'perf_code' and value <> '')
$$;

/* Run by the owner in the SQL editor. Never granted to a browser. */
create or replace function public.perf_code_reset(p_code text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(coalesce(p_code, '')) < 6 then
    raise exception 'The master code needs at least 6 characters.';
  end if;
  insert into public.app_secrets (key, value) values ('perf_code', crypt(p_code, gen_salt('bf', 8)))
  on conflict (key) do update set value = excluded.value, updated_at = now();
  delete from public.perf_unlocks;
  delete from public.perf_attempts;
  return 'Master code set.';
end $$;

create or replace function public.perf_log(p_review uuid, p_member uuid, p_kind text, p_detail jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  insert into public.perf_events (review_id, team_member_id, actor_id, actor_email, kind, detail)
  values (p_review, p_member, m.id, m.email, p_kind, coalesce(p_detail, '{}'::jsonb));
end $$;

/* The two tests every management function asks, in one place: the granted
   part at the level the act needs, and a live unlock. A live unlock is
   extended by its use, so somebody working through the month is not asked
   again mid review. Null means pass. */
create or replace function public.perf_check(p_token text, p_level text)
returns text
language plpgsql security definer set search_path = public as $$
declare m public.team_members; n integer;
begin
  m := public.ops_me();
  if m.id is null then return 'not-team'; end if;
  if not public.ops_granted('team.performance', p_level) then return 'denied'; end if;
  if not public.perf_code_set() then return 'no-code'; end if;
  update public.perf_unlocks set expires_at = now() + interval '15 minutes'
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and team_member_id = m.id and expires_at > now();
  get diagnostics n = row_count;
  if n = 0 then return 'code-needed'; end if;
  return null;
end $$;

create or replace function public.perf_gate_info()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; a public.perf_attempts;
begin
  m := public.ops_me();
  if m.id is null or not public.ops_granted('team.performance', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into a from public.perf_attempts where team_member_id = m.id;
  return jsonb_build_object('code_set', public.perf_code_set(),
    'locked_until', case when a.locked_until > now() then a.locked_until end,
    'can_work', public.ops_granted('team.performance', 'work'),
    'can_manage', public.ops_granted('team.performance', 'manage'));
end $$;

create or replace function public.perf_unlock(p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  m public.team_members; h text; a public.perf_attempts; tok text; f integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('team.performance', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select value into h from public.app_secrets where key = 'perf_code';
  if coalesce(h, '') = '' then return jsonb_build_object('error', 'no-code'); end if;
  select * into a from public.perf_attempts where team_member_id = m.id;
  if a.locked_until > now() then
    return jsonb_build_object('error', 'locked', 'until', a.locked_until);
  end if;
  if crypt(coalesce(p_code, ''), h) <> h then
    f := case when a.locked_until is not null then 1 else coalesce(a.failures, 0) + 1 end;
    insert into public.perf_attempts (team_member_id, failures, locked_until)
    values (m.id, f, case when f >= 5 then now() + interval '15 minutes' end)
    on conflict (team_member_id) do update
      set failures = excluded.failures, locked_until = excluded.locked_until;
    perform public.perf_log(null, null, 'unlock_failed', jsonb_build_object('failures', f));
    if f >= 5 then
      return jsonb_build_object('error', 'locked', 'until', now() + interval '15 minutes');
    end if;
    return jsonb_build_object('error', 'wrong-code', 'left', 5 - f);
  end if;
  delete from public.perf_attempts where team_member_id = m.id;
  delete from public.perf_unlocks where expires_at < now();
  tok := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.perf_unlocks (token_hash, team_member_id, expires_at)
  values (encode(sha256(convert_to(tok, 'UTF8')), 'hex'), m.id, now() + interval '15 minutes');
  perform public.perf_log(null, null, 'unlocked', '{}'::jsonb);
  return jsonb_build_object('token', tok, 'expires_at', now() + interval '15 minutes');
end $$;

create or replace function public.perf_lock(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  delete from public.perf_unlocks
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex');
  return jsonb_build_object('ok', true);
end $$;

-- 5. The calculator -----------------------------------------------------------------
create or replace function public.perf_breaches_json(p_member uuid, p_period date, p_with_void boolean)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'occurred_on', b.occurred_on, 'category', b.category,
           'severity', b.severity, 'repeated', b.repeated, 'late', b.late,
           'what', b.what, 'evidence', b.evidence,
           'deduction', public.perf_deduction(b.severity, b.repeated, b.late),
           'logged_by', (select name from public.team_members where id = b.logged_by),
           'logged_at', b.logged_at, 'voided_at', b.voided_at, 'void_reason', b.void_reason)
         order by b.occurred_on, b.logged_at), '[]'::jsonb)
    from public.perf_breaches b
   where b.team_member_id = p_member and b.period = p_period
     and (p_with_void or b.voided_at is null)
$$;

/* One definition of the month's result, read by the management page, the
   member's page and the printed copy alike. A final review keeps the result
   it was finalised with, so a later change to an earlier month cannot move
   a record somebody has signed. */
create or replace function public.perf_calc(r public.perf_reviews)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  base numeric; raw_ded integer; ded integer; fin numeric; l3 boolean; l4 boolean;
  g text; cap integer; rk integer; prev public.perf_reviews; prev_g text; ok boolean;
  complete boolean; path text; ads boolean; bd text; bc text; bm text;
  rank_of constant text := 'ABCDE';
begin
  if r.status = 'final' and r.result is not null then return r.result; end if;
  complete := r.s_output is not null and r.s_accuracy is not null and r.s_delivery is not null
          and r.s_client is not null and r.s_comms is not null and r.s_initiative is not null;
  base := coalesce(r.s_output, 0) + coalesce(r.s_accuracy, 0) + coalesce(r.s_delivery, 0)
        + coalesce(r.s_client, 0) + coalesce(r.s_comms, 0) + coalesce(r.s_initiative, 0);
  select coalesce(sum(public.perf_deduction(severity, repeated, late)), 0),
         coalesce(bool_or(severity = 3), false), coalesce(bool_or(severity = 4), false)
    into raw_ded, l3, l4
    from public.perf_breaches
   where team_member_id = r.team_member_id and period = r.period and voided_at is null;
  ded := greatest(raw_ded, -35);
  fin := greatest(0, least(100, base + ded));
  g := public.perf_grade_of(fin);
  cap := case when l4 then 4 when l3 then 2 else 0 end;
  rk := greatest(position(g in rank_of), cap);
  g := substr(rank_of, rk, 1);

  select * into prev from public.perf_reviews
   where team_member_id = r.team_member_id and period = (r.period - interval '1 month')::date
     and status <> 'draft';
  if prev.id is not null then
    prev_g := (public.perf_calc(prev)) ->> 'grade';
  end if;
  ok := (g in ('A', 'B') or (g = 'C' and prev_g is distinct from 'C')) and not l3 and not l4;
  path := case when g = 'E' or l3 or l4 then 'accountability' when g = 'D' then 'development' end;

  ads := coalesce((select runs_ads from public.perf_people where team_member_id = r.team_member_id), false);
  bd := (select b from unnest(array[public.perf_band(r.r_posting, 95), public.perf_band(r.r_timeline, 90)]) b
          where b is not null order by position(b in 'green amber red') desc limit 1);
  bc := (select b from unnest(array[public.perf_band(r.r_satisfaction, 90),
                                    case when ads then public.perf_pacing_band(r.r_pacing) end]) b
          where b is not null order by position(b in 'green amber red') desc limit 1);
  bm := public.perf_band(r.r_sla, 90);

  return jsonb_build_object(
    'complete', complete, 'base', base, 'deduction', ded, 'deduction_raw', raw_ded,
    'final', fin, 'raw_grade', public.perf_grade_of(fin), 'grade', g,
    'grade_word', public.perf_grade_word(g),
    'capped', case when rk > position(public.perf_grade_of(fin) in rank_of) then (case when l4 then 'D' else 'B' end) end,
    'l3', l3, 'l4', l4, 'review', l4,
    'eligible', ok, 'previous_grade', prev_g,
    'path', path,
    'suggested', jsonb_build_object(
      'delivery', case bd when 'green' then 15 when 'amber' then 12 when 'red' then 7.5 end,
      'delivery_band', bd,
      'client', case bc when 'green' then 20 when 'amber' then 16 when 'red' then 10 end,
      'client_band', bc,
      'comms', case bm when 'green' then 15 when 'amber' then 12 when 'red' then 7.5 end,
      'comms_band', bm));
end $$;

/* What My Work already knows: the tasks this person owned that were finished
   in the month with a due date, and how many were finished by it. A hint for
   the reviewer, never a score. */
create or replace function public.perf_ops_rate(p_member uuid, p_period date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d integer; o integer;
begin
  if to_regclass('public.ops_tasks') is null then return null; end if;
  select count(*),
         count(*) filter (where coalesce(t.completed_at, t.delivered_at)::date <= t.current_final_due_at::date)
    into d, o
    from public.ops_tasks t
   where t.completed_at >= p_period and t.completed_at < (p_period + interval '1 month')
     and t.current_final_due_at is not null
     and (select a.team_member_id from public.ops_task_assignees a
           where a.task_id = t.id and a.responsibility = 'owner'
           order by a.ended_at nulls first, a.assigned_at desc limit 1) = p_member;
  return jsonb_build_object('done', d, 'on_time', o);
end $$;

create or replace function public.perf_json(r public.perf_reviews, p_full boolean)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.team_members; pp public.perf_people; out jsonb;
begin
  select * into m from public.team_members where id = r.team_member_id;
  select * into pp from public.perf_people where team_member_id = r.team_member_id;
  out := jsonb_build_object(
    'id', r.id, 'team_member_id', r.team_member_id, 'period', r.period,
    'month', public.perf_month_word(r.period), 'status', r.status,
    'member', jsonb_build_object('name', m.name, 'staff_code', m.staff_code,
      'designation', m.designation, 'department', pp.department,
      'role_family', pp.role_family, 'runs_ads', coalesce(pp.runs_ads, false)),
    'scores', jsonb_build_object('output', r.s_output, 'accuracy', r.s_accuracy,
      'delivery', r.s_delivery, 'client', r.s_client, 'comms', r.s_comms,
      'initiative', r.s_initiative),
    'rates', jsonb_build_object('posting', r.r_posting, 'timeline', r.r_timeline,
      'satisfaction', r.r_satisfaction, 'pacing', r.r_pacing, 'sla', r.r_sla),
    'notes', r.notes, 'improvement', r.improvement, 'review_by', r.review_by,
    'reward_step', r.reward_step, 'serial', r.serial,
    'reviewer', (select name from public.team_members where id = r.reviewer_id),
    'released_at', r.released_at, 'dispute_until', r.dispute_until,
    'dispute_open', r.status = 'released' and r.dispute_until > now()
                    and not exists (select 1 from public.perf_disputes d
                                     where d.review_id = r.id and d.version = r.version),
    'acknowledged_at', r.acknowledged_at, 'finalised_at', r.finalised_at,
    'finalised_by', (select name from public.team_members where id = r.finalised_by),
    'version', r.version, 'rev', r.rev,
    'result', public.perf_calc(r),
    'breaches', public.perf_breaches_json(r.team_member_id, r.period, false),
    'disputes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', d.id, 'item', d.item, 'breach_id', d.breach_id, 'reason', d.reason,
        'breach_what', (select b.what from public.perf_breaches b where b.id = d.breach_id),
        'raised_at', d.raised_at, 'decision', d.decision, 'response', d.response,
        'before_value', d.before_value, 'after_value', d.after_value,
        'decided_by', (select name from public.team_members where id = d.decided_by),
        'decided_at', d.decided_at) order by d.raised_at)
        from public.perf_disputes d where d.review_id = r.id and d.version = r.version), '[]'::jsonb));
  if p_full then
    out := out || jsonb_build_object(
      'voided', (select coalesce(jsonb_agg(x), '[]'::jsonb)
                   from jsonb_array_elements(public.perf_breaches_json(r.team_member_id, r.period, true)) x
                  where x ->> 'voided_at' is not null),
      'ops', public.perf_ops_rate(r.team_member_id, r.period),
      'events', coalesce((select jsonb_agg(jsonb_build_object(
          'kind', e.kind, 'detail', e.detail, 'at', e.created_at,
          'by', coalesce((select name from public.team_members where id = e.actor_id), e.actor_email))
          order by e.created_at desc)
          from public.perf_events e where e.review_id = r.id), '[]'::jsonb));
  end if;
  return out;
end $$;

create or replace function public.perf_notify(p_member uuid, p_kind text, p_title text, p_dedupe text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_member is null or to_regclass('public.ops_notifications') is null then return; end if;
  insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
  values (p_member, null, p_kind, p_title, null, p_dedupe)
  on conflict (dedupe_key) do nothing;
end $$;

-- 6. Management: the month, one review, the breach log ------------------------------
create or replace function public.perf_month(p_token text, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; p date := date_trunc('month', p_period)::date;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  return jsonb_build_object(
    'period', p, 'month', public.perf_month_word(p),
    'people', coalesce((select jsonb_agg(x order by x ->> 'name') from (
      select jsonb_build_object(
        'team_member_id', t.id, 'name', t.name, 'staff_code', t.staff_code,
        'designation', t.designation,
        'department', pp.department, 'role_family', pp.role_family,
        'runs_ads', coalesce(pp.runs_ads, false),
        'reviewed', public.perf_reviewed(t.id),
        'breaches', (select count(*) from public.perf_breaches b
                      where b.team_member_id = t.id and b.period = p and b.voided_at is null),
        'review', case when r.id is null then null else jsonb_build_object(
          'id', r.id, 'status', r.status, 'result', public.perf_calc(r),
          'open_disputes', (select count(*) from public.perf_disputes d
                             where d.review_id = r.id and d.version = r.version and d.decision is null),
          'dispute_until', r.dispute_until) end) as x
        from public.team_members t
        left join public.perf_people pp on pp.team_member_id = t.id
        left join public.perf_reviews r on r.team_member_id = t.id and r.period = p
       where t.active and t.id <> m.id) q), '[]'::jsonb));
end $$;

create or replace function public.perf_open(p_token text, p_member uuid, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; p date := date_trunc('month', p_period)::date;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  select * into r from public.perf_reviews where team_member_id = p_member and period = p;
  if r.id is null then
    /* Not started: the shape of a draft, written nowhere until it is saved. */
    r.team_member_id := p_member; r.period := p; r.status := 'draft';
    r.notes := '{}'::jsonb; r.version := 1; r.rev := 0;
  end if;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_save(p_token text, p_member uuid, p_period date,
                                            p_payload jsonb, p_rev integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; r public.perf_reviews; p date := date_trunc('month', p_period)::date;
  sc jsonb := coalesce(p_payload -> 'scores', '{}'::jsonb);
  rt jsonb := coalesce(p_payload -> 'rates', '{}'::jsonb);
  k text; v jsonb; mx numeric; rb date;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if not exists (select 1 from public.team_members where id = p_member and active) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if jsonb_typeof(sc) <> 'object' or jsonb_typeof(rt) <> 'object'
     or (p_payload ? 'notes' and jsonb_typeof(p_payload -> 'notes') <> 'object') then
    return jsonb_build_object('error', 'bad-payload');
  end if;
  for k, v in select key, value from jsonb_each(sc) loop
    mx := case k when 'output' then 25 when 'accuracy' then 15 when 'delivery' then 15
                 when 'client' then 20 when 'comms' then 15 when 'initiative' then 10 end;
    if mx is null then return jsonb_build_object('error', 'bad-score', 'key', k); end if;
    if jsonb_typeof(v) <> 'null' then
      if jsonb_typeof(v) <> 'number' then return jsonb_build_object('error', 'bad-score', 'key', k, 'max', mx); end if;
      if (v #>> '{}')::numeric not between 0 and mx or round((v #>> '{}')::numeric, 1) <> (v #>> '{}')::numeric then
        return jsonb_build_object('error', 'bad-score', 'key', k, 'max', mx);
      end if;
    end if;
  end loop;
  for k, v in select key, value from jsonb_each(rt) loop
    mx := case k when 'pacing' then 1000 when 'posting' then 100 when 'timeline' then 100
                 when 'satisfaction' then 100 when 'sla' then 100 end;
    if mx is null then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
    if jsonb_typeof(v) <> 'null' then
      if jsonb_typeof(v) <> 'number' then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
      if (v #>> '{}')::numeric not between 0 and mx then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
    end if;
  end loop;
  if coalesce(p_payload ->> 'review_by', '') <> '' then
    begin
      rb := (p_payload ->> 'review_by')::date;
    exception when others then
      return jsonb_build_object('error', 'bad-date');
    end;
  end if;

  select * into r from public.perf_reviews where team_member_id = p_member and period = p for update;
  if r.id is null then
    insert into public.perf_reviews (team_member_id, period) values (p_member, p)
    on conflict (team_member_id, period) do nothing;
    select * into r from public.perf_reviews where team_member_id = p_member and period = p for update;
    perform public.perf_log(r.id, p_member, 'started', '{}'::jsonb);
  elsif p_rev is not null and r.rev <> p_rev then
    return jsonb_build_object('error', 'stale', 'record', public.perf_json(r, true));
  end if;
  /* The scores are the draft's. What the month asks of the person next (the
     improvement, the date it is reviewed by, the step or reward) is written
     at the 1-1 and may be filled in until the record is final. */
  if r.status = 'final' or (r.status <> 'draft'
       and (p_payload - 'improvement' - 'review_by' - 'reward_step') <> '{}'::jsonb) then
    return jsonb_build_object('error', 'not-draft');
  end if;

  update public.perf_reviews set
    s_output     = case when sc ? 'output'     then (sc ->> 'output')::numeric     else s_output end,
    s_accuracy   = case when sc ? 'accuracy'   then (sc ->> 'accuracy')::numeric   else s_accuracy end,
    s_delivery   = case when sc ? 'delivery'   then (sc ->> 'delivery')::numeric   else s_delivery end,
    s_client     = case when sc ? 'client'     then (sc ->> 'client')::numeric     else s_client end,
    s_comms      = case when sc ? 'comms'      then (sc ->> 'comms')::numeric      else s_comms end,
    s_initiative = case when sc ? 'initiative' then (sc ->> 'initiative')::numeric else s_initiative end,
    r_posting      = case when rt ? 'posting'      then (rt ->> 'posting')::numeric      else r_posting end,
    r_timeline     = case when rt ? 'timeline'     then (rt ->> 'timeline')::numeric     else r_timeline end,
    r_satisfaction = case when rt ? 'satisfaction' then (rt ->> 'satisfaction')::numeric else r_satisfaction end,
    r_pacing       = case when rt ? 'pacing'       then (rt ->> 'pacing')::numeric       else r_pacing end,
    r_sla          = case when rt ? 'sla'          then (rt ->> 'sla')::numeric          else r_sla end,
    notes       = case when p_payload ? 'notes' then coalesce(p_payload -> 'notes', '{}'::jsonb) else notes end,
    improvement = case when p_payload ? 'improvement' then nullif(btrim(p_payload ->> 'improvement'), '') else improvement end,
    review_by   = case when p_payload ? 'review_by' then rb else review_by end,
    reward_step = case when p_payload ? 'reward_step' then nullif(btrim(p_payload ->> 'reward_step'), '') else reward_step end,
    updated_at = now(), rev = rev + 1
  where id = r.id
  returning * into r;
  if p_payload <> '{}'::jsonb then
    perform public.perf_log(r.id, p_member, 'scored', jsonb_build_object('fields',
      (select coalesce(jsonb_agg(k2), '[]'::jsonb) from jsonb_object_keys(p_payload) k2)));
  end if;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_release(p_token text, p_review uuid, p_rev integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; tm public.team_members;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if p_rev is not null and r.rev <> p_rev then
    return jsonb_build_object('error', 'stale', 'record', public.perf_json(r, true));
  end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  if not (public.perf_calc(r) ->> 'complete')::boolean then
    return jsonb_build_object('error', 'incomplete');
  end if;
  select * into tm from public.team_members where id = r.team_member_id;
  if r.serial is null and coalesce(btrim(tm.staff_code), '') = '' then
    return jsonb_build_object('error', 'no-staff-code');
  end if;
  update public.perf_reviews set status = 'released', released_at = now(),
         dispute_until = now() + interval '3 days', reviewer_id = m.id,
         serial = coalesce(serial, 'ADHR/' || upper(btrim(tm.staff_code)) || '/PR' || to_char(period, 'YYMM')),
         rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'released', jsonb_build_object('version', r.version));
  perform public.perf_notify(r.team_member_id, 'perf.released',
    'Your ' || public.perf_month_word(r.period) || ' performance review is ready.',
    'perf.released.' || r.id || '.' || r.version);
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_unrelease(p_token text, p_review uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status <> 'released' or exists (select 1 from public.perf_disputes d
                                        where d.review_id = r.id and d.version = r.version) then
    return jsonb_build_object('error', 'cannot-return');
  end if;
  update public.perf_reviews set status = 'draft', released_at = null, dispute_until = null,
         rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'returned', jsonb_build_object('reason', btrim(p_reason)));
  perform public.perf_notify(r.team_member_id, 'perf.returned',
    'Your ' || public.perf_month_word(r.period) || ' review was taken back for correction.',
    'perf.returned.' || r.id || '.' || r.rev);
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_decide(p_token text, p_dispute uuid, p_decision text,
                                              p_response text, p_value numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; d public.perf_disputes; r public.perf_reviews;
  b public.perf_breaches; mx numeric; was numeric; col text;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_decision not in ('upheld', 'partly', 'not_upheld') then return jsonb_build_object('error', 'bad-decision'); end if;
  if coalesce(btrim(p_response), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into d from public.perf_disputes where id = p_dispute for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into r from public.perf_reviews where id = d.review_id for update;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status <> 'disputed' or d.decision is not null or d.version <> r.version then
    return jsonb_build_object('error', 'already-decided');
  end if;

  if d.item = 'breach' then
    select * into b from public.perf_breaches where id = d.breach_id for update;
    was := b.severity;
    if p_decision = 'upheld' then
      update public.perf_breaches set voided_at = now(), voided_by = m.id, void_reason = 'Dispute upheld'
       where id = b.id;
    elsif p_decision = 'partly' then
      if p_value is null or p_value not in (1, 2, 3) or p_value >= b.severity then
        return jsonb_build_object('error', 'bad-severity');
      end if;
      update public.perf_breaches set severity = p_value::integer where id = b.id;
    end if;
  else
    mx := case d.item when 'output' then 25 when 'accuracy' then 15 when 'delivery' then 15
                      when 'client' then 20 when 'comms' then 15 when 'initiative' then 10 end;
    col := 's_' || d.item;
    execute format('select %I from public.perf_reviews where id = $1', col) into was using r.id;
    if p_decision in ('upheld', 'partly') then
      if p_value is null or p_value < 0 or p_value > mx or round(p_value, 1) <> p_value then
        return jsonb_build_object('error', 'bad-score', 'max', mx);
      end if;
      execute format('update public.perf_reviews set %I = $1 where id = $2', col) using p_value, r.id;
    end if;
  end if;

  update public.perf_disputes set decision = p_decision, response = btrim(p_response),
         before_value = was,
         after_value = case when p_decision = 'not_upheld' then was
                            when d.item = 'breach' and p_decision = 'upheld' then 0
                            else p_value end,
         decided_by = m.id, decided_at = now()
   where id = d.id;
  if not exists (select 1 from public.perf_disputes x
                  where x.review_id = r.id and x.version = r.version and x.decision is null) then
    update public.perf_reviews set status = 'resolved' where id = r.id;
    perform public.perf_notify(r.team_member_id, 'perf.answered',
      'Your dispute on ' || public.perf_month_word(r.period) || ' has been answered.',
      'perf.answered.' || r.id || '.' || r.version);
  end if;
  update public.perf_reviews set rev = rev + 1, updated_at = now() where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'decided',
    jsonb_build_object('item', d.item, 'decision', p_decision, 'was', was,
                       'after', case when p_decision = 'not_upheld' then was else p_value end));
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_finalise(p_token text, p_review uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; res jsonb;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status = 'disputed' then return jsonb_build_object('error', 'open-dispute'); end if;
  if r.status not in ('released', 'resolved', 'acknowledged') then
    return jsonb_build_object('error', 'not-released');
  end if;
  if r.status <> 'acknowledged' and r.dispute_until > now() then
    return jsonb_build_object('error', 'window-open', 'until', r.dispute_until);
  end if;
  res := public.perf_calc(r);
  update public.perf_reviews set status = 'final', result = res, finalised_at = now(),
         finalised_by = m.id, rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'finalised',
    jsonb_build_object('grade', res ->> 'grade', 'final', res -> 'final'));
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_reopen(p_token text, p_review uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews;
begin
  err := public.perf_check(p_token, 'manage');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status <> 'final' then return jsonb_build_object('error', 'not-final'); end if;
  perform public.perf_log(r.id, r.team_member_id, 'reopened',
    jsonb_build_object('reason', btrim(p_reason), 'was', public.perf_json(r, false)));
  update public.perf_reviews set status = 'draft', result = null, released_at = null,
         dispute_until = null, acknowledged_at = null, finalised_at = null, finalised_by = null,
         version = version + 1, rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_breach_log(p_token text, p_member uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; on_ date; p date; cat text; sev integer; rep boolean;
  st text; nb public.perf_breaches;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if not exists (select 1 from public.team_members where id = p_member and active) then
    return jsonb_build_object('error', 'not-found');
  end if;
  begin on_ := (p_payload ->> 'occurred_on')::date; exception when others then on_ := null; end;
  if on_ is null or on_ > current_date then return jsonb_build_object('error', 'bad-date'); end if;
  cat := p_payload ->> 'category';
  if cat is null or cat not in ('client', 'delivery', 'compliance', 'asset') then
    return jsonb_build_object('error', 'bad-category');
  end if;
  sev := case when (p_payload ->> 'severity') ~ '^[1-4]$' then (p_payload ->> 'severity')::integer end;
  if sev is null then return jsonb_build_object('error', 'bad-severity'); end if;
  if coalesce(btrim(p_payload ->> 'what'), '') = '' then return jsonb_build_object('error', 'what-needed'); end if;
  p := date_trunc('month', on_)::date;
  select status into st from public.perf_reviews where team_member_id = p_member and period = p;
  if st is not null and st <> 'draft' then
    return jsonb_build_object('error', 'month-released', 'month', public.perf_month_word(p));
  end if;
  /* The same kind of breach earlier in the same quarter is a repeat, unless
     the reviewer says otherwise. */
  rep := case when p_payload ? 'repeated' and jsonb_typeof(p_payload -> 'repeated') = 'boolean'
              then (p_payload ->> 'repeated')::boolean
              else exists (select 1 from public.perf_breaches b
                            where b.team_member_id = p_member and b.category = cat
                              and b.voided_at is null
                              and date_trunc('quarter', b.occurred_on) = date_trunc('quarter', on_)
                              and b.occurred_on <= on_) end;
  insert into public.perf_breaches (team_member_id, occurred_on, period, category, severity,
                                    repeated, late, what, evidence, logged_by)
  values (p_member, on_, p, cat, sev, rep, coalesce((p_payload ->> 'late')::boolean, false),
          btrim(p_payload ->> 'what'), nullif(btrim(p_payload ->> 'evidence'), ''), m.id)
  returning * into nb;
  perform public.perf_log((select id from public.perf_reviews where team_member_id = p_member and period = p),
    p_member, 'breach_logged', jsonb_build_object('breach', nb.id, 'category', cat, 'severity', sev,
      'repeated', rep, 'late', nb.late, 'deduction', public.perf_deduction(sev, rep, nb.late)));
  return jsonb_build_object('ok', true, 'id', nb.id, 'repeated', rep,
    'deduction', public.perf_deduction(sev, rep, nb.late), 'period', p);
end $$;

create or replace function public.perf_breach_void(p_token text, p_breach uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; b public.perf_breaches; st text;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into b from public.perf_breaches where id = p_breach for update;
  if b.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if b.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if b.voided_at is not null then return jsonb_build_object('ok', true); end if;
  select status into st from public.perf_reviews where team_member_id = b.team_member_id and period = b.period;
  if st is not null and st <> 'draft' then
    return jsonb_build_object('error', 'month-released', 'month', public.perf_month_word(b.period));
  end if;
  update public.perf_breaches set voided_at = now(), voided_by = m.id, void_reason = btrim(p_reason)
   where id = b.id;
  perform public.perf_log((select id from public.perf_reviews where team_member_id = b.team_member_id and period = b.period),
    b.team_member_id, 'breach_voided', jsonb_build_object('breach', b.id, 'reason', btrim(p_reason)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.perf_profile_set(p_token text, p_member uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; dep text; fam text;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  dep := nullif(p_payload ->> 'department', '');
  fam := nullif(p_payload ->> 'role_family', '');
  if dep is not null and dep not in ('creative', 'marketing') then return jsonb_build_object('error', 'bad-department'); end if;
  if fam is not null and fam not in ('visual', 'video', 'planner', 'account') then return jsonb_build_object('error', 'bad-role'); end if;
  insert into public.perf_people (team_member_id, department, role_family, runs_ads, reviewed)
  values (p_member, dep, fam, coalesce((p_payload ->> 'runs_ads')::boolean, false),
          case when p_payload ? 'reviewed' then (p_payload ->> 'reviewed')::boolean end)
  on conflict (team_member_id) do update set
    department = case when p_payload ? 'department' then dep else perf_people.department end,
    role_family = case when p_payload ? 'role_family' then fam else perf_people.role_family end,
    runs_ads = case when p_payload ? 'runs_ads' then coalesce((p_payload ->> 'runs_ads')::boolean, false) else perf_people.runs_ads end,
    reviewed = case when p_payload ? 'reviewed' then (p_payload ->> 'reviewed')::boolean else perf_people.reviewed end,
    updated_at = now();
  perform public.perf_log(null, p_member, 'profile', p_payload);
  return jsonb_build_object('ok', true);
end $$;

-- 7. The member: their own months, a dispute, an acknowledgement --------------------
create or replace function public.perf_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  return jsonb_build_object('reviews', coalesce((
    select jsonb_agg(public.perf_json(r, false) order by r.period desc)
      from public.perf_reviews r
     where r.team_member_id = m.id and r.status <> 'draft'), '[]'::jsonb));
end $$;

create or replace function public.perf_dispute(p_review uuid, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews; it jsonb; n integer := 0; itm text; bid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status <> 'released' or exists (select 1 from public.perf_disputes d
                                        where d.review_id = r.id and d.version = r.version) then
    return jsonb_build_object('error', 'dispute-closed');
  end if;
  if r.dispute_until <= now() then return jsonb_build_object('error', 'window-closed'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('error', 'nothing-disputed');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    itm := it ->> 'item';
    if itm is null or itm not in ('output', 'accuracy', 'delivery', 'client', 'comms', 'initiative', 'breach') then
      return jsonb_build_object('error', 'bad-item');
    end if;
    if coalesce(btrim(it ->> 'reason'), '') = '' then return jsonb_build_object('error', 'reason-needed', 'item', itm); end if;
    bid := null;
    if itm = 'breach' then
      begin bid := (it ->> 'breach_id')::uuid; exception when others then bid := null; end;
      if bid is null or not exists (select 1 from public.perf_breaches b
                                     where b.id = bid and b.team_member_id = m.id
                                       and b.period = r.period and b.voided_at is null) then
        return jsonb_build_object('error', 'bad-item');
      end if;
    end if;
    insert into public.perf_disputes (review_id, version, item, breach_id, reason)
    values (r.id, r.version, itm, bid, btrim(it ->> 'reason'));
    n := n + 1;
  end loop;
  update public.perf_reviews set status = 'disputed', rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'disputed', jsonb_build_object('items', n));
  perform public.perf_notify(r.reviewer_id, 'perf.disputed',
    m.name || ' disputed ' || public.perf_month_word(r.period) || '.',
    'perf.disputed.' || r.id || '.' || r.version);
  return public.perf_json(r, false);
end $$;

create or replace function public.perf_acknowledge(p_review uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status = 'acknowledged' or r.status = 'final' then return public.perf_json(r, false); end if;
  if r.status = 'disputed' then return jsonb_build_object('error', 'open-dispute'); end if;
  update public.perf_reviews set status = 'acknowledged', acknowledged_at = now(),
         dispute_until = least(dispute_until, now()), rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'acknowledged', '{}'::jsonb);
  return public.perf_json(r, false);
end $$;

/* A copy was drawn: by the member for their own month, or by management with
   a live unlock. The record keeps who printed what. */
create or replace function public.perf_printed(p_review uuid, p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.perf_reviews where id = p_review;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id <> m.id and public.perf_check(p_token, 'view') is not null then
    return jsonb_build_object('error', 'denied');
  end if;
  if r.team_member_id = m.id and r.status = 'draft' then return jsonb_build_object('error', 'not-found'); end if;
  perform public.perf_log(r.id, r.team_member_id, 'printed', jsonb_build_object('version', r.version));
  return jsonb_build_object('ok', true);
end $$;

-- 8. Who may call what ----------------------------------------------------------------
/* Postgres lets PUBLIC execute every new function and Supabase grants anon
   and authenticated as well, so each is closed first. The helpers stay
   closed: the calculator and the record builder would read anybody's
   breaches for whoever called them, and the code reset is the owner's in the
   SQL editor. The functions a page calls are opened to a signed-in browser
   and answer for themselves. */
revoke all on function public.perf_code_reset(text) from public, anon, authenticated;
revoke all on function public.perf_log(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.perf_calc(public.perf_reviews) from public, anon, authenticated;
revoke all on function public.perf_json(public.perf_reviews, boolean) from public, anon, authenticated;
revoke all on function public.perf_ops_rate(uuid, date) from public, anon, authenticated;
revoke all on function public.perf_breaches_json(uuid, date, boolean) from public, anon, authenticated;
revoke all on function public.perf_notify(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.perf_reviewed(uuid) from public, anon, authenticated;
revoke all on function public.perf_check(text, text) from public, anon, authenticated;
revoke all on function public.perf_events_frozen() from public, anon, authenticated;
revoke all on function public.perf_grade_of(numeric) from public, anon, authenticated;
revoke all on function public.perf_grade_word(text) from public, anon, authenticated;
revoke all on function public.perf_deduction(integer, boolean, boolean) from public, anon, authenticated;
revoke all on function public.perf_band(numeric, numeric) from public, anon, authenticated;
revoke all on function public.perf_pacing_band(numeric) from public, anon, authenticated;
revoke all on function public.perf_month_word(date) from public, anon, authenticated;
revoke all on function public.perf_code_set() from public, anon, authenticated;
revoke all on function public.perf_gate_info() from public, anon, authenticated;
revoke all on function public.perf_unlock(text) from public, anon, authenticated;
revoke all on function public.perf_lock(text) from public, anon, authenticated;
revoke all on function public.perf_month(text, date) from public, anon, authenticated;
revoke all on function public.perf_open(text, uuid, date) from public, anon, authenticated;
revoke all on function public.perf_save(text, uuid, date, jsonb, integer) from public, anon, authenticated;
revoke all on function public.perf_release(text, uuid, integer) from public, anon, authenticated;
revoke all on function public.perf_unrelease(text, uuid, text) from public, anon, authenticated;
revoke all on function public.perf_decide(text, uuid, text, text, numeric) from public, anon, authenticated;
revoke all on function public.perf_finalise(text, uuid) from public, anon, authenticated;
revoke all on function public.perf_reopen(text, uuid, text) from public, anon, authenticated;
revoke all on function public.perf_breach_log(text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_breach_void(text, uuid, text) from public, anon, authenticated;
revoke all on function public.perf_profile_set(text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_mine() from public, anon, authenticated;
revoke all on function public.perf_dispute(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_acknowledge(uuid) from public, anon, authenticated;
revoke all on function public.perf_printed(uuid, text) from public, anon, authenticated;
grant execute on function public.perf_code_set() to authenticated;
grant execute on function public.perf_gate_info() to authenticated;
grant execute on function public.perf_unlock(text) to authenticated;
grant execute on function public.perf_lock(text) to authenticated;
grant execute on function public.perf_month(text, date) to authenticated;
grant execute on function public.perf_open(text, uuid, date) to authenticated;
grant execute on function public.perf_save(text, uuid, date, jsonb, integer) to authenticated;
grant execute on function public.perf_release(text, uuid, integer) to authenticated;
grant execute on function public.perf_unrelease(text, uuid, text) to authenticated;
grant execute on function public.perf_decide(text, uuid, text, text, numeric) to authenticated;
grant execute on function public.perf_finalise(text, uuid) to authenticated;
grant execute on function public.perf_reopen(text, uuid, text) to authenticated;
grant execute on function public.perf_breach_log(text, uuid, jsonb) to authenticated;
grant execute on function public.perf_breach_void(text, uuid, text) to authenticated;
grant execute on function public.perf_profile_set(text, uuid, jsonb) to authenticated;
grant execute on function public.perf_mine() to authenticated;
grant execute on function public.perf_dispute(uuid, jsonb) to authenticated;
grant execute on function public.perf_acknowledge(uuid) to authenticated;
grant execute on function public.perf_printed(uuid, text) to authenticated;

-- END OF PERFORMANCE REVIEWS ------------------------------------------------
