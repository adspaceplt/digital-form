-- ===========================================================================
-- INITIATIVES AND THE MONTHLY REFLECTION — a colleague logs what they started
-- (an idea for a client, a better way of working, a tool, an SOP) and writes
-- three lines on their month; management reads both beside the review.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/perf.js compares the
-- two. Runs after the PERFORMANCE sections.
--
-- WHAT CHANGED (the user, 2026-10-04: initiative is already scored, Initiative
-- and improvement, 10 points; growth data is shared only by the member)
--   1. `perf_initiatives`: one row an initiative, the colleague's own. Proposed
--      → Adopted / Not now → Done; Withdrawn by its author (Restore brings it
--      back). Credited in the month it was logged and the month it was done.
--   2. `perf_reflections`: Proud of, Found hard, Want to learn, one row a
--      colleague a month; management reads it only once the colleague shares
--      it, and never scores it.
--   3. The colleague's functions ask the fresh proof My performance asks
--      (`perf_guarded`, `perf_code_fresh`); management's ask the granted part
--      and a live unlock (`perf_check`). Nobody decides on their own.
--   4. `perf_review_context(p_token, p_member, p_period)`: what the review
--      sheet shows beside Initiative and improvement.
--
-- ROLLBACK
--   In the SQL Editor, drop the twelve functions below, then the two tables.
--   No other table or function reads them.
-- ===========================================================================

create table if not exists public.perf_initiatives (
  id             uuid primary key default gen_random_uuid(),
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  title          text not null check (char_length(btrim(title)) between 3 and 140),
  improves       text not null check (improves in ('client', 'process', 'tool', 'sop', 'other')),
  detail         text check (detail is null or char_length(detail) <= 2000),
  link           text check (link is null or link ~ '^https://[^[:space:]]+$'),
  status         text not null default 'proposed'
                 check (status in ('proposed', 'adopted', 'not_now', 'done', 'withdrawn')),
  period         date not null check (extract(day from period) = 1),
  done_period    date check (done_period is null or extract(day from done_period) = 1),
  decided_by     uuid references public.team_members(id) on delete set null,
  decided_at     timestamptz,
  note           text check (note is null or char_length(note) <= 1000),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists perf_initiatives_member_idx on public.perf_initiatives (team_member_id, period);

create table if not exists public.perf_reflections (
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  period         date not null check (extract(day from period) = 1),
  proud          text check (proud is null or char_length(proud) <= 1000),
  hard           text check (hard is null or char_length(hard) <= 1000),
  learn          text check (learn is null or char_length(learn) <= 1000),
  shared_at      timestamptz,
  updated_at     timestamptz not null default now(),
  primary key (team_member_id, period)
);

alter table public.perf_initiatives enable row level security;
alter table public.perf_reflections enable row level security;
revoke all on public.perf_initiatives, public.perf_reflections from anon, authenticated;

/* One reading of an initiative, for its author and for management alike. */
create or replace function public.perf_initiative_json(i public.perf_initiatives)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', i.id, 'team_member_id', i.team_member_id,
    'name', (select t.name from public.team_members t where t.id = i.team_member_id),
    'title', i.title, 'improves', i.improves, 'detail', i.detail, 'link', i.link,
    'status', i.status, 'period', i.period, 'month', public.perf_month_word(i.period),
    'done_period', i.done_period,
    'done_month', case when i.done_period is null then null else public.perf_month_word(i.done_period) end,
    'decided_by', (select t.name from public.team_members t where t.id = i.decided_by),
    'decided_at', i.decided_at, 'note', i.note, 'created_at', i.created_at)
$$;
revoke all on function public.perf_initiative_json(public.perf_initiatives) from public, anon, authenticated;

/* The colleague's own: the fresh proof My performance asks, every time. */
create or replace function public.perf_mine_gate()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  return null;
end $$;
revoke all on function public.perf_mine_gate() from public, anon, authenticated;

create or replace function public.perf_initiatives_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  return jsonb_build_object('initiatives', coalesce((
    select jsonb_agg(public.perf_initiative_json(i) order by i.created_at desc)
      from public.perf_initiatives i where i.team_member_id = m.id), '[]'::jsonb));
end $$;

create or replace function public.perf_initiative_save(p_id uuid, p_title text, p_improves text, p_detail text, p_link text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; i public.perf_initiatives;
        t text := btrim(coalesce(p_title, '')); d text := nullif(btrim(coalesce(p_detail, '')), '');
        l text := nullif(btrim(coalesce(p_link, '')), '');
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  if char_length(t) < 3 then return jsonb_build_object('error', 'title'); end if;
  if char_length(t) > 140 then return jsonb_build_object('error', 'title-long'); end if;
  if p_improves is null or p_improves not in ('client', 'process', 'tool', 'sop', 'other') then
    return jsonb_build_object('error', 'improves');
  end if;
  if l is not null and l !~ '^https://[^[:space:]]+$' then return jsonb_build_object('error', 'link'); end if;
  if p_id is null then
    insert into public.perf_initiatives (team_member_id, title, improves, detail, link, period)
    values (m.id, t, p_improves, d, l, date_trunc('month', public.perf_today())::date)
    returning * into i;
    perform public.perf_log(null, m.id, 'initiative.logged', jsonb_build_object('title', t));
  else
    select * into i from public.perf_initiatives where id = p_id for update;
    if i.id is null or i.team_member_id <> m.id then return jsonb_build_object('error', 'not-found'); end if;
    if i.status <> 'proposed' then return jsonb_build_object('error', 'decided'); end if;
    update public.perf_initiatives
       set title = t, improves = p_improves, detail = d, link = l, updated_at = now()
     where id = i.id returning * into i;
    perform public.perf_log(null, m.id, 'initiative.edited', jsonb_build_object('title', t));
  end if;
  return jsonb_build_object('initiative', public.perf_initiative_json(i));
end $$;

/* Withdraw is the author's way out of a proposal; Restore its way back. */
create or replace function public.perf_initiative_withdraw(p_id uuid, p_back boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; i public.perf_initiatives;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  select * into i from public.perf_initiatives where id = p_id for update;
  if i.id is null or i.team_member_id <> m.id then return jsonb_build_object('error', 'not-found'); end if;
  if i.status <> (case when p_back then 'withdrawn' else 'proposed' end) then
    return jsonb_build_object('error', 'decided');
  end if;
  update public.perf_initiatives
     set status = case when p_back then 'proposed' else 'withdrawn' end, updated_at = now()
   where id = i.id returning * into i;
  perform public.perf_log(null, m.id, case when p_back then 'initiative.restored' else 'initiative.withdrawn' end,
                          jsonb_build_object('title', i.title));
  return jsonb_build_object('initiative', public.perf_initiative_json(i));
end $$;

/* A reflection is written for this month or the last, until that month's
   review is final. */
create or replace function public.perf_reflection_open(p_member uuid, p_period date)
returns text
language sql stable security definer set search_path = public as $$
  select case
    when p_period is null or p_period not in (date_trunc('month', public.perf_today())::date,
                                              (date_trunc('month', public.perf_today()) - interval '1 month')::date)
      then 'bad-month'
    when exists (select 1 from public.perf_reviews r
                  where r.team_member_id = p_member and r.period = p_period and r.status = 'final')
      then 'final'
  end
$$;
revoke all on function public.perf_reflection_open(uuid, date) from public, anon, authenticated;

create or replace function public.perf_reflection_mine(p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; f public.perf_reflections; p date := date_trunc('month', p_period)::date;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  select * into f from public.perf_reflections where team_member_id = m.id and period = p;
  return jsonb_build_object('period', p, 'month', public.perf_month_word(p),
    'proud', f.proud, 'hard', f.hard, 'learn', f.learn, 'shared_at', f.shared_at,
    'open', public.perf_reflection_open(m.id, p) is null);
end $$;

create or replace function public.perf_reflection_save(p_period date, p_proud text, p_hard text, p_learn text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; err text; p date := date_trunc('month', p_period)::date;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  err := public.perf_reflection_open(m.id, p);
  if err is not null then return jsonb_build_object('error', err); end if;
  if char_length(coalesce(p_proud, '')) > 1000 or char_length(coalesce(p_hard, '')) > 1000
     or char_length(coalesce(p_learn, '')) > 1000 then
    return jsonb_build_object('error', 'too-long');
  end if;
  insert into public.perf_reflections (team_member_id, period, proud, hard, learn)
  values (m.id, p, nullif(btrim(coalesce(p_proud, '')), ''), nullif(btrim(coalesce(p_hard, '')), ''),
          nullif(btrim(coalesce(p_learn, '')), ''))
  on conflict (team_member_id, period) do update
     set proud = excluded.proud, hard = excluded.hard, learn = excluded.learn, updated_at = now();
  return public.perf_reflection_mine(p);
end $$;

/* Shared only by the colleague, and taken back by them until the month is
   final. */
create or replace function public.perf_reflection_share(p_period date, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; err text; n integer; p date := date_trunc('month', p_period)::date;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  err := public.perf_reflection_open(m.id, p);
  if err is not null then return jsonb_build_object('error', err); end if;
  update public.perf_reflections
     set shared_at = case when p_on then now() end, updated_at = now()
   where team_member_id = m.id and period = p
     and (not p_on or coalesce(proud, hard, learn) is not null);
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error', 'empty'); end if;
  perform public.perf_log(null, m.id, case when p_on then 'reflection.shared' else 'reflection.unshared' end,
                          jsonb_build_object('period', p));
  return public.perf_reflection_mine(p);
end $$;

/* Management: every colleague's initiatives but the caller's own. */
create or replace function public.perf_initiatives(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  return jsonb_build_object('initiatives', coalesce((
    select jsonb_agg(public.perf_initiative_json(i) order by i.created_at desc)
      from public.perf_initiatives i
     where i.team_member_id <> m.id and i.status <> 'withdrawn'), '[]'::jsonb));
end $$;

/* Adopted or Not now from a proposal, Done from adopted; Proposed is the way
   back from any of them and asks nothing. */
create or replace function public.perf_initiative_decide(p_token text, p_id uuid, p_status text, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; i public.perf_initiatives; was text;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  select * into i from public.perf_initiatives where id = p_id for update;
  if i.id is null or i.status = 'withdrawn' then return jsonb_build_object('error', 'not-found'); end if;
  if i.team_member_id = m.id then return jsonb_build_object('error', 'own'); end if;
  if p_status is null or p_status not in ('adopted', 'not_now', 'done', 'proposed') then
    return jsonb_build_object('error', 'bad-status');
  end if;
  if not ((i.status = 'proposed' and p_status in ('adopted', 'not_now'))
       or (i.status = 'adopted' and p_status = 'done')
       or (i.status <> 'proposed' and p_status = 'proposed')) then
    return jsonb_build_object('error', 'bad-move');
  end if;
  was := i.status;
  update public.perf_initiatives
     set status = p_status,
         done_period = case when p_status = 'done' then date_trunc('month', public.perf_today())::date
                            when p_status = 'proposed' then null else done_period end,
         decided_by = case when p_status = 'proposed' then null else m.id end,
         decided_at = case when p_status = 'proposed' then null else now() end,
         note = case when p_status = 'proposed' then null
                     else coalesce(nullif(btrim(coalesce(p_note, '')), ''), note) end,
         updated_at = now()
   where id = i.id returning * into i;
  perform public.perf_log(null, i.team_member_id, 'initiative.' || p_status,
                          jsonb_build_object('title', i.title, 'from', was));
  if p_status in ('adopted', 'done', 'not_now') then
    perform public.perf_notify(i.team_member_id, 'perf.initiative',
      case p_status when 'adopted' then 'Your initiative was adopted: '
                    when 'done' then 'Your initiative is done: '
                    else 'Your initiative is on hold for now: ' end || i.title,
      'initiative:' || i.id || ':' || p_status || ':' || extract(epoch from now())::bigint);
  end if;
  return jsonb_build_object('initiative', public.perf_initiative_json(i));
end $$;

/* Beside Initiative and improvement in the review sheet: the colleague's
   initiatives logged or done in the month, and their reflection once shared. */
create or replace function public.perf_review_context(p_token text, p_member uuid, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; f public.perf_reflections; p date := date_trunc('month', p_period)::date;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member is null or p_member = m.id then return jsonb_build_object('error', 'own'); end if;
  select * into f from public.perf_reflections
   where team_member_id = p_member and period = p and shared_at is not null;
  return jsonb_build_object(
    'initiatives', coalesce((
      select jsonb_agg(public.perf_initiative_json(i) order by i.created_at)
        from public.perf_initiatives i
       where i.team_member_id = p_member and i.status <> 'withdrawn'
         and (i.period = p or i.done_period = p)), '[]'::jsonb),
    'reflection', case when f.team_member_id is null then null else jsonb_build_object(
      'proud', f.proud, 'hard', f.hard, 'learn', f.learn, 'shared_at', f.shared_at) end);
end $$;

revoke all on function public.perf_initiatives_mine() from public, anon, authenticated;
revoke all on function public.perf_initiative_save(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.perf_initiative_withdraw(uuid, boolean) from public, anon, authenticated;
revoke all on function public.perf_reflection_mine(date) from public, anon, authenticated;
revoke all on function public.perf_reflection_save(date, text, text, text) from public, anon, authenticated;
revoke all on function public.perf_reflection_share(date, boolean) from public, anon, authenticated;
revoke all on function public.perf_initiatives(text) from public, anon, authenticated;
revoke all on function public.perf_initiative_decide(text, uuid, text, text) from public, anon, authenticated;
revoke all on function public.perf_review_context(text, uuid, date) from public, anon, authenticated;
grant execute on function public.perf_initiatives_mine() to authenticated;
grant execute on function public.perf_initiative_save(uuid, text, text, text, text) to authenticated;
grant execute on function public.perf_initiative_withdraw(uuid, boolean) to authenticated;
grant execute on function public.perf_reflection_mine(date) to authenticated;
grant execute on function public.perf_reflection_save(date, text, text, text) to authenticated;
grant execute on function public.perf_reflection_share(date, boolean) to authenticated;
grant execute on function public.perf_initiatives(text) to authenticated;
grant execute on function public.perf_initiative_decide(text, uuid, text, text) to authenticated;
grant execute on function public.perf_review_context(text, uuid, date) to authenticated;

-- END OF INITIATIVES AND THE MONTHLY REFLECTION -----------------------------
