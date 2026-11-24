-- ===========================================================================
-- A CLIENT'S TASKS AND VISITS BY MONTH (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24: "Every single my work submission should also
-- go under clients engagements tab ... so that we have a linking record
-- that we can trace it back", "Every record a row". A client's
-- Engagements counted its month's tasks and named no task, and an
-- outstation visit was a line of Calls and visits alone.
--
-- WHAT IT ADDS
--   * `client_engagement_items(p_client)`: in one answer, the client's My
--     Work tasks the reader may see (`ops_may_see_task`), not archived, each
--     with its number (`ops_serial`), title, stage and stage group, its
--     content month (`period`, its engagement's, else null and the day it
--     was made, `made`), done, cancelled and late; and the client's
--     outstation visits, a row a stop (its trip's number, the trip, the
--     Malaysian day, the purpose, the driver, and `mine` where the reader
--     drove or joined it), at My Work View on a client the reader sees
--     (`client_seen`). Neither part is answered to a reader without its
--     access (`tasks`, `visits` null); `denied` when the reader is no
--     colleague.
--
-- ORDER: this file, then the page (a page from before never asks it; the
-- new page reads the months without these rows while it is not run).
-- Safe to run twice.
-- ROLLBACK: drop `client_engagement_items(uuid)`; the page then draws the
-- months without these rows.
-- ===========================================================================

create or replace function public.client_engagement_items(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me public.team_members; v_tasks jsonb; v_visits jsonb;
begin
  v_me := public.ops_me();
  if v_me.id is null or p_client is null then return jsonb_build_object('error', 'denied'); end if;
  if public.allowed('ops', 'view') then
    select coalesce(jsonb_agg(x.j order by x.done, x.due nulls last, x.no), '[]'::jsonb) into v_tasks
      from (
        select t.task_no as no, t.current_final_due_at as due,
               (t.completed_at is not null or t.cancelled_at is not null) as done,
               jsonb_build_object(
                 'id', t.id,
                 'serial', public.ops_serial(t.task_no),
                 'title', public.ops_title(t),
                 'stage', coalesce(s.label, initcap(replace(t.stage_key, '_', ' '))),
                 'stage_group', s.stage_group,
                 'period', e.period,
                 'made', (t.created_at at time zone 'Asia/Kuala_Lumpur')::date,
                 'done', t.completed_at is not null,
                 'cancelled', t.cancelled_at is not null,
                 'late', t.completed_at is null and t.cancelled_at is null and public.ops_task_late(t.id)) as j
          from public.ops_tasks t
          left join public.ops_engagements e on e.id = t.engagement_id
          left join public.ops_workflow_stages s on s.workflow_id = t.workflow_id and s.key = t.stage_key
         where t.client_id = p_client and t.archived_at is null
           and public.ops_may_see_task(t.id)
      ) x;
    if public.client_seen(p_client, 'view') then
      select coalesce(jsonb_agg(jsonb_build_object(
               'trip', t.id, 'ref', t.ref,
               'day', (s.arrived_at at time zone 'Asia/Kuala_Lumpur')::date,
               'purpose', t.purpose,
               'driver', (select m.name from public.team_members m where m.id = t.driver_id),
               'open', s.left_at is null,
               'mine', t.driver_id = v_me.id or v_me.id = any(t.companions))
             order by s.arrived_at desc), '[]'::jsonb) into v_visits
        from public.outstation_stops s
        join public.outstation_trips t on t.id = s.trip_id
       where s.client_id = p_client;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'tasks', v_tasks, 'visits', v_visits);
end $$;
revoke all on function public.client_engagement_items(uuid) from public, anon;
grant execute on function public.client_engagement_items(uuid) to authenticated;

-- END OF A CLIENT'S TASKS AND VISITS BY MONTH -------------------------------

select public.functions_tidy();
