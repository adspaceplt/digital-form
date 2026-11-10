-- ============================================================================
-- CONTENT LOOP, PHASE 3: A MONTH'S INVOICE FROM ITS 1ST (2026-11-10)
-- ============================================================================
-- The user, 2026-11-10: "our way is invoice issued 01/11 for November (its
-- pre-issued basis not upon completion)". A client's month is invoiced in
-- advance, so its invoice is looked for from the 1st of its content month,
-- whatever its stage, never waiting for the month to be completed:
--
--   1. `month_invoice_window(p_period)`: the content month's calendar
--      month, the days an invoice for it is dated in (internal).
--   2. `ops_month_invoice_ask(p_engagement)`: any month not cancelled whose
--      1st has come (MYT); `cancelled`, `not-started` (was
--      `not-completed`).
--   3. `ops_month_invoices_due()`: the months the night reads, from their
--      1st, in the last four months, not cancelled: never checked, none
--      found, or an invoice found still unpaid, each last read 20 hours
--      ago or more.
--   4. `ops_months_not_invoiced()`: a month not cancelled with none found
--      by a read made after its 1st had ended (MYT), so a read on the
--      morning of the 1st, before the invoice is issued, flags nothing.
--
-- Re-runnable. Rollback: run 2026-11-10-month-invoice-check.sql again and
-- drop `month_invoice_window`.

create or replace function public.month_invoice_window(p_period text)
returns table (starts date, ends date)
language sql immutable set search_path = public as $$
  select to_date(p_period || '-01', 'YYYY-MM-DD'),
         (to_date(p_period || '-01', 'YYYY-MM-DD') + interval '1 month' - interval '1 day')::date
$$;
revoke all on function public.month_invoice_window(text) from public, anon, authenticated;

create or replace function public.ops_month_invoice_ask(p_engagement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e  public.ops_engagements;
  v_from date;
  v_to   date;
  v_c    bigint[];
begin
  if (public.ops_me()).id is null or not public.allowed('clients.billing', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into e from public.ops_engagements x where x.id = p_engagement;
  if e.id is null or not public.ops_may_see_engagement(e.id) or not public.client_seen(e.client_id, 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if e.status = 'cancelled' then return jsonb_build_object('error', 'cancelled'); end if;
  select w.starts, w.ends into v_from, v_to from public.month_invoice_window(e.period) w;
  if v_from > (now() at time zone 'Asia/Kuala_Lumpur')::date then
    return jsonb_build_object('error', 'not-started');
  end if;
  v_c := public.month_invoice_contacts(e.client_id);
  if cardinality(v_c) = 0 then return jsonb_build_object('error', 'not-linked'); end if;
  return jsonb_build_object('ok', true, 'engagement', e.id, 'client', e.client_id, 'from', v_from, 'to', v_to,
    'contacts', to_jsonb(v_c));
end $$;
revoke all on function public.ops_month_invoice_ask(uuid) from public, anon;
grant execute on function public.ops_month_invoice_ask(uuid) to authenticated;

create or replace function public.ops_month_invoices_due()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('engagement', e.id, 'from', w.starts, 'to', w.ends,
           'contacts', to_jsonb(public.month_invoice_contacts(e.client_id))) order by e.period desc), '[]'::jsonb)
    from public.ops_engagements e
    cross join lateral public.month_invoice_window(e.period) w
    left join public.ops_month_invoices m on m.engagement_id = e.id
   where e.status <> 'cancelled'
     and w.starts <= (now() at time zone 'Asia/Kuala_Lumpur')::date
     and e.period >= to_char((now() at time zone 'Asia/Kuala_Lumpur')::date - interval '4 months', 'YYYY-MM')
     and (m.engagement_id is null
          or (m.checked_at < now() - interval '20 hours'
              and (m.state = 'none' or exists (select 1 from jsonb_array_elements(m.invoices) v
                                                where coalesce((v->>'paid')::boolean, false) = false))))
     and cardinality(public.month_invoice_contacts(e.client_id)) > 0
$$;
revoke all on function public.ops_month_invoices_due() from public, anon, authenticated;
grant execute on function public.ops_month_invoices_due() to service_role;

create or replace function public.ops_months_not_invoiced()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('clients.billing', 'manage') then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('engagement', e.id, 'client', c.id, 'name', c.name, 'slug', c.slug,
             'owner', c.owner, 'period', e.period, 'checked_at', m.checked_at, 'since', w.starts)
             order by e.period, c.name)
      from public.ops_month_invoices m
      join public.ops_engagements e on e.id = m.engagement_id
      join public.clients c on c.id = e.client_id
      cross join lateral public.month_invoice_window(e.period) w
     where m.state = 'none' and e.status <> 'cancelled'
       and (m.checked_at at time zone 'Asia/Kuala_Lumpur')::date > w.starts
       and public.client_seen(c.id, 'view')), '[]'::jsonb);
end $$;
revoke all on function public.ops_months_not_invoiced() from public, anon;
grant execute on function public.ops_months_not_invoiced() to authenticated;

select public.functions_tidy();
