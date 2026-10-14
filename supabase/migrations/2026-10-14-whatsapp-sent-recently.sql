-- ===========================================================================
-- WHATSAPP SENT RECENTLY — the composer asks again before the same message
-- goes to the same person twice within a day (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-14: "once it is pressed or sent once within 24
-- hours if someone tried to send it again pops a notice that recently it has
-- been sent. So no duplicate would be repeated sent")
--
-- WHAT IT ADDS
--   * `wa_repeat_hours` (24), a Business setting from a day on (0 to 168, 0
--     asks nothing): how long a send counts as recent.
--   * `wa_sent_recently(p_to_kind, p_to, p_purpose, p_ref, p_template)` (as the
--     composer's caller, `wa_compose_prepare` first): the newest message not
--     failed to that recipient for that purpose and record (a feedback
--     request its client, a plain message its template) within the window,
--     with when, who sent it (none for the queue) and its state; else
--     `recent` false. `wa-send` asks it before a send unless the colleague
--     answered Send again.
--
-- Safe to run twice. Rollback: remove `wa_sent_recently`, restate app_settings_set
-- from CLIENT DETAILS FORM, and remove the `wa_repeat_hours` setting.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select 'wa_repeat_hours', date '2023-08-14', 24
 where not exists (select 1 from public.app_settings s where s.key = 'wa_repeat_hours');

/* Business settings take the hours a WhatsApp message counts as sent
   recently (WhatsApp, Sent again; 0 asks nothing). */
create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days',
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
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 23 months' when 'term_24' then '24 months and more'
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

create or replace function public.wa_sent_recently(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid, p_template text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_prep  jsonb;
  v_hours numeric := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  v_ref   uuid;
  w       public.wa_outbox;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  v_prep := public.wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref);
  if v_prep ? 'error' then return v_prep; end if;
  if v_hours <= 0 then return jsonb_build_object('ok', true, 'recent', false, 'hours', 0); end if;
  v_ref := case when p_purpose = 'feedback' then (v_prep ->> 'client_id')::uuid
                when p_purpose = 'message' then null else p_ref end;
  select * into w from public.wa_outbox x
   where x.to_kind = p_to_kind and x.to_id = p_to and x.purpose = p_purpose
     and x.state in ('queued', 'sending', 'sent')
     and x.created_at > now() - make_interval(hours => v_hours::int)
     and x.ref_id is not distinct from v_ref
     and (p_purpose <> 'message' or x.template = coalesce(p_template, ''))
   order by x.created_at desc limit 1;
  if w.id is null then return jsonb_build_object('ok', true, 'recent', false, 'hours', v_hours); end if;
  return jsonb_build_object('ok', true, 'recent', true, 'hours', v_hours, 'at', w.created_at,
    'by', case when w.created_by = 'system' then null else w.created_by end, 'to', w.to_name, 'state', w.state);
end $$;
revoke all on function public.wa_sent_recently(text, uuid, text, uuid, text) from public, anon;
grant execute on function public.wa_sent_recently(text, uuid, text, uuid, text) to authenticated;

-- END OF WHATSAPP SENT RECENTLY ----------------------------------------------

select public.functions_tidy();
