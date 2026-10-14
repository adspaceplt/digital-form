-- ===========================================================================
-- QUOTATION TERMS — a quotation is offered on 3, 6, 12, 18 or 24 months, each
-- with its own adjustment kept in Business settings (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-14: "for quotation, we accept flexibility starting
-- from 3 months, 6 months, 12 months, 18 months and 24 months. apply this to
-- everywhere related"; "with different period, it would have different
-- optional discounts (sometimes we dont even give), so this option of disc
-- rates or additional rates would stay in business settings")
--
-- WHAT CHANGED
--   * `quote_price` takes a term of 3, 6, 12, 18 or 24 months alone
--     (`bad-term`), a plan included (no longer six months or more); the
--     adjustment is the term's Business setting as the rate card version
--     holds it: 3 `term_1_3`, 6 `term_6_11`, 12 `term_12_23`, 18
--     `term_18_23` (a version published before it takes 12's), 24
--     `term_24`. 0 gives none.
--   * `term_18_23`, a new Business setting (Tax and terms, `team.settings`),
--     seeded with 12 months' figure so no price moves until it is edited;
--     `term_12_23` now covers 12 to 17 months. `app_settings_set` takes it,
--     and `rate_card_draft` carries it into the next published version.
--   Quotations already made keep the term and the figures they were made
--   with.
--
-- Safe to run twice. Rollback: run QUOTE GRAPHIC WORD's quote_price, WHATSAPP
-- SENT RECENTLY's app_settings_set and RATE CARD VERSIONS' rate_card_draft
-- again; the setting row may stay.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select 'term_18_23', date '2023-08-14', coalesce(public.app_setting('term_12_23', (now() at time zone 'Asia/Kuala_Lumpur')::date), -5)
 where not exists (select 1 from public.app_settings s where s.key = 'term_18_23');

/* Business settings take 18 months' adjustment. */
create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days', 'quote_valid_days', 'details_form_days', 'wa_repeat_hours'];
  v_moved text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, 2) <> v_v
       or (v_k = 'lead_followup_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'proposal_followup_days' and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k = 'meta_checks' and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v))) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      insert into public.app_settings (key, from_date, value, set_by, set_at)
      values (v_k, p_from, v_v, v_me.id, now())
      on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      v_name := case v_k when 'lead_followup_hours' then 'A lead waits' when 'proposal_followup_days' then 'A proposal waits'
        when 'sst_pct' then 'SST' when 'term_1_3' then '1 to 3 months' when 'term_4_5' then '4 and 5 months'
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 17 months' when 'term_18_23' then '18 to 23 months' when 'term_24' then '24 months and more'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input, a million tokens'
        when 'ai_price_out' then 'AI output, a million tokens' when 'ai_price_search' then 'AI web searches, a thousand' when 'meta_checks' then 'Meta checks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'wa_repeat_hours' then 'WhatsApp sent again' else 'Report due' end;
      v_unit := case when v_k in ('lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'quote_valid_days', 'details_form_days') then ' days'
        else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || case when v_k = 'meta_checks' then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k = 'meta_checks' then '' else case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_was, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end || ' → ' ||
              case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end ||
              ' · from ' || public.register_day(p_from) end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

/* The draft carries 18 months' adjustment into the next version. */
create or replace function public.rate_card_draft()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'services', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', s.slug, 'category', s.category, 'name', s.name, 'rate', s.rate, 'unit', s.unit,
        'position', s.position, 'active', s.active, 'note', s.note, 'detail', s.detail,
        'min_months', s.min_months, 'spec', s.spec) order by s.position, s.slug)
      from public.services s), '[]'::jsonb),
    'text', coalesce((select jsonb_object_agg(t.key, t.value) from public.rate_card_text t), '{}'::jsonb),
    'settings', (select jsonb_object_agg(k, public.app_setting(k, (now() at time zone 'Asia/Kuala_Lumpur')::date))
      from unnest(array['sst_pct', 'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24']) k))
$$;
revoke all on function public.rate_card_draft() from public, anon, authenticated;

/* The one calculation, on the five terms a quotation is offered on. */
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
  v_sub numeric := 0; v_once numeric := 0; v_pct numeric := 0; v_off numeric; v_excl numeric;
  v_sst_pct numeric := coalesce((v_set->>'sst_pct')::numeric, 0); v_sst numeric; v_osst numeric;
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

  select coalesce(sum((l->>'qty')::numeric * (l->>'rate')::numeric) filter (where l->>'basis' = 'month'), 0),
         coalesce(sum((l->>'qty')::numeric * (l->>'rate')::numeric) filter (where l->>'basis' = 'once'), 0),
         bool_or(l->>'basis' = 'month')
    into v_sub, v_once, v_month
    from jsonb_array_elements(v_lines) l;
  v_month := coalesce(v_month, false);
  if v_month and v_term = 1 then return jsonb_build_object('error', 'bad-term'); end if;
  v_pct := case when not v_month then 0
                when v_term <= 3 then coalesce((v_set->>'term_1_3')::numeric, 0)
                when v_term <= 5 then coalesce((v_set->>'term_4_5')::numeric, 0)
                when v_term <= 11 then coalesce((v_set->>'term_6_11')::numeric, 0)
                when v_term <= 17 then coalesce((v_set->>'term_12_23')::numeric, 0)
                when v_term <= 23 then coalesce((v_set->>'term_18_23')::numeric, (v_set->>'term_12_23')::numeric, 0)
                else coalesce((v_set->>'term_24')::numeric, 0) end;
  v_off := round(v_sub * v_pct / 100, 2);
  v_excl := v_sub + v_off;
  v_sst := round(v_excl * v_sst_pct / 100, 2);
  v_osst := round(v_once * v_sst_pct / 100, 2);

  return jsonb_build_object(
    'lines', (select jsonb_agg(l || jsonb_build_object('amount', round((l->>'qty')::numeric * (l->>'rate')::numeric, 2)))
                from jsonb_array_elements(v_lines) l),
    'on_request', to_jsonb(v_req),
    'extra_rates', v_hint,
    'totals', jsonb_build_object(
      'term', v_term, 'term_pct', v_pct, 'sst_pct', v_sst_pct, 'budget', greatest(v_budget, 0),
      'month', case when v_month then jsonb_build_object('subtotal', v_sub, 'term', v_off, 'excl', v_excl,
                 'sst', v_sst, 'incl', v_excl + v_sst) end,
      'once', case when v_once > 0 then jsonb_build_object('subtotal', v_once, 'sst', v_osst, 'incl', v_once + v_osst) end,
      'commitment', case when v_month then (v_excl + v_sst) * v_term else 0 end + v_once + v_osst));
end $$;
revoke all on function public.quote_price(jsonb, jsonb) from public, anon, authenticated;

-- END OF QUOTATION TERMS ----------------------------------------------------

select public.functions_tidy();
