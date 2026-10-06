-- ===========================================================================
-- HEALTH CHECK-INS — a colleague's own check-in on body, mind, sleep, energy
-- and workload every half month once they have agreed to it, a request to
-- talk to the colleague of their choice, and every colleague's check-ins for
-- the holders of Team: Health.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/health.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-07: "a health section (company concerns
-- about their physical health, mental health, body health, sleep health
-- etc.)"; answered: an admin alone views everyone's health data, set in the
-- user permissions; colleagues declare that they accept first; every two
-- weeks, reminded with the month's reflection; the check-in and Ask for a
-- talk)
--   1. `health_consents` (colleague, when agreed, the wording agreed to,
--      when withdrawn) and `health_log` (agreed, withdrawn; append only).
--      Health is sensitive personal data (PDPA 2010, s.40): nothing is
--      asked or kept before the colleague agrees, and withdrawing stops the
--      check-ins and takes their answers out of Team: Health.
--   2. `health_checkins` (colleague, the half month it is for: the 1st to
--      the 15th or the 16th to the month's end, MYT; five scales from 1 to
--      5 where 5 is well: body, mind, sleep, energy, workload; a note up to
--      1000 characters): one a half month, changed until that half ends.
--   3. `health_talks` (who asks, who with, a note, open / done /
--      withdrawn): the colleague asked is told through the bell and a push
--      (`health.talk`, the asker's name alone, never the note), reads the
--      note in My HR, Health and marks it done; the asker withdraws it.
--      Each way back reopens it.
--   4. The colleague's own, behind the fresh proof My HR asks
--      (`perf_mine_gate`): `health_mine()`, `health_consent(p_on)`,
--      `health_checkin_save(p_scores, p_note)`, `health_talk_ask(p_with,
--      p_note)`, `health_talk_set(p_id, p_status)`.
--   5. Team: Health (`team.health`, a granted part: an admin's by itself,
--      any other group's once set, at Work): `health_team()` answers every
--      active colleague with their consent and, while it stands, their
--      check-ins of the last twelve half months, and the talks of the last
--      ninety days.
--   Every table: RLS on, no policy, no grant. Nothing about health is
--   written to the Activity record, and no notification carries a score or
--   a note.
--
-- ROLLBACK (in the SQL Editor)
--   drop the eleven functions below, then the four tables.
-- ===========================================================================

create table if not exists public.health_consents (
  team_member_id uuid primary key references public.team_members(id) on delete cascade,
  agreed_at      timestamptz not null default now(),
  wording        integer not null default 1,
  withdrawn_at   timestamptz,
  updated_at     timestamptz not null default now()
);
create table if not exists public.health_log (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  kind           text not null check (kind in ('agreed', 'withdrawn')),
  wording        integer,
  created_at     timestamptz not null default now()
);
create table if not exists public.health_checkins (
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  half           date not null check (extract(day from half) in (1, 16)),
  body           smallint not null check (body between 1 and 5),
  mind           smallint not null check (mind between 1 and 5),
  sleep          smallint not null check (sleep between 1 and 5),
  energy         smallint not null check (energy between 1 and 5),
  workload       smallint not null check (workload between 1 and 5),
  note           text check (note is null or char_length(note) <= 1000),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (team_member_id, half)
);
create table if not exists public.health_talks (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  with_id        uuid not null references public.team_members(id) on delete cascade,
  note           text check (note is null or char_length(note) <= 1000),
  status         text not null default 'open' check (status in ('open', 'done', 'withdrawn')),
  created_at     timestamptz not null default now(),
  closed_at      timestamptz,
  closed_by      uuid references public.team_members(id) on delete set null
);
create index if not exists health_talks_with_idx on public.health_talks (with_id, status);
create index if not exists health_talks_member_idx on public.health_talks (team_member_id, status);

alter table public.health_consents enable row level security;
alter table public.health_log enable row level security;
alter table public.health_checkins enable row level security;
alter table public.health_talks enable row level security;
revoke all on public.health_consents, public.health_log, public.health_checkins, public.health_talks
  from public, anon, authenticated;

/* Today in Malaysia, the one clock health asks. */
create or replace function public.health_today()
returns date language sql stable as $$
  select (now() at time zone 'Asia/Kuala_Lumpur')::date
$$;
/* The half month a day falls in, named by its first day. */
create or replace function public.health_half(p_day date)
returns date language sql immutable as $$
  select case when extract(day from p_day) <= 15 then date_trunc('month', p_day)::date
              else (date_trunc('month', p_day) + interval '15 days')::date end
$$;
create or replace function public.health_half_end(p_half date)
returns date language sql immutable as $$
  select case when extract(day from p_half) = 1 then (p_half + interval '14 days')::date
              else (date_trunc('month', p_half) + interval '1 month' - interval '1 day')::date end
$$;
/* Whether a colleague's agreement stands. */
create or replace function public.health_agreed(p_member uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.health_consents c
                  where c.team_member_id = p_member and c.withdrawn_at is null)
$$;
create or replace function public.health_checkin_json(c public.health_checkins)
returns jsonb language sql stable as $$
  select jsonb_build_object('half', c.half, 'half_end', public.health_half_end(c.half),
    'scales', jsonb_build_object('body', c.body, 'mind', c.mind, 'sleep', c.sleep,
                                 'energy', c.energy, 'workload', c.workload),
    'note', c.note, 'at', c.updated_at)
$$;
revoke all on function public.health_today() from public, anon, authenticated;
revoke all on function public.health_half(date) from public, anon, authenticated;
revoke all on function public.health_half_end(date) from public, anon, authenticated;
revoke all on function public.health_agreed(uuid) from public, anon, authenticated;
revoke all on function public.health_checkin_json(public.health_checkins) from public, anon, authenticated;

create or replace function public.health_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; c public.health_consents; h date;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  select * into c from public.health_consents where team_member_id = m.id;
  h := public.health_half(public.health_today());
  return jsonb_build_object(
    'consent', case when c.team_member_id is null then null else jsonb_build_object(
      'agreed_at', c.agreed_at, 'withdrawn_at', c.withdrawn_at, 'wording', c.wording) end,
    'half', h, 'half_end', public.health_half_end(h),
    'history', coalesce((select jsonb_agg(public.health_checkin_json(x) order by x.half desc)
                           from (select * from public.health_checkins k
                                  where k.team_member_id = m.id order by k.half desc limit 12) x), '[]'::jsonb),
    'asked', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'with', w.name, 'with_id', t.with_id,
                         'note', t.note, 'status', t.status, 'at', t.created_at, 'closed_at', t.closed_at)
                         order by (t.status = 'open') desc, t.created_at desc)
                         from (select * from public.health_talks x where x.team_member_id = m.id
                                order by (x.status = 'open') desc, x.created_at desc limit 20) t
                         join public.team_members w on w.id = t.with_id), '[]'::jsonb),
    'asked_me', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'from', f.name, 'from_id', t.team_member_id,
                            'note', t.note, 'status', t.status, 'at', t.created_at, 'closed_at', t.closed_at)
                            order by (t.status = 'open') desc, t.created_at desc)
                            from (select * from public.health_talks x where x.with_id = m.id and x.status <> 'withdrawn'
                                   order by (x.status = 'open') desc, x.created_at desc limit 20) t
                            join public.team_members f on f.id = t.team_member_id), '[]'::jsonb),
    'colleagues', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'staff_code', t.staff_code)
                              order by t.staff_code nulls last, t.name)
                              from public.team_members t where t.active and t.id <> m.id), '[]'::jsonb));
end $$;

create or replace function public.health_consent(p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; n integer;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  if coalesce(p_on, false) then
    insert into public.health_consents (team_member_id, agreed_at, wording, withdrawn_at, updated_at)
    values (m.id, now(), 1, null, now())
    on conflict (team_member_id) do update
       set agreed_at = now(), wording = 1, withdrawn_at = null, updated_at = now();
    insert into public.health_log (team_member_id, kind, wording) values (m.id, 'agreed', 1);
  else
    update public.health_consents set withdrawn_at = now(), updated_at = now()
     where team_member_id = m.id and withdrawn_at is null;
    get diagnostics n = row_count;
    if n = 0 then return jsonb_build_object('error', 'not-agreed'); end if;
    insert into public.health_log (team_member_id, kind) values (m.id, 'withdrawn');
  end if;
  return public.health_mine();
end $$;

create or replace function public.health_checkin_save(p_scores jsonb, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; k text; v numeric; h date;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  if not public.health_agreed(m.id) then return jsonb_build_object('error', 'no-consent'); end if;
  if jsonb_typeof(p_scores) is distinct from 'object' then return jsonb_build_object('error', 'incomplete'); end if;
  foreach k in array array['body', 'mind', 'sleep', 'energy', 'workload'] loop
    if jsonb_typeof(p_scores -> k) is distinct from 'number' then
      return jsonb_build_object('error', 'incomplete', 'item', k);
    end if;
    v := (p_scores ->> k)::numeric;
    if v < 1 or v > 5 or v <> trunc(v) then return jsonb_build_object('error', 'bad-score', 'item', k); end if;
  end loop;
  if char_length(coalesce(p_note, '')) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  h := public.health_half(public.health_today());
  insert into public.health_checkins (team_member_id, half, body, mind, sleep, energy, workload, note)
  values (m.id, h, (p_scores ->> 'body')::smallint, (p_scores ->> 'mind')::smallint,
          (p_scores ->> 'sleep')::smallint, (p_scores ->> 'energy')::smallint,
          (p_scores ->> 'workload')::smallint, nullif(btrim(coalesce(p_note, '')), ''))
  on conflict (team_member_id, half) do update
     set body = excluded.body, mind = excluded.mind, sleep = excluded.sleep, energy = excluded.energy,
         workload = excluded.workload, note = excluded.note, updated_at = now();
  return public.health_mine();
end $$;

create or replace function public.health_talk_ask(p_with uuid, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; t uuid;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  if not public.health_agreed(m.id) then return jsonb_build_object('error', 'no-consent'); end if;
  if p_with is null or p_with = m.id
     or not exists (select 1 from public.team_members x where x.id = p_with and x.active) then
    return jsonb_build_object('error', 'bad-colleague');
  end if;
  if char_length(coalesce(p_note, '')) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  if exists (select 1 from public.health_talks x
              where x.team_member_id = m.id and x.with_id = p_with and x.status = 'open') then
    return jsonb_build_object('error', 'already-asked');
  end if;
  insert into public.health_talks (team_member_id, with_id, note)
  values (m.id, p_with, nullif(btrim(coalesce(p_note, '')), ''))
  returning id into t;
  perform public.perf_notify(p_with, 'health.talk', m.name || ' would like to talk.', 'health.talk.' || t);
  return public.health_mine();
end $$;

/* The asker withdraws and asks again; the colleague asked marks it done and
   reopens it. */
create or replace function public.health_talk_set(p_id uuid, p_status text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; t public.health_talks;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  select * into t from public.health_talks where id = p_id for update;
  if t.id is null or m.id not in (t.team_member_id, t.with_id) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if not ((m.id = t.team_member_id and ((t.status = 'open' and p_status = 'withdrawn')
                                     or (t.status = 'withdrawn' and p_status = 'open')))
       or (m.id = t.with_id and ((t.status = 'open' and p_status = 'done')
                              or (t.status = 'done' and p_status = 'open')))) then
    return jsonb_build_object('error', 'bad-status');
  end if;
  if m.id = t.team_member_id and p_status = 'open' and not public.health_agreed(m.id) then
    return jsonb_build_object('error', 'no-consent');
  end if;
  update public.health_talks
     set status = p_status,
         closed_at = case when p_status = 'open' then null else now() end,
         closed_by = case when p_status = 'open' then null else m.id end
   where id = t.id;
  return public.health_mine();
end $$;

/* Team: Health. Every active colleague, their agreement and, while it
   stands, their check-ins; the talks of the last ninety days, a note shown
   only while its asker's agreement stands. */
create or replace function public.health_team()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; h date;
begin
  m := public.ops_me();
  if m.id is null or not public.ops_granted('team.health', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  h := public.health_half(public.health_today());
  return jsonb_build_object('half', h, 'half_end', public.health_half_end(h),
    'people', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'staff_code', t.staff_code, 'designation', t.designation,
        'department', t.department, 'role', t.role,
        'consent', case when c.team_member_id is null then null else jsonb_build_object(
          'agreed_at', c.agreed_at, 'withdrawn_at', c.withdrawn_at) end,
        'checkins', case when c.team_member_id is not null and c.withdrawn_at is null then coalesce((
            select jsonb_agg(public.health_checkin_json(x) order by x.half desc)
              from (select * from public.health_checkins k where k.team_member_id = t.id
                     order by k.half desc limit 12) x), '[]'::jsonb) else '[]'::jsonb end)
        order by t.staff_code nulls last, t.name)
        from public.team_members t
        left join public.health_consents c on c.team_member_id = t.id
       where t.active), '[]'::jsonb),
    'talks', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'from', f.name, 'from_id', k.team_member_id, 'with', w.name, 'with_id', k.with_id,
        'note', case when public.health_agreed(k.team_member_id) then k.note end,
        'status', k.status, 'at', k.created_at, 'closed_at', k.closed_at)
        order by (k.status = 'open') desc, k.created_at desc)
        from public.health_talks k
        join public.team_members f on f.id = k.team_member_id
        join public.team_members w on w.id = k.with_id
       where k.status <> 'withdrawn' and k.created_at > now() - interval '90 days'), '[]'::jsonb));
end $$;

revoke all on function public.health_mine() from public, anon, authenticated;
revoke all on function public.health_consent(boolean) from public, anon, authenticated;
revoke all on function public.health_checkin_save(jsonb, text) from public, anon, authenticated;
revoke all on function public.health_talk_ask(uuid, text) from public, anon, authenticated;
revoke all on function public.health_talk_set(uuid, text) from public, anon, authenticated;
revoke all on function public.health_team() from public, anon, authenticated;
grant execute on function public.health_mine() to authenticated;
grant execute on function public.health_consent(boolean) to authenticated;
grant execute on function public.health_checkin_save(jsonb, text) to authenticated;
grant execute on function public.health_talk_ask(uuid, text) to authenticated;
grant execute on function public.health_talk_set(uuid, text) to authenticated;
grant execute on function public.health_team() to authenticated;

-- END OF HEALTH CHECK-INS -----------------------------------------------------
