-- ===========================================================================
-- SUPPLIERS LINKED TO CLIENTS — a supplier that is also one of our clients
-- names that client (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18: some suppliers are clients too; "u can leave
-- the supplier and client id separate"): the two records keep their own
-- IDs and are linked, each opening the other.
--
-- WHAT IT ADDS
--   * `suppliers.client_id` (the client it is, set null if the client goes).
--   * `supplier_client_set(p_id, p_client)` (Suppliers Work; a client needs
--     Clients View and the client in the caller's scope; null unlinks):
--     filed `supplier.edited` from and to.
--   * `supplier_get` answers `client` (its id, code and name where the
--     caller reads Clients and the client is in scope; `hidden` otherwise)
--     and, while none is linked and the caller may link one, `match`: the
--     clients whose BRN, digits alone, is the supplier's. The BRN itself is
--     never sent.
--   * `client_suppliers(p_client)` (Suppliers View, the client in scope):
--     the suppliers linked to a client, for its record.
--
-- ORDER: this file, then the pages. A page served before draws no link.
-- Safe to run twice. Rollback: drop `supplier_client_set`,
-- `client_suppliers`, put back `supplier_get` from SUPPLIERS, A SECTION OF
-- THEIR OWN, then drop `suppliers.client_id`.
-- ===========================================================================

alter table public.suppliers add column if not exists client_id uuid references public.clients(id) on delete set null;
create index if not exists suppliers_client_idx on public.suppliers (client_id) where client_id is not null;

create or replace function public.supplier_get(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s   public.suppliers;
  f   public.supplier_forms;
  pay boolean := public.ops_granted('suppliers.pay', 'view');
  work boolean := public.allowed('suppliers', 'work');
  cv  boolean := public.allowed('clients', 'view');
  a   jsonb;
  cl  jsonb;
  mt  jsonb;
begin
  if (public.ops_me()).id is null or not public.allowed('suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into s from public.suppliers x where x.id = p_id;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into f from public.supplier_forms x where x.supplier_id = p_id and x.voided_at is null
   order by x.created_at desc limit 1;
  a := f.answers;
  if a is not null and not pay then
    a := a - array['nric', 'payee_name', 'bank_name', 'bank_account', 'swift', 'bank_address'];
  end if;
  if s.client_id is not null then
    select case when cv and public.client_seen(c.id, 'view')
                then jsonb_build_object('id', c.id, 'slug', c.slug, 'code', c.client_code, 'name', c.name)
                else jsonb_build_object('hidden', true) end
      into cl from public.clients c where c.id = s.client_id;
  elsif work and cv and s.brn is not null then
    select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.client_code, 'name', c.name) order by c.client_code, c.name)
      into mt from public.clients c
     where regexp_replace(coalesce(c.company_no, ''), '[^0-9]', '', 'g') = s.brn
       and public.client_seen(c.id, 'view');
  end if;
  return jsonb_build_object('ok', true, 'pay', pay, 'supplier', public.supplier_json(s, pay),
    'client', cl, 'match', mt,
    'form', case when f.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'id', f.id,
      'key', case when work and f.submitted_at is null and f.expires_at > now() then f.access_key end,
      'state', case when f.used_at is not null then 'used' when f.submitted_at is not null then 'submitted'
                    when f.expires_at <= now() then 'expired' else 'open' end,
      'created_at', f.created_at, 'expires_at', f.expires_at, 'submitted_at', f.submitted_at, 'used_at', f.used_at,
      'answers', case when f.submitted_at is not null then a end)) end);
end $$;
revoke all on function public.supplier_get(uuid) from public, anon;
grant execute on function public.supplier_get(uuid) to authenticated;

create or replace function public.supplier_client_set(p_id uuid, p_client uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  s      public.suppliers;
  was_w  text;
  now_w  text;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_client is not null then
    if not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
    if not exists (select 1 from public.clients c where c.id = p_client) or not public.client_seen(p_client, 'view') then
      return jsonb_build_object('error', 'no-client');
    end if;
  end if;
  if s.client_id is not distinct from p_client then return jsonb_build_object('ok', true); end if;
  select coalesce(c.client_code || ' · ', '') || c.name into was_w from public.clients c where c.id = s.client_id;
  select coalesce(c.client_code || ' · ', '') || c.name into now_w from public.clients c where c.id = p_client;
  update public.suppliers x set client_id = p_client, updated_at = now() where x.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'supplier.edited', coalesce(s.name, s.code),
          s.code || ' · Client: ' || coalesce(was_w, 'not set') || ' → ' || coalesce(now_w, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_client_set(uuid, uuid) from public, anon;
grant execute on function public.supplier_client_set(uuid, uuid) to authenticated;

create or replace function public.client_suppliers(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('suppliers', 'view')
     or not public.client_seen(p_client, 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'name', s.name, 'status', s.status) order by upper(s.code))
      from public.suppliers s where s.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.client_suppliers(uuid) from public, anon;
grant execute on function public.client_suppliers(uuid) to authenticated;

-- END OF SUPPLIERS LINKED TO CLIENTS ----------------------------------------
select public.functions_tidy();
