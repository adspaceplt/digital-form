-- ===========================================================================
-- ADMIN NOTICES REACH THE SYSTEM ACCOUNT — and a waiting overseas request
-- reminds the admins until it is decided (2026-10-24)
-- ===========================================================================
-- WHY (the user, 2026-10-24): a colleague's overseas request reached one
-- admin, whose phone takes no notifications, and nobody else: the system
-- account was left out. "System account acts same as other admins. The
-- only difference is that it could overwrite everything without reason."
-- A request then waited with nothing to bring it back.
--
-- WHAT CHANGED
--   * `team_notice_send`, `quote_tell`, `client_details_submit`,
--     `supplier_form_submit` and `abroad_request` tell a system account as
--     they tell every other colleague who qualifies. Nothing else in them
--     moves. Task work (the reminders, pickers) still leaves it out.
--   * `team_abroad.reminded_at`; a request asked again starts afresh.
--   * `abroad_remind()` (pg_cron `abroad-remind`, every fifteen minutes from
--     08:00 to 22:45 MYT): every request still waiting, its colleague
--     active and its day not passed, tells every active admin again once
--     `abroad_remind_hours` (2, a Business setting, 0 sends none) have
--     passed since it was asked or last reminded. The service role's alone.
--
-- ORDER
--   This file, then OVERSEAS REMINDER SETTING in the SQL Editor (Settings
--   edits the hours only once it has run), then the pages. The page before
--   reads no new key; a reminder reads as the request's own notice.
--
-- Safe to run twice. Rollback: run each function from its section before
-- (TEAM NOTICES' send as last restated, QUOTATION WEBSITE, CLIENT DETAILS
-- FORM, SUPPLIER UPDATE LINK, OVERSEAS ACCESS) and unschedule
-- `abroad-remind`.
-- ===========================================================================

alter table public.team_abroad add column if not exists reminded_at timestamptz;

insert into public.app_settings (key, from_date, value)
select 'abroad_remind_hours', date '2023-08-14', 2
 where not exists (select 1 from public.app_settings s where s.key = 'abroad_remind_hours');

create or replace function public.team_notice_send(p_title text, p_body text, p_to uuid[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_title text := btrim(coalesce(p_title, ''));
  v_body  text := nullif(btrim(coalesce(p_body, '')), '');
  v_to    uuid[];
  v_id    uuid;
  n       int;
  v_sent  int;
  v_first timestamptz;
begin
  if me.id is null or not public.ops_granted('team.notice', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_title = '' or length(v_title) > 120 then return jsonb_build_object('error', 'bad-title'); end if;
  if v_body is not null and length(v_body) > 1000 then return jsonb_build_object('error', 'bad-body'); end if;
  perform pg_advisory_xact_lock(hashtext('team-notice-send:' || me.id::text));
  select count(*), min(tn.created_at) into v_sent, v_first
    from (select x.created_at from public.team_notices x
           where x.sent_by = me.id and x.created_at > now() - interval '1 hour'
           order by x.created_at desc limit 10) tn;
  if v_sent >= 10 then
    return jsonb_build_object('error', 'too-many', 'limit', 10, 'next', v_first + interval '1 hour');
  end if;
  select coalesce(array_agg(m.id order by m.name), '{}') into v_to
    from public.team_members m
   where m.active and m.id <> me.id
     and (p_to is null or m.id = any(p_to));
  n := coalesce(array_length(v_to, 1), 0);
  if n = 0 then return jsonb_build_object('error', 'no-one'); end if;
  insert into public.team_notices (title, body, to_all, recipients, sent_by, sent_by_name)
  values (v_title, v_body, p_to is null, v_to, me.id, me.name)
  returning id into v_id;
  insert into public.ops_notifications (team_member_id, kind, title, body, notice_id, from_name)
  select x, 'notice', v_title, v_body, v_id, me.name from unnest(v_to) as x;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Notices',
    'Sent to ' || case when p_to is null then 'all colleagues (' || n || ')'
                       when n = 1 then '1 colleague' else n || ' colleagues' end || ': ' || v_title);
  return jsonb_build_object('ok', true, 'id', v_id, 'count', n);
end $$;
revoke all on function public.team_notice_send(text, text, uuid[]) from public, anon;
grant execute on function public.team_notice_send(text, text, uuid[]) to authenticated;

create or replace function public.quote_tell(p_client uuid, p_kind text, p_title text, p_body text, p_key text)
returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, p_kind, p_title, p_body, p_client, p_kind || ':' || p_key || ':' || m.id
    from public.team_members m
   where m.active
     and (m.is_admin or m.role = 'admin'
          or public.level_rank(coalesce(m.access ->> 'clients.leads', m.access ->> 'clients')) >= 2)
  on conflict (dedupe_key) do nothing;
end $$;
revoke all on function public.quote_tell(uuid, text, text, text, text) from public, anon, authenticated;

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
  if exists (select 1 from public.clients c where c.id = v_f.client_id and c.stage = 'past') then
    return jsonb_build_object('error', 'not_found');
  end if;
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
  if length(t) < 8 or length(t) > 15 or length(v_cp) > 30 then return jsonb_build_object('error', 'bad-contact_phone'); end if;
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
  values ('Details form', 'client.edited', v_cl.name,
          'Billing details received on the details form from ' || coalesce(v_sal || ' ', '') || v_cn);
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.details', 'Billing details received · ' || v_cl.name,
         'From ' || coalesce(v_sal || ' ', '') || v_cn || '. Review them on the client''s Billing.',
         v_cl.id, 'client.details:' || v_f.id || ':' || m.id
    from public.team_members m
   where m.active
     and (m.is_admin or m.role = 'admin'
          or (public.level_rank(coalesce(m.access ->> 'clients.billing', m.access ->> 'clients')) >= 2
              -- held to the colleague's own client scope, as client_row_seen holds a reader (audit S7)
              and (v_cl.stage not in ('lead', 'contacted', 'proposal', 'past')
                   or public.level_rank(coalesce(m.access ->> case when v_cl.stage = 'past' then 'clients.past' else 'clients.leads' end,
                                                 m.access ->> 'clients')) >= 1)
              and (coalesce(m.client_scope, 'all') <> 'own'
                   or (nullif(btrim(coalesce(v_cl.owner, '')), '') is null and v_cl.stage in ('lead', 'contacted', 'proposal'))
                   or lower(btrim(coalesce(v_cl.owner, ''))) = lower(btrim(coalesce(m.name, ''))))))
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

create or replace function public.supplier_form_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f public.supplier_forms;
  s public.suppliers;
  v jsonb;
  a jsonb := coalesce(p_answers, '{}'::jsonb);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into f from public.supplier_forms x where x.access_key = p_key and x.voided_at is null for update;
  if f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  if coalesce(a->>'authorise', '') <> 'true' then return jsonb_build_object('error', 'bad-authorise'); end if;
  select * into s from public.suppliers x where x.id = f.supplier_id;
  /* An update keeps the NRIC and the bank details held where left blank. */
  if f.purpose = 'update' then
    if btrim(coalesce(a->>'bank_account', '')) = '' and s.bank_account is not null then
      a := a || jsonb_build_object('payee_name', s.payee_name, 'bank_name', s.bank_name, 'bank_account', s.bank_account,
                                   'swift', s.swift, 'bank_address', s.bank_address);
    end if;
    if btrim(coalesce(a->>'nric', '')) = '' and s.nric is not null then
      a := a || jsonb_build_object('nric', s.nric);
    end if;
  end if;
  v := public.supplier_values_check(a, true);
  if v ? 'error' then return v; end if;
  update public.supplier_forms x set submitted_at = now(), answers = jsonb_strip_nulls(v) where x.id = f.id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Supplier form', 'supplier.edited', coalesce(s.name, v->>'name'), s.code || ' · ' ||
          case when f.purpose = 'update' then 'Details update received on the update link' else 'Details received on the details form' end ||
          coalesce(' from ' || nullif(btrim(v->>'contact_name'), ''), ''));
  insert into public.ops_notifications (team_member_id, kind, title, body, supplier_id, dedupe_key)
  select m.id, 'supplier.details',
         case when f.purpose = 'update' then 'Supplier details update received · ' else 'Supplier details received · ' end || coalesce(s.name, v->>'name'),
         'From ' || (v->>'contact_name') || '. Review them on the supplier.',
         s.id, 'supplier.details:' || f.id || ':' || m.id
    from public.team_members m
   where m.active
     and (m.is_admin or m.role = 'admin'
          or public.level_rank(m.access ->> 'suppliers') >= 2)
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_form_submit(text, jsonb) from public;
grant execute on function public.supplier_form_submit(text, jsonb) to anon, authenticated;

create or replace function public.abroad_request(p_reason text, p_until date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t public.team_members := public.abroad_who();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days int := coalesce(public.app_setting('abroad_days', (now() at time zone 'Asia/Kuala_Lumpur')::date), 14)::int;
  v_reason text := btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g'));
  v_country text := public.request_country();
  v_id uuid;
begin
  if t.id is null then return jsonb_build_object('error', 'denied'); end if;
  if t.is_admin or t.role = 'admin' then return jsonb_build_object('error', 'admin'); end if;
  if char_length(v_reason) < 3 or char_length(v_reason) > 300 then return jsonb_build_object('error', 'bad-reason'); end if;
  if p_until is null or p_until < v_today or p_until > v_today + v_days then
    return jsonb_build_object('error', 'bad-until', 'max', v_today + v_days);
  end if;
  select x.id into v_id from public.team_abroad x
   where x.team_member_id = t.id and x.status = 'waiting' order by x.asked_at desc limit 1 for update;
  if v_id is null then
    insert into public.team_abroad (team_member_id, country, reason, until)
    values (t.id, v_country, v_reason, p_until) returning id into v_id;
  else
    update public.team_abroad set country = v_country, reason = v_reason, until = p_until, asked_at = now(), reminded_at = null
     where id = v_id;
  end if;
  insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
  select m.id, 'abroad.request', 'Overseas access requested · ' || t.name,
         case when v_country <> '' then 'From ' || v_country || ' · ' else '' end ||
         'until ' || public.register_day(p_until) || ' · ' || v_reason,
         'abroad:' || v_id || ':' || m.id || ':' || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI')
    from public.team_members m
   where m.active and (m.is_admin or m.role = 'admin')
  on conflict (dedupe_key) do nothing;
  return public.abroad_state();
end $$;
revoke all on function public.abroad_request(text, date) from public, anon;
grant execute on function public.abroad_request(text, date) to authenticated;

create or replace function public.abroad_remind()
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_hours numeric := coalesce(public.app_setting('abroad_remind_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 2);
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_n int := 0;
  r record;
begin
  if v_hours <= 0 then return 0; end if;
  for r in
    select x.id, x.country, x.reason, x.until, t.name
      from public.team_abroad x join public.team_members t on t.id = x.team_member_id
     where x.status = 'waiting' and t.active and x.until >= v_today
       and greatest(x.asked_at, coalesce(x.reminded_at, x.asked_at)) <= now() - make_interval(mins => (v_hours * 60)::int)
     order by x.asked_at
     for update of x skip locked
  loop
    update public.team_abroad set reminded_at = now() where id = r.id;
    insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
    select m.id, 'abroad.request', 'Overseas access waiting · ' || r.name,
           case when r.country <> '' then 'From ' || r.country || ' · ' else '' end ||
           'until ' || public.register_day(r.until) || ' · ' || r.reason,
           'abroad:' || r.id || ':remind:' || m.id || ':' || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI')
      from public.team_members m
     where m.active and (m.is_admin or m.role = 'admin')
    on conflict (dedupe_key) do nothing;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke all on function public.abroad_remind() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: no overseas reminders go out until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'abroad-remind';
  perform cron.schedule('abroad-remind', '*/15 0-14 * * *', 'select public.abroad_remind()');
end $$;

-- END OF ADMIN NOTICES REACH THE SYSTEM ACCOUNT ------------------------------

select public.functions_tidy();
