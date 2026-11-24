-- ===========================================================================
-- QUOTATION BRANDS ON SERVICE LINES AND INVOICES (2026-11-24)
-- ===========================================================================
-- WHY: a quotation may now cover several brands of one client (QUOTATION
-- BRANDS, 2026-11-24); approved, its lines become service lines and each
-- cycle's invoice lines go to Bukku, where two brands' "Social Media
-- Services · Plan F" lines could not be told apart.
--
-- WHAT CHANGED
--   * `quote_line_label(p_totals, p_line)` (internal): on a quotation of two
--     brands or more, the line's brand name before its name ("Laman
--     Waringin · Social Media Services · Plan B (Meta)"); else the line's
--     own name.
--   * `quotation_review` (the service lines made on approval),
--     `quotation_offer` (the To quote lines of a Letter of Offer) and
--     `quotation_cycle_lines` (each cycle's invoice lines to Bukku) name a
--     line through it. A quotation of one brand reads as before.
--
-- ORDER: this file (connector); the pages are unchanged. Safe to run twice.
-- ROLLBACK: run `quotation_review`, `quotation_offer` and
-- `quotation_cycle_lines` from their sections before this one again; the new
-- function may stay.
-- ===========================================================================

-- QUOTATION BRANDS ON SERVICE LINES AND INVOICES -----------------------------

/* A quotation line's name where it leaves the quotation (a service line
   made on approval, an invoice line to Bukku): on a quotation for several
   brands (QUOTATION BRANDS, 2026-11-24) its brand's name before it, so two
   brands' Plan lines are told apart; else the line's own name. */
create or replace function public.quote_line_label(p_totals jsonb, p_line jsonb)
returns text
language sql immutable set search_path = public as $$
  select case when jsonb_typeof(p_totals->'brands') = 'array' and jsonb_array_length(p_totals->'brands') > 1
                   and coalesce(p_line->>'brand', '') ~ '^[0-9]{1,2}$'
                   and nullif(btrim(p_totals->'brands'->((p_line->>'brand')::int)->>'name'), '') is not null
              then btrim(p_totals->'brands'->((p_line->>'brand')::int)->>'name') || ' · ' || coalesce(nullif(btrim(p_line->>'label'), ''), 'Service')
              else coalesce(nullif(btrim(p_line->>'label'), ''), 'Service') end
$$;
revoke all on function public.quote_line_label(jsonb, jsonb) from public, anon, authenticated;

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
             term_adjust = v_l->>'basis' = 'month', term_pct = case when v_l->>'basis' = 'month' then coalesce((v_l->>'pct')::numeric, (q.totals->>'term_pct')::numeric) else 0 end,
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
              public.quote_line_label(q.totals, v_l), (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
              case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'confirmed',
              'Quotation ' || q.ref,
              case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
              v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then coalesce((v_l->>'pct')::numeric, (q.totals->>'term_pct')::numeric) else 0 end,
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

create or replace function public.quotation_cycle_lines(p_id uuid, p_cycle int, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  v_out jsonb := '[]'::jsonb;
  e jsonb;
  v_months int; v_month boolean; v_pct numeric; v_rate numeric; v_unit numeric;
  v_sst numeric; v_tax text; v_sku text;
  g record; v_last int; v_amt numeric; v_q numeric;
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
    v_out := v_out || jsonb_strip_nulls(jsonb_build_object('label', public.quote_line_label(q.totals, e),
      'qty', coalesce((e->>'qty')::numeric, 1), 'unit', v_unit, 'sst', v_sst, 'tax', v_tax, 'sku', v_sku,
      'pct', case when v_pct <> 0 then v_pct end, 'month', v_month,
      '_g', case when v_month and v_pct <> 0 then v_sst::text || '|' || v_pct::text end,
      '_v', coalesce((e->>'qty')::numeric, 1) * v_rate));
  end loop;
  for g in
    select x->>'_g' as k, max((x->>'pct')::numeric) as p, sum((x->>'_v')::numeric) as gsub,
           sum((x->>'qty')::numeric * (x->>'unit')::numeric) as billed, max(i) as last
      from jsonb_array_elements(v_out) with ordinality t(x, i)
     where x ? '_g' group by x->>'_g'
  loop
    v_amt := g.gsub + round(g.gsub * g.p / 100, 2) - g.billed;
    if v_amt <> 0 then
      v_last := g.last::int - 1;
      v_q := (v_out->v_last->>'qty')::numeric;
      v_amt := round(v_q * (v_out->v_last->>'unit')::numeric + v_amt, 2);
      v_out := jsonb_set(v_out, array[v_last::text], (v_out->v_last) || jsonb_build_object('qty', 1, 'unit', v_amt,
        'label', case when v_q <> 1 then trim(to_char(v_q, 'FM999990.##')) || ' × ' else '' end || (v_out->v_last->>'label')));
    end if;
  end loop;
  select coalesce(jsonb_agg((x - '_g') - '_v' order by i), '[]'::jsonb) into v_out
    from jsonb_array_elements(v_out) with ordinality t(x, i);
  return v_out;
end $$;
revoke all on function public.quotation_cycle_lines(uuid, integer, text) from public, anon, authenticated;

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
  if me.id is null or not (public.allowed('clients.quotes', 'work') and public.allowed('clients.services', 'work')
                           and public.allowed('clients.documents', 'work')) then return jsonb_build_object('error', 'denied'); end if;
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
            public.quote_line_label(v_q.totals, v_l), (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
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

-- END OF QUOTATION BRANDS ON SERVICE LINES AND INVOICES ----------------------

select public.functions_tidy();
