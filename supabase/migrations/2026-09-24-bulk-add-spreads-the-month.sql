-- ===========================================================================
-- BULK ADD SPREADS THE MONTH — a month of tasks is shared across its four
-- weeks, not piled into the last one.
-- 2026-09-24. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   `ops_generate_month` with no week counts gave weeks 1 to 3 the whole
--   quarter of the count and week 4 everything left over, so six tasks came
--   out 1, 1, 1, 3 and one, two or three tasks all landed in week 4 (the
--   user, 2026-09-24: "it should proceed to divide every 30 days ... not just
--   keep all at the last week"). Task i, counted from 0, now falls in week
--   floor(i * 4 / n) + 1: eight is two a week, six is 2, 1, 2, 1, five is
--   2, 1, 1, 1, two is weeks 1 and 3. The running number still runs 01 to n
--   across the month.
--
--   The tentative publish date moves with it: each task sits inside its own
--   week, the week's tasks spread over its seven days, where every task in a
--   week used to share that week's first day.
--
--   Week counts typed on the sheet (Set how many in each week) are used as
--   typed, as before. Tasks already made keep their codes: a code is written
--   once and never rewritten.
--
-- ROLLBACK
--   Re-run section 9.12 of 2026-09-23-operations-phase4.sql.
-- ===========================================================================

-- 1. A month of content at once, spread over the month ------------------------
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
  if not p_dry_run then
    eng := coalesce((p_payload ->> 'engagement_id')::uuid,
                    (select e.id from public.ops_engagements e where e.client_id = cid and e.period = per));
    if eng is null then
      eng := (public.ops_engagement_upsert(jsonb_build_object(
                'client_id', cid, 'period', per, 'planned_count', n,
                'manager_id', coalesce((p_payload ->> 'manager_id')::uuid, m.id))) ->> 'id')::uuid;
    else
      update public.ops_engagements set planned_count = greatest(planned_count, n), updated_at = now()
       where id = eng and planned_count < n;
    end if;
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
      publish := (first_day + least((w - 1) * 7 + ((k - 1) * 7) / weeks[w], last_off))::timestamptz;
      if p_dry_run then
        made := made || jsonb_build_object('code', public.ops_code_of(per, w, seq), 'week', w, 'seq', seq);
      else
        key := case when p_idem is null then null else 'month:' || p_idem || ':' || seqs::text end;
        one := public.ops_create_task(jsonb_build_object(
          'scope', scope, 'client_id', cid, 'engagement_id', eng,
          'task_type', coalesce(p_payload ->> 'task_type', 'engagement'),
          'deliverable_type', p_payload ->> 'deliverable_type',
          'priority_level', (p_payload ->> 'priority_level')::integer,
          'complexity', p_payload ->> 'complexity',
          'owner_id', (p_payload ->> 'owner_id')::uuid,
          'manager_id', (p_payload ->> 'manager_id')::uuid,
          'code_period', per, 'code_week', w,
          'publish_at', publish), key);
        if one ? 'error' then return one; end if;
        made := made || jsonb_build_object('id', one ->> 'id', 'code', one ->> 'code', 'week', w, 'seq', seq);
      end if;
    end loop;
  end loop;
  return jsonb_build_object('engagement_id', eng, 'period', per, 'count', seqs,
                            'tasks', made, 'dry_run', p_dry_run);
end $$;
grant execute on function public.ops_generate_month(jsonb, boolean, text) to authenticated;

-- END OF BULK ADD SPREADS THE MONTH ------------------------------------------
