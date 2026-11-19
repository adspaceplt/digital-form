-- ===========================================================================
-- PAYMENT PATTERNS (2026-11-19)
-- ===========================================================================
-- WHY: the user, 2026-11-19: beside Overdue invoices, "analyze the pattern
-- of each client / entity to see their payment patterns, delays, how long
-- they usually transfer payments", the figures a finance director reads,
-- "to estimate and predicts the payments inwards outwards". Agreed: a third
-- view on Clients' view strip, Payments; the last 24 months of invoices;
-- creators' and suppliers' bills as money going out; Clients: Billing at
-- Full control alone, held to the clients the colleague sees.
--
-- WHAT IT CHANGES
--   * `bukku_docs`: Bukku's sales invoices and suppliers' purchase bills as
--     last read (kind `invoice` or `bill`), each with its date, its due date
--     (its last instalment's, else its date), amount, balance, currency and
--     the day it was paid (its payments' latest, read once). Filled by
--     `bukku-sync` alone (the nightly run and Read from Bukku), through
--     `bukku_docs_take` (the service role's). RLS on, no policy, no grant.
--   * `bukku_doc_marks`: how far back each kind has been read whole
--     (`back_to`), so each run reads one month further until 24 months are
--     held. RLS on, no policy, no grant.
--   * `payment_analysis(p_currency)`: the one read. Clients: Billing at Full
--     control (`denied`; Sensitive details off shuts it with Billing), the
--     invoices held as `invoice_scope()` holds Overdue invoices (a contact
--     linked to a client the colleague sees, any contact only for one who
--     sees every client). One currency at a time, never added across. It
--     answers: the open receivables and their ages (not due, 1 to 30, 31 to
--     60, 61 to 90, over 90 days past due); days sales outstanding (what is
--     open against the last 90 days' invoicing, in days); over the invoices
--     paid in the last 12 months, the average days from invoice to payment,
--     the average days paid after the due date (an early payment counts as
--     none) and the share paid by the due date, each beside the 12 months
--     before; a row a payer (a Bukku contact: the billing entity, else the
--     client) with the same figures; and 13 weeks from this Monday of money
--     expected in (each open invoice at its due date moved by its payer's
--     average days from due to paid over the last 12 months, else everyone's,
--     never before today) and out (creators' unpaid bills by their booking's
--     Pay by, else their date, and suppliers' unpaid bills by their due
--     date, never before today; a creator's held to its campaign's client,
--     a supplier's to its client, either one with no client only for a
--     colleague who sees every client).
--   * `payment_docs` and `payment_bills` are the analysis's own reads;
--     nobody else's.
--
-- ROLLBACK:
--   drop function public.payment_analysis(text);
--   drop function public.payment_bills(jsonb);
--   drop function public.payment_docs(jsonb, date);
--   drop function public.bukku_docs_take(text, jsonb, date);
--   drop table public.bukku_doc_marks; drop table public.bukku_docs;
-- Safe to run twice.
-- ===========================================================================

create table if not exists public.bukku_docs (
  kind         text not null check (kind in ('invoice', 'bill')),
  doc_id       bigint not null,
  contact_id   bigint not null,
  contact_name text,
  number       text,
  doc_date     date not null,
  due_date     date,
  amount       numeric(14,2) not null default 0,
  balance      numeric(14,2) not null default 0,
  currency     text not null default 'MYR',
  paid_on      date,
  gone         boolean not null default false,
  read_at      timestamptz not null default now(),
  primary key (kind, doc_id)
);
create index if not exists bukku_docs_contact_idx on public.bukku_docs (kind, contact_id);
create index if not exists bukku_docs_date_idx on public.bukku_docs (kind, doc_date);
alter table public.bukku_docs enable row level security;
revoke all on table public.bukku_docs from public, anon, authenticated;

create table if not exists public.bukku_doc_marks (
  kind     text primary key check (kind in ('invoice', 'bill')),
  back_to  date,
  read_at  timestamptz
);
alter table public.bukku_doc_marks enable row level security;
revoke all on table public.bukku_doc_marks from public, anon, authenticated;

/* What bukku-sync read, kept: a row a document (id, contact, name, number,
   date, due, amount, balance, currency, paid_on, gone). A balance standing
   again clears the day it was paid; a due date or a paid day not sent keeps
   the one held. `p_back_to`: the month a run read whole, the history's
   reach. The service role's alone. */
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
    insert into public.bukku_docs as d (kind, doc_id, contact_id, contact_name, number, doc_date, due_date, amount, balance,
                                        currency, paid_on, gone, read_at)
    values (p_kind, v_id, v_contact, left(nullif(btrim(r ->> 'name'), ''), 200), left(coalesce(r ->> 'number', ''), 60), v_date,
            v_due, v_amt, coalesce(v_bal, v_amt), v_cur, case when coalesce(v_bal, v_amt) <= 0 then v_paid end,
            coalesce((r ->> 'gone') = 'true', false), now())
    on conflict (kind, doc_id) do update set
      contact_id = excluded.contact_id,
      contact_name = coalesce(excluded.contact_name, d.contact_name),
      number = excluded.number,
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

/* The invoices a scope holds (`invoice_scope()`'s answer), dated from
   p_from: each with its payer, a contact linked to a client named by that
   client's company or name. */
create or replace function public.payment_docs(p_scope jsonb, p_from date)
returns table (doc_id bigint, contact_id bigint, doc_date date, due date, amount numeric, balance numeric, currency text,
               paid_on date, client_id uuid, client_name text, slug text, code text, payer text)
language sql stable security definer set search_path = public as $$
  with lk as (
    select (l ->> 'contact')::bigint as contact, (l ->> 'client')::uuid as client, l ->> 'name' as name,
           l ->> 'slug' as slug, l ->> 'code' as code, nullif(l ->> 'company', '') as company
      from jsonb_array_elements(coalesce(p_scope -> 'links', '[]'::jsonb)) l
  )
  select d.doc_id, d.contact_id, d.doc_date, coalesce(d.due_date, d.doc_date), d.amount, d.balance, d.currency, d.paid_on,
         lk.client, lk.name, lk.slug, lk.code, coalesce(lk.company, lk.name, d.contact_name, 'Bukku contact')
    from public.bukku_docs d left join lk on lk.contact = d.contact_id
   where d.kind = 'invoice' and not d.gone and d.doc_date >= p_from
     and (lk.contact is not null or coalesce((p_scope ->> 'all')::boolean, false))
$$;
revoke all on function public.payment_docs(jsonb, date) from public, anon, authenticated;

/* Money going out (2026-11-19): creators' unpaid bills by their booking's
   Pay by, else their date; suppliers' unpaid bills by their due date. A
   creator's held to its campaign's client, a supplier's to its client; one
   with no client only where the scope sees every client. */
create or replace function public.payment_bills(p_scope jsonb)
returns table (source text, due date, amount numeric, currency text)
language sql stable security definer set search_path = public as $$
  select 'creator', coalesce(o.pay_by, b.bill_date), coalesce(b.balance, b.amount), coalesce(b.currency, 'MYR')
    from public.creator_bills b
    left join public.campaign_options o on o.id = coalesce(b.option_id, b.made_for)
    left join public.campaigns m on m.id = o.campaign_id
   where not b.gone and b.status in ('draft', 'processing') and coalesce(b.balance, b.amount) > 0
     and coalesce(o.pay_by, b.bill_date) is not null
     and (coalesce((p_scope ->> 'all')::boolean, false) or (m.client_id is not null and public.client_seen(m.client_id, 'view')))
  union all
  select 'supplier', coalesce(d.due_date, d.doc_date), d.balance, d.currency
    from public.bukku_docs d
   where d.kind = 'bill' and not d.gone and d.balance > 0
     and (coalesce((p_scope ->> 'all')::boolean, false) or exists (
       select 1 from public.bukku_links bl join public.suppliers s on s.id = bl.record_id
        where bl.kind = 'supplier' and bl.contact_id = d.contact_id and s.client_id is not null
          and public.client_seen(s.client_id, 'view')))
$$;
revoke all on function public.payment_bills(jsonb) from public, anon, authenticated;

create or replace function public.payment_analysis(p_currency text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_from date;
  v_y1 date;
  v_y2 date;
  v_wk0 date;
  v_scope jsonb;
  v_cur text;
  v_curs jsonb;
  v_lag numeric;
  v_sum jsonb;
  v_payers jsonb;
  v_weeks jsonb;
  v_later jsonb;
  v_marks jsonb;
begin
  if me.id is null or not public.allowed('clients.billing', 'manage') then
    return jsonb_build_object('error', 'denied');
  end if;
  v_scope := public.invoice_scope();
  if v_scope ? 'error' then return jsonb_build_object('error', v_scope ->> 'error'); end if;
  v_from := (v_today - interval '24 months')::date;
  v_y1 := (v_today - interval '12 months')::date;
  v_y2 := v_from;
  v_wk0 := v_today - (extract(isodow from v_today)::integer - 1);

  select coalesce(jsonb_agg(c.currency order by c.currency <> 'MYR', c.n desc, c.currency), '[]'::jsonb) into v_curs
    from (select x.currency, count(*) as n from public.payment_docs(v_scope, v_from) x group by x.currency) c;
  v_cur := case when p_currency is not null and v_curs ? p_currency then p_currency
                when v_curs ? 'MYR' or jsonb_array_length(v_curs) = 0 then 'MYR'
                else v_curs ->> 0 end;

  /* Everyone's average days from due to paid, for a payer with none. */
  select avg(x.paid_on - x.due) into v_lag
    from public.payment_docs(v_scope, v_from) x
   where x.currency = v_cur and x.balance <= 0 and x.paid_on is not null and x.paid_on > v_y1;

  select jsonb_build_object(
      'open', coalesce(sum(x.balance) filter (where x.balance > 0), 0),
      'overdue', coalesce(sum(x.balance) filter (where x.balance > 0 and x.due < v_today), 0),
      'open_count', count(*) filter (where x.balance > 0),
      'aging', jsonb_build_object(
        'current', coalesce(sum(x.balance) filter (where x.balance > 0 and x.due >= v_today), 0),
        'd30', coalesce(sum(x.balance) filter (where x.balance > 0 and v_today - x.due between 1 and 30), 0),
        'd60', coalesce(sum(x.balance) filter (where x.balance > 0 and v_today - x.due between 31 and 60), 0),
        'd90', coalesce(sum(x.balance) filter (where x.balance > 0 and v_today - x.due between 61 and 90), 0),
        'over90', coalesce(sum(x.balance) filter (where x.balance > 0 and v_today - x.due > 90), 0)),
      'invoiced_90', coalesce(sum(x.amount) filter (where x.doc_date > v_today - 90), 0),
      'dso', case when coalesce(sum(x.amount) filter (where x.doc_date > v_today - 90), 0) > 0
                  then round(coalesce(sum(x.balance) filter (where x.balance > 0), 0)
                             / sum(x.amount) filter (where x.doc_date > v_today - 90) * 90) end,
      'paid', count(*) filter (where x.balance <= 0 and x.paid_on > v_y1),
      'days_to_pay', round(avg(x.paid_on - x.doc_date) filter (where x.balance <= 0 and x.paid_on > v_y1), 1),
      'days_late', round(avg(greatest(0, x.paid_on - x.due)) filter (where x.balance <= 0 and x.paid_on > v_y1), 1),
      'on_time', round(100.0 * count(*) filter (where x.balance <= 0 and x.paid_on > v_y1 and x.paid_on <= x.due)
                       / nullif(count(*) filter (where x.balance <= 0 and x.paid_on > v_y1), 0)),
      'paid_before', count(*) filter (where x.balance <= 0 and x.paid_on > v_y2 and x.paid_on <= v_y1),
      'days_to_pay_before', round(avg(x.paid_on - x.doc_date) filter (where x.balance <= 0 and x.paid_on > v_y2 and x.paid_on <= v_y1), 1),
      'days_late_before', round(avg(greatest(0, x.paid_on - x.due)) filter (where x.balance <= 0 and x.paid_on > v_y2 and x.paid_on <= v_y1), 1),
      'on_time_before', round(100.0 * count(*) filter (where x.balance <= 0 and x.paid_on > v_y2 and x.paid_on <= v_y1 and x.paid_on <= x.due)
                       / nullif(count(*) filter (where x.balance <= 0 and x.paid_on > v_y2 and x.paid_on <= v_y1), 0)),
      'invoices', count(*))
    into v_sum
    from public.payment_docs(v_scope, v_from) x
   where x.currency = v_cur;

  select coalesce(jsonb_agg(to_jsonb(p) - 'lag' order by p.open desc, p.name), '[]'::jsonb) into v_payers
    from (
      select x.contact_id as contact, min(x.payer) as name, x.client_id as client, x.client_name, x.slug, x.code,
             count(*) as invoices,
             count(*) filter (where x.balance <= 0) as paid,
             round(avg(x.paid_on - x.doc_date) filter (where x.balance <= 0 and x.paid_on > v_y1), 1) as days_to_pay,
             round(avg(greatest(0, x.paid_on - x.due)) filter (where x.balance <= 0 and x.paid_on > v_y1), 1) as days_late,
             round(100.0 * count(*) filter (where x.balance <= 0 and x.paid_on > v_y1 and x.paid_on <= x.due)
                   / nullif(count(*) filter (where x.balance <= 0 and x.paid_on > v_y1), 0)) as on_time,
             round(avg(greatest(0, x.paid_on - x.due)) filter (where x.balance <= 0 and x.paid_on > v_y2 and x.paid_on <= v_y1), 1) as late_before,
             coalesce(sum(x.balance) filter (where x.balance > 0), 0) as open,
             coalesce(sum(x.balance) filter (where x.balance > 0 and x.due < v_today), 0) as overdue,
             max(x.paid_on) as last_paid,
             avg(x.paid_on - x.due) filter (where x.balance <= 0 and x.paid_on > v_y1) as lag
        from public.payment_docs(v_scope, v_from) x
       where x.currency = v_cur
       group by x.contact_id, x.client_id, x.client_name, x.slug, x.code
    ) p;

  /* Thirteen weeks from this Monday: in, each open invoice at its due date
     moved by its payer's lag; out, the unpaid bills by their due date; never
     before today; what falls after the thirteenth week is `later`. */
  with lags as (
    select x.contact_id, avg(x.paid_on - x.due) as lag
      from public.payment_docs(v_scope, v_from) x
     where x.currency = v_cur and x.balance <= 0 and x.paid_on is not null and x.paid_on > v_y1
     group by x.contact_id
  ), ins as (
    select greatest(v_today, x.due + round(coalesce(l.lag, v_lag, 0))::integer) as at, x.balance as amt
      from public.payment_docs(v_scope, v_from) x left join lags l on l.contact_id = x.contact_id
     where x.currency = v_cur and x.balance > 0
  ), outs as (
    select greatest(v_today, b.due) as at, b.amount as amt, b.source
      from public.payment_bills(v_scope) b where b.currency = v_cur
  ), wk as (
    select g as n, v_wk0 + g * 7 as start from generate_series(0, 12) g
  )
  select jsonb_agg(jsonb_build_object('start', wk.start,
           'in', coalesce((select sum(i.amt) from ins i where i.at >= wk.start and i.at < wk.start + 7), 0),
           'out', coalesce((select sum(o.amt) from outs o where o.at >= wk.start and o.at < wk.start + 7), 0),
           'creators', coalesce((select sum(o.amt) from outs o where o.source = 'creator' and o.at >= wk.start and o.at < wk.start + 7), 0),
           'suppliers', coalesce((select sum(o.amt) from outs o where o.source = 'supplier' and o.at >= wk.start and o.at < wk.start + 7), 0))
           order by wk.n),
         jsonb_build_object(
           'in', coalesce((select sum(i.amt) from ins i where i.at >= v_wk0 + 91), 0),
           'out', coalesce((select sum(o.amt) from outs o where o.at >= v_wk0 + 91), 0))
    into v_weeks, v_later
    from wk;

  select jsonb_build_object('back_to', min(m.back_to) filter (where m.kind = 'invoice'), 'read_at', max(m.read_at))
    into v_marks from public.bukku_doc_marks m;

  return jsonb_build_object('ok', true, 'today', v_today, 'from', v_from, 'currency', v_cur, 'currencies', v_curs,
    'all', coalesce((v_scope ->> 'all')::boolean, false), 'lag', round(v_lag, 1),
    'summary', v_sum, 'payers', v_payers, 'weeks', v_weeks, 'later', v_later,
    'back_to', v_marks ->> 'back_to', 'read_at', v_marks ->> 'read_at');
end $$;
revoke all on function public.payment_analysis(text) from public, anon;
grant execute on function public.payment_analysis(text) to authenticated;

-- END OF PAYMENT PATTERNS ----------------------------------------------------

select public.functions_tidy();
