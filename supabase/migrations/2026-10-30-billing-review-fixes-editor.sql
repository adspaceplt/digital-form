-- ===========================================================================
-- BILLING REVIEW FIXES, THE SQL EDITOR PART — an entity's last client kept (2026-10-30)
-- ===========================================================================
-- Run in the SQL Editor after 2026-10-30-billing-review-fixes.sql: the
-- connector holds a function body that removes a row. `client_entity_remove`
-- marks an entity left billing no client with the client it billed last
-- (`orphan_of`). Safe to run twice.
--
-- ROLLBACK: run BILLING ENTITIES' client_entity_remove again.
-- ===========================================================================

create or replace function public.client_entity_remove(p_client uuid, p_entity uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_name text;
  v_main boolean;
begin
  if not public.billing_entity_may(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  select ce.is_main into v_main from public.client_entities ce where ce.client_id = p_client and ce.entity_id = p_entity;
  if v_name is null or v_main is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_main then return jsonb_build_object('error', 'main'); end if;
  delete from public.client_entities ce where ce.client_id = p_client and ce.entity_id = p_entity;
  -- An entity left billing no client is kept with the client it billed last,
  -- so only a colleague who reaches that client finds it (audit 2026-10-30).
  if not exists (select 1 from public.client_entities ce where ce.entity_id = p_entity) then
    update public.billing_entities e set orphan_of = p_client where e.id = p_entity;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name, 'Billing entity removed');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_entity_remove(uuid, uuid) from public, anon;
grant execute on function public.client_entity_remove(uuid, uuid) to authenticated;

-- END OF BILLING REVIEW FIXES, THE SQL EDITOR PART ---------------------------

select public.functions_tidy();
