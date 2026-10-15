-- ===========================================================================
-- QUOTATION IN SINGAPORE DOLLARS — a Singapore client's quotation is priced
-- in S$ at the rate the team sets (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15: "singapore client reprice in S$, however needs
-- a place for us to input the currency rates so MYR plans or items charge in
-- SGD rate with dynamic manual input rates"): the rate card is in RM, and a
-- Singapore client's quotation read RM.
--
-- WHAT IT ADDS
--   * `fx_sgd`, a Business setting (Tax and terms, Singapore): the ringgit
--     to one Singapore dollar, from a day on, 0.5 to 10, four decimals;
--     `app_settings_set` takes it and files it from and to. Unset, nothing
--     is assumed.
--   * `quote_fx(p_client)`: null for a client not in Singapore; for one in
--     Singapore the rate in force today (MYT), else 0.
--   * `quote_fx_snap(p_snap, p_fx)`: the version's every rate in S$ (the RM
--     rate over the rate, to the cent); the budgets the card covers stay its
--     own, so a budget the page sends matches them as before.
--   * `quote_fx_out(p_price, p_fx)`: every RM figure in a line's words in S$
--     (whole dollars), and the totals marked `currency` SGD with the `fx`.
--   * `quote_preview` and `quotation_make` price a Singapore client so, and
--     refuse `no-fx` while the rate is unset; a quotation keeps what it was
--     priced at. Issue Letter of Offer takes the S$ lines as they stand.
--
-- ORDER
--   This file, then the pages (Tax and terms asks the rate; Build quote,
--   the quotation PDF and the website read S$). A page from before shows a
--   Singapore quotation's S$ figures under RM until it reloads.
--
-- Safe to run twice. Rollback: run QUOTATION TAX DAY's quote_preview and
-- quotation_make, and VIC CLIENTS's app_settings_set, again; then remove
-- quote_fx, quote_fx_snap, quote_fx_text and quote_fx_out.
-- ===========================================================================

create or replace function public.quote_fx(p_client uuid)
returns numeric
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from public.clients c where c.id = p_client and c.market = 'SG')
              then coalesce(nullif(public.app_setting('fx_sgd', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0), 0) end
$$;
revoke all on function public.quote_fx(uuid) from public, anon, authenticated;

create or replace function public.quote_fx_snap(p_snap jsonb, p_fx numeric)
returns jsonb
language sql immutable set search_path = public as $$
  select case when p_fx is null or p_fx <= 0 or jsonb_typeof(p_snap->'services') is distinct from 'array' then p_snap
    else jsonb_set(p_snap, '{services}', coalesce((
      select jsonb_agg(case when coalesce(x.s->>'rate', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
                            then jsonb_set(x.s, '{rate}', to_jsonb(round((x.s->>'rate')::numeric / p_fx, 2)))
                            else x.s end order by x.o)
        from jsonb_array_elements(p_snap->'services') with ordinality x(s, o)), '[]'::jsonb)) end
$$;
revoke all on function public.quote_fx_snap(jsonb, numeric) from public, anon, authenticated;

create or replace function public.quote_fx_text(p text, p_fx numeric)
returns text
language plpgsql immutable set search_path = public as $$
declare
  v_out text := '';
  v_rest text := p;
  v_m text[];
begin
  if p is null or p_fx is null or p_fx <= 0 then return p; end if;
  loop
    v_m := regexp_match(v_rest, '^(.*?)RM ?([0-9][0-9,]*(\.[0-9]+)?)(.*)$');
    exit when v_m is null;
    v_out := v_out || v_m[1] || 'S$ ' || to_char(round(replace(v_m[2], ',', '')::numeric / p_fx), 'FM999,999,990');
    v_rest := v_m[4];
  end loop;
  return v_out || v_rest;
end $$;
revoke all on function public.quote_fx_text(text, numeric) from public, anon, authenticated;

create or replace function public.quote_fx_out(p_price jsonb, p_fx numeric)
returns jsonb
language sql immutable set search_path = public as $$
  select case when p_fx is null or p_fx <= 0 or p_price ? 'error' then p_price
    else p_price
      || jsonb_build_object('lines', coalesce((
           select jsonb_agg(x.l || jsonb_build_object('label', public.quote_fx_text(x.l->>'label', p_fx))
                    || case when jsonb_typeof(x.l->'detail') = 'array' then jsonb_build_object('detail', coalesce((
                              select jsonb_agg(public.quote_fx_text(d.v, p_fx) order by d.o)
                                from jsonb_array_elements_text(x.l->'detail') with ordinality d(v, o)), '[]'::jsonb))
                            when jsonb_typeof(x.l->'detail') = 'string' then jsonb_build_object('detail', public.quote_fx_text(x.l->>'detail', p_fx))
                            else '{}'::jsonb end
                  order by x.o)
             from jsonb_array_elements(coalesce(p_price->'lines', '[]'::jsonb)) with ordinality x(l, o)), '[]'::jsonb))
      || jsonb_build_object('totals', coalesce(p_price->'totals', '{}'::jsonb) || jsonb_build_object('currency', 'SGD', 'fx', p_fx)) end
$$;
revoke all on function public.quote_fx_out(jsonb, numeric) from public, anon, authenticated;

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text; v_pre text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days', 'quote_valid_days', 'details_form_days', 'wa_repeat_hours',
    'bench_cpr_low', 'bench_cpr_mid', 'bench_cpr_high', 'bench_cpr_top', 'bench_msg_min', 'bench_msg_target', 'bench_msg_max',
    'bench_form_min', 'bench_form_target', 'bench_form_max', 'bench_cpm_min', 'bench_cpm_max', 'bench_cpl_rise',
    'bench_reels_share', 'bench_ad_spend_pct', 'bench_adset_daily', 'vic_lead_followup_hours', 'vic_proposal_followup_days', 'fx_sgd'];
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
    if round(v_v, case when v_k = 'fx_sgd' then 4 else 2 end) <> v_v
       or (v_k = 'fx_sgd' and (v_v < 0.5 or v_v > 10))
       or (v_k in ('lead_followup_hours', 'vic_lead_followup_hours') and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k in ('proposal_followup_days', 'vic_proposal_followup_days') and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
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
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k in ('bench_reels_share') and (v_v < 0 or v_v > 100))
       or (v_k = 'bench_ad_spend_pct' and (v_v < 1 or v_v > 100))
       or (v_k = 'bench_cpl_rise' and (v_v < -100 or v_v > 100))
       or (v_k like 'bench_%' and v_k not in ('bench_reels_share', 'bench_ad_spend_pct', 'bench_cpl_rise') and (v_v < 0 or v_v > 10000)) then
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
        when 'vic_lead_followup_hours' then 'A VIC lead waits' when 'vic_proposal_followup_days' then 'A VIC proposal waits'
        when 'sst_pct' then 'SST' when 'term_1_3' then '1 to 3 months' when 'term_4_5' then '4 and 5 months'
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 17 months' when 'term_18_23' then '18 to 23 months' when 'term_24' then '24 months and more'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input, a million tokens'
        when 'ai_price_out' then 'AI output, a million tokens' when 'ai_price_search' then 'AI web searches, a thousand' when 'meta_checks' then 'Meta checks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'wa_repeat_hours' then 'WhatsApp sent again'
        when 'bench_cpr_low' then 'Property cost per result, tier 1 from' when 'bench_cpr_mid' then 'Property cost per result, tier 2 from'
        when 'bench_cpr_high' then 'Property cost per result, tier 3 from' when 'bench_cpr_top' then 'Property cost per result, tier 3 up to'
        when 'bench_msg_min' then 'Messaging cost per result, low' when 'bench_msg_target' then 'Messaging cost per result, target'
        when 'bench_msg_max' then 'Messaging cost per result, high' when 'bench_form_min' then 'Lead form cost per result, low'
        when 'bench_form_target' then 'Lead form cost per result, target' when 'bench_form_max' then 'Lead form cost per result, high'
        when 'bench_cpm_min' then 'Cost per 1,000 impressions, low' when 'bench_cpm_max' then 'Cost per 1,000 impressions, high'
        when 'bench_cpl_rise' then 'Cost per lead rise a year' when 'bench_reels_share' then 'Reels share of impressions'
        when 'bench_ad_spend_pct' then 'Ad spend of the budget' when 'bench_adset_daily' then 'Daily budget an ad set, at least'
        when 'fx_sgd' then 'Singapore dollar rate'
        else 'Report due' end;
      v_pre := case when v_k = 'fx_sgd' then 'RM ' when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k = 'fx_sgd' then ' to S$1' when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'quote_valid_days', 'details_form_days') then ' days'
        when v_pre <> '' then '' else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || case when v_k = 'meta_checks' then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k = 'meta_checks' then '' else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit, 'not set') || ' → ' || v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit ||
              ' · from ' || public.register_day(p_from) end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

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
           p_sel - 'client'), p_sel->'edits'), v_fx) || jsonb_build_object('version', v_card->>'version');
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
           v_sel), v_sel->'edits'), v_fx);
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
          v_q.ref || ' sent · ' || coalesce('Monthly incl. SST ' || case when v_fx is null then 'RM ' else 'S$ ' end ||
            to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'key', v_q.access_key);
end $$;
revoke all on function public.quotation_make(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

-- END OF QUOTATION IN SINGAPORE DOLLARS ----------------------------------------

select public.functions_tidy();
