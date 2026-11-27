-- ===========================================================================
-- QUOTATION INVOICE LINKED FROM BUKKU (2026-11-27)
-- ===========================================================================
-- WHY: a signed quotation's Invoices sheet could only create a cycle's
-- invoice in Bukku; one a colleague had already made there by hand
-- (ADP/QT2611-B02, RM 1,299.00) stood Not created with no way to name it.
-- As a campaign's invoice does (CAMPAIGN INVOICE FROM BUKKU), a cycle now
-- takes an existing invoice by its number.
--
-- WHAT IT CHANGES
--   * `quotation_invoice_link_prep(p_id, p_cycle, p_kind)`: at Clients:
--     Billing Work, the client in scope, the Bukku contact the cycle bills
--     (the advertising budget's chosen contact, else the billing entity's,
--     else the client's own, else its company's), as Create in Bukku reads
--     it; refuses `invoiced`, `creating`, `removed`, `nothing`, `not-linked`.
--   * `quotation_invoice_link(p_id, p_cycle, p_kind, p_bukku, p_number,
--     p_amount)`: files the invoice Bukku answered on that contact to the
--     cycle and kind (filed `client.billing`), refusing `invoiced`,
--     `creating`, and `taken` where the invoice is already on another
--     cycle, quotation or campaign. A linked cycle holds a number, so
--     `quotation_invoice_prep` refuses Create in Bukku for it (`invoiced`).
--   * `quotation_invoice_unlink(p_id, p_cycle, p_kind)`: the cycle let go
--     of its invoice, nothing changed in Bukku, filed; answers the number
--     for Undo (linked again by its number).
--   * `quotation_invoices_of(p_id)`: answers `once` where the quotation
--     bills nothing monthly (its row reads One-time).
--
-- ORDER: this file, then bukku-sync (`invoicelink`), then the pages. An old
-- tab meets no new act; a page before bukku-sync meets `bad-request` on
-- Link existing invoice. Safe to run twice.
-- ROLLBACK: drop the three new functions; run
-- `2026-11-22-quotation-invoice-paid.sql` again for `quotation_invoices_of`.
-- ===========================================================================

create or replace function public.quotation_invoices_of(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  v_start date;
  v_n int;
  v_rows jsonb := '[]'::jsonb;
  i int; k text; v_lines jsonb; v_sum numeric; r public.quotation_invoices;
  v_day date;
  v_bill boolean;
  v_doc public.bukku_docs;
  v_once boolean;
begin
  if (public.ops_me()).id is null
     or not (public.allowed('clients.billing', 'view') or public.allowed('clients.quotes', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  v_bill := public.allowed('clients.billing', 'view');
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  v_start := public.quotation_start(q.id);
  v_n := public.quotation_cycles(q.id);
  for i in 1 .. v_n loop
    v_day := case when v_start is not null then (v_start + make_interval(months => i - 1))::date end;
    foreach k in array array['service', 'budget'] loop
      v_lines := public.quotation_cycle_lines(q.id, i, k);
      if jsonb_array_length(v_lines) = 0 then continue; end if;
      select coalesce(sum(round((x->>'qty')::numeric * (x->>'unit')::numeric, 2)), 0) into v_sum from jsonb_array_elements(v_lines) x;
      select * into r from public.quotation_invoices x where x.quotation_id = q.id and x.cycle = i and x.kind = k;
      v_doc := null;
      if r.bukku_id is not null then
        select * into v_doc from public.bukku_docs d where d.kind = 'invoice' and d.doc_id = r.bukku_id and not d.gone;
      end if;
      v_rows := v_rows || jsonb_strip_nulls(jsonb_build_object('cycle', i, 'kind', k, 'date', v_day,
        'until', case when v_day is not null then ((v_start + make_interval(months => i))::date - 1) end,
        'amount', case when v_bill then v_sum end, 'number', r.number, 'bukku_id', r.bukku_id, 'made_at', r.made_at,
        'creating', r.claimed_at is not null and r.claimed_at > now() - interval '10 minutes' and r.number is null,
        'paid', case when v_doc.doc_id is not null then v_doc.balance <= 0 end,
        'paid_on', case when v_doc.doc_id is not null and v_doc.balance <= 0 then v_doc.paid_on end));
    end loop;
  end loop;
  -- One-time only: no monthly line and no monthly advertising budget.
  v_once := not exists (select 1 from jsonb_array_elements(coalesce(q.lines, '[]'::jsonb)) e where e->>'basis' = 'month')
        and not exists (select 1 from jsonb_array_elements(coalesce(q.totals->'ads', '[]'::jsonb)) e
                         where coalesce(e->>'freq', 'monthly') = 'monthly' and coalesce((e->>'budget')::numeric, (e->>'amount')::numeric, 0) > 0);
  return jsonb_strip_nulls(jsonb_build_object('ok', true, 'ref', q.ref, 'start', v_start, 'cycles', v_n, 'once', v_once,
    'currency', coalesce(q.totals->>'currency', 'MYR'), 'rows', v_rows, 'billing', v_bill,
    'debtor', case when v_bill then (select jsonb_build_object('contact_id', d.contact_id, 'code', d.code, 'name', d.name) from public.client_ad_debtors d where d.client_id = q.client_id) end,
    'budget_account', case when v_bill then (select b.budget_account_code from public.bukku_settings b where b.id = 1) end));
end $$;
revoke all on function public.quotation_invoices_of(uuid) from public, anon;
grant execute on function public.quotation_invoices_of(uuid) to authenticated;

/* The Bukku contact one cycle bills, as quotation_invoice_prep reads it. */
create or replace function public.quotation_invoice_contact(p_id uuid, p_kind text)
returns bigint language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  v_contact bigint; v_ent uuid;
begin
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null then return null; end if;
  if p_kind = 'budget' then
    select d.contact_id into v_contact from public.client_ad_debtors d where d.client_id = q.client_id;
  end if;
  if v_contact is null then
    v_ent := nullif(q.totals->'bill_to'->>'entity_id', '')::uuid;
    if v_ent is not null then
      select l.contact_id into v_contact from public.bukku_links l where l.kind = 'entity' and l.record_id = v_ent;
    end if;
  end if;
  if v_contact is null then
    select l.contact_id into v_contact from public.bukku_links l where l.kind = 'client' and l.record_id = q.client_id;
  end if;
  if v_contact is null then
    v_contact := (public.bukku_shared('client', q.client_id)->>'contact_id')::bigint;
  end if;
  return v_contact;
end $$;
revoke all on function public.quotation_invoice_contact(uuid, text) from public, anon, authenticated;

create or replace function public.quotation_invoice_link_prep(p_id uuid, p_cycle int, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q public.quotations;
  r public.quotation_invoices;
  v_contact bigint;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind is null or p_kind not in ('service', 'budget') or p_cycle is null or p_cycle < 1 or p_cycle > 36 then
    return jsonb_build_object('error', 'bad-request');
  end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  if q.removed_at is not null then return jsonb_build_object('error', 'removed'); end if;
  if p_cycle > public.quotation_cycles(q.id)
     or jsonb_array_length(public.quotation_cycle_lines(q.id, p_cycle, p_kind)) = 0 then
    return jsonb_build_object('error', 'nothing');
  end if;
  select * into r from public.quotation_invoices x where x.quotation_id = q.id and x.cycle = p_cycle and x.kind = p_kind;
  if r.number is not null then return jsonb_build_object('error', 'invoiced', 'number', r.number); end if;
  if r.claimed_at is not null and r.claimed_at > now() - interval '10 minutes' then return jsonb_build_object('error', 'creating'); end if;
  v_contact := public.quotation_invoice_contact(q.id, p_kind);
  if v_contact is null then return jsonb_build_object('error', 'not-linked'); end if;
  return jsonb_build_object('ok', true, 'contact_id', v_contact);
end $$;
revoke all on function public.quotation_invoice_link_prep(uuid, integer, text) from public, anon;
grant execute on function public.quotation_invoice_link_prep(uuid, integer, text) to authenticated;

create or replace function public.quotation_invoice_link(p_id uuid, p_cycle int, p_kind text, p_bukku bigint, p_number text, p_amount numeric)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q public.quotations;
  r public.quotation_invoices;
  v_num text := nullif(left(btrim(coalesce(p_number, '')), 60), '');
  v_on text;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind is null or p_kind not in ('service', 'budget') or p_cycle is null or p_cycle < 1 or p_cycle > 36
     or v_num is null or coalesce(p_bukku, 0) <= 0 then
    return jsonb_build_object('error', 'bad-request');
  end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  if q.removed_at is not null then return jsonb_build_object('error', 'removed'); end if;
  if p_cycle > public.quotation_cycles(q.id)
     or jsonb_array_length(public.quotation_cycle_lines(q.id, p_cycle, p_kind)) = 0 then
    return jsonb_build_object('error', 'nothing');
  end if;
  select * into r from public.quotation_invoices x where x.quotation_id = q.id and x.cycle = p_cycle and x.kind = p_kind for update;
  if r.number is not null then return jsonb_build_object('error', 'invoiced', 'number', r.number); end if;
  if r.claimed_at is not null and r.claimed_at > now() - interval '10 minutes' then return jsonb_build_object('error', 'creating'); end if;
  -- One Bukku invoice is one cycle's, or one campaign's.
  select x2.ref into v_on from public.quotation_invoices i join public.quotations x2 on x2.id = i.quotation_id
   where (i.bukku_id = p_bukku or upper(i.number) = upper(v_num)) limit 1;
  if v_on is null then
    select coalesce(nullif(c.campaign_code, ''), c.title) into v_on from public.campaigns c
     where c.bukku_invoice_id = p_bukku or upper(coalesce(c.invoice_no, '')) = upper(v_num) limit 1;
  end if;
  if v_on is not null then return jsonb_build_object('error', 'taken', 'number', v_num, 'on', v_on); end if;
  insert into public.quotation_invoices (quotation_id, cycle, kind, bukku_id, number, amount, currency, made_at, made_by)
  values (q.id, p_cycle, p_kind, p_bukku, v_num, p_amount, case when q.totals->>'currency' = 'SGD' then 'SGD' else 'MYR' end, now(), me.id)
  on conflict (quotation_id, cycle, kind) do update
     set bukku_id = excluded.bukku_id, number = excluded.number, amount = excluded.amount, currency = excluded.currency,
         made_at = now(), made_by = me.id, claimed_at = null, claimed_by = null;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', q.brand, q.ref || ' · ' ||
          case when p_kind = 'budget' then 'Advertising budget invoice ' else 'Invoice ' end ||
          v_num || ' linked from Bukku' ||
          case when public.quotation_cycles(q.id) > 1 then ' · Month ' || p_cycle else '' end);
  return jsonb_build_object('ok', true, 'number', v_num);
end $$;
revoke all on function public.quotation_invoice_link(uuid, integer, text, bigint, text, numeric) from public, anon;
grant execute on function public.quotation_invoice_link(uuid, integer, text, bigint, text, numeric) to authenticated;

create or replace function public.quotation_invoice_unlink(p_id uuid, p_cycle int, p_kind text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q public.quotations;
  r public.quotation_invoices;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  select * into r from public.quotation_invoices x where x.quotation_id = q.id and x.cycle = p_cycle and x.kind = p_kind for update;
  if r.number is null then return jsonb_build_object('error', 'not-linked'); end if;
  update public.quotation_invoices x set bukku_id = null, number = null, amount = null, currency = null, made_at = null, made_by = null
   where x.quotation_id = q.id and x.cycle = p_cycle and x.kind = p_kind;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', q.brand, q.ref || ' · ' ||
          case when p_kind = 'budget' then 'Advertising budget invoice ' else 'Invoice ' end ||
          r.number || ' unlinked' ||
          case when public.quotation_cycles(q.id) > 1 then ' · Month ' || p_cycle else '' end);
  return jsonb_build_object('ok', true, 'number', r.number, 'bukku', r.bukku_id);
end $$;
revoke all on function public.quotation_invoice_unlink(uuid, integer, text) from public, anon;
grant execute on function public.quotation_invoice_unlink(uuid, integer, text) to authenticated;

-- END OF QUOTATION INVOICE LINKED FROM BUKKU ---------------------------------
select public.functions_tidy();
