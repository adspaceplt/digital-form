-- ===========================================================================
-- THE SUPPLIER'S REFERENCE NO. ON BUKKU LISTS (2026-11-23)
-- ===========================================================================
-- WHY: the user, 2026-11-23: a bill or invoice reads its number and the
-- reference no. Bukku keeps beside it (`number2`), as
-- `AB2609081 / Reference: XXXX`, so a supplier's or creator's own invoice
-- number is found without opening Bukku.
--
-- WHAT IT CHANGES
--   * `bukku_docs.ref_no` and `creator_bills.ref_no`: Bukku's reference no.
--     alone (60 characters), kept by `bukku_docs_take` and
--     `creator_bills_take` from `ref_no` in each row the nightly read sends.
--     A creator bill's `ref` (every reference field joined, for matching a
--     Job reference) is unchanged.
--   * `supplier_bills()`, `creator_bills_list()` and
--     `creator_payments_queue()` answer `ref_no` beside `number`.
--   * Overdue invoices and a client's unpaid invoices are read live from
--     Bukku, so no column: `bukku-sync` sends `ref_no` on each line.
--
-- ORDER: this file, then the function (`bukku-sync`, which sends `ref_no`),
-- then the pages. Before the function, `ref_no` stays empty and the pages
-- draw the number alone; a page from before ignores `ref_no`.
-- Rollback: `alter table … drop column ref_no` on both tables, then run
-- SUPPLIER BILLS' `supplier_bills` and `bukku_docs_take`, and CREATOR
-- PAYMENTS' last `creator_bills_take`, `creator_bills_list` and
-- `creator_payments_queue` again.
-- Safe to run twice.
-- ===========================================================================

alter table public.bukku_docs add column if not exists ref_no text;
alter table public.creator_bills add column if not exists ref_no text;

create or replace function public.bukku_docs_take(p_kind text, p_rows jsonb, p_back_to date default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  r jsonb;
  v_n integer := 0;
  v_id bigint;
  v_contact bigint;
  v_date date;
  v_due date;
  v_paid date;
  v_amt numeric;
  v_bal numeric;
  v_cur text;
begin
  if p_kind is null or p_kind not in ('invoice', 'bill') then return jsonb_build_object('error', 'bad-kind'); end if;
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then return jsonb_build_object('error', 'bad-rows'); end if;
  for r in select x from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) x loop
    v_id := case when (r ->> 'id') ~ '^[0-9]{1,15}$' then (r ->> 'id')::bigint end;
    v_contact := case when (r ->> 'contact') ~ '^[0-9]{1,15}$' then (r ->> 'contact')::bigint end;
    v_date := case when (r ->> 'date') ~ '^\d{4}-\d{2}-\d{2}$' then (r ->> 'date')::date end;
    if v_id is null or v_contact is null or v_date is null then continue; end if;
    v_due := case when (r ->> 'due') ~ '^\d{4}-\d{2}-\d{2}$' then (r ->> 'due')::date end;
    v_paid := case when (r ->> 'paid_on') ~ '^\d{4}-\d{2}-\d{2}$' then (r ->> 'paid_on')::date end;
    v_amt := case when (r ->> 'amount') ~ '^-?[0-9]{1,12}(\.[0-9]+)?$' then round((r ->> 'amount')::numeric, 2) else 0 end;
    v_bal := case when (r ->> 'balance') ~ '^-?[0-9]{1,12}(\.[0-9]+)?$' then round((r ->> 'balance')::numeric, 2) end;
    v_cur := case when (r ->> 'currency') ~ '^[A-Z]{3}$' then r ->> 'currency' else 'MYR' end;
    insert into public.bukku_docs as d (kind, doc_id, contact_id, contact_name, number, ref_no, doc_date, due_date, amount, balance,
                                        currency, paid_on, gone, read_at)
    values (p_kind, v_id, v_contact, left(nullif(btrim(r ->> 'name'), ''), 200), left(coalesce(r ->> 'number', ''), 60),
            left(nullif(btrim(r ->> 'ref_no'), ''), 60), v_date,
            v_due, v_amt, coalesce(v_bal, v_amt), v_cur, case when coalesce(v_bal, v_amt) <= 0 then v_paid end,
            coalesce((r ->> 'gone') = 'true', false), now())
    on conflict (kind, doc_id) do update set
      contact_id = excluded.contact_id,
      contact_name = coalesce(excluded.contact_name, d.contact_name),
      number = excluded.number,
      ref_no = excluded.ref_no,
      doc_date = excluded.doc_date,
      due_date = coalesce(excluded.due_date, d.due_date),
      amount = excluded.amount,
      balance = coalesce(v_bal, d.balance),
      currency = excluded.currency,
      paid_on = case when coalesce(v_bal, d.balance) > 0 then null else coalesce(v_paid, d.paid_on) end,
      gone = excluded.gone,
      read_at = now();
    v_n := v_n + 1;
  end loop;
  insert into public.bukku_doc_marks as m (kind, back_to, read_at) values (p_kind, p_back_to, now())
  on conflict (kind) do update set back_to = least(m.back_to, excluded.back_to), read_at = now();
  return jsonb_build_object('ok', true, 'kept', v_n);
end $$;
revoke all on function public.bukku_docs_take(text, jsonb, date) from public, anon, authenticated;
grant execute on function public.bukku_docs_take(text, jsonb, date) to service_role;

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
           'number', d.number, 'ref_no', d.ref_no, 'date', d.doc_date, 'due', coalesce(d.due_date, d.doc_date),
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

create or replace function public.creator_bills_take(p_creator uuid, p_contact bigint, p_rows jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  x jsonb; b public.creator_bills; v_id bigint; v_status text; v_opt uuid; v_n int := 0; v_paid int := 0;
  v_seen bigint[] := '{}'; v_post boolean;
begin
  if p_creator is null or jsonb_typeof(p_rows) is distinct from 'array' then return jsonb_build_object('error', 'bad-request'); end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    v_id := (x->>'id')::bigint;
    if v_id is null then continue; end if;
    v_seen := v_seen || v_id;
    select * into b from public.creator_bills y where y.bill_id = v_id for update;
    -- A bill the portal made keeps its booking, whatever its reference reads now.
    v_opt := coalesce(b.made_for,
      case when coalesce(x->>'made_for', '') ~ '^[0-9a-f-]{36}$' then (x->>'made_for')::uuid end,
      public.creator_bill_option(p_creator, x->>'ref', x->>'number'));
    -- A bill read with no balance keeps the state it had, never Paid by default.
    v_status := case when coalesce(x->>'draft', '') = 'true' then 'draft'
                     when nullif(x->>'balance', '') is null then coalesce(nullif(b.status, 'draft'), 'processing')
                     when (x->>'balance')::numeric <= 0 then 'paid' else 'processing' end;
    v_post := v_opt is not null and exists (select 1 from public.campaign_options o where o.id = v_opt and o.posted_on is not null);
    if b.bill_id is null then
      insert into public.creator_bills (bill_id, creator_id, contact_id, number, ref, ref_no, bill_date, amount, balance, currency, status,
                                        option_id, made_for, read_at, paid_seen_at, paid_told_at, paid_on)
      values (v_id, p_creator, p_contact, left(x->>'number', 60), left(x->>'ref', 200),
              left(nullif(btrim(x->>'ref_no'), ''), 60), nullif(x->>'date', '')::date,
              (x->>'amount')::numeric, nullif(x->>'balance', '')::numeric, left(coalesce(x->>'currency', 'MYR'), 3), v_status, v_opt,
              case when coalesce(x->>'made_for', '') ~ '^[0-9a-f-]{36}$' then (x->>'made_for')::uuid end, now(),
              case when v_status = 'paid' then now() end,
              case when v_status = 'paid' then now() end,
              case when v_status = 'paid' then nullif(x->>'paid_on', '')::date end);
      -- A bill first read already paid is told only for a booking posted in the
      -- portal; one from before the portal (no posted day) tells nobody.
      if v_status = 'paid' and v_post then
        perform public.creator_mail_job('paid', v_opt);
        v_paid := v_paid + 1;
      end if;
    else
      update public.creator_bills y set creator_id = p_creator, contact_id = p_contact, number = left(x->>'number', 60),
        ref = left(x->>'ref', 200), ref_no = left(nullif(btrim(x->>'ref_no'), ''), 60), bill_date = nullif(x->>'date', '')::date, amount = (x->>'amount')::numeric,
        balance = coalesce(nullif(x->>'balance', '')::numeric, y.balance), currency = left(coalesce(x->>'currency', 'MYR'), 3), status = v_status,
        option_id = v_opt, gone = false, read_at = now(),
        paid_seen_at = case when v_status = 'paid' then coalesce(y.paid_seen_at, now()) end,
        paid_on = case when v_status = 'paid' then coalesce(nullif(x->>'paid_on', '')::date, y.paid_on) end
       where y.bill_id = v_id;
      if v_status = 'paid' and b.status in ('processing', 'draft') and b.paid_told_at is null and v_opt is not null then
        update public.creator_bills y set paid_told_at = now() where y.bill_id = v_id;
        perform public.creator_mail_job('paid', v_opt);
        v_paid := v_paid + 1;
      end if;
    end if;
    v_n := v_n + 1;
  end loop;
  update public.creator_bills y set gone = true where y.creator_id = p_creator and not (y.bill_id = any(v_seen)) and not y.gone;
  return jsonb_build_object('ok', true, 'bills', v_n, 'told', v_paid);
end $$;
revoke all on function public.creator_bills_take(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.creator_bills_take(uuid, bigint, jsonb) to service_role;

create or replace function public.creator_bills_list(p_creator uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pay boolean := public.ops_granted('campaigns.pay', 'view'); l public.bukku_links;
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.creators c where c.id = p_creator) then return jsonb_build_object('error', 'not-found'); end if;
  select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = p_creator;
  return jsonb_build_object('ok', true, 'pay', v_pay, 'linked', l.contact_id is not null,
    'read_at', (select max(b.read_at) from public.creator_bills b where b.creator_id = p_creator),
    -- The creator fees (2026-11-13): the standard fee, and whether the
    -- account a bill is posted to is set, at Creator payments View alone.
    'standard_fee', case when v_pay then (select jsonb_build_object('amount', s.amount, 'currency', s.currency)
        from public.creator_standard_fees s where s.creator_id = p_creator) end,
    'bill_account', case when v_pay then exists (select 1 from public.bukku_settings s where s.id = 1 and s.bill_account is not null) end,
    'jobs', coalesce((select jsonb_agg(jsonb_build_object(
        'option', o.id, 'job', public.creator_job_ref(o.id), 'earlier_job', o.earlier_job, 'state', o.state,
        'campaign', m.title, 'campaign_id', m.id, 'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'fee', case when v_pay then (select jsonb_build_object('amount', f.amount, 'currency', f.currency, 'source', f.source)
                 from public.creator_fees f where f.option_id = o.id) end,
        'bill', (select jsonb_build_object('number', b.number, 'ref_no', b.ref_no, 'status', b.status, 'date', b.bill_date,
                   'amount', case when v_pay then b.amount end, 'currency', b.currency, 'paid_on', case when b.status = 'paid' then coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date) end)
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = p_creator and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb),
    -- a creator's past job IDs from before the portal, each with the bill
    -- whose reference or number holds it
    'past', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'ref', e.ref,
        'bill', (select jsonb_build_object('number', b.number, 'ref_no', b.ref_no, 'status', b.status, 'date', b.bill_date,
                   'amount', case when v_pay then b.amount end, 'currency', b.currency, 'paid_on', case when b.status = 'paid' then coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date) end)
                   from public.creator_bills b
                  where b.creator_id = p_creator and b.option_id is null and not b.gone
                    and length(public.creator_ref_key(e.ref)) >= 4
                    and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                      or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0)
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by e.ref desc)
        from public.creator_earlier_jobs e where e.creator_id = p_creator and e.removed_at is null), '[]'::jsonb),
    'earlier', coalesce((select jsonb_agg(jsonb_build_object('number', b.number, 'ref', b.ref, 'ref_no', b.ref_no, 'status', b.status, 'date', b.bill_date,
        'amount', case when v_pay then b.amount end, 'currency', b.currency, 'paid_on', case when b.status = 'paid' then coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date) end) order by b.bill_date desc nulls last)
        from public.creator_bills b where b.creator_id = p_creator and b.option_id is null and not b.gone
         and not exists (select 1 from public.creator_earlier_jobs e
                          where e.creator_id = p_creator and e.removed_at is null and length(public.creator_ref_key(e.ref)) >= 4
                            and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                              or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0))), '[]'::jsonb));
end $$;
revoke all on function public.creator_bills_list(uuid) from public, anon;
grant execute on function public.creator_bills_list(uuid) to authenticated;

create or replace function public.creator_payments_queue(p_paid_from date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_pay  boolean := public.ops_granted('campaigns.pay', 'view');
  v_from date := coalesce(p_paid_from,
    (date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') - interval '1 month')::date);
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'pay', v_pay, 'work', public.ops_granted('campaigns.pay', 'work'),
    'paid_from', v_from,
    'bill_account', case when v_pay then exists (select 1 from public.bukku_settings s where s.id = 1 and s.bill_account is not null) end,
    'read_at', (select max(b.read_at) from public.creator_bills b),
    -- Payment details waiting for review, oldest first.
    'review', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'creator', cr.id, 'name', cr.name, 'code', cr.creator_code, 'ref', r.ref,
        'currency', r.currency, 'method_word', public.creator_pay_method(r.method, r.bank),
        'account_end', right(r.account, 4), 'created_at', r.created_at,
        'replaces', exists (select 1 from public.creator_pay_requests y where y.creator_id = r.creator_id and y.status = 'approved'))
        order by r.created_at)
        from public.creator_pay_requests r join public.creators cr on cr.id = r.creator_id
       where r.status = 'pending'), '[]'::jsonb),
    -- Every booking posted in the portal, or holding a live bill.
    'jobs', coalesce((select jsonb_agg(x.j order by x.k) from (
      select jsonb_build_object(
          'option', o.id, 'creator', cr.id, 'name', cr.name, 'code', cr.creator_code,
          'linked', exists (select 1 from public.bukku_links l where l.kind = 'creator' and l.record_id = cr.id and l.contact_id is not null),
          'job', public.creator_job_ref(o.id), 'state', o.state, 'campaign', case when public.client_seen(c.id, 'view') then m.title end, 'campaign_id', m.id,
          'client', case when public.client_seen(c.id, 'view') then c.name end,
          'client_code', case when public.client_seen(c.id, 'view') then c.client_code end,
          'posted_on', o.posted_on, 'pay_by', o.pay_by,
          'currency', coalesce(f.currency, (select p.currency from public.creator_pay_requests p
                                             where p.creator_id = cr.id and p.status = 'approved' order by p.seq desc limit 1), 'MYR'),
          'fee', case when v_pay and f.option_id is not null then jsonb_build_object('amount', f.amount, 'currency', f.currency) end,
          'bill', case when b.bill_id is not null then jsonb_build_object('number', b.number, 'ref_no', b.ref_no, 'status', b.status, 'date', b.bill_date,
                    'paid_on', coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date),
                    'amount', case when v_pay then b.amount end, 'currency', b.currency) end) as j,
          coalesce(o.pay_by, o.posted_on) as k
        from public.campaign_options o
        join public.creators cr on cr.id = o.creator_id
        join public.campaigns m on m.id = o.campaign_id
        join public.clients c on c.id = m.client_id
        left join public.creator_fees f on f.option_id = o.id
        left join lateral (select y.* from public.creator_bills y where y.option_id = o.id and not y.gone
                            order by (y.status = 'processing') desc, (y.status = 'draft') desc, y.bill_date desc nulls last limit 1) b on true
       where o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
         and ((b.bill_id is null and o.posted_on is not null and o.state in ('posted', 'completed'))
           or b.status in ('draft', 'processing')
           or (b.status = 'paid' and coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date, b.bill_date) >= v_from))
      ) x), '[]'::jsonb));
end $$;
revoke all on function public.creator_payments_queue(date) from public, anon;
grant execute on function public.creator_payments_queue(date) to authenticated;

-- END OF THE SUPPLIER'S REFERENCE NO. ON BUKKU LISTS -------------------------
select public.functions_tidy();
