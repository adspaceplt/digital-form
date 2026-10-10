-- ===========================================================================
-- WHATSAPP APPROVAL REMINDER — a client reminded on WhatsApp, by hand, when a
-- content set or a creator's draft has waited on their approval.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Run after 2026-10-10-whatsapp-approval-purpose.sql.
--
-- WHAT CHANGED (the user, 2026-10-10: "yes" to the approval chaser: manual,
-- its own template purpose, the wait a Business setting)
--   1. `approval_reminder_days` (3), a Business setting from a day on: how
--      long a published set or a draft at Reviewing waits on the client
--      before My Work's Waiting for you offers Remind. `app_settings_set`
--      takes it (1 to 60 whole days), filed as Approval reminder.
--   2. `wa_may_send('approval', 'contact')`: WhatsApp and its Approval
--      reminder part at Work, and Content Review: Content sets or Creator
--      Campaigns: Campaigns at View.
--   3. `wa_compose_prepare` and `wa_sent` take `approval` to a client
--      contact, `p_ref` a published content set of the contact's client
--      (Content sets View) or a booking at Reviewing on a campaign of that
--      client (Campaigns View); else `not-found` or `not-waiting`. It is
--      filed against the set (`set`) or the booking (`option`), and in the
--      activity record as "Approval reminder sent on WhatsApp to …".
--   4. `wa_template_set` names the purpose Approval reminder.
--
-- ROLLBACK
--   Pages first, then restate app_settings_set from META CHECKS SWITCH and
--   wa_may_send, wa_compose_prepare, wa_sent and wa_template_set from
--   WHATSAPP SECTION. The setting's row may stay.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select 'approval_reminder_days', date '2023-08-14', 3
 where not exists (select 1 from public.app_settings s where s.key = 'approval_reminder_days');

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days'];
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
       or (v_k = 'meta_checks' and v_v not in (0, 1)) then
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
        when 'ai_price_out' then 'AI output, a million tokens' when 'meta_checks' then 'Meta checks'
        when 'approval_reminder_days' then 'Approval reminder' else 'Report due' end;
      v_unit := case when v_k = 'lead_followup_hours' then ' hours' when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days') then ' days'
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

create or replace function public.wa_may_send(p_purpose text, p_to_kind text)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.allowed('whatsapp', 'work') and case p_purpose
    when 'report'   then public.allowed('whatsapp.report', 'work') and public.allowed('reports', 'view')
    when 'feedback' then public.allowed('whatsapp.feedback', 'work') and public.allowed('clients', 'view')
    when 'creator'  then public.allowed('whatsapp.booking', 'work') and public.allowed('campaigns', 'view')
    when 'approval' then p_to_kind = 'contact' and public.allowed('whatsapp.approval', 'work')
                         and (public.allowed('review.sets', 'view') or public.allowed('campaigns.campaigns', 'view'))
    when 'message'  then case p_to_kind when 'contact' then public.allowed('clients.contacts', 'view')
                                        when 'creator' then public.allowed('campaigns.creators', 'view')
                                        else false end
    else false end
$$;
revoke all on function public.wa_may_send(text, text) from public, anon, authenticated;

create or replace function public.wa_compose_prepare(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  k    public.client_contacts;
  cr   public.creators;
  c    public.clients;
  r    public.sm_reports;
  o    public.campaign_options;
  cp   public.campaigns;
  b    public.batches;
  v_n  text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose not in ('message', 'report', 'feedback', 'creator', 'approval') or p_to_kind not in ('contact', 'creator')
     or (p_purpose in ('report', 'feedback', 'approval') and p_to_kind <> 'contact')
     or (p_purpose = 'creator' and p_to_kind <> 'creator') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if not public.wa_may_send(p_purpose, p_to_kind) then return jsonb_build_object('error', 'denied'); end if;
  if p_to_kind = 'contact' then
    select * into k from public.client_contacts x where x.id = p_to and x.archived_at is null;
    if k.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = k.client_id;
    if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    if p_purpose = 'report' then
      select * into r from public.sm_reports x where x.id = p_ref;
      if r.id is null or r.client_id <> c.id then return jsonb_build_object('error', 'not-found'); end if;
      if r.status <> 'published' then return jsonb_build_object('error', 'not-published'); end if;
    end if;
    /* An approval reminder names what waits on the client: a published
       content set of theirs, or a creator's draft at Reviewing on a
       campaign of theirs, each read at its own section. */
    if p_purpose = 'approval' then
      select * into b from public.batches x where x.id = p_ref;
      if b.id is not null then
        if b.client_id <> c.id or not public.allowed('review.sets', 'view') then return jsonb_build_object('error', 'not-found'); end if;
        if not coalesce(b.published, false) then return jsonb_build_object('error', 'not-waiting'); end if;
      else
        select * into o from public.campaign_options x where x.id = p_ref;
        if o.id is not null then select * into cp from public.campaigns x where x.id = o.campaign_id; end if;
        if o.id is null or cp.id is null or cp.client_id is distinct from c.id or not public.allowed('campaigns.campaigns', 'view') then
          return jsonb_build_object('error', 'not-found');
        end if;
        if o.state <> 'reviewing' then return jsonb_build_object('error', 'not-waiting'); end if;
      end if;
    end if;
    v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
    if v_n is null then
      return jsonb_build_object('error', case when k.whatsapp ~ '^@' then 'username' else 'no-number' end);
    end if;
    return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'greeting', public.contact_greeting(k.salutation, k.name),
      'client_id', c.id, 'client', case when r.id is not null then coalesce(nullif(r.brand_name, ''), c.name) else c.name end,
      'subject', c.name, 'ref_kind', case when b.id is not null then 'set' when o.id is not null then 'option' end);
  end if;
  select * into cr from public.creators x where x.id = p_to;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_purpose = 'creator' then
    select * into o from public.campaign_options x where x.id = p_ref;
    if o.id is null or o.creator_id <> cr.id then return jsonb_build_object('error', 'not-found'); end if;
    select * into cp from public.campaigns x where x.id = o.campaign_id;
    if cp.id is null or (cp.client_id is not null and not public.client_seen(cp.client_id, 'view')) then
      return jsonb_build_object('error', 'not-found');
    end if;
    if o.state in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced') then
      return jsonb_build_object('error', 'not-booked');
    end if;
  elsif not cr.active then
    return jsonb_build_object('error', 'not-found');
  end if;
  v_n := public.wa_number(cr.whatsapp, 'MY');
  if v_n is null then return jsonb_build_object('error', 'no-creator-number'); end if;
  return jsonb_build_object('ok', true, 'number', v_n, 'name', cr.name, 'greeting', split_part(btrim(cr.name), ' ', 1),
    'client_id', cp.client_id,
    'campaign', case when cp.id is not null then coalesce(nullif(btrim(cp.title), ''), 'Your campaign') end,
    'code', cr.access_code, 'subject', coalesce(nullif(btrim(cp.title), ''), cr.name));
end $$;
revoke all on function public.wa_compose_prepare(text, uuid, text, uuid) from public, anon;
grant execute on function public.wa_compose_prepare(text, uuid, text, uuid) to authenticated;

create or replace function public.wa_sent(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid, p_template text,
                                          p_lang text, p_category text, p_params jsonb, p_ok boolean,
                                          p_wa_id text, p_error text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  p    jsonb := public.wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref);
  v_word text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p ? 'error' then return p; end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, state,
                                wa_id, error, created_by, sent_at, tries, to_kind, to_id, category)
  values (p_purpose, p ->> 'number', p ->> 'name', coalesce(nullif(btrim(p_template), ''), ''), coalesce(nullif(btrim(p_lang), ''), 'en'),
          case when jsonb_typeof(p_params) = 'array' then p_params else '[]'::jsonb end,
          case p_purpose when 'report' then 'report' when 'creator' then 'option' when 'feedback' then 'client'
                         when 'approval' then p ->> 'ref_kind' end,
          case when p_purpose in ('report', 'creator', 'approval') then p_ref when p_purpose = 'feedback' then (p ->> 'client_id')::uuid end,
          (p ->> 'client_id')::uuid,
          case when p_ok then 'sent' else 'failed' end, left(p_wa_id, 200), left(p_error, 500), me.name,
          case when p_ok then now() end, 1, p_to_kind, p_to,
          nullif(lower(btrim(coalesce(p_category, ''))), ''));
  if p_ok then
    v_word := case p_purpose when 'report' then 'Report' when 'feedback' then 'Feedback request'
                             when 'creator' then 'Booking' when 'approval' then 'Approval reminder' else 'Message' end;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'wa.sent', p ->> 'subject',
            case when p_purpose = 'creator' then (p ->> 'name') || ' · Booking sent on WhatsApp'
                 else v_word || ' sent on WhatsApp to ' || coalesce(nullif(btrim(p ->> 'name'), ''), 'the contact') end);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_sent(text, uuid, text, uuid, text, text, text, jsonb, boolean, text, text) from public, anon;
grant execute on function public.wa_sent(text, uuid, text, uuid, text, text, text, jsonb, boolean, text, text) to authenticated;

create or replace function public.wa_template_set(p_purpose text, p_name text, p_lang text, p_params integer,
                                                  p_category text, p_active boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  t      public.wa_templates;
  v_name text := btrim(coalesce(p_name, ''));
  v_lang text := btrim(coalesce(p_lang, ''));
  v_cat  text := lower(btrim(coalesce(p_category, '')));
  v_word text;
begin
  if me.id is null or not public.allowed('whatsapp', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.wa_templates x where x.purpose = p_purpose;
  if t.purpose is null then return jsonb_build_object('error', 'not-found'); end if;
  if (v_name !~ '^[a-z0-9_]+$' or length(v_name) > 512) and not (v_name = '' and not coalesce(p_active, false)) then
    return jsonb_build_object('error', 'bad-name');
  end if;
  if v_lang !~ '^[a-z]{2,3}(_[A-Z]{2})?$' then return jsonb_build_object('error', 'bad-lang'); end if;
  if p_params is null or p_params not between 0 and 5 then return jsonb_build_object('error', 'bad-params'); end if;
  if v_cat not in ('', 'utility', 'marketing', 'authentication') then return jsonb_build_object('error', 'bad-category'); end if;
  if t.name = v_name and t.lang = v_lang and t.params = p_params and t.category = v_cat and t.active = coalesce(p_active, false) then
    return jsonb_build_object('ok', true, 'same', true);
  end if;
  update public.wa_templates x
     set name = v_name, lang = v_lang, params = p_params, category = v_cat, active = coalesce(p_active, false),
         set_by = me.name, set_at = now()
   where x.purpose = p_purpose;
  v_word := case p_purpose when 'report' then 'Report to client' when 'feedback' then 'Feedback request'
                           when 'reminder' then 'Team reminders' when 'approval' then 'Approval reminder' else 'Creator updates' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'wa.template', 'WhatsApp',
          v_word || ': ' || coalesce(nullif(t.name, ''), 'not set') || ' (' || t.lang || ', ' || case when t.active then 'on' else 'off' end
          || ') → ' || coalesce(nullif(v_name, ''), 'not set') || ' (' || v_lang || ', ' || case when coalesce(p_active, false) then 'on' else 'off' end || ')');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_template_set(text, text, text, integer, text, boolean) from public, anon;
grant execute on function public.wa_template_set(text, text, text, integer, text, boolean) to authenticated;

-- END OF WHATSAPP APPROVAL REMINDER -------------------------------------------

select public.functions_tidy();
