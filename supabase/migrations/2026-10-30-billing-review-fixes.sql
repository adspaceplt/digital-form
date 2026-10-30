-- ===========================================================================
-- BILLING REVIEW FIXES — the audit of 2026-10-30
-- ===========================================================================
-- WHY: the audit of the releases since 2026-10-29 found an edit to a billing
-- entity Bukku holds saved in the portal alone and then read over by Bukku;
-- an entity removed from its last client found by every colleague at
-- Billing View, own clients only included; an emptied finance email sent
-- back to Bukku as the old address; a read rewriting the portal's own form
-- of a number Bukku holds unchanged; a client's first entity made from
-- Bukku never reaching the client's columns; and two first entities at once.
--
-- WHAT IT CHANGES
--   `billing_entities.orphan_of`, the client an entity billing none billed
--   last. `billing_entity_reached(p_entity)` (no grant): one billing a
--   client the caller sees, or none but last such a client, or any for a
--   colleague who sees every client; `billing_entities_find` and
--   `client_entity_add` ask it. `client_entity_remove` marks it (the SQL
--   Editor part, below: the connector holds its body), `client_entity_add`
--   clears it and holds the client while it chooses
--   the primary. `client_entity_save` refuses `held` for an entity Bukku
--   holds. `bukku_prepare_with` sends the billing contact's email where the
--   finance email is emptied. `bukku_take` writes a detail only where it
--   changed or the portal holds none, stamps `updated_at`, and carries a
--   first entity it made to the client.
--
-- ORDER: this file, then the pages, then the SQL Editor part. Until that
-- part runs, an entity left billing no client is found by a colleague who
-- sees every client alone. Safe to run twice.
--
-- ROLLBACK: run these six functions' earlier definitions again (BILLING
-- ENTITIES, ENTITY FOUND BY BRANDS, BILLING FROM BUKKU); the column may stay.
-- ===========================================================================

alter table public.billing_entities add column if not exists orphan_of uuid;

/* Whether the caller reaches an entity: one billing a client the caller
   sees, or one billing none that last billed such a client (or for a
   colleague who sees every client). Audit 2026-10-30. */
create or replace function public.billing_entity_reached(p_entity uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.client_entities ce
                  where ce.entity_id = p_entity and public.client_seen(ce.client_id, 'view'))
      or (not exists (select 1 from public.client_entities ce where ce.entity_id = p_entity)
          and (public.client_scope_free('view')
               or exists (select 1 from public.billing_entities e
                           where e.id = p_entity and e.orphan_of is not null and public.client_seen(e.orphan_of, 'view'))))
$$;
revoke all on function public.billing_entity_reached(uuid) from public, anon, authenticated;

create or replace function public.client_entity_save(p_client uuid, p_entity uuid, p_values jsonb,
                                                     p_expected timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_name  text;
  v_vals  jsonb;
  v_was   public.billing_entities;
  v_held  public.billing_entities;
  v_moved text[] := '{}';
  v_at    timestamptz;
begin
  if not public.billing_entity_may(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  if v_name is null or not exists (select 1 from public.client_entities ce
                                    where ce.client_id = p_client and ce.entity_id = p_entity) then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- An entity Bukku holds is saved to Bukku, never here: a portal save would
  -- be read over by Bukku's (audit 2026-10-30).
  if exists (select 1 from public.bukku_links l where l.kind = 'entity' and l.record_id = p_entity and l.held_at is not null) then
    return jsonb_build_object('error', 'held');
  end if;
  select * into v_was from public.billing_entities e where e.id = p_entity for update;
  if p_expected is not null and v_was.updated_at is distinct from p_expected then
    return jsonb_build_object('error', 'stale', 'entity', public.billing_entity_json(p_entity, p_client));
  end if;
  v_vals := public.billing_entity_clean(p_values);
  if v_vals ? 'error' then return v_vals; end if;
  if v_vals ->> 'bill_contact_id' is not null
     and (v_vals ->> 'bill_contact_id')::uuid is distinct from v_was.bill_contact_id
     and not exists (
       select 1 from public.client_contacts k join public.client_entities ce on ce.client_id = k.client_id
        where k.id = (v_vals ->> 'bill_contact_id')::uuid and k.archived_at is null and ce.entity_id = p_entity) then
    return jsonb_build_object('error', 'bad-contact');
  end if;
  if length(regexp_replace(coalesce(v_vals ->> 'company_no', ''), '\D', '', 'g')) > 0 then
    select * into v_held from public.billing_entities e
     where e.id <> p_entity
       and regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = regexp_replace(v_vals ->> 'company_no', '\D', '', 'g')
       and regexp_replace(coalesce(v_was.company_no, ''), '\D', '', 'g') <> regexp_replace(v_vals ->> 'company_no', '\D', '', 'g')
     order by e.created_at limit 1;
    if v_held.id is not null then
      return jsonb_build_object('error', 'brn-taken', 'entity',
                                jsonb_build_object('id', v_held.id, 'legal_name', v_held.legal_name));
    end if;
  end if;
  v_moved := array_remove(array[
    case when v_was.legal_name is distinct from v_vals ->> 'legal_name' then 'Company name as registered' end,
    case when v_was.company_no is distinct from v_vals ->> 'company_no' then 'Business registration no.' end,
    case when v_was.company_no_old is distinct from v_vals ->> 'company_no_old' then 'Old registration no.' end,
    case when v_was.tin is distinct from v_vals ->> 'tin' then 'TIN' end,
    case when v_was.sst_no is distinct from v_vals ->> 'sst_no' then 'SST registration no.' end,
    case when v_was.bill_contact_id is distinct from (v_vals ->> 'bill_contact_id')::uuid then 'Billing contact' end,
    case when v_was.finance_email is distinct from v_vals ->> 'finance_email' then 'Finance department email' end,
    case when v_was.billing_address is distinct from v_vals ->> 'billing_address' then 'Company billing address' end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true, 'updated_at', v_was.updated_at); end if;
  update public.billing_entities e
     set legal_name = v_vals ->> 'legal_name', company_no = v_vals ->> 'company_no',
         company_no_old = v_vals ->> 'company_no_old', tin = v_vals ->> 'tin', sst_no = v_vals ->> 'sst_no',
         bill_contact_id = (v_vals ->> 'bill_contact_id')::uuid, finance_email = v_vals ->> 'finance_email',
         billing_address = v_vals ->> 'billing_address', updated_at = clock_timestamp()
   where e.id = p_entity
  returning e.updated_at into v_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name, 'Billing entity edited: ' || array_to_string(v_moved, ', '));
  return jsonb_build_object('ok', true, 'updated_at', v_at);
end $$;
revoke all on function public.client_entity_save(uuid, uuid, jsonb, timestamptz) from public, anon;
grant execute on function public.client_entity_save(uuid, uuid, jsonb, timestamptz) to authenticated;

create or replace function public.client_entity_add(p_client uuid, p_entity uuid default null, p_values jsonb default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_name  text;
  v_vals  jsonb;
  v_ent   uuid := p_entity;
  v_main  boolean;
  v_held  public.billing_entities;
begin
  if not public.billing_entity_may(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  if v_name is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_ent is not null then
    if not exists (select 1 from public.billing_entities e where e.id = v_ent) then
      return jsonb_build_object('error', 'not-found');
    end if;
    if not public.billing_entity_reached(v_ent) then
      return jsonb_build_object('error', 'denied');
    end if;
    if exists (select 1 from public.client_entities ce where ce.entity_id = v_ent and ce.client_id = p_client) then
      return jsonb_build_object('error', 'taken');
    end if;
  else
    v_vals := public.billing_entity_clean(p_values);
    if v_vals ? 'error' then return v_vals; end if;
    if v_vals ->> 'bill_contact_id' is not null and not exists (
         select 1 from public.client_contacts k
          where k.id = (v_vals ->> 'bill_contact_id')::uuid and k.client_id = p_client and k.archived_at is null) then
      return jsonb_build_object('error', 'bad-contact');
    end if;
    if length(regexp_replace(coalesce(v_vals ->> 'company_no', ''), '\D', '', 'g')) > 0 then
      select * into v_held from public.billing_entities e
       where regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = regexp_replace(v_vals ->> 'company_no', '\D', '', 'g')
       order by e.created_at limit 1;
      if v_held.id is not null then
        return jsonb_build_object('error', 'brn-taken', 'entity',
                                  jsonb_build_object('id', v_held.id, 'legal_name', v_held.legal_name));
      end if;
    end if;
    insert into public.billing_entities (legal_name, company_no, company_no_old, tin, sst_no, bill_contact_id,
                                         finance_email, billing_address, created_by)
    values (v_vals ->> 'legal_name', v_vals ->> 'company_no', v_vals ->> 'company_no_old', v_vals ->> 'tin',
            v_vals ->> 'sst_no', (v_vals ->> 'bill_contact_id')::uuid, v_vals ->> 'finance_email',
            v_vals ->> 'billing_address', me.id)
    returning id into v_ent;
  end if;
  -- One first entity at a time for a client (audit 2026-10-30).
  perform 1 from public.clients x where x.id = p_client for update;
  v_main := not exists (select 1 from public.client_entities ce where ce.client_id = p_client and ce.is_main);
  insert into public.client_entities (client_id, entity_id, is_main, added_by) values (p_client, v_ent, v_main, me.id);
  update public.billing_entities e set orphan_of = null where e.id = v_ent and e.orphan_of is not null;
  if v_main then perform public.billing_entity_put(v_ent, p_client); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name,
          case when p_entity is null then 'Billing entity added' else 'Billing entity added, already held' end
          || case when v_main then ' · main' else '' end);
  return jsonb_build_object('ok', true, 'id', v_ent, 'main', v_main);
end $$;
revoke all on function public.client_entity_add(uuid, uuid, jsonb) from public, anon;
grant execute on function public.client_entity_add(uuid, uuid, jsonb) to authenticated;

create or replace function public.billing_entities_find(p_q text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q text := btrim(coalesce(p_q, ''));
  v_words text[];
  v_digits text := regexp_replace(coalesce(p_q, ''), '\D', '', 'g');
begin
  if not public.allowed('clients.billing', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_q) < 2 then return jsonb_build_object('entities', '[]'::jsonb); end if;
  -- Each word as a pattern, a wildcard typed read as a letter.
  select array_agg('%' || replace(replace(replace(w, '\', '\\'), '%', '\%'), '_', '\_') || '%')
    into v_words
    from regexp_split_to_table(v_q, '\s+') w where w <> '';
  return jsonb_build_object('entities', coalesce((
    select jsonb_agg(x.j order by x.n) from (
      select public.billing_entity_json(e.id, null) as j, e.legal_name as n
        from public.billing_entities e
       where (not exists (
                select 1 from unnest(v_words) l
                 where not (coalesce(e.legal_name, '') ilike l
                            or exists (select 1 from public.client_entities ce
                                         join public.clients x on x.id = ce.client_id
                                        where ce.entity_id = e.id and public.client_seen(x.id, 'view')
                                          and (x.name ilike l or coalesce(x.client_code, '') ilike l))))
              or (length(v_digits) >= 4 and regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') like '%' || v_digits || '%'))
         and public.billing_entity_reached(e.id)
       order by e.legal_name
       limit 10) x), '[]'::jsonb));
end $$;
revoke all on function public.billing_entities_find(text) from public, anon;
grant execute on function public.billing_entities_find(text) to authenticated;

create or replace function public.bukku_prepare_with(p_kind text, p_id uuid, p_values jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb; k public.client_contacts; v_clear text[] := '{}'; v_t text; v_key text; v_fin_clear boolean := false;
  v_map constant text[][] := array[array['company_no_old', 'old_reg_no'], array['tin', 'tax_id_no'], array['sst_no', 'sst_reg_no']];
begin
  if p_kind not in ('client', 'entity') then return jsonb_build_object('error', 'bad-kind'); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  for v_key in select jsonb_object_keys(p_values) loop
    if v_key not in ('legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no', 'finance_email', 'billing_address',
                     'bill_contact_id') then
      return jsonb_build_object('error', 'bad-field', 'field', v_key);
    end if;
  end loop;
  v := public.bukku_prepare(p_kind, p_id);
  if v ? 'error' then return v; end if;
  if v->>'contact_id' is null then return jsonb_build_object('error', 'not-linked'); end if;
  if p_values ? 'legal_name' then
    v_t := btrim(regexp_replace(coalesce(p_values->>'legal_name', ''), '\s+', ' ', 'g'));
    if v_t = '' then return jsonb_build_object('error', 'no-name'); end if;
    if length(v_t) > 200 then return jsonb_build_object('error', 'too-long', 'field', 'legal_name'); end if;
    v := v || jsonb_build_object('legal_name', public.bukku_name_case(upper(v_t), true));
  end if;
  if p_values ? 'company_no' then
    v_t := nullif(regexp_replace(coalesce(p_values->>'company_no', ''), '[^0-9A-Za-z]', '', 'g'), '');
    if length(v_t) > 40 then return jsonb_build_object('error', 'too-long', 'field', 'company_no'); end if;
    v := v || jsonb_build_object('reg_no', v_t, 'reg_no_type', case when v_t is null then null else 'BRN' end);
    if v_t is null then v_clear := v_clear || 'reg_no'::text; end if;
  end if;
  for i in 1 .. array_length(v_map, 1) loop
    if p_values ? v_map[i][1] then
      v_t := nullif(btrim(coalesce(p_values->>v_map[i][1], '')), '');
      if length(v_t) > 60 then return jsonb_build_object('error', 'too-long', 'field', v_map[i][1]); end if;
      v := v || jsonb_build_object(v_map[i][2], v_t);
      if v_t is null then v_clear := v_clear || v_map[i][2]; end if;
    end if;
  end loop;
  if p_values ? 'finance_email' then
    v_t := nullif(btrim(coalesce(p_values->>'finance_email', '')), '');
    if v_t is not null and v_t !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[A-Za-z]{2,}$' then return jsonb_build_object('error', 'bad-email'); end if;
    if v_t is not null then v := v || jsonb_build_object('email', lower(v_t)); else v_fin_clear := true; end if;
  end if;
  if p_values ? 'billing_address' then
    v_t := nullif(btrim(coalesce(p_values->>'billing_address', '')), '');
    if v_t is null then return jsonb_build_object('error', 'no-address'); end if;
    if length(v_t) > 500 then return jsonb_build_object('error', 'too-long', 'field', 'billing_address'); end if;
    v := v || jsonb_build_object('address', v_t);
  end if;
  if p_values ? 'bill_contact_id' then
    v_t := nullif(btrim(coalesce(p_values->>'bill_contact_id', '')), '');
    if v_t is null then
      if p_kind = 'client' then
        select * into k from public.client_contacts x where x.client_id = p_id and x.is_primary and x.archived_at is null limit 1;
      else
        select * into k from public.client_contacts x
         where x.client_id = public.entity_home_client(p_id) and x.is_primary and x.archived_at is null limit 1;
      end if;
    elsif v_t ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select * into k from public.client_contacts x
       where x.id = v_t::uuid and x.archived_at is null
         and (case when p_kind = 'client' then x.client_id = p_id
                   else x.client_id in (select ce.client_id from public.client_entities ce where ce.entity_id = p_id) end);
      if k.id is null then return jsonb_build_object('error', 'bad-contact'); end if;
    else
      return jsonb_build_object('error', 'bad-contact');
    end if;
    v := v || jsonb_build_object('person', nullif(public.bukku_name_case(btrim(coalesce(k.name, '')), false), ''),
                                 'salutation', nullif(btrim(coalesce(k.salutation, '')), ''));
  end if;
  -- Finance email emptied: Bukku takes the billing contact's, as bukku_prepare
  -- reads it, never the old finance address (audit 2026-10-30).
  if v_fin_clear then
    if k.id is null then
      if p_kind = 'client' then
        select x.* into k from public.client_contacts x join public.clients c on c.id = p_id
         where x.archived_at is null
           and (x.id = c.bill_contact_id or (c.bill_contact_id is null and x.client_id = p_id and x.is_primary))
         limit 1;
      else
        select x.* into k from public.client_contacts x join public.billing_entities e on e.id = p_id
         where x.archived_at is null
           and (x.id = e.bill_contact_id or (e.bill_contact_id is null and x.client_id = public.entity_home_client(p_id) and x.is_primary))
         limit 1;
      end if;
    end if;
    v := v || jsonb_build_object('email', nullif(lower(btrim(coalesce(k.email, ''))), ''));
    if nullif(btrim(coalesce(k.email, '')), '') is null then v_clear := v_clear || 'email'::text; end if;
  end if;
  return v || jsonb_build_object('clear', to_jsonb(v_clear));
end $$;
revoke all on function public.bukku_prepare_with(text, uuid, jsonb) from public, anon;
grant execute on function public.bukku_prepare_with(text, uuid, jsonb) to authenticated;

create or replace function public.bukku_take(p_actor uuid, p_kind text, p_id uuid, p_values jsonb, p_hash text,
                                             p_changed text[], p_mode text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  l public.bukku_links; p jsonb; k public.client_contacts;
  v_ent uuid; v_who text; v_name text; v_detail text; v_bc uuid; v_bc_set boolean := false;
  v_changed text[] := coalesce(p_changed, '{}');
  v_open text[];
  v_words constant jsonb := '{"legal_name": "Registered name", "company_no": "Business registration no.",
    "company_no_old": "Old registration no.", "tin": "TIN", "sst_no": "SST registration no.",
    "finance_email": "Finance email", "billing_address": "Billing address", "person": "Billing contact"}';
  v_t text;
  v_new boolean := false;
begin
  if p_kind not in ('client', 'entity') or p_mode not in ('read', 'hold', 'save')
     or jsonb_typeof(p_values) is distinct from 'object' then
    return jsonb_build_object('error', 'bad-request');
  end if;
  l := public.bukku_link_row(p_kind, p_id);
  if l.contact_id is null then return jsonb_build_object('error', 'not-linked'); end if;
  p := public.bukku_portal(p_kind, p_id);
  if p is null then return jsonb_build_object('error', 'not-found'); end if;
  select array_agg(f) into v_changed from unnest(v_changed) f where v_words ? f;
  v_changed := coalesce(v_changed, '{}');
  select array_agg(f) into v_open from unnest(v_changed) f
   where nullif(btrim(coalesce(p->>f, '')), '') is not null;
  v_open := coalesce(v_open, '{}');
  update public.bukku_links x set read_at = now(), read_hash = left(p_hash, 200),
         person = nullif(left(btrim(coalesce(p_values->>'person', '')), 120), '')
   where x.kind = l.kind and x.record_id = l.record_id;
  /* The first read of a link not yet held writes nothing over a detail
     the portal holds: it waits on Send to Bukku or Use Bukku's. */
  if p_mode = 'read' and l.held_at is null and cardinality(v_open) > 0 then
    return jsonb_build_object('ok', true, 'held', false, 'differs', to_jsonb(v_changed));
  end if;

  if p_kind = 'client' then
    v_ent := public.client_main_entity(p_id);
    if v_ent is null then
      insert into public.billing_entities (legal_name) values (nullif(btrim(coalesce(p_values->>'legal_name', '')), ''))
      returning id into v_ent;
      insert into public.client_entities (client_id, entity_id, is_main) values (p_id, v_ent, true);
      v_new := true;
    end if;
  else
    v_ent := p_id;
  end if;
  if p_values ? 'person' and nullif(btrim(coalesce(p_values->>'person', '')), '') is not null then
    k := public.bukku_person_contact(p_kind, p_id, p_values->>'person');
    if k.id is not null then
      v_bc_set := true;
      v_bc := case when k.is_primary and k.client_id = coalesce(case when p_kind = 'client' then p_id end,
                                                                public.entity_home_client(p_id)) then null else k.id end;
    end if;
  end if;
  update public.billing_entities e
     set legal_name = case when p_values ? 'legal_name' and ('legal_name' = any(v_changed) or nullif(btrim(coalesce(e.legal_name, '')), '') is null)
                           then nullif(upper(btrim(regexp_replace(coalesce(p_values->>'legal_name', ''), '\s+', ' ', 'g'))), '')
                           else e.legal_name end,
         company_no = case when p_values ? 'company_no' and ('company_no' = any(v_changed) or nullif(btrim(coalesce(e.company_no, '')), '') is null) then nullif(btrim(coalesce(p_values->>'company_no', '')), '') else e.company_no end,
         company_no_old = case when p_values ? 'company_no_old' and ('company_no_old' = any(v_changed) or nullif(btrim(coalesce(e.company_no_old, '')), '') is null) then nullif(btrim(coalesce(p_values->>'company_no_old', '')), '') else e.company_no_old end,
         tin = case when p_values ? 'tin' and ('tin' = any(v_changed) or nullif(btrim(coalesce(e.tin, '')), '') is null) then nullif(btrim(coalesce(p_values->>'tin', '')), '') else e.tin end,
         sst_no = case when p_values ? 'sst_no' and ('sst_no' = any(v_changed) or nullif(btrim(coalesce(e.sst_no, '')), '') is null) then nullif(btrim(coalesce(p_values->>'sst_no', '')), '') else e.sst_no end,
         finance_email = case when p_values ? 'finance_email' and ('finance_email' = any(v_changed) or nullif(btrim(coalesce(e.finance_email, '')), '') is null) then nullif(lower(btrim(coalesce(p_values->>'finance_email', ''))), '') else e.finance_email end,
         billing_address = case when p_values ? 'billing_address' and ('billing_address' = any(v_changed) or nullif(btrim(coalesce(e.billing_address, '')), '') is null) then nullif(btrim(coalesce(p_values->>'billing_address', '')), '') else e.billing_address end,
         bill_contact_id = case when v_bc_set then v_bc else e.bill_contact_id end,
         updated_at = clock_timestamp()
   where e.id = v_ent;
  -- A client's first entity, made here, is carried to the client's own
  -- columns (audit 2026-10-30: the update changed nothing, so the mirror
  -- never ran).
  if v_new then perform public.billing_entity_put(v_ent, p_id); end if;
  update public.bukku_links x set held_at = coalesce(x.held_at, now())
   where x.kind = l.kind and x.record_id = l.record_id;

  if cardinality(v_changed) > 0 then
    select string_agg(v_words->>f, ', ' order by array_position(array['legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no',
             'person', 'finance_email', 'billing_address'], f))
      into v_t from unnest(v_changed) f;
    select x.name into v_who from public.team_members x where x.id = p_actor;
    v_detail := case p_mode when 'read' then 'Read from Bukku: ' when 'save' then 'Saved to Bukku: ' else 'Took Bukku''s details: ' end
                || v_t || ' · ' || coalesce(l.code, l.contact_id::text);
    v_who := case when p_mode = 'read' then 'Bukku' else coalesce(v_who, 'Bukku') end;
    if p_kind = 'entity' then
      perform public.bukku_file_entity(p_id, v_who, v_detail);
    else
      select x.name into v_name from public.clients x where x.id = p_id;
      insert into public.activity_log (actor, action, subject, detail) values (v_who, 'client.billing', v_name, v_detail);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'held', true, 'changed', to_jsonb(v_changed),
    'person_in', v_bc_set or nullif(btrim(coalesce(p_values->>'person', '')), '') is null);
end $$;
revoke all on function public.bukku_take(uuid, text, uuid, jsonb, text, text[], text) from public, anon, authenticated;
grant execute on function public.bukku_take(uuid, text, uuid, jsonb, text, text[], text) to service_role;

-- END OF BILLING REVIEW FIXES ------------------------------------------------

select public.functions_tidy();
