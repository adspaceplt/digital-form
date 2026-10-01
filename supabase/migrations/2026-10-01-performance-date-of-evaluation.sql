-- ===========================================================================
-- DATE OF EVALUATION — each month's review records the day its numbers were
-- reported to the team member, and the member has 7 days from release to
-- dispute.
-- 2026-10-01. Safe to run twice. Run after
-- 2026-09-28-performance-release-notify.sql. Rollback at the foot of this
-- header. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/perf.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-01)
--   1. `perf_reviews.evaluated_on` (date): the day the report and its
--      numbers were reported to the team member. Release fills it with the
--      day of release (Malaysia) where it is empty; management may correct
--      it until the record is final.
--   2. perf_save takes `evaluated_on` in its payload: on or after the first
--      day of the month reviewed and never after today in Malaysia
--      (`bad-eval-date`); an empty value clears it. A change is filed from
--      and to.
--   3. perf_release gives the member 7 days to dispute (was 3). A month
--      released before keeps the window it was given.
--   4. perf_json sends `evaluated_on`, so the review, the member's own page
--      and the printed record read it beside the last day to dispute.
--
-- ROLLBACK
--   Run the PERFORMANCE RECORDS, THEIR TRAIL AND THEIR CHECK section of
--   supabase/schema.sql again for perf_save, the DEPARTMENT AND ROLE ON THE
--   TEAM section for perf_json and the RELEASE WITH OR WITHOUT TELLING
--   section for perf_release, then:
--   alter table public.perf_reviews drop column if exists evaluated_on;
-- ===========================================================================

alter table public.perf_reviews add column if not exists evaluated_on date;

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
    'acknowledged_at', r.acknowledged_at, 'finalised_at', r.finalised_at,
    'finalised_by', (select name from public.team_members where id = r.finalised_by),
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
          from public.perf_events e where e.review_id = r.id), '[]'::jsonb));
  end if;
  return out;
end $$;

create or replace function public.perf_save(p_token text, p_member uuid, p_period date,
                                            p_payload jsonb, p_rev integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; r public.perf_reviews; p date := date_trunc('month', p_period)::date;
  sc jsonb := coalesce(p_payload -> 'scores', '{}'::jsonb);
  rt jsonb := coalesce(p_payload -> 'rates', '{}'::jsonb);
  k text; v jsonb; mx numeric; rb date; ev date; was public.perf_reviews; changed jsonb;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if not exists (select 1 from public.team_members where id = p_member and active) then
    return jsonb_build_object('error', 'not-found');
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
         dispute_until = now() + interval '7 days', reviewer_id = m.id,
         evaluated_on = coalesce(evaluated_on, (now() at time zone 'Asia/Kuala_Lumpur')::date),
         serial = coalesce(serial, 'ADHR/' || upper(btrim(tm.staff_code)) || '/PR' || to_char(period, 'YYMM')),
         rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'released',
    jsonb_build_object('version', r.version, 'notified', coalesce(p_notify, true)));
  if coalesce(p_notify, true) then
    perform public.perf_notify(r.team_member_id, 'perf.released',
      'Your ' || public.perf_month_word(r.period) || ' performance review is ready.',
      'perf.released.' || r.id || '.' || r.version);
  end if;
  return public.perf_json(r, true);
end $$;

revoke all on function public.perf_json(public.perf_reviews, boolean) from public, anon, authenticated;
revoke all on function public.perf_save(text, uuid, date, jsonb, integer) from public, anon, authenticated;
revoke all on function public.perf_release(text, uuid, integer, boolean) from public, anon, authenticated;
grant execute on function public.perf_save(text, uuid, date, jsonb, integer) to authenticated;
grant execute on function public.perf_release(text, uuid, integer, boolean) to authenticated;

-- END OF DATE OF EVALUATION --------------------------------------------------
