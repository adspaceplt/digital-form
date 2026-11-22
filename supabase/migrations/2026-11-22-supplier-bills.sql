-- ===========================================================================
-- SUPPLIER BILLS (2026-11-22)
-- ===========================================================================
-- WHY: the user, 2026-11-22, approving the Bukku structure mockup (v3,
-- screens a, b and c-alt; "proceed all as recommended"): every supplier's
-- purchase bills read in the portal, from the copy the nightly run already
-- keeps (`bukku_docs`, kind `bill`), read only. Suppliers gains a Payments
-- view; a supplier's record lists its bills under Payment, with its totals
-- in a rail. No bill is made in the portal: a supplier's own invoice is what
-- is keyed into Bukku.
--
-- WHAT IT ADDS
--   * `supplier_bills(p_supplier, p_paid_from, p_doc)`: the one read, at
--     Suppliers View (`denied`; decision 2: the amounts are the supplier's,
--     and Sensitive details keeps only the bank details shut). The bills of
--     every Bukku contact linked to a supplier (`bukku_links` kind
--     `supplier`), never a creator's (theirs are `creator_bills`) nor a
--     contact no supplier holds; a bill marked gone left out. Each with its
--     supplier (id, Supplier ID, name), number, date, due date (its own,
--     else its date), amount, balance, currency and paid day, and the
--     supplier's client where the colleague sees that client
--     (`client_seen`). `p_supplier` one supplier's (`not-found`);
--     `p_paid_from` leaves out a bill settled before that day (a bill still
--     owing always stands); `p_doc` one bill, for Open in Bukku. Answers
--     `work` (Suppliers Work: Read from Bukku), today (Malaysia's) and when
--     the bills were last read (`bukku_doc_marks`).
--
-- ORDER: this file, then the pages, then `bukku-sync` (its `supplierbills`
-- and `supplierbilllink` actions ask this function as the caller). A page
-- from before never asks; a page after it before this file reads "This
-- feature is not available yet." on the Payments view and leaves the
-- record's bills out. Nothing is written; nothing changes in Bukku.
-- Rollback: drop function public.supplier_bills(uuid, date, bigint);
-- Safe to run twice.
-- ===========================================================================

create or replace function public.supplier_bills(p_supplier uuid default null, p_paid_from date default null, p_doc bigint default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_rows jsonb;
  v_read timestamptz;
begin
  if me.id is null or not public.allowed('suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if p_supplier is not null and not exists (select 1 from public.suppliers s where s.id = p_supplier) then
    return jsonb_build_object('error', 'not-found');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.doc_id, 'supplier', s.id, 'code', s.code, 'name', coalesce(s.name, s.code),
           'number', d.number, 'date', d.doc_date, 'due', coalesce(d.due_date, d.doc_date),
           'amount', d.amount, 'balance', d.balance, 'currency', d.currency, 'paid_on', d.paid_on,
           'client', case when c.id is not null and public.client_seen(c.id, 'view') then c.name end,
           'client_code', case when c.id is not null and public.client_seen(c.id, 'view') then c.client_code end)
         order by coalesce(d.due_date, d.doc_date), d.doc_id), '[]'::jsonb)
    into v_rows
    from public.bukku_docs d
    join public.bukku_links bl on bl.kind = 'supplier' and bl.contact_id = d.contact_id
    join public.suppliers s on s.id = bl.record_id
    left join public.clients c on c.id = s.client_id
   where d.kind = 'bill' and not d.gone
     and (p_supplier is null or s.id = p_supplier)
     and (p_doc is null or d.doc_id = p_doc)
     and (p_paid_from is null or d.balance > 0 or coalesce(d.paid_on, d.doc_date) >= p_paid_from);
  select m.read_at into v_read from public.bukku_doc_marks m where m.kind = 'bill';
  return jsonb_build_object('ok', true, 'today', v_today, 'work', public.allowed('suppliers', 'work'),
    'read_at', v_read, 'bills', v_rows);
end $$;
revoke all on function public.supplier_bills(uuid, date, bigint) from public, anon;
grant execute on function public.supplier_bills(uuid, date, bigint) to authenticated;

-- END OF SUPPLIER BILLS ------------------------------------------------------
select public.functions_tidy();
