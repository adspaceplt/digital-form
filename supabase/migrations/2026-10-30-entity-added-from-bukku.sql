-- AN ENTITY ADDED FROM BUKKU — a customer Bukku holds is added to a client
-- as a billing entity and linked to its Bukku contact in one step
-- (2026-10-30; the user: "just add and pull from Bukku instead of the
-- multiple steps"). bukku-sync's `adopt` reads the contact and calls this
-- as the colleague; it then holds the link, so Bukku's details are the
-- entity's. A contact the portal already links (an entity's, or a client's
-- through its primary entity) adds that entity, nothing made. The entity
-- and its link are one transaction: a link refused takes the entity back.
-- Safe to run twice; its rollback is `drop function
-- public.client_entity_from_bukku(uuid, bigint, text, jsonb);`.

create or replace function public.client_entity_from_bukku(p_client uuid, p_contact bigint, p_code text, p_values jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_held uuid;
  v_add  jsonb;
  v_link jsonb;
begin
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-contact'); end if;
  select case l.kind when 'entity' then l.record_id else public.client_main_entity(l.record_id) end
    into v_held
    from public.bukku_links l
   where l.contact_id = p_contact and l.kind in ('entity', 'client')
   order by (l.kind = 'entity') desc
   limit 1;
  if v_held is not null then
    return public.client_entity_add(p_client, v_held, null) || jsonb_build_object('held', true);
  end if;
  if exists (select 1 from public.bukku_links l where l.contact_id = p_contact) then
    return jsonb_build_object('error', 'taken');
  end if;
  v_add := public.client_entity_add(p_client, null, coalesce(p_values, '{}'::jsonb) - 'bill_contact_id');
  if v_add ? 'error' then return v_add; end if;
  v_link := public.bukku_link_only('entity', (v_add ->> 'id')::uuid, p_contact, p_code);
  if v_link ? 'error' then
    raise exception using errcode = 'P0001', message = 'bukku-link:' || (v_link ->> 'error');
  end if;
  return v_add;
exception when raise_exception then
  if sqlerrm like 'bukku-link:%' then return jsonb_build_object('error', substr(sqlerrm, 12)); end if;
  raise;
end $$;
revoke all on function public.client_entity_from_bukku(uuid, bigint, text, jsonb) from public, anon;
grant execute on function public.client_entity_from_bukku(uuid, bigint, text, jsonb) to authenticated;

-- END OF AN ENTITY ADDED FROM BUKKU ------------------------------------------

select public.functions_tidy();
