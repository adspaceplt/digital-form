-- ===========================================================================
-- PRESSES HELD AND FIGURES KEPT (2026-11-24)
-- ===========================================================================
-- WHY: the audit of 2026-11-24 of the migrations since 2026-11-09 (the
-- user: "fix all except 2"), each a wrong case found in the last
-- definition:
--   * `quotation_invoice_done`: one colleague's Cancel let go of another's
--     claim still being made, so a third press made a second invoice.
--   * `perf_quarter_confirm`: two confirms at once both filed the quarter
--     and told every colleague twice.
--   * `personnel_salary_set`: a colleague at Personnel holding the master
--     code set their own salary.
--   * `perf_recognition_give`: two presses at once made two recognitions,
--     past the daily ten.
--   * `ops_stage_times`: each colleague's own figures reached a reader at
--     My Work's Reports who may not read every colleague's work.
--   * `outstation_route_set`: a reading made while the trip was open and
--     answered after Check out took away its way back and its total.
--
-- ORDER: this file, then the pages (Personnel says `own-salary`; an old
-- page reads it as Not saved). Safe to run twice.
-- ROLLBACK: run the six functions from their last definitions before this
-- banner in schema.sql.
-- ===========================================================================

-- PRESSES HELD AND FIGURES KEPT ----------------------------------------------

create or replace function public.quotation_invoice_done(p_id uuid, p_cycle int, p_kind text, p_bukku bigint, p_number text, p_amount numeric)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q public.quotations;
  v_num text := nullif(left(btrim(coalesce(p_number, '')), 60), '');
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if v_num is null then
    -- a cancel lets go of the caller's own claim alone, never another's
    -- still being made (2026-11-24)
    update public.quotation_invoices set claimed_at = null, claimed_by = null
     where quotation_id = q.id and cycle = p_cycle and kind = p_kind and number is null and claimed_by = me.id;
    return jsonb_build_object('ok', true);
  end if;
  update public.quotation_invoices set number = v_num, bukku_id = nullif(p_bukku, 0), amount = p_amount,
         currency = case when q.totals->>'currency' = 'SGD' then 'SGD' else 'MYR' end,
         made_at = now(), made_by = me.id, claimed_at = null, claimed_by = null
   where quotation_id = q.id and cycle = p_cycle and kind = p_kind and number is null;
  if found then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.billing', q.brand, q.ref || ' · ' ||
            case when p_kind = 'budget' then 'Advertising budget invoice ' else 'Invoice ' end ||
            v_num || ' created in Bukku as a draft · Month ' || p_cycle);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_invoice_done(uuid, integer, text, bigint, text, numeric) from public, anon;
grant execute on function public.quotation_invoice_done(uuid, integer, text, bigint, text, numeric) to authenticated;

create or replace function public.perf_quarter_confirm(p_token text, p_quarter date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_err text; v_me public.team_members; v_q date; v_snap jsonb; v_x jsonb; v_open integer;
begin
  v_err := public.perf_check(p_token, 'work');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  v_me := public.ops_me();
  v_q := date_trunc('quarter', p_quarter)::date;
  if v_q is null or v_q < date '2026-07-01' then return jsonb_build_object('error', 'before-first'); end if;
  if exists (select 1 from public.perf_rewards where kind = 'quarter' and period = v_q) then
    return public.perf_quarter(p_token, v_q);
  end if;
  if public.perf_today() < (v_q + interval '3 months')::date then
    return jsonb_build_object('error', 'quarter-open');
  end if;
  select count(*)::int into v_open
    from public.perf_reviews r join public.team_members t on t.id = r.team_member_id
   where r.status <> 'final' and r.period >= v_q and r.period < (v_q + interval '3 months')::date
     and not (r.status = 'draft' and not t.active);
  if v_open > 0 then
    return jsonb_build_object('error', 'months-open', 'count', v_open);
  end if;
  if exists (select 1 from public.departments k
              where k.active and k.in_prize
                and not exists (select 1 from public.perf_dept_scores s where s.quarter = v_q and s.department = k.key)) then
    return jsonb_build_object('error', 'dept-scores-needed');
  end if;
  v_snap := public.perf_quarter_calc(v_q);
  insert into public.perf_rewards (kind, period, snapshot, confirmed_by) values ('quarter', v_q, v_snap, v_me.id)
  on conflict (kind, period) do nothing;
  -- two confirms at once: the second files and tells nobody (2026-11-24)
  if not found then return public.perf_quarter(p_token, v_q); end if;
  perform public.perf_log(null, null, 'quarter_confirmed', jsonb_build_object('key', v_q::text,
    'winners', v_snap -> 'individual' -> 'winners', 'departments', v_snap -> 'department_prize' -> 'winners'));
  for v_x in select * from jsonb_array_elements(v_snap -> 'people') loop
    if (v_x ->> 'active')::boolean then
      perform public.perf_notify((v_x ->> 'team_member_id')::uuid, 'perf.quarter',
        'Your ' || public.perf_quarter_word(v_q) || ' quarterly outcome is ready.',
        'perf.quarter.' || v_q || '.' || (v_x ->> 'team_member_id') || '.' || extract(epoch from now())::bigint);
    end if;
  end loop;
  return public.perf_quarter(p_token, v_q);
end $$;
revoke all on function public.perf_quarter_confirm(text, date) from public, anon;
grant execute on function public.perf_quarter_confirm(text, date) to authenticated;

create or replace function public.personnel_salary_set(p_token text, p_member uuid, p_probation numeric, p_confirmed numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare e text; me public.team_members; t public.team_members; s public.personnel_salaries;
begin
  e := public.personnel_check(p_token);
  if e is not null then return jsonb_build_object('error', e); end if;
  me := public.ops_me();
  select * into t from public.team_members where id = p_member;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  -- a colleague's own salary is an admin's to set (2026-11-24)
  if t.id = me.id and not (me.is_admin or me.role = 'admin') then return jsonb_build_object('error', 'own-salary'); end if;
  if (p_probation is not null and (p_probation < 0 or p_probation >= 10000000))
     or (p_confirmed is not null and (p_confirmed < 0 or p_confirmed >= 10000000)) then
    return jsonb_build_object('error', 'bad-amount');
  end if;
  insert into public.personnel_salaries (team_member_id) values (p_member) on conflict (team_member_id) do nothing;
  select * into s from public.personnel_salaries where team_member_id = p_member for update;
  if s.probation is not distinct from round(p_probation, 2) and s.confirmed is not distinct from round(p_confirmed, 2) then
    return jsonb_build_object('ok', true, 'probation', s.probation, 'confirmed', s.confirmed, 'updated_at', s.updated_at);
  end if;
  update public.personnel_salaries set probation = round(p_probation, 2), confirmed = round(p_confirmed, 2),
         updated_at = now(), updated_by = me.id
   where team_member_id = p_member returning * into s;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, 'admin'), 'team.edited', t.name, 'Salary changed');
  return jsonb_build_object('ok', true, 'probation', s.probation, 'confirmed', s.confirmed, 'updated_at', s.updated_at);
end $$;
revoke all on function public.personnel_salary_set(text, uuid, numeric, numeric) from public, anon;
grant execute on function public.personnel_salary_set(text, uuid, numeric, numeric) to authenticated;

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
  -- one press at a time a giver: two at once passed the same-press and
  -- daily checks together (2026-11-24)
  perform pg_advisory_xact_lock(hashtext('rec:' || coalesce(v_me.id::text, '')));
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

create or replace function public.ops_stage_times(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  out jsonb;
begin
  if not public.ops_granted('ops.reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;

  with moves as (
    select e.task_id, e.created_at,
           e.from_value ->> 'stage_key' as from_key,
           e.to_value ->> 'stage_key' as to_key,
           row_number() over (partition by e.task_id order by e.created_at, e.id) as rn
      from public.ops_task_events e
     where e.event_type = 'stage_changed'
       and e.to_value ->> 'stage_key' is not null
  ),
  stays as (
    /* A move opens a stay in the stage it led into; the next move closes it. */
    select m.task_id, m.to_key as stage_key, m.created_at as from_at,
           lead(m.created_at) over (partition by m.task_id order by m.created_at, m.rn) as to_at
      from moves m
    union all
    /* The first stage, from the task's making to its first move. */
    select m.task_id, m.from_key, t.created_at, m.created_at
      from moves m
      join public.ops_tasks t on t.id = m.task_id
     where m.rn = 1 and m.from_key is not null and m.created_at > t.created_at
  ),
  kept as (
    select s.task_id, s.stage_key, s.from_at,
           extract(epoch from (s.to_at - s.from_at)) / 60 as mins,
           t.workflow_id, wf.key as wf_key,
           coalesce(
             (select a.team_member_id from public.ops_task_assignees a
               where a.task_id = s.task_id and a.responsibility = 'owner'
                 and a.assigned_at <= s.from_at and (a.ended_at is null or a.ended_at > s.from_at)
               order by a.assigned_at desc limit 1),
             (select a.team_member_id from public.ops_task_assignees a
               where a.task_id = s.task_id and a.responsibility = 'owner'
               order by a.assigned_at limit 1)) as owner_id
      from stays s
      join public.ops_tasks t on t.id = s.task_id
      join public.ops_workflows wf on wf.id = t.workflow_id
     where s.to_at is not null
       and s.to_at >= p_from and s.to_at < p_to
       and s.to_at - s.from_at >= interval '5 minutes'
       and public.ops_task_in_scope(s.task_id)
  ),
  stages as (
    select jsonb_agg(x order by x ->> 'workflow', (x ->> 'position')::int) as j from (
      select jsonb_build_object(
               'workflow', k.wf_key,
               'stage_key', k.stage_key,
               'label', coalesce(min(w.label), k.stage_key),
               'position', coalesce(min(w.position), 999),
               'stage_group', min(w.stage_group),
               'n', count(*),
               'tasks', count(distinct k.task_id),
               'median_minutes', round(percentile_cont(0.5) within group (order by k.mins))::int) as x
        from kept k
        left join public.ops_workflow_stages w on w.workflow_id = k.workflow_id and w.key = k.stage_key
       group by k.wf_key, k.stage_key
    ) q
  ),
  people as (
    select jsonb_agg(x order by x ->> 'name') as j from (
      select jsonb_build_object(
               'id', k.owner_id,
               'name', coalesce(tm.name, ''),
               'tasks', (select count(distinct k2.task_id) from kept k2 where k2.owner_id is not distinct from k.owner_id),
               'stages', jsonb_object_agg(k.wf_key || '|' || k.stage_key, jsonb_build_object(
                  'n', k.n, 'median_minutes', k.med))) as x
        from (select owner_id, wf_key, stage_key, count(*) as n,
                     round(percentile_cont(0.5) within group (order by mins))::int as med
                from kept group by owner_id, wf_key, stage_key) k
        left join public.team_members tm on tm.id = k.owner_id
       group by k.owner_id, tm.name
    ) q
  )
  select jsonb_build_object(
           'stages', coalesce((select j from stages), '[]'::jsonb),
           -- each colleague's own figures to a reader of every colleague's
           -- work alone, as ops_timeliness (2026-11-24)
           'people', case when public.ops_granted('ops.all', 'view') then coalesce((select j from people), '[]'::jsonb) else '[]'::jsonb end,
           'tasks', (select count(distinct task_id) from kept))
    into out;
  return out;
end $$;
revoke all on function public.ops_stage_times(timestamptz, timestamptz) from public, anon;
grant execute on function public.ops_stage_times(timestamptz, timestamptz) to authenticated;

create or replace function public.outstation_route_set(p_trip uuid, p_legs numeric[], p_back numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  select count(*) into v_n from public.outstation_stops s where s.trip_id = p_trip;
  if v_n = 0 then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(array_length(p_legs, 1), 0) <> v_n
     or exists (select 1 from unnest(p_legs) x where x is null or x < 0 or x > 5000)
     or (p_back is not null and (p_back < 0 or p_back > 5000)) then
    return jsonb_build_object('error', 'bad-value');
  end if;
  update public.outstation_stops s set km_from_prev = round(p_legs[s.seq], 1) where s.trip_id = p_trip;
  -- a reading made while the trip was open, answered after it closed,
  -- never takes away the way back and the total (2026-11-24)
  update public.outstation_trips t
     set km_back = case when t.state = 'closed' then coalesce(round(p_back, 1), t.km_back) end,
         km_total = case when t.state = 'closed' and p_back is not null
                         then round((select sum(round(x, 1)) from unnest(p_legs) x) + round(p_back, 1), 1)
                         when t.state = 'closed' then t.km_total end,
         updated_at = now()
   where t.id = p_trip;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.outstation_route_set(uuid, numeric[], numeric) from public, anon, authenticated;
grant execute on function public.outstation_route_set(uuid, numeric[], numeric) to service_role;

-- END OF PRESSES HELD AND FIGURES KEPT ---------------------------------------

select public.functions_tidy();
