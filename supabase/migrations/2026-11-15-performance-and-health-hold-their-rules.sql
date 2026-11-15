-- ===========================================================================
-- PERFORMANCE AND HEALTH HOLD TO THEIR RULES (2026-11-15)
-- ===========================================================================
-- WHY: the phase 2 audit of Performance and Health (2026-11-15; the user:
-- "Ok fix all 21").
--
-- WHAT IT CHANGES
--   * `perf_period_held(p_period)` (a helper no page calls): the confirmed
--     quarter or half a month falls in, as perf_reopen and perf_delete read
--     it, answered as their `period-confirmed` refusal (`kind`, `word`).
--   * `perf_open` (a month not begun), `perf_save` and `perf_release` refuse
--     `period-confirmed` inside a confirmed quarter or half: Q3 2026 was
--     confirmed while a new review could still be begun, scored and shared in
--     it. Reopen under Quarters or Bonus and trip is the way through.
--   * `perf_save` refuses `bad-month` (with `from`) before June 2026 or after
--     the month in hand (`perf_today()`).
--   * `perf_printed`: one's own record asks the fresh proof (`perf_mine_gate`)
--     before it is filed.
--   * `perf_month` also lists a colleague no longer active whose review of
--     the month is not a draft (the Confirm gates count it), with `active`.
--   * `perf_commission_json`: the commission is rounded down to the cent, as
--     every other reward share is.
--   * `health_team(p_token)`: a talk is listed only while its asker's
--     agreement stands, as their answers are.
--   * Dropped, nothing calling them: `health_checkin_save(jsonb, text)` (it
--     saved into the current half with no stale-half check),
--     `health_consent(boolean)`, `health_team()`, `perf_deduction`,
--     `perf_deduction_at`, `perf_deduction_vic_at`, `perf_grade_of`.
--
-- ORDER: the pages first (Withdraw sends `p_wording`; the refusals are said in
-- words), then this file. A page open from before that withdraws an
-- agreement is refused until it is reloaded. Safe to run twice.
--
-- ROLLBACK: run perf_open, perf_save, perf_release, perf_printed, perf_month,
-- perf_commission_json and health_team(text) from schema.sql at the commit
-- before this file, and the dropped functions from their sections there
-- (HEALTH TERMS ARE VERSIONED, HEALTH CHECK-INS, A CHECK-IN KEEPS ITS HALF
-- MONTH, PERFORMANCE RULE SETTINGS, VIC PERFORMANCE); then
-- drop function public.perf_period_held(date);
-- ===========================================================================

-- PERFORMANCE AND HEALTH HOLD TO THEIR RULES ----------------------------------

create or replace function public.perf_period_held(p_period date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w public.perf_rewards; p date := date_trunc('month', p_period)::date;
begin
  select * into w from public.perf_rewards x
   where (x.kind = 'quarter' and x.period = date_trunc('quarter', p)::date)
      or (x.kind = 'period' and x.period = public.perf_half(p))
   order by x.kind limit 1;
  if w.kind is null then return null; end if;
  return jsonb_build_object('error', 'period-confirmed', 'kind', w.kind,
    'word', case w.kind when 'quarter' then public.perf_quarter_word(w.period) else public.perf_period_word(w.period) end);
end $$;
revoke all on function public.perf_period_held(date) from public, anon, authenticated;

create or replace function public.perf_open(p_token text, p_member uuid, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; p date := date_trunc('month', p_period)::date;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  select * into r from public.perf_reviews where team_member_id = p_member and period = p;
  if r.id is null then
    /* A month inside a confirmed quarter or half is never begun: the period
       is reopened first (audit 2026-11-15). */
    if public.perf_period_held(p) is not null then return public.perf_period_held(p); end if;
    /* Not started: the shape of a draft, written nowhere until it is saved. */
    r.team_member_id := p_member; r.period := p; r.status := 'draft';
    r.notes := '{}'::jsonb; r.version := 1; r.rev := 0;
  end if;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_save(p_token text, p_member uuid, p_period date,
                                            p_payload jsonb, p_rev integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; r public.perf_reviews; p date := date_trunc('month', p_period)::date;
  sc jsonb := coalesce(p_payload -> 'scores', '{}'::jsonb);
  rt jsonb := coalesce(p_payload -> 'rates', '{}'::jsonb);
  k text; v jsonb; mx numeric; rb date; ev date; was public.perf_reviews; changed jsonb; held jsonb;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if not exists (select 1 from public.team_members where id = p_member and active) then
    return jsonb_build_object('error', 'not-found');
  end if;
  /* Reviews run from June 2026 to the month in hand, never ahead of it. */
  if p < date '2026-06-01' or p > date_trunc('month', public.perf_today())::date then
    return jsonb_build_object('error', 'bad-month', 'from', date '2026-06-01');
  end if;
  if jsonb_typeof(sc) <> 'object' or jsonb_typeof(rt) <> 'object'
     or (p_payload ? 'notes' and jsonb_typeof(p_payload -> 'notes') <> 'object') then
    return jsonb_build_object('error', 'bad-payload');
  end if;
  for k, v in select key, value from jsonb_each(sc) loop
    mx := case k when 'output' then 25 when 'accuracy' then 15 when 'delivery' then 15
                 when 'client' then 20 when 'comms' then 15 when 'initiative' then 10 end;
    if mx is null then return jsonb_build_object('error', 'bad-score', 'key', k); end if;
    if jsonb_typeof(v) <> 'null' then
      if jsonb_typeof(v) <> 'number' then return jsonb_build_object('error', 'bad-score', 'key', k, 'max', mx); end if;
      if (v #>> '{}')::numeric not between 0 and mx or round((v #>> '{}')::numeric, 1) <> (v #>> '{}')::numeric then
        return jsonb_build_object('error', 'bad-score', 'key', k, 'max', mx);
      end if;
    end if;
  end loop;
  for k, v in select key, value from jsonb_each(rt) loop
    mx := case k when 'pacing' then 1000 when 'posting' then 100 when 'timeline' then 100
                 when 'satisfaction' then 100 when 'sla' then 100 end;
    if mx is null then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
    if jsonb_typeof(v) <> 'null' then
      if jsonb_typeof(v) <> 'number' then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
      if (v #>> '{}')::numeric not between 0 and mx then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
    end if;
  end loop;
  if coalesce(p_payload ->> 'review_by', '') <> '' then
    begin
      rb := (p_payload ->> 'review_by')::date;
    exception when others then
      return jsonb_build_object('error', 'bad-date');
    end;
  end if;

  /* The day the month was evaluated: on or after its first day, never
     after today in Malaysia. */
  if coalesce(p_payload ->> 'evaluated_on', '') <> '' then
    begin
      ev := (p_payload ->> 'evaluated_on')::date;
    exception when others then
      return jsonb_build_object('error', 'bad-eval-date');
    end;
    if ev < p or ev > (now() at time zone 'Asia/Kuala_Lumpur')::date then
      return jsonb_build_object('error', 'bad-eval-date');
    end if;
  end if;

  /* A month inside a confirmed quarter or half is paid on that snapshot:
     nothing in it is begun or scored until the period is reopened. */
  held := public.perf_period_held(p);
  if held is not null then return held; end if;

  select * into r from public.perf_reviews where team_member_id = p_member and period = p for update;
  if r.id is null then
    insert into public.perf_reviews (team_member_id, period) values (p_member, p)
    on conflict (team_member_id, period) do nothing;
    select * into r from public.perf_reviews where team_member_id = p_member and period = p for update;
    perform public.perf_log(r.id, p_member, 'started', '{}'::jsonb);
  elsif p_rev is not null and r.rev <> p_rev then
    return jsonb_build_object('error', 'stale', 'record', public.perf_json(r, true));
  end if;
  /* The scores are the draft's. What the month asks of the person next (the
     improvement, the date it is reviewed by, the step or reward) is written
     at the 1-1 and may be filled in until the record is final. */
  if r.status = 'final' or (r.status <> 'draft'
       and (p_payload - 'improvement' - 'review_by' - 'reward_step' - 'evaluated_on') <> '{}'::jsonb) then
    return jsonb_build_object('error', 'not-draft');
  end if;

  was := r;
  update public.perf_reviews set
    s_output     = case when sc ? 'output'     then (sc ->> 'output')::numeric     else s_output end,
    s_accuracy   = case when sc ? 'accuracy'   then (sc ->> 'accuracy')::numeric   else s_accuracy end,
    s_delivery   = case when sc ? 'delivery'   then (sc ->> 'delivery')::numeric   else s_delivery end,
    s_client     = case when sc ? 'client'     then (sc ->> 'client')::numeric     else s_client end,
    s_comms      = case when sc ? 'comms'      then (sc ->> 'comms')::numeric      else s_comms end,
    s_initiative = case when sc ? 'initiative' then (sc ->> 'initiative')::numeric else s_initiative end,
    r_posting      = case when rt ? 'posting'      then (rt ->> 'posting')::numeric      else r_posting end,
    r_timeline     = case when rt ? 'timeline'     then (rt ->> 'timeline')::numeric     else r_timeline end,
    r_satisfaction = case when rt ? 'satisfaction' then (rt ->> 'satisfaction')::numeric else r_satisfaction end,
    r_pacing       = case when rt ? 'pacing'       then (rt ->> 'pacing')::numeric       else r_pacing end,
    r_sla          = case when rt ? 'sla'          then (rt ->> 'sla')::numeric          else r_sla end,
    notes       = case when p_payload ? 'notes' then coalesce(p_payload -> 'notes', '{}'::jsonb) else notes end,
    improvement = case when p_payload ? 'improvement' then nullif(btrim(p_payload ->> 'improvement'), '') else improvement end,
    review_by   = case when p_payload ? 'review_by' then rb else review_by end,
    reward_step = case when p_payload ? 'reward_step' then nullif(btrim(p_payload ->> 'reward_step'), '') else reward_step end,
    evaluated_on = case when p_payload ? 'evaluated_on' then ev else evaluated_on end,
    updated_at = now(), rev = rev + 1
  where id = r.id
  returning * into r;
  /* What the save changed, named: each scorecard and rate whose value moved,
     from and to, then whether the notes or the plan moved. A save that moved
     nothing is not filed. */
  select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'from', c.a, 'to', c.b) order by c.n), '[]'::jsonb)
    into changed
    from (values (1, 'output', was.s_output, r.s_output), (2, 'accuracy', was.s_accuracy, r.s_accuracy),
                 (3, 'delivery', was.s_delivery, r.s_delivery), (4, 'client', was.s_client, r.s_client),
                 (5, 'comms', was.s_comms, r.s_comms), (6, 'initiative', was.s_initiative, r.s_initiative),
                 (7, 'posting', was.r_posting, r.r_posting), (8, 'timeline', was.r_timeline, r.r_timeline),
                 (9, 'satisfaction', was.r_satisfaction, r.r_satisfaction), (10, 'pacing', was.r_pacing, r.r_pacing),
                 (11, 'sla', was.r_sla, r.r_sla)) as c(n, key, a, b)
   where c.a is distinct from c.b;
  if coalesce(was.notes, '{}'::jsonb) is distinct from coalesce(r.notes, '{}'::jsonb) then
    changed := changed || jsonb_build_array(jsonb_build_object('key', 'notes'));
  end if;
  if was.improvement is distinct from r.improvement or was.review_by is distinct from r.review_by
     or was.reward_step is distinct from r.reward_step then
    changed := changed || jsonb_build_array(jsonb_build_object('key', 'plan'));
  end if;
  if was.evaluated_on is distinct from r.evaluated_on then
    changed := changed || jsonb_build_array(jsonb_build_object('key', 'evaluated_on', 'from', was.evaluated_on, 'to', r.evaluated_on));
  end if;
  if jsonb_array_length(changed) > 0 then
    perform public.perf_log(r.id, p_member, 'scored', jsonb_build_object('changed', changed));
  end if;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_release(p_token text, p_review uuid, p_rev integer, p_notify boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; tm public.team_members; held jsonb;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if p_rev is not null and r.rev <> p_rev then
    return jsonb_build_object('error', 'stale', 'record', public.perf_json(r, true));
  end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  held := public.perf_period_held(r.period);
  if held is not null then return held; end if;
  if not (public.perf_calc(r) ->> 'complete')::boolean then
    return jsonb_build_object('error', 'incomplete');
  end if;
  select * into tm from public.team_members where id = r.team_member_id;
  if r.serial is null and coalesce(btrim(tm.staff_code), '') = '' then
    return jsonb_build_object('error', 'no-staff-code');
  end if;
  update public.perf_reviews set status = 'released', released_at = now(),
         dispute_until = now() + make_interval(days => public.perf_setting('dispute_days', r.period)::integer), reviewer_id = m.id,
         evaluated_on = coalesce(evaluated_on, (now() at time zone 'Asia/Kuala_Lumpur')::date),
         serial = coalesce(serial, 'ADHR/' || upper(btrim(tm.staff_code)) || '/PR' || to_char(period, 'YYMM')),
         rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'released',
    jsonb_build_object('version', r.version, 'notified', coalesce(p_notify, true)));
  if coalesce(p_notify, true) then
    perform public.perf_notify(r.team_member_id, 'perf.released',
      'Your ' || public.perf_month_word(r.period) || ' performance review is ready.',
      -- released again after a correction is told again (audit 2026-11-15)
      'perf.released.' || r.id || '.' || r.version || '.' || r.rev);
  end if;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_printed(p_review uuid, p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews; ev_id uuid; ev_at timestamptz; g jsonb;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.perf_reviews where id = p_review;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id <> m.id and public.perf_check(p_token, 'view') is not null then
    return jsonb_build_object('error', 'denied');
  end if;
  /* One's own record asks the fresh proof My records asks. */
  if r.team_member_id = m.id then
    g := public.perf_mine_gate();
    if g is not null then return g; end if;
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

create or replace function public.perf_month(p_token text, p_period date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; p date := date_trunc('month', p_period)::date;
begin
  err := public.perf_check(p_token, 'view');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  return jsonb_build_object(
    'period', p, 'month', public.perf_month_word(p),
    'people', coalesce((select jsonb_agg(x order by x ->> 'name') from (
      select jsonb_build_object(
        'team_member_id', t.id, 'name', t.name, 'staff_code', t.staff_code, 'active', t.active,
        'designation', t.designation,
        'department', t.department, 'role_family', t.role_family,
        'runs_ads', coalesce(pp.runs_ads, false),
        'reviewed', public.perf_reviewed(t.id),
        'breaches', (select count(*) from public.perf_breaches b
                      where b.team_member_id = t.id and b.period = p and b.voided_at is null),
        'review', case when r.id is null then null else jsonb_build_object(
          'id', r.id, 'status', r.status, 'result', public.perf_calc(r),
          'open_disputes', (select count(*) from public.perf_disputes d
                             where d.review_id = r.id and d.version = r.version and d.decision is null),
          'dispute_until', r.dispute_until) end) as x
        from public.team_members t
        left join public.perf_people pp on pp.team_member_id = t.id
        left join public.perf_reviews r on r.team_member_id = t.id and r.period = p
       where t.id <> m.id
         and (t.active or (r.id is not null and r.status <> 'draft'))) q), '[]'::jsonb));
end $$;

create or replace function public.perf_commission_json(c public.perf_commissions)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_r public.perf_reviews; v_res jsonb; v_state text; v_why text;
begin
  select * into v_r from public.perf_reviews where team_member_id = c.team_member_id and period = c.month;
  v_res := case when v_r.id is not null and v_r.status = 'final' then coalesce(v_r.result, public.perf_calc(v_r)) end;
  if v_res is null then
    v_state := 'pending'; v_why := 'month-not-final';
  elsif (v_res ->> 'final')::numeric < public.perf_setting('commission_min', c.month) then
    v_state := 'not-payable'; v_why := 'below-c';
  elsif coalesce((v_res ->> 'l3')::boolean, false) or coalesce((v_res ->> 'l4')::boolean, false) then
    v_state := 'not-payable'; v_why := 'breach';
  else
    v_state := 'payable';
  end if;
  return jsonb_build_object('id', c.id, 'team_member_id', c.team_member_id,
    'name', (select t.name from public.team_members t where t.id = c.team_member_id),
    'staff_code', (select t.staff_code from public.team_members t where t.id = c.team_member_id),
    'client_id', c.client_id,
    'client', (select cl.name from public.clients cl where cl.id = c.client_id),
    'client_code', (select cl.client_code from public.clients cl where cl.id = c.client_id),
    'description', c.description, 'month', c.month, 'month_word', public.perf_month_word(c.month),
    'net_profit', c.net_profit, 'pct', c.pct, 'amount', round(floor(c.net_profit * c.pct) / 100, 2),
    'state', v_state, 'reason', v_why, 'created_at', c.created_at,
    'created_by', (select t.name from public.team_members t where t.id = c.created_by),
    'removed_at', c.removed_at, 'min', public.perf_setting('commission_min', c.month));
end $$;

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
       where k.status <> 'withdrawn' and k.created_at > now() - interval '90 days'
         and public.health_agreed(k.team_member_id)), '[]'::jsonb));
end $$;

revoke all on function public.perf_open(text, uuid, date) from public, anon, authenticated;
revoke all on function public.perf_save(text, uuid, date, jsonb, integer) from public, anon, authenticated;
revoke all on function public.perf_release(text, uuid, integer, boolean) from public, anon, authenticated;
revoke all on function public.perf_printed(uuid, text) from public, anon, authenticated;
revoke all on function public.perf_month(text, date) from public, anon, authenticated;
revoke all on function public.perf_commission_json(public.perf_commissions) from public, anon, authenticated;
revoke all on function public.health_team(text) from public, anon, authenticated;
grant execute on function public.perf_open(text, uuid, date) to authenticated;
grant execute on function public.perf_save(text, uuid, date, jsonb, integer) to authenticated;
grant execute on function public.perf_release(text, uuid, integer, boolean) to authenticated;
grant execute on function public.perf_printed(uuid, text) to authenticated;
grant execute on function public.perf_month(text, date) to authenticated;
grant execute on function public.health_team(text) to authenticated;

drop function if exists public.health_checkin_save(jsonb, text);
drop function if exists public.health_consent(boolean);
drop function if exists public.health_team();
drop function if exists public.perf_deduction(integer, boolean, boolean);
drop function if exists public.perf_deduction_vic_at(integer, boolean, boolean, boolean, date);
drop function if exists public.perf_deduction_at(integer, boolean, boolean, date);
drop function if exists public.perf_grade_of(numeric);

-- END OF PERFORMANCE AND HEALTH HOLD TO THEIR RULES ---------------------------

select public.functions_tidy();
