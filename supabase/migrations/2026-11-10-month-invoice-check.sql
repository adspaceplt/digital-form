-- ============================================================================
-- CONTENT LOOP, PHASE 3: A COMPLETED MONTH AND ITS INVOICE IN BUKKU (2026-11-10)
-- ============================================================================
-- The user, 2026-11-10: "phase 2 and 3 proceed all until completion". A
-- client's month completed in My Work is checked against Bukku: an invoice
-- the client's Bukku contacts were sent, dated within the month's own span
-- (`ops_month_span`), is the month's invoice. Nothing is written in Bukku.
--
--   1. `ops_month_invoices` (RLS on, no policy, no grant): a completed
--      month's last check, `found` with the invoices read (number, date,
--      amount, currency, paid, Bukku's own link) or `none`.
--   2. `month_invoice_contacts(p_client)`: the Bukku contacts billing a
--      client (its own, its supplier's, each billing entity's); internal.
--   3. `ops_month_invoice_ask(p_engagement)`: what `bukku-sync` `month` reads
--      for the caller (the month seen in My Work, Clients: Billing at View,
--      the client in scope; `not-completed`, `not-linked`).
--   4. `ops_month_invoice_take(p_engagement, p_invoices)`: the check kept,
--      the service role's alone; `ops_month_invoices_due()` the months the
--      night reads again (completed in the last four months, never checked
--      or none found, last checked 20 hours ago or more).
--   5. `ops_month_invoices_of(p_client)` (Billing View, in scope) for the
--      client's Months, and `ops_months_not_invoiced()` (Billing Full
--      Access) for the Dashboard's Needs attention.
--
-- Re-runnable. Rollback: drop the functions in 2 to 5 and the table.

create table if not exists public.ops_month_invoices (
  engagement_id uuid primary key references public.ops_engagements(id) on delete cascade,
  client_id     uuid not null,
  state         text not null check (state in ('found', 'none')),
  invoices      jsonb not null default '[]'::jsonb,
  checked_at    timestamptz not null default now()
);
alter table public.ops_month_invoices enable row level security;
revoke all on public.ops_month_invoices from public, anon, authenticated;

create or replace function public.month_invoice_contacts(p_client uuid)
returns bigint[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct x.contact_id), '{}'::bigint[]) from (
    select b.contact_id from public.bukku_links b where b.kind = 'client' and b.record_id = p_client
    union all
    select b.contact_id from public.bukku_links b join public.suppliers s on s.id = b.record_id
     where b.kind = 'supplier' and s.client_id = p_client
    union all
    select b.contact_id from public.bukku_links b join public.client_entities ce on ce.entity_id = b.record_id
     where b.kind = 'entity' and ce.client_id = p_client
  ) x where x.contact_id is not null
$$;
revoke all on function public.month_invoice_contacts(uuid) from public, anon, authenticated;

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
  if e.status <> 'completed' then return jsonb_build_object('error', 'not-completed'); end if;
  select s.starts, s.ends into v_from, v_to from public.ops_month_span(e.period, e.start_day) s;
  v_c := public.month_invoice_contacts(e.client_id);
  if cardinality(v_c) = 0 then return jsonb_build_object('error', 'not-linked'); end if;
  return jsonb_build_object('ok', true, 'engagement', e.id, 'client', e.client_id, 'from', v_from, 'to', v_to,
    'contacts', to_jsonb(v_c));
end $$;
revoke all on function public.ops_month_invoice_ask(uuid) from public, anon;
grant execute on function public.ops_month_invoice_ask(uuid) to authenticated;

create or replace function public.ops_month_invoice_take(p_engagement uuid, p_invoices jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e  public.ops_engagements;
  v_list jsonb := case when jsonb_typeof(p_invoices) = 'array' then p_invoices else '[]'::jsonb end;
begin
  select * into e from public.ops_engagements x where x.id = p_engagement;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.ops_month_invoices (engagement_id, client_id, state, invoices, checked_at)
  values (e.id, e.client_id, case when jsonb_array_length(v_list) > 0 then 'found' else 'none' end, v_list, now())
  on conflict (engagement_id) do update set client_id = excluded.client_id, state = excluded.state,
    invoices = excluded.invoices, checked_at = now();
  return (select jsonb_build_object('ok', true, 'state', m.state, 'invoices', m.invoices, 'checked_at', m.checked_at)
            from public.ops_month_invoices m where m.engagement_id = e.id);
end $$;
revoke all on function public.ops_month_invoice_take(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ops_month_invoice_take(uuid, jsonb) to service_role;

create or replace function public.ops_month_invoices_due()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('engagement', e.id, 'from', s.starts, 'to', s.ends,
           'contacts', to_jsonb(public.month_invoice_contacts(e.client_id))) order by e.period desc), '[]'::jsonb)
    from public.ops_engagements e
    cross join lateral public.ops_month_span(e.period, e.start_day) s
    left join public.ops_month_invoices m on m.engagement_id = e.id
   where e.status = 'completed'
     and e.period >= to_char((now() at time zone 'Asia/Kuala_Lumpur')::date - interval '4 months', 'YYYY-MM')
     and (m.engagement_id is null or (m.state = 'none' and m.checked_at < now() - interval '20 hours'))
     and cardinality(public.month_invoice_contacts(e.client_id)) > 0
$$;
revoke all on function public.ops_month_invoices_due() from public, anon, authenticated;
grant execute on function public.ops_month_invoices_due() to service_role;

create or replace function public.ops_month_invoices_of(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('clients.billing', 'view')
     or not public.client_seen(p_client, 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true,
    'linked', cardinality(public.month_invoice_contacts(p_client)) > 0,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('engagement', m.engagement_id, 'state', m.state,
              'invoices', m.invoices, 'checked_at', m.checked_at))
              from public.ops_month_invoices m where m.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.ops_month_invoices_of(uuid) from public, anon;
grant execute on function public.ops_month_invoices_of(uuid) to authenticated;

create or replace function public.ops_months_not_invoiced()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('clients.billing', 'manage') then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('engagement', e.id, 'client', c.id, 'name', c.name, 'slug', c.slug,
             'owner', c.owner, 'period', e.period, 'checked_at', m.checked_at, 'since', e.updated_at)
             order by e.period, c.name)
      from public.ops_month_invoices m
      join public.ops_engagements e on e.id = m.engagement_id
      join public.clients c on c.id = e.client_id
     where m.state = 'none' and e.status = 'completed' and public.client_seen(c.id, 'view')), '[]'::jsonb);
end $$;
revoke all on function public.ops_months_not_invoiced() from public, anon;
grant execute on function public.ops_months_not_invoiced() to authenticated;

select public.functions_tidy();
