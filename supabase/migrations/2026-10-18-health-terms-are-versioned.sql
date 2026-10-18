-- ===========================================================================
-- HEALTH TERMS ARE VERSIONED — the words a colleague agrees to are kept in
-- one place, each version whole, and a new version asks everyone again
-- (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 17): the agreement card's words lived in
-- js/health.js and every agreement was stored as wording 1, so a change to
-- the words would have stood on agreements given to other words (PDPA 2010:
-- consent is to what was shown).
--
-- WHAT IT CHANGES
--   * `health_wordings` (version, care, terms, made_at; RLS on, no policy, no
--     grant): every version of the card's words, the company's lines
--     (`care`) and What you agree to (`terms`). Version 1, the words the
--     page has shown since 2026-10-07, is seeded once into an empty table.
--     A change of words is a migration adding the next version, never an
--     edit of one given.
--   * `health_wording_now()`: the latest version (an internal helper).
--   * `health_agreed(p_member)` stands only on an agreement to the latest
--     version: a new version pauses the check-ins, the talks and the
--     reminders, and takes the answers out of Team: Health, until the
--     colleague agrees to it.
--   * `health_mine()` also sends the latest version's words (`wording`), so
--     the page draws the card from the database alone.
--   * `health_consent(p_on, p_wording)`: agreeing names the version the page
--     showed, refused `stale-wording` where it is no longer the latest; the
--     version is kept on the agreement and its log line. The old
--     `health_consent(p_on)` stays for a page loaded before this one and
--     agrees to version 1 alone (no drop: the connector holds a drop).
--   * `health_team(p_token)` marks each agreement `current` and sends answers
--     only while `health_agreed()` stands.
--
-- ORDER: this file, then the pages (the page draws the words from
-- `health_mine()`). Safe to run twice.
-- Rollback: run HEALTH CHECK-INS' `health_agreed`, `health_mine` and
-- `health_consent`, and TEAM HEALTH IS AN ADMIN'S `health_team(p_token)`,
-- again; the table and `health_consent(boolean, integer)` may then be
-- dropped in the SQL Editor.
-- ===========================================================================

create table if not exists public.health_wordings (
  version   integer primary key check (version > 0),
  care      jsonb not null check (jsonb_typeof(care) = 'array'),
  terms     jsonb not null check (jsonb_typeof(terms) = 'array'),
  made_at   timestamptz not null default now()
);
alter table public.health_wordings enable row level security;
revoke all on table public.health_wordings from public, anon, authenticated;

insert into public.health_wordings (version, care, terms, made_at)
select 1, jsonb_build_array(
    'Life at work and life at home both shape how you feel, in body and in mind, and we care about all of it. Every two weeks, take a quiet moment to tell us how you really are.',
    'Please answer honestly. There are no right or wrong answers, only a true picture that helps us look after you. If something feels heavy, ask for a talk: reaching out early is a strength, and we would always rather hear from you and help.'),
  jsonb_build_array(
    'Every two weeks: five questions on your body, mind, sleep, energy and workload, each from 1 to 5, with a note if you wish.',
    'ADspace management reads your answers with your name, only to understand how you are and to support you.',
    'Your answers are never part of your performance review.',
    'You can withdraw at any time here, and your answers leave management''s view.'),
  timestamptz '2026-10-07 00:00:00+08'
 where not exists (select 1 from public.health_wordings);

create or replace function public.health_wording_now()
returns integer language sql stable security definer set search_path = public as $$
  select coalesce(max(w.version), 1) from public.health_wordings w
$$;
revoke all on function public.health_wording_now() from public, anon, authenticated;

create or replace function public.health_agreed(p_member uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.health_consents c
                  where c.team_member_id = p_member and c.withdrawn_at is null
                    and c.wording >= public.health_wording_now())
$$;
revoke all on function public.health_agreed(uuid) from public, anon, authenticated;

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
    'wording', (select jsonb_build_object('version', w.version, 'care', w.care, 'terms', w.terms, 'made_at', w.made_at)
                  from public.health_wordings w where w.version = public.health_wording_now()),
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
revoke all on function public.health_mine() from public, anon, authenticated;
grant execute on function public.health_mine() to authenticated;

create or replace function public.health_consent(p_on boolean, p_wording integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; n integer; v integer;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  if coalesce(p_on, false) then
    v := public.health_wording_now();
    if p_wording is distinct from v then return jsonb_build_object('error', 'stale-wording', 'version', v); end if;
    insert into public.health_consents (team_member_id, agreed_at, wording, withdrawn_at, updated_at)
    values (m.id, now(), v, null, now())
    on conflict (team_member_id) do update
       set agreed_at = now(), wording = v, withdrawn_at = null, updated_at = now();
    insert into public.health_log (team_member_id, kind, wording) values (m.id, 'agreed', v);
  else
    update public.health_consents set withdrawn_at = now(), updated_at = now()
     where team_member_id = m.id and withdrawn_at is null;
    get diagnostics n = row_count;
    if n = 0 then return jsonb_build_object('error', 'not-agreed'); end if;
    insert into public.health_log (team_member_id, kind) values (m.id, 'withdrawn');
  end if;
  return public.health_mine();
end $$;
revoke all on function public.health_consent(boolean, integer) from public, anon, authenticated;
grant execute on function public.health_consent(boolean, integer) to authenticated;

create or replace function public.health_consent(p_on boolean)
returns jsonb
language sql security definer set search_path = public as $$
  select public.health_consent(p_on, 1)
$$;
revoke all on function public.health_consent(boolean) from public, anon, authenticated;
grant execute on function public.health_consent(boolean) to authenticated;

create or replace function public.health_team(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; h date; e text;
begin
  m := public.ops_me();
  e := public.health_check(p_token);
  if e is not null then return jsonb_build_object('error', e); end if;
  h := public.health_half(public.health_today());
  return jsonb_build_object('half', h, 'half_end', public.health_half_end(h),
    'people', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'staff_code', t.staff_code, 'designation', t.designation,
        'department', t.department, 'role', t.role,
        'consent', case when c.team_member_id is null then null else jsonb_build_object(
          'agreed_at', c.agreed_at, 'withdrawn_at', c.withdrawn_at,
          'current', c.wording >= public.health_wording_now()) end,
        'checkins', case when public.health_agreed(t.id) then coalesce((
            select jsonb_agg(public.health_checkin_json(x) order by x.half desc)
              from (select * from public.health_checkins k
                     where k.team_member_id = t.id and k.updated_at >= c.agreed_at
                     order by k.half desc limit 12) x), '[]'::jsonb) else '[]'::jsonb end)
        order by t.staff_code nulls last, t.name)
        from public.team_members t
        left join public.health_consents c on c.team_member_id = t.id
       where t.active), '[]'::jsonb),
    'talks', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'from', f.name, 'from_id', k.team_member_id, 'with', w.name, 'with_id', k.with_id,
        'status', k.status, 'at', k.created_at, 'closed_at', k.closed_at)
        order by (k.status = 'open') desc, k.created_at desc)
        from public.health_talks k
        join public.team_members f on f.id = k.team_member_id
        join public.team_members w on w.id = k.with_id
       where k.status <> 'withdrawn' and k.created_at > now() - interval '90 days'), '[]'::jsonb));
end $$;
revoke all on function public.health_team(text) from public, anon, authenticated;
grant execute on function public.health_team(text) to authenticated;

-- END OF HEALTH TERMS ARE VERSIONED -----------------------------------------

select public.functions_tidy();
