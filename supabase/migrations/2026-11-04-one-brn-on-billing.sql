-- ===========================================================================
-- ONE BRN, ONE BILLING ENTITY, ON BILLING TOO (2026-11-04)
-- ===========================================================================
-- Add entity and an entity's own Save refused a registration no. another
-- billing entity holds, one at a time (2026-11-04, billing audit fixes); a
-- client's own Billing sheet, Use details from its form and a signed
-- quotation's review write the client, whose main entity the trigger made
-- with no such check, so a second entity of one BRN could still be made.
-- `clients_entity_sync` now takes the same lock and refuses `brn-taken` on
-- a BRN changed to one another entity holds; a carry from the entity
-- (`adspace.entity_sync`) is never asked. Two clients holding one BRN
-- before stay two. Safe to run twice. Rollback: run clients_entity_sync
-- from 2026-10-31-entity-contact-per-brand.sql again.
-- ===========================================================================

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
  -- A BRN another billing entity holds is refused here too, the Billing
  -- sheet's own write, Use details and a signed quotation's review alike,
  -- one BRN checked at a time (audit 2026-11-04, 2).
  if regexp_replace(coalesce(new.company_no, ''), '\D', '', 'g') <> ''
     and regexp_replace(coalesce(new.company_no, ''), '\D', '', 'g') is distinct from regexp_replace(coalesce(old.company_no, ''), '\D', '', 'g') then
    perform pg_advisory_xact_lock(hashtextextended('entity-brn:' || regexp_replace(new.company_no, '\D', '', 'g'), 0));
    if exists (select 1 from public.billing_entities e
                where e.id is distinct from v_ent
                  and regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = regexp_replace(new.company_no, '\D', '', 'g')) then
      raise exception 'An entity with this registration no. already exists. Add that entity instead.'
        using errcode = '23505', hint = 'brn-taken';
    end if;
  end if;
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

-- END OF ONE BRN, ONE BILLING ENTITY, ON BILLING TOO --------------------------

select public.functions_tidy();
