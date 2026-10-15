-- ===========================================================================
-- QUOTATION RATES — the team may quote a line at its own quantity, rate and
-- months
-- 2026-10-15. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner.
--
-- WHY (the user, 2026-10-15: Build quote "does not allow price change …
-- could you allow the price changes?"; "fully customised for the rates qty
-- and months", as the approved board drew it)
--   Build quote priced every line from the live rate card alone. A figure
--   the team agrees with a client (a discount, a rounded rate, a shorter
--   term for one line) could be typed on a service line but not on a
--   quotation.
--
-- WHAT CHANGED
--   * `quote_adjust(p_price, p_edits)` (internal): names each priced line
--     (`key`: kind|slug|label) and gives it `months` (the quotation's term
--     for a monthly line, 1 for a one-off); where `p_edits` holds the key,
--     the team's `qty` (1 to 9999), `rate` (up to seven digits and two
--     decimals; the card's kept as `list_rate`) and, on a monthly line,
--     `months` (1 to 36) take their place (`bad-edit`, naming the line).
--     The totals are worked again as `quote_price` works them (the term's
--     percentage on the monthly subtotal, SST on what remains, the one-off
--     subtotal apart); the commitment adds each monthly line for its own
--     months. A key no line holds is ignored; the card's own figures typed
--     back are no change.
--   * `quote_preview` answers the lines adjusted by `p_sel.edits`, each with
--     its key, so Build quote shows what will be kept.
--   * `quotation_make` keeps the adjusted lines for a quotation made in the
--     console (Clients: Services at Work, as `quotation_create` asks) and
--     files how many lines were changed; a quotation from the website is
--     never adjusted and keeps no `edits` in its selection.
--   * `quotation_offer` (Issue Letter of Offer) gives each To quote line the
--     months its quotation line holds (the term where it holds none).
--   * Make a copy prices the selection again, its edits with it.
--
-- ORDER
--   This file, then the pages. A page from before sends no edits and reads
--   the same figures as before.
--
-- ROLLBACK
--   Run the QUOTATIONS section's `quote_preview`, `quotation_make` and
--   `quotation_offer` again (supabase/migrations/2026-10-14-quotations.sql),
--   then: drop function if exists public.quote_adjust(jsonb, jsonb);
-- ===========================================================================

create or replace function public.quote_adjust(p_price jsonb, p_edits jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_t jsonb := coalesce(p_price->'totals', '{}'::jsonb);
  v_term int := coalesce((v_t->>'term')::int, 1);
  v_lines jsonb := '[]'::jsonb;
  v_l jsonb; v_e jsonb; v_k text; v_n int := 0; v_hit boolean;
  v_qty numeric; v_rate numeric; v_mo int;
  v_sub numeric := 0; v_once numeric := 0; v_month boolean := false; v_span numeric := 0; v_even boolean := true;
  v_pct numeric := coalesce((v_t->>'term_pct')::numeric, 0);
  v_sst_pct numeric := coalesce((v_t->>'sst_pct')::numeric, 0);
  v_off numeric; v_excl numeric; v_sst numeric; v_osst numeric;
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
         or (v_e ? 'months' and (v_l->>'basis' <> 'month' or coalesce(v_e->>'months', '') !~ '^[0-9]{1,2}$')) then
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
    end if;
    if v_hit then v_n := v_n + 1; end if;
    v_l := v_l || jsonb_build_object('key', v_k, 'qty', v_qty, 'rate', v_rate, 'months', v_mo,
                                     'amount', round(v_qty * v_rate, 2));
    v_lines := v_lines || jsonb_build_array(v_l);
    if v_l->>'basis' = 'month' then
      v_sub := v_sub + v_qty * v_rate; v_month := true;
      v_span := v_span + round(v_qty * v_rate, 2) * v_mo;
      v_even := v_even and v_mo = v_term;
    else
      v_once := v_once + v_qty * v_rate;
    end if;
  end loop;
  if v_n = 0 then
    return p_price || jsonb_build_object('lines', v_lines, 'adjusted', 0);
  end if;
  v_off := round(v_sub * v_pct / 100, 2);
  v_excl := v_sub + v_off;
  v_sst := round(v_excl * v_sst_pct / 100, 2);
  v_osst := round(v_once * v_sst_pct / 100, 2);
  return p_price || jsonb_build_object('lines', v_lines, 'adjusted', v_n,
    'totals', v_t || jsonb_build_object(
      'month', case when v_month then jsonb_build_object('subtotal', v_sub, 'term', v_off, 'excl', v_excl,
                 'sst', v_sst, 'incl', v_excl + v_sst) end,
      'once', case when v_once > 0 then jsonb_build_object('subtotal', v_once, 'sst', v_osst, 'incl', v_once + v_osst) end,
      'commitment', case when not v_month then 0
                         when v_even then (v_excl + v_sst) * v_term
                         else round(v_span * (1 + v_pct / 100) * (1 + v_sst_pct / 100), 2) end + v_once + v_osst));
end $$;
revoke all on function public.quote_adjust(jsonb, jsonb) from public, anon, authenticated;

-- Priced as it would be sent, read only (Build quote, as it is ticked and
-- as its lines are edited).
create or replace function public.quote_preview(p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_card jsonb := public.quote_card();
begin
  if not public.is_team() or not public.allowed('clients.services', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  return public.quote_adjust(public.quote_price(v_card->'snapshot', p_sel), p_sel->'edits') ||
         jsonb_build_object('version', v_card->>'version');
end $$;
revoke all on function public.quote_preview(jsonb) from public, anon;
grant execute on function public.quote_preview(jsonb) to authenticated;

-- Makes and keeps one quotation for a client. The same key twice is the
-- same quotation. Only the console's quotations take the team's edits.
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
  v_sel jsonb := case when p_source = 'console' or jsonb_typeof(p_sel) is distinct from 'object' then p_sel
                      else p_sel - 'edits' end;
begin
  if p_idem is not null then
    select * into v_q from public.quotations q where q.idem = p_idem;
    if v_q.id is not null then return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true); end if;
  end if;
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_p := public.quote_adjust(public.quote_price(v_card->'snapshot', v_sel), v_sel->'edits');
  if v_p ? 'error' then return v_p; end if;
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  insert into public.quotations (ref, client_id, brand, version, version_id, selection, lines, totals, source,
                                 issued_at, valid_until, made_by, contact, idem, access_key)
  values (public.quote_ref(v_c.name, v_now), v_c.id, v_c.name, v_card->>'version', (v_card->>'id')::uuid, v_sel,
          v_p->'lines', v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request'), p_source,
          v_now, (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days, p_by, p_contact, p_idem,
          case when p_source = 'website' then public.new_link_key() end)
  returning * into v_q;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(p_by, 'Website'), 'client.quotation', v_c.name,
          v_q.ref || ' sent · ' || coalesce('Monthly incl. SST RM ' ||
            to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'key', v_q.access_key);
end $$;
revoke all on function public.quotation_make(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

-- Issue Letter of Offer: the chosen quotation's lines become the client's
-- To quote lines, priced as quoted, once (a second press answers the same
-- lines).
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
  for v_l in select * from jsonb_array_elements(v_q.lines) loop
    insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                        tenure, term_adjust, term_pct, detail, quotation_id)
    values (v_q.client_id,
            case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
            v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
            case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'quoted',
            'Quotation ' || v_q.ref,
            case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (v_q.totals->>'term')::int) else 1 end,
            v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (v_q.totals->>'term_pct')::numeric else 0 end,
            nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
            v_q.id)
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || ' · ' || array_length(v_ids, 1) || ' lines To quote for the Letter of Offer');
  return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids));
end $$;
revoke all on function public.quotation_offer(uuid) from public, anon;
grant execute on function public.quotation_offer(uuid) to authenticated;

-- END OF QUOTATION RATES ------------------------------------------------------

select public.functions_tidy();
