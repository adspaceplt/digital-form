-- ===========================================================================
-- PERFORMANCE SELF-RATING — a colleague rates themselves on the scorecard
-- before the month is shared, a month whose query window has closed settles
-- by itself, and the first open of a shared review is recorded.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/perf.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-07: "we need them to rate themselves too
-- based on the same metrics"; "after dispute period, no disputes = auto
-- acknowledged same goes to previous months. So i would be able to confirm
-- and issue the quarter rewards"; answered: the scorecard only, before
-- management scores, Acknowledged and Final, record the first open)
--   1. `perf_self_ratings` (colleague, month, the six scorecard scores in
--      the scorecard's own maxima, when saved): RLS on, no policy, no
--      grant. A month opens to rate on the 1st after it (from June 2026)
--      for a colleague on the review list, or one whose review of it has
--      begun, from the month they joined, and stays open until its review
--      is shared (`perf_self_open`: `bad-month`, `shared`, `not-reviewed`).
--      `perf_self_mine()` answers the months open and what was given;
--      `perf_self_save(p_period, p_scores)` writes all six at once
--      (`incomplete`, `bad-score` with the item and its maximum); both
--      behind the fresh proof (`perf_mine_gate`). Each save is filed
--      `self.saved`, which the review's history reads.
--   2. `perf_json` sends the colleague's rating as `self` (scores, total,
--      when saved) beside management's scores; it never enters the grade.
--      It sends `opened_at` (the open of the version on show) and
--      `final_auto` (settled by itself).
--   3. `perf_reviews.opened_at`: `perf_seen(p_review)` stamps the first time
--      the colleague opens their shared review (again after a release
--      that followed it), filed `opened`. It moves nothing else.
--   4. `perf_close_windows()`: a shared month whose query window has closed
--      with no query waiting on an answer (shared, every query answered, or
--      acknowledged) becomes Final by itself: acknowledged as at the window's
--      close, or the last answer where that came after it, and finalised
--      now, each filed with `auto`, its result kept as Final keeps it.
--      Every hour (pg_cron `perf-close-windows`) and once at the foot of
--      this file, so earlier months settle at once. No browser calls it.
--   5. `perf_printed`'s trail adds Opened and marks the automatic steps;
--      `perf_activity` lists `opened` and `self.saved`, each with `auto`.
--
-- ROLLBACK (in the SQL Editor)
--   select cron.unschedule('perf-close-windows');
--   Run perf_json from DATE OF EVALUATION, perf_printed from PERFORMANCE
--   RECORDS, THEIR TRAIL AND THEIR CHECK and perf_activity from A
--   PERFORMANCE RECORD CAN BE DELETED again; then drop perf_close_windows,
--   perf_seen, perf_self_save, perf_self_mine, perf_self_open and the
--   table, and run
--   alter table public.perf_reviews drop column if exists opened_at;
-- ===========================================================================

alter table public.perf_reviews add column if not exists opened_at timestamptz;

create table if not exists public.perf_self_ratings (
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  period         date not null check (extract(day from period) = 1),
  s_output       numeric(4,1) not null check (s_output between 0 and 25),
  s_accuracy     numeric(4,1) not null check (s_accuracy between 0 and 15),
  s_delivery     numeric(4,1) not null check (s_delivery between 0 and 15),
  s_client       numeric(4,1) not null check (s_client between 0 and 20),
  s_comms        numeric(4,1) not null check (s_comms between 0 and 15),
  s_initiative   numeric(4,1) not null check (s_initiative between 0 and 10),
  saved_at       timestamptz not null default now(),
  primary key (team_member_id, period)
);
alter table public.perf_self_ratings enable row level security;
revoke all on public.perf_self_ratings from public, anon, authenticated;

/* One reading of a colleague's own rating, for them and for management. */
create or replace function public.perf_self_json(p_member uuid, p_period date)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'scores', jsonb_build_object('output', s.s_output, 'accuracy', s.s_accuracy,
      'delivery', s.s_delivery, 'client', s.s_client, 'comms', s.s_comms,
      'initiative', s.s_initiative),
    'total', s.s_output + s.s_accuracy + s.s_delivery + s.s_client + s.s_comms + s.s_initiative,
    'saved_at', s.saved_at)
    from public.perf_self_ratings s
   where s.team_member_id = p_member and s.period = p_period
$$;
revoke all on function public.perf_self_json(uuid, date) from public, anon, authenticated;

/* Null when the month is open to rate; else why not. */
create or replace function public.perf_self_open(p_member uuid, p_period date)
returns text
language sql stable security definer set search_path = public as $$
  select case
    when p_period is null or extract(day from p_period) <> 1 or p_period < date '2026-06-01'
      or p_period >= date_trunc('month', public.perf_today())::date
      then 'bad-month'
    when exists (select 1 from public.perf_reviews r
                  where r.team_member_id = p_member and r.period = p_period and r.status <> 'draft')
      then 'shared'
    when not exists (select 1 from public.perf_reviews r
                      where r.team_member_id = p_member and r.period = p_period)
     and (not coalesce(public.perf_reviewed(p_member), false)
          or p_period < (select date_trunc('month', t.created_at)::date
                           from public.team_members t where t.id = p_member))
      then 'not-reviewed'
  end
$$;
revoke all on function public.perf_self_open(uuid, date) from public, anon, authenticated;

create or replace function public.perf_self_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  return jsonb_build_object('months', coalesce((
    select jsonb_agg(jsonb_build_object('period', p.period, 'month', public.perf_month_word(p.period),
                                        'rating', public.perf_self_json(m.id, p.period))
                     order by p.period desc)
      from (select generate_series(date '2026-06-01',
                                   (date_trunc('month', public.perf_today()) - interval '1 month')::date,
                                   interval '1 month')::date as period) p
     where public.perf_self_open(m.id, p.period) is null), '[]'::jsonb));
end $$;

create or replace function public.perf_self_save(p_period date, p_scores jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members; g jsonb; err text; p date := date_trunc('month', p_period)::date;
  k text; mx numeric; v numeric; was boolean; rid uuid;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  err := public.perf_self_open(m.id, p);
  if err is not null then return jsonb_build_object('error', err); end if;
  if jsonb_typeof(p_scores) is distinct from 'object' then return jsonb_build_object('error', 'incomplete'); end if;
  foreach k in array array['output', 'accuracy', 'delivery', 'client', 'comms', 'initiative'] loop
    if jsonb_typeof(p_scores -> k) is distinct from 'number' then
      return jsonb_build_object('error', 'incomplete', 'item', k);
    end if;
    mx := case k when 'output' then 25 when 'accuracy' then 15 when 'delivery' then 15
                 when 'client' then 20 when 'comms' then 15 when 'initiative' then 10 end;
    v := (p_scores ->> k)::numeric;
    if v < 0 or v > mx or round(v, 1) <> v then
      return jsonb_build_object('error', 'bad-score', 'item', k, 'max', mx);
    end if;
  end loop;
  was := exists (select 1 from public.perf_self_ratings s where s.team_member_id = m.id and s.period = p);
  insert into public.perf_self_ratings (team_member_id, period, s_output, s_accuracy, s_delivery,
                                        s_client, s_comms, s_initiative, saved_at)
  values (m.id, p, (p_scores ->> 'output')::numeric, (p_scores ->> 'accuracy')::numeric,
          (p_scores ->> 'delivery')::numeric, (p_scores ->> 'client')::numeric,
          (p_scores ->> 'comms')::numeric, (p_scores ->> 'initiative')::numeric, now())
  on conflict (team_member_id, period) do update
     set s_output = excluded.s_output, s_accuracy = excluded.s_accuracy, s_delivery = excluded.s_delivery,
         s_client = excluded.s_client, s_comms = excluded.s_comms, s_initiative = excluded.s_initiative,
         saved_at = now();
  select r.id into rid from public.perf_reviews r where r.team_member_id = m.id and r.period = p;
  perform public.perf_log(rid, m.id, 'self.saved', jsonb_build_object('period', p, 'again', was));
  return public.perf_self_mine();
end $$;

/* The first open of what was shared, by the colleague it is about. */
create or replace function public.perf_seen(p_review uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; r public.perf_reviews;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  update public.perf_reviews set opened_at = now()
   where id = p_review and team_member_id = m.id and status <> 'draft'
     and (opened_at is null or opened_at < released_at)
  returning * into r;
  if r.id is not null then
    perform public.perf_log(r.id, r.team_member_id, 'opened', jsonb_build_object('version', r.version));
  else
    select * into r from public.perf_reviews
     where id = p_review and team_member_id = m.id and status <> 'draft';
    if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  return public.perf_json(r, false);
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
      'designation', m.designation, 'department', m.department,
      'role_family', m.role_family, 'runs_ads', coalesce(pp.runs_ads, false)),
    'scores', jsonb_build_object('output', r.s_output, 'accuracy', r.s_accuracy,
      'delivery', r.s_delivery, 'client', r.s_client, 'comms', r.s_comms,
      'initiative', r.s_initiative),
    'self', public.perf_self_json(r.team_member_id, r.period),
    'rates', jsonb_build_object('posting', r.r_posting, 'timeline', r.r_timeline,
      'satisfaction', r.r_satisfaction, 'pacing', r.r_pacing, 'sla', r.r_sla),
    'notes', r.notes, 'improvement', r.improvement, 'review_by', r.review_by,
    'evaluated_on', r.evaluated_on,
    'reward_step', r.reward_step, 'serial', r.serial,
    'reviewer', (select name from public.team_members where id = r.reviewer_id),
    'released_at', r.released_at, 'dispute_until', r.dispute_until,
    'dispute_open', r.status = 'released' and r.dispute_until > now()
                    and not exists (select 1 from public.perf_disputes d
                                     where d.review_id = r.id and d.version = r.version),
    'opened_at', case when r.opened_at >= r.released_at then r.opened_at end,
    'acknowledged_at', r.acknowledged_at, 'finalised_at', r.finalised_at,
    'finalised_by', (select name from public.team_members where id = r.finalised_by),
    'final_auto', r.status = 'final' and r.finalised_by is null,
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
          from public.perf_events e
         where e.review_id = r.id
            or (e.review_id is null and e.kind = 'self.saved' and e.team_member_id = r.team_member_id
                and e.detail ->> 'period' = r.period::text)), '[]'::jsonb));
  end if;
  return out;
end $$;

/* A month whose window has closed with nothing waiting on an answer is
   settled: acknowledged as at the close (or the last answer, where that
   came after it) and finalised now, each filed as automatic. */
create or replace function public.perf_close_windows()
returns integer
language plpgsql security definer set search_path = public as $$
declare r public.perf_reviews; res jsonb; n integer := 0; v_ack timestamptz;
begin
  for r in
    select x.* from public.perf_reviews x
     where x.status in ('released', 'resolved', 'acknowledged')
       and x.dispute_until is not null and x.dispute_until <= now()
       and not exists (select 1 from public.perf_disputes d
                        where d.review_id = x.id and d.version = x.version and d.decision is null)
     order by x.period, x.id
     for update skip locked
  loop
    v_ack := coalesce(r.acknowledged_at, greatest(r.dispute_until,
               coalesce((select max(d.decided_at) from public.perf_disputes d
                          where d.review_id = r.id and d.version = r.version), r.dispute_until)));
    res := public.perf_calc(r);
    update public.perf_reviews
       set status = 'final', result = res, acknowledged_at = v_ack,
           finalised_at = now(), finalised_by = null, rev = rev + 1, updated_at = now()
     where id = r.id;
    if r.acknowledged_at is null then
      insert into public.perf_events (review_id, team_member_id, actor_id, actor_email, kind, detail, created_at)
      values (r.id, r.team_member_id, null, null, 'acknowledged', jsonb_build_object('auto', true), v_ack);
    end if;
    insert into public.perf_events (review_id, team_member_id, actor_id, actor_email, kind, detail)
    values (r.id, r.team_member_id, null, null, 'finalised',
            jsonb_build_object('auto', true, 'grade', res ->> 'grade', 'final', res -> 'final'));
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.perf_printed(p_review uuid, p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews; ev_id uuid; ev_at timestamptz;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.perf_reviews where id = p_review;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id <> m.id and public.perf_check(p_token, 'view') is not null then
    return jsonb_build_object('error', 'denied');
  end if;
  if r.team_member_id = m.id and r.status = 'draft' then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.perf_events (review_id, team_member_id, actor_id, actor_email, kind, detail)
  values (r.id, r.team_member_id, m.id, m.email, 'printed', jsonb_build_object('version', r.version))
  returning id, created_at into ev_id, ev_at;
  return jsonb_build_object('ok', true, 'id', ev_id, 'at', ev_at, 'by', m.name, 'email', m.email,
    'trail', coalesce((
      select jsonb_agg(jsonb_build_object('kind', t.kind, 'at', t.created_at, 'by', t.who,
                                          'email', t.actor_email, 'auto', t.auto)
                       order by t.created_at)
        from (select distinct on (pe.kind) pe.kind, pe.created_at, pe.actor_email,
                     coalesce(tm.name, pe.actor_email) as who,
                     coalesce((pe.detail ->> 'auto')::boolean, false) as auto
                from public.perf_events pe
                left join public.team_members tm on tm.id = pe.actor_id
               where pe.review_id = r.id
                 and ((pe.kind = 'released' and r.released_at is not null)
                   or (pe.kind = 'opened' and r.opened_at >= r.released_at)
                   or (pe.kind = 'acknowledged' and r.acknowledged_at is not null)
                   or (pe.kind = 'finalised' and r.finalised_at is not null))
               order by pe.kind, pe.created_at desc) t), '[]'::jsonb));
end $$;

/* The Activity record's Performance tab, now with the first open and a
   colleague's own rating, and whether a step settled by itself. */
create or replace function public.perf_activity(p_limit integer default 200)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me_row public.team_members;
begin
  me_row := public.ops_me();
  if me_row.id is null or not public.ops_granted('team.performance', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object(
             'at', e.created_at, 'kind', e.kind, 'member', tm.name,
             'period', coalesce(rv.period, case when e.kind in ('deleted', 'self.saved')
                                                then (e.detail ->> 'period')::date end),
             'actor', e.actor_email, 'actor_name', ac.name,
             'auto', coalesce((e.detail ->> 'auto')::boolean, false)) order by e.created_at desc)
      from (select pe.* from public.perf_events pe
             where pe.kind in ('released', 'opened', 'self.saved', 'disputed', 'decided', 'acknowledged',
                               'finalised', 'reopened', 'returned', 'printed', 'deleted')
               and pe.team_member_id is distinct from me_row.id
             order by pe.created_at desc
             limit greatest(1, least(coalesce(p_limit, 200), 500))) e
      left join public.team_members tm on tm.id = e.team_member_id
      left join public.perf_reviews rv on rv.id = e.review_id
      left join public.team_members ac on ac.id = e.actor_id), '[]'::jsonb));
end $$;

revoke all on function public.perf_self_mine() from public, anon, authenticated;
revoke all on function public.perf_self_save(date, jsonb) from public, anon, authenticated;
revoke all on function public.perf_seen(uuid) from public, anon, authenticated;
revoke all on function public.perf_json(public.perf_reviews, boolean) from public, anon, authenticated;
revoke all on function public.perf_close_windows() from public, anon, authenticated;
revoke all on function public.perf_printed(uuid, text) from public, anon, authenticated;
revoke all on function public.perf_activity(integer) from public, anon, authenticated;
grant execute on function public.perf_self_mine() to authenticated;
grant execute on function public.perf_self_save(date, jsonb) to authenticated;
grant execute on function public.perf_seen(uuid) to authenticated;
grant execute on function public.perf_printed(uuid, text) to authenticated;
grant execute on function public.perf_activity(integer) to authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: a closed window settles on the next run of this file.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'perf-close-windows';
  perform cron.schedule('perf-close-windows', '7 * * * *', 'select public.perf_close_windows()');
end $$;

-- Earlier months past their window settle now.
select public.perf_close_windows();

-- END OF PERFORMANCE SELF-RATING ----------------------------------------------
