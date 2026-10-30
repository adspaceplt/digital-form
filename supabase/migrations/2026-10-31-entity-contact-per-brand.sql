-- ===========================================================================
-- A BRAND'S OWN BILLING CONTACT — one entity, shared or per brand (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31: "Could be shared or different contact for
-- different brand"): a billing entity held one billing contact for every
-- brand it bills, so a brand choosing its own wiped another brand's choice.
--
-- WHAT IT CHANGES
--   `client_entities.bill_contact_id`: a brand's own billing contact for an
--   entity (one of its own contacts); empty, it follows the entity's shared
--   one (`billing_entities.bill_contact_id`), else its live main contact.
--   `entity_contact(p_entity, p_client)` (internal) answers that order;
--   `entity_contact(p_entity)`, Bukku's billing person, is unchanged.
--   `client_entity_contact(p_client, p_entity, p_contact, p_every)`:
--   Clients: Billing at Work, the client in scope (`billing_entity_may`);
--   `p_every` sets the shared contact (any brand's, `held` where Bukku holds
--   the entity) and lets this brand follow it, else sets this brand's own
--   (`bad-contact`). A brand's own Billing sheet sets its own where the
--   entity bills other brands too (`clients_entity_sync`), and the brand's
--   billing columns follow its own, else the shared one where that is its
--   contact (`billing_entity_put`). The letter's Attn (`issue_letter`), the
--   overdue reminder (`invoice_recipient`, `invoice_entity_recipient`) and
--   the pane (`billing_entity_json` `own_contact_id`, `contact`) read it.
--
-- ORDER: this file, then the pages. A page served before saves the shared
-- contact as before. Safe to run twice.
--
-- ROLLBACK: run the earlier definitions again (BILLING ENTITIES, BILL TO,
-- BUKKU BY ENTITY, OVERDUE INVOICE REMINDERS, SALUTATION SAID ONCE); the
-- column may stay.
-- ===========================================================================

-- No foreign key: a contact removed for good leaves the choice pointing at
-- nothing, which every reading passes over.
alter table public.client_entities add column if not exists bill_contact_id uuid;

-- A brand's billing contact that differs from its primary entity's shared
-- one becomes its own, once.
update public.client_entities ce set bill_contact_id = c.bill_contact_id
  from public.clients c, public.billing_entities e
 where c.id = ce.client_id and e.id = ce.entity_id and ce.is_main
   and ce.bill_contact_id is null and c.bill_contact_id is not null
   and c.bill_contact_id is distinct from e.bill_contact_id;

/* A brand's billing contact for an entity: its own choice, else the
   entity's shared one, else its live main contact. Internal. */
create or replace function public.entity_contact(p_entity uuid, p_client uuid)
returns public.client_contacts
language sql stable security definer set search_path = public as $$
  select k.* from public.client_contacts k
   where p_entity is not null and k.archived_at is null
     and (k.id = (select ce.bill_contact_id from public.client_entities ce
                   where ce.entity_id = p_entity and ce.client_id = p_client)
          or k.id = (select e.bill_contact_id from public.billing_entities e where e.id = p_entity)
          or (k.client_id = p_client and k.is_primary))
   order by (k.id is not distinct from (select ce.bill_contact_id from public.client_entities ce
                                         where ce.entity_id = p_entity and ce.client_id = p_client)) desc,
            (k.id is not distinct from (select e.bill_contact_id from public.billing_entities e where e.id = p_entity)) desc,
            k.name
   limit 1
$$;
revoke all on function public.entity_contact(uuid, uuid) from public, anon, authenticated;

/* The entity's values carried to the brands it is the main of (one brand
   where `p_client` names it). A brand's billing contact is its own choice
   for the entity, else the entity's shared one where that is the brand's
   own contact (2026-10-31). Marked as a carry, so the client's own sync
   does not answer it. Internal. */
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
           coalesce(
             (select k.id from public.client_contacts k
               where k.id = ce.bill_contact_id and k.client_id = ce.client_id and k.archived_at is null),
             case when e.bill_contact_id is not null and exists (
                    select 1 from public.client_contacts k where k.id = e.bill_contact_id and k.client_id = ce.client_id)
                  then e.bill_contact_id end) as bc
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

/* Billing's own sheet writes the client: the main entity follows, made at
   the first value where none is held. A carry from the entity is not
   answered. */
create or replace function public.clients_entity_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_ent uuid;
  v_own boolean := false;
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
  -- A billing contact chosen on a brand's own sheet is that brand's own
  -- choice where the entity bills other brands too, and the entity's
  -- shared one where it bills this brand alone (2026-10-31).
  if new.bill_contact_id is distinct from old.bill_contact_id then
    v_own := exists (select 1 from public.client_entities ce where ce.entity_id = v_ent and ce.client_id <> new.id);
    update public.client_entities ce set bill_contact_id = case when v_own then new.bill_contact_id end
     where ce.client_id = new.id and ce.entity_id = v_ent;
  end if;
  -- Only what this write changed: another brand's choice (its billing
  -- contact) is never overwritten by a brand that never held it.
  update public.billing_entities e
     set legal_name = case when new.legal_name is distinct from old.legal_name then new.legal_name else e.legal_name end,
         company_no = case when new.company_no is distinct from old.company_no then new.company_no else e.company_no end,
         company_no_old = case when new.company_no_old is distinct from old.company_no_old then new.company_no_old else e.company_no_old end,
         tin = case when new.tin is distinct from old.tin then new.tin else e.tin end,
         sst_no = case when new.sst_no is distinct from old.sst_no then new.sst_no else e.sst_no end,
         bill_contact_id = case when new.bill_contact_id is distinct from old.bill_contact_id and not v_own
                                then new.bill_contact_id else e.bill_contact_id end,
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
    'own_contact_id', (select ce.bill_contact_id from public.client_entities ce
                        where ce.entity_id = e.id and ce.client_id = p_client),
    'contact', (select jsonb_build_object('id', k.id, 'name', k.name, 'salutation', k.salutation,
                                          'client_id', k.client_id,
                                          'client', (select x.name from public.clients x where x.id = k.client_id))
                  from public.entity_contact(e.id, p_client) k where p_client is not null and k.id is not null),
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

create or replace function public.invoice_entity_recipient(p_entity uuid, p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e public.billing_entities;
  k public.client_contacts;
begin
  select * into e from public.billing_entities x where x.id = p_entity;
  if e.id is null then return null; end if;
  k := public.entity_contact(e.id, coalesce(p_client, public.entity_home_client(e.id)));
  return jsonb_build_object(
    'name', nullif(public.contact_named(k.salutation, k.name), ''),
    'email', nullif(btrim(coalesce(k.email, '')), ''),
    'cc', case when nullif(btrim(coalesce(e.finance_email, '')), '') is not null
                and lower(btrim(e.finance_email)) is distinct from lower(btrim(coalesce(k.email, '')))
               then btrim(e.finance_email) end,
    'company', coalesce(nullif(btrim(coalesce(e.legal_name, '')), ''),
                        (select c.name from public.clients c where c.id = coalesce(p_client, public.entity_home_client(e.id)))));
end $$;
revoke all on function public.invoice_entity_recipient(uuid, uuid) from public, anon, authenticated;

create or replace function public.invoice_recipient_for(p_client uuid, p_contact bigint)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ent uuid := public.bukku_contact_entity(p_contact);
  v_r jsonb := public.invoice_recipient(p_client);
begin
  if v_ent is not null and exists (select 1 from public.client_entities ce where ce.client_id = p_client and ce.entity_id = v_ent)
     and (v_ent is distinct from public.client_main_entity(p_client) or v_r->>'email' is null) then
    return public.invoice_entity_recipient(v_ent, p_client);
  end if;
  return v_r;
end $$;
revoke all on function public.invoice_recipient_for(uuid, bigint) from public, anon, authenticated;

create or replace function public.invoice_recipient(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients;
  k public.client_contacts;
begin
  select * into c from public.clients x where x.id = p_client;
  if c.id is null then return null; end if;
  -- Its billing contact for its primary entity: its own choice, else the
  -- entity's shared one, else its live main contact (2026-10-31).
  k := public.entity_contact(public.client_main_entity(c.id), c.id);
  if k.id is null then
    select * into k from public.client_contacts x
     where x.client_id = c.id and x.archived_at is null and (x.id = c.bill_contact_id or x.is_primary)
     order by (x.id = c.bill_contact_id) desc limit 1;
  end if;
  return jsonb_build_object(
    'name', nullif(public.contact_named(k.salutation, k.name), ''),
    'email', nullif(btrim(coalesce(k.email, '')), ''),
    'cc', case when nullif(btrim(coalesce(c.finance_email, '')), '') is not null
                and lower(btrim(c.finance_email)) is distinct from lower(btrim(coalesce(k.email, '')))
               then btrim(c.finance_email) end,
    'company', coalesce(nullif(btrim(coalesce(c.legal_name, '')), ''), c.name));
end $$;
revoke all on function public.invoice_recipient(uuid) from public, anon, authenticated;


/* A brand's billing contact for an entity it bills: its own (one of its
   contacts), or, with `p_every`, the entity's shared one (a contact of any
   brand it bills), which this brand then follows. Empty is the next in
   line: the shared one, else the main contact. */
create or replace function public.client_entity_contact(p_client uuid, p_entity uuid, p_contact uuid, p_every boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_name text;
  v_was  public.billing_entities;
  v_own  uuid;
  v_at   timestamptz;
begin
  if not public.billing_entity_may(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  select ce.bill_contact_id into v_own from public.client_entities ce
   where ce.client_id = p_client and ce.entity_id = p_entity for update;
  if v_name is null or not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into v_was from public.billing_entities e where e.id = p_entity for update;
  if p_contact is not null and not exists (
       select 1 from public.client_contacts k
        where k.id = p_contact and k.archived_at is null
          and (k.client_id = p_client
               or (coalesce(p_every, false)
                   and k.client_id in (select ce.client_id from public.client_entities ce where ce.entity_id = p_entity)))) then
    return jsonb_build_object('error', 'bad-contact');
  end if;
  if coalesce(p_every, false) then
    if v_was.bill_contact_id is not distinct from p_contact and v_own is null then
      return jsonb_build_object('ok', true, 'updated_at', v_was.updated_at);
    end if;
    -- Bukku's billing person is the shared one: changed in Bukku alone.
    if v_was.bill_contact_id is distinct from p_contact and exists (
         select 1 from public.bukku_links l where l.kind = 'entity' and l.record_id = p_entity and l.held_at is not null) then
      return jsonb_build_object('error', 'held');
    end if;
    update public.client_entities ce set bill_contact_id = null
     where ce.client_id = p_client and ce.entity_id = p_entity;
    update public.billing_entities e set bill_contact_id = p_contact, updated_at = clock_timestamp()
     where e.id = p_entity and e.bill_contact_id is distinct from p_contact;
  else
    if v_own is not distinct from p_contact then
      return jsonb_build_object('ok', true, 'updated_at', v_was.updated_at);
    end if;
    update public.client_entities ce set bill_contact_id = p_contact
     where ce.client_id = p_client and ce.entity_id = p_entity;
  end if;
  perform public.billing_entity_put(p_entity, p_client);
  select e.updated_at into v_at from public.billing_entities e where e.id = p_entity;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name,
          'Billing entity edited: ' || case when coalesce(p_every, false) then 'Shared billing contact' else 'Billing contact' end);
  return jsonb_build_object('ok', true, 'updated_at', v_at);
end $$;
revoke all on function public.client_entity_contact(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.client_entity_contact(uuid, uuid, uuid, boolean) to authenticated;

/* The one-argument reading (Bukku's) stays; a brand's reminder names its own. */
create or replace function public.invoice_entity_recipient(p_entity uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select public.invoice_entity_recipient(p_entity, null)
$$;
revoke all on function public.invoice_entity_recipient(uuid) from public, anon, authenticated;

create or replace function public.issue_letter(
  p_client    uuid,
  p_services  uuid[],
  p_idem      text,
  p_subtotal  numeric,
  p_tax       numeric,
  p_total     numeric,
  p_deal      jsonb   default '{}'::jsonb,
  p_replaces  uuid    default null,
  p_renewal   boolean default false,
  /* A reference somebody typed. Blank is the ordinary case and the counter
     below makes the number; where one is typed it is checked against every
     document that stands and the counter is not advanced, so filling a gap
     by hand never costs the next letter its place in the sequence. */
  p_serial    text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  ct     public.client_contacts%rowtype;
  me     public.team_members%rowtype;
  v_ym   text;
  v_seq  int;
  v_try  int;
  v_no   text;
  v_id   uuid;
  v_lines jsonb;
  v_n    int;
  v_bad  int;
  v_old  public.client_documents%rowtype;
  v_term int;
  v_each numeric;
  v_etax numeric;
  v_once numeric;
  v_otax numeric;
  v_sub  numeric;
  v_tax  numeric;
  v_tot  numeric;
  v_pct  numeric;
  v_qid  uuid;
  v_q    public.quotations%rowtype;
  v_tp   numeric;
  v_tpn  int;
  v_tadj boolean;
  v_qterm int;
  v_msub numeric;
  v_span numeric;
  v_even boolean;
  v_qt   jsonb;
  v_month boolean;
  v_terms jsonb;
  v_ent  public.billing_entities%rowtype;
  v_ect  public.client_contacts%rowtype;
begin
  if not public.allowed('clients.documents') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if p_client is null or p_services is null or array_length(p_services, 1) is null then
    return jsonb_build_object('error', 'no-lines');
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;

  -- Bill to (2026-10-29): a billing entity of this client other than its
  -- main, named in the deal, is the one the letter bills: its registered
  -- name, numbers, address and finance email stand in for the client's in
  -- the snapshot, and its billing contact is the letter's Attn where one is
  -- set and live. None named is the main entity, the client's own billing.
  if nullif(btrim(coalesce(p_deal ->> 'entity', '')), '') is not null then
    if (p_deal ->> 'entity') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('error', 'bad-entity');
    end if;
    select e.* into v_ent from public.billing_entities e
      join public.client_entities ce on ce.entity_id = e.id and ce.client_id = p_client
     where e.id = (p_deal ->> 'entity')::uuid;
    if v_ent.id is null then return jsonb_build_object('error', 'bad-entity'); end if;
    if coalesce(btrim(v_ent.legal_name), '') = '' or coalesce(btrim(v_ent.company_no), '') = ''
       or coalesce(btrim(v_ent.billing_address), '') = '' then
      return jsonb_build_object('error', 'entity-incomplete');
    end if;
    cl.legal_name := v_ent.legal_name; cl.company_no := v_ent.company_no;
    cl.company_no_old := v_ent.company_no_old; cl.tin := v_ent.tin; cl.sst_no := v_ent.sst_no;
    cl.finance_email := v_ent.finance_email; cl.billing_address := v_ent.billing_address;
  end if;

  -- The letter's own terms, one point a line, kept with what it was issued
  -- with and printed under TERMS after the term and the validity
  -- (2026-10-23): ten at most, each 1 to 400 characters.
  v_terms := coalesce((select jsonb_agg(btrim(t)) from jsonb_array_elements_text(
               case when jsonb_typeof(p_deal -> 'terms') = 'array' then p_deal -> 'terms' else '[]'::jsonb end) t
             where btrim(t) <> ''), '[]'::jsonb);
  if jsonb_array_length(v_terms) > 10
     or exists (select 1 from jsonb_array_elements_text(v_terms) t where length(t) > 400) then
    return jsonb_build_object('error', 'bad-terms');
  end if;

  -- The Client ID is what the serial is built from, so there is no letter
  -- without one. Staff enter it on the record; nothing invents it. A typed
  -- reference needs no code, because nothing is being built.
  v_no := nullif(btrim(coalesce(p_serial, '')), '');
  if v_no is null and coalesce(btrim(cl.client_code), '') = '' then
    return jsonb_build_object('error', 'no-client-code');
  end if;

  -- The same submission, pressed twice, is one letter. Answered before any
  -- number is reserved, so a double click cannot spend a serial either.
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.client_documents
      where client_id = p_client and idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
    end if;
  end if;

  -- A typed reference is checked before anything is written: the same shape
  -- the Register accepts, and refused where a document still holds it.
  if v_no is not null then
    if v_no !~ '^[A-Za-z0-9/._-]{3,40}$' then
      return jsonb_build_object('error', 'serial-shape');
    end if;
    if public.serial_taken(v_no) then
      return jsonb_build_object('error', 'serial-taken');
    end if;
  end if;

  -- Every id must be this client's own live line, and in a state this letter
  -- may carry: To quote always, Confirmed only on a deliberate renewal.
  select count(*) into v_bad from unnest(p_services) s(id)
    left join public.client_services cs
      on cs.id = s.id and cs.client_id = p_client and cs.archived_at is null
    where cs.id is null
       or (cs.state = 'confirmed' and not p_renewal)
       or cs.state not in ('quoted', 'confirmed');
  if v_bad > 0 then return jsonb_build_object('error', 'bad-lines'); end if;

  -- A line already on a live letter is not offered again by accident. The way
  -- through is to void that letter, or to name it as the one being replaced.
  select count(*) into v_bad
    from public.client_document_services m
    join public.client_documents d on d.id = m.document_id
   where m.service_id = any(p_services)
     and d.voided_at is null
     and d.superseded_by is null
     and d.verified_at is null
     and (p_replaces is null or d.id <> p_replaces);
  if v_bad > 0 then return jsonb_build_object('error', 'already-quoted'); end if;

  if p_replaces is not null then
    select * into v_old from public.client_documents
      where id = p_replaces and client_id = p_client;
    if v_old.id is null then return jsonb_build_object('error', 'no-replaces'); end if;
    if v_old.verified_at is not null then return jsonb_build_object('error', 'replaces-verified'); end if;
  end if;

  select * into ct from public.client_contacts
    where client_id = p_client and archived_at is null
    order by (id = cl.bill_contact_id) desc, is_primary desc, name limit 1;
  -- The brand's billing contact for the entity billed (the one named, else
  -- its primary): its own choice, else the entity's shared one, else its
  -- live main contact (2026-10-31).
  v_ect := public.entity_contact(coalesce(v_ent.id, public.client_main_entity(p_client)), p_client);
  if v_ect.id is not null then ct := v_ect; end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  -- A letter is signed by a person. issued_by is this row's name, so a team
  -- row named "Superadmin" printed that word under ADSPACE PLT on a client's
  -- letterhead. Refuse rather than draw a permission as a signatory.
  if not public.issuer_name_ok(me.name) then
    return jsonb_build_object('error', 'issuer-name', 'name', coalesce(me.name, ''));
  end if;

  -- The snapshot is built from the stored rows, never from what the browser
  -- sent: the words on a letter are the words the record held at that moment.
  select jsonb_agg(jsonb_build_object(
           'label', cs.label, 'unit', coalesce(cs.unit, ''), 'note', coalesce(cs.note, ''),
           'detail', coalesce(cs.detail, ''), 'state', cs.state,
           'qty', cs.qty, 'rate', cs.rate,
           'tenure', greatest(1, coalesce(cs.tenure, 1)),
           'start_on', coalesce(cs.start_on, ''),
           -- The line's own answer to whether its term prices it. Written into
           -- the snapshot because the letter is redrawn from it, and a letter
           -- must print the same figure every time it is drawn. A snapshot
           -- taken before this key existed carries none, which money.js reads
           -- as on, so those letters redraw as they were issued.
           'term_adjust', coalesce(cs.term_adjust, false),
           -- And the percentage that tick applies, so a later rate card can
           -- never move a figure this letter printed. Null on a line quoted
           -- before the column existed, which money.js reads as that card.
           'term_pct', cs.term_pct,
           'tax', cl.sst_applies is not false,
           -- The line's own tax code and its rate as issued (2026-10-22);
           -- none is the client's SST, as before.
           'tax_code', cs.tax_code,
           'tax_pct', (select t.rate from public.tax_codes t where t.code = cs.tax_code),
           'service_id', cs.id)
           order by cs.created_at)
    into v_lines
    from public.client_services cs
   where cs.id = any(p_services);
  if v_lines is null then return jsonb_build_object('error', 'no-lines'); end if;
  /* A line's tax code is one the team holds and offers (2026-10-22). */
  if exists (select 1 from public.client_services cs
              where cs.id = any(p_services) and cs.tax_code is not null
                and not exists (select 1 from public.tax_codes t where t.code = cs.tax_code and t.active)) then
    return jsonb_build_object('error', 'bad-tax');
  end if;

  /* The price is the database's (audit S4, 2026-10-10), worked as the
     letter draws it (js/documents.js priceOf, js/money.js rateFor): each
     line's rate with its term on it, rounded to the cent. Where every line
     of more than a month shares one term, those lines are priced by the
     month and times the term, and a line of one month is a one-off item
     with its own SST (2026-10-15: a one-off item beside them no longer
     turns the letter into one whole total); otherwise every line is its
     whole amount. SST at the rate in force today unless the client is
     exempt. The page's figures are kept only where they agree to the sen,
     so a line changed since the sheet opened, or a figure typed in a
     browser, is refused (`stale`) and the sheet reads the lines again. */
  select case when count(distinct greatest(1, coalesce(cs.tenure, 1)))
                     filter (where greatest(1, coalesce(cs.tenure, 1)) > 1) = 1
              then max(greatest(1, coalesce(cs.tenure, 1))) else 0 end
    into v_term
    from public.client_services cs where cs.id = any(p_services);
  /* A letter whose every line came from one quotation is priced as that
     quotation was (audit F, 2026-10-17), exactly as `quote_price` and
     `quote_adjust` total it (2026-10-17, the review's finding 7): a line
     the quotation bills by the month (`quotation_offer` ticks its term) is
     a monthly line whatever months Build quote gave it, its percentage
     taken once on their subtotal; a line with no term is one-off; SST at
     the quotation's rate. The page's figures are held to the same price
     (js/documents.js priceOf). */
  select case when count(*) filter (where cs.quotation_id is null) = 0
                   and count(distinct cs.quotation_id) = 1 then min(cs.quotation_id::text)::uuid end,
         count(distinct coalesce(cs.term_pct, 0)) filter (where coalesce(cs.term_adjust, false)),
         coalesce(bool_and(greatest(1, coalesce(cs.tenure, 1)) = 1) filter (where not coalesce(cs.term_adjust, false)), true),
         coalesce(max(cs.term_pct) filter (where coalesce(cs.term_adjust, false)), 0)
    into v_qid, v_tpn, v_tadj, v_tp
    from public.client_services cs where cs.id = any(p_services);
  /* Only while the quotation still stands (2026-10-17, the review's
     finding 2): unexpired by Malaysia's day and not removed. A renewal, or a
     letter replacing one after the quotation lapsed, is priced on today's
     rates, as any other letter. */
  if v_qid is not null and coalesce(v_tpn, 0) <= 1 and v_tadj and not coalesce(p_renewal, false) then
    select * into v_q from public.quotations q
     where q.id = v_qid and q.removed_at is null
       and q.valid_until >= (timezone('Asia/Kuala_Lumpur', now()))::date;
  end if;
  if v_q.id is not null then
    /* As quote_adjust totals it: the monthly lines' subtotal of quantity ×
       rate, the percentage once on it; where every one runs the quotation's
       term, a month's excl. SST, its SST rounded once, times the term; where
       Build quote gave a line months of its own, the whole span (each line's
       amount × its months) with the percentage and SST taken once on it.
       One-off lines and their SST apart. */
    v_qterm := greatest(1, coalesce((v_q.totals->>'term')::int, 1));
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce((v_q.totals->>'sst_pct')::numeric, 0) end;
    /* The lines as the quotation reads them (a line with its term ticked is
       monthly, on its own months), totalled by the one calculation every
       quotation shares (2026-10-18). */
    v_qt := public.quote_totals(
      (select coalesce(jsonb_agg(jsonb_build_object(
                'basis', case when coalesce(cs.term_adjust, false) then 'month' else 'once' end,
                'qty', coalesce(cs.qty, 0), 'rate', coalesce(cs.rate, 0),
                'months', greatest(1, coalesce(cs.tenure, 1)),
                'sst', (select t.rate from public.tax_codes t where t.code = cs.tax_code))), '[]'::jsonb)
         from public.client_services cs where cs.id = any(p_services)),
      v_qterm, v_tp, v_pct);
    v_month := jsonb_typeof(v_qt->'month') = 'object';
    v_once := coalesce((v_qt->'once'->>'subtotal')::numeric, 0);
    v_otax := coalesce((v_qt->'once'->>'sst')::numeric, 0);
    if not v_month then
      v_sub := round(v_once, 2);
      v_tax := v_otax;
    elsif (v_qt->>'even')::boolean then
      v_each := (v_qt->'month'->>'excl')::numeric;
      v_etax := (v_qt->'month'->>'sst')::numeric;
      v_sub := round(v_each * v_qterm + v_once, 2);
      v_tax := v_etax * v_qterm + v_otax;
    else
      v_sub := (v_qt->>'span_excl')::numeric + round(v_once, 2);
      v_tax := (v_qt->>'span_incl')::numeric + round(v_once, 2) + v_otax - v_sub;
    end if;
    v_tot := v_sub + v_tax;
    /* The letter keeps what it was priced on, so a redraw prints the same:
       the quotation, its SST and its term (a snapshot with no `quote_term`
       was priced before this, and redraws as it was). */
    select jsonb_agg(l.e || jsonb_build_object('quotation_id', v_qid, 'quote_sst', v_pct, 'quote_term', v_qterm) order by l.n)
      into v_lines from jsonb_array_elements(v_lines) with ordinality l(e, n);
  else
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce(public.app_setting('sst_pct', (timezone('Asia/Kuala_Lumpur', now()))::date), 0) end;
    /* Each line at its own SST rate (2026-10-22): its tax code's, else the
       client's. The SST is worked a rate at a time, rounded once each, so
       a letter on one rate prices as it always did. */
    with x as (
      select greatest(1, coalesce(cs.tenure, 1)) as n,
             coalesce(cs.qty, 0) *
             round(coalesce(cs.rate, 0) *
               case when cs.term_adjust is false then 1
                    when cs.term_pct is not null then 1 + cs.term_pct / 100
                    else case greatest(1, coalesce(cs.tenure, 1))
                           when 3 then 1 / 0.9 when 12 then 0.95 when 24 then 0.9 else 1 end
               end, 2) as v,
             coalesce((select t.rate from public.tax_codes t where t.code = cs.tax_code), v_pct) as r
        from public.client_services cs where cs.id = any(p_services)
    ), y as (
      select r,
             coalesce(sum(v) filter (where v_term > 0 and n = v_term), 0) as e,
             coalesce(sum(v * n) filter (where v_term = 0 or n <> v_term), 0) as o
        from x group by r
    )
    select coalesce(sum(e), 0), coalesce(sum(o), 0),
           coalesce(sum(round(e * r) / 100), 0), coalesce(sum(round(o * r) / 100), 0)
      into v_each, v_once, v_etax, v_otax
      from y;
    v_sub := round(v_each * greatest(v_term, 1), 2) + round(v_once, 2);
    v_tax := round(v_etax * greatest(v_term, 1), 2) + v_otax;
    v_tot := round(round(v_each + v_etax, 2) * greatest(v_term, 1), 2) + round(v_once + v_otax, 2);
  end if;
  if abs(coalesce(p_subtotal, -1) - v_sub) > 0.01 or abs(coalesce(p_tax, -1) - v_tax) > 0.01
     or abs(coalesce(p_total, -1) - v_tot) > 0.01 then
    return jsonb_build_object('error', 'stale', 'subtotal', v_sub, 'tax', v_tax, 'total', v_tot);
  end if;

  -- A typed reference spends no sequence number: the counter is the office's
  -- record of how many letters it has issued this month, and a person filling
  -- a gap by hand has not issued one more.
  if v_no is null then
    -- The month is Malaysian, because the office that numbers the letter is.
    v_ym := to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM');

    -- The counter still advances on every automatic issue, and the upsert's
    -- row lock is what makes the scan below safe: a second issuer blocks here
    -- until the first has committed its letter, so the two never read the same
    -- gap as free. What the counter gives is a bound to scan within, not the
    -- number itself.
    insert into public.client_document_seq (client_id, ym, next_val)
         values (p_client, v_ym, 2)
    on conflict (client_id, ym)
      do update set next_val = public.client_document_seq.next_val + 1
      returning next_val - 1 into v_seq;

    -- The lowest free slot, not the counter's own value. A letter removed
    -- releases its reference (serial_taken stopped counting deletions on
    -- 2026-09-20), and without this the automatic path still counted upward
    -- past the gap: a client whose first two letters were issued in testing
    -- and removed started at 03 for ever. The counter is at least the number
    -- of letters issued this month, so a free slot exists at or below it
    -- unless somebody has typed references over the same range by hand; the
    -- cap covers that and refuses rather than looping.
    --
    -- Two digits is the floor, not the ceiling: the hundredth letter of a month
    -- widens to three rather than wrapping. Not lpad(): Postgres pads AND
    -- truncates to the width it is given, so lpad('100', 2, '0') is '10' and the
    -- hundredth letter would collide with the tenth.
    v_try := 1;
    loop
      v_no := 'AQL/' || cl.client_code || '/' || v_ym ||
              case when v_try < 100 then lpad(v_try::text, 2, '0') else v_try::text end;
      exit when not public.serial_taken(v_no);
      v_try := v_try + 1;
      if v_try > greatest(v_seq, 1) + 200 then
        return jsonb_build_object('error', 'no-serial');
      end if;
    end loop;
  end if;

  insert into public.client_documents
    (client_id, kind, number, issued_at, market, subtotal, tax, total,
     bill_to, lines, issued_by, client_code, idem_key)
  values
    (p_client, 'offer', v_no, (timezone('Asia/Kuala_Lumpur', now()))::date,
     public.client_bill_market(cl.market, cl.bill_sgd),
     round(coalesce(p_subtotal, 0), 2), round(coalesce(p_tax, 0), 2), round(coalesce(p_total, 0), 2),
     jsonb_build_object(
       'name', coalesce(cl.name, ''), 'legal_name', coalesce(cl.legal_name, ''),
       'address', coalesce(cl.billing_address, ''), 'regno', coalesce(cl.company_no, ''),
       'regno_old', coalesce(cl.company_no_old, ''), 'tin', coalesce(cl.tin, ''),
       'sst_no', coalesce(cl.sst_no, ''), 'sst_applies', cl.sst_applies is not false,
       'contact', coalesce(ct.name, ''), 'contact_role', coalesce(ct.role, ''),
       'contact_salutation', coalesce(ct.salutation, ''),
       -- A Singapore client billed in RM: its market and the rate in force,
       -- so the letter reads its figure in S$ beside it, as issued.
       'market', coalesce(cl.market, 'MY'),
       'fx_sgd', case when cl.market = 'SG' and not cl.bill_sgd then public.app_setting('fx_sgd', (timezone('Asia/Kuala_Lumpur', now()))::date) end,
       'phone', coalesce(ct.phone, ''), 'email', coalesce(ct.email, ''),
       'finance_email', coalesce(cl.finance_email, ''),
       'client_code', cl.client_code,
       'entity_id', v_ent.id,
       'owner', coalesce(p_deal ->> 'owner', ''), 'source', coalesce(p_deal ->> 'source', ''),
       'industry', coalesce(p_deal ->> 'industry', ''), 'stage', coalesce(p_deal ->> 'stage', ''),
       'enquiry', coalesce(p_deal ->> 'enquiry', ''),
       'terms', v_terms,
       -- The validity is one of the points typed (2026-10-23): a letter
       -- sent with it in its terms prints none of its own.
       'terms_own', coalesce(p_deal ->> 'terms_own', '') = 'true'),
     v_lines, coalesce(me.name, who), cl.client_code, nullif(btrim(p_idem), ''))
  returning id into v_id;

  insert into public.client_document_services (document_id, service_id)
    select v_id, s.id from unnest(p_services) s(id)
    on conflict do nothing;

  if p_replaces is not null then
    update public.client_documents set superseded_by = v_id where id = p_replaces;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.superseded', cl.name, v_old.number || ' replaced by ' || v_no);
  end if;

  select count(*) into v_n from public.client_document_services where document_id = v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.issued', cl.name, v_no || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end);

  return jsonb_build_object('ok', true, 'id', v_id, 'number', v_no);
exception
  when unique_violation then
    -- Two presses that raced past the idempotency read: the loser reads the
    -- winner's letter back rather than making a second one.
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.client_documents
        where client_id = p_client and idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
      end if;
    end if;
    -- A typed reference two people sent at once: the loser is told the
    -- reference is spent rather than that "two letters were issued at once",
    -- which names a cause they cannot act on.
    if nullif(btrim(coalesce(p_serial, '')), '') is not null then
      return jsonb_build_object('error', 'serial-taken');
    end if;
    return jsonb_build_object('error', 'clash');
end $$;
revoke all on function public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean, text) from public, anon;
grant execute on function public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean, text) to authenticated;

-- END OF A BRAND'S OWN BILLING CONTACT -------------------------------------

select public.functions_tidy();
