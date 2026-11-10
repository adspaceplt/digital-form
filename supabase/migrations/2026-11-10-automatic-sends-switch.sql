-- ===========================================================================
-- AUTOMATIC SENDS SWITCHED — Settings, Messages: Automatic emails and
-- Automatic WhatsApp, each On or Off (2026-11-10)
-- ===========================================================================
-- WHY (the user, 2026-11-10: payment details approved for a creator in
-- arrears sent the creator emails "without me noticing which violates my
-- previous instructions"; "automatic only"): one switch a channel stops
-- everything the portal sends by itself; a send a colleague presses is not
-- held.
--
-- WHAT CHANGED
--   * `app_settings` keys `auto_email_on` and `auto_whatsapp_on` (1 On,
--     0 Off, from a day; seeded On, as before), read by `auto_send_on(kind)`
--     (internal) and set by `auto_send_set(p_kind, p_on)` (`team.settings`;
--     `bad-kind`; filed `team.changed` under Settings from and to).
--   * Off: `creator_mail_queue` and `creator_mail_job` (the six creator
--     emails) keep each email as Not sent (`failed`, `off: Automatic emails
--     are off.`), so the Email log shows what was held; it is never sent
--     later. `wa_enqueue` queues no colleague reminder and no creator
--     booking message. A quotation's WhatsApp (a colleague's press) and
--     every email a colleague sends go as before.
--
-- ORDER: this file (connector), then the pages (the Settings rows). Safe to
-- run twice. ROLLBACK: CREATOR PAYMENTS REVIEWED's creator_mail_queue and
-- creator_mail_job and the WHATSAPP section's wa_enqueue again.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select k, date '2023-08-14', 1 from (values ('auto_email_on'), ('auto_whatsapp_on')) v(k)
 where not exists (select 1 from public.app_settings s where s.key = v.k);

create or replace function public.auto_send_on(p_kind text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.app_setting(case p_kind when 'email' then 'auto_email_on' else 'auto_whatsapp_on' end,
                                     (now() at time zone 'Asia/Kuala_Lumpur')::date), 1) = 1
$$;
revoke all on function public.auto_send_on(text) from public, anon, authenticated;

create or replace function public.auto_send_set(p_kind text, p_on boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_key   text := case p_kind when 'email' then 'auto_email_on' when 'whatsapp' then 'auto_whatsapp_on' end;
  v_was   numeric;
  v_to    numeric := case when coalesce(p_on, false) then 1 else 0 end;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_key is null then return jsonb_build_object('error', 'bad-kind'); end if;
  v_was := coalesce(public.app_setting(v_key, v_today), 1);
  if v_was is not distinct from v_to then return jsonb_build_object('ok', true); end if;
  insert into public.app_settings (key, from_date, value, set_by, set_at)
  values (v_key, v_today, v_to, me.id, now())
  on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Settings',
          case p_kind when 'email' then 'Automatic emails: ' else 'Automatic WhatsApp: ' end ||
          case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_to = 1 then 'On' else 'Off' end ||
          ' · from ' || public.register_day(v_today));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.auto_send_set(text, boolean) from public, anon;
grant execute on function public.auto_send_set(text, boolean) to authenticated;

create or replace function public.wa_enqueue(p_purpose text, p_number text, p_name text, p_params jsonb,
                                             p_ref_kind text, p_ref_id uuid, p_client uuid, p_button text)
returns void
language plpgsql security definer set search_path = public as $$
declare t public.wa_templates;
begin
  select * into t from public.wa_templates x where x.purpose = p_purpose and x.active and x.name <> '';
  if t.purpose is null or p_number is null then return; end if;
  -- What the portal sends by itself waits on its switch (2026-11-10).
  if p_purpose in ('reminder', 'creator') and not public.auto_send_on('whatsapp') then return; end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, created_by, button,
                                to_kind, to_id, category)
  values (p_purpose, p_number, p_name, t.name, t.lang,
          coalesce((select jsonb_agg(e.value) from (select value from jsonb_array_elements(coalesce(p_params, '[]'::jsonb)) with ordinality e(value, n)
                     where n <= t.params order by n) e), '[]'::jsonb),
          p_ref_kind, p_ref_id, p_client, 'system', nullif(btrim(coalesce(p_button, '')), ''),
          case p_purpose when 'reminder' then 'colleague' when 'creator' then 'creator' else 'contact' end,
          case when p_purpose = 'reminder' then (select n.team_member_id from public.ops_notifications n where n.id = p_ref_id)
               when p_purpose = 'creator' then (select o.creator_id from public.campaign_options o where o.id = p_ref_id) end,
          nullif(t.category, ''));
  perform public.wa_kick();
end $$;

revoke all on function public.wa_enqueue(text, text, text, jsonb, text, uuid, uuid, text) from public, anon, authenticated;

create or replace function public.creator_mail_queue(p_purpose text, p_req uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t   public.creator_email_templates;
  r   public.creator_pay_requests;
  c   public.creators;
  v_to text;
  v_sub text;
  v_body text;
  v_vals jsonb;
begin
  select * into t from public.creator_email_templates x where x.purpose = p_purpose;
  if t.purpose is null or not t.on_send then return; end if;
  select * into r from public.creator_pay_requests x where x.id = p_req;
  select * into c from public.creators x where x.id = r.creator_id;
  v_to := lower(btrim(coalesce(case when p_purpose = 'review' then t.to_email else r.email end, '')));
  if v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return; end if;
  v_sub := t.subject;
  v_body := t.body;
  v_vals := jsonb_build_object(
    'creator name', c.name, 'creator id', coalesce(c.creator_code, ''), 'reference', r.ref, 'payee', r.payee,
    'method', public.creator_pay_method(r.method, r.bank), 'account ending', right(r.account, 4),
    'review link', 'https://digital.adspace.me/admin/?s=campaigns&tab=roster&pay=' || c.id);
  v_sub := public.creator_mail_fill(v_sub, v_vals);
  v_body := public.creator_mail_fill(v_body, v_vals);
  -- Off, the email is kept as Not sent and never sent later (2026-11-10).
  insert into public.creator_emails (purpose, creator_id, request_id, to_email, subject, body, status, error)
  values (p_purpose, c.id, r.id, v_to, left(v_sub, 200), v_body,
          case when public.auto_send_on('email') then 'queued' else 'failed' end,
          case when public.auto_send_on('email') then null else 'off: Automatic emails are off.' end);
  perform public.creator_mail_kick();
end $$;
revoke all on function public.creator_mail_queue(text, uuid) from public, anon, authenticated;

create or replace function public.creator_mail_job(p_purpose text, p_option uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t   public.creator_email_templates;
  fin public.creator_email_templates;
  o   public.campaign_options;
  c   public.creators;
  m   public.campaigns;
  r   public.creator_pay_requests;
  b   public.creator_bills;
  v_to text; v_sub text; v_body text; v_vals jsonb;
begin
  select * into t from public.creator_email_templates x where x.purpose = p_purpose;
  if t.purpose is null or not t.on_send then return; end if;
  select * into o from public.campaign_options x where x.id = p_option;
  select * into c from public.creators x where x.id = o.creator_id;
  select * into m from public.campaigns x where x.id = o.campaign_id;
  select * into r from public.creator_pay_requests x where x.creator_id = c.id and x.status = 'approved'
   order by x.decided_at desc limit 1;
  -- The bill this email is about: the one just told paid, else the newest.
  select * into b from public.creator_bills x where x.option_id = o.id and not x.gone
   order by x.paid_told_at desc nulls last, x.bill_date desc nulls last limit 1;
  select * into fin from public.creator_email_templates x where x.purpose = 'review';
  v_to := lower(btrim(coalesce(case when p_purpose = 'request' then fin.to_email else r.email end, '')));
  if v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return; end if;
  v_sub := t.subject;
  v_body := t.body;
  v_vals := jsonb_build_object(
    'creator name', c.name, 'creator id', coalesce(c.creator_code, ''),
    'job reference', coalesce(public.creator_job_ref(o.id), '') || coalesce(' (' || o.earlier_job || ')', ''),
    'campaign', coalesce(m.title, ''),
    'posted date', coalesce(public.register_day(o.posted_on), ''),
    'pay by', coalesce(public.register_day(o.pay_by), ''),
    'payee', coalesce(r.payee, 'Payment details pending approval'),
    'method', coalesce(public.creator_pay_method(r.method, r.bank), ''),
    'account ending', coalesce(right(r.account, 4), ''),
    'amount', case when b.amount is null then '' else
      case coalesce(b.currency, 'MYR') when 'MYR' then 'RM ' when 'SGD' then 'S$ ' else b.currency || ' ' end ||
      to_char(b.amount, 'FM999,999,990.00') end,
    'bill number', coalesce(b.number, ''),
    'review link', 'https://digital.adspace.me/admin/?s=campaigns&tab=roster&pay=' || c.id);
  v_sub := public.creator_mail_fill(v_sub, v_vals);
  v_body := public.creator_mail_fill(v_body, v_vals);
  -- Off, the email is kept as Not sent and never sent later (2026-11-10).
  insert into public.creator_emails (purpose, creator_id, request_id, option_id, to_email, subject, body, status, error)
  values (p_purpose, c.id, r.id, o.id, v_to, left(v_sub, 200), v_body,
          case when public.auto_send_on('email') then 'queued' else 'failed' end,
          case when public.auto_send_on('email') then null else 'off: Automatic emails are off.' end);
  perform public.creator_mail_kick();
end $$;
revoke all on function public.creator_mail_job(text, uuid) from public, anon, authenticated;

select public.functions_tidy();

-- END OF AUTOMATIC SENDS SWITCHED --------------------------------------------
