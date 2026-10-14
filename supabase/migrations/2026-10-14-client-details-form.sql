-- ===========================================================================
-- CLIENT DETAILS FORM — a link a client fills in with their company's
-- billing details, no sign-in, the answers waiting for the team (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-14: "a form … for client to fill in (public link, no
-- need any login when sent, for them to fill in all details like the company
-- name BRN, old BRN, TIN, contact hp, address, email etc. like a full set";
-- then "ok" to the plan)
--   Billing must be complete before a client is Active, and the team typed
--   it in from chat messages.
--
-- WHAT IT ADDS
--   * `client_detail_forms`: one row a link (the client, its key, made by
--     whom, when it ends, voided, submitted with its answers, used by whom).
--     RLS on, no policy, no grant.
--   * `client_details_link(p_client, p_reset)` (Clients: Billing at Work, the
--     client in scope at Work): the link still open, else a new one ending
--     `details_form_days` (14, a Business setting) from now; p_reset voids
--     the open one first. Filed `client.edited`. `app_settings_set` takes
--     `details_form_days` (1 to 90), edited in Tax and terms.
--   * `client_details_state(p_client)` (Clients: Billing at View): the latest
--     link, its key at Work alone, and the answers once submitted.
--   * `client_details_read(p_key)` (anon): the brand the link is for and when
--     it ends, else `not_found`, `expired` or `submitted`. Never a value the
--     record holds.
--   * `client_details_submit(p_key, p_answers)` (anon): the answers, once
--     (`submitted`), checked field by field (`bad-…`), the registered name in
--     capitals; the team at Clients: Billing Work told (kind
--     `client.details`, opening the client's Billing); filed.
--   * `client_details_used(p_id)` (Clients: Billing at Work): the answers
--     taken into the record by the team's own Save, stamped.
--   The answers never write into the record by themselves.
--
-- Safe to run twice. Rollback: drop the six functions and the table, and
-- delete the `details_form_days` setting.
-- ===========================================================================

create table if not exists public.client_detail_forms (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid not null references public.clients(id) on delete cascade,
  access_key   text not null unique,
  created_at   timestamptz not null default now(),
  created_by   uuid references public.team_members(id) on delete set null,
  expires_at   timestamptz not null,
  voided_at    timestamptz,
  submitted_at timestamptz,
  answers      jsonb,
  used_at      timestamptz,
  used_by      uuid references public.team_members(id) on delete set null
);
create index if not exists client_detail_forms_client_idx on public.client_detail_forms (client_id, created_at desc);
alter table public.client_detail_forms enable row level security;
revoke all on table public.client_detail_forms from public, anon, authenticated;

insert into public.app_settings (key, from_date, value)
select 'details_form_days', date '2023-08-14', 14
 where not exists (select 1 from public.app_settings s where s.key = 'details_form_days');

/* Business settings take the form's open days (Tax and terms). */
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
    'task_remind_hours', 'task_start_days', 'quote_valid_days', 'details_form_days'];
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
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v))) then
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
        when 'task_start_days' then 'Not started reminder' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open' else 'Report due' end;
      v_unit := case when v_k in ('lead_followup_hours', 'task_remind_hours') or v_k like 'priority_%_hours' then ' hours'
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

/* The link still open for a client, else a new one. */
create or replace function public.client_details_link(p_client uuid, p_reset boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_cl   public.clients;
  v_f    public.client_detail_forms;
  v_key  text;
  v_days int;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_cl from public.clients c where c.id = p_client;
  if v_cl.id is null or not public.client_seen(v_cl.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  select * into v_f from public.client_detail_forms f
   where f.client_id = p_client and f.voided_at is null and f.submitted_at is null and f.expires_at > now()
   order by f.created_at desc limit 1;
  if v_f.id is not null and not coalesce(p_reset, false) then
    return jsonb_build_object('ok', true, 'id', v_f.id, 'key', v_f.access_key, 'expires_at', v_f.expires_at);
  end if;
  update public.client_detail_forms f set voided_at = now()
   where f.client_id = p_client and f.voided_at is null and f.submitted_at is null;
  loop
    v_key := public.new_link_key();
    exit when not exists (select 1 from public.client_detail_forms f where f.access_key = v_key);
  end loop;
  v_days := coalesce(public.app_setting('details_form_days', (now() at time zone 'Asia/Kuala_Lumpur')::date), 14)::int;
  insert into public.client_detail_forms (client_id, access_key, created_by, expires_at)
  values (p_client, v_key, (select t.id from public.team_members t where t.id = me.id), now() + make_interval(days => v_days))
  returning * into v_f;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', v_cl.name,
          case when coalesce(p_reset, false) then 'Details form link reset' else 'Details form link created' end);
  return jsonb_build_object('ok', true, 'id', v_f.id, 'key', v_f.access_key, 'expires_at', v_f.expires_at);
end $$;
revoke all on function public.client_details_link(uuid, boolean) from public, anon;
grant execute on function public.client_details_link(uuid, boolean) to authenticated;

/* The latest link for a client: its state, the key at Work, the answers. */
create or replace function public.client_details_state(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  v_f  public.client_detail_forms;
  work boolean;
begin
  if me.id is null or not public.allowed('clients.billing', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  work := public.allowed('clients.billing', 'work');
  select * into v_f from public.client_detail_forms f
   where f.client_id = p_client and f.voided_at is null
   order by f.created_at desc limit 1;
  if v_f.id is null then return jsonb_build_object('ok', true); end if;
  return jsonb_build_object('ok', true, 'form', jsonb_strip_nulls(jsonb_build_object(
    'id', v_f.id,
    'key', case when work and v_f.submitted_at is null and v_f.expires_at > now() then v_f.access_key end,
    'state', case when v_f.used_at is not null then 'used' when v_f.submitted_at is not null then 'submitted'
                  when v_f.expires_at <= now() then 'expired' else 'open' end,
    'created_at', v_f.created_at, 'expires_at', v_f.expires_at,
    'submitted_at', v_f.submitted_at, 'used_at', v_f.used_at,
    'answers', case when v_f.submitted_at is not null then v_f.answers end)));
end $$;
revoke all on function public.client_details_state(uuid) from public, anon;
grant execute on function public.client_details_state(uuid) to authenticated;

/* What the client's page may know before it is filled in. */
create or replace function public.client_details_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_f  public.client_detail_forms;
  v_cl public.clients;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_f from public.client_detail_forms f where f.access_key = p_key and f.voided_at is null;
  if v_f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if v_f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if v_f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  return jsonb_build_object('ok', true, 'brand', v_cl.name, 'expires_at', v_f.expires_at);
end $$;
revoke all on function public.client_details_read(text) from public;
grant execute on function public.client_details_read(text) to anon, authenticated;

/* The client's answers, once, checked field by field. */
create or replace function public.client_details_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_f    public.client_detail_forms;
  v_cl   public.clients;
  a      jsonb := coalesce(p_answers, '{}'::jsonb);
  t      text;
  v_name text := upper(btrim(regexp_replace(coalesce(a->>'legal_name', ''), '\s+', ' ', 'g')));
  v_brn  text := upper(regexp_replace(coalesce(a->>'company_no', ''), '\s+', '', 'g'));
  v_old  text := nullif(upper(regexp_replace(coalesce(a->>'company_no_old', ''), '\s+', '', 'g')), '');
  v_tin  text := nullif(upper(regexp_replace(coalesce(a->>'tin', ''), '\s+', '', 'g')), '');
  v_sst  text := nullif(upper(regexp_replace(coalesce(a->>'sst_no', ''), '\s+', '', 'g')), '');
  v_addr text := btrim(coalesce(a->>'billing_address', ''));
  v_fin  text := nullif(lower(btrim(coalesce(a->>'finance_email', ''))), '');
  v_sal  text := nullif(btrim(coalesce(a->>'contact_salutation', '')), '');
  v_cn   text := btrim(regexp_replace(coalesce(a->>'contact_name', ''), '\s+', ' ', 'g'));
  v_cp   text := btrim(coalesce(a->>'contact_phone', ''));
  v_ce   text := lower(btrim(coalesce(a->>'contact_email', '')));
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_f from public.client_detail_forms f where f.access_key = p_key and f.voided_at is null for update;
  if v_f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if v_f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if v_f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  if length(v_name) < 2 or length(v_name) > 160 then return jsonb_build_object('error', 'bad-legal_name'); end if;
  if v_brn !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-company_no'); end if;
  if v_old is not null and v_old !~ '^[A-Z0-9-]{4,20}$' then return jsonb_build_object('error', 'bad-company_no_old'); end if;
  if v_tin is not null and v_tin !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-tin'); end if;
  if v_sst is not null and v_sst !~ '^[A-Z0-9-]{6,25}$' then return jsonb_build_object('error', 'bad-sst_no'); end if;
  if length(v_addr) < 10 or length(v_addr) > 400 then return jsonb_build_object('error', 'bad-billing_address'); end if;
  if v_fin is not null and (v_fin !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_fin) > 160) then
    return jsonb_build_object('error', 'bad-finance_email');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-contact_salutation');
  end if;
  if length(v_cn) < 2 or length(v_cn) > 80 then return jsonb_build_object('error', 'bad-contact_name'); end if;
  t := regexp_replace(v_cp, '[^0-9]', '', 'g');
  if length(t) < 8 or length(t) > 15 then return jsonb_build_object('error', 'bad-contact_phone'); end if;
  if v_ce !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_ce) > 160 then return jsonb_build_object('error', 'bad-contact_email'); end if;

  update public.client_detail_forms f
     set submitted_at = now(),
         answers = jsonb_strip_nulls(jsonb_build_object(
           'legal_name', v_name, 'company_no', v_brn, 'company_no_old', v_old, 'tin', v_tin, 'sst_no', v_sst,
           'billing_address', v_addr, 'finance_email', v_fin, 'contact_salutation', v_sal,
           'contact_name', v_cn, 'contact_phone', v_cp, 'contact_email', v_ce))
   where f.id = v_f.id;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_sal || ' ', '') || v_cn, 'client.edited', v_cl.name, 'Billing details received on the details form');
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.details', 'Billing details received · ' || v_cl.name,
         'From ' || coalesce(v_sal || ' ', '') || v_cn || '. Review them on the client''s Billing.',
         v_cl.id, 'client.details:' || v_f.id || ':' || m.id
    from public.team_members m
   where m.active and not coalesce(m.system, false)
     and (m.is_admin or m.role = 'admin'
          or public.level_rank(coalesce(m.access ->> 'clients.billing', m.access ->> 'clients')) >= 2)
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

/* The answers taken into the record, by the team's own Save. */
create or replace function public.client_details_used(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  v_f public.client_detail_forms;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_f from public.client_detail_forms f where f.id = p_id;
  if v_f.id is null or not public.client_seen(v_f.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if v_f.submitted_at is null then return jsonb_build_object('error', 'not-submitted'); end if;
  update public.client_detail_forms f set used_at = coalesce(f.used_at, now()), used_by = coalesce(f.used_by, (select t.id from public.team_members t where t.id = me.id)) where f.id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_used(uuid) from public, anon;
grant execute on function public.client_details_used(uuid) to authenticated;

-- END OF CLIENT DETAILS FORM -------------------------------------------------
select public.functions_tidy();
