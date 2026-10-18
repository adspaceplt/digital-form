-- ===========================================================================
-- A LEFT COLLEAGUE'S DRAFT NEVER HOLDS THE HALF — a bonus and trip period
-- no longer waits on a draft review of a colleague who has left, and names
-- the reviews it does wait on. 2026-10-18. Safe to run twice. Rollback at
-- the foot. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/perf.js compares the two.
--
-- WHAT CHANGED (follow-up to HALF YEAR WAITS ON FINAL MONTHS, #567)
--   A draft review that was started and never scored, of a colleague who
--   has since left, can never become final: perf_release refuses an
--   incomplete month and perf_close_windows skips a draft. Counted as open,
--   it held the whole half from being confirmed for good. Such a draft is
--   no longer counted (an inactive colleague earns no share); a released,
--   queried or acknowledged month of theirs still is, since it closes by
--   itself. perf_period answers `open_reviews` (name, month, state) beside
--   the count, and Bonus and trip names them.
--
-- ROLLBACK
--   Run the perf_period and perf_period_confirm definitions of the HALF
--   YEAR WAITS ON FINAL MONTHS section of supabase/schema.sql again.
-- ===========================================================================

create or replace function public.perf_period(p_token text, p_from date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_f date; v_rw public.perf_rewards; v_c public.perf_company; v_out jsonb;
begin
  v_err := public.perf_check(p_token, 'view');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_f := public.perf_half(coalesce(p_from, public.perf_today()));
  if v_f < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  select * into v_rw from public.perf_rewards where kind = 'period' and period = v_f;
  v_out := coalesce(v_rw.snapshot, public.perf_period_calc(v_f));
  v_out := v_out || jsonb_build_object(
    'people', public.perf_hide_own(v_out -> 'people', v_me.id),
    'admin', public.perf_is_admin(),
    'confirmed', v_rw.period is not null, 'confirmed_at', v_rw.confirmed_at,
    'confirmed_by', (select t.name from public.team_members t where t.id = v_rw.confirmed_by),
    'ended', public.perf_today() >= (v_f + interval '6 months')::date,
    /* What still waits: every review of the six months not final, but a
       draft of a colleague who has left, which can never be released and
       earns no share. */
    'open_months', (select count(*)::int from public.perf_reviews r
                      join public.team_members t on t.id = r.team_member_id
                     where r.status <> 'final' and r.period >= v_f and r.period < (v_f + interval '6 months')::date
                       and not (r.status = 'draft' and not t.active)),
    'open_reviews', (select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'period', r.period, 'status', r.status)
                                               order by r.period, t.name), '[]'::jsonb)
                       from public.perf_reviews r
                       join public.team_members t on t.id = r.team_member_id
                      where r.status <> 'final' and r.period >= v_f and r.period < (v_f + interval '6 months')::date
                        and not (r.status = 'draft' and not t.active)),
    'events', public.perf_reward_events(array['company_set', 'period_confirmed', 'period_reopened'], v_f::text));
  /* Revenue and profit, and the ceiling they set, for an admin alone. */
  if public.perf_is_admin() then
    select * into v_c from public.perf_company where period = v_f;
    if v_c.period is not null then
      v_out := v_out || jsonb_build_object('company', jsonb_build_object('revenue', v_c.revenue, 'profit', v_c.profit,
        'pool', v_c.pool, 'trip_budget', v_c.trip_budget, 'max_pool', greatest(0, floor(v_c.profit * public.perf_setting('bonus_pool_profit_pct', v_f)) / 100)));
    end if;
  end if;
  return v_out;
end $$;

create or replace function public.perf_period_confirm(p_token text, p_from date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_f date; v_snap jsonb; v_x jsonb; v_open integer;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_f := public.perf_half(p_from);
  if v_f is null or v_f < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if exists (select 1 from public.perf_rewards where kind = 'period' and period = v_f) then
    return public.perf_period(p_token, v_f);
  end if;
  if public.perf_today() < (v_f + interval '6 months')::date then
    return jsonb_build_object('error', 'period-open');
  end if;
  /* Every review in the six months final first, as a quarter's: the
     calculation reads final months alone, and a snapshot is kept. A draft
     of a colleague who has left never can be, and earns no share. */
  select count(*)::int into v_open
    from public.perf_reviews r
    join public.team_members t on t.id = r.team_member_id
   where r.status <> 'final' and r.period >= v_f and r.period < (v_f + interval '6 months')::date
     and not (r.status = 'draft' and not t.active);
  if v_open > 0 then
    return jsonb_build_object('error', 'months-open', 'count', v_open, 'scope', 'period');
  end if;
  if not exists (select 1 from public.perf_company where period = v_f) then
    return jsonb_build_object('error', 'figures-needed');
  end if;
  v_snap := public.perf_period_calc(v_f);
  insert into public.perf_rewards (kind, period, snapshot, confirmed_by) values ('period', v_f, v_snap, v_me.id)
  on conflict (kind, period) do nothing;
  perform public.perf_log(null, null, 'period_confirmed', jsonb_build_object('key', v_f::text));
  for v_x in select * from jsonb_array_elements(v_snap -> 'people') loop
    if (v_x ->> 'active')::boolean then
      perform public.perf_notify((v_x ->> 'team_member_id')::uuid, 'perf.period',
        'Your ' || public.perf_period_word(v_f) || ' bonus and trip outcome is ready.',
        'perf.period.' || v_f || '.' || (v_x ->> 'team_member_id') || '.' || extract(epoch from now())::bigint);
    end if;
  end loop;
  return public.perf_period(p_token, v_f);
end $$;

revoke all on function public.perf_period(text, date) from public, anon, authenticated;
revoke all on function public.perf_period_confirm(text, date) from public, anon, authenticated;
grant execute on function public.perf_period(text, date) to authenticated;
grant execute on function public.perf_period_confirm(text, date) to authenticated;

-- END OF A LEFT COLLEAGUE'S DRAFT NEVER HOLDS THE HALF ----------------------

select public.functions_tidy();
