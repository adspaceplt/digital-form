-- ===========================================================================
-- TAX CODES PER LINE — each service line and quotation line carries its own
-- tax code, Bukku's, so an outstation fee or a reimbursement can go without
-- SST beside lines that carry it (2026-10-22)
-- ===========================================================================
-- WHY (the user, 2026-10-22: "make the 8% SST inside settings ... and then
-- choose to apply each under per item basis", after Bukku's own Items
-- table): a letter and a quotation took one SST rate for every line, or
-- none for an exempt client. A fee billed at cost, or a line the client
-- owes no SST on, could not sit on the same letter as the rest.
--
-- WHAT IT CHANGES
--   * `tax_codes` (RLS on, no policy, no grant): the codes the team bills
--     with, read from Bukku (`bukku-sync` `taxes`) or added by hand: code,
--     name, rate, active. `tax_codes_list()` (the team) reads them;
--     `tax_codes_save(p_rows, p_replace)` (Business settings) writes them,
--     a read from Bukku standing down a code Bukku no longer holds; filed
--     `team.changed` under Tax codes. A code is never deleted: a letter
--     issued on it keeps its name and rate in its snapshot.
--   * `client_services.tax_code`: none is the client's SST as before.
--   * `quote_totals`: a line may carry its own rate (`sst`); the SST is
--     worked a rate at a time, each rounded once, so a quotation on one
--     rate is priced exactly as before.
--   * `quote_adjust`: an edit may set a line's tax code (`tax`), its rate
--     read from `tax_codes` by `quote_tax_edits` (never the page's);
--     `quote_preview` and `quotation_make` ask it. `quotation_offer`
--     carries each line's code onto the client's service line.
--   * `issue_letter`: each line priced at its code's rate, else the
--     client's (refused `bad-tax` for a code not offered), the code and
--     rate kept on the snapshot; a letter on one rate is priced as before.
--   * `verify_letter`: a line whose tax code moved since the letter is
--     `changed-terms`, as a moved rate is.
--
-- ORDER: this file, then the pages. An old page sends no tax code and
-- every figure it works stays the database's. Safe to run twice. Rollback:
-- QUOTE TOTALS IN ONE PLACE's quote_totals, quote_adjust and issue_letter,
-- QUOTATION TAX DAY's quotation_offer and quote_preview, the last
-- quotation_make before this and SERVICE CONFIRM GUARD's verify_letter; the
-- table and the column may stay.
-- ===========================================================================

create table if not exists public.tax_codes (
  code       text primary key check (code ~ '^[A-Za-z0-9._ -]{1,30}$'),
  name       text not null default '' check (length(name) <= 80),
  rate       numeric(5,2) not null check (rate >= 0 and rate <= 100),
  active     boolean not null default true,
  bukku_id   text,
  updated_at timestamptz not null default now()
);
alter table public.tax_codes enable row level security;
revoke all on public.tax_codes from public, anon, authenticated;

alter table public.client_services add column if not exists tax_code text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'client_services_tax_code_check') then
    alter table public.client_services add constraint client_services_tax_code_check
      check (tax_code is null or tax_code ~ '^[A-Za-z0-9._ -]{1,30}$');
  end if;
end $$;

create or replace function public.tax_codes_list()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_team() then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'codes', coalesce((
      select jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name, 'rate', t.rate, 'active', t.active,
                                          'bukku', t.bukku_id is not null)
                       order by t.active desc, t.rate desc, t.code)
        from public.tax_codes t), '[]'::jsonb)) end
$$;
revoke all on function public.tax_codes_list() from public, anon;
grant execute on function public.tax_codes_list() to authenticated;

create or replace function public.tax_codes_save(p_rows jsonb, p_replace boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members := public.ops_me();
  v_r jsonb; v_code text; v_name text; v_rate numeric; v_on boolean;
  v_was public.tax_codes;
  v_codes text[] := '{}';
  v_add int := 0; v_moved text[] := '{}'; v_off int := 0; v_i int := 0;
begin
  if v_me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) > 100 then
    return jsonb_build_object('error', 'bad-row');
  end if;
  -- Every row checked before any is written.
  for v_r in select * from jsonb_array_elements(p_rows) loop
    v_i := v_i + 1;
    v_code := btrim(coalesce(v_r->>'code', ''));
    if v_code !~ '^[A-Za-z0-9._ -]{1,30}$' or length(btrim(coalesce(v_r->>'name', ''))) > 80
       or coalesce(v_r->>'rate', '') !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' or (v_r->>'rate')::numeric > 100
       or v_code = any(v_codes) then
      return jsonb_build_object('error', 'bad-row', 'row', v_i, 'code', v_code);
    end if;
    v_codes := v_codes || v_code;
  end loop;
  for v_r in select * from jsonb_array_elements(p_rows) loop
    v_code := btrim(v_r->>'code');
    v_name := btrim(coalesce(v_r->>'name', ''));
    v_rate := (v_r->>'rate')::numeric;
    v_on := coalesce((v_r->>'active')::boolean, true);
    select * into v_was from public.tax_codes t where t.code = v_code;
    if v_was.code is null then
      insert into public.tax_codes (code, name, rate, active, bukku_id)
      values (v_code, v_name, v_rate, v_on, nullif(btrim(coalesce(v_r->>'bukku_id', '')), ''));
      v_add := v_add + 1;
    elsif v_was.name is distinct from v_name or v_was.rate <> v_rate or v_was.active <> v_on then
      update public.tax_codes t
         set name = v_name, rate = v_rate, active = v_on,
             bukku_id = coalesce(nullif(btrim(coalesce(v_r->>'bukku_id', '')), ''), t.bukku_id), updated_at = now()
       where t.code = v_code;
      v_moved := v_moved || (v_code || case when v_was.rate <> v_rate then ': ' || trim(to_char(v_was.rate, 'FM990.99'), '.') ||
        '% → ' || trim(to_char(v_rate, 'FM990.99'), '.') || '%' else '' end ||
        case when v_was.active <> v_on then case when v_on then ': on' else ': off' end else '' end);
    end if;
  end loop;
  -- A read from Bukku: a code Bukku no longer holds is stood down, never removed.
  if coalesce(p_replace, false) then
    with d as (
      update public.tax_codes t set active = false, updated_at = now()
       where t.active and not (t.code = any(v_codes)) returning 1)
    select count(*) into v_off from d;
  end if;
  if v_add + coalesce(array_length(v_moved, 1), 0) + v_off > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (v_me.name, 'team.changed', 'Tax codes',
            concat_ws(' · ', case when p_replace then 'Read from Bukku' end,
              case when v_add > 0 then v_add || ' added' end,
              case when array_length(v_moved, 1) > 0 then array_to_string(v_moved, ', ') end,
              case when v_off > 0 then v_off || ' no longer offered' end));
  end if;
  return public.tax_codes_list();
end $$;
revoke all on function public.tax_codes_save(jsonb, boolean) from public, anon;
grant execute on function public.tax_codes_save(jsonb, boolean) to authenticated;

create or replace function public.quote_totals(p_lines jsonb, p_term int, p_pct numeric, p_sst numeric)
returns jsonb
language sql immutable set search_path = public as $$
  with l as (
    select e->>'basis' = 'month' as m,
           coalesce((e->>'qty')::numeric, 0) * coalesce((e->>'rate')::numeric, 0) as v,
           greatest(1, coalesce((e->>'months')::int, p_term, 1)) as mo,
           coalesce((e->>'sst')::numeric, p_sst) as r
      from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
  ), g as (
    -- A rate's own subtotals: one rate is the whole, as before tax codes.
    select r,
           coalesce(sum(v) filter (where m), 0) as gsub,
           coalesce(sum(round(v, 2) * mo) filter (where m), 0) as gspan,
           coalesce(sum(v) filter (where not m), 0) as gonce
      from l group by r
  ), gt as (
    select coalesce(sum(round((gsub + round(gsub * p_pct / 100, 2)) * r / 100, 2)), 0) as sst,
           coalesce(sum(round(gonce * r / 100, 2)), 0) as osst,
           coalesce(sum(round(gspan * (1 + p_pct / 100) * (1 + r / 100), 2)), 0) as span_incl
      from g
  ), s as (
    select coalesce(sum(v) filter (where m), 0) as sub,
           coalesce(sum(round(v, 2) * mo) filter (where m), 0) as span,
           coalesce(bool_and(mo = p_term) filter (where m), true) as even,
           coalesce(bool_or(m), false) as month,
           coalesce(sum(v) filter (where not m), 0) as once
      from l
  ), u as (
    select s.*, gt.sst, gt.osst, gt.span_incl, round(sub * p_pct / 100, 2) as off,
           round(span * (1 + p_pct / 100), 2) as span_excl
      from s, gt
  )
  select jsonb_build_object(
    'month', case when month then jsonb_build_object('subtotal', sub, 'term', off, 'excl', sub + off, 'sst', sst, 'incl', sub + off + sst) end,
    'once', case when once > 0 then jsonb_build_object('subtotal', once, 'sst', osst, 'incl', once + osst) end,
    'even', even, 'span_excl', case when month then span_excl else 0 end, 'span_incl', case when month then span_incl else 0 end,
    'commitment', case when not month then 0 when even then (sub + off + sst) * p_term else span_incl end + once + osst)
  from u
$$;
revoke all on function public.quote_totals(jsonb, integer, numeric, numeric) from public, anon, authenticated;

/* Each edit's tax code given its rate from tax_codes, a rate the page sent
   dropped first: the price is the database's. An unknown code gets none,
   and quote_adjust refuses it. */
create or replace function public.quote_tax_edits(p_edits jsonb)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_out jsonb := '{}'::jsonb; v_k text; v_e jsonb; v_r numeric;
begin
  if jsonb_typeof(p_edits) is distinct from 'object' then return p_edits; end if;
  for v_k, v_e in select key, value from jsonb_each(p_edits) loop
    if jsonb_typeof(v_e) = 'object' then
      v_e := v_e - 'tax_pct';
      if coalesce(v_e->>'tax', '') <> '' then
        v_r := null;
        select t.rate into v_r from public.tax_codes t where t.code = v_e->>'tax' and t.active;
        if v_r is not null then v_e := v_e || jsonb_build_object('tax_pct', v_r); end if;
      end if;
    end if;
    v_out := v_out || jsonb_build_object(v_k, v_e);
  end loop;
  return v_out;
end $$;
revoke all on function public.quote_tax_edits(jsonb) from public, anon, authenticated;

create or replace function public.quote_adjust(p_price jsonb, p_edits jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_t jsonb := coalesce(p_price->'totals', '{}'::jsonb);
  v_term int := coalesce((v_t->>'term')::int, 1);
  v_lines jsonb := '[]'::jsonb;
  v_l jsonb; v_e jsonb; v_k text; v_n int := 0; v_hit boolean;
  v_qty numeric; v_rate numeric; v_mo int;
  v_pct numeric := coalesce((v_t->>'term_pct')::numeric, 0);
  v_sst_pct numeric := coalesce((v_t->>'sst_pct')::numeric, 0);
  v_tot jsonb;
begin
  if p_price ? 'error' or jsonb_typeof(p_price->'lines') is distinct from 'array' then return p_price; end if;
  if p_edits is not null and jsonb_typeof(p_edits) not in ('object', 'null') then
    return jsonb_build_object('error', 'bad-edit');
  end if;
  for v_l in select * from jsonb_array_elements(p_price->'lines') loop
    v_k := (v_l->>'kind') || '|' || coalesce(v_l->>'slug', '') || '|' || (v_l->>'label');
    v_qty := (v_l->>'qty')::numeric; v_rate := (v_l->>'rate')::numeric;
    v_mo := case when v_l->>'basis' = 'month' then v_term else 1 end;
    v_hit := false;
    if jsonb_typeof(p_edits) = 'object' and jsonb_typeof(p_edits->v_k) = 'object' then
      v_e := p_edits->v_k;
      if (v_e ? 'qty' and coalesce(v_e->>'qty', '') !~ '^[0-9]{1,4}$')
         or (v_e ? 'rate' and coalesce(v_e->>'rate', '') !~ '^[0-9]{1,7}(\.[0-9]{1,2})?$')
         or (v_e ? 'months' and (v_l->>'basis' <> 'month' or coalesce(v_e->>'months', '') !~ '^[0-9]{1,2}$'))
         or (v_e ? 'tax' and coalesce(v_e->>'tax', '') !~ '^([A-Za-z0-9._ -]{1,30})?$') then
        return jsonb_build_object('error', 'bad-edit', 'line', v_l->>'label');
      end if;
      if (v_e ? 'qty' and (v_e->>'qty')::int < 1) or (v_e ? 'months' and (v_e->>'months')::int not between 1 and 36) then
        return jsonb_build_object('error', 'bad-edit', 'line', v_l->>'label');
      end if;
      if v_e ? 'qty' and (v_e->>'qty')::numeric <> v_qty then v_qty := (v_e->>'qty')::numeric; v_hit := true; end if;
      if v_e ? 'rate' and (v_e->>'rate')::numeric <> v_rate then
        v_l := v_l || jsonb_build_object('list_rate', v_rate);
        v_rate := (v_e->>'rate')::numeric; v_hit := true;
      end if;
      if v_e ? 'months' and (v_e->>'months')::int <> v_mo then v_mo := (v_e->>'months')::int; v_hit := true; end if;
      /* A line's own tax code (2026-10-22), its rate read from tax_codes by
         quote_tax_edits; an empty one keeps the quotation's SST. */
      if coalesce(v_e->>'tax', '') <> '' then
        if jsonb_typeof(v_e->'tax_pct') is distinct from 'number' then
          return jsonb_build_object('error', 'bad-tax', 'line', v_l->>'label');
        end if;
        v_l := v_l || jsonb_build_object('tax_code', v_e->>'tax', 'sst', (v_e->>'tax_pct')::numeric);
        v_hit := true;
      end if;
    end if;
    if v_hit then v_n := v_n + 1; end if;
    v_l := v_l || jsonb_build_object('key', v_k, 'qty', v_qty, 'rate', v_rate, 'months', v_mo,
                                     'amount', round(v_qty * v_rate, 2));
    v_lines := v_lines || jsonb_build_array(v_l);
  end loop;
  if v_n = 0 then
    return p_price || jsonb_build_object('lines', v_lines, 'adjusted', 0);
  end if;
  -- The figures, from the one calculation every quotation and letter shares.
  v_tot := public.quote_totals(v_lines, v_term, v_pct, v_sst_pct);
  return p_price || jsonb_build_object('lines', v_lines, 'adjusted', v_n,
    'totals', v_t || jsonb_build_object('month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment'));
end $$;
revoke all on function public.quote_adjust(jsonb, jsonb) from public, anon, authenticated;

create or replace function public.quote_preview(p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_card jsonb := public.quote_card();
  v_cl uuid;
  v_fx numeric;
begin
  if not public.is_team() or not public.allowed('clients.services', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  if coalesce(p_sel->>'client', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and public.client_scope_ok('client', (p_sel->>'client')::uuid, 'view') then
    v_cl := (p_sel->>'client')::uuid;
  end if;
  v_fx := public.quote_fx(v_cl);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  return public.quote_fx_out(public.quote_adjust(public.quote_price(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_cl), v_fx),
           p_sel - 'client'), public.quote_tax_edits(p_sel->'edits')), v_fx) || jsonb_build_object('version', v_card->>'version');
end $$;
revoke all on function public.quote_preview(jsonb) from public, anon;
grant execute on function public.quote_preview(jsonb) to authenticated;

create or replace function public.quotation_make(p_client uuid, p_sel jsonb, p_idem text, p_source text,
                                                 p_by text, p_contact jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_c public.clients;
  v_card jsonb := public.quote_card();
  v_p jsonb;
  v_q public.quotations;
  v_now timestamptz := now();
  v_days int;
  v_fx numeric;
  v_sel jsonb := case when jsonb_typeof(p_sel) is distinct from 'object' then p_sel
                      when p_source = 'console' then p_sel - 'client'
                      else p_sel - 'edits' - 'client' end;
begin
  if p_idem is not null then
    select * into v_q from public.quotations q where q.idem = p_idem;
    if v_q.id is not null then return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true); end if;
  end if;
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_p := public.quote_fx_out(public.quote_adjust(public.quote_price(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id), v_fx),
           v_sel), public.quote_tax_edits(v_sel->'edits')), v_fx);
  if v_p ? 'error' then return v_p; end if;
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  begin
  insert into public.quotations (ref, client_id, brand, version, version_id, selection, lines, totals, source,
                                 issued_at, valid_until, made_by, contact, idem, access_key)
  values (public.quote_ref(v_c.name, v_now), v_c.id, v_c.name, v_card->>'version', (v_card->>'id')::uuid, v_sel,
          v_p->'lines', v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request'), p_source,
          v_now, (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days, p_by, p_contact, p_idem,
          case when p_source = 'website' then public.new_link_key() end)
  returning * into v_q;
  -- Two presses at once with one key: the second answers the first's.
  exception when unique_violation then
    select * into v_q from public.quotations q where q.idem = p_idem;
    if p_idem is null or v_q.id is null then raise; end if;
    return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true);
  end;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(p_by, 'Website'), 'client.quotation', v_c.name,
          v_q.ref || ' sent · ' || coalesce('Monthly incl. SST ' || case when v_fx is null then 'RM ' else 'S$ ' end ||
            to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'key', v_q.access_key);
end $$;
revoke all on function public.quotation_make(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

create or replace function public.quotation_offer(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_l jsonb;
  v_ids uuid[] := '{}';
  v_id uuid;
begin
  if me.id is null or not public.allowed('clients.services', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or v_q.removed_at is not null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  select coalesce(array_agg(s.id order by s.created_at), '{}') into v_ids
    from public.client_services s where s.quotation_id = v_q.id and s.archived_at is null;
  if array_length(v_ids, 1) is not null then return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids), 'again', true); end if;
  if v_q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  for v_l in select * from jsonb_array_elements(v_q.lines) loop
    insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                        tenure, term_adjust, term_pct, detail, quotation_id, tax_code)
    values (v_q.client_id,
            case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
            v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
            case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'quoted',
            'Quotation ' || v_q.ref,
            case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (v_q.totals->>'term')::int) else 1 end,
            v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (v_q.totals->>'term_pct')::numeric else 0 end,
            nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
            v_q.id, nullif(v_l->>'tax_code', ''))
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || ' · ' || array_length(v_ids, 1) || ' lines To quote for the Letter of Offer');
  return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids));
end $$;
revoke all on function public.quotation_offer(uuid) from public, anon;
grant execute on function public.quotation_offer(uuid) to authenticated;

create or replace function public.issue_letter(
  p_client    uuid,
  p_services  uuid[],
  p_idem      text,
  p_subtotal  numeric,
  p_tax       numeric,
  p_total     numeric,
  p_deal      jsonb   default '{}'::jsonb,
  p_replaces  uuid    default null,
  p_renewal   boolean default false,
  /* A reference somebody typed. Blank is the ordinary case and the counter
     below makes the number; where one is typed it is checked against every
     document that stands and the counter is not advanced, so filling a gap
     by hand never costs the next letter its place in the sequence. */
  p_serial    text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  ct     public.client_contacts%rowtype;
  me     public.team_members%rowtype;
  v_ym   text;
  v_seq  int;
  v_try  int;
  v_no   text;
  v_id   uuid;
  v_lines jsonb;
  v_n    int;
  v_bad  int;
  v_old  public.client_documents%rowtype;
  v_term int;
  v_each numeric;
  v_etax numeric;
  v_once numeric;
  v_otax numeric;
  v_sub  numeric;
  v_tax  numeric;
  v_tot  numeric;
  v_pct  numeric;
  v_qid  uuid;
  v_q    public.quotations%rowtype;
  v_tp   numeric;
  v_tpn  int;
  v_tadj boolean;
  v_qterm int;
  v_msub numeric;
  v_span numeric;
  v_even boolean;
  v_qt   jsonb;
  v_month boolean;
begin
  if not public.allowed('clients.documents') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if p_client is null or p_services is null or array_length(p_services, 1) is null then
    return jsonb_build_object('error', 'no-lines');
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;

  -- The Client ID is what the serial is built from, so there is no letter
  -- without one. Staff enter it on the record; nothing invents it. A typed
  -- reference needs no code, because nothing is being built.
  v_no := nullif(btrim(coalesce(p_serial, '')), '');
  if v_no is null and coalesce(btrim(cl.client_code), '') = '' then
    return jsonb_build_object('error', 'no-client-code');
  end if;

  -- The same submission, pressed twice, is one letter. Answered before any
  -- number is reserved, so a double click cannot spend a serial either.
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.client_documents
      where client_id = p_client and idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
    end if;
  end if;

  -- A typed reference is checked before anything is written: the same shape
  -- the Register accepts, and refused where a document still holds it.
  if v_no is not null then
    if v_no !~ '^[A-Za-z0-9/._-]{3,40}$' then
      return jsonb_build_object('error', 'serial-shape');
    end if;
    if public.serial_taken(v_no) then
      return jsonb_build_object('error', 'serial-taken');
    end if;
  end if;

  -- Every id must be this client's own live line, and in a state this letter
  -- may carry: To quote always, Confirmed only on a deliberate renewal.
  select count(*) into v_bad from unnest(p_services) s(id)
    left join public.client_services cs
      on cs.id = s.id and cs.client_id = p_client and cs.archived_at is null
    where cs.id is null
       or (cs.state = 'confirmed' and not p_renewal)
       or cs.state not in ('quoted', 'confirmed');
  if v_bad > 0 then return jsonb_build_object('error', 'bad-lines'); end if;

  -- A line already on a live letter is not offered again by accident. The way
  -- through is to void that letter, or to name it as the one being replaced.
  select count(*) into v_bad
    from public.client_document_services m
    join public.client_documents d on d.id = m.document_id
   where m.service_id = any(p_services)
     and d.voided_at is null
     and d.superseded_by is null
     and d.verified_at is null
     and (p_replaces is null or d.id <> p_replaces);
  if v_bad > 0 then return jsonb_build_object('error', 'already-quoted'); end if;

  if p_replaces is not null then
    select * into v_old from public.client_documents
      where id = p_replaces and client_id = p_client;
    if v_old.id is null then return jsonb_build_object('error', 'no-replaces'); end if;
    if v_old.verified_at is not null then return jsonb_build_object('error', 'replaces-verified'); end if;
  end if;

  select * into ct from public.client_contacts
    where client_id = p_client and archived_at is null
    order by (id = cl.bill_contact_id) desc, is_primary desc, name limit 1;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  -- A letter is signed by a person. issued_by is this row's name, so a team
  -- row named "Superadmin" printed that word under ADSPACE PLT on a client's
  -- letterhead. Refuse rather than draw a permission as a signatory.
  if not public.issuer_name_ok(me.name) then
    return jsonb_build_object('error', 'issuer-name', 'name', coalesce(me.name, ''));
  end if;

  -- The snapshot is built from the stored rows, never from what the browser
  -- sent: the words on a letter are the words the record held at that moment.
  select jsonb_agg(jsonb_build_object(
           'label', cs.label, 'unit', coalesce(cs.unit, ''), 'note', coalesce(cs.note, ''),
           'detail', coalesce(cs.detail, ''), 'state', cs.state,
           'qty', cs.qty, 'rate', cs.rate,
           'tenure', greatest(1, coalesce(cs.tenure, 1)),
           'start_on', coalesce(cs.start_on, ''),
           -- The line's own answer to whether its term prices it. Written into
           -- the snapshot because the letter is redrawn from it, and a letter
           -- must print the same figure every time it is drawn. A snapshot
           -- taken before this key existed carries none, which money.js reads
           -- as on, so those letters redraw as they were issued.
           'term_adjust', coalesce(cs.term_adjust, false),
           -- And the percentage that tick applies, so a later rate card can
           -- never move a figure this letter printed. Null on a line quoted
           -- before the column existed, which money.js reads as that card.
           'term_pct', cs.term_pct,
           'tax', cl.sst_applies is not false,
           -- The line's own tax code and its rate as issued (2026-10-22);
           -- none is the client's SST, as before.
           'tax_code', cs.tax_code,
           'tax_pct', (select t.rate from public.tax_codes t where t.code = cs.tax_code),
           'service_id', cs.id)
           order by cs.created_at)
    into v_lines
    from public.client_services cs
   where cs.id = any(p_services);
  if v_lines is null then return jsonb_build_object('error', 'no-lines'); end if;
  /* A line's tax code is one the team holds and offers (2026-10-22). */
  if exists (select 1 from public.client_services cs
              where cs.id = any(p_services) and cs.tax_code is not null
                and not exists (select 1 from public.tax_codes t where t.code = cs.tax_code and t.active)) then
    return jsonb_build_object('error', 'bad-tax');
  end if;

  /* The price is the database's (audit S4, 2026-10-10), worked as the
     letter draws it (js/documents.js priceOf, js/money.js rateFor): each
     line's rate with its term on it, rounded to the cent. Where every line
     of more than a month shares one term, those lines are priced by the
     month and times the term, and a line of one month is a one-off item
     with its own SST (2026-10-15: a one-off item beside them no longer
     turns the letter into one whole total); otherwise every line is its
     whole amount. SST at the rate in force today unless the client is
     exempt. The page's figures are kept only where they agree to the sen,
     so a line changed since the sheet opened, or a figure typed in a
     browser, is refused (`stale`) and the sheet reads the lines again. */
  select case when count(distinct greatest(1, coalesce(cs.tenure, 1)))
                     filter (where greatest(1, coalesce(cs.tenure, 1)) > 1) = 1
              then max(greatest(1, coalesce(cs.tenure, 1))) else 0 end
    into v_term
    from public.client_services cs where cs.id = any(p_services);
  /* A letter whose every line came from one quotation is priced as that
     quotation was (audit F, 2026-10-17), exactly as `quote_price` and
     `quote_adjust` total it (2026-10-17, the review's finding 7): a line
     the quotation bills by the month (`quotation_offer` ticks its term) is
     a monthly line whatever months Build quote gave it, its percentage
     taken once on their subtotal; a line with no term is one-off; SST at
     the quotation's rate. The page's figures are held to the same price
     (js/documents.js priceOf). */
  select case when count(*) filter (where cs.quotation_id is null) = 0
                   and count(distinct cs.quotation_id) = 1 then min(cs.quotation_id::text)::uuid end,
         count(distinct coalesce(cs.term_pct, 0)) filter (where coalesce(cs.term_adjust, false)),
         coalesce(bool_and(greatest(1, coalesce(cs.tenure, 1)) = 1) filter (where not coalesce(cs.term_adjust, false)), true),
         coalesce(max(cs.term_pct) filter (where coalesce(cs.term_adjust, false)), 0)
    into v_qid, v_tpn, v_tadj, v_tp
    from public.client_services cs where cs.id = any(p_services);
  /* Only while the quotation still stands (2026-10-17, the review's
     finding 2): unexpired by Malaysia's day and not removed. A renewal, or a
     letter replacing one after the quotation lapsed, is priced on today's
     rates, as any other letter. */
  if v_qid is not null and coalesce(v_tpn, 0) <= 1 and v_tadj and not coalesce(p_renewal, false) then
    select * into v_q from public.quotations q
     where q.id = v_qid and q.removed_at is null
       and q.valid_until >= (timezone('Asia/Kuala_Lumpur', now()))::date;
  end if;
  if v_q.id is not null then
    /* As quote_adjust totals it: the monthly lines' subtotal of quantity ×
       rate, the percentage once on it; where every one runs the quotation's
       term, a month's excl. SST, its SST rounded once, times the term; where
       Build quote gave a line months of its own, the whole span (each line's
       amount × its months) with the percentage and SST taken once on it.
       One-off lines and their SST apart. */
    v_qterm := greatest(1, coalesce((v_q.totals->>'term')::int, 1));
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce((v_q.totals->>'sst_pct')::numeric, 0) end;
    /* The lines as the quotation reads them (a line with its term ticked is
       monthly, on its own months), totalled by the one calculation every
       quotation shares (2026-10-18). */
    v_qt := public.quote_totals(
      (select coalesce(jsonb_agg(jsonb_build_object(
                'basis', case when coalesce(cs.term_adjust, false) then 'month' else 'once' end,
                'qty', coalesce(cs.qty, 0), 'rate', coalesce(cs.rate, 0),
                'months', greatest(1, coalesce(cs.tenure, 1)),
                'sst', (select t.rate from public.tax_codes t where t.code = cs.tax_code))), '[]'::jsonb)
         from public.client_services cs where cs.id = any(p_services)),
      v_qterm, v_tp, v_pct);
    v_month := jsonb_typeof(v_qt->'month') = 'object';
    v_once := coalesce((v_qt->'once'->>'subtotal')::numeric, 0);
    v_otax := coalesce((v_qt->'once'->>'sst')::numeric, 0);
    if not v_month then
      v_sub := round(v_once, 2);
      v_tax := v_otax;
    elsif (v_qt->>'even')::boolean then
      v_each := (v_qt->'month'->>'excl')::numeric;
      v_etax := (v_qt->'month'->>'sst')::numeric;
      v_sub := round(v_each * v_qterm + v_once, 2);
      v_tax := v_etax * v_qterm + v_otax;
    else
      v_sub := (v_qt->>'span_excl')::numeric + round(v_once, 2);
      v_tax := (v_qt->>'span_incl')::numeric + round(v_once, 2) + v_otax - v_sub;
    end if;
    v_tot := v_sub + v_tax;
    /* The letter keeps what it was priced on, so a redraw prints the same:
       the quotation, its SST and its term (a snapshot with no `quote_term`
       was priced before this, and redraws as it was). */
    select jsonb_agg(l.e || jsonb_build_object('quotation_id', v_qid, 'quote_sst', v_pct, 'quote_term', v_qterm) order by l.n)
      into v_lines from jsonb_array_elements(v_lines) with ordinality l(e, n);
  else
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce(public.app_setting('sst_pct', (timezone('Asia/Kuala_Lumpur', now()))::date), 0) end;
    /* Each line at its own SST rate (2026-10-22): its tax code's, else the
       client's. The SST is worked a rate at a time, rounded once each, so
       a letter on one rate prices as it always did. */
    with x as (
      select greatest(1, coalesce(cs.tenure, 1)) as n,
             coalesce(cs.qty, 0) *
             round(coalesce(cs.rate, 0) *
               case when cs.term_adjust is false then 1
                    when cs.term_pct is not null then 1 + cs.term_pct / 100
                    else case greatest(1, coalesce(cs.tenure, 1))
                           when 3 then 1 / 0.9 when 12 then 0.95 when 24 then 0.9 else 1 end
               end, 2) as v,
             coalesce((select t.rate from public.tax_codes t where t.code = cs.tax_code), v_pct) as r
        from public.client_services cs where cs.id = any(p_services)
    ), y as (
      select r,
             coalesce(sum(v) filter (where v_term > 0 and n = v_term), 0) as e,
             coalesce(sum(v * n) filter (where v_term = 0 or n <> v_term), 0) as o
        from x group by r
    )
    select coalesce(sum(e), 0), coalesce(sum(o), 0),
           coalesce(sum(round(e * r) / 100), 0), coalesce(sum(round(o * r) / 100), 0)
      into v_each, v_once, v_etax, v_otax
      from y;
    v_sub := round(v_each * greatest(v_term, 1), 2) + round(v_once, 2);
    v_tax := round(v_etax * greatest(v_term, 1), 2) + v_otax;
    v_tot := round(round(v_each + v_etax, 2) * greatest(v_term, 1), 2) + round(v_once + v_otax, 2);
  end if;
  if abs(coalesce(p_subtotal, -1) - v_sub) > 0.01 or abs(coalesce(p_tax, -1) - v_tax) > 0.01
     or abs(coalesce(p_total, -1) - v_tot) > 0.01 then
    return jsonb_build_object('error', 'stale', 'subtotal', v_sub, 'tax', v_tax, 'total', v_tot);
  end if;

  -- A typed reference spends no sequence number: the counter is the office's
  -- record of how many letters it has issued this month, and a person filling
  -- a gap by hand has not issued one more.
  if v_no is null then
    -- The month is Malaysian, because the office that numbers the letter is.
    v_ym := to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM');

    -- The counter still advances on every automatic issue, and the upsert's
    -- row lock is what makes the scan below safe: a second issuer blocks here
    -- until the first has committed its letter, so the two never read the same
    -- gap as free. What the counter gives is a bound to scan within, not the
    -- number itself.
    insert into public.client_document_seq (client_id, ym, next_val)
         values (p_client, v_ym, 2)
    on conflict (client_id, ym)
      do update set next_val = public.client_document_seq.next_val + 1
      returning next_val - 1 into v_seq;

    -- The lowest free slot, not the counter's own value. A deleted letter
    -- releases its reference (serial_taken stopped counting deletions on
    -- 2026-09-20), and without this the automatic path still counted upward
    -- past the gap: a client whose first two letters were issued in testing
    -- and deleted started at 03 for ever. The counter is at least the number
    -- of letters issued this month, so a free slot exists at or below it
    -- unless somebody has typed references over the same range by hand; the
    -- cap covers that and refuses rather than looping.
    --
    -- Two digits is the floor, not the ceiling: the hundredth letter of a month
    -- widens to three rather than wrapping. Not lpad(): Postgres pads AND
    -- truncates to the width it is given, so lpad('100', 2, '0') is '10' and the
    -- hundredth letter would collide with the tenth.
    v_try := 1;
    loop
      v_no := 'AQL/' || cl.client_code || '/' || v_ym ||
              case when v_try < 100 then lpad(v_try::text, 2, '0') else v_try::text end;
      exit when not public.serial_taken(v_no);
      v_try := v_try + 1;
      if v_try > greatest(v_seq, 1) + 200 then
        return jsonb_build_object('error', 'no-serial');
      end if;
    end loop;
  end if;

  insert into public.client_documents
    (client_id, kind, number, issued_at, market, subtotal, tax, total,
     bill_to, lines, issued_by, client_code, idem_key)
  values
    (p_client, 'offer', v_no, (timezone('Asia/Kuala_Lumpur', now()))::date,
     coalesce(cl.market, 'MY'),
     round(coalesce(p_subtotal, 0), 2), round(coalesce(p_tax, 0), 2), round(coalesce(p_total, 0), 2),
     jsonb_build_object(
       'name', coalesce(cl.name, ''), 'legal_name', coalesce(cl.legal_name, ''),
       'address', coalesce(cl.billing_address, ''), 'regno', coalesce(cl.company_no, ''),
       'regno_old', coalesce(cl.company_no_old, ''), 'tin', coalesce(cl.tin, ''),
       'sst_no', coalesce(cl.sst_no, ''), 'sst_applies', cl.sst_applies is not false,
       'contact', coalesce(ct.name, ''), 'contact_role', coalesce(ct.role, ''),
       'contact_salutation', coalesce(ct.salutation, ''),
       'phone', coalesce(ct.phone, ''), 'email', coalesce(ct.email, ''),
       'finance_email', coalesce(cl.finance_email, ''),
       'client_code', cl.client_code,
       'owner', coalesce(p_deal ->> 'owner', ''), 'source', coalesce(p_deal ->> 'source', ''),
       'industry', coalesce(p_deal ->> 'industry', ''), 'stage', coalesce(p_deal ->> 'stage', ''),
       'enquiry', coalesce(p_deal ->> 'enquiry', '')),
     v_lines, coalesce(me.name, who), cl.client_code, nullif(btrim(p_idem), ''))
  returning id into v_id;

  insert into public.client_document_services (document_id, service_id)
    select v_id, s.id from unnest(p_services) s(id)
    on conflict do nothing;

  if p_replaces is not null then
    update public.client_documents set superseded_by = v_id where id = p_replaces;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.superseded', cl.name, v_old.number || ' replaced by ' || v_no);
  end if;

  select count(*) into v_n from public.client_document_services where document_id = v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.issued', cl.name, v_no || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end);

  return jsonb_build_object('ok', true, 'id', v_id, 'number', v_no);
exception
  when unique_violation then
    -- Two presses that raced past the idempotency read: the loser reads the
    -- winner's letter back rather than making a second one.
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.client_documents
        where client_id = p_client and idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
      end if;
    end if;
    -- A typed reference two people sent at once: the loser is told the
    -- reference is spent rather than that "two letters were issued at once",
    -- which names a cause they cannot act on.
    if nullif(btrim(coalesce(p_serial, '')), '') is not null then
      return jsonb_build_object('error', 'serial-taken');
    end if;
    return jsonb_build_object('error', 'clash');
end $$;


grant execute on function public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean, text) to authenticated;

create or replace function public.verify_letter(p_doc uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.client_documents%rowtype;
  cl    public.clients%rowtype;
  me    public.team_members%rowtype;
  v_map int;
  v_n   int;
begin
  if not public.allowed('clients.documents') then return jsonb_build_object('error', 'not-allowed'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('error', 'voided'); end if;
  if d.superseded_by is not null then return jsonb_build_object('error', 'superseded'); end if;
  if d.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;

  -- Verifying twice is verifying once.
  if d.verified_at is not null then
    return jsonb_build_object('ok', true, 'repeat', true, 'confirmed', 0);
  end if;

  -- A letter issued before this change has no mappings, so there is nothing
  -- to confirm and no guess is made. It stays history.
  select count(*) into v_map from public.client_document_services where document_id = p_doc;
  if v_map = 0 or v_map <> coalesce(jsonb_array_length(d.lines), -1) then
    return jsonb_build_object('error', 'no-mapping');
  end if;

  /* What the client signed is the letter's snapshot. A line removed since,
     or one whose quantity, rate, term, adjustment or tax code moved since, is not
     what was signed, so nothing is confirmed (audit S4, 2026-10-10): the
     letter is reissued, or the line put back as it was. */
  if exists (select 1 from public.client_document_services m
               join public.client_services cs on cs.id = m.service_id
              where m.document_id = p_doc and cs.archived_at is not null) then
    return jsonb_build_object('error', 'archived-line');
  end if;
  if exists (select 1 from jsonb_array_elements(d.lines) l
               join public.client_services cs on cs.id = (l ->> 'service_id')::uuid
              where l ? 'service_id'
                and ((l ->> 'qty')::numeric is distinct from cs.qty
                  or (l ->> 'rate')::numeric is distinct from cs.rate
                  or (l ->> 'tenure')::int is distinct from greatest(1, coalesce(cs.tenure, 1))
                  or (l ? 'term_adjust' and (l ->> 'term_adjust')::boolean is distinct from coalesce(cs.term_adjust, false))
                  or (l ? 'term_pct' and (l ->> 'term_pct')::numeric is distinct from cs.term_pct)
                  or (l ? 'tax_code' and nullif(l ->> 'tax_code', '') is distinct from cs.tax_code))) then
    return jsonb_build_object('error', 'changed-terms');
  end if;

  update public.client_services cs
     set state = 'confirmed'
    from public.client_document_services m
   where m.document_id = p_doc and cs.id = m.service_id
     and cs.archived_at is null and cs.state <> 'confirmed';
  get diagnostics v_n = row_count;

  select * into me from public.team_members where lower(email) = who and active limit 1;
  update public.client_documents
     set verified_at = now(), verified_by = coalesce(me.name, who)
   where id = p_doc;

  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.verified', cl.name,
          d.number || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end || ' confirmed');
  return jsonb_build_object('ok', true, 'confirmed', v_n);
end $$;


grant execute on function public.verify_letter(uuid) to authenticated;

-- END OF TAX CODES PER LINE ------------------------------------------------
select public.functions_tidy();
