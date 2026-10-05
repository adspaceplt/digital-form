-- ===========================================================================
-- A CLIENT PAUSED OR PAST SAYS WHY — moving a client to Paused or Past takes
-- a reason, kept on that stage move, and each colleague with work still open
-- for the client is told once to finish its delivery.
-- 2026-10-04. Safe to run twice. Rollback below. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-10-04: a reason required on Paused and Past;
-- a client paused or ended at its invoice period still has revisions and
-- reviews to deliver, and they need arranging urgently)
--   1. `clients.stage_reason` (budget, results, in_house, closed, no_reply,
--      other) and `clients.stage_note` arrive with the stage itself; the
--      clock writes them into that move's `stage_log` entry. A move into
--      Paused or Past without a reason is refused (`stage-reason`); a move
--      to any other stage clears both, since they belong to the pause or
--      the ending.
--   2. `clients_stage_notice` (after update): on a real move into Paused or
--      Past, each colleague who owns an open task of the client is told
--      once, `{client} moved to Paused · 3 open tasks to deliver`, opening My
--      Work (`kind` client_left). The urgent mark itself is worked out by
--      the page from the client's stage, never written to a task.
--   3. `client_open_tasks(p_client)`: the count of the client's open tasks,
--      for the question that asks the reason (Clients View).
--   4. `ops_notifications_push` opens My Work for a client_left notice.
--   5. `ops_task_client_facts(p_tasks)`: a task's client name and stage for
--      the tasks the colleague may see, where the client itself is out of
--      their reach (their own task on another's client), so its urgent
--      delivery shows too. `ops_task_clients` stays for the page before it.
--
-- ROLLBACK
--   Run the CLIENTS STAGE CLOCK section's clients_stage_clock and the PUSH
--   section's ops_notifications_push again; then, in the SQL Editor, drop
--   the trigger clients_stage_notice, its function, client_open_tasks and
--   ops_task_client_facts.
--   The two columns may stay.
-- ===========================================================================

alter table public.clients add column if not exists stage_reason text;
alter table public.clients add column if not exists stage_note text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'clients_stage_reason') then
    alter table public.clients add constraint clients_stage_reason
      check (stage_reason is null or stage_reason in ('budget', 'results', 'in_house', 'closed', 'no_reply', 'other'));
  end if;
end $$;
grant select (stage_reason, stage_note) on table public.clients to authenticated;

create or replace function public.clients_stage_clock()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    new.stage_since := coalesce(new.stage_since, coalesce(new.created_at, now()));
    if new.stage_log is null or jsonb_array_length(new.stage_log) = 0 then
      new.stage_log := jsonb_build_array(
        jsonb_build_object('stage', new.stage, 'at', new.stage_since));
    end if;
    return new;
  end if;
  -- Only a real move restarts the clock. A move into Paused or Past says
  -- why; a move anywhere else leaves the reason behind with the pause.
  if new.stage is distinct from old.stage then
    if new.stage in ('paused', 'past') then
      if nullif(btrim(coalesce(new.stage_reason, '')), '') is null then
        raise exception 'stage-reason' using errcode = 'P0001';
      end if;
    else
      new.stage_reason := null;
      new.stage_note := null;
    end if;
    new.stage_since := now();
    new.stage_log := coalesce(old.stage_log, '[]'::jsonb) ||
      jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('stage', new.stage, 'at', now(),
        'reason', new.stage_reason, 'note', nullif(btrim(coalesce(new.stage_note, '')), ''))));
  end if;
  return new;
end $$;

-- A client's open tasks: not finished, cancelled or archived.
create or replace function public.client_open_tasks(p_client uuid)
returns integer
language sql stable security definer set search_path = public as $$
  select case when public.allowed('clients', 'view') and public.client_seen(p_client, 'view') then
    (select count(*)::integer from public.ops_tasks t
      where t.client_id = p_client and t.completed_at is null
        and t.cancelled_at is null and t.archived_at is null)
  else 0 end
$$;
revoke all on function public.client_open_tasks(uuid) from public, anon, authenticated;
grant execute on function public.client_open_tasks(uuid) to authenticated;

create or replace function public.clients_stage_notice()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_word text := case new.stage when 'paused' then 'Paused' else 'Past' end;
begin
  if new.stage is not distinct from old.stage or new.stage not in ('paused', 'past') then
    return new;
  end if;
  for r in select a.team_member_id as owner, count(*) as n
             from public.ops_tasks t
             join public.ops_task_assignees a
               on a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null
            where t.client_id = new.id and t.completed_at is null
              and t.cancelled_at is null and t.archived_at is null
            group by a.team_member_id loop
    perform public.ops_notify(r.owner, null, 'client_left',
      coalesce(nullif(btrim(new.name), ''), 'A client') || ' moved to ' || v_word,
      r.n || case when r.n = 1 then ' open task' else ' open tasks' end || ' to deliver',
      'client_left:' || new.id || ':' || new.stage || ':' || r.owner || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
  end loop;
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.clients_stage_notice() from public, anon, authenticated;
create or replace trigger clients_stage_notice after update on public.clients
  for each row execute function public.clients_stage_notice();

create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.task_id is not null then '/admin/?s=work&open=' || new.task_id::text
         when new.report_id is not null then '/admin/?s=reports&report=' || new.report_id::text
         when new.kind = 'client_left' then '/admin/?s=work'
         else '/admin/' end,
    case when new.task_id is not null then 'task-' || new.task_id::text
         when new.report_id is not null then 'report-' || new.report_id::text
         else null end);
  return new;
exception when others then
  return new;
end $$;

/* A task's client, named and staged, for the colleague's own tasks on a
   client outside their reach: the name alone was not enough once a paused
   or past client's open work reads as urgent delivery. */
create or replace function public.ops_task_client_facts(p_tasks uuid[])
returns table (task_id uuid, client_name text, client_stage text)
language sql security definer stable set search_path = public as $$
  select t.id, c.name, c.stage
    from public.ops_tasks t
    join public.clients c on c.id = t.client_id
   where t.id = any (p_tasks[1:500])
     and public.ops_may_see_task(t.id)
$$;
revoke all on function public.ops_task_client_facts(uuid[]) from public, anon;
grant execute on function public.ops_task_client_facts(uuid[]) to authenticated;

-- END OF A CLIENT PAUSED OR PAST SAYS WHY ------------------------------------
