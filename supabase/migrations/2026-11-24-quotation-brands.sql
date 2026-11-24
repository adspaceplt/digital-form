-- ===========================================================================
-- QUOTATION BRANDS (2026-11-24)
-- ===========================================================================
-- WHY (the user, 2026-11-24): "the current build doesnt allow me to build
-- quote based on two different plans (eg. 1x plan F and 1x plan B for
-- another brand under same client entity)"; one quotation, a section a brand.
--
-- WHAT CHANGED
--   * `quote_compose(p_snap, p_sel, p_console)` (internal): a selection with
--     no `brands` is priced as before (quote_base, quote_adjust,
--     quote_custom); one with `brands` (1 to 10, each a `name` of 1 to 120
--     with its own plan, mix, platforms, extra, langs, translate, budget,
--     once, edits, custom and order) prices each brand so, marks its lines
--     with the brand's place (`brand`), and totals the whole once
--     (`quote_totals`), the names kept in `totals.brands` and each brand's
--     own figures answered in `brands`; a brand refused
--     names its place (`brand`, `brand_name`); a website selection with
--     `brands` is refused (`bad-brands`).
--   * `quote_preview`, `quotation_make` and `quotation_edit` price through it.
--
-- ORDER: this file (connector), then the pages. An old open Build quote
-- sends no `brands` and is priced as before. Safe to run twice.
-- ROLLBACK: run `quote_preview` and `quotation_make`, `quotation_edit` from
-- QUOTATION LINES OF OUR OWN and the section before it again; the new
-- function may stay.
-- ===========================================================================

-- QUOTATION BRANDS ------------------------------------------------------------

/* One quotation for several brands of one client (2026-11-24, the user: "1x
   plan F and 1x plan B for another brand under same client entity"): each
   brand of `p_sel.brands` is priced as a quotation of its own is (its plan,
   platforms, contents, budget, one-off items, edits, custom lines and
   order), its lines marked with their brand's place (`brand`), and the
   whole quotation totalled once on the term, the date and the Rate Card it
   shares. A selection with no `brands` is priced exactly as before. Brands
   are the team's alone: a website selection holding them is refused. */
create or replace function public.quote_compose(p_snap jsonb, p_sel jsonb, p_console boolean)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_keys constant text[] := array['plan', 'mix', 'platforms', 'extra', 'langs', 'translate', 'budget', 'once',
                                  'edits', 'custom', 'order'];
  v_b jsonb; v_s jsonb; v_p jsonb; v_t jsonb; v_first jsonb;
  v_lines jsonb := '[]'::jsonb; v_req jsonb := '[]'::jsonb; v_names jsonb := '[]'::jsonb; v_rates jsonb := '[]'::jsonb;
  v_i int := 0; v_adj int := 0; v_term int; v_pct numeric := 0; v_budget numeric := 0; v_name text;
  v_tot jsonb;
begin
  if jsonb_typeof(p_sel->'brands') is null or jsonb_typeof(p_sel->'brands') = 'null' then
    return public.quote_custom(public.quote_adjust(public.quote_base(p_snap, p_sel), public.quote_tax_edits(p_sel->'edits')),
                               case when p_console then p_sel else '{}'::jsonb end);
  end if;
  if not p_console or jsonb_typeof(p_sel->'brands') <> 'array' or jsonb_array_length(p_sel->'brands') not between 1 and 10 then
    return jsonb_build_object('error', 'bad-brands');
  end if;
  for v_b in select * from jsonb_array_elements(p_sel->'brands') loop
    v_name := case when jsonb_typeof(v_b) = 'object' and jsonb_typeof(v_b->'name') = 'string' then btrim(v_b->>'name') end;
    if v_name is null or length(v_name) not between 1 and 120 then
      return jsonb_build_object('error', 'bad-brands', 'brand', v_i);
    end if;
    -- the brand's own choices, on the quotation's term
    select coalesce(jsonb_object_agg(k, v_b->k), '{}'::jsonb) into v_s from unnest(v_keys) k where v_b ? k;
    v_s := v_s || jsonb_build_object('term', p_sel->'term');
    v_p := public.quote_custom(public.quote_adjust(public.quote_base(p_snap, v_s), public.quote_tax_edits(v_s->'edits')), v_s);
    if v_p ? 'error' then return v_p || jsonb_build_object('brand', v_i, 'brand_name', v_name); end if;
    v_t := coalesce(v_p->'totals', '{}'::jsonb);
    if v_first is null then v_first := v_t; end if;
    v_pct := case when coalesce((v_t->>'term_pct')::numeric, 0) <> 0 then (v_t->>'term_pct')::numeric else v_pct end;
    v_budget := v_budget + coalesce((v_t->>'budget')::numeric, 0);
    v_lines := v_lines || coalesce((select jsonb_agg(l || jsonb_build_object('brand', v_i) order by n)
                                      from jsonb_array_elements(v_p->'lines') with ordinality x(l, n)), '[]'::jsonb);
    v_req := v_req || coalesce(v_p->'on_request', '[]'::jsonb);
    v_names := v_names || jsonb_build_array(jsonb_build_object('name', v_name));
    -- each brand's own figures, for the builder's list
    v_rates := v_rates || jsonb_build_array(jsonb_build_object('name', v_name, 'extra_rates', coalesce(v_p->'extra_rates', '{}'::jsonb),
      'month', v_t->'month', 'once', v_t->'once', 'term_pct', v_t->'term_pct', 'term_rows', v_t->'term_rows'));
    v_adj := v_adj + coalesce((v_p->>'adjusted')::int, 0);
    v_i := v_i + 1;
  end loop;
  if jsonb_array_length(v_lines) = 0 and jsonb_array_length(v_req) = 0 then return jsonb_build_object('error', 'empty'); end if;
  v_term := coalesce((v_first->>'term')::int, 1);
  -- The figures, from the one calculation every quotation and letter shares.
  v_tot := public.quote_totals(v_lines, v_term, v_pct, coalesce((v_first->>'sst_pct')::numeric, 0));
  return jsonb_build_object('lines', v_lines, 'on_request', v_req, 'adjusted', v_adj,
    'extra_rates', coalesce(v_rates->0->'extra_rates', '{}'::jsonb), 'brands', v_rates,
    'totals', v_first || jsonb_build_object('term_pct', v_pct, 'budget', v_budget, 'brands', v_names,
      'month', v_tot->'month', 'once', v_tot->'once', 'commitment', v_tot->'commitment', 'term_rows', v_tot->'term_rows'));
end $$;
revoke all on function public.quote_compose(jsonb, jsonb, boolean) from public, anon, authenticated;

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
  v_card := public.quote_card(v_on, nullif(btrim(coalesce(p_sel->>'card', '')), ''));
  if not public.is_team() or not public.allowed('clients.quotes', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_card is null then return jsonb_build_object('error', case when nullif(btrim(coalesce(p_sel->>'card', '')), '') is not null then 'bad-card' else 'no-card' end); end if;
  if coalesce(p_sel->>'client', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and public.client_scope_ok('client', (p_sel->>'client')::uuid, 'view') then
    v_cl := (p_sel->>'client')::uuid;
  end if;
  v_fx := public.quote_fx(v_cl, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- Custom lines and starts (2026-11-12) priced with the rest, before S$.
  return public.quote_fx_out(public.quote_compose(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_cl, v_on), v_fx),
           p_sel - 'client' - 'date', true), v_fx)
         || jsonb_build_object('version', v_card->>'version', 'versions', public.quote_card_versions());
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
  -- the Rate Card chosen in Build quote, else the one live on the date (2026-11-15)
  v_card := public.quote_card(v_on, case when p_source = 'console' then nullif(btrim(coalesce(p_sel->>'card', '')), '') end);
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_p := public.quote_fx_out(public.quote_compose(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id, v_on), v_fx),
           v_sel, p_source = 'console'), v_fx);
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
          ' · Rate Card v.' || v_q.version ||
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
  v_card := public.quote_card(v_on, nullif(btrim(coalesce(p_sel->>'card', '')), ''));
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
  v_fx := public.quote_fx(v_c.id, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- As the team builds it: their edits kept (quotation_make's console path);
  -- a website quotation is never adjusted, as quotation_make holds (audit
  -- 2026-11-15).
  v_sel := case when v_q.source = 'console' then p_sel - 'client' - 'date' else p_sel - 'client' - 'date' - 'edits' end;
  v_p := public.quote_fx_out(public.quote_compose(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id, v_on), v_fx),
           v_sel, v_q.source = 'console'), v_fx);
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
          ' · Rate Card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref);
end $$;
revoke all on function public.quotation_edit(uuid, jsonb) from public, anon;

-- END OF QUOTATION BRANDS -----------------------------------------------------

select public.functions_tidy();
