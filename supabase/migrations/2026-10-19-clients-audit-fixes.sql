-- ===========================================================================
-- CLIENTS AUDIT FIXES — a client's timeline written over the row as read,
-- billing complete at Active, a details form used on its own client, the
-- main contact swapped in one transaction. 2026-10-19. Safe to run twice.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the audit of the Clients section, 2026-10-19)
--   * Trigger `clients_touch`: every update of a client stamps `updated_at`,
--     so the page writes the timeline (`stage_log`, `stage_since`,
--     `created_at`, a move's reason) only over the row as it read it, and a
--     move made meanwhile is never overwritten (item 4).
--   * Trigger `clients_active_billing`: a move into Active is refused while
--     the registered name, BRN or billing address is empty, or the client
--     holds no billing contact (the one chosen, else a live main contact)
--     (`active-needs-billing`, item 7). Only the move is held: a client
--     already Active keeps its place. `clients_active_code` is unchanged.
--   * `client_details_used(p_id, p_client)`: the form must be that client's
--     (`not-found`), so a Billing save on one client never marks another's
--     form used (item 8). The one-argument version is dropped.
--   * `client_contact_make_primary(p_contact)`: the main contact swapped in
--     one transaction, at Clients: Contacts Work on a client in scope at
--     Work (`denied`, `not-found`), so a failed swap never leaves a client
--     with no main contact (item 12). The page files it as before.
--
-- ORDER: the pages, then this file. A page from before calls
--   `client_details_used(p_id)`, which is gone: its Save is kept and the
--   form stays unmarked (the call's refusal is not shown). Its main-contact
--   change writes the table as before.
--
-- ROLLBACK
--   drop trigger clients_touch on public.clients;
--   drop trigger clients_active_billing on public.clients;
--   drop function public.client_contact_make_primary(uuid);
--   the CLIENT DETAILS FORM section's client_details_used(uuid) again, and
--   drop function public.client_details_used(uuid, uuid).
-- ===========================================================================

create or replace trigger clients_touch before update on public.clients
  for each row execute function public.touch_updated_at();

create or replace function public.clients_active_billing()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.stage = 'active' and old.stage is distinct from 'active' and (
       coalesce(btrim(new.legal_name), '') = ''
       or coalesce(btrim(new.company_no), '') = ''
       or coalesce(btrim(new.billing_address), '') = ''
       or not exists (select 1 from public.client_contacts k
                       where k.client_id = new.id and k.archived_at is null
                         and (k.id = new.bill_contact_id or k.is_primary))) then
    raise exception 'active-needs-billing';
  end if;
  return new;
end $$;
revoke all on function public.clients_active_billing() from public, anon, authenticated;
create or replace trigger clients_active_billing before update of stage on public.clients
  for each row execute function public.clients_active_billing();

drop function if exists public.client_details_used(uuid);
create or replace function public.client_details_used(p_id uuid, p_client uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  v_f public.client_detail_forms;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_f from public.client_detail_forms f where f.id = p_id;
  if v_f.id is null or v_f.client_id is distinct from p_client or not public.client_seen(v_f.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_f.submitted_at is null then return jsonb_build_object('error', 'not-submitted'); end if;
  update public.client_detail_forms f set used_at = coalesce(f.used_at, now()), used_by = coalesce(f.used_by, (select t.id from public.team_members t where t.id = me.id)) where f.id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_used(uuid, uuid) from public, anon;
grant execute on function public.client_details_used(uuid, uuid) to authenticated;

create or replace function public.client_contact_make_primary(p_contact uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  v_ct public.client_contacts;
begin
  if me.id is null or not public.allowed('clients.contacts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_ct from public.client_contacts k where k.id = p_contact;
  if v_ct.id is null or v_ct.archived_at is not null or not public.client_seen(v_ct.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if not v_ct.is_primary then
    update public.client_contacts k set is_primary = false where k.client_id = v_ct.client_id and k.is_primary;
    update public.client_contacts k set is_primary = true where k.id = v_ct.id;
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_contact_make_primary(uuid) from public, anon;
grant execute on function public.client_contact_make_primary(uuid) to authenticated;

-- END OF CLIENTS AUDIT FIXES -------------------------------------------------
select public.functions_tidy();
