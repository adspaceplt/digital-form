-- ===========================================================================
-- HIRING — candidates, the colleagues on each, and the candidate's own page
-- (2026-11-16, release H2 step A)
-- ===========================================================================
-- WHY (the user, 2026-11-16, HR-SPEC.md decisions 1 and 3): hiring moves
-- into the portal. An admin adds a candidate (name, email, phone, the CV as a
-- link or a file, where they came from, the position); a candidate never
-- holds an account and reads one private page of their own
-- (`/careers/?k=`). Who may hire is a granted part, `team.hiring`, an admin
-- tool: an admin's by itself, any other group's only once an admin gives
-- it. On a candidate an admin adds colleagues as Owner (decides and sends)
-- or Interviews (sees that candidate and scores); such a colleague sees that
-- candidate alone.
--
-- WHAT IT CHANGES
--   * `hiring_candidates`, `hiring_people` and `hiring_events` (RLS on, no
--     policy, no grant): every read and write goes through the functions
--     below. A candidate's history is `hiring_events`, never the Activity
--     record, so a candidate's personal details reach only the people on
--     that candidate.
--   * `hiring_role(p_candidate)`: admin (the part), owner, interviews, or
--     nothing. `hiring_mine()` counts the live candidates the caller holds
--     a place on (the rail draws Hiring for them).
--   * `hiring_list()`, `hiring_get(p_id)`, `hiring_add(...)`,
--     `hiring_save(p_id, p_values, p_expected)`, `hiring_person_set`,
--     `hiring_person_remove`, `hiring_remove` / `hiring_restore`,
--     `hiring_delete(p_id, p_name)`, `hiring_link(p_id, p_reset)`.
--   * `careers_read(p_key)` (anon): the candidate's page; the link ends 30
--     days after the last step (`hiring_link_days`, a Business setting with
--     its Settings row in step C, decision 13; until it is saved, 30).
--   * The private Storage bucket `hiring` for a CV file (20 MB, PDF or
--     Word), read by anyone on that candidate, added and removed by an
--     admin or the candidate's Owner (`hiring_file_ok`).
--   * `rail_order_set` takes `hiring` among the sections a colleague arranges.
--   * `team_roles_admin_guard` holds `team.hiring` (and `team.personnel`,
--     the Personnel release's part) with the other admin tools.
--
-- ORDER
--   The pages first (an old tab never asks these), then this file through
--   the connector less its STORAGE block, then the STORAGE block in the SQL
--   Editor as a run of its own (it holds a drop),
--   then 2026-10-07-function-hygiene.sql again (`open_to_anon` names
--   `careers_read`). A failed step leaves the section reading "This feature
--   is not available yet."
--
-- Safe to run twice. Rollback: drop the three tables and the functions
-- named above; the bucket's three policies `hiring_files_*` and the bucket;
-- run SUPER ADMIN's `team_roles_admin_guard` again.
-- ===========================================================================

-- HIRING ---------------------------------------------------------------------

create table if not exists public.hiring_candidates (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 2 and 120),
  email        text not null check (char_length(email) between 5 and 160 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone        text check (phone is null or char_length(phone) between 6 and 30),
  position     text not null check (char_length(position) between 2 and 80),
  source       text not null check (source in ('jobstreet', 'linkedin', 'indeed', 'referral', 'website', 'walk_in', 'other')),
  cv_url       text check (cv_url is null or (cv_url ~ '^https://' and cv_url !~ '[\s"''<>`\\]' and char_length(cv_url) <= 500)),
  cv_path      text check (cv_path is null or char_length(cv_path) <= 300),
  cv_name      text check (cv_name is null or char_length(cv_name) <= 200),
  note         text check (note is null or char_length(note) <= 2000),
  stage        text not null default 'new'
               check (stage in ('new', 'invited', 'interview', 'offer', 'hired', 'pool', 'closed')),
  link_key     text unique check (link_key is null or link_key ~ '^[a-z0-9]{8}$'),
  last_step_at timestamptz not null default now(),
  idem         text unique,
  created_by   uuid references public.team_members(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  removed_at   timestamptz,
  removed_by   uuid references public.team_members(id) on delete set null
);

create table if not exists public.hiring_people (
  candidate_id   uuid not null references public.hiring_candidates(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  role           text not null check (role in ('owner', 'interviews')),
  added_by       uuid references public.team_members(id) on delete set null,
  added_at       timestamptz not null default now(),
  primary key (candidate_id, team_member_id)
);

create table if not exists public.hiring_events (
  id           uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.hiring_candidates(id) on delete cascade,
  actor        text not null,
  action       text not null,
  detail       text,
  created_at   timestamptz not null default now()
);
create index if not exists hiring_events_candidate_idx on public.hiring_events (candidate_id, created_at desc);

alter table public.hiring_candidates enable row level security;
alter table public.hiring_people enable row level security;
alter table public.hiring_events enable row level security;
revoke all on table public.hiring_candidates from public, anon, authenticated;
revoke all on table public.hiring_people from public, anon, authenticated;
revoke all on table public.hiring_events from public, anon, authenticated;

/* Who the caller is on a candidate: admin (the granted part), owner,
   interviews, or nothing. A removed candidate is the part's alone. */
create or replace function public.hiring_role(p_candidate uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text;
begin
  if me.id is null then return null; end if;
  if public.ops_granted('team.hiring', 'work') then return 'admin'; end if;
  select p.role into v_role
    from public.hiring_people p join public.hiring_candidates c on c.id = p.candidate_id
   where p.candidate_id = p_candidate and p.team_member_id = me.id and c.removed_at is null;
  return v_role;
end $$;
revoke all on function public.hiring_role(uuid) from public, anon, authenticated;

create or replace function public.hiring_log(p_candidate uuid, p_action text, p_detail text)
returns void language plpgsql security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (p_candidate, coalesce(me.name, 'System'), p_action, p_detail);
end $$;
revoke all on function public.hiring_log(uuid, text, text) from public, anon, authenticated;

/* The live candidates the caller holds a place on: the rail draws Hiring
   for a colleague with one, whatever their group. */
create or replace function public.hiring_mine()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true, 'admin', public.ops_granted('team.hiring', 'work'),
    'count', (select count(*) from public.hiring_people p join public.hiring_candidates c on c.id = p.candidate_id
               where p.team_member_id = me.id and c.removed_at is null));
end $$;
grant execute on function public.hiring_mine() to authenticated;

/* The checks every write of a candidate's details makes. */
create or replace function public.hiring_values(p jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  o jsonb := '{}'::jsonb;
  v text;
  d text;
begin
  if p ? 'name' then
    v := regexp_replace(btrim(coalesce(p->>'name', '')), '\s+', ' ', 'g');
    if char_length(v) < 2 or char_length(v) > 120 then return jsonb_build_object('error', 'bad-name'); end if;
    o := o || jsonb_build_object('name', v);
  end if;
  if p ? 'email' then
    v := lower(btrim(coalesce(p->>'email', '')));
    if v !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v) > 160 then return jsonb_build_object('error', 'bad-email'); end if;
    o := o || jsonb_build_object('email', v);
  end if;
  if p ? 'phone' then
    v := btrim(coalesce(p->>'phone', ''));
    d := regexp_replace(v, '[^0-9]', '', 'g');
    if v <> '' and (char_length(d) < 8 or char_length(d) > 15 or v !~ '^\+?[0-9 ()-]+$') then
      return jsonb_build_object('error', 'bad-phone');
    end if;
    o := o || jsonb_build_object('phone', nullif(v, ''));
  end if;
  if p ? 'position' then
    v := regexp_replace(btrim(coalesce(p->>'position', '')), '\s+', ' ', 'g');
    if char_length(v) < 2 or char_length(v) > 80 then return jsonb_build_object('error', 'bad-position'); end if;
    o := o || jsonb_build_object('position', v);
  end if;
  if p ? 'source' then
    v := coalesce(p->>'source', '');
    if v not in ('jobstreet', 'linkedin', 'indeed', 'referral', 'website', 'walk_in', 'other') then
      return jsonb_build_object('error', 'bad-source');
    end if;
    o := o || jsonb_build_object('source', v);
  end if;
  if p ? 'cv_url' then
    v := btrim(coalesce(p->>'cv_url', ''));
    if v <> '' and (v !~ '^https://[^\s"''<>`\\]+$' or char_length(v) > 500) then return jsonb_build_object('error', 'bad-cv'); end if;
    o := o || jsonb_build_object('cv_url', nullif(v, ''));
  end if;
  if p ? 'note' then
    v := btrim(coalesce(p->>'note', ''));
    if char_length(v) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
    o := o || jsonb_build_object('note', nullif(v, ''));
  end if;
  return o;
end $$;
revoke all on function public.hiring_values(jsonb) from public, anon, authenticated;

create or replace function public.hiring_row(c public.hiring_candidates, p_role text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', c.id, 'name', c.name, 'position', c.position, 'source', c.source, 'stage', c.stage,
    'created_at', c.created_at, 'last_step_at', c.last_step_at, 'removed_at', c.removed_at, 'role', p_role,
    'owners', coalesce((select jsonb_agg(t.name order by t.name) from public.hiring_people p
                         join public.team_members t on t.id = p.team_member_id
                        where p.candidate_id = c.id and p.role = 'owner'), '[]'::jsonb));
$$;
revoke all on function public.hiring_row(public.hiring_candidates, text) from public, anon, authenticated;

create or replace function public.hiring_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_admin boolean := public.ops_granted('team.hiring', 'work');
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true, 'admin', v_admin, 'rows', coalesce((
    select jsonb_agg(public.hiring_row(c, case when v_admin then 'admin' else p.role end) order by c.created_at desc)
      from public.hiring_candidates c
      left join public.hiring_people p on p.candidate_id = c.id and p.team_member_id = me.id
     where (v_admin or (p.role is not null and c.removed_at is null))), '[]'::jsonb));
end $$;
grant execute on function public.hiring_list() to authenticated;

create or replace function public.hiring_get(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  v_role text := public.hiring_role(p_id);
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true, 'role', v_role,
    'candidate', public.hiring_row(c, v_role) || jsonb_strip_nulls(jsonb_build_object(
      'email', c.email, 'phone', c.phone, 'cv_url', c.cv_url, 'cv_path', c.cv_path, 'cv_name', c.cv_name,
      'note', c.note, 'updated_at', c.updated_at,
      'link_key', case when v_role in ('admin', 'owner') then c.link_key end,
      'link_ends', c.last_step_at + make_interval(days => v_days))),
    'people', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'role', p.role,
                          'designation', t.designation) order by (p.role <> 'owner'), t.name)
                          from public.hiring_people p join public.team_members t on t.id = p.team_member_id
                         where p.candidate_id = c.id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('actor', e.actor, 'action', e.action, 'detail', e.detail,
                          'created_at', e.created_at) order by e.created_at desc)
                          from (select * from public.hiring_events e where e.candidate_id = c.id
                                 order by e.created_at desc limit 100) e), '[]'::jsonb));
end $$;
grant execute on function public.hiring_get(uuid) to authenticated;

create or replace function public.hiring_add(p_values jsonb, p_idem text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v jsonb;
  c public.hiring_candidates;
  v_dup public.hiring_candidates;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_idem, '') !~ '^[A-Za-z0-9-]{8,64}$' then return jsonb_build_object('error', 'bad-request'); end if;
  perform pg_advisory_xact_lock(hashtext('hiring_add:' || p_idem));
  select * into c from public.hiring_candidates where idem = p_idem;
  if c.id is not null then return jsonb_build_object('ok', true, 'id', c.id, 'again', true); end if;
  v := public.hiring_values(p_values || jsonb_build_object(
    'name', coalesce(p_values->>'name', ''), 'email', coalesce(p_values->>'email', ''),
    'position', coalesce(p_values->>'position', ''), 'source', coalesce(p_values->>'source', '')));
  if v ? 'error' then return v; end if;
  select * into v_dup from public.hiring_candidates
   where lower(email) = v->>'email' and removed_at is null and stage not in ('hired', 'closed') limit 1;
  if v_dup.id is not null then
    return jsonb_build_object('error', 'taken', 'id', v_dup.id, 'name', v_dup.name);
  end if;
  insert into public.hiring_candidates (name, email, phone, position, source, cv_url, note, link_key, idem, created_by)
  values (v->>'name', v->>'email', v->>'phone', v->>'position', v->>'source', v->>'cv_url', v->>'note',
          public.new_link_key(), p_idem, me.id)
  returning * into c;
  insert into public.hiring_people (candidate_id, team_member_id, role, added_by) values (c.id, me.id, 'owner', me.id);
  perform public.hiring_log(c.id, 'candidate.added', c.position || ' · ' || initcap(replace(c.source, '_', '-')));
  return jsonb_build_object('ok', true, 'id', c.id);
end $$;
grant execute on function public.hiring_add(jsonb, text) to authenticated;

/* Details changed by an admin or the candidate's Owner, over the row as
   read; the CV file's path held to the candidate's own folder. */
create or replace function public.hiring_save(p_id uuid, p_values jsonb, p_expected timestamptz)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  v jsonb;
  v_path text;
  v_said text[] := '{}';
  k text;
  w text[] := array['name', 'Name', 'email', 'Email', 'phone', 'Phone', 'position', 'Position', 'source', 'Source',
                    'cv_url', 'CV link', 'note', 'Note'];
  i int;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if p_expected is not null and c.updated_at is distinct from p_expected then
    return jsonb_build_object('error', 'stale', 'updated_at', c.updated_at);
  end if;
  v := public.hiring_values(coalesce(p_values, '{}'::jsonb) - 'cv_path' - 'cv_name');
  if v ? 'error' then return v; end if;
  if p_values ? 'cv_path' then
    v_path := nullif(btrim(coalesce(p_values->>'cv_path', '')), '');
    if v_path is not null and (v_path not like c.id::text || '/%' or v_path ~ '\.\.' or char_length(v_path) > 300) then
      return jsonb_build_object('error', 'bad-cv');
    end if;
    if v_path is distinct from c.cv_path then v_said := v_said || case when v_path is null then 'CV file removed' else 'CV file added' end; end if;
  end if;
  if v ? 'email' and lower(v->>'email') is distinct from lower(c.email) and exists (
       select 1 from public.hiring_candidates x where lower(x.email) = v->>'email' and x.id <> c.id
          and x.removed_at is null and x.stage not in ('hired', 'closed')) then
    return jsonb_build_object('error', 'taken');
  end if;
  for i in 1 .. array_length(w, 1) by 2 loop
    k := w[i];
    if v ? k and (v->>k) is distinct from (to_jsonb(c)->>k) then
      v_said := v_said || (w[i + 1] || case when k in ('note', 'cv_url', 'email', 'phone') then ' changed'
                  else ': ' || coalesce(to_jsonb(c)->>k, 'not set') || ' → ' || coalesce(v->>k, 'not set') end);
    end if;
  end loop;
  if array_length(v_said, 1) is null then return jsonb_build_object('ok', true, 'same', true, 'updated_at', c.updated_at); end if;
  update public.hiring_candidates x set
    name = coalesce(v->>'name', x.name), email = coalesce(v->>'email', x.email),
    phone = case when v ? 'phone' then v->>'phone' else x.phone end,
    position = coalesce(v->>'position', x.position), source = coalesce(v->>'source', x.source),
    cv_url = case when v ? 'cv_url' then v->>'cv_url' else x.cv_url end,
    cv_path = case when p_values ? 'cv_path' then v_path else x.cv_path end,
    cv_name = case when p_values ? 'cv_path' then case when v_path is null then null
                else left(coalesce(nullif(btrim(p_values->>'cv_name'), ''), 'CV'), 200) end else x.cv_name end,
    note = case when v ? 'note' then v->>'note' else x.note end,
    updated_at = now()
   where x.id = p_id returning * into c;
  perform public.hiring_log(p_id, 'candidate.edited', array_to_string(v_said, ' · '));
  return jsonb_build_object('ok', true, 'updated_at', c.updated_at);
end $$;
grant execute on function public.hiring_save(uuid, jsonb, timestamptz) to authenticated;

/* A colleague on a candidate, by an admin alone; told in the bell, the
   notice opening the candidate. */
create or replace function public.hiring_person_set(p_id uuid, p_member uuid, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.hiring_candidates;
  t public.team_members;
  v_was text;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_role, '') not in ('owner', 'interviews') then return jsonb_build_object('error', 'bad-role'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.team_members where id = p_member and active and removed_at is null and not system;
  if t.id is null then return jsonb_build_object('error', 'bad-colleague'); end if;
  select role into v_was from public.hiring_people where candidate_id = p_id and team_member_id = p_member;
  if v_was = p_role then return jsonb_build_object('ok', true, 'same', true); end if;
  insert into public.hiring_people (candidate_id, team_member_id, role, added_by)
  values (p_id, p_member, p_role, me.id)
  on conflict (candidate_id, team_member_id) do update set role = excluded.role;
  perform public.hiring_log(p_id, 'candidate.people', t.name || case when v_was is null then ' added as ' else ': ' || initcap(v_was) || ' → ' end
    || case p_role when 'owner' then 'Owner' else 'Interviews' end);
  if v_was is null and t.id <> me.id then
    insert into public.ops_notifications (team_member_id, kind, title, body, link)
    values (t.id, 'hiring.added', 'You were added to a candidate',
            c.position || ' · ' || case p_role when 'owner' then 'Owner' else 'Interviews' end || ' · added by ' || me.name,
            'https://digital.adspace.me/admin/?s=hiring&candidate=' || c.id);
  end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_person_set(uuid, uuid, text) to authenticated;

create or replace function public.hiring_person_remove(p_id uuid, p_member uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text;
  v_name text;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select p.role, t.name into v_role, v_name from public.hiring_people p join public.team_members t on t.id = p.team_member_id
   where p.candidate_id = p_id and p.team_member_id = p_member;
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from public.hiring_people where candidate_id = p_id and team_member_id = p_member;
  perform public.hiring_log(p_id, 'candidate.people', v_name || ' removed (' || case v_role when 'owner' then 'Owner' else 'Interviews' end || ')');
  return jsonb_build_object('ok', true, 'role', v_role);
end $$;
grant execute on function public.hiring_person_remove(uuid, uuid) to authenticated;

/* Remove hides a candidate from everyone but the part; Restore brings it
   back; Delete takes it away for good once removed, the name typed back,
   and answers the CV file's path for the page to remove. */
create or replace function public.hiring_remove(p_id uuid, p_restore boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.hiring_candidates;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(p_restore, false) then
    if c.removed_at is null then return jsonb_build_object('ok', true, 'same', true); end if;
    update public.hiring_candidates set removed_at = null, removed_by = null, updated_at = now() where id = p_id;
    perform public.hiring_log(p_id, 'candidate.restored', null);
  else
    if c.removed_at is not null then return jsonb_build_object('ok', true, 'same', true); end if;
    update public.hiring_candidates set removed_at = now(), removed_by = me.id, updated_at = now() where id = p_id;
    perform public.hiring_log(p_id, 'candidate.removed', null);
  end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_remove(uuid, boolean) to authenticated;

create or replace function public.hiring_delete(p_id uuid, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.hiring_candidates;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.removed_at is null then return jsonb_build_object('error', 'not-removed'); end if;
  if lower(btrim(coalesce(p_name, ''))) <> lower(c.name) then return jsonb_build_object('error', 'bad-name'); end if;
  delete from public.hiring_candidates where id = p_id;
  return jsonb_build_object('ok', true, 'cv_path', c.cv_path);
end $$;
grant execute on function public.hiring_delete(uuid, text) to authenticated;

/* The candidate's page: its key, read by an admin or the Owner; Reset link
   retires the old one at once. */
create or replace function public.hiring_link(p_id uuid, p_reset boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(p_reset, false) or c.link_key is null then
    update public.hiring_candidates set link_key = public.new_link_key(), last_step_at = now(), updated_at = now()
     where id = p_id returning * into c;
    perform public.hiring_log(p_id, 'candidate.link', case when p_reset then 'Link reset' else 'Link made' end);
  end if;
  return jsonb_build_object('ok', true, 'key', c.link_key, 'updated_at', c.updated_at);
end $$;
grant execute on function public.hiring_link(uuid, boolean) to authenticated;

/* The candidate's own page (`/careers/?k=`): their name, the position and
   where it stands; never a colleague's name, a note or a score. The link
   ends `hiring_link_days` after the last step. */
create or replace function public.careers_read(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null;
  if c.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() then return jsonb_build_object('error', 'expired'); end if;
  return jsonb_build_object('ok', true, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage in ('new', 'pool') then 'received' else c.stage end, 'received_at', c.created_at);
end $$;
revoke all on function public.careers_read(text) from public;
grant execute on function public.careers_read(text) to anon, authenticated;

/* A CV file in the private bucket `hiring`, at `{candidate id}/{name}`: read
   by anyone on that candidate, added and removed by an admin or its Owner.
   Used by the bucket's policies, so it keeps `authenticated`. */
create or replace function public.hiring_file_ok(p_name text, p_write boolean)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid;
  v_role text;
begin
  begin
    v_id := split_part(coalesce(p_name, ''), '/', 1)::uuid;
  exception when others then return false;
  end;
  v_role := public.hiring_role(v_id);
  if v_role is null then return false; end if;
  return not coalesce(p_write, false) or v_role in ('admin', 'owner');
end $$;
revoke all on function public.hiring_file_ok(text, boolean) from public, anon;
grant execute on function public.hiring_file_ok(text, boolean) to authenticated;

/* STORAGE (the SQL Editor's, a run of its own: the connector holds a drop).
   The private bucket and who may touch it, where the project has storage. */
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'storage') then
    raise notice 'hiring: no storage schema here, so no bucket or policy was written.';
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('hiring', 'hiring', false, 20971520, array['application/pdf', 'application/msword',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
  on conflict (id) do update set public = false, file_size_limit = 20971520,
    allowed_mime_types = excluded.allowed_mime_types;
  execute 'drop policy if exists hiring_files_read on storage.objects';
  execute $p$create policy hiring_files_read on storage.objects for select to authenticated
    using (bucket_id = 'hiring' and public.hiring_file_ok(name, false))$p$;
  execute 'drop policy if exists hiring_files_add on storage.objects';
  execute $p$create policy hiring_files_add on storage.objects for insert to authenticated
    with check (bucket_id = 'hiring' and public.hiring_file_ok(name, true))$p$;
  execute 'drop policy if exists hiring_files_remove on storage.objects';
  execute $p$create policy hiring_files_remove on storage.objects for delete to authenticated
    using (bucket_id = 'hiring' and public.hiring_file_ok(name, true))$p$;
end $$;

/* `team.hiring` and `team.personnel` join the admin tools only an admin
   turns on (as SUPER ADMIN left the guard, with the two added). */
create or replace function public.team_roles_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_granted constant text[] := array['ops.all', 'ops.reports', 'ops.workflows', 'ops.time', 'ops.numbering',
    'ops.override', 'team.performance', 'team.perfadmin', 'team.settings', 'team.upgrade', 'team.invite',
    'team.handbook', 'team.announce', 'team.notice', 'reports.whitelabel', 'reports.transfer', 'reports.ai',
    'reports.meta', 'register.types', 'campaigns.files_delete', 'clients.vic', 'suppliers.pay',
    'team.analytics', 'campaigns.pay', 'team.hiring', 'team.personnel'];
  k text;
begin
  if who = '' or pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  /* A group made admin, an admin group made plain, made or deleted: the
     super admin's alone. */
  if not public.team_super_ok() and (
       (tg_op = 'INSERT' and (coalesce(new.is_admin, false) or new.slug = 'admin'))
    or (tg_op = 'DELETE' and (coalesce(old.is_admin, false) or old.slug = 'admin'))
    or (tg_op = 'UPDATE' and coalesce(new.is_admin, false) is distinct from coalesce(old.is_admin, false))) then
    raise exception 'super-only' using errcode = '42501', hint = 'Only the super admin makes or removes an admin group.';
  end if;
  if public.allowed('admin') then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if (tg_op <> 'INSERT' and (coalesce(old.is_admin, false) or old.slug = 'admin'))
     or (tg_op <> 'DELETE' and (coalesce(new.is_admin, false) or new.slug = 'admin')) then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes an admin group.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  foreach k in array v_granted loop
    if coalesce(new.access ->> k, '') is distinct from
       (case when tg_op = 'INSERT' then '' else coalesce(old.access ->> k, '') end) then
      raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes an admin tool.';
    end if;
  end loop;
  return new;
end $$;
revoke all on function public.team_roles_admin_guard() from public, anon, authenticated;

/* Hiring may be placed in a colleague's own order of the rail (as SUPPLIERS
   left it, with `hiring` added). */
create or replace function public.rail_order_set(p_sections text[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members;
  v_list text[] := coalesce(p_sections, '{}');
  v_known constant text[] := array['work', 'clients', 'review', 'scripts', 'campaigns', 'reports', 'whatsapp',
    'register', 'suppliers', 'links', 'services', 'hiring', 'team', 'handbook'];
begin
  me := public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if exists (select 1 from unnest(v_list) k where k is null or not (k = any(v_known)))
     or (select count(distinct k) from unnest(v_list) k) <> cardinality(v_list) then
    return jsonb_build_object('error', 'bad-order');
  end if;
  insert into public.rail_orders (member_id, sections, updated_at) values (me.id, v_list, now())
  on conflict (member_id) do update set sections = excluded.sections, updated_at = now();
  return jsonb_build_object('sections', to_jsonb(v_list));
end $$;
grant execute on function public.rail_order_set(text[]) to authenticated;

-- END OF HIRING --------------------------------------------------------------

select public.functions_tidy();
