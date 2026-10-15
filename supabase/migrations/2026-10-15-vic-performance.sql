-- ===========================================================================
-- VIC PERFORMANCE — an issue on a VIC client's work counts double in a
-- performance review (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15: issues on VIC client work "2x penalize your
-- performance")
--   An issue logged in a monthly review may name the client it concerns; an
--   issue on a Very Important Client's work takes its points off times a
--   Performance setting.
--
-- WHAT CHANGED
--   * `perf_breaches.client_id` (optional; no foreign key, so a client's
--     removal never touches a review) and `perf_breaches.vic`, stamped by
--     trigger `perf_breaches_vic` at logging from the client's VIC state
--     then, and never changed after (`vic-stamped`).
--   * Performance setting `ded_vic` (2, from Q3 2026; 1 to 10), in
--     Performance settings' Months part; `perf_settings_set` takes it.
--   * `perf_deduction_vic_at(severity, repeated, late, vic, at)`: an issue's
--     points, times `ded_vic` where it is a VIC client's. `perf_calc` adds
--     them up with it, still under `ded_cap`, and names the multiplier in
--     `points.vic`.
--   * `perf_breach_log` takes `client_id` (`bad-client`), and
--     `perf_breaches_json` sends the client's name, `vic` and `vic_x`, so the
--     review sheet, the member's page and the printed record read
--     "VIC client · ×2" on that issue. Never a score in a notification.
--
-- ORDER
--   This file, then the pages (the issue sheet's Client select; an old page
--   logs issues with no client, as before).
--
-- Safe to run twice. Rollback: run PERFORMANCE RULE SETTINGS' perf_calc, the
-- PERFORMANCE section's perf_breaches_json and perf_breach_log and the last
-- perf_settings_set again; the columns and the setting may stay unread.
-- ===========================================================================

alter table public.perf_breaches add column if not exists client_id uuid;
alter table public.perf_breaches add column if not exists vic boolean not null default false;

/* An issue is a VIC client's as the client stood the day it was logged. */
create or replace function public.perf_breaches_vic()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.vic := new.client_id is not null
               and exists (select 1 from public.clients c where c.id = new.client_id and c.vic_at is not null);
  elsif new.vic is distinct from old.vic or new.client_id is distinct from old.client_id then
    raise exception 'vic-stamped'
      using hint = 'Whether an issue was a VIC client''s is kept as it was logged.';
  end if;
  return new;
end $$;
revoke all on function public.perf_breaches_vic() from public, anon, authenticated;
create or replace trigger perf_breaches_vic
  before insert or update of vic, client_id on public.perf_breaches
  for each row execute function public.perf_breaches_vic();

insert into public.perf_settings (key, from_period, value)
select 'ded_vic', date '2026-07-01', 2
 where not exists (select 1 from public.perf_settings s where s.key = 'ded_vic');

/* An issue's points, times the VIC multiplier where it is a VIC client's. */
create or replace function public.perf_deduction_vic_at(p_severity integer, p_repeated boolean, p_late boolean,
                                                        p_vic boolean, p_at date)
returns integer
language sql stable security definer set search_path = public as $$
  select round(public.perf_deduction_at(p_severity, p_repeated, p_late, p_at)
               * case when p_vic then coalesce(public.perf_setting('ded_vic', p_at), 1) else 1 end)::integer
$$;
revoke all on function public.perf_deduction_vic_at(integer, boolean, boolean, boolean, date) from public, anon, authenticated;

create or replace function public.perf_breaches_json(p_member uuid, p_period date, p_with_void boolean)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'occurred_on', b.occurred_on, 'category', b.category,
           'severity', b.severity, 'repeated', b.repeated, 'late', b.late,
           'what', b.what, 'evidence', b.evidence,
           'deduction', public.perf_deduction_vic_at(b.severity, b.repeated, b.late, b.vic, public.perf_today()),
           'client_id', b.client_id, 'client_name', (select c.name from public.clients c where c.id = b.client_id),
           'vic', b.vic, 'vic_x', case when b.vic then public.perf_setting('ded_vic', public.perf_today()) end,
           'logged_by', (select name from public.team_members where id = b.logged_by),
           'logged_at', b.logged_at, 'voided_at', b.voided_at, 'void_reason', b.void_reason)
         order by b.occurred_on, b.logged_at), '[]'::jsonb)
    from public.perf_breaches b
   where b.team_member_id = p_member and b.period = p_period
     and (p_with_void or b.voided_at is null)
$$;
revoke all on function public.perf_breaches_json(uuid, date, boolean) from public, anon, authenticated;

create or replace function public.perf_calc(r public.perf_reviews)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  base numeric; raw_ded integer; ded integer; fin numeric; l3 boolean; l4 boolean;
  g text; cap integer; rk integer; prev public.perf_reviews; prev_g text; ok boolean;
  complete boolean; path text; ads boolean; bd text; bc text; bm text;
  rank_of constant text := 'ABCDE';
  v_cap numeric;
begin
  if r.status = 'final' and r.result is not null then return r.result; end if;
  complete := r.s_output is not null and r.s_accuracy is not null and r.s_delivery is not null
          and r.s_client is not null and r.s_comms is not null and r.s_initiative is not null;
  base := coalesce(r.s_output, 0) + coalesce(r.s_accuracy, 0) + coalesce(r.s_delivery, 0)
        + coalesce(r.s_client, 0) + coalesce(r.s_comms, 0) + coalesce(r.s_initiative, 0);
  select coalesce(sum(public.perf_deduction_vic_at(severity, repeated, late, vic, r.period)), 0),
         coalesce(bool_or(severity = 3), false), coalesce(bool_or(severity = 4), false)
    into raw_ded, l3, l4
    from public.perf_breaches
   where team_member_id = r.team_member_id and period = r.period and voided_at is null;
  v_cap := public.perf_setting('ded_cap', r.period);
  ded := greatest(raw_ded, -v_cap::integer);
  fin := greatest(0, least(100, base + ded));
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

create or replace function public.perf_breach_log(p_token text, p_member uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; on_ date; p date; cat text; sev integer; rep boolean;
  st text; nb public.perf_breaches; cl uuid;
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
  /* The client it concerns, optional (2026-10-15): a VIC client's issue
     counts double, stamped at logging. */
  if nullif(p_payload ->> 'client_id', '') is not null then
    begin cl := (p_payload ->> 'client_id')::uuid; exception when others then cl := null; end;
    if cl is null or not exists (select 1 from public.clients c where c.id = cl) then
      return jsonb_build_object('error', 'bad-client');
    end if;
  end if;
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
                                    repeated, late, what, evidence, logged_by, client_id)
  values (p_member, on_, p, cat, sev, rep, coalesce((p_payload ->> 'late')::boolean, false),
          btrim(p_payload ->> 'what'), nullif(btrim(p_payload ->> 'evidence'), ''), m.id, cl)
  returning * into nb;
  perform public.perf_log((select id from public.perf_reviews where team_member_id = p_member and period = p),
    p_member, 'breach_logged', jsonb_build_object('breach', nb.id, 'category', cat, 'severity', sev,
      'repeated', rep, 'late', nb.late, 'vic', nb.vic,
      'deduction', public.perf_deduction_vic_at(sev, rep, nb.late, nb.vic, public.perf_today())));
  return jsonb_build_object('ok', true, 'id', nb.id, 'repeated', rep, 'vic', nb.vic,
    'deduction', public.perf_deduction_vic_at(sev, rep, nb.late, nb.vic, public.perf_today()), 'period', p);
end $$;
revoke all on function public.perf_breach_log(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.perf_breach_log(text, uuid, jsonb) to authenticated;

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
    'ded_cap', 'dispute_days', 'remind_before_days', 'remind_again_days', 'ded_vic'];
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
                   'ded_l1', 'ded_l2', 'ded_l3', 'ded_l4', 'ded_repeat', 'ded_late', 'ded_cap') and v_v > 100)
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

-- END OF VIC PERFORMANCE ------------------------------------------------------
select public.functions_tidy();
