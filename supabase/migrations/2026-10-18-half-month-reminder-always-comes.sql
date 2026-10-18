-- ===========================================================================
-- A HALF MONTH'S REMINDER ALWAYS COMES — the health reminder's days before a
-- half month ends are held to the days the half has (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 19): `remind_before_days` may be up to 14, and the
-- health reminder went out that many days before the half month's end. The
-- second half of February runs 13 days (16 to 28 February; 14 in a leap
-- year), so at 13 or 14 its day fell in the first half and nobody was
-- reminded to check in for it.
--
-- WHAT IT CHANGES
--   * `my_hr_remind`: the days before a half month's end are the lesser of
--     the setting and the days from the half's first day to its last, so the
--     reminder comes on the half's first day at the latest. The month's
--     reflection reminder and everything else are as before.
--
-- ORDER: this file alone (no page reads it). Safe to run twice.
-- Rollback: run MY HR REMINDERS' `my_hr_remind` again.
-- ===========================================================================

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
  /* A half month is 13 to 16 days long: the days before its end are never
     more than the days it has, so a February's second half is reminded on
     its first day at the latest, never not at all. */
  v_hbefore := least(v_before, public.health_half_end(v_half) - v_half);
  v_half_day := v_before > 0 and v_today = public.health_half_end(v_half) - v_hbefore;
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

-- END OF A HALF MONTH'S REMINDER ALWAYS COMES -------------------------------

select public.functions_tidy();
