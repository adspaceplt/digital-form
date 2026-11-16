-- ===========================================================================
-- QUOTATION INVOICES — an approved quotation's invoices made as Bukku drafts,
-- one a billing cycle (2026-11-17)
-- ===========================================================================
-- WHY (the user, 2026-11-17, approving the Quotation to Bukku Invoice
-- proposal): finance retyped every approved quotation's lines into Bukku.
-- Option B: the portal prepares each cycle's invoice from the quotation and
-- creates it in Bukku as a draft; finance approves it there. A line's Bukku
-- product is the Rate Card line's SKU, whose product carries its income
-- account. The advertising budget is its own invoice, to a debtor contact
-- the team chooses for the client, with no SST. A cycle starts on the day
-- the services start (the 1st, the 16th, the 23rd) and runs a full month;
-- the first is never pro-rated. Clients: Billing at Work makes them.
--
-- WHAT IT ADDS
--   * `bukku_settings.budget_account_code`: the account the advertising
--     budget's line posts to (Settings, Money, Bukku; `bukku_invoice_set`).
--   * `client_ad_debtors`: the Bukku contact a client's advertising budget is
--     invoiced to (`client_ad_debtor_set`), else the client's own contact.
--   * `quotation_invoices`: one row a quotation, cycle and kind (service or
--     budget), its Bukku draft's id and number once made; held ten minutes
--     while one is being made, so a second press makes no second draft.
--   * `quotation_cycle_lines`: the lines a cycle bills, each priced at its
--     rate after its term percentage, its SKU and Bukku tax code.
--   * `quotation_invoice_prep` / `_done` (as the caller) and
--     `quotation_invoices_of` (the schedule: every cycle of the term).
--
-- ORDER: this file, then bukku-sync, then the pages. Safe to run twice.
-- ROLLBACK: drop the six functions and the two tables; the column can stay.
-- ===========================================================================

alter table public.bukku_settings add column if not exists budget_account_code text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'bukku_settings_budget_account_code_check') then
    alter table public.bukku_settings add constraint bukku_settings_budget_account_code_check
      check (budget_account_code is null or budget_account_code ~ '^[A-Za-z0-9._/-]{1,30}$');
  end if;
end $$;

create table if not exists public.client_ad_debtors (
  client_id  uuid primary key references public.clients(id) on delete cascade,
  contact_id bigint not null check (contact_id > 0),
  code       text,
  name       text check (name is null or length(name) <= 200),
  set_by     uuid references public.team_members(id) on delete set null,
  set_at     timestamptz not null default now()
);
alter table public.client_ad_debtors enable row level security;
revoke all on table public.client_ad_debtors from public, anon, authenticated;

create table if not exists public.quotation_invoices (
  quotation_id uuid not null references public.quotations(id) on delete cascade,
  cycle        int not null check (cycle between 1 and 36),
  kind         text not null check (kind in ('service', 'budget')),
  bukku_id     bigint,
  number       text check (number is null or length(number) <= 60),
  amount       numeric(14,2),
  currency     text,
  made_at      timestamptz,
  made_by      uuid references public.team_members(id) on delete set null,
  claimed_at   timestamptz,
  claimed_by   uuid references public.team_members(id) on delete set null,
  primary key (quotation_id, cycle, kind)
);
alter table public.quotation_invoices enable row level security;
revoke all on table public.quotation_invoices from public, anon, authenticated;

/* The day the quotation's services start: its confirmed lines' earliest
   start, set at approval. */
create or replace function public.quotation_start(p_id uuid)
returns date language sql stable security definer set search_path = public as $$
  select min(case when s.start_on ~ '^\d{4}-\d{2}-\d{2}$' then s.start_on::date
                  when s.start_on ~ '^\d{4}-\d{2}$' then (s.start_on || '-01')::date end)
    from public.client_services s
   where s.quotation_id = p_id and s.archived_at is null
$$;
revoke all on function public.quotation_start(uuid) from public, anon, authenticated;

/* The lines one cycle bills. A monthly line bills each cycle up to its
   months; a one-off line the first cycle alone. Each is priced at its rate
   after its own term percentage, to the cent, as the quotation totals it;
   its SKU is the Rate Card line's, its tax Bukku's code for its rate. The
   advertising budget: each platform's monthly amount up to its months, a
   one-off amount the first cycle, no tax. */
create or replace function public.quotation_cycle_lines(p_id uuid, p_cycle int, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  v_out jsonb := '[]'::jsonb;
  e jsonb;
  v_months int; v_month boolean; v_pct numeric; v_rate numeric; v_unit numeric;
  v_sst numeric; v_tax text; v_sku text;
begin
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null then return v_out; end if;
  if p_kind = 'budget' then
    for e in select x from jsonb_array_elements(coalesce(q.totals->'ads', '[]'::jsonb)) x loop
      v_month := coalesce(e->>'freq', 'monthly') = 'monthly';
      v_months := greatest(1, coalesce((e->>'months')::int, 1));
      if (v_month and p_cycle <= v_months) or (not v_month and p_cycle = 1) then
        v_unit := round(coalesce((e->>'budget')::numeric, (e->>'amount')::numeric, 0), 2);
        if v_unit > 0 then
          v_out := v_out || jsonb_build_object('label', 'Advertising budget · ' ||
            case lower(coalesce(e->>'platform', '')) when 'meta' then 'Meta' when 'tiktok' then 'TikTok' when 'google' then 'Google'
              when 'xhs' then 'rednote' when 'rednote' then 'rednote' else initcap(coalesce(e->>'platform', 'Other')) end,
            'qty', 1, 'unit', v_unit, 'sst', 0);
        end if;
      end if;
    end loop;
    return v_out;
  end if;
  for e in select x from jsonb_array_elements(coalesce(q.lines, '[]'::jsonb)) x loop
    if coalesce((e->>'in_plan')::boolean, false) then continue; end if;
    v_month := e->>'basis' = 'month';
    v_months := greatest(1, coalesce((e->>'months')::int, (q.totals->>'term')::int, 1));
    if not ((v_month and p_cycle <= v_months) or (not v_month and p_cycle = 1)) then continue; end if;
    v_rate := coalesce((e->>'rate')::numeric, 0);
    v_pct := case when v_month then coalesce((e->>'pct')::numeric, (q.totals->>'term_pct')::numeric, 0) else 0 end;
    v_unit := round(v_rate * (1 + v_pct / 100), 2);
    v_sst := coalesce((e->>'tax_pct')::numeric, (e->>'sst')::numeric, (q.totals->>'sst_pct')::numeric, 0);
    v_tax := null;
    if coalesce(e->>'tax', '') <> '' then
      select t.bukku_id into v_tax from public.tax_codes t where t.code = e->>'tax';
    end if;
    if v_tax is null and v_sst > 0 then
      select t.bukku_id into v_tax from public.tax_codes t
       where t.active and t.rate = v_sst and t.bukku_id is not null
       order by (t.code ilike 'SV%') desc, t.code limit 1;
    end if;
    v_sku := null;
    if coalesce(e->>'slug', '') <> '' then
      select nullif(btrim(s.sku), '') into v_sku from public.services s where s.slug = e->>'slug';
    end if;
    v_out := v_out || jsonb_strip_nulls(jsonb_build_object('label', coalesce(nullif(btrim(e->>'label'), ''), 'Service'),
      'qty', coalesce((e->>'qty')::numeric, 1), 'unit', v_unit, 'sst', v_sst, 'tax', v_tax, 'sku', v_sku,
      'pct', case when v_pct <> 0 then v_pct end, 'month', v_month));
  end loop;
  return v_out;
end $$;
revoke all on function public.quotation_cycle_lines(uuid, integer, text) from public, anon, authenticated;

/* The number of cycles a quotation bills: its term, else one. */
create or replace function public.quotation_cycles(p_id uuid)
returns int language sql stable security definer set search_path = public as $$
  select least(36, greatest(1, coalesce((q.totals->>'term')::int, 1),
         coalesce((select max(coalesce((e->>'months')::int, 1)) from jsonb_array_elements(coalesce(q.lines, '[]'::jsonb)) e
                    where e->>'basis' = 'month'), 1),
         coalesce((select max(coalesce((e->>'months')::int, 1)) from jsonb_array_elements(coalesce(q.totals->'ads', '[]'::jsonb)) e
                    where coalesce(e->>'freq', 'monthly') = 'monthly'), 1)))
    from public.quotations q where q.id = p_id
$$;
revoke all on function public.quotation_cycles(uuid) from public, anon, authenticated;

/* The schedule: each cycle of the term, its day, what it bills and the
   draft made for it. Clients: Billing at View, the client in scope. */
create or replace function public.quotation_invoices_of(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  v_start date;
  v_n int;
  v_rows jsonb := '[]'::jsonb;
  i int; k text; v_lines jsonb; v_sum numeric; r public.quotation_invoices;
  v_day date;
begin
  if (public.ops_me()).id is null or not public.allowed('clients.billing', 'view') then return jsonb_build_object('error', 'denied'); end if;
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
      v_rows := v_rows || jsonb_strip_nulls(jsonb_build_object('cycle', i, 'kind', k, 'date', v_day,
        'until', case when v_day is not null then ((v_start + make_interval(months => i))::date - 1) end,
        'amount', v_sum, 'number', r.number, 'bukku_id', r.bukku_id, 'made_at', r.made_at,
        'creating', r.claimed_at is not null and r.claimed_at > now() - interval '10 minutes' and r.number is null));
    end loop;
  end loop;
  return jsonb_build_object('ok', true, 'ref', q.ref, 'start', v_start, 'cycles', v_n,
    'currency', coalesce(q.totals->>'currency', 'MYR'), 'rows', v_rows,
    'debtor', (select jsonb_build_object('contact_id', d.contact_id, 'code', d.code, 'name', d.name) from public.client_ad_debtors d where d.client_id = q.client_id),
    'budget_account', (select b.budget_account_code from public.bukku_settings b where b.id = 1));
end $$;
revoke all on function public.quotation_invoices_of(uuid) from public, anon;
grant execute on function public.quotation_invoices_of(uuid) to authenticated;

/* One cycle's draft asked for: everything bukku-sync sends, read as the
   caller, the press held ten minutes. */
create or replace function public.quotation_invoice_prep(p_id uuid, p_cycle int, p_kind text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q public.quotations;
  r public.quotation_invoices;
  b public.bukku_settings;
  v_start date; v_day date; v_lines jsonb; v_contact bigint; v_ent uuid; v_cur text; v_fx numeric := 1;
  v_ref text;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind is null or p_kind not in ('service', 'budget') or p_cycle is null or p_cycle < 1 or p_cycle > 36 then
    return jsonb_build_object('error', 'bad-request');
  end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  if q.removed_at is not null then return jsonb_build_object('error', 'removed'); end if;
  v_start := public.quotation_start(q.id);
  if v_start is null then return jsonb_build_object('error', 'no-start'); end if;
  if p_cycle > public.quotation_cycles(q.id) then return jsonb_build_object('error', 'bad-request'); end if;
  v_lines := public.quotation_cycle_lines(q.id, p_cycle, p_kind);
  if jsonb_array_length(v_lines) = 0 then return jsonb_build_object('error', 'nothing'); end if;
  select * into b from public.bukku_settings where id = 1;
  if p_kind = 'budget' then
    if b.budget_account_code is null then return jsonb_build_object('error', 'no-budget-account'); end if;
    select d.contact_id into v_contact from public.client_ad_debtors d where d.client_id = q.client_id;
  end if;
  if v_contact is null then
    v_ent := nullif(q.totals->'bill_to'->>'entity_id', '')::uuid;
    if v_ent is not null then
      select l.contact_id into v_contact from public.bukku_links l where l.kind = 'entity' and l.record_id = v_ent;
    end if;
    if v_contact is null then
      select l.contact_id into v_contact from public.bukku_links l where l.kind = 'client' and l.record_id = q.client_id;
    end if;
    if v_contact is null then
      v_contact := (public.bukku_shared('client', q.client_id)->>'contact_id')::bigint;
    end if;
  end if;
  if v_contact is null then return jsonb_build_object('error', 'not-linked'); end if;
  if p_kind = 'service' and exists (select 1 from jsonb_array_elements(v_lines) x where (x->>'sst')::numeric > 0 and x->>'tax' is null) then
    return jsonb_build_object('error', 'no-tax-code');
  end if;
  v_cur := case when q.totals->>'currency' = 'SGD' then 'SGD' else 'MYR' end;
  if v_cur = 'SGD' then
    v_fx := nullif(coalesce((q.totals->>'fx')::numeric, 0), 0);
    if v_fx is null then return jsonb_build_object('error', 'no-fx'); end if;
  end if;
  select * into r from public.quotation_invoices x where x.quotation_id = q.id and x.cycle = p_cycle and x.kind = p_kind for update;
  if r.number is not null then return jsonb_build_object('error', 'invoiced', 'number', r.number); end if;
  if r.claimed_at is not null and r.claimed_at > now() - interval '10 minutes' then return jsonb_build_object('error', 'creating'); end if;
  insert into public.quotation_invoices (quotation_id, cycle, kind, claimed_at, claimed_by)
  values (q.id, p_cycle, p_kind, now(), me.id)
  on conflict (quotation_id, cycle, kind) do update set claimed_at = now(), claimed_by = me.id;
  v_day := (v_start + make_interval(months => p_cycle - 1))::date;
  -- Bukku's second number names the quotation and the cycle, so one is found again.
  v_ref := left(q.ref || ' · ' || to_char(v_day, 'YYYY-MM-DD') || case when p_kind = 'budget' then ' · Ads' else '' end, 50);
  return jsonb_build_object('ok', true, 'contact_id', v_contact, 'ref', v_ref, 'date', v_day,
    'until', ((v_start + make_interval(months => p_cycle))::date - 1), 'currency', v_cur, 'fx', v_fx,
    'kind', p_kind, 'lines', v_lines, 'account_code', case when p_kind = 'budget' then b.budget_account_code end,
    'description', left(q.brand || ' · ' || q.ref || ' · ' || public.register_day(v_day) ||
      case when p_kind = 'budget' then ' · Advertising budget' else '' end, 200));
end $$;
revoke all on function public.quotation_invoice_prep(uuid, integer, text) from public, anon;
grant execute on function public.quotation_invoice_prep(uuid, integer, text) to authenticated;

/* The press let go: the draft's id and number kept where one was made (or
   found), filed on the client. */
create or replace function public.quotation_invoice_done(p_id uuid, p_cycle int, p_kind text, p_bukku bigint, p_number text, p_amount numeric)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q public.quotations;
  v_num text := nullif(left(btrim(coalesce(p_number, '')), 60), '');
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if v_num is null then
    update public.quotation_invoices set claimed_at = null, claimed_by = null
     where quotation_id = q.id and cycle = p_cycle and kind = p_kind and number is null;
    return jsonb_build_object('ok', true);
  end if;
  update public.quotation_invoices set number = v_num, bukku_id = nullif(p_bukku, 0), amount = p_amount,
         currency = case when q.totals->>'currency' = 'SGD' then 'SGD' else 'MYR' end,
         made_at = now(), made_by = me.id, claimed_at = null, claimed_by = null
   where quotation_id = q.id and cycle = p_cycle and kind = p_kind and number is null;
  if found then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.billing', q.brand, q.ref || ' · ' ||
            case when p_kind = 'budget' then 'Advertising budget invoice ' else 'Invoice ' end ||
            v_num || ' created in Bukku as a draft · Month ' || p_cycle);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_invoice_done(uuid, integer, text, bigint, text, numeric) from public, anon;
grant execute on function public.quotation_invoice_done(uuid, integer, text, bigint, text, numeric) to authenticated;

/* The Bukku contact a client's advertising budget is invoiced to; none
   (null) puts it back on the client's own contact. */
create or replace function public.client_ad_debtor_set(p_client uuid, p_contact bigint, p_code text, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.clients;
  d public.client_ad_debtors;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.clients x where x.id = p_client;
  if c.id is null or not public.client_scope_ok('client', c.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if p_contact is not null and p_contact <= 0 then return jsonb_build_object('error', 'bad-request'); end if;
  select * into d from public.client_ad_debtors x where x.client_id = c.id;
  if p_contact is null then
    delete from public.client_ad_debtors x where x.client_id = c.id;
  else
    insert into public.client_ad_debtors (client_id, contact_id, code, name, set_by, set_at)
    values (c.id, p_contact, nullif(left(btrim(coalesce(p_code, '')), 40), ''), nullif(left(btrim(coalesce(p_name, '')), 200), ''), me.id, now())
    on conflict (client_id) do update set contact_id = excluded.contact_id, code = excluded.code, name = excluded.name,
      set_by = excluded.set_by, set_at = now();
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', c.name, 'Advertising budget billed to: ' || coalesce(d.name, d.code, 'the client') || ' → ' ||
          coalesce(nullif(btrim(p_name), ''), nullif(btrim(p_code), ''), 'the client'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_ad_debtor_set(uuid, bigint, text, text) from public, anon;
grant execute on function public.client_ad_debtor_set(uuid, bigint, text, text) to authenticated;

/* The advertising budget's account, by its code in Bukku's chart. */
create or replace function public.bukku_invoice_set(p_budget_code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  b public.bukku_settings;
  v_code text := nullif(btrim(coalesce(p_budget_code, '')), '');
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_code is not null and v_code !~ '^[A-Za-z0-9._/-]{1,30}$' then return jsonb_build_object('error', 'bad-account'); end if;
  select * into b from public.bukku_settings where id = 1 for update;
  if b.budget_account_code is not distinct from v_code then return jsonb_build_object('ok', true); end if;
  insert into public.bukku_settings (id, budget_account_code, set_by, set_at) values (1, v_code, me.id, now())
  on conflict (id) do update set budget_account_code = excluded.budget_account_code, set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Bukku', 'Advertising budget account: ' || coalesce(b.budget_account_code, 'not set') || ' → ' || coalesce(v_code, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_invoice_set(text) from public, anon;
grant execute on function public.bukku_invoice_set(text) to authenticated;

create or replace function public.bukku_config()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b public.bukku_settings;
begin
  if (public.ops_me()).id is null or not (public.allowed('clients.billing', 'work') or public.allowed('suppliers', 'work')
      or public.ops_granted('team.settings', 'work')) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into b from public.bukku_settings where id = 1;
  return jsonb_build_object('ok', true, 'field_client', b.field_client, 'field_supplier', b.field_supplier,
    'field_creator', b.field_creator, 'bill_account', b.bill_account, 'bill_account_name', b.bill_account_name,
    'bill_item_sku', b.bill_item_sku, 'bill_class_code', b.bill_class_code, 'bill_account_code', b.bill_account_code,
    'budget_account_code', b.budget_account_code, 'set_at', b.set_at);
end $$;
revoke all on function public.bukku_config() from public, anon;
grant execute on function public.bukku_config() to authenticated;

-- END OF QUOTATION INVOICES -------------------------------------------------
select public.functions_tidy();
