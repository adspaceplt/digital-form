-- ===========================================================================
-- A FORMAT PER TASK — Bulk add gives each task in the month its own
-- deliverable format, so a month can be mixed.
-- 2026-09-25. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   `ops_generate_month` takes an optional `formats` array in its payload,
--   one entry per task in the order the tasks are made (week 1's first, then
--   on), so a month of eight can be three Reels and five graphics (the user,
--   2026-09-25: "if 8 contents, not all 8 are same deliverables"). An array
--   whose length is not the count is refused with `formats-do-not-match`; a
--   blank entry takes the run's `deliverable_type` as before. The preview
--   answers each code with its format. The month rules, the spread over weeks,
--   the codes and the publish dates are unchanged.
--
-- ROLLBACK
--   Re-run section 1 of 2026-09-25-bulk-add-from-the-month.sql.
-- ===========================================================================

create or replace function public.ops_generate_month(
  p_payload jsonb, p_dry_run boolean default false, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  cid    uuid;
  per    text;
  n      integer;
  weeks  integer[];
  bad    text;
  eng    uuid;
  e      public.ops_engagements;
  k      integer;
  w      integer;
  seq    integer;
  seqs   integer;
  made   jsonb := '[]'::jsonb;
  one    jsonb;
  key    text;
  scope  text;
  first_day date;
  last_off integer;
  publish timestamptz;
  fmts   text[];
  fmt    text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  cid := (p_payload ->> 'client_id')::uuid;
  per := p_payload ->> 'period';
  n := coalesce((p_payload ->> 'count')::integer, 0);
  scope := coalesce(p_payload ->> 'scope', 'client');
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;
  if per is null or per !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  if n < 1 or n > 60 then return jsonb_build_object('error', 'bad-count'); end if;

  if (p_payload -> 'weeks') is not null and jsonb_typeof(p_payload -> 'weeks') = 'array' then
    select array_agg(x::integer) into weeks from jsonb_array_elements_text(p_payload -> 'weeks') x;
    if array_length(weeks, 1) < 1 or array_length(weeks, 1) > 5 then
      return jsonb_build_object('error', 'bad-weeks');
    end if;
    if (select sum(v) from unnest(weeks) v) <> n then return jsonb_build_object('error', 'weeks-do-not-add-up'); end if;
  else
    /* Evenly over four weeks, the extras early: task i (from 0) falls in
       week floor(i * 4 / n) + 1, so eight is two a week, six is 2, 1, 2, 1,
       and two is weeks 1 and 3 rather than both in week 4. */
    weeks := array[]::integer[];
    for w in 1 .. 4 loop
      weeks := weeks || (ceil(w * n / 4.0)::integer - ceil((w - 1) * n / 4.0)::integer);
    end loop;
  end if;

  /* A format for each task, in the order the tasks are made (week by week,
     then by number), because a month is usually mixed: three Reels and five
     graphics, not eight of one. A task given no format of its own takes the
     one for the run. */
  if (p_payload -> 'formats') is not null and jsonb_typeof(p_payload -> 'formats') = 'array' then
    select array_agg(nullif(btrim(x), '') order by i) into fmts
      from jsonb_array_elements_text(p_payload -> 'formats') with ordinality as a(x, i);
    if coalesce(array_length(fmts, 1), 0) <> n then return jsonb_build_object('error', 'formats-do-not-match'); end if;
  end if;

  /* The same press twice is one month, not two. */
  if not p_dry_run and p_idem is not null then
    if exists (select 1 from public.ops_tasks where idem_key = 'month:' || p_idem || ':1') then
      return jsonb_build_object('error', 'already-generated');
    end if;
  end if;

  first_day := (per || '-01')::date;
  last_off := ((first_day + interval '1 month')::date - first_day) - 1;
  /* One lock for the whole run, taken before anything is read: two operators
     generating the same month queue here, so the second sees the first's
     engagement and the first's numbers rather than racing both. */
  perform pg_advisory_xact_lock(hashtext('ops_code:' || cid::text || ':' || per));
  /* The month must already exist on the client's Work pane, still be open,
     and have its content meeting confirmed: a month nobody planned holds no
     tasks. Asked on the preview as well as the run, so the sheet cannot
     show codes for a month the run would refuse. */
  select * into e from public.ops_engagements
   where client_id = cid and period = per;
  if e.id is null then return jsonb_build_object('error', 'no-month'); end if;
  if (p_payload ->> 'engagement_id') is not null and (p_payload ->> 'engagement_id')::uuid <> e.id then
    return jsonb_build_object('error', 'no-month');
  end if;
  if e.status in ('completed', 'cancelled') then return jsonb_build_object('error', 'month-closed'); end if;
  if e.meeting_at is null and not e.meeting_na then
    return jsonb_build_object('error', 'month-not-confirmed');
  end if;
  eng := e.id;
  if not p_dry_run then
    update public.ops_engagements set planned_count = greatest(planned_count, n), updated_at = now()
     where id = eng and planned_count < n;
  end if;

  /* One lock for the whole month, so the preview and the run see the same
     next number and two operators generating for one client queue. */
  seq := public.ops_next_seq(cid, per) - 1;
  seqs := 0;
  for w in 1 .. array_length(weeks, 1) loop
    for k in 1 .. coalesce(weeks[w], 0) loop
      seq := seq + 1;
      seqs := seqs + 1;
      /* A tentative date inside the task's own week, the week's tasks
         spread across its seven days, so the calendar has somewhere to put
         each one; the content meeting fixes the real date. Never past the
         month's last day, which only a fifth week can reach. */
      fmt := coalesce(fmts[seqs], nullif(p_payload ->> 'deliverable_type', ''));
      publish := (first_day + least((w - 1) * 7 + ((k - 1) * 7) / weeks[w], last_off))::timestamptz;
      if p_dry_run then
        made := made || jsonb_build_object('code', public.ops_code_of(per, w, seq), 'week', w, 'seq', seq, 'format', fmt);
      else
        key := case when p_idem is null then null else 'month:' || p_idem || ':' || seqs::text end;
        one := public.ops_create_task(jsonb_build_object(
          'scope', scope, 'client_id', cid, 'engagement_id', eng,
          'task_type', coalesce(p_payload ->> 'task_type', 'engagement'),
          'deliverable_type', fmt,
          'priority_level', (p_payload ->> 'priority_level')::integer,
          'complexity', p_payload ->> 'complexity',
          'owner_id', (p_payload ->> 'owner_id')::uuid,
          'manager_id', (p_payload ->> 'manager_id')::uuid,
          'code_period', per, 'code_week', w,
          'publish_at', publish), key);
        if one ? 'error' then return one; end if;
        made := made || jsonb_build_object('id', one ->> 'id', 'code', one ->> 'code', 'week', w, 'seq', seq, 'format', fmt);
      end if;
    end loop;
  end loop;
  return jsonb_build_object('engagement_id', eng, 'period', per, 'count', seqs,
                            'tasks', made, 'dry_run', p_dry_run);
end $$;
grant execute on function public.ops_generate_month(jsonb, boolean, text) to authenticated;

-- END OF A FORMAT PER TASK ------------------------------------------------
