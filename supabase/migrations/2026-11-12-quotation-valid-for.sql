-- =====================================================================
-- QUOTATION VALID FOR
-- 2026-11-12, the user: "Build valid for". Build quote asks how many days
-- a quotation stands (14, 30, 45, 60 or 90; `p_sel.valid`), kept in its
-- totals as `valid_days`; `quotation_make` and `quotation_edit` count
-- `valid_until` from the quotation's Date by it, else by the Business
-- setting `quote_valid_days` as before. A website quotation sends none.
-- =====================================================================
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
  v_valid int;
begin
  -- Payment terms for the whole quotation: NET 7 unless chosen.
  if coalesce(p_sel->>'pay', '') = '' then v_pay := 7;
  elsif p_sel->>'pay' ~ '^\d{1,3}$' then v_pay := (p_sel->>'pay')::int;
  else return jsonb_build_object('error', 'bad-pay'); end if;
  if v_pay not in (7, 14, 30, 60, 90) then return jsonb_build_object('error', 'bad-pay'); end if;
  -- Valid for (2026-11-12): the days chosen in Build quote, else the
  -- Business setting, which the caller reads (`valid_days` left out).
  if coalesce(p_sel->>'valid', '') = '' then v_valid := null;
  elsif p_sel->>'valid' ~ '^\d{1,3}$' and (p_sel->>'valid')::int in (14, 30, 45, 60, 90) then v_valid := (p_sel->>'valid')::int;
  else return jsonb_build_object('error', 'bad-valid'); end if;
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
        if coalesce(r->>'months', '') !~ '^\d{1,2}$' or (r->>'months')::int not between 1 and 36 then
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
  return jsonb_strip_nulls(jsonb_build_object('layout', 2, 'pay_days', v_pay, 'valid_days', v_valid)) ||
    jsonb_build_object('ads', v_rows, 'ads_total', v_total, 'terms', v_terms);
end $$;
revoke all on function public.quote_extras(jsonb) from public, anon, authenticated;

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
  v_days := coalesce((v_x->>'valid_days')::int, public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
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
  v_days := coalesce((v_x->>'valid_days')::int, public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
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

-- END OF QUOTATION VALID FOR ---------------------------------------------

select public.functions_tidy();
