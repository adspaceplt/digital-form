-- ===========================================================================
-- NEW MONTH NEVER REPLACES ONE — New month refuses a month the client already
-- holds rather than writing over it. 2026-10-22. Safe to run twice. Rollback
-- at the foot. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/ops.js compares the two.
--
-- WHY (the review of 2026-10-22, WRK-1, P1): New month opened on this month
-- with its fields empty; saved on a month the client held, the function
-- edited that month, so its posts planned became 0, its Reports ticks none
-- and its Drive link empty, and its open report task was cancelled.
--
-- WHAT IT CHANGES
--   * ops_engagement_upsert: a payload carrying `new: true` (New month) on a
--     client and month already held answers `exists` with the period and
--     writes nothing, also where another colleague made it a moment before.
--     A payload without it (Edit, a task joining its month) is as before.
--
-- ORDER: this file, then the pages (an old page sends no `new` and is
-- answered as before). ROLLBACK: MONTH REPORTS' ops_engagement_upsert.
-- ===========================================================================

create or replace function public.ops_engagement_upsert(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  cid uuid;
  per text;
  eid uuid;
  k text;
  fresh boolean := false;
  prev public.ops_engagements;
  v_day integer;
  v_reports text[];
  v_was_day integer;
  v_new boolean := coalesce((p_payload ->> 'new')::boolean, false);
begin
  p_payload := p_payload - 'new';
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  if cid is null or not exists (select 1 from public.clients where id = cid) then
    return jsonb_build_object('error', 'client-required');
  end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  if p_payload ? 'start_day' and (nullif(p_payload ->> 'start_day', '') is null
     or (p_payload ->> 'start_day') !~ '^\d{1,2}$' or (p_payload ->> 'start_day')::integer not between 1 and 28) then
    return jsonb_build_object('error', 'bad-start-day');
  end if;
  if p_payload ? 'reports' then
    if jsonb_typeof(p_payload -> 'reports') <> 'array' then return jsonb_build_object('error', 'bad-reports'); end if;
    select coalesce(array_agg(distinct x), '{}') into v_reports from jsonb_array_elements_text(p_payload -> 'reports') x;
    if not (v_reports <@ array['social', 'ads']::text[]) then return jsonb_build_object('error', 'bad-reports'); end if;
  end if;

  select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
  /* New month never edits a month the client holds (2026-10-22, WRK-1). */
  if eid is not null and v_new then return jsonb_build_object('error', 'exists', 'period', per); end if;
  if eid is null then
    select * into prev from public.ops_engagements o
     where o.client_id = cid and o.period < per order by o.period desc limit 1;
    v_day := coalesce((p_payload ->> 'start_day')::integer, prev.start_day, 1);
    v_reports := coalesce(v_reports, prev.reports, '{}');
    insert into public.ops_engagements (client_id, period, manager_id, planned_count, drive_url, created_by,
                                        reports, start_day)
    values (cid, per, coalesce((p_payload ->> 'manager_id')::uuid, m.id),
            coalesce((p_payload ->> 'planned_count')::integer, 0),
            nullif(p_payload ->> 'drive_url', ''), m.id, v_reports, v_day)
    on conflict (client_id, period) do nothing
    returning id into eid;
    /* Somebody else made it between the read and the write: theirs stands. */
    if eid is null then
      if v_new then return jsonb_build_object('error', 'exists', 'period', per); end if;
      select e.id into eid from public.ops_engagements e where e.client_id = cid and e.period = per;
    else
      fresh := true;
    end if;
  end if;
  if fresh then
    if not exists (select 1 from public.ops_engagements o where o.client_id = cid and o.id <> eid) then
    foreach k in array array['onboarding', 'pre_ads'] loop
      insert into public.ops_engagement_checks (engagement_id, key) values (eid, k)
      on conflict do nothing;
    end loop;
    end if;
    perform public.ops_engagement_log(eid, 'created', p_payload - 'client_id');
  else
    if not public.ops_may_see_engagement(eid) then return jsonb_build_object('error', 'denied'); end if;
    /* Asked for with nothing to change, the month is answered as it stands:
       a task made for a month joins it without editing it. */
    if (p_payload - 'client_id' - 'period') = '{}'::jsonb then
      return public.ops_engagement_json(eid) || jsonb_build_object('created', false);
    end if;
    select o.start_day into v_was_day from public.ops_engagements o where o.id = eid;
    update public.ops_engagements set
      manager_id = coalesce((p_payload ->> 'manager_id')::uuid, manager_id),
      planned_count = coalesce((p_payload ->> 'planned_count')::integer, planned_count),
      drive_url = case when p_payload ? 'drive_url' then nullif(p_payload ->> 'drive_url', '') else drive_url end,
      reports = coalesce(v_reports, reports),
      start_day = coalesce((p_payload ->> 'start_day')::integer, start_day),
      updated_at = now(), version = version + 1
    where id = eid;
    perform public.ops_engagement_log(eid, 'edited', p_payload - 'client_id' - 'period');
  end if;
  perform public.ops_engagement_sync_reports(eid,
    v_was_day is not null and v_was_day is distinct from (select o.start_day from public.ops_engagements o where o.id = eid));
  return public.ops_engagement_json(eid) || jsonb_build_object('created', fresh);
end $$;
grant execute on function public.ops_engagement_upsert(jsonb) to authenticated;

-- END OF NEW MONTH NEVER REPLACES ONE ----------------------------------------
select public.functions_tidy();
