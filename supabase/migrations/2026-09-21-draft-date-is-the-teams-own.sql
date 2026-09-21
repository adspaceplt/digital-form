-- =============================================================================
-- THE FIRST DRAFT DATE IS THE TEAM'S OWN, AND IT LANDS BEFORE THE COMMITMENT
-- 2026-09-21
--
-- Three rules the user gave on 2026-09-21, and one open item they settle.
--
--   1. The FIRST DRAFT date is the team's own internal milestone, set against
--      a schedule that is already agreed, so it is freely adjustable by
--      anybody who may work the task. It goes through no approval round.
--
--   2. The FINAL date is the commitment a client is owed. It keeps the
--      approval round shipped on 2026-09-20: the person doing the work asks,
--      the person who created the task decides, and `ops_decide_due_change`
--      is the only path to the moved date.
--
--   3. A first draft date on or after the final date is a plan that cannot
--      work. The latest a draft may fall is the calendar day before the final
--      date, and the database refuses anything later whichever end of the
--      pair is being moved.
--
-- Rule 1 closes an item this repository has carried as open since 2026-09-20.
-- `CLAUDE.md` and `STANDARD.md` both record that the first draft date "was
-- meant not to be gated" while the shipped `ops_due_decider` answered with the
-- task's creator whatever the kind, so both dates went through the round.
-- `tests/ops.js` asserted the shipped behaviour and flagged the difference
-- rather than choosing. The user has now chosen: the intent moves into the
-- code, not the other way round.
--
-- WHAT IS DELIBERATELY NOT DONE HERE. The user wrote that the final due date
-- "cannot be changed". Read strictly that retires the approval round entirely,
-- one day after they designed it ("A creates the task and assigns it to B;
-- B's change goes to A"). This file takes the reading that keeps both
-- statements true: the final date cannot be changed *by the person doing the
-- work*, which is what the round already enforces, and the page stops offering
-- it as something to move. Making it immovable outright is a second change and
-- is the user's to call.
--
-- `ops_decide_due_change` is deliberately untouched. It already calls
-- `ops_change_due_date` and already puts its decision back when that call
-- refuses, so the new guard reaches the approval path without an edit.
--
-- SAFE TO RUN TWICE. Every statement is `create or replace` and the one drop
-- is `if exists`. No table, column, policy or permission changes.
--
-- ROLLBACK is at the foot of this file.
-- =============================================================================

-- 1. The order of the pair, stated once ---------------------------------------
-- Calendar days, not an interval: a person reads "the day before", and
-- comparing timestamps would refuse a draft set for the morning of the day
-- before a midnight final, which is a plan that works perfectly well.
create or replace function public.ops_due_order_ok(
  p_draft timestamptz, p_final timestamptz)
returns boolean
language sql immutable set search_path = public as $$
  select p_draft is null
      or p_final is null
      or p_draft::date <= (p_final::date - 1)
$$;
grant execute on function public.ops_due_order_ok(timestamptz, timestamptz) to authenticated;

-- 2. Who decides, per kind ----------------------------------------------------
-- The one-argument form is dropped rather than left beside this one: PostgREST
-- resolves a call by its argument list, and two candidates for one name is how
-- `issue_letter` came to have two signatures for one call. Nothing outside this
-- schema calls it, so there is nothing to keep compatible.
drop function if exists public.ops_due_decider(uuid);
create or replace function public.ops_due_decider(p_task uuid, p_kind text)
returns uuid
language sql security definer stable set search_path = public as $$
  -- No decider for the team's own milestone: the caller moves it themselves.
  select case when p_kind = 'first_draft' then null
              else (select t.created_by from public.ops_tasks t where t.id = p_task)
         end
$$;
grant execute on function public.ops_due_decider(uuid, text) to authenticated;

-- 3. The move itself refuses an impossible pair -------------------------------
create or replace function public.ops_change_due_date(
  p_task uuid, p_kind text, p_value timestamptz, p_reason text,
  p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  was timestamptz;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if p_kind not in ('first_draft', 'final') then return jsonb_build_object('error', 'bad-kind'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  /* The pair as it would stand after this move, whichever end moved. Checked
     here and not only on the asking path, because `ops_decide_due_change`
     reaches this function directly once an extension is approved: a gate that
     lives only where the ask is raised is one an approval walks straight
     past. */
  if not public.ops_due_order_ok(
       case when p_kind = 'first_draft' then p_value else t.current_first_draft_due_at end,
       case when p_kind = 'final'       then p_value else t.current_final_due_at end) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  was := case when p_kind = 'final' then t.current_final_due_at
              else t.current_first_draft_due_at end;

  /* The original is written once, when the task is created, and never here.
     A report that can only measure the latest replan cannot see replanning. */
  update public.ops_tasks set
    current_final_due_at = case when p_kind = 'final' then p_value else current_final_due_at end,
    current_first_draft_due_at = case when p_kind = 'first_draft' then p_value else current_first_draft_due_at end,
    version = version + 1, updated_at = now()
  where id = p_task;

  perform public.ops_log(p_task, 'due_changed',
    jsonb_build_object('kind', p_kind, 'value', was),
    jsonb_build_object('kind', p_kind, 'value', p_value),
    jsonb_build_object('reason', p_reason, 'note', p_note));
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_change_due_date(uuid, text, timestamptz, text, text, integer) to authenticated;

-- 4. Asking routes the two kinds differently ----------------------------------
-- The page still makes one call and the database still decides what it is.
-- What changed is the answer for `first_draft`: there is no decider, so it
-- falls through to the move exactly as a creator's own task always did.
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
  if who is null or who = m.id then
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

-- =============================================================================
-- ROLLBACK
--
--   drop function if exists public.ops_due_decider(uuid, text);
--   create or replace function public.ops_due_decider(p_task uuid)
--   returns uuid language sql security definer stable set search_path = public as $$
--     select t.created_by from public.ops_tasks t where t.id = p_task
--   $$;
--   grant execute on function public.ops_due_decider(uuid) to authenticated;
--   drop function if exists public.ops_due_order_ok(timestamptz, timestamptz);
--
-- then re-apply `ops_change_due_date` from section 6.3 of
-- `supabase/schema.sql` and `ops_request_due_change` from
-- `2026-09-20-extension-approval.sql`, which carry the bodies this file
-- replaced.
-- =============================================================================
