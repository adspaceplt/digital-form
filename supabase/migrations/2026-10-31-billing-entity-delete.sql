-- ===========================================================================
-- BILLING ENTITY DELETED — an entity removed from a client, and naming
-- nothing, is deleted for good (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31, approving an audit of a client record's tabs):
-- whatever a person can add, they can delete where nothing names it
-- (CLAUDE.md, 2026-10-22). Other billing entities offered Remove alone, so
-- an entity added in error stayed in the portal, found again by Add entity.
--
-- WHAT IT CHANGES
--   * `client_entities_removed(p_client)` (Clients: Billing View, the client
--     in scope): the entities removed from this client that bill no client
--     now (`orphan_of`), each with whether Bukku links it and whether a
--     letter names it, for Billing's Removed list.
--   * `client_entity_delete(p_client, p_entity, p_name)` (Clients: Billing
--     Full Access, the client in scope): the registered name typed back
--     (`bad-name`); refused while it still bills this client
--     (`not-removed`) or another (`bills-others`), while Bukku links it
--     (`bukku`), or while a letter names it (`on-letter`). The entity goes
--     with any unlink kept for Undo; filed `client.billing` · Billing entity
--     deleted: {name}. No restore.
--
-- ORDER: the pages, then this file in the SQL Editor (its bodies remove
-- rows, which the connector holds). Until it runs, Billing lists no removed
-- entity and offers no Delete. Safe to run twice. Mirrored byte for byte in
-- supabase/schema.sql under the same banner.
--
-- ROLLBACK (SQL Editor): drop function public.client_entity_delete(uuid,
-- uuid, text); drop function public.client_entities_removed(uuid).
-- ===========================================================================

-- BILLING ENTITY DELETED -----------------------------------------------------

create or replace function public.client_entities_removed(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.ops_me() is null or not public.billing_entity_may(p_client, 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('entities', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', e.id, 'legal_name', e.legal_name, 'company_no', e.company_no,
             'bukku', exists (select 1 from public.bukku_links l where l.kind = 'entity' and l.record_id = e.id),
             'on_letter', exists (select 1 from public.client_documents d where d.bill_to ->> 'entity_id' = e.id::text))
           order by e.legal_name, e.created_at)
      from public.billing_entities e
     where e.orphan_of = p_client
       and not exists (select 1 from public.client_entities ce where ce.entity_id = e.id)), '[]'::jsonb));
end $$;
revoke all on function public.client_entities_removed(uuid) from public, anon;
grant execute on function public.client_entities_removed(uuid) to authenticated;

create or replace function public.client_entity_delete(p_client uuid, p_entity uuid, p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_name text;
  e      public.billing_entities;
begin
  if me.id is null or not public.allowed('clients.billing', 'manage') or not public.client_seen(p_client, 'manage') then
    return jsonb_build_object('error', 'denied');
  end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  select * into e from public.billing_entities x where x.id = p_entity for update;
  if v_name is null or e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.client_entities ce where ce.entity_id = p_entity and ce.client_id = p_client) then
    return jsonb_build_object('error', 'not-removed');
  end if;
  if exists (select 1 from public.client_entities ce where ce.entity_id = p_entity) then
    return jsonb_build_object('error', 'bills-others');
  end if;
  if e.orphan_of is distinct from p_client then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.bukku_links l where l.kind = 'entity' and l.record_id = p_entity) then
    return jsonb_build_object('error', 'bukku');
  end if;
  if exists (select 1 from public.client_documents d where d.bill_to ->> 'entity_id' = p_entity::text) then
    return jsonb_build_object('error', 'on-letter');
  end if;
  if upper(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'))
     <> upper(regexp_replace(btrim(coalesce(e.legal_name, '')), '\s+', ' ', 'g')) then
    return jsonb_build_object('error', 'bad-name');
  end if;
  delete from public.bukku_links_gone g where g.kind = 'entity' and g.record_id = p_entity;
  delete from public.billing_entities x where x.id = p_entity;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name, 'Billing entity deleted: ' || coalesce(e.legal_name, 'no registered name'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_entity_delete(uuid, uuid, text) from public, anon;
grant execute on function public.client_entity_delete(uuid, uuid, text) to authenticated;

-- END OF BILLING ENTITY DELETED ----------------------------------------------

select public.functions_tidy();
