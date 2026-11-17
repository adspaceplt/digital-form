-- ============================================================================
-- A COLLEAGUE DELETED PERMANENTLY (2026-11-17)
-- ============================================================================
-- The user, 2026-11-17: "also allow entirely delete a person from Team".
-- Supersedes A COLLEAGUE'S ROW IS NEVER DELETED (2026-10-14, 2026-10-18) for a
-- colleague already removed: their row and sign-in go, by an admin, the name
-- typed back, no restore.
--
--   * `team_member_purge(p_member, p_name)`: an admin's (`admin-only`); the
--     colleague already Removed (`not-removed`); never oneself (`own`), the
--     super admin account (`system-account`) or the last admin
--     (`last-admin`); the name typed back (`bad-name`).
--   * Every foreign key to `team_members` is read from the catalogue as it
--     stands when it runs, so a key added later is met too:
--       - on delete set null (73 columns on 2026-11-17: who made, sent, confirmed or
--         decided a record, e.g. `sm_reports.created_by`,
--         `quotations.reviewer_id`, `documents.member_id`) are cleared by the
--         key itself;
--       - on delete cascade (26: their own data, e.g. `perf_reviews`,
--         `perf_events`, `health_*`, `ops_notifications`,
--         `push_subscriptions`, `team_abroad`, `team_onboarding`,
--         `hiring_people`) go with the row;
--       - no action or restrict, column nullable (27, e.g. `clients.sales_by`,
--         `ops_tasks.created_by`, `ops_engagements.manager_id`,
--         `ops_task_events.actor_id`): set null first;
--       - no action or restrict, column required (9: `delete_requests.requested_by`,
--         `guide_seen`, `ops_due_requests.asked_by`, `ops_task_assignees`,
--         `ops_work_sessions`, `option_qc`, `personnel_records`,
--         `personnel_salaries`, `rail_orders`): those rows are theirs and
--         are deleted first.
--     Names stored as text on past work, documents, clients and the Activity
--     record are kept. Their sign-in is deleted where no live client contact
--     holds the address. Filed `team.changed` "Deleted permanently".
--
-- ORDER: this file (connector), then the pages. Safe to run twice.
-- ROLLBACK: `drop function public.team_member_purge(uuid, text);` (nothing
-- deleted by it comes back).
-- ============================================================================

-- A COLLEAGUE DELETED PERMANENTLY --------------------------------------------

create or replace function public.team_member_purge(p_member uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  me      public.team_members := public.ops_me();
  v_m     public.team_members;
  v_email text;
  k       record;
begin
  if me.id is null or not public.allowed('admin') then return jsonb_build_object('error', 'admin-only'); end if;
  select * into v_m from public.team_members x where x.id = p_member for update;
  if v_m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_m.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if coalesce(v_m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if v_m.removed_at is null then return jsonb_build_object('error', 'not-removed'); end if;
  if lower(btrim(coalesce(p_name, ''))) <> lower(btrim(v_m.name)) then return jsonb_build_object('error', 'bad-name'); end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and v_m.active
     and not exists (select 1 from public.team_members x where x.id <> v_m.id and x.active
                       and (coalesce(x.is_admin, false) or x.role = 'admin')) then
    return jsonb_build_object('error', 'last-admin');
  end if;
  v_email := v_m.email;
  for k in
    select c.conrelid::regclass as tbl, a.attname as col, a.attnotnull as req
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.team_members'::regclass and c.confdeltype in ('a', 'r')
  loop
    if k.req then
      execute format('delete from %s where %I = $1', k.tbl, k.col) using p_member;
    else
      execute format('update %s set %I = null where %I = $1', k.tbl, k.col, k.col) using p_member;
    end if;
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', v_m.name, 'Deleted permanently');
  delete from public.team_members x where x.id = p_member;
  if v_email is not null and not exists (select 1 from public.team_members x where lower(x.email) = lower(v_email))
     and not exists (select 1 from public.client_contacts k2 where lower(k2.email) = lower(v_email) and k2.archived_at is null) then
    delete from auth.users u where lower(u.email) = lower(v_email);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_member_purge(uuid, text) from public, anon;
grant execute on function public.team_member_purge(uuid, text) to authenticated;

-- END OF A COLLEAGUE DELETED PERMANENTLY -------------------------------------

select public.functions_tidy();
