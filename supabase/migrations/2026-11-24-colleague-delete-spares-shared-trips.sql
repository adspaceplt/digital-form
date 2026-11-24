-- ===========================================================================
-- A COLLEAGUE'S DELETE SPARES SHARED TRIPS (2026-11-24)
-- ===========================================================================
-- WHY: the audit of 2026-11-24 (approved by the user): `team_member_purge`
-- deleted every row a required key to the colleague held, so an outstation
-- trip they drove went with its stops from the colleagues who joined it,
-- and a required key added later would be deleted unread.
--
-- WHAT CHANGED
--   * A required key is cleared only for the tables named as the
--     colleague's own (assignments, time records, extension requests,
--     quality checks, guides, section order, personnel record and salary,
--     delete requests, as the delete's question names them on 2026-11-17),
--     and a trip they drove alone.
--   * A trip they drove that another colleague joined refuses the delete
--     (`in-use`, `held` ['trips']); a required key not named, holding a row,
--     refuses it with its table.
--   * A trip they joined keeps itself; their id leaves its companions.
--
-- ORDER: this file (it holds `delete`, so the SQL Editor where the
-- connector holds it), then the pages (Team says `in-use`; an old page
-- reads it as the database's refusal). Safe to run twice.
-- ROLLBACK: run `team_member_purge` from DELETES AND BUILDS HELD in
-- schema.sql.
-- ===========================================================================

-- A COLLEAGUE'S DELETE SPARES SHARED TRIPS -----------------------------------

create or replace function public.team_member_purge(p_member uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  me      public.team_members := public.ops_me();
  v_m     public.team_members;
  v_email text;
  k       record;
  v_held  text[];
  v_any   boolean;
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
  /* A required key is cleared only where its rows are the colleague's own
     (review 2026-11-24: the loop deleted every row a required key held, so
     a trip they drove went from the colleagues who joined it). A trip
     another colleague joined holds the delete; a key not named here, added
     later, holds it too, never deleting what it does not know. */
  v_held := case when exists (select 1 from public.outstation_trips t
                               where t.driver_id = p_member and exists (select 1 from unnest(t.companions) c where c <> p_member))
                 then array['trips'] else '{}'::text[] end;
  for k in
    select c.conrelid::regclass as tbl, a.attname as col
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.team_members'::regclass and c.confdeltype in ('a', 'r') and a.attnotnull
       and c.conrelid::regclass::text not in ('ops_task_assignees', 'ops_work_sessions', 'ops_due_requests', 'option_qc',
         'guide_seen', 'rail_orders', 'personnel_records', 'personnel_salaries', 'delete_requests', 'outstation_trips')
  loop
    execute format('select exists (select 1 from %s where %I = $1)', k.tbl, k.col) using p_member into v_any;
    if v_any then v_held := v_held || k.tbl::text; end if;
  end loop;
  if cardinality(v_held) > 0 then return jsonb_build_object('error', 'in-use', 'held', to_jsonb(v_held)); end if;
  v_email := v_m.email;
  -- A trip they joined keeps itself without their name.
  update public.outstation_trips t set companions = array_remove(t.companions, p_member) where p_member = any (t.companions);
  /* A report's names (submitted, confirmed, reviewer) are cleared by their
     keys, which the report's guard holds to its functions: this is one. */
  perform set_config('adspace.sm_fn', 'on', true);
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
  perform set_config('adspace.sm_fn', 'off', true);
  if v_email is not null and not exists (select 1 from public.team_members x where lower(x.email) = lower(v_email))
     and not exists (select 1 from public.client_contacts k2 where lower(k2.email) = lower(v_email) and k2.archived_at is null) then
    delete from auth.users u where lower(u.email) = lower(v_email);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_member_purge(uuid, text) from public, anon;
grant execute on function public.team_member_purge(uuid, text) to authenticated;

-- END OF A COLLEAGUE'S DELETE SPARES SHARED TRIPS --------------------------

select public.functions_tidy();
