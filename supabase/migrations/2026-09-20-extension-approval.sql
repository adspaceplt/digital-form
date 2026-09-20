-- ==========================================================================
-- AN EXTENSION IS ASKED FOR, NOT TAKEN
-- 2026-09-20. Safe to run twice. Rollback at the foot.
--
-- `ops_change_due_date` moved a commitment the moment somebody pressed it, so
-- the person who created the task and put the date on it found out afterwards,
-- from a notification, about a deadline that had already moved. The user asked
-- for the round that was missing: A creates the task and assigns it to B; B
-- asking to move the date raises a request back to A, and the date moves when
-- A approves it and not before.
--
-- WHAT IS DELIBERATELY NOT CHANGED
--   * A person moving a date on a task THEY created still moves it at once.
--     An approval round with one name on both ends is a form, not a control.
--   * The first draft date is not gated. It is the team's own internal
--     milestone; the commitment a client is owed is the final due date, and
--     that is the one an extension is about.
--   * `ops_change_due_date` keeps its signature and its behaviour, so every
--     existing caller, the original-commitment rule and the event it files
--     are untouched. The approval path calls it once A has said yes.
--
-- The request carries the reason category the date sheet already asks for, so
-- nothing new is asked of the person raising it.
-- ==========================================================================

create table if not exists public.ops_due_requests (
  id            uuid primary key default gen_random_uuid(),
  task_id       uuid not null references public.ops_tasks(id) on delete cascade,
  kind          text not null check (kind in ('first_draft', 'final')),
  -- What the date is now, kept so the decision can be read long afterwards
  -- without replaying the task's events.
  was_at        timestamptz,
  wants_at      timestamptz not null,
  reason        text not null,
  note          text,
  asked_by      uuid not null references public.team_members(id),
  asked_at      timestamptz not null default now(),
  -- Who it went to. Stored rather than derived, because a task's creator can
  -- be stood down and the request still has to say who was asked.
  decider_id    uuid references public.team_members(id),
  state         text not null default 'asked' check (state in ('asked', 'approved', 'declined', 'withdrawn')),
  decided_by    uuid references public.team_members(id),
  decided_at    timestamptz,
  decide_note   text
);
create index if not exists ops_due_requests_task_idx on public.ops_due_requests(task_id);
create index if not exists ops_due_requests_decider_idx on public.ops_due_requests(decider_id) where state = 'asked';
/* One open request a task and a kind: a second press is the same ask, and two
   open requests over one date is a question with two answers. */
create unique index if not exists ops_due_requests_open_uidx
  on public.ops_due_requests(task_id, kind) where state = 'asked';

alter table public.ops_due_requests enable row level security;
drop policy if exists ops_due_requests_read on public.ops_due_requests;
/* Read only, like every other ops table: the two writes below are functions,
   so a browser cannot approve its own extension whatever it sends. Visible to
   whoever may already see the task. */
create policy ops_due_requests_read on public.ops_due_requests
  for select to authenticated using (public.ops_may_see_task(task_id));

-- Who an extension on this task is asked of: the person who created it.
create or replace function public.ops_due_decider(p_task uuid)
returns uuid
language sql security definer stable set search_path = public as $$
  select t.created_by from public.ops_tasks t where t.id = p_task
$$;
grant execute on function public.ops_due_decider(uuid) to authenticated;

-- 1. Asking.
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

  who := public.ops_due_decider(p_task);
  /* Nobody to ask, or the asker is the person who would be asked: the move is
     theirs to make and the round would be a form with one name on both ends. */
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

-- 2. Deciding. The date moves here and nowhere else on this path.
create or replace function public.ops_decide_due_change(
  p_request uuid, p_approve boolean, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  r   public.ops_due_requests;
  out jsonb;
  nm  text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;

  select * into r from public.ops_due_requests where id = p_request for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.state <> 'asked' then return jsonb_build_object('error', 'decided'); end if;

  /* The person it was asked of decides it. An ops Manage may also, because
     somebody has to when the creator has left; nobody else, and never the
     person who asked. */
  if m.id <> coalesce(r.decider_id, '00000000-0000-0000-0000-000000000000'::uuid)
     and not public.allowed('ops', 'manage') then
    return jsonb_build_object('error', 'not-yours');
  end if;
  if m.id = r.asked_by and m.id <> r.decider_id then
    return jsonb_build_object('error', 'not-yours');
  end if;

  update public.ops_due_requests set
    state = case when p_approve then 'approved' else 'declined' end,
    decided_by = m.id, decided_at = now(), decide_note = nullif(btrim(p_note), '')
  where id = p_request;

  select name into nm from public.team_members where id = m.id;

  if p_approve then
    /* One path to a moved date, so the original-commitment rule and the event
       it files are the same whether or not an approval was needed. */
    out := public.ops_change_due_date(r.task_id, r.kind, r.wants_at,
                                      r.reason, r.note, null);
    if out ? 'error' then
      /* The gate refused after the approval, so the decision is put back
         rather than left recorded against a date that never moved. */
      update public.ops_due_requests set
        state = 'asked', decided_by = null, decided_at = null, decide_note = null
      where id = p_request;
      return out;
    end if;
  end if;

  perform public.ops_notify(r.asked_by, r.task_id,
    case when p_approve then 'due_approved' else 'due_declined' end,
    case when p_approve then 'Extension approved' else 'Extension declined' end,
    coalesce(nm, 'The task owner') ||
      case when p_approve then ' approved the new date' else ' declined the new date' end,
    'due_dec:' || p_request::text);

  perform public.ops_log(r.task_id,
    case when p_approve then 'due_approved' else 'due_declined' end,
    jsonb_build_object('kind', r.kind, 'value', r.was_at),
    jsonb_build_object('kind', r.kind, 'value', r.wants_at),
    jsonb_build_object('request', p_request, 'note', p_note));

  return jsonb_build_object('ok', true, 'approved', p_approve,
                            'task', public.ops_task_json(r.task_id));
end $$;
grant execute on function public.ops_decide_due_change(uuid, boolean, text) to authenticated;

-- 3. Taking it back. The person who asked may withdraw while it is open.
create or replace function public.ops_withdraw_due_change(p_request uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  r public.ops_due_requests;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.ops_due_requests where id = p_request for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.state <> 'asked' then return jsonb_build_object('error', 'decided'); end if;
  if m.id <> r.asked_by and not public.allowed('ops', 'manage') then
    return jsonb_build_object('error', 'not-yours');
  end if;
  update public.ops_due_requests set state = 'withdrawn', decided_by = m.id, decided_at = now()
    where id = p_request;
  return jsonb_build_object('ok', true, 'task', public.ops_task_json(r.task_id));
end $$;
grant execute on function public.ops_withdraw_due_change(uuid) to authenticated;

-- Rollback:
--   drop function if exists public.ops_withdraw_due_change(uuid);
--   drop function if exists public.ops_decide_due_change(uuid, boolean, text);
--   drop function if exists public.ops_request_due_change(uuid, text, timestamptz, text, text, integer);
--   drop function if exists public.ops_due_decider(uuid);
--   drop table if exists public.ops_due_requests;
-- ops_change_due_date is unchanged by this file and needs no rollback.
