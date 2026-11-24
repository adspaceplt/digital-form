-- ===========================================================================
-- A SUPPLIER'S EDIT HOLDS TO ITS COPY (2026-11-24)
-- ===========================================================================
-- WHY: the review of 2026-11-24 (C1): `supplier_save` wrote every field the
-- sheet held, bank details included, with no version check, so an Edit left
-- open on a phone could put back an old bank account a colleague had since
-- corrected.
--
-- WHAT IT CHANGES
--   * `supplier_save(p_id, p_values, p_form)` keeps its signature (no drop:
--     an open tab keeps working). `p_values` may now carry `expected`, the
--     supplier's `updated_at` as the sheet read it: a supplier changed since
--     is refused `stale`, answered with the supplier as it now stands, and
--     the page repaints from it.
--   * Only the fields sent move: the rest keep what is stored (the stored
--     row is laid under what was sent before the one check), so the page
--     sends only what changed. A page from before, sending every field and
--     no `expected`, is answered as before.
--
-- ORDER: this migration first, then the pages (a page from this release
-- sends only the fields that moved, which the function before this one
-- would have written as blanks).
--
-- ROLLBACK: run `supplier_save` as OFFICIAL TERMS CAPITALISED stated it
-- (its previous last definition in schema.sql). The pages then send every
-- field again only after their own rollback, so roll the pages back first.
-- ===========================================================================

create or replace function public.supplier_save(p_id uuid, p_values jsonb, p_form uuid default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.suppliers;
  pay   boolean := public.ops_granted('suppliers.pay', 'work');
  v     jsonb;
  v_code text;
  moved text[] := '{}';
  k     text;
  word  constant jsonb := '{"code":"Supplier ID","name":"Name","kind":"Type","brn":"BRN","tin":"TIN","sst_no":"SST Registration No.",
    "phone":"Office / mobile","address":"Billing address","contact_name":"Legal name","designation":"Designation",
    "email":"Email","mobile":"Mobile / WhatsApp","payment_term":"Payment term","currency":"Currency",
    "finance_email":"Finance email","nric":"NRIC","payee_name":"Payee name","bank_name":"Bank",
    "bank_account":"Account number","swift":"SWIFT code","bank_address":"Bank address"}';
  secret constant text[] := array['nric', 'payee_name', 'bank_name', 'bank_account', 'swift', 'bank_address'];
  was   jsonb;
  repend boolean := false;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  /* The copy the sheet opened on: a write over a newer one is refused,
     and the page repaints from the supplier answered with it. */
  if (p_values ? 'expected') and s.updated_at is distinct from (p_values->>'expected')::timestamptz then
    return jsonb_build_object('error', 'stale', 'supplier', public.supplier_json(s, public.ops_granted('suppliers.pay', 'view')));
  end if;
  /* Only the fields sent move; the rest keep what is stored, so a phone
     edit never writes back an older bank account. */
  p_values := (to_jsonb(s) - 'id' - 'status' - 'created_at' - 'updated_at') || (coalesce(p_values, '{}'::jsonb) - 'expected');
  v_code := upper(regexp_replace(coalesce(p_values->>'code', ''), '\s+', '', 'g'));
  if v_code !~ '^[A-Z0-9]{2,12}$' then return jsonb_build_object('error', 'bad-code'); end if;
  if exists (select 1 from public.suppliers x where upper(x.code) = v_code and x.id <> p_id) then
    return jsonb_build_object('error', 'code-taken', 'name', (select x.name from public.suppliers x where upper(x.code) = v_code));
  end if;
  v := public.supplier_values_check(coalesce(p_values, '{}'::jsonb), pay);
  if v ? 'error' then return v; end if;
  v := v || jsonb_build_object('code', v_code);
  was := to_jsonb(s);
  for k in select jsonb_object_keys(v) loop
    if (was->>k) is distinct from (v->>k) then
      moved := moved || case when k = any (secret) then (word->>k)
        else (word->>k) || ': ' || coalesce(was->>k, 'not set') || ' → ' || coalesce(v->>k, 'not set') end;
    end if;
  end loop;
  /* A bank account changed on an approved supplier is approved again. */
  repend := pay and s.status = 'active' and s.bank_account is not null and (
    (v->>'payee_name') is distinct from s.payee_name or (v->>'bank_name') is distinct from s.bank_name
    or (v->>'bank_account') is distinct from s.bank_account);
  update public.suppliers x set
    code = v_code, name = v->>'name', kind = v->>'kind', brn = v->>'brn', tin = v->>'tin', sst_no = v->>'sst_no',
    phone = v->>'phone', address = v->>'address', contact_name = v->>'contact_name', designation = v->>'designation',
    email = v->>'email', mobile = v->>'mobile', payment_term = v->>'payment_term', currency = v->>'currency',
    finance_email = v->>'finance_email',
    nric = case when pay then v->>'nric' else x.nric end,
    payee_name = case when pay then v->>'payee_name' else x.payee_name end,
    bank_name = case when pay then v->>'bank_name' else x.bank_name end,
    bank_account = case when pay then v->>'bank_account' else x.bank_account end,
    swift = case when pay then v->>'swift' else x.swift end,
    bank_address = case when pay then v->>'bank_address' else x.bank_address end,
    status = case when repend then 'pending' else x.status end,
    updated_at = now()
   where x.id = p_id;
  if p_form is not null then
    update public.supplier_forms f set used_at = coalesce(f.used_at, now()), used_by = coalesce(f.used_by, me.id)
     where f.id = p_form and f.supplier_id = p_id and f.submitted_at is not null;
  end if;
  if array_length(moved, 1) is not null then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'supplier.edited', v->>'name', v_code || ' · ' || array_to_string(moved, ' · ') ||
            case when p_form is not null then ' · from the details form' else '' end ||
            case when repend then ' · Active → Pending until approved again' else '' end);
  end if;
  return jsonb_build_object('ok', true, 'repending', repend, 'supplier',
    public.supplier_json((select x from public.suppliers x where x.id = p_id), public.ops_granted('suppliers.pay', 'view')));
end $$;
revoke all on function public.supplier_save(uuid, jsonb, uuid) from public, anon;
grant execute on function public.supplier_save(uuid, jsonb, uuid) to authenticated;

-- END OF A SUPPLIER'S EDIT HOLDS TO ITS COPY -------------------------------

select public.functions_tidy();
