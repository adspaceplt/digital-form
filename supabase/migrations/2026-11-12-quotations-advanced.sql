-- =====================================================================
-- QUOTATIONS IN PLACE OF THE LETTER OF OFFER
-- 2026-11-12, the user: the quotation takes over what only the Letter of
-- Offer did, and the Letter of Offer is no longer issued (letters issued
-- before stay as they are). Build quote's Advanced part: custom lines
-- (`quote_custom`: words, quantity, rate, Monthly or One-off, months and
-- start; a start on a Rate Card line by `starts`), renewals (a line naming
-- one of the client's confirmed service lines, confirmed for its new term
-- on approval, never added twice), Bill to (one of the client's billing
-- entities, held in the totals as printed) and the quotation's own terms.
-- =====================================================================
/* A quotation of custom lines alone (a renewal with no plan, 2026-11-12):
   where nothing on the Rate Card is chosen, the term, its percentage and
   SST as quote_price would read them, and no line yet; quote_custom adds
   the lines and the totals. */
create or replace function public.quote_base(p_snap jsonb, p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v jsonb := public.quote_price(p_snap, p_sel);
  v_set jsonb := coalesce(p_snap->'settings', '{}'::jsonb);
  v_term int;
  v_month boolean;
  v_pct numeric;
begin
  if v->>'error' is distinct from 'empty' or jsonb_typeof(p_sel->'custom') is distinct from 'array'
     or jsonb_array_length(p_sel->'custom') = 0 then
    return v;
  end if;
  v_term := case when coalesce(p_sel->>'term', '') ~ '^\d{1,2}$' then (p_sel->>'term')::int else 6 end;
  select coalesce(bool_or(x->>'basis' = 'month'), false) into v_month from jsonb_array_elements(p_sel->'custom') x;
  if v_month and v_term = 1 then return jsonb_build_object('error', 'bad-term'); end if;
  v_pct := case when not v_month then 0
                when v_term <= 3 then coalesce((v_set->>'term_1_3')::numeric, 0)
                when v_term <= 5 then coalesce((v_set->>'term_4_5')::numeric, 0)
                when v_term <= 11 then coalesce((v_set->>'term_6_11')::numeric, 0)
                when v_term <= 17 then coalesce((v_set->>'term_12_23')::numeric, 0)
                when v_term <= 23 then coalesce((v_set->>'term_18_23')::numeric, (v_set->>'term_12_23')::numeric, 0)
                else coalesce((v_set->>'term_24')::numeric, 0) end;
  return jsonb_build_object('lines', '[]'::jsonb, 'on_request', '[]'::jsonb, 'extra_rates', '{}'::jsonb,
    'totals', jsonb_build_object('term', v_term, 'term_pct', v_pct, 'sst_pct', coalesce((v_set->>'sst_pct')::numeric, 0), 'budget', 0));
end $$;
revoke all on function public.quote_base(jsonb, jsonb) from public, anon, authenticated;

/* Custom lines (2026-11-12, the user: the quotation takes over what only the
   Letter of Offer did): a line typed in with its words, quantity, rate,
   Monthly or One-off, months and start, priced with the rest by
   quote_totals; a line renewing one of the client's confirmed service lines
   names it (`renews`). A Rate Card line may take a start too (`starts`). */
create or replace function public.quote_custom(p_price jsonb, p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_t jsonb := coalesce(p_price->'totals', '{}'::jsonb);
  v_term int := coalesce((v_t->>'term')::int, 1);
  v_lines jsonb := '[]'::jsonb;
  v_l jsonb;
  r jsonb;
  d jsonb;
  i int := 0;
  v_mo int;
  v_start text;
  v_tot jsonb;
  v_any boolean := false;
begin
  if p_price ? 'error' or jsonb_typeof(p_price->'lines') is distinct from 'array' then return p_price; end if;
  if jsonb_typeof(p_sel->'starts') is not null and jsonb_typeof(p_sel->'starts') not in ('object', 'null') then
    return jsonb_build_object('error', 'bad-custom');
  end if;
  for v_l in select * from jsonb_array_elements(p_price->'lines') loop
    v_start := case when jsonb_typeof(p_sel->'starts') = 'object' then p_sel->'starts'->>(v_l->>'key') end;
    if coalesce(v_start, '') <> '' then
      if v_start !~ '^\d{4}-\d{2}-\d{2}$' or public.doc_day_of(v_start) is null or public.doc_day_of(v_start) = date '0001-01-01' then
        return jsonb_build_object('error', 'bad-custom', 'line', v_l->>'label');
      end if;
      v_l := v_l || jsonb_build_object('start', v_start);
      v_any := true;
    end if;
    v_lines := v_lines || jsonb_build_array(v_l);
  end loop;
  if jsonb_typeof(p_sel->'custom') is not null and jsonb_typeof(p_sel->'custom') <> 'null' then
    if jsonb_typeof(p_sel->'custom') <> 'array' or jsonb_array_length(p_sel->'custom') > 30 then
      return jsonb_build_object('error', 'bad-custom');
    end if;
    for r in select * from jsonb_array_elements(p_sel->'custom') loop
      i := i + 1;
      if jsonb_typeof(r) <> 'object'
         or length(btrim(coalesce(r->>'label', ''))) not between 1 and 120
         or coalesce(r->>'qty', '') !~ '^\d{1,4}$' or (r->>'qty')::int < 1
         or coalesce(r->>'rate', '') !~ '^\d{1,7}(\.\d{1,2})?$'
         or coalesce(r->>'basis', '') not in ('month', 'once')
         or (jsonb_typeof(r->'detail') is not null and jsonb_typeof(r->'detail') not in ('array', 'null'))
         or (jsonb_typeof(r->'detail') = 'array' and jsonb_array_length(r->'detail') > 12)
         or (coalesce(r->>'renews', '') <> '' and r->>'renews' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
        return jsonb_build_object('error', 'bad-custom', 'line', coalesce(r->>'label', i::text));
      end if;
      if jsonb_typeof(r->'detail') = 'array' then
        for d in select * from jsonb_array_elements(r->'detail') loop
          if jsonb_typeof(d) <> 'string' or length(d #>> '{}') > 300 then
            return jsonb_build_object('error', 'bad-custom', 'line', r->>'label');
          end if;
        end loop;
      end if;
      v_mo := 1;
      if r->>'basis' = 'month' then
        if coalesce(r->>'months', '') !~ '^\d{1,2}$' or (r->>'months')::int not between 1 and 60 then
          return jsonb_build_object('error', 'bad-custom', 'line', r->>'label');
        end if;
        v_mo := (r->>'months')::int;
      end if;
      v_start := nullif(r->>'start', '');
      if v_start is not null and (v_start !~ '^\d{4}-\d{2}-\d{2}$' or public.doc_day_of(v_start) = date '0001-01-01') then
        return jsonb_build_object('error', 'bad-custom', 'line', r->>'label');
      end if;
      v_lines := v_lines || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'kind', 'custom', 'key', 'custom|' || i || '|' || btrim(r->>'label'), 'label', btrim(r->>'label'),
        'detail', coalesce(r->'detail', '[]'::jsonb), 'qty', (r->>'qty')::numeric, 'rate', (r->>'rate')::numeric,
        'basis', r->>'basis', 'months', v_mo, 'amount', round((r->>'qty')::numeric * (r->>'rate')::numeric, 2),
        'start', v_start, 'renews', nullif(r->>'renews', ''))));
      v_any := true;
    end loop;
  end if;
  if not v_any then return p_price; end if;
  v_tot := public.quote_totals(v_lines, v_term, coalesce((v_t->>'term_pct')::numeric, 0), coalesce((v_t->>'sst_pct')::numeric, 0));
  return p_price || jsonb_build_object('lines', v_lines,
    'totals', v_t || jsonb_build_object('month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment'));
end $$;
revoke all on function public.quote_custom(jsonb, jsonb) from public, anon, authenticated;

/* What a team's quotation adds as it is kept: each renewal names a
   confirmed line of this client, and Bill to one of its billing entities,
   its registered name, numbers and address held as the quotation printed
   them. */
create or replace function public.quote_client_extras(p_client uuid, p_lines jsonb, p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_e public.billing_entities;
  l jsonb;
begin
  for l in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    if coalesce(l->>'renews', '') <> '' and not exists (
         select 1 from public.client_services s
          where s.id = (l->>'renews')::uuid and s.client_id = p_client and s.archived_at is null and s.state = 'confirmed') then
      return jsonb_build_object('error', 'bad-renewal', 'line', l->>'label');
    end if;
  end loop;
  if coalesce(p_sel->>'entity', '') = '' then return '{}'::jsonb; end if;
  if p_sel->>'entity' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return jsonb_build_object('error', 'bad-entity');
  end if;
  select e.* into v_e from public.billing_entities e join public.client_entities ce on ce.entity_id = e.id
   where e.id = (p_sel->>'entity')::uuid and ce.client_id = p_client;
  if v_e.id is null then return jsonb_build_object('error', 'bad-entity'); end if;
  return jsonb_build_object('bill_to', jsonb_strip_nulls(jsonb_build_object('entity_id', v_e.id, 'legal_name', v_e.legal_name,
    'company_no', v_e.company_no, 'billing_address', v_e.billing_address)));
end $$;
revoke all on function public.quote_client_extras(uuid, jsonb, jsonb) from public, anon, authenticated;

create or replace function public.quote_extras(p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_pay int;
  v_rows jsonb := '[]'::jsonb;
  v_total numeric := 0;
  r jsonb;
  v_amt numeric;
  v_mo int;
  v_terms jsonb := '[]'::jsonb;
  t jsonb;
begin
  -- Payment terms for the whole quotation: NET 7 unless chosen.
  if coalesce(p_sel->>'pay', '') = '' then v_pay := 7;
  elsif p_sel->>'pay' ~ '^\d{1,3}$' then v_pay := (p_sel->>'pay')::int;
  else return jsonb_build_object('error', 'bad-pay'); end if;
  if v_pay not in (7, 14, 30, 60, 90) then return jsonb_build_object('error', 'bad-pay'); end if;
  if jsonb_typeof(p_sel->'ads') is not null and jsonb_typeof(p_sel->'ads') <> 'null' then
    if jsonb_typeof(p_sel->'ads') <> 'array' or jsonb_array_length(p_sel->'ads') > 6 then
      return jsonb_build_object('error', 'bad-ads');
    end if;
    for r in select * from jsonb_array_elements(p_sel->'ads') loop
      if jsonb_typeof(r) <> 'object'
         or coalesce(r->>'platform', '') not in ('meta', 'tiktok', 'google', 'xhs', 'youtube', 'linkedin')
         or coalesce(r->>'freq', '') not in ('monthly', 'once')
         or coalesce(r->>'budget', '') !~ '^\d{1,9}(\.\d{1,2})?$' then
        return jsonb_build_object('error', 'bad-ads');
      end if;
      v_amt := (r->>'budget')::numeric;
      if v_amt <= 0 then return jsonb_build_object('error', 'bad-ads'); end if;
      v_mo := null;
      if r->>'freq' = 'monthly' then
        if coalesce(r->>'months', '') !~ '^\d{1,2}$' or (r->>'months')::int not between 1 and 60 then
          return jsonb_build_object('error', 'bad-ads');
        end if;
        v_mo := (r->>'months')::int;
      end if;
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('platform', r->>'platform', 'freq', r->>'freq',
                  'budget', v_amt, 'months', v_mo, 'amount', v_amt * coalesce(v_mo, 1)));
      v_total := v_total + v_amt * coalesce(v_mo, 1);
    end loop;
  end if;
  /* The quotation's own terms (2026-11-12), one point a line, after the
     ones it works out: ten at most, 400 characters each. */
  if jsonb_typeof(p_sel->'terms') is not null and jsonb_typeof(p_sel->'terms') <> 'null' then
    if jsonb_typeof(p_sel->'terms') <> 'array' or jsonb_array_length(p_sel->'terms') > 10 then
      return jsonb_build_object('error', 'bad-terms');
    end if;
    for t in select * from jsonb_array_elements(p_sel->'terms') loop
      if jsonb_typeof(t) <> 'string' or length(t #>> '{}') > 400 then return jsonb_build_object('error', 'bad-terms'); end if;
      if btrim(t #>> '{}') <> '' then v_terms := v_terms || jsonb_build_array(btrim(t #>> '{}')); end if;
    end loop;
  end if;
  return jsonb_build_object('layout', 2, 'pay_days', v_pay, 'ads', v_rows, 'ads_total', v_total, 'terms', v_terms);
end $$;
revoke all on function public.quote_extras(jsonb) from public, anon, authenticated;

create or replace function public.quote_preview(p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_on date := public.doc_day_of(p_sel->>'date');
  v_card jsonb;
  v_cl uuid;
  v_fx numeric;
begin
  -- Priced on the quotation's own date (2026-11-12), today where none.
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  v_on := coalesce(v_on, (now() at time zone 'Asia/Kuala_Lumpur')::date);
  v_card := public.quote_card(v_on);
  if not public.is_team() or not public.allowed('clients.quotes', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  if coalesce(p_sel->>'client', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and public.client_scope_ok('client', (p_sel->>'client')::uuid, 'view') then
    v_cl := (p_sel->>'client')::uuid;
  end if;
  v_fx := public.quote_fx(v_cl);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- Custom lines and starts (2026-11-12) priced with the rest, before S$.
  return public.quote_fx_out(public.quote_custom(public.quote_adjust(public.quote_base(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_cl, v_on), v_fx),
           p_sel - 'client' - 'date'), public.quote_tax_edits(p_sel->'edits')), p_sel), v_fx) || jsonb_build_object('version', v_card->>'version');
end $$;

create or replace function public.quotation_make(p_client uuid, p_sel jsonb, p_idem text, p_source text,
                                                 p_by text, p_contact jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_c public.clients;
  v_on date := case when p_source = 'console' and jsonb_typeof(p_sel) = 'object' then public.doc_day_of(p_sel->>'date') end;
  v_card jsonb;
  v_p jsonb;
  v_q public.quotations;
  v_now timestamptz := now();
  v_days int;
  v_fx numeric;
  v_x jsonb;
  v_b jsonb;
  v_sel jsonb := case when jsonb_typeof(p_sel) is distinct from 'object' then p_sel
                      when p_source = 'console' then p_sel - 'client' - 'date'
                      else p_sel - 'edits' - 'client' - 'date' end;
begin
  if p_idem is not null then
    select * into v_q from public.quotations q where q.idem = p_idem and q.client_id = p_client;
    if v_q.id is not null then return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true); end if;
  end if;
  /* The quotation's own date (2026-11-12, the user: a document may be
     backdated): its reference's month, its validity, and the SST and terms
     in force; a team's alone, today where none is chosen. */
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  if v_on is not null and v_on <> (v_now at time zone 'Asia/Kuala_Lumpur')::date then
    v_now := (v_on::timestamp + (v_now at time zone 'Asia/Kuala_Lumpur')::time) at time zone 'Asia/Kuala_Lumpur';
  end if;
  v_on := (v_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_card := public.quote_card(v_on);
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_p := public.quote_fx_out(public.quote_custom(public.quote_adjust(public.quote_base(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id, v_on), v_fx),
           v_sel), public.quote_tax_edits(v_sel->'edits')), case when p_source = 'console' then v_sel else '{}'::jsonb end), v_fx);
  if v_p ? 'error' then return v_p; end if;
  /* The advertising budget and the payment terms (2026-11-12): a team's
     own; a website quotation takes none and NET 7. */
  v_x := public.quote_extras(case when p_source = 'console' then v_sel else '{}'::jsonb end);
  if v_x ? 'error' then return v_x; end if;
  if p_source = 'console' then
    v_b := public.quote_client_extras(v_c.id, v_p->'lines', v_sel);
    if v_b ? 'error' then return v_b; end if;
    v_x := v_x || v_b;
  end if;
  /* A quotation holds at least one priced line (2026-10-29): a selection of
     items quoted on request alone (a KOL campaign, a custom creator list)
     made a quotation with no line and no figure. */
  if jsonb_typeof(v_p->'lines') is distinct from 'array' or jsonb_array_length(v_p->'lines') = 0 then
    return jsonb_build_object('error', 'nothing-priced');
  end if;
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  begin
  insert into public.quotations (ref, client_id, brand, version, version_id, selection, lines, totals, source,
                                 issued_at, valid_until, made_by, contact, idem, access_key)
  values (public.quote_ref(v_c.name, v_now), v_c.id, v_c.name, v_card->>'version', (v_card->>'id')::uuid, v_sel,
          v_p->'lines', v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request') || v_x, p_source,
          v_now, (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days, p_by, p_contact, p_idem,
          case when p_source = 'website' then public.new_link_key() end)
  returning * into v_q;
  -- Two presses at once with one key: the second answers the first's.
  exception when unique_violation then
    select * into v_q from public.quotations q where q.idem = p_idem and q.client_id = p_client;
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

create or replace function public.quotation_edit(p_id uuid, p_sel jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_c public.clients;
  v_on date := public.doc_day_of(p_sel->>'date');
  v_card jsonb;
  v_ref text;
  v_was_ref text;
  v_p jsonb;
  v_fx numeric;
  v_now timestamptz := now();
  v_days int;
  v_sel jsonb;
  v_was numeric;
  v_is numeric;
  v_cur text;
  v_n int;
  v_doc text;
  v_x jsonb;
  v_b jsonb;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  if v_on is not null and v_on <> (v_now at time zone 'Asia/Kuala_Lumpur')::date then
    v_now := (v_on::timestamp + (v_now at time zone 'Asia/Kuala_Lumpur')::time) at time zone 'Asia/Kuala_Lumpur';
  end if;
  v_on := (v_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_card := public.quote_card(v_on);
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.removed_at is not null then return jsonb_build_object('error', 'removed'); end if;
  if v_q.signed_at is not null or v_q.reviewed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = v_q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if v_q.sent_out_at is not null or v_q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  -- A quotation a letter or service lines came from keeps its figures
  -- (2026-11-07), as its removal is refused then: Edit makes its revision.
  select count(*) into v_n from public.client_services s where s.quotation_id = v_q.id;
  if v_n > 0 then return jsonb_build_object('error', 'lines', 'count', v_n); end if;
  select d.number into v_doc from public.client_documents d
   where d.lines @> jsonb_build_array(jsonb_build_object('quotation_id', v_q.id::text))
   order by d.created_at limit 1;
  if v_doc is not null then return jsonb_build_object('error', 'letter', 'number', v_doc); end if;
  select * into v_c from public.clients where id = v_q.client_id;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- As the team builds it: their edits kept (quotation_make's console path).
  v_sel := p_sel - 'client' - 'date';
  v_p := public.quote_fx_out(public.quote_custom(public.quote_adjust(public.quote_base(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id, v_on), v_fx),
           v_sel), public.quote_tax_edits(v_sel->'edits')), case when v_q.source = 'console' then v_sel else '{}'::jsonb end), v_fx);
  if v_p ? 'error' then return v_p; end if;
  v_x := public.quote_extras(case when v_q.source = 'console' then v_sel else '{}'::jsonb end);
  if v_x ? 'error' then return v_x; end if;
  if v_q.source = 'console' then
    v_b := public.quote_client_extras(v_c.id, v_p->'lines', v_sel);
    if v_b ? 'error' then return v_b; end if;
    v_x := v_x || v_b;
  end if;
  if jsonb_typeof(v_p->'lines') is distinct from 'array' or jsonb_array_length(v_p->'lines') = 0 then
    return jsonb_build_object('error', 'nothing-priced');
  end if;
  v_was := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  /* A team's quotation dated into another month takes that month's
     reference (it has not been sent); the one it held is kept, never
     issued again. */
  v_ref := v_q.ref; v_was_ref := v_q.ref;
  if v_q.source = 'console' and v_q.ref !~ ('^ADP/QT' || to_char(v_on, 'YYMM') || '-') then
    v_ref := public.quote_ref(v_q.brand, v_now);
    insert into public.quotation_refs_kept (ref) values (v_q.ref) on conflict do nothing;
  end if;
  update public.quotations
     set ref = v_ref, version = v_card->>'version', version_id = (v_card->>'id')::uuid, selection = v_sel,
         lines = v_p->'lines', totals = v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request') || v_x,
         -- A team's quotation is dated when it is made ready; a website one
         -- keeps the day it was asked for (its validity runs from its send).
         issued_at = case when v_q.source = 'console' then v_now else issued_at end,
         valid_until = case when v_q.source = 'console' then (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days else valid_until end
   where id = v_q.id
  returning * into v_q;
  v_is := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_cur := case when v_fx is null then 'RM ' else 'S$ ' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_c.name,
          case when v_ref <> v_was_ref then v_was_ref || ' → ' else '' end || v_q.ref || ' edited · ' ||
          coalesce(v_cur || to_char(v_was, 'FM999,999,990.00'), 'not set') || ' → ' ||
          coalesce(v_cur || to_char(v_is, 'FM999,999,990.00'), 'not set') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref);
end $$;
revoke all on function public.quotation_edit(uuid, jsonb) from public, anon;

create or replace function public.quotation_review(p_id uuid, p_ok boolean, p_note text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  c  public.clients;
  co jsonb;
  v_note text := btrim(coalesce(p_note, ''));
  v_billing text := 'kept';
  v_lines int := 0;
  v_l jsonb;
  v_admin boolean;
  v_renewed int := 0;
  v_sid uuid;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  if q.submitted_at is null or q.returned_at is not null then return jsonb_build_object('error', 'not-submitted'); end if;
  -- A colleague with no role is no admin: a null here would let anyone through.
  v_admin := coalesce(me.is_admin, false) or coalesce(me.role, '') = 'admin';
  if q.reviewer_id is distinct from me.id and not v_admin then return jsonb_build_object('error', 'not-reviewer'); end if;

  if not coalesce(p_ok, false) then
    if length(v_note) < 2 or length(v_note) > 1000 then return jsonb_build_object('error', 'note-required'); end if;
    update public.quotations set returned_at = now(), return_note = v_note, returned_by = me.name where id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', q.brand, q.ref || ' · sent back by ' || me.name || ': ' || v_note);
    perform public.quote_sign_tell(array[public.quote_sign_member(q.submitted_by)], 'quote.returned',
      'Quotation sent back · ' || q.brand, q.ref || ' · ' || v_note, q.client_id, q.id::text || ':' || now()::text);
    return jsonb_build_object('ok', true, 'returned', true);
  end if;

  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  select * into c from public.clients where id = q.client_id for update;
  v_lines := 0;
  co := q.signed->'company';
  if exists (select 1 from public.bukku_links b where b.kind = 'client' and b.record_id = c.id and b.held_at is not null) then
    v_billing := 'held';
  elsif q.totals ? 'bill_to' then
    v_billing := 'kept';
  elsif coalesce(btrim(c.legal_name), '') = '' and coalesce(btrim(c.company_no), '') = '' and coalesce(btrim(c.billing_address), '') = '' then
    if not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'billing-access'); end if;
    update public.clients
       set legal_name = co->>'legal_name', company_no = co->>'company_no',
           company_no_old = coalesce(co->>'company_no_old', company_no_old), tin = coalesce(co->>'tin', tin),
           sst_no = coalesce(co->>'sst_no', sst_no), billing_address = co->>'billing_address',
           finance_email = coalesce(co->>'finance_email', finance_email)
     where id = c.id;
    v_billing := 'filled';
  end if;

  update public.client_services set state = 'confirmed'
   where quotation_id = q.id and archived_at is null and state <> 'confirmed';
  select count(*) into v_lines from public.client_services where quotation_id = q.id and archived_at is null;
  /* A renewal (2026-11-12) confirms the client's own line for its new
     term, rate and start, never a second line beside it. */
  for v_l in select * from jsonb_array_elements(q.lines) loop
    if coalesce(v_l->>'renews', '') <> '' then
      update public.client_services
         set qty = (v_l->>'qty')::numeric, rate = (v_l->>'rate')::numeric, state = 'confirmed',
             tenure = case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
             term_adjust = v_l->>'basis' = 'month', term_pct = case when v_l->>'basis' = 'month' then (q.totals->>'term_pct')::numeric else 0 end,
             start_on = coalesce(nullif(v_l->>'start', '')::date, start_on), quotation_id = q.id, note = 'Renewed by quotation ' || q.ref,
             detail = coalesce(nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''), detail)
       where id = (v_l->>'renews')::uuid and client_id = q.client_id and archived_at is null;
      if found then v_renewed := v_renewed + 1; end if;
    end if;
  end loop;
  if v_lines = 0 then
    for v_l in select * from jsonb_array_elements(q.lines) loop
      if coalesce(v_l->>'renews', '') <> '' then continue; end if;
      insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                          tenure, term_adjust, term_pct, detail, quotation_id, tax_code)
      values (q.client_id,
              case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
              v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
              case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'confirmed',
              'Quotation ' || q.ref,
              case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
              v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (q.totals->>'term_pct')::numeric else 0 end,
              nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
              q.id, nullif(v_l->>'tax_code', ''))
      returning id into v_sid;
      if coalesce(v_l->>'start', '') <> '' then
        update public.client_services set start_on = (v_l->>'start')::date where id = v_sid;
      end if;
      v_lines := v_lines + 1;
    end loop;
  end if;

  update public.quotations set reviewed_at = now(), reviewed_by = me.name, reviewed_role = nullif(btrim(coalesce(me.designation, '')), '')
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · reviewed and approved by ' || me.name ||
          case when q.reviewer_id is distinct from me.id then ' in place of ' || coalesce(q.reviewer_name, 'the reviewer') else '' end ||
          ' · ' || (v_lines + v_renewed) || case when v_lines + v_renewed = 1 then ' service line confirmed · ' else ' service lines confirmed · ' end ||
          case v_renewed when 0 then '' when 1 then '1 renewed · ' else v_renewed || ' renewed · ' end ||
          case v_billing when 'filled' then 'Billing filled from the signed quotation' when 'held' then 'Billing not changed, as Bukku keeps this client''s billing details'
               else 'Billing not changed' end);
  perform public.quote_sign_tell(array_remove(array[public.quote_sign_member(q.submitted_by), public.quote_sign_member(c.owner)], me.id),
    'quote.reviewed', 'Quotation approved · ' || q.brand, q.ref || ' · by ' || me.name, q.client_id, q.id::text);
  return jsonb_build_object('ok', true, 'billing', v_billing, 'lines', v_lines + v_renewed);
end $$;
revoke all on function public.quotation_review(uuid, boolean, text) from public, anon;

select public.functions_tidy();
