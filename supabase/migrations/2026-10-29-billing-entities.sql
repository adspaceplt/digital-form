-- ===========================================================================
-- BILLING ENTITIES — a brand billed by several companies, and a company
-- billing several brands (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29): listed clients deal through several companies
-- of their group ("ABC sdn bhd, DEF sdn bhd, EFG sdn bhd"), "one client
-- several entities, however allow to set the main"; and the reverse, one
-- company owning several brands, each its own client. Each entity keeps its
-- own billing contact; a BRN already held is kept apart, merged by hand.
--
-- WHAT IT ADDS
--   * `billing_entities`: a registered company that is billed (registered
--     name, BRN, old BRN, TIN, SST no., billing contact, finance email,
--     billing address). RLS on, no policy, no grant: read and written
--     through the functions below alone.
--   * `client_entities`: which brand (client) each entity bills, one marked
--     main a brand. RLS on, no policy, no grant.
--   * The main entity is the client's billing: its values are the client's
--     billing columns, kept equal both ways by trigger. Billing's own sheet
--     writes the client as before, and `clients_entity_sync` carries it to
--     the main entity (making one where none is held); an entity changed
--     carries itself to every brand it is the main of
--     (`billing_entity_put`). So every reader of a client's billing
--     (letters, the Active gate, Bukku, the details form) reads the main
--     entity, unchanged. A billing contact that is another brand's contact
--     is not carried to a brand it does not belong to: that brand's billing
--     contact follows its main contact.
--   * Each client holding any billing value now holds it as its main
--     entity, one entity a client (two clients with one BRN stay two).
--   * `client_entities_list(p_client)` (Clients: Billing View, the client in
--     scope): its entities, main first, each with the other brands it bills
--     that the caller sees and a count of the rest.
--   * `billing_entities_find(p_q)` (Clients: Billing View): entities by
--     registered name or BRN digits, ten at most, held to those billing a
--     brand the caller sees, or none.
--   * `client_entity_add(p_client, p_entity, p_values)`, `client_entity_save
--     (p_client, p_entity, p_values, p_expected)`, `client_entity_main
--     (p_client, p_entity)`, `client_entity_remove(p_client, p_entity)`:
--     Clients: Billing at Work, the client in scope at Work. Refused
--     `denied`, `not-found`, `taken` (already billing this brand), `no-name`,
--     `too-long`, `bad-email`, `bad-contact` (not a contact of a brand the
--     entity bills), `brn-taken` (with the entity holding it), `stale`
--     (changed since it was read, with the row), `main` (the main entity is
--     not removed: another is made main first). The first entity a brand
--     takes is its main. Filed `client.billing` under the client, naming
--     fields alone, never values, as Billing is filed.
--
-- ORDER: this file (SQL Editor: it holds `delete`), then the pages. A page
-- served before reads Billing as one entity, as now; a page served after on
-- a database without this file reads its main entity alone and offers no
-- Add entity (This needs a database update). Safe to run twice.
--
-- ROLLBACK (the client's billing columns keep the main entity's values)
--   drop trigger if exists clients_entity_sync on public.clients;
--   drop function if exists public.client_entity_remove(uuid, uuid);
--   drop function if exists public.client_entity_main(uuid, uuid);
--   drop function if exists public.client_entity_save(uuid, uuid, jsonb, timestamptz);
--   drop function if exists public.client_entity_add(uuid, uuid, jsonb);
--   drop function if exists public.billing_entities_find(text);
--   drop function if exists public.client_entities_list(uuid);
--   drop table if exists public.client_entities;
--   drop table if exists public.billing_entities;
--   drop function if exists public.clients_entity_sync();
--   drop function if exists public.billing_entity_mirror();
--   drop function if exists public.billing_entity_put(uuid, uuid);
--   drop function if exists public.billing_entity_json(uuid, uuid);
--   drop function if exists public.billing_entity_clean(jsonb);
--   drop function if exists public.billing_entity_may(uuid, text);
-- ===========================================================================

-- BILLING ENTITIES ----------------------------------------------------------

create table if not exists public.billing_entities (
  id              uuid primary key default gen_random_uuid(),
  legal_name      text,
  company_no      text,
  company_no_old  text,
  tin             text,
  sst_no          text,
  bill_contact_id uuid references public.client_contacts(id) on delete set null,
  finance_email   text,
  billing_address text,
  created_at      timestamptz not null default now(),
  created_by      uuid references public.team_members(id) on delete set null,
  updated_at      timestamptz not null default now()
);
alter table public.billing_entities enable row level security;
revoke all on table public.billing_entities from public, anon, authenticated;
create index if not exists billing_entities_brn_idx
  on public.billing_entities ((regexp_replace(coalesce(company_no, ''), '\D', '', 'g')));

create table if not exists public.client_entities (
  client_id uuid not null references public.clients(id) on delete cascade,
  entity_id uuid not null references public.billing_entities(id) on delete cascade,
  is_main   boolean not null default false,
  added_at  timestamptz not null default now(),
  added_by  uuid references public.team_members(id) on delete set null,
  primary key (client_id, entity_id)
);
alter table public.client_entities enable row level security;
revoke all on table public.client_entities from public, anon, authenticated;
create unique index if not exists client_entities_main_idx on public.client_entities (client_id) where is_main;
create index if not exists client_entities_entity_idx on public.client_entities (entity_id);

/* Clients: Billing at the level asked, the client in scope. Internal. */
create or replace function public.billing_entity_may(p_client uuid, p_level text)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.allowed('clients.billing', p_level)
     and public.client_seen(p_client, case when p_level = 'view' then 'view' else 'work' end)
$$;
revoke all on function public.billing_entity_may(uuid, text) from public, anon, authenticated;

/* An entity's values as typed, trimmed and held to their lengths; the
   registered name in capitals, as Billing keeps it. Internal. */
create or replace function public.billing_entity_clean(p_values jsonb)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_lim constant jsonb := '{"legal_name": 200, "company_no": 40, "company_no_old": 40, "tin": 40, "sst_no": 40,
                            "finance_email": 200, "billing_address": 600}';
  v_out jsonb := '{}'::jsonb;
  v_key text;
  v_val text;
begin
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  for v_key in select jsonb_object_keys(v_lim) loop
    v_val := nullif(btrim(coalesce(p_values ->> v_key, '')), '');
    if v_val is not null and length(v_val) > (v_lim ->> v_key)::int then
      return jsonb_build_object('error', 'too-long', 'field', v_key);
    end if;
    if v_key = 'legal_name' and v_val is not null then v_val := upper(v_val); end if;
    v_out := v_out || jsonb_build_object(v_key, v_val);
  end loop;
  if v_out ->> 'legal_name' is null then return jsonb_build_object('error', 'no-name'); end if;
  if v_out ->> 'finance_email' is not null and v_out ->> 'finance_email' !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    return jsonb_build_object('error', 'bad-email');
  end if;
  v_val := nullif(btrim(coalesce(p_values ->> 'bill_contact_id', '')), '');
  if v_val is not null and v_val !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return jsonb_build_object('error', 'bad-contact');
  end if;
  return v_out || jsonb_build_object('bill_contact_id', v_val);
end $$;
revoke all on function public.billing_entity_clean(jsonb) from public, anon, authenticated;

/* The entity's values carried to the brands it is the main of (one brand
   where `p_client` names it). A billing contact goes only to the brand it
   belongs to. Marked as a carry, so the client's own sync does not answer
   it. Internal. */
create or replace function public.billing_entity_put(p_entity uuid, p_client uuid default null)
returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  v_was text := coalesce(current_setting('adspace.entity_sync', true), '');
begin
  perform set_config('adspace.entity_sync', 'on', true);
  with t as (
    select ce.client_id, e.legal_name, e.company_no, e.company_no_old, e.tin, e.sst_no, e.finance_email,
           e.billing_address,
           case when e.bill_contact_id is not null and exists (
                  select 1 from public.client_contacts k where k.id = e.bill_contact_id and k.client_id = ce.client_id)
                then e.bill_contact_id end as bc
      from public.client_entities ce join public.billing_entities e on e.id = ce.entity_id
     where ce.entity_id = p_entity and ce.is_main and (p_client is null or ce.client_id = p_client)
  )
  update public.clients c
     set legal_name = t.legal_name, company_no = t.company_no, company_no_old = t.company_no_old, tin = t.tin,
         sst_no = t.sst_no, finance_email = t.finance_email, billing_address = t.billing_address,
         bill_contact_id = t.bc
    from t
   where c.id = t.client_id
     and (c.legal_name, c.company_no, c.company_no_old, c.tin, c.sst_no, c.finance_email, c.billing_address, c.bill_contact_id)
         is distinct from (t.legal_name, t.company_no, t.company_no_old, t.tin, t.sst_no, t.finance_email, t.billing_address, t.bc);
  perform set_config('adspace.entity_sync', v_was, true);
end $$;
revoke all on function public.billing_entity_put(uuid, uuid) from public, anon, authenticated;

create or replace function public.billing_entity_mirror()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.legal_name, new.company_no, new.company_no_old, new.tin, new.sst_no, new.bill_contact_id,
      new.finance_email, new.billing_address)
     is distinct from
     (old.legal_name, old.company_no, old.company_no_old, old.tin, old.sst_no, old.bill_contact_id,
      old.finance_email, old.billing_address) then
    perform public.billing_entity_put(new.id, null);
  end if;
  return null;
end $$;
revoke all on function public.billing_entity_mirror() from public, anon, authenticated;
create or replace trigger billing_entity_mirror after update on public.billing_entities
  for each row execute function public.billing_entity_mirror();

/* Billing's own sheet writes the client: the main entity follows, made at
   the first value where none is held. A carry from the entity is not
   answered. */
create or replace function public.clients_entity_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_ent uuid;
  v_was text := coalesce(current_setting('adspace.entity_sync', true), '');
begin
  if v_was = 'on' then return null; end if;
  if (new.legal_name, new.company_no, new.company_no_old, new.tin, new.sst_no, new.bill_contact_id,
      new.finance_email, new.billing_address)
     is not distinct from
     (old.legal_name, old.company_no, old.company_no_old, old.tin, old.sst_no, old.bill_contact_id,
      old.finance_email, old.billing_address) then
    return null;
  end if;
  select ce.entity_id into v_ent from public.client_entities ce where ce.client_id = new.id and ce.is_main;
  if v_ent is null then
    if nullif(btrim(coalesce(new.legal_name, '') || coalesce(new.company_no, '') || coalesce(new.company_no_old, '') ||
                    coalesce(new.tin, '') || coalesce(new.sst_no, '') || coalesce(new.finance_email, '') ||
                    coalesce(new.billing_address, '')), '') is null and new.bill_contact_id is null then
      return null;
    end if;
    insert into public.billing_entities (legal_name, company_no, company_no_old, tin, sst_no, bill_contact_id,
                                         finance_email, billing_address, created_by)
    values (new.legal_name, new.company_no, new.company_no_old, new.tin, new.sst_no, new.bill_contact_id,
            new.finance_email, new.billing_address, (public.ops_me()).id)
    returning id into v_ent;
    insert into public.client_entities (client_id, entity_id, is_main, added_by)
    values (new.id, v_ent, true, (public.ops_me()).id);
    return null;
  end if;
  perform set_config('adspace.entity_sync', 'on', true);
  -- Only what this write changed: another brand's choice (its billing
  -- contact) is never overwritten by a brand that never held it.
  update public.billing_entities e
     set legal_name = case when new.legal_name is distinct from old.legal_name then new.legal_name else e.legal_name end,
         company_no = case when new.company_no is distinct from old.company_no then new.company_no else e.company_no end,
         company_no_old = case when new.company_no_old is distinct from old.company_no_old then new.company_no_old else e.company_no_old end,
         tin = case when new.tin is distinct from old.tin then new.tin else e.tin end,
         sst_no = case when new.sst_no is distinct from old.sst_no then new.sst_no else e.sst_no end,
         bill_contact_id = case when new.bill_contact_id is distinct from old.bill_contact_id then new.bill_contact_id else e.bill_contact_id end,
         finance_email = case when new.finance_email is distinct from old.finance_email then new.finance_email else e.finance_email end,
         billing_address = case when new.billing_address is distinct from old.billing_address then new.billing_address else e.billing_address end,
         updated_at = now()
   where e.id = v_ent;
  -- `billing_entity_mirror` carries it to the other brands it is the main of.
  perform set_config('adspace.entity_sync', v_was, true);
  return null;
end $$;
revoke all on function public.clients_entity_sync() from public, anon, authenticated;
create or replace trigger clients_entity_sync
  after update of legal_name, company_no, company_no_old, tin, sst_no, bill_contact_id, finance_email, billing_address
  on public.clients
  for each row execute function public.clients_entity_sync();

/* Each client's billing as its main entity, once. */
do $$
declare
  r record;
  v_ent uuid;
begin
  for r in
    select c.* from public.clients c
     where not exists (select 1 from public.client_entities ce where ce.client_id = c.id)
       and (nullif(btrim(coalesce(c.legal_name, '') || coalesce(c.company_no, '') || coalesce(c.company_no_old, '') ||
                         coalesce(c.tin, '') || coalesce(c.sst_no, '') || coalesce(c.finance_email, '') ||
                         coalesce(c.billing_address, '')), '') is not null
            or c.bill_contact_id is not null)
  loop
    insert into public.billing_entities (legal_name, company_no, company_no_old, tin, sst_no, bill_contact_id,
                                         finance_email, billing_address)
    values (r.legal_name, r.company_no, r.company_no_old, r.tin, r.sst_no, r.bill_contact_id,
            r.finance_email, r.billing_address)
    returning id into v_ent;
    insert into public.client_entities (client_id, entity_id, is_main) values (r.id, v_ent, true);
  end loop;
end $$;

/* One entity as a brand's pane reads it: the other brands it bills that
   the caller sees, and how many more. Internal. */
create or replace function public.billing_entity_json(p_entity uuid, p_client uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id,
    'main', coalesce((select ce.is_main from public.client_entities ce
                       where ce.entity_id = e.id and ce.client_id = p_client), false),
    'legal_name', e.legal_name, 'company_no', e.company_no, 'company_no_old', e.company_no_old,
    'tin', e.tin, 'sst_no', e.sst_no, 'bill_contact_id', e.bill_contact_id,
    'bill_contact', (select jsonb_build_object('name', k.name, 'salutation', k.salutation,
                                               'client_id', k.client_id,
                                               'client', (select x.name from public.clients x where x.id = k.client_id))
                       from public.client_contacts k where k.id = e.bill_contact_id and k.archived_at is null),
    'finance_email', e.finance_email, 'billing_address', e.billing_address, 'updated_at', e.updated_at,
    'missing', to_jsonb(array_remove(array[
        case when coalesce(btrim(e.legal_name), '') = '' then 'legal_name' end,
        case when coalesce(btrim(e.company_no), '') = '' then 'company_no' end,
        case when coalesce(btrim(e.billing_address), '') = '' then 'billing_address' end], null)),
    'brands', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'slug', x.slug,
                                                            'code', x.client_code) order by x.name)
                          from public.client_entities ce join public.clients x on x.id = ce.client_id
                         where ce.entity_id = e.id and ce.client_id is distinct from p_client
                           and public.client_seen(x.id, 'view')), '[]'::jsonb),
    'hidden', (select count(*) from public.client_entities ce
                where ce.entity_id = e.id and ce.client_id is distinct from p_client
                  and not public.client_seen(ce.client_id, 'view')))
    from public.billing_entities e where e.id = p_entity
$$;
revoke all on function public.billing_entity_json(uuid, uuid) from public, anon, authenticated;

create or replace function public.client_entities_list(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.billing_entity_may(p_client, 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('entities', coalesce((
    select jsonb_agg(public.billing_entity_json(ce.entity_id, p_client)
                     order by ce.is_main desc, e.legal_name nulls last, ce.added_at)
      from public.client_entities ce join public.billing_entities e on e.id = ce.entity_id
     where ce.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.client_entities_list(uuid) from public, anon;
grant execute on function public.client_entities_list(uuid) to authenticated;

create or replace function public.billing_entities_find(p_q text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q text := btrim(coalesce(p_q, ''));
  v_like text;
  v_digits text := regexp_replace(coalesce(p_q, ''), '\D', '', 'g');
begin
  if not public.allowed('clients.billing', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_q) < 2 then return jsonb_build_object('entities', '[]'::jsonb); end if;
  v_like := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return jsonb_build_object('entities', coalesce((
    select jsonb_agg(x.j order by x.n) from (
      select public.billing_entity_json(e.id, null) as j, e.legal_name as n
        from public.billing_entities e
       where (e.legal_name ilike v_like
              or (length(v_digits) >= 4 and regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') like '%' || v_digits || '%'))
         and (not exists (select 1 from public.client_entities ce where ce.entity_id = e.id)
              or exists (select 1 from public.client_entities ce
                          where ce.entity_id = e.id and public.client_seen(ce.client_id, 'view')))
       order by e.legal_name
       limit 10) x), '[]'::jsonb));
end $$;
revoke all on function public.billing_entities_find(text) from public, anon;
grant execute on function public.billing_entities_find(text) to authenticated;

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
    if exists (select 1 from public.client_entities ce where ce.entity_id = v_ent)
       and not exists (select 1 from public.client_entities ce
                        where ce.entity_id = v_ent and public.client_seen(ce.client_id, 'view')) then
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
  v_main := not exists (select 1 from public.client_entities ce where ce.client_id = p_client and ce.is_main);
  insert into public.client_entities (client_id, entity_id, is_main, added_by) values (p_client, v_ent, v_main, me.id);
  if v_main then perform public.billing_entity_put(v_ent, p_client); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name,
          case when p_entity is null then 'Billing entity added' else 'Billing entity added, already held' end
          || case when v_main then ' · main' else '' end);
  return jsonb_build_object('ok', true, 'id', v_ent, 'main', v_main);
end $$;
revoke all on function public.client_entity_add(uuid, uuid, jsonb) from public, anon;
grant execute on function public.client_entity_add(uuid, uuid, jsonb) to authenticated;

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
  values (me.name, 'client.billing', v_name, 'Main billing entity changed');
  return jsonb_build_object('ok', true, 'was', v_was);
end $$;
revoke all on function public.client_entity_main(uuid, uuid) from public, anon;
grant execute on function public.client_entity_main(uuid, uuid) to authenticated;

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
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name, 'Billing entity removed');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_entity_remove(uuid, uuid) from public, anon;
grant execute on function public.client_entity_remove(uuid, uuid) to authenticated;

-- END OF BILLING ENTITIES ---------------------------------------------------

select public.functions_tidy();
