-- ===========================================================================
-- BULK ADD FROM THE MONTH — Bulk add takes tasks only into a content month
-- the client already has, with its meeting confirmed; an admin moves a due
-- date without the approval round.
-- 2026-09-25. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the two.
--
-- WHAT THIS CHANGES, AND WHAT IT LEAVES ALONE.
--
--   1. `ops_generate_month` made the client's month when there was none, so
--      Bulk add could fill a month nobody had planned (the user, 2026-09-25:
--      "if under client -> work is not created for the month, then it
--      shouldnt have tasks within it"). It now refuses, on the preview and on
--      the run alike: `no-month` where the client has no month for that
--      period, `month-closed` where the month is completed or cancelled, and
--      `month-not-confirmed` where its content meeting is neither set nor
--      marked not applicable. The spread over weeks, the codes and the
--      publish dates are unchanged.
--
--   2. `ops_request_due_change` sends an admin's move straight through, as it
--      already did for the person who created the task (the user: "admin
--      should have the full access to overwrite everything"). The move still
--      goes through `ops_change_due_date`, so the original commitment is kept
--      and the event is filed. Everybody else still asks the creator.
--
-- ROLLBACK
--   Re-run 2026-09-24-bulk-add-spreads-the-month.sql and section 4 of
--   2026-09-21-draft-date-is-the-teams-own.sql.
-- ===========================================================================

-- 1. A month of content, only into a month the client has ---------------------
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

-- 2. Asking to move a date; an admin moves it --------------------------------
create or replace function public.ops_request_due_change(
  p_task uuid, p_kind text, p_value timestamptz, p_reason text,
  p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  t     public.ops_tasks;
  who   uuid;
  was   timestamptz;
  v_id  uuid;
  nm    text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if p_kind not in ('first_draft', 'final') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_value is null then return jsonb_build_object('error', 'no-date'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  /* Refused before an ask is raised as well as before a move is made: an ask
     nobody could approve without breaking the plan is one to turn away at the
     door, with the word the move itself would have used. */
  if not public.ops_due_order_ok(
       case when p_kind = 'first_draft' then p_value else t.current_first_draft_due_at end,
       case when p_kind = 'final'       then p_value else t.current_final_due_at end) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  who := public.ops_due_decider(p_task, p_kind);
  /* Nobody to ask — the team's own first draft milestone, or a task whose
     creator is the person asking — so the move is theirs to make and the
     round would be a form with one name on both ends. */
  /* An admin moves any date directly: the round protects the person who set
     the date from somebody else, and an admin is the one who may overwrite
     anybody's. The move still files its event and keeps the original. */
  if who is null or who = m.id or public.allowed('admin') then
    return public.ops_change_due_date(p_task, p_kind, p_value, p_reason, p_note, p_version);
  end if;

  was := case when p_kind = 'final' then t.current_final_due_at
              else t.current_first_draft_due_at end;

  insert into public.ops_due_requests
    (task_id, kind, was_at, wants_at, reason, note, asked_by, decider_id)
  values (p_task, p_kind, was, p_value, p_reason, nullif(btrim(p_note), ''), m.id, who)
  on conflict (task_id, kind) where state = 'asked' do nothing
  returning id into v_id;

  /* The same press twice is the same ask. The open one is handed back so the
     page can say it is already with somebody. */
  if v_id is null then
    select id into v_id from public.ops_due_requests
      where task_id = p_task and kind = p_kind and state = 'asked';
    return jsonb_build_object('ok', true, 'repeat', true, 'request', v_id,
                              'task', public.ops_task_json(p_task));
  end if;

  select name into nm from public.team_members where id = m.id;
  perform public.ops_notify(who, p_task, 'due_requested',
    'Extension requested',
    coalesce(nm, 'Somebody') || ' asked to move ' ||
      case when p_kind = 'final' then 'the due date' else 'the first draft date' end ||
      ' to ' || to_char(timezone('Asia/Kuala_Lumpur', p_value), 'DD Mon YYYY'),
    'due_req:' || v_id::text);

  perform public.ops_log(p_task, 'due_requested',
    jsonb_build_object('kind', p_kind, 'value', was),
    jsonb_build_object('kind', p_kind, 'value', p_value),
    jsonb_build_object('reason', p_reason, 'note', p_note, 'request', v_id));

  return jsonb_build_object('ok', true, 'request', v_id, 'asked', true,
                            'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_request_due_change(uuid, text, timestamptz, text, text, integer) to authenticated;

-- END OF BULK ADD FROM THE MONTH -------------------------------------------
