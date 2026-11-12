-- =====================================================================
-- QUOTATION TERMS AND MONTHS IN ONE PLACE
-- 2026-11-12, the review of Build quote: the term's percentage is read by
-- one function (`quote_term_pct`) for quote_price and quote_base alike; a
-- custom line, an advertising budget and an edited line run 1 to 36
-- months; quote_custom takes no `starts` (nothing sent them).
-- =====================================================================
create or replace function public.quote_term_pct(p_set jsonb, p_term int)
returns numeric
language sql immutable set search_path = public as $$
  select case when p_term <= 3 then coalesce((p_set->>'term_1_3')::numeric, 0)
              when p_term <= 5 then coalesce((p_set->>'term_4_5')::numeric, 0)
              when p_term <= 11 then coalesce((p_set->>'term_6_11')::numeric, 0)
              when p_term <= 17 then coalesce((p_set->>'term_12_23')::numeric, 0)
              when p_term <= 23 then coalesce((p_set->>'term_18_23')::numeric, (p_set->>'term_12_23')::numeric, 0)
              else coalesce((p_set->>'term_24')::numeric, 0) end
$$;
revoke all on function public.quote_term_pct(jsonb, int) from public, anon, authenticated;

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
    v_detail := array[v_contents || ' content pieces per month: ' || array_to_string(v_words, ' and ') ||
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
          'label', 'Translation into ' || (v_lname->>v_l) || ', per content piece', 'detail', '[]'::jsonb,
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
                        when 'gif' then 'Graphic (GIF)' else v_s->>'name' end,
        'detail', coalesce((select jsonb_agg(btrim(regexp_replace(d, '^\s*::\s*', '')) order by o)
                              from unnest(string_to_array(coalesce(v_s->>'detail', ''), E'\n')) with ordinality as t(d, o)
                             where btrim(regexp_replace(d, '^\s*::\s*', '')) <> ''), '[]'::jsonb), 'qty', (v_x->>'qty')::int, 'rate', (v_s->>'rate')::numeric);
    end loop;
  end if;

  if jsonb_array_length(v_lines) = 0 and array_length(v_req, 1) is null then
    return jsonb_build_object('error', 'empty');
  end if;

  select coalesce(bool_or(l->>'basis' = 'month'), false) into v_month from jsonb_array_elements(v_lines) l;
  if v_month and v_term = 1 then return jsonb_build_object('error', 'bad-term'); end if;
  v_pct := case when not v_month then 0 else public.quote_term_pct(v_set, v_term) end;
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

create or replace function public.quote_base(p_snap jsonb, p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v jsonb := public.quote_price(p_snap, p_sel);
  v_set jsonb := coalesce(p_snap->'settings', '{}'::jsonb);
  v_term int;
  v_month boolean;
  v_pct numeric;
  v_if numeric;
begin
  v_term := case when coalesce(p_sel->>'term', '') ~ '^\d{1,2}$' then (p_sel->>'term')::int else 6 end;
  v_if := public.quote_term_pct(v_set, v_term);
  if v->>'error' is distinct from 'empty' or jsonb_typeof(p_sel->'custom') is distinct from 'array'
     or jsonb_array_length(p_sel->'custom') = 0 then
    if v ? 'totals' then v := jsonb_set(v, '{totals,term_pct_if}', to_jsonb(v_if)); end if;
    return v;
  end if;
  select coalesce(bool_or(x->>'basis' = 'month'), false) into v_month from jsonb_array_elements(p_sel->'custom') x;
  if v_month and v_term = 1 then return jsonb_build_object('error', 'bad-term'); end if;
  v_pct := case when v_month then v_if else 0 end;
  return jsonb_build_object('lines', '[]'::jsonb, 'on_request', '[]'::jsonb, 'extra_rates', '{}'::jsonb,
    'totals', jsonb_build_object('term', v_term, 'term_pct', v_pct, 'term_pct_if', v_if, 'sst_pct', coalesce((v_set->>'sst_pct')::numeric, 0), 'budget', 0));
end $$;
revoke all on function public.quote_base(jsonb, jsonb) from public, anon, authenticated;

create or replace function public.quote_custom(p_price jsonb, p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_t jsonb := coalesce(p_price->'totals', '{}'::jsonb);
  v_term int := coalesce((v_t->>'term')::int, 1);
  v_lines jsonb := p_price->'lines';
  r jsonb;
  d jsonb;
  i int := 0;
  v_mo int;
  v_start text;
  v_tot jsonb;
  v_any boolean := false;
begin
  if p_price ? 'error' or jsonb_typeof(p_price->'lines') is distinct from 'array' then return p_price; end if;
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
        if coalesce(r->>'months', '') !~ '^\d{1,2}$' or (r->>'months')::int not between 1 and 36 then
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
  return jsonb_build_object('layout', 2, 'pay_days', v_pay, 'ads', v_rows, 'ads_total', v_total, 'terms', v_terms);
end $$;
revoke all on function public.quote_extras(jsonb) from public, anon, authenticated;

-- END OF QUOTATION TERMS AND MONTHS IN ONE PLACE --------------------------

select public.functions_tidy();
