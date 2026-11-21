-- ===========================================================================
-- RECOGNITION (2026-11-22)
-- ===========================================================================
-- WHY: the user, 2026-11-22, approving the Recognition mockup: colleagues
-- recognise one another, and a recognition management confirms adds marks
-- to that month's performance review, as a logged issue takes them away.
-- Initiatives and Reflection leave the pages; their tables and rows stay.
--
-- WHAT IT CHANGES
--   * `perf_recognitions` (RLS on, no policy, no grant): who gave it, to
--     whom, its category (helped: Helped a colleague, effort: Extra effort,
--     praise: Client praise), its note (3 to 500), the Malaysian day given,
--     its status (waiting, confirmed, declined, withdrawn) and, once
--     confirmed, the month it counts in (`period`).
--   * The month it counts in (`perf_recognition_month`, a helper): the month
--     given, unless that month's review is already shared or its quarter or
--     half confirmed; then the month confirmed, or the next month neither
--     holds. A shared or finalised month never changes.
--   * `perf_recognition_give(p_to, p_category, p_note)`: any colleague, to
--     any other active colleague, never themselves (`own`), never the system
--     account (`bad-colleague`), behind the fresh proof as My records is;
--     ten a day at most (`too-many`); the same press again answers the first
--     (`again`). With Management confirms each recognition off it is
--     confirmed as it is given. The receiver is told, never the points
--     (`perf.recognition`).
--   * `perf_recognition_withdraw(p_id, p_back)`: the giver's, while it waits;
--     `p_back` puts a withdrawn one back to waiting (Undo).
--   * `perf_recognitions_mine()`: the colleague's received (withdrawn left
--     out) and given (withdrawn left out), newest first, no points.
--   * `perf_review_recognitions(p_token, p_member, p_period)`: management's
--     read beside a month's review (View, a live unlock, never one's own).
--   * `perf_recognition_decide(p_token, p_id, p_status)`: Confirm and
--     Decline a waiting one, Revert to waiting (Work, a live unlock); never
--     one the caller gave or received (`own`); a confirmed one counted in a
--     month already shared or confirmed stays (`month-released`,
--     `period-confirmed`). The receiver is told of a confirmation.
--   * `perf_calc`: the month's confirmed recognitions times `rec_points`,
--     held to `rec_cap`, are added after the issues (`recognition`,
--     `recognition_raw`, `rec_points`, `rec_cap`, `recognitions`).
--   * `perf_settings_set`: `rec_points` (1), `rec_cap` (3; 0 turns the
--     points off) and `rec_confirm` (1 on, 0 off), each from a quarter on,
--     seeded from Q3 2026 into a key with no row.
--   * `perf_activity`: every recognition step, filed in the review trail as
--     `recognition.given`, `.withdrawn`, `.restored`, `.confirmed`,
--     `.declined` and `.reverted`, is listed in the Activity record under
--     Performance, whose month and colleague it concerns.
--   * `my_hr_remind`: no longer asks for a reflection; the self-rating and
--     the health check-in as before.
--
-- ORDER: this file first (it adds and restates; a page open from before
-- reads the extra figures of perf_calc and ignores them), then the pages.
-- A page open from before this file and after the pages' deploy offers
-- Recognition and reads "This feature is not available yet" until this file
-- is applied. Safe to run twice.
--
-- ROLLBACK: run perf_calc (BREACH POINTS ADDED AS NUMBERS), perf_settings_set
-- (VIC PERFORMANCE), perf_activity (PERFORMANCE SELF-RATING) and my_hr_remind
-- (A HALF MONTH'S REMINDER ALWAYS COMES) from schema.sql at the commit before
-- this file; then
-- drop function public.perf_recognition_decide(text, uuid, text);
-- drop function public.perf_review_recognitions(text, uuid, date);
-- drop function public.perf_recognitions_mine();
-- drop function public.perf_recognition_withdraw(uuid, boolean);
-- drop function public.perf_recognition_give(uuid, text, text);
-- drop function public.perf_recognition_json(public.perf_recognitions);
-- drop function public.perf_recognition_month(uuid, date, date);
-- drop table public.perf_recognitions;
-- delete from public.perf_settings where key in ('rec_points', 'rec_cap', 'rec_confirm');
-- ===========================================================================

-- RECOGNITION — the table, the helpers, the calls ------------------------------

create table if not exists public.perf_recognitions (
  id             uuid primary key default gen_random_uuid(),
  giver_id       uuid not null references public.team_members(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  category       text not null check (category in ('helped', 'effort', 'praise')),
  note           text not null check (char_length(note) between 3 and 500),
  given_on       date not null,
  status         text not null default 'waiting' check (status in ('waiting', 'confirmed', 'declined', 'withdrawn')),
  period         date check (period is null or extract(day from period) = 1),
  decided_by     uuid references public.team_members(id) on delete set null,
  decided_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint perf_recognitions_not_own check (giver_id <> team_member_id),
  constraint perf_recognitions_counted check ((status = 'confirmed') = (period is not null))
);
create index if not exists perf_recognitions_member_idx on public.perf_recognitions(team_member_id, period);
create index if not exists perf_recognitions_giver_idx on public.perf_recognitions(giver_id, created_at desc);
alter table public.perf_recognitions enable row level security;
revoke all on table public.perf_recognitions from public, anon, authenticated;

-- The figures as approved, from Q3 2026, into a key that has no row.
insert into public.perf_settings (key, from_period, value)
select k.key, date '2026-07-01', k.value
  from (values ('rec_points', 1), ('rec_cap', 3), ('rec_confirm', 1)) k(key, value)
 where not exists (select 1 from public.perf_settings s where s.key = k.key);

/* The month a recognition counts in: the month given, unless that month's
   review is already shared or its quarter or half confirmed; then the month
   in hand, or the next month neither holds. */
create or replace function public.perf_recognition_month(p_member uuid, p_given date, p_today date)
returns date
language plpgsql stable security definer set search_path = public as $$
declare v_p date := date_trunc('month', p_given)::date; v_n integer := 0;
begin
  if not (exists (select 1 from public.perf_reviews r
                   where r.team_member_id = p_member and r.period = v_p and r.status <> 'draft')
          or public.perf_period_held(v_p) is not null) then
    return v_p;
  end if;
  v_p := greatest(v_p, date_trunc('month', p_today)::date);
  while v_n < 36 and (exists (select 1 from public.perf_reviews r
                               where r.team_member_id = p_member and r.period = v_p and r.status <> 'draft')
                      or public.perf_period_held(v_p) is not null) loop
    v_p := (v_p + interval '1 month')::date;
    v_n := v_n + 1;
  end loop;
  return v_p;
end $$;
revoke all on function public.perf_recognition_month(uuid, date, date) from public, anon, authenticated;

create or replace function public.perf_recognition_json(x public.perf_recognitions)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', x.id, 'team_member_id', x.team_member_id,
    'name', (select t.name from public.team_members t where t.id = x.team_member_id),
    'giver_id', x.giver_id, 'giver', (select t.name from public.team_members t where t.id = x.giver_id),
    'category', x.category, 'note', x.note, 'given_on', x.given_on,
    'month', public.perf_month_word(date_trunc('month', x.given_on)::date),
    'status', x.status, 'period', x.period,
    'period_month', case when x.period is not null then public.perf_month_word(x.period) end,
    'decided_by', (select t.name from public.team_members t where t.id = x.decided_by),
    'decided_at', x.decided_at, 'created_at', x.created_at)
$$;
revoke all on function public.perf_recognition_json(public.perf_recognitions) from public, anon, authenticated;

create or replace function public.perf_recognition_give(p_to uuid, p_category text, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_gate jsonb; v_me public.team_members; v_to public.team_members; v_note text := btrim(coalesce(p_note, ''));
  v_today date := public.perf_today(); x public.perf_recognitions; v_on boolean;
begin
  v_gate := public.perf_mine_gate();
  if v_gate is not null then return v_gate; end if;
  v_me := public.ops_me();
  if p_to is null then return jsonb_build_object('error', 'bad-colleague'); end if;
  if p_to = v_me.id then return jsonb_build_object('error', 'own'); end if;
  select * into v_to from public.team_members t
   where t.id = p_to and t.active and not coalesce(t.system, false) and t.removed_at is null;
  if v_to.id is null then return jsonb_build_object('error', 'bad-colleague'); end if;
  if p_category is null or p_category not in ('helped', 'effort', 'praise') then
    return jsonb_build_object('error', 'bad-category');
  end if;
  if char_length(v_note) < 3 then return jsonb_build_object('error', 'note-needed'); end if;
  if char_length(v_note) > 500 then return jsonb_build_object('error', 'too-long'); end if;
  -- The same press again: the first answer stands.
  select * into x from public.perf_recognitions r
   where r.giver_id = v_me.id and r.team_member_id = p_to and r.category = p_category and r.note = v_note
     and r.status <> 'withdrawn' and r.created_at > now() - interval '10 minutes'
   order by r.created_at desc limit 1;
  if x.id is not null then
    return jsonb_build_object('ok', true, 'again', true, 'recognition', public.perf_recognition_json(x));
  end if;
  if (select count(*) from public.perf_recognitions r
       where r.giver_id = v_me.id and r.given_on = v_today) >= 10 then
    return jsonb_build_object('error', 'too-many');
  end if;
  v_on := coalesce(public.perf_setting('rec_confirm', v_today), 1) <> 0;
  insert into public.perf_recognitions (giver_id, team_member_id, category, note, given_on, status, period, decided_at)
  values (v_me.id, p_to, p_category, v_note, v_today,
          case when v_on then 'waiting' else 'confirmed' end,
          case when v_on then null else public.perf_recognition_month(p_to, v_today, v_today) end,
          case when v_on then null else now() end)
  returning * into x;
  perform public.perf_log((select r.id from public.perf_reviews r
                            where r.team_member_id = x.team_member_id and r.period = coalesce(x.period, date_trunc('month', x.given_on)::date)),
    x.team_member_id, 'recognition.given', jsonb_build_object('recognition', x.id, 'category', x.category,
      'period', coalesce(x.period, date_trunc('month', x.given_on)::date), 'confirmed', not v_on));
  perform public.perf_notify(x.team_member_id, 'perf.recognition',
    v_me.name || ' recognised you: ' || case x.category when 'helped' then 'Helped a colleague'
                                                       when 'effort' then 'Extra effort' else 'Client praise' end || '.',
    'recognition:' || x.id || ':given');
  return jsonb_build_object('ok', true, 'recognition', public.perf_recognition_json(x));
end $$;

create or replace function public.perf_recognition_withdraw(p_id uuid, p_back boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_gate jsonb; v_me public.team_members; x public.perf_recognitions;
  v_from text := case when coalesce(p_back, false) then 'withdrawn' else 'waiting' end;
begin
  v_gate := public.perf_mine_gate();
  if v_gate is not null then return v_gate; end if;
  v_me := public.ops_me();
  select * into x from public.perf_recognitions r where r.id = p_id and r.giver_id = v_me.id for update;
  if x.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if x.status <> v_from then return jsonb_build_object('error', 'decided'); end if;
  update public.perf_recognitions
     set status = case when coalesce(p_back, false) then 'waiting' else 'withdrawn' end, updated_at = now()
   where id = x.id returning * into x;
  perform public.perf_log(null, x.team_member_id,
    case when coalesce(p_back, false) then 'recognition.restored' else 'recognition.withdrawn' end,
    jsonb_build_object('recognition', x.id, 'period', date_trunc('month', x.given_on)::date));
  return jsonb_build_object('ok', true, 'recognition', public.perf_recognition_json(x));
end $$;

create or replace function public.perf_recognitions_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_gate jsonb; v_me public.team_members;
begin
  v_gate := public.perf_mine_gate();
  if v_gate is not null then return v_gate; end if;
  v_me := public.ops_me();
  return jsonb_build_object(
    'received', coalesce((select jsonb_agg(public.perf_recognition_json(r) order by r.created_at desc)
                            from public.perf_recognitions r
                           where r.team_member_id = v_me.id and r.status <> 'withdrawn'), '[]'::jsonb),
    'given', coalesce((select jsonb_agg(public.perf_recognition_json(r) order by r.created_at desc)
                         from public.perf_recognitions r
                        where r.giver_id = v_me.id and r.status <> 'withdrawn'), '[]'::jsonb),
    'confirm', coalesce(public.perf_setting('rec_confirm', public.perf_today()), 1) <> 0);
end $$;

/* Beside a month's review: what was given in the month (withdrawn left out)
   and every confirmed recognition counted in it, with the month's figures. */
create or replace function public.perf_review_recognitions(p_token text, p_member uuid, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_p date := date_trunc('month', p_period)::date;
begin
  v_err := public.perf_check(p_token, 'view');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  if p_member is null or p_member = v_me.id then return jsonb_build_object('error', 'own-review'); end if;
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(public.perf_recognition_json(r)
                                       || jsonb_build_object('mine', r.giver_id = v_me.id)
                                       order by r.given_on, r.created_at)
                        from public.perf_recognitions r
                       where r.team_member_id = p_member and r.status <> 'withdrawn'
                         and (r.period = v_p or date_trunc('month', r.given_on)::date = v_p)), '[]'::jsonb),
    'points', public.perf_setting('rec_points', v_p), 'cap', public.perf_setting('rec_cap', v_p));
end $$;

create or replace function public.perf_recognition_decide(p_token text, p_id uuid, p_status text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; x public.perf_recognitions; v_was text; v_held jsonb; v_p date;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  select * into x from public.perf_recognitions r where r.id = p_id for update;
  if x.id is null or x.status = 'withdrawn' then return jsonb_build_object('error', 'not-found'); end if;
  if v_me.id in (x.giver_id, x.team_member_id) then return jsonb_build_object('error', 'own'); end if;
  if p_status is null or p_status not in ('confirmed', 'declined', 'waiting') then
    return jsonb_build_object('error', 'bad-status');
  end if;
  if not ((x.status = 'waiting' and p_status in ('confirmed', 'declined'))
       or (x.status in ('confirmed', 'declined') and p_status = 'waiting')) then
    return jsonb_build_object('error', 'bad-move');
  end if;
  -- A month already shared, or a quarter or half confirmed, keeps what it counted.
  if x.status = 'confirmed' then
    if exists (select 1 from public.perf_reviews r
                where r.team_member_id = x.team_member_id and r.period = x.period and r.status <> 'draft') then
      return jsonb_build_object('error', 'month-released', 'month', public.perf_month_word(x.period));
    end if;
    v_held := public.perf_period_held(x.period);
    if v_held is not null then return v_held; end if;
  end if;
  v_was := x.status;
  v_p := case when p_status = 'confirmed'
              then public.perf_recognition_month(x.team_member_id, x.given_on, public.perf_today()) end;
  update public.perf_recognitions
     set status = p_status, period = v_p,
         decided_by = case when p_status = 'waiting' then null else v_me.id end,
         decided_at = case when p_status = 'waiting' then null else now() end,
         updated_at = now()
   where id = x.id returning * into x;
  perform public.perf_log((select r.id from public.perf_reviews r
                            where r.team_member_id = x.team_member_id and r.period = coalesce(v_p, date_trunc('month', x.given_on)::date)),
    x.team_member_id, 'recognition.' || case p_status when 'waiting' then 'reverted' else p_status end,
    jsonb_build_object('recognition', x.id, 'from', v_was, 'period', coalesce(v_p, date_trunc('month', x.given_on)::date)));
  if p_status = 'confirmed' then
    perform public.perf_notify(x.team_member_id, 'perf.recognition',
      'Your recognition from ' || coalesce((select t.name from public.team_members t where t.id = x.giver_id), 'a colleague') || ' was confirmed.',
      'recognition:' || x.id || ':confirmed:' || extract(epoch from now())::bigint);
  end if;
  return jsonb_build_object('ok', true, 'recognition', public.perf_recognition_json(x) || jsonb_build_object('mine', false));
end $$;

revoke all on function public.perf_recognition_give(uuid, text, text) from public, anon, authenticated;
revoke all on function public.perf_recognition_withdraw(uuid, boolean) from public, anon, authenticated;
revoke all on function public.perf_recognitions_mine() from public, anon, authenticated;
revoke all on function public.perf_review_recognitions(text, uuid, date) from public, anon, authenticated;
revoke all on function public.perf_recognition_decide(text, uuid, text) from public, anon, authenticated;
grant execute on function public.perf_recognition_give(uuid, text, text) to authenticated;
grant execute on function public.perf_recognition_withdraw(uuid, boolean) to authenticated;
grant execute on function public.perf_recognitions_mine() to authenticated;
grant execute on function public.perf_review_recognitions(text, uuid, date) to authenticated;
grant execute on function public.perf_recognition_decide(text, uuid, text) to authenticated;

/* The month's score: the issues taken off, then the confirmed recognitions
   counted in the month added, held to the month's limit. */
create or replace function public.perf_calc(r public.perf_reviews)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  base numeric; raw_ded numeric; ded numeric; fin numeric; l3 boolean; l4 boolean;
  g text; cap integer; rk integer; prev public.perf_reviews; prev_g text; ok boolean;
  complete boolean; path text; ads boolean; bd text; bc text; bm text;
  rank_of constant text := 'ABCDE';
  v_cap numeric;
  v_rpts numeric; v_rcap numeric; v_rn integer; raw_rec numeric; rec numeric;
begin
  if r.status = 'final' and r.result is not null then return r.result; end if;
  complete := r.s_output is not null and r.s_accuracy is not null and r.s_delivery is not null
          and r.s_client is not null and r.s_comms is not null and r.s_initiative is not null;
  base := coalesce(r.s_output, 0) + coalesce(r.s_accuracy, 0) + coalesce(r.s_delivery, 0)
        + coalesce(r.s_client, 0) + coalesce(r.s_comms, 0) + coalesce(r.s_initiative, 0);
  /* Each issue's points exactly as the settings give them (two decimals,
     times the VIC multiplier), the month's total rounded once, to the 0.1
     step the scores take, before the cap. */
  select round(coalesce(sum(public.perf_points_at(severity, repeated, late, vic, r.period)), 0), 1),
         coalesce(bool_or(severity = 3), false), coalesce(bool_or(severity = 4), false)
    into raw_ded, l3, l4
    from public.perf_breaches
   where team_member_id = r.team_member_id and period = r.period and voided_at is null;
  v_cap := public.perf_setting('ded_cap', r.period);
  ded := greatest(raw_ded, -v_cap);
  /* Recognitions (2026-11-22): each confirmed one counted in the month adds
     the month's points, held to its limit; a limit of 0 adds none. */
  v_rpts := coalesce(public.perf_setting('rec_points', r.period), 0);
  v_rcap := coalesce(public.perf_setting('rec_cap', r.period), 0);
  select count(*) into v_rn from public.perf_recognitions x
   where x.team_member_id = r.team_member_id and x.period = r.period and x.status = 'confirmed';
  raw_rec := round(v_rn * v_rpts, 1);
  rec := least(raw_rec, v_rcap);
  fin := greatest(0, least(100, base + ded + rec));
  g := public.perf_grade_at(fin, r.period);
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
    'recognition', rec, 'recognition_raw', raw_rec, 'recognitions', v_rn,
    'rec_points', v_rpts, 'rec_cap', v_rcap,
    'final', fin, 'cap', v_cap,
    'points', jsonb_build_object('1', public.perf_setting('ded_l1', r.period), '2', public.perf_setting('ded_l2', r.period),
                                 '3', public.perf_setting('ded_l3', r.period), '4', public.perf_setting('ded_l4', r.period),
                                 'repeat', public.perf_setting('ded_repeat', r.period), 'late', public.perf_setting('ded_late', r.period),
                                 'vic', public.perf_setting('ded_vic', r.period)),
    'raw_grade', public.perf_grade_at(fin, r.period), 'grade', g,
    'grade_word', public.perf_grade_word(g),
    'capped', case when rk > position(public.perf_grade_at(fin, r.period) in rank_of) then (case when l4 then 'D' else 'B' end) end,
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
revoke all on function public.perf_calc(public.perf_reviews) from public, anon, authenticated;

create or replace function public.perf_settings_set(p_token text, p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_err text; v_me public.team_members; v_from date; v_k text; v_v numeric; v_was numeric;
  v_changed jsonb := '[]'::jsonb;
  v_keys constant text[] := array['prize_individual', 'prize_department', 'prize_department_min_total',
    'flex_team_share', 'flex_member_min', 'bonus_pool_revenue',
    'bonus_pool_profit_pct', 'trip_revenue', 'bonus_months_b', 'units_a', 'units_b', 'units_c', 'commission_min',
    'grade_a', 'grade_b', 'grade_c', 'grade_d', 'ded_l1', 'ded_l2', 'ded_l3', 'ded_l4', 'ded_repeat', 'ded_late',
    'ded_cap', 'dispute_days', 'remind_before_days', 'remind_again_days', 'ded_vic',
    'rec_points', 'rec_cap', 'rec_confirm'];
  v_a numeric; v_b numeric; v_c numeric; v_d numeric;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  if not public.perf_is_admin() then return jsonb_build_object('error', 'admin-only'); end if;
  v_me := public.ops_me();
  v_from := date_trunc('quarter', p_from)::date;
  if v_from is null or v_from < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  if exists (select 1 from public.perf_rewards r
              where (r.kind = 'quarter' and r.period >= v_from)
                 or (r.kind = 'period' and (r.period + interval '6 months')::date > v_from)) then
    return jsonb_build_object('error', 'confirmed');
  end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if v_v < 0 or round(v_v, 2) <> v_v
       or (v_k in ('prize_individual', 'prize_department', 'bonus_pool_revenue', 'trip_revenue') and v_v >= 1e9)
       or (v_k in ('prize_department_min_total', 'flex_team_share', 'flex_member_min',
                   'bonus_pool_profit_pct', 'commission_min', 'grade_a', 'grade_b', 'grade_c', 'grade_d',
                   'ded_l1', 'ded_l2', 'ded_l3', 'ded_l4', 'ded_repeat', 'ded_late', 'ded_cap',
                   'rec_points', 'rec_cap') and v_v > 100)
       or (v_k = 'rec_confirm' and v_v not in (0, 1))
       or (v_k = 'dispute_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k in ('remind_before_days', 'remind_again_days') and (v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'bonus_months_b' and (v_v > 6 or v_v <> trunc(v_v)))
       or (v_k = 'ded_vic' and (v_v < 1 or v_v > 10))
       or (v_k in ('units_a', 'units_b', 'units_c') and v_v > 10) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  -- The grade bands stay in order from the quarter on: A above B above C above D.
  v_a := coalesce((p_values ->> 'grade_a')::numeric, public.perf_setting('grade_a', v_from));
  v_b := coalesce((p_values ->> 'grade_b')::numeric, public.perf_setting('grade_b', v_from));
  v_c := coalesce((p_values ->> 'grade_c')::numeric, public.perf_setting('grade_c', v_from));
  v_d := coalesce((p_values ->> 'grade_d')::numeric, public.perf_setting('grade_d', v_from));
  if not (v_a > v_b and v_b > v_c and v_c > v_d and v_d > 0) then
    return jsonb_build_object('error', 'bad-order');
  end if;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.perf_setting(v_k, v_from);
    if v_was is distinct from v_v then
      insert into public.perf_settings (key, from_period, value, set_by, set_at)
      values (v_k, v_from, v_v, v_me.id, now())
      on conflict (key, from_period) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      v_changed := v_changed || jsonb_build_array(jsonb_build_object('key', v_k, 'from', v_was, 'to', v_v));
    end if;
  end loop;
  if jsonb_array_length(v_changed) > 0 then
    perform public.perf_log(null, null, 'settings_set', jsonb_build_object('from_period', v_from,
      'word', public.perf_quarter_word(v_from), 'changed', v_changed));
  end if;
  return public.perf_settings_read(p_token);
end $$;
revoke all on function public.perf_settings_set(text, date, jsonb) from public, anon, authenticated;
grant execute on function public.perf_settings_set(text, date, jsonb) to authenticated;

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
             'period', coalesce(rv.period, case when e.kind in ('deleted', 'self.saved') or e.kind like 'recognition.%'
                                                then (e.detail ->> 'period')::date end),
             'actor', e.actor_email, 'actor_name', ac.name,
             'auto', coalesce((e.detail ->> 'auto')::boolean, false)) order by e.created_at desc)
      from (select pe.* from public.perf_events pe
             where (pe.kind in ('released', 'opened', 'self.saved', 'disputed', 'decided', 'acknowledged',
                                'finalised', 'reopened', 'returned', 'printed', 'deleted')
                    or pe.kind in ('recognition.given', 'recognition.withdrawn', 'recognition.restored',
                                   'recognition.confirmed', 'recognition.declined', 'recognition.reverted'))
               and pe.team_member_id is distinct from me_row.id
             order by pe.created_at desc
             limit greatest(1, least(coalesce(p_limit, 200), 500))) e
      left join public.team_members tm on tm.id = e.team_member_id
      left join public.perf_reviews rv on rv.id = e.review_id
      left join public.team_members ac on ac.id = e.actor_id), '[]'::jsonb));
end $$;
revoke all on function public.perf_activity(integer) from public, anon, authenticated;
grant execute on function public.perf_activity(integer) to authenticated;

/* The reminders ask for the self-rating and the health check-in; the
   reflection has left the pages (2026-11-22), so none asks for it. */
create or replace function public.my_hr_remind(p_today date default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_today    date := coalesce(p_today, public.health_today());
  v_before   integer := coalesce(public.perf_setting('remind_before_days', coalesce(p_today, public.health_today())), 3)::integer;
  v_again    integer := coalesce(public.perf_setting('remind_again_days', coalesce(p_today, public.health_today())), 3)::integer;
  v_month    date := date_trunc('month', coalesce(p_today, public.health_today()))::date;
  v_last     date;
  v_half     date;
  v_hbefore  integer;
  v_after    boolean;
  v_half_day boolean;
  v_self     boolean;
  v_health   boolean;
  v_title    text;
  m          record;
  n          integer := 0;
begin
  v_last := (v_month - interval '1 month')::date;
  v_half := public.health_half(v_today);
  v_after := extract(day from v_today) = 1 or (v_again > 0 and extract(day from v_today) = 1 + v_again);
  /* A half month is 13 to 16 days long: the days before its end are never
     more than the days it has, so a February's second half is reminded on
     its first day at the latest, never not at all. */
  v_hbefore := least(v_before, public.health_half_end(v_half) - v_half);
  v_half_day := v_before > 0 and v_today = public.health_half_end(v_half) - v_hbefore;
  if not (v_after or v_half_day) then return 0; end if;
  for m in select t.id from public.team_members t where t.active order by t.id loop
    v_self := false; v_health := false;
    if v_after and public.perf_reviewed(m.id) then
      v_self := public.perf_self_open(m.id, v_last) is null
                and not exists (select 1 from public.perf_self_ratings s
                                 where s.team_member_id = m.id and s.period = v_last);
    end if;
    if v_half_day then
      v_health := public.health_agreed(m.id)
                  and not exists (select 1 from public.health_checkins k
                                   where k.team_member_id = m.id and k.half = v_half);
    end if;
    if not (v_self or v_health) then continue; end if;
    if v_self and v_health then
      v_title := 'Rate yourself for ' || public.perf_month_word(v_last) || ' and check in on your health.';
    elsif v_self then
      v_title := 'Rate yourself for ' || public.perf_month_word(v_last) || '.';
    else
      v_title := 'Check in on your health by ' || to_char(public.health_half_end(v_half), 'FMDD FMMonth') || '.';
    end if;
    insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
    values (m.id, null, case when v_self then 'perf.remind' else 'health.remind' end,
            v_title, null, 'myhr.remind.' || m.id || '.' || v_today)
    on conflict (dedupe_key) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.my_hr_remind(date) from public, anon, authenticated;

-- END OF RECOGNITION -----------------------------------------------------------

select public.functions_tidy();
