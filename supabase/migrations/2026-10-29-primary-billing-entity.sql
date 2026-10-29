-- ===========================================================================
-- PRIMARY BILLING ENTITY — the entity a client is billed by first is its
-- primary one, in words as on the pages (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "Make main for main entity why not use Make
-- primary. Who says make main so weird"): the pages say Primary billing
-- entity and Make primary; the Activity record said Main billing entity
-- changed.
--
-- WHAT CHANGED
--   * `client_entity_main` files Primary billing entity changed. Its checks,
--     refusals and answer are unchanged; the stored key `is_main` stays.
--
-- ORDER: this file (connector), then the pages. Either order is safe: only
-- the words of a new Activity record row change. Safe to run twice.
--
-- ROLLBACK: run BILLING ENTITIES' client_entity_main again.
-- ===========================================================================

-- PRIMARY BILLING ENTITY ----------------------------------------------------

create or replace function public.client_entity_main(p_client uuid, p_entity uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_name text;
  v_was  uuid;
begin
  if not public.billing_entity_may(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  if v_name is null or not exists (select 1 from public.client_entities ce
                                    where ce.client_id = p_client and ce.entity_id = p_entity) then
    return jsonb_build_object('error', 'not-found');
  end if;
  select ce.entity_id into v_was from public.client_entities ce where ce.client_id = p_client and ce.is_main for update;
  if v_was = p_entity then return jsonb_build_object('ok', true, 'was', v_was); end if;
  update public.client_entities ce set is_main = false where ce.client_id = p_client and ce.is_main;
  update public.client_entities ce set is_main = true where ce.client_id = p_client and ce.entity_id = p_entity;
  perform public.billing_entity_put(p_entity, p_client);
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name, 'Primary billing entity changed');
  return jsonb_build_object('ok', true, 'was', v_was);
end $$;
revoke all on function public.client_entity_main(uuid, uuid) from public, anon;
grant execute on function public.client_entity_main(uuid, uuid) to authenticated;

-- END OF PRIMARY BILLING ENTITY ---------------------------------------------

select public.functions_tidy();
