-- ===========================================================================
-- AUDIT FIXES, SECOND BATCH (2026-11-15)
-- ===========================================================================
-- WHY: the whole-portal audit of 2026-11-15, its deeper read of the console's
-- screens, Performance, Health and the Assistant.
--
-- WHAT IT CHANGES
--   * `sm_report_revise`, `sm_report_version_restore`: a new version is not
--     sent (`sent_on`, `sent_by` cleared), so it never reads Sent before it is.
--   * `perf_release`: a month released again after a correction is told.
--   * `perf_unlock`: wrong master codes sent at once are counted in turn.
--   * `perf_flex_calc`, `perf_quarter_calc`, `perf_quarter_confirm`: a month
--     counts who was on the list then; a leaver's draft holds no Confirm.
--   * `health_talk_set`: a withdrawn talk is reopened only while no other
--     talk with that colleague is open.
--   * `ai_agent_turn`, `ai_agent_tokens`: a failed question takes no further
--     steps, and tokens spent are a use counted.
--   * `creator_bill_option`: a short earlier job ID never matches inside a
--     longer bill number.
--   * `creator_payments_queue`: a campaign's title only for a client seen.
--   * `team_member_remove_check`: an admin removed by the super admin alone,
--     before any work moves.
--
-- ORDER: this file, then the pages. Safe to run twice.
--
-- ROLLBACK: restate each function from its band before this one in
-- schema.sql.
-- ===========================================================================

-- AUDIT FIXES, SECOND BATCH --------------------------------------------------

create or replace function public.sm_report_revise(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'published' then return jsonb_build_object('error', 'not-published', 'status', r.status); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'draft', version_no = r.version_no + 1, return_note = null,
    submitted_by = null, submitted_at = null, confirmed_by = null, confirmed_at = null,
    -- a new version has not been sent (audit 2026-11-15)
    sent_on = null, sent_by = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.revised');
  return jsonb_build_object('ok', true, 'status', 'draft', 'version_no', r.version_no + 1);
end $$;
grant execute on function public.sm_report_revise(uuid) to authenticated;

create or replace function public.sm_report_version_restore(p_version uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v public.sm_report_versions;
  r public.sm_reports;
  s jsonb;
  head jsonb;
  nv integer;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.sm_report_versions where id = p_version;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into r from public.sm_reports where id = v.report_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if r.status not in ('draft', 'published') then return jsonb_build_object('error', 'in-review', 'status', r.status); end if;
  s := v.snapshot;
  head := coalesce(s -> 'report', '{}'::jsonb);
  nv := case when r.status = 'published' then r.version_no + 1 else r.version_no end;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports
     set status = 'draft', version_no = nv, return_note = null,
         submitted_by = null, submitted_at = null, confirmed_by = null, confirmed_at = null,
         -- a version restored is a draft not yet sent (audit 2026-11-15)
         sent_on = null, sent_by = null,
         headline = head ->> 'headline', intro = head ->> 'intro',
         insights = coalesce(head -> 'insights', '{}'::jsonb),
         rank_metric = coalesce(head ->> 'rank_metric', r.rank_metric),
         first_month = coalesce((head ->> 'first_month')::boolean, r.first_month),
         ads_totals = coalesce(nullif(head -> 'ads_totals', 'null'::jsonb), '{}'::jsonb)
   where id = r.id;
  delete from public.sm_report_posts where report_id = r.id;
  delete from public.sm_report_platforms where report_id = r.id;
  delete from public.sm_report_ads where report_id = r.id;
  insert into public.sm_report_platforms
  select (jsonb_populate_record(null::public.sm_report_platforms,
           jsonb_build_object('id', gen_random_uuid(), 'position', 0, 'metrics', jsonb_build_array('views', 'engagements'))
           || e.j || jsonb_build_object('report_id', r.id, 'created_at', now() + e.n * interval '1 microsecond'))).*
    from jsonb_array_elements(coalesce(s -> 'platforms', '[]'::jsonb)) with ordinality e(j, n);
  insert into public.sm_report_posts
  select (jsonb_populate_record(null::public.sm_report_posts,
           jsonb_build_object('id', gen_random_uuid(), 'position', 0)
           || (e.j - 'thumb_url')
           || jsonb_build_object('report_id', r.id, 'thumb_data', e.j -> 'thumb_url',
                                 'created_at', now() + e.n * interval '1 microsecond'))).*
    from jsonb_array_elements(coalesce(s -> 'posts', '[]'::jsonb)) with ordinality e(j, n);
  insert into public.sm_report_ads
  select (jsonb_populate_record(null::public.sm_report_ads,
           jsonb_build_object('id', gen_random_uuid(), 'position', 0, 'objective', 'awareness',
                              'age', '{}'::jsonb, 'retention', '{}'::jsonb, 'platform', 'meta')
           || (e.j - 'thumb_url')
           || jsonb_build_object('report_id', r.id, 'thumb_data', e.j -> 'thumb_url',
                                 'created_at', now() + e.n * interval '1 microsecond'))).*
    from jsonb_array_elements(coalesce(s -> 'ads', '[]'::jsonb)) with ordinality e(j, n);
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(r.id, 'report.revised', 'Restored from version ' || v.version_no);
  return jsonb_build_object('ok', true, 'status', 'draft', 'version_no', nv, 'from', v.version_no);
end $$;
revoke all on function public.sm_report_version_restore(uuid) from public, anon;
grant execute on function public.sm_report_version_restore(uuid) to authenticated;

create or replace function public.perf_release(p_token text, p_review uuid, p_rev integer, p_notify boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; tm public.team_members;
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

create or replace function public.perf_unlock(p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  m public.team_members; h text; a public.perf_attempts; tok text; f integer;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('team.performance', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select value into h from public.app_secrets where key = 'perf_code';
  if coalesce(h, '') = '' then return jsonb_build_object('error', 'no-code'); end if;
  /* The member's row taken first, so wrong codes sent at once are counted
     one after another, never all as the first (audit 2026-11-15). */
  insert into public.perf_attempts (team_member_id, failures) values (m.id, 0)
  on conflict (team_member_id) do nothing;
  select * into a from public.perf_attempts where team_member_id = m.id for update;
  if a.locked_until > now() then
    return jsonb_build_object('error', 'locked', 'until', a.locked_until);
  end if;
  if crypt(coalesce(p_code, ''), h) <> h then
    f := case when a.locked_until is not null then 1 else coalesce(a.failures, 0) + 1 end;
    insert into public.perf_attempts (team_member_id, failures, locked_until)
    values (m.id, f, case when f >= 5 then now() + interval '15 minutes' end)
    on conflict (team_member_id) do update
      set failures = excluded.failures, locked_until = excluded.locked_until;
    perform public.perf_log(null, null, 'unlock_failed', jsonb_build_object('failures', f));
    if f >= 5 then
      return jsonb_build_object('error', 'locked', 'until', now() + interval '15 minutes');
    end if;
    return jsonb_build_object('error', 'wrong-code', 'left', 5 - f);
  end if;
  delete from public.perf_attempts where team_member_id = m.id;
  delete from public.perf_unlocks where expires_at < now();
  tok := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.perf_unlocks (token_hash, team_member_id, expires_at)
  values (encode(sha256(convert_to(tok, 'UTF8')), 'hex'), m.id, now() + interval '15 minutes');
  perform public.perf_log(null, null, 'unlocked', '{}'::jsonb);
  return jsonb_build_object('token', tok, 'expires_at', now() + interval '15 minutes');
end $$;

create or replace function public.perf_flex_calc(p_period date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_p date := date_trunc('month', p_period)::date;
  v_total integer; v_finals integer; v_at integer; v_rows jsonb;
  v_share numeric := public.perf_setting('flex_team_share', date_trunc('month', p_period)::date);
  v_fmin numeric := public.perf_setting('flex_member_min', date_trunc('month', p_period)::date);
begin
  with m as (
    select t.id as mid, t.name as mname, t.staff_code as mcode,
           case when r.id is not null then coalesce(r.result, public.perf_calc(r)) end as res
      from public.team_members t
      left join public.perf_reviews r on r.team_member_id = t.id and r.period = v_p and r.status = 'final'
     /* Who was on the list in that month: a colleague added later never
        unsettles a month decided, nor one who left with a final review
        (audit 2026-11-15). */
     where (t.active and public.perf_reviewed(t.id)
            and date_trunc('month', t.created_at at time zone 'Asia/Kuala_Lumpur')::date <= v_p)
        or r.id is not null
  )
  select count(*)::int, count(m.res)::int,
         (count(*) filter (where (m.res ->> 'final')::numeric >= v_fmin))::int,
         coalesce(jsonb_agg(jsonb_build_object('team_member_id', m.mid, 'name', m.mname, 'staff_code', m.mcode,
           'final', m.res -> 'final', 'grade', m.res ->> 'grade',
           'breach', coalesce((m.res ->> 'l3')::boolean or (m.res ->> 'l4')::boolean, false),
           'eligible', coalesce((m.res ->> 'final')::numeric >= v_fmin
                                and not (m.res ->> 'l3')::boolean and not (m.res ->> 'l4')::boolean, false))
           order by m.mname), '[]'::jsonb)
    into v_total, v_finals, v_at, v_rows
    from m;
  return jsonb_build_object('period', v_p, 'month', public.perf_month_word(v_p),
    'next', (v_p + interval '1 month')::date,
    'next_month', public.perf_month_word((v_p + interval '1 month')::date),
    'members', v_total, 'finals', v_finals, 'at_70', v_at,
    'decided', v_total > 0 and v_finals = v_total,
    'unlocked', v_total > 0 and v_finals = v_total and v_at * 100 >= v_total * v_share,
    'people', v_rows, 'rules', jsonb_build_object('share', v_share, 'min', v_fmin));
end $$;

create or replace function public.perf_quarter_calc(p_quarter date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q date := date_trunc('quarter', p_quarter)::date;
  v_qe date := (date_trunc('quarter', p_quarter) + interval '3 months')::date;
  v_people jsonb; v_wins integer; v_each numeric; v_ind jsonb;
  v_depts jsonb; v_dwins integer; v_both boolean; v_why text; v_dp jsonb;
  v_open integer; v_missing integer; v_ended boolean := public.perf_today() >= (date_trunc('quarter', p_quarter) + interval '3 months')::date;
  v_ip numeric := public.perf_setting('prize_individual', date_trunc('quarter', p_quarter)::date);
  v_dpool numeric := public.perf_setting('prize_department', date_trunc('quarter', p_quarter)::date);
  v_dmin numeric := public.perf_setting('prize_department_min_total', date_trunc('quarter', p_quarter)::date);
begin
  with m as (
    select t.id as mid, t.name as mname, t.staff_code as mcode, t.department as mdept, t.active as mactive,
           public.perf_reviewed(t.id) as monlist, f.nmonths, f.nfinal, f.mean, f.emonth,
           (select count(*)::int from public.perf_reviews o
             where o.team_member_id = t.id and o.status <> 'final'
               and o.period >= v_q and o.period < v_qe) as nopen,
           exists (select 1 from public.perf_breaches b
                    where b.team_member_id = t.id and b.voided_at is null and b.severity = 4
                      and b.period >= v_q and b.period < v_qe) as ml4
      from public.team_members t
      cross join lateral (
        select count(*)::int as nmonths, (count(*) filter (where x.st = 'final'))::int as nfinal,
               round(avg((x.res ->> 'final')::numeric), 2) as mean,
               coalesce(bool_or(x.res ->> 'grade' = 'E'), false) as emonth
          from (select coalesce(r.result, public.perf_calc(r)) as res, r.status as st
                  from public.perf_reviews r
                 where r.team_member_id = t.id and r.status <> 'draft'
                   and r.period >= v_q and r.period < v_qe) x) f
     where f.nmonths > 0 or (t.active and public.perf_reviewed(t.id))
  ), e as (
    select m.*, array_remove(array[
             case when m.nmonths = 0 then 'no-month' end,
             case when m.emonth then 'e-month' end,
             case when m.ml4 then 'critical-breach' end,
             case when not m.mactive then 'inactive' end,
             case when not m.monlist then 'not-reviewed' end], null) as why
      from m
  ), w as (
    select e.*, cardinality(e.why) = 0 as ok,
           coalesce(cardinality(e.why) = 0
                    and e.mean = max(e.mean) filter (where cardinality(e.why) = 0) over (), false) as won
      from e
  ), p as (
    select w.*, count(*) filter (where w.won) over () as nwon,
           case when w.nmonths > 0 then rank() over (order by w.mean desc nulls last) end as mrank
      from w
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'team_member_id', p.mid, 'name', p.mname, 'staff_code', p.mcode, 'department', p.mdept,
           'active', p.mactive, 'reviewed', p.monlist, 'months', p.nmonths, 'finals', p.nfinal, 'open', p.nopen,
           'rank', p.mrank, 'average', p.mean,
           'grade', case when p.nmonths > 0 then public.perf_grade_at(p.mean, v_q) end,
           'e_month', p.emonth, 'l4', p.ml4, 'eligible', p.ok, 'reasons', to_jsonb(p.why),
           'prize', case when p.won then floor(v_ip * 100 / p.nwon) / 100 else 0 end)
         order by p.mean desc nulls last, p.mname), '[]'::jsonb),
         coalesce(max(p.nwon), 0)
    into v_people, v_wins
    from p;
  v_each := case when v_wins > 0 then floor(v_ip * 100 / v_wins) / 100 end;
  v_ind := jsonb_build_object('pool', v_ip, 'winners', v_wins, 'each', v_each,
    'paid', coalesce(v_each * v_wins, 0), 'remainder', v_ip - coalesce(v_each * v_wins, 0),
    'reason', case when v_wins = 0 then 'nobody-eligible' end);

  with d as (
    select k.key as dep, k.name as dname, k.criteria as dnames, s.c1, s.c2, s.c3, s.c4, s.c5, coalesce(s.critical, false) as crit,
           s.c1 + s.c2 + s.c3 + s.c4 + s.c5 as total, s.quarter is not null as entered,
           row_number() over (order by k.position, lower(k.name)) as ord
      from public.departments k
      left join public.perf_dept_scores s on s.quarter = v_q and s.department = k.key
     where k.active and k.in_prize
  ), x as (
    select d.*, bool_and(d.entered) over () as bothin,
           coalesce(d.total = max(d.total) over (), false) as istop
      from d
  ), y as (
    select x.*, (x.bothin and x.istop and x.total >= v_dmin and not x.crit) as won,
           coalesce((select array_agg(t.id order by t.name) from public.team_members t
                      where t.active and t.department = x.dep and public.perf_reviewed(t.id)), '{}'::uuid[]) as mems
      from x
  ), z as (
    select y.*, count(*) filter (where y.won) over () as nwon,
           case when y.won then floor((v_dpool * 100) / count(*) filter (where y.won) over ()) end as sharec
      from y
  )
  select jsonb_agg(jsonb_build_object(
           'department', z.dep, 'name', z.dname, 'names', coalesce(z.dnames, '[]'::jsonb), 'entered', z.entered,
           'criteria', case when z.entered then jsonb_build_array(z.c1, z.c2, z.c3, z.c4, z.c5) end,
           'total', z.total, 'grade', case when z.entered then public.perf_grade_at(z.total, v_q) end,
           'critical', z.crit, 'top', z.bothin and z.istop,
           'qualifies', z.entered and z.total >= v_dmin and not z.crit, 'won', z.won,
           'share', coalesce(z.sharec / 100, 0), 'members', to_jsonb(z.mems))
         order by z.ord),
         coalesce(max(z.nwon), 0), bool_and(z.bothin),
         case when bool_and(z.bothin) and max(z.nwon) = 0 then
           case when bool_or(z.istop and z.total >= v_dmin and z.crit) then 'critical-issue' else 'below-b' end end
    into v_depts, v_dwins, v_both, v_why
    from z;
  v_dp := jsonb_build_object('pool', v_dpool, 'winners', v_dwins,
    'paid', case when v_dwins > 0 then floor((v_dpool * 100) / v_dwins) * v_dwins / 100 else 0 end,
    'remainder', case when v_dwins > 0 then v_dpool - floor((v_dpool * 100) / v_dwins) * v_dwins / 100 else v_dpool end,
    'reason', case when v_depts is null then 'no-departments' when not v_both then 'scores-needed' else v_why end);

  -- a leaver's draft, which can never be released, holds nothing (audit 2026-11-15)
  select count(*)::int into v_open
    from public.perf_reviews r join public.team_members t on t.id = r.team_member_id
   where r.status <> 'final' and r.period >= v_q and r.period < v_qe
     and not (r.status = 'draft' and not t.active);
  select count(*)::int into v_missing
    from public.team_members t
    cross join generate_series(v_q, (v_qe - interval '1 month')::date, interval '1 month') g(mo)
   where t.active and public.perf_reviewed(t.id)
     and (g.mo + interval '1 month')::date <= public.perf_today()
     and date_trunc('month', t.created_at at time zone 'Asia/Kuala_Lumpur')::date <= g.mo::date
     and not exists (select 1 from public.perf_reviews r where r.team_member_id = t.id and r.period = g.mo::date);

  return jsonb_build_object('quarter', v_q, 'word', public.perf_quarter_word(v_q),
    'ended', v_ended, 'provisional', not v_ended or v_open > 0 or v_missing > 0,
    'people', v_people, 'individual', v_ind,
    'departments', coalesce(v_depts, '[]'::jsonb), 'department_prize', v_dp,
    'open_months', v_open, 'missing_months', v_missing,
    'rules', jsonb_build_object('individual', v_ip, 'department', v_dpool, 'min_total', v_dmin,
      'grades', jsonb_build_object('A', public.perf_setting('grade_a', v_q), 'B', public.perf_setting('grade_b', v_q),
                                   'C', public.perf_setting('grade_c', v_q), 'D', public.perf_setting('grade_d', v_q))));
end $$;
revoke all on function public.perf_quarter_calc(date) from public, anon, authenticated;

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

create or replace function public.health_talk_set(p_id uuid, p_status text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; t public.health_talks;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  select * into t from public.health_talks where id = p_id for update;
  if t.id is null or m.id not in (t.team_member_id, t.with_id) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if not ((m.id = t.team_member_id and ((t.status = 'open' and p_status = 'withdrawn')
                                     or (t.status = 'withdrawn' and p_status = 'open')))
       or (m.id = t.with_id and ((t.status = 'open' and p_status = 'done')
                              or (t.status = 'done' and p_status = 'open')))) then
    return jsonb_build_object('error', 'bad-status');
  end if;
  if m.id = t.team_member_id and p_status = 'open' and not public.health_agreed(m.id) then
    return jsonb_build_object('error', 'no-consent');
  end if;
  -- one open talk with a colleague at a time, as asking holds (audit 2026-11-15)
  if m.id = t.team_member_id and p_status = 'open' and exists (
       select 1 from public.health_talks x where x.id <> t.id and x.team_member_id = t.team_member_id
          and x.with_id = t.with_id and x.status = 'open') then
    return jsonb_build_object('error', 'already-asked');
  end if;
  update public.health_talks
     set status = p_status,
         closed_at = case when p_status = 'open' then null else now() end,
         closed_by = case when p_status = 'open' then null else m.id end
   where id = t.id;
  return public.health_mine();
end $$;

create or replace function public.ai_agent_turn(p_press uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members := public.ops_me();
  d public.ai_drafts;
begin
  if m.id is null or not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.ai_drafts x
   where x.id = p_press and x.team_member_id = m.id and x.purpose = 'agent' for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  -- a question that failed takes no further steps uncounted (audit 2026-11-15)
  if d.outcome = 'failed' then return jsonb_build_object('error', 'not-found'); end if;
  if d.created_at < now() - interval '30 minutes' then return jsonb_build_object('error', 'expired'); end if;
  if d.agent_steps >= 12 then return jsonb_build_object('error', 'too-many-steps'); end if;
  update public.ai_drafts x set agent_steps = x.agent_steps + 1 where x.id = d.id;
  return jsonb_build_object('ok', true, 'step', d.agent_steps + 1);
end $$;
revoke all on function public.ai_agent_turn(uuid) from public, anon;
grant execute on function public.ai_agent_turn(uuid) to authenticated;

create or replace function public.ai_agent_tokens(p_press uuid, p_in integer, p_out integer, p_model text)
returns void language sql security definer set search_path = public as $$
  update public.ai_drafts d
     set input_tokens = coalesce(d.input_tokens, 0) + greatest(0, coalesce(p_in, 0)),
         output_tokens = coalesce(d.output_tokens, 0) + greatest(0, coalesce(p_out, 0)),
         model = left(nullif(btrim(coalesce(p_model, '')), ''), 80),
         -- tokens spent are a use counted (audit 2026-11-15)
         outcome = case when d.outcome = 'failed' and coalesce(p_in, 0) > 0 then 'incomplete' else d.outcome end
   where d.id = p_press and d.purpose = 'agent'
     and d.team_member_id = (public.ops_me()).id
$$;
revoke all on function public.ai_agent_tokens(uuid, integer, integer, text) from public, anon;
grant execute on function public.ai_agent_tokens(uuid, integer, integer, text) to authenticated;

create or replace function public.creator_bill_option(p_creator uuid, p_ref text, p_number text)
returns uuid language sql stable security definer set search_path = public as $$
  select o.id from public.campaign_options o
   where o.creator_id = p_creator
     and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
     and exists (select 1 from unnest(array[public.creator_job_ref(o.id), o.earlier_job]) k(v)
                  where length(public.creator_ref_key(k.v)) >= 4
                    -- whole: a key ending in a digit never matches inside a longer
                    -- number (AKJ31 is not AKJ3105; audit 2026-11-15)
                    and (public.creator_ref_key(p_ref) ~ (public.creator_ref_key(k.v) || '(?![0-9])')
                      or public.creator_ref_key(p_number) ~ (public.creator_ref_key(k.v) || '(?![0-9])')))
   order by greatest(length(public.creator_ref_key(public.creator_job_ref(o.id))), length(public.creator_ref_key(coalesce(o.earlier_job, '')))) desc
   limit 1
$$;
revoke all on function public.creator_bill_option(uuid, text, text) from public, anon, authenticated;

create or replace function public.creator_payments_queue(p_paid_from date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_pay  boolean := public.ops_granted('campaigns.pay', 'view');
  v_from date := coalesce(p_paid_from,
    (date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') - interval '1 month')::date);
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'pay', v_pay, 'work', public.ops_granted('campaigns.pay', 'work'),
    'paid_from', v_from,
    'bill_account', case when v_pay then exists (select 1 from public.bukku_settings s where s.id = 1 and s.bill_account is not null) end,
    'read_at', (select max(b.read_at) from public.creator_bills b),
    -- Payment details waiting for review, oldest first.
    'review', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'creator', cr.id, 'name', cr.name, 'code', cr.creator_code, 'ref', r.ref,
        'currency', r.currency, 'method_word', public.creator_pay_method(r.method, r.bank),
        'account_end', right(r.account, 4), 'created_at', r.created_at,
        'replaces', exists (select 1 from public.creator_pay_requests y where y.creator_id = r.creator_id and y.status = 'approved'))
        order by r.created_at)
        from public.creator_pay_requests r join public.creators cr on cr.id = r.creator_id
       where r.status = 'pending'), '[]'::jsonb),
    -- Every booking posted in the portal, or holding a live bill.
    'jobs', coalesce((select jsonb_agg(x.j order by x.k) from (
      select jsonb_build_object(
          'option', o.id, 'creator', cr.id, 'name', cr.name, 'code', cr.creator_code,
          'linked', exists (select 1 from public.bukku_links l where l.kind = 'creator' and l.record_id = cr.id and l.contact_id is not null),
          'job', public.creator_job_ref(o.id), 'state', o.state, 'campaign', case when public.client_seen(c.id, 'view') then m.title end, 'campaign_id', m.id,
          'client', case when public.client_seen(c.id, 'view') then c.name end,
          'client_code', case when public.client_seen(c.id, 'view') then c.client_code end,
          'posted_on', o.posted_on, 'pay_by', o.pay_by,
          'currency', coalesce(f.currency, (select p.currency from public.creator_pay_requests p
                                             where p.creator_id = cr.id and p.status = 'approved' order by p.seq desc limit 1), 'MYR'),
          'fee', case when v_pay and f.option_id is not null then jsonb_build_object('amount', f.amount, 'currency', f.currency) end,
          'bill', case when b.bill_id is not null then jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                    'paid_on', coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date),
                    'amount', case when v_pay then b.amount end, 'currency', b.currency) end) as j,
          coalesce(o.pay_by, o.posted_on) as k
        from public.campaign_options o
        join public.creators cr on cr.id = o.creator_id
        join public.campaigns m on m.id = o.campaign_id
        join public.clients c on c.id = m.client_id
        left join public.creator_fees f on f.option_id = o.id
        left join lateral (select y.* from public.creator_bills y where y.option_id = o.id and not y.gone
                            order by (y.status = 'processing') desc, (y.status = 'draft') desc, y.bill_date desc nulls last limit 1) b on true
       where o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
         and ((b.bill_id is null and o.posted_on is not null and o.state in ('posted', 'completed'))
           or b.status in ('draft', 'processing')
           or (b.status = 'paid' and coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date, b.bill_date) >= v_from))
      ) x), '[]'::jsonb));
end $$;
revoke all on function public.creator_payments_queue(date) from public, anon;
grant execute on function public.creator_payments_queue(date) to authenticated;

create or replace function public.team_member_remove_check(p_member uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  v_m public.team_members;
begin
  if me.id is null or not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_m from public.team_members x where x.id = p_member;
  if v_m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_m.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if coalesce(v_m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and not public.allowed('admin') then
    return jsonb_build_object('error', 'admin-only');
  end if;
  -- the super admin's alone while one is active, as the removal itself holds,
  -- so no work moves before a removal that is refused (audit 2026-11-15)
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and not public.team_super_ok() then
    return jsonb_build_object('error', 'super-only');
  end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and v_m.active
     and not exists (select 1 from public.team_members x where x.id <> v_m.id and x.active
                       and (coalesce(x.is_admin, false) or x.role = 'admin')) then
    return jsonb_build_object('error', 'last-admin');
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_member_remove_check(uuid) from public, anon;
grant execute on function public.team_member_remove_check(uuid) to authenticated;

-- END OF AUDIT FIXES, SECOND BATCH -------------------------------------------

select public.functions_tidy();
