-- ===========================================================================
-- MY HR REMINDERS — a nudge for what a colleague still owes: the month's
-- reflection before it ends, last month's rating and reflection on the 1st
-- and again a few days on, and the health check-in before each half month
-- ends.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/health.js compares the
-- two. Runs after PERFORMANCE SELF-RATING and HEALTH CHECK-INS.
--
-- WHAT CHANGED (the user, 2026-10-07: "send periodic u suggest reminder for
-- those being selected for review on the self rating and reflection before
-- the month ends and after"; the health check-in "every two weeks with
-- reflection for the month reminders")
--   1. Two Performance settings, from Q3 2026 into a key that has no row:
--      `remind_before_days` (3: the days before a month or a half month
--      ends that its reminder goes out) and `remind_again_days` (3: the days
--      after the 1st that last month's goes out again); each 0 to 14, 0
--      sending none. `perf_settings_set` takes both.
--   2. `my_hr_remind(p_today)`, every day at 09:05 MYT (pg_cron
--      `my-hr-reminders`), one notice a colleague a day at most, naming
--      only what is still owed:
--        - on the 1st, and again `remind_again_days` on: a colleague on the
--          review list rates last month while it is open and unrated, and
--          writes its reflection while it is open and empty;
--        - `remind_before_days` before the month's last day: this month's
--          reflection, while empty;
--        - `remind_before_days` before each half month ends (the 15th, the
--          month's last day): the health check-in, for every active
--          colleague whose agreement stands and who has not checked in
--          (never one who has not agreed); at the month's end it shares the
--          reflection's notice.
--      Never a score or a note; no browser calls it.
--   3. `ops_notifications_push` opens the reminder where it points (Reviews,
--      Reflection, Health), a query on a review the team's month, and an
--      initiative decided the colleague's Initiatives.
--
-- ROLLBACK (in the SQL Editor)
--   select cron.unschedule('my-hr-reminders');
--   Run ops_notifications_push from HR LETTERS SHARED and perf_settings_set
--   from PERFORMANCE RULE SETTINGS again; then drop my_hr_remind.
-- ===========================================================================

insert into public.perf_settings (key, from_period, value)
select k.key, date '2026-07-01', k.value
  from (values ('remind_before_days', 3), ('remind_again_days', 3)) k(key, value)
 where not exists (select 1 from public.perf_settings s where s.key = k.key);

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
    'ded_cap', 'dispute_days', 'remind_before_days', 'remind_again_days'];
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

/* What a colleague still owes today, in one notice. */
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
  v_after    boolean;
  v_end_day  boolean;
  v_half_day boolean;
  v_self     boolean;
  v_rlast    boolean;
  v_refl     boolean;
  v_health   boolean;
  v_parts    text[];
  v_said     text;
  v_title    text;
  m          record;
  n          integer := 0;
begin
  v_last := (v_month - interval '1 month')::date;
  v_half := public.health_half(v_today);
  v_after := extract(day from v_today) = 1 or (v_again > 0 and extract(day from v_today) = 1 + v_again);
  v_end_day := v_before > 0 and v_today = (v_month + interval '1 month' - interval '1 day')::date - v_before;
  v_half_day := v_before > 0 and v_today = public.health_half_end(v_half) - v_before;
  if not (v_after or v_end_day or v_half_day) then return 0; end if;
  for m in select t.id from public.team_members t where t.active order by t.id loop
    v_self := false; v_rlast := false; v_refl := false; v_health := false;
    if public.perf_reviewed(m.id) then
      if v_after then
        v_self := public.perf_self_open(m.id, v_last) is null
                  and not exists (select 1 from public.perf_self_ratings s
                                   where s.team_member_id = m.id and s.period = v_last);
        v_rlast := public.perf_reflection_open(m.id, v_last) is null
                   and not exists (select 1 from public.perf_reflections f
                                    where f.team_member_id = m.id and f.period = v_last
                                      and coalesce(f.proud, f.hard, f.learn) is not null);
      end if;
      if v_end_day then
        v_refl := public.perf_reflection_open(m.id, v_month) is null
                  and not exists (select 1 from public.perf_reflections f
                                   where f.team_member_id = m.id and f.period = v_month
                                     and coalesce(f.proud, f.hard, f.learn) is not null);
      end if;
    end if;
    if v_half_day then
      v_health := public.health_agreed(m.id)
                  and not exists (select 1 from public.health_checkins k
                                   where k.team_member_id = m.id and k.half = v_half);
    end if;
    v_parts := array[]::text[];
    if v_self and v_rlast then
      v_parts := v_parts || ('rate yourself and write your reflection for ' || public.perf_month_word(v_last));
    elsif v_self then
      v_parts := v_parts || ('rate yourself for ' || public.perf_month_word(v_last));
    elsif v_rlast then
      v_parts := v_parts || ('write your reflection for ' || public.perf_month_word(v_last));
    end if;
    if v_refl then v_parts := v_parts || ('write your ' || public.perf_month_word(v_month) || ' reflection'); end if;
    if v_health then v_parts := v_parts || 'check in on your health'::text; end if;
    if cardinality(v_parts) = 0 then continue; end if;
    if cardinality(v_parts) = 1 and v_refl then
      v_title := 'Write your reflection for ' || public.perf_month_word(v_month) || ' before the month ends.';
    elsif cardinality(v_parts) = 1 and v_health then
      v_title := 'Check in on your health by ' || to_char(public.health_half_end(v_half), 'FMDD FMMonth') || '.';
    else
      v_said := case cardinality(v_parts)
                  when 1 then v_parts[1]
                  when 2 then v_parts[1] || ' and ' || v_parts[2]
                  else v_parts[1] || ', ' || v_parts[2] || ' and ' || v_parts[3] end;
      v_title := upper(left(v_said, 1)) || substr(v_said, 2) || '.';
    end if;
    insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
    values (m.id, null,
            case when v_self then 'perf.remind' when v_rlast or v_refl then 'perf.reflect' else 'health.remind' end,
            v_title, null, 'myhr.remind.' || m.id || '.' || v_today)
    on conflict (dedupe_key) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.my_hr_remind(date) from public, anon, authenticated;

create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.task_id is not null then '/admin/?s=work&open=' || new.task_id::text
         when new.report_id is not null then '/admin/?s=reports&report=' || new.report_id::text
         when new.kind = 'client_left' then '/admin/?s=work'
         when new.kind = 'hr.letter' then '/admin/?s=mine&view=letters'
         when new.kind = 'perf.disputed' then '/admin/?s=team&tab=performance'
         when new.kind = 'perf.reflect' then '/admin/?s=mine&view=reflection'
         when new.kind = 'perf.initiative' then '/admin/?s=mine&view=initiatives'
         when new.kind like 'health.%' then '/admin/?s=mine&view=health'
         when new.kind like 'perf.%' then '/admin/?s=mine'
         else '/admin/' end,
    case when new.task_id is not null then 'task-' || new.task_id::text
         when new.report_id is not null then 'report-' || new.report_id::text
         when new.kind = 'hr.letter' then 'hr-letter'
         when new.kind in ('perf.remind', 'perf.reflect', 'health.remind') then 'my-hr'
         else null end);
  return new;
exception when others then
  return new;
end $$;

revoke all on function public.perf_settings_set(text, date, jsonb) from public, anon, authenticated;
grant execute on function public.perf_settings_set(text, date, jsonb) to authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: no reminders go out until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'my-hr-reminders';
  perform cron.schedule('my-hr-reminders', '5 1 * * *', 'select public.my_hr_remind()');
end $$;

-- END OF MY HR REMINDERS ------------------------------------------------------
