-- ===========================================================================
-- QUOTE TOTALS IN ONE PLACE — a quotation's and a quoted letter's totals are
-- worked by one function. 2026-10-18. Safe to run twice. Rollback at the
-- foot. Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/sql.js and tests/lettersql.js compare the two.
--
-- WHAT CHANGED (the review of #538 to #550, item 8)
--   The same totals were worked in three places: `quote_price` (a
--   quotation as priced), `quote_adjust` (the lines the team edited) and
--   `issue_letter`'s quotation branch (a Letter of Offer from a quotation).
--   A change to one, as #544 showed, had to be found and made in the
--   others. `quote_totals(p_lines, p_term, p_pct, p_sst)` now works them:
--   the monthly lines' subtotal, the term's percentage once on it (to the
--   cent), the month's SST rounded once; the one-off lines and their SST
--   apart; the commitment by the month where every monthly line runs the
--   term, else on the whole span (each line's amount, to the cent, times
--   its months) with the percentage and SST taken once. A line's months
--   default to the term. All three call it, and no figure moves:
--   tests/sql.js prices a set of quotations before and after and compares
--   them whole, and tests/lettersql.js issues every quoted case again.
--   `quote_totals` is a helper no page calls: closed to every role.
--
-- ROLLBACK
--   Run quote_price again from QUOTATION TERMS, quote_adjust from
--   QUOTATION RATES and issue_letter from LETTERS PRICED AS THEIR QUOTATION
--   (each restates its own totals); quote_totals may stay.
-- ===========================================================================

create or replace function public.quote_totals(p_lines jsonb, p_term int, p_pct numeric, p_sst numeric)
returns jsonb
language sql immutable set search_path = public as $$
  with l as (
    select e->>'basis' = 'month' as m,
           coalesce((e->>'qty')::numeric, 0) * coalesce((e->>'rate')::numeric, 0) as v,
           greatest(1, coalesce((e->>'months')::int, p_term, 1)) as mo
      from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
  ), s as (
    select coalesce(sum(v) filter (where m), 0) as sub,
           coalesce(sum(round(v, 2) * mo) filter (where m), 0) as span,
           coalesce(bool_and(mo = p_term) filter (where m), true) as even,
           coalesce(bool_or(m), false) as month,
           coalesce(sum(v) filter (where not m), 0) as once
      from l
  ), t as (
    select s.*, round(sub * p_pct / 100, 2) as off, round(once * p_sst / 100, 2) as osst from s
  ), u as (
    select t.*, sub + off as excl, round((sub + off) * p_sst / 100, 2) as sst,
           round(span * (1 + p_pct / 100), 2) as span_excl,
           round(span * (1 + p_pct / 100) * (1 + p_sst / 100), 2) as span_incl
      from t
  )
  select jsonb_build_object(
    'month', case when month then jsonb_build_object('subtotal', sub, 'term', off, 'excl', excl, 'sst', sst, 'incl', excl + sst) end,
    'once', case when once > 0 then jsonb_build_object('subtotal', once, 'sst', osst, 'incl', once + osst) end,
    'even', even, 'span_excl', case when month then span_excl else 0 end, 'span_incl', case when month then span_incl else 0 end,
    'commitment', case when not month then 0 when even then (excl + sst) * p_term else span_incl end + once + osst)
  from u
$$;
revoke all on function public.quote_totals(jsonb, integer, numeric, numeric) from public, anon, authenticated;

create or replace function public.quote_price(p_snap jsonb, p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_svc jsonb := coalesce(p_snap->'services', '[]'::jsonb);
  v_set jsonb := coalesce(p_snap->'settings', '{}'::jsonb);
  v_text jsonb := coalesce(p_snap->'text', '{}'::jsonb);
  v_lines jsonb := '[]'::jsonb;
  v_req text[] := '{}';
  v_plan jsonb; v_spec jsonb; v_mix jsonb; v_opt jsonb;
  v_term int; v_mixi int := 0; v_slots int := 0; v_contents int := 0;
  v_meta numeric; v_fee numeric; v_val numeric; v_best numeric := 0; v_factor numeric;
  v_cover numeric := 0; v_budget numeric := 0; v_cost numeric; v_from numeric;
  v_plats text[] := '{}'; v_in text[] := '{}'; v_p text; v_k text; v_n int; v_q int;
  v_s jsonb; v_rate numeric; v_langs text[] := '{}'; v_l text; v_base text;
  v_pct numeric := 0; v_qtot jsonb;
  v_sst_pct numeric := coalesce((v_set->>'sst_pct')::numeric, 0);
  v_detail text[]; v_words text[]; v_tot int := 0; v_x jsonb; v_month boolean := false;
  v_hint jsonb := '{}'::jsonb;
  v_names constant jsonb := '{"meta":"Meta","tiktok":"TikTok","rednote":"rednote","linkedin":"LinkedIn"}';
  v_lname constant jsonb := '{"en":"English","zh":"Chinese","ms":"Malay"}';
begin
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if coalesce(p_sel->>'term', '') !~ '^[0-9]{1,2}$' then return jsonb_build_object('error', 'bad-term'); end if;
  v_term := (p_sel->>'term')::int;
  /* The terms a quotation is offered on (the user, 2026-10-14); 1 is
     one-off items alone, refused below where a monthly line is held. */
  if v_term not in (1, 3, 6, 12, 18, 24) then return jsonb_build_object('error', 'bad-term'); end if;
  select (s->>'rate')::numeric into v_meta from jsonb_array_elements(v_svc) s
   where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = 'meta' limit 1;
  v_meta := coalesce(v_meta, 0);

  -- Platforms asked for, known and once each, cheapest first.
  select coalesce(array_agg(p order by f, o), '{}') into v_plats
    from (select x.p, x.o, (select (s->>'rate')::numeric from jsonb_array_elements(v_svc) s
                             where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = x.p
                               and coalesce((s->>'active')::boolean, true) limit 1) f
            from (select distinct on (v) v as p, array_position(array['meta', 'tiktok', 'rednote', 'linkedin'], v) o
                    from jsonb_array_elements_text(coalesce(p_sel->'platforms', '[]'::jsonb)) v
                   where v in ('meta', 'tiktok', 'rednote', 'linkedin')) x) y
   where f is not null;

  if nullif(p_sel->>'plan', '') is not null then
    v_plan := public.quote_svc(p_snap, p_sel->>'plan');
    v_spec := v_plan->'spec';
    if v_plan is null or v_spec->>'role' is distinct from 'plan' or v_plan->>'rate' is null then
      return jsonb_build_object('error', 'bad-plan');
    end if;
    if coalesce(p_sel->>'mix', '0') ~ '^[0-9]$' then v_mixi := coalesce((p_sel->>'mix')::int, 0); end if;
    if v_mixi >= jsonb_array_length(v_spec->'mix') then v_mixi := 0; end if;
    v_mix := v_spec->'mix'->v_mixi;
    v_slots := (v_spec->>'platforms')::int;
    v_contents := (v_spec->>'contents')::int;
    v_cover := coalesce((v_spec->>'ad_budget')::numeric, 0);
    if array_length(v_plats, 1) is null then return jsonb_build_object('error', 'no-platform'); end if;
    v_in := v_plats[1:v_slots];

    -- The plan's whole saving: its fee against everything in it at Ala Carte,
    -- on the option worth more.
    for v_opt in select * from jsonb_array_elements(v_spec->'mix') loop
      v_val := v_slots * v_meta + coalesce(public.quote_ads_cost(p_snap, v_cover), 0);
      for v_k in select jsonb_object_keys(v_opt) loop
        select (s->>'rate')::numeric into v_rate from jsonb_array_elements(v_svc) s
         where s->'spec'->>'role' = 'content' and s->'spec'->>'kind' = v_k limit 1;
        v_val := v_val + coalesce(v_rate, 0) * (v_opt->>v_k)::int;
      end loop;
      v_best := greatest(v_best, v_val);
    end loop;
    v_factor := case when v_best > 0 then (v_plan->>'rate')::numeric / v_best else 1 end;
    -- What one more of each content costs on this plan, for the builder.
    select coalesce(jsonb_object_agg(s->>'slug', round((s->>'rate')::numeric * v_factor / 10) * 10), '{}'::jsonb) into v_hint
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'content' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true);

    v_words := '{}';
    for v_k in select k from jsonb_object_keys(v_mix) k
                order by array_position(array['graphic', 'reel'], k) nulls last, k loop
      v_n := (v_mix->>v_k)::int;
      v_words := v_words || (v_n || ' ' || case v_k when 'graphic' then case when v_n = 1 then 'graphic' else 'graphics' end
        when 'reel' then case when v_n = 1 then 'reel' else 'reels' end else v_k end);
    end loop;
    v_detail := array[v_contents || ' contents per month: ' || array_to_string(v_words, ' and ') ||
      case when v_mix ? 'reel' then ', up to 60 seconds each' else '' end];
    if v_cover > 0 then
      v_detail := v_detail || ('Advertising budget coverage up to ' || public.quote_rm(v_cover) || ' per month');
    end if;
    v_detail := v_detail || string_to_array(coalesce(v_text->>case when v_cover > 0 then 'plans_ads_included' else 'plans_included' end, ''), E'\n');
    v_lines := v_lines || jsonb_build_object('slug', v_plan->>'slug', 'kind', 'plan', 'basis', 'month',
      'label', 'Social Media Services · Plan ' || (v_spec->>'plan') || ' (' ||
        regexp_replace((select string_agg(v_names->>x, ', ' order by o) from unnest(v_in) with ordinality u(x, o)),
                       ', ([^,]*)$', ' and \1') || ')',
      'detail', (select jsonb_agg(d) from unnest(v_detail) d where btrim(d) <> ''),
      'qty', 1, 'rate', (v_plan->>'rate')::numeric);

    -- A dearer platform in a Meta-rate place adds the difference.
    foreach v_p in array v_in loop
      select (s->>'rate')::numeric, s->>'slug' into v_fee, v_k from jsonb_array_elements(v_svc) s
       where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = v_p limit 1;
      if v_fee > v_meta then
        v_lines := v_lines || jsonb_build_object('slug', v_k, 'kind', 'platform_in', 'basis', 'month',
          'label', (v_names->>v_p) || ' within the plan', 'detail', '[]'::jsonb, 'qty', 1, 'rate', v_fee - v_meta);
      end if;
    end loop;
    foreach v_p in array coalesce(v_plats[v_slots + 1:], '{}') loop
      select (s->>'rate')::numeric, s->>'slug' into v_fee, v_k from jsonb_array_elements(v_svc) s
       where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = v_p limit 1;
      v_lines := v_lines || jsonb_build_object('slug', v_k, 'kind', 'platform', 'basis', 'month',
        'label', 'Additional platform · ' || (v_names->>v_p), 'detail', '[]'::jsonb, 'qty', 1, 'rate', v_fee);
    end loop;

    -- Extra contents, at the plan's whole saving, to the nearest RM 10.
    if jsonb_typeof(p_sel->'extra') = 'object' then
      for v_k in select k from jsonb_object_keys(p_sel->'extra') k
                 order by array_position(array['static-graphic', 'gif', 'carousel', 'reels-30', 'reels-60', 'short-video-120'], k) nulls last, k loop
        if coalesce(p_sel->'extra'->>v_k, '') !~ '^[0-9]{1,2}$' then return jsonb_build_object('error', 'bad-extra'); end if;
        v_q := (p_sel->'extra'->>v_k)::int;
        continue when v_q = 0;
        v_s := public.quote_svc(p_snap, v_k);
        if v_s is null or v_s->'spec'->>'role' is distinct from 'content' or v_s->>'rate' is null then
          return jsonb_build_object('error', 'bad-extra');
        end if;
        v_lines := v_lines || jsonb_build_object('slug', v_k, 'kind', 'extra', 'basis', 'month',
          'label', 'Additional ' || lower(left(case v_s->'spec'->>'kind' when 'graphic' then 'Graphic (Static)' when 'carousel' then 'Graphic (Carousel)'
                        when 'gif' then 'Graphic (GIF)' else v_s->>'name' end, 1)) || substr(case v_s->'spec'->>'kind' when 'graphic' then 'Graphic (Static)' when 'carousel' then 'Graphic (Carousel)'
                        when 'gif' then 'Graphic (GIF)' else v_s->>'name' end, 2),
          'detail', '[]'::jsonb, 'qty', v_q,
          'rate', round((v_s->>'rate')::numeric * v_factor / 10) * 10);
        v_tot := v_tot + v_q;
      end loop;
    end if;
    v_tot := v_tot + v_contents;

    -- Translation, a content for each language after the first.
    select coalesce(array_agg(l order by array_position(array['en', 'zh', 'ms'], l)), '{}') into v_langs
      from (select distinct l from jsonb_array_elements_text(coalesce(p_sel->'langs', '[]'::jsonb)) l
             where l in ('en', 'zh', 'ms')) z;
    if coalesce((p_sel->>'translate')::boolean, false) and array_length(v_langs, 1) > 1 then
      v_s := (select s from jsonb_array_elements(v_svc) s where s->'spec'->>'role' = 'language'
               and coalesce((s->>'active')::boolean, true) limit 1);
      if v_s is null then return jsonb_build_object('error', 'no-translation'); end if;
      foreach v_l in array v_langs[2:] loop
        v_lines := v_lines || jsonb_build_object('slug', v_s->>'slug', 'kind', 'translation', 'basis', 'month',
          'label', 'Translation into ' || (v_lname->>v_l) || ', per content', 'detail', '[]'::jsonb,
          'qty', v_tot, 'rate', (v_s->>'rate')::numeric);
      end loop;
    end if;
  else
    -- No plan: each platform managed at its own fee.
    foreach v_p in array v_plats loop
      select (s->>'rate')::numeric, s->>'slug' into v_fee, v_k from jsonb_array_elements(v_svc) s
       where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = v_p limit 1;
      v_lines := v_lines || jsonb_build_object('slug', v_k, 'kind', 'platform', 'basis', 'month',
        'label', 'Account management · ' || (v_names->>v_p), 'detail', '[]'::jsonb, 'qty', 1, 'rate', v_fee);
    end loop;
  end if;

  -- The advertising budget past what the plan covers.
  if coalesce(p_sel->>'budget', '0') !~ '^-?[0-9]{1,7}$' then return jsonb_build_object('error', 'bad-budget'); end if;
  v_budget := (coalesce(p_sel->>'budget', '0'))::numeric;
  if v_budget < 0 then
    v_req := v_req || 'budget'::text;
  elsif v_budget > v_cover then
    v_cost := public.quote_ads_cost(p_snap, v_budget);
    if v_cost is null then
      v_req := v_req || 'budget'::text;
    elsif v_cover > 0 then
      v_lines := v_lines || jsonb_build_object('slug', null, 'kind', 'ads', 'basis', 'month',
        'label', 'Advertising budget coverage, up to ' || public.quote_rm(v_budget), 'detail', '[]'::jsonb,
        'qty', 1, 'rate', v_cost - public.quote_ads_cost(p_snap, v_cover));
    else
      select s into v_s from jsonb_array_elements(v_svc) s
       where s->'spec'->>'role' = 'ads' and coalesce((s->>'active')::boolean, true)
       order by ((s->'spec'->>'budget')::numeric >= v_budget) desc,
                case when (s->'spec'->>'budget')::numeric >= v_budget then (s->'spec'->>'budget')::numeric
                     else -(s->'spec'->>'budget')::numeric end
       limit 1;
      v_from := least(v_budget, (v_s->'spec'->>'budget')::numeric);
      v_lines := v_lines || jsonb_build_object('slug', v_s->>'slug', 'kind', 'ads', 'basis', 'month',
        'label', 'Meta advertising · advertising budget up to ' || public.quote_rm((v_s->'spec'->>'budget')::numeric),
        'detail', coalesce((select jsonb_agg(d) from unnest(string_to_array(coalesce(v_text->>'ads_included', ''), E'\n')) d
                             where btrim(d) <> ''), '[]'::jsonb),
        'qty', 1, 'rate', (v_s->>'rate')::numeric);
      if v_budget > (v_s->'spec'->>'budget')::numeric then
        v_lines := v_lines || jsonb_build_object('slug', null, 'kind', 'ads', 'basis', 'month',
          'label', 'Advertising budget coverage, up to ' || public.quote_rm(v_budget), 'detail', '[]'::jsonb,
          'qty', 1, 'rate', v_cost - (v_s->>'rate')::numeric);
      end if;
    end if;
  end if;

  -- One-off items; a KOL campaign and a custom KOC list are quoted on request.
  if jsonb_typeof(p_sel->'once') = 'array' then
    for v_x in select * from jsonb_array_elements(p_sel->'once') loop
      if coalesce(v_x->>'qty', '') !~ '^[0-9]{1,3}$' or (v_x->>'qty')::int < 1 then
        return jsonb_build_object('error', 'bad-once');
      end if;
      v_s := public.quote_svc(p_snap, v_x->>'slug');
      if v_s is null or coalesce(v_s->'spec'->>'role', '') not in ('content', 'verify', 'koc', 'kol', 'addon') then
        return jsonb_build_object('error', 'bad-once');
      end if;
      if v_s->>'rate' is null then v_req := v_req || (v_s->>'name')::text; continue; end if;
      v_lines := v_lines || jsonb_build_object('slug', v_s->>'slug', 'kind', v_s->'spec'->>'role', 'basis', 'once',
        'label', case v_s->'spec'->>'kind' when 'graphic' then 'Graphic (Static)' when 'carousel' then 'Graphic (Carousel)'
                        when 'gif' then 'Graphic (GIF)' else v_s->>'name' end, 'detail', '[]'::jsonb, 'qty', (v_x->>'qty')::int, 'rate', (v_s->>'rate')::numeric);
    end loop;
  end if;

  if jsonb_array_length(v_lines) = 0 and array_length(v_req, 1) is null then
    return jsonb_build_object('error', 'empty');
  end if;

  select coalesce(bool_or(l->>'basis' = 'month'), false) into v_month from jsonb_array_elements(v_lines) l;
  if v_month and v_term = 1 then return jsonb_build_object('error', 'bad-term'); end if;
  v_pct := case when not v_month then 0
                when v_term <= 3 then coalesce((v_set->>'term_1_3')::numeric, 0)
                when v_term <= 5 then coalesce((v_set->>'term_4_5')::numeric, 0)
                when v_term <= 11 then coalesce((v_set->>'term_6_11')::numeric, 0)
                when v_term <= 17 then coalesce((v_set->>'term_12_23')::numeric, 0)
                when v_term <= 23 then coalesce((v_set->>'term_18_23')::numeric, (v_set->>'term_12_23')::numeric, 0)
                else coalesce((v_set->>'term_24')::numeric, 0) end;
  -- The figures, from the one calculation every quotation and letter shares.
  v_qtot := public.quote_totals(v_lines, v_term, v_pct, v_sst_pct);

  return jsonb_build_object(
    'lines', (select jsonb_agg(l || jsonb_build_object('amount', round((l->>'qty')::numeric * (l->>'rate')::numeric, 2)))
                from jsonb_array_elements(v_lines) l),
    'on_request', to_jsonb(v_req),
    'extra_rates', v_hint,
    'totals', jsonb_build_object(
      'term', v_term, 'term_pct', v_pct, 'sst_pct', v_sst_pct, 'budget', greatest(v_budget, 0),
      'month', v_qtot->'month', 'once', v_qtot->'once', 'commitment', v_qtot->'commitment'));
end $$;
revoke all on function public.quote_price(jsonb, jsonb) from public, anon, authenticated;

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
           'service_id', cs.id)
           order by cs.created_at)
    into v_lines
    from public.client_services cs
   where cs.id = any(p_services);
  if v_lines is null then return jsonb_build_object('error', 'no-lines'); end if;

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
                'months', greatest(1, coalesce(cs.tenure, 1)))), '[]'::jsonb)
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
    select coalesce(sum(coalesce(cs.qty, 0) *
             round(coalesce(cs.rate, 0) *
               case when cs.term_adjust is false then 1
                    when cs.term_pct is not null then 1 + cs.term_pct / 100
                    else case greatest(1, coalesce(cs.tenure, 1))
                           when 3 then 1 / 0.9 when 12 then 0.95 when 24 then 0.9 else 1 end
               end, 2) *
             case when v_term > 0 then 1 else greatest(1, coalesce(cs.tenure, 1)) end)
             filter (where v_term > 0 and greatest(1, coalesce(cs.tenure, 1)) = v_term), 0),
           coalesce(sum(coalesce(cs.qty, 0) *
             round(coalesce(cs.rate, 0) *
               case when cs.term_adjust is false then 1
                    when cs.term_pct is not null then 1 + cs.term_pct / 100
                    else case greatest(1, coalesce(cs.tenure, 1))
                           when 3 then 1 / 0.9 when 12 then 0.95 when 24 then 0.9 else 1 end
               end, 2) *
             greatest(1, coalesce(cs.tenure, 1)))
             filter (where v_term = 0 or greatest(1, coalesce(cs.tenure, 1)) <> v_term), 0)
      into v_each, v_once
      from public.client_services cs where cs.id = any(p_services);
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce(public.app_setting('sst_pct', (timezone('Asia/Kuala_Lumpur', now()))::date), 0) end;
    v_etax := round(v_each * v_pct) / 100;
    v_otax := round(v_once * v_pct) / 100;
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

-- END OF QUOTE TOTALS IN ONE PLACE ----------------------------------------

select public.functions_tidy();
