-- INVOICES SENT BY EMAIL -------------------------------------------------------
-- 2026-11-04, the user: "is it possible to build a send invoice (pulled data
-- and pdf from bukku) send to clients email?", approved with "attach link for
-- now": a colleague at Clients: Billing Work sends a client's unpaid invoice
-- (due or not) by email from its Billing, from ADspace Finance, the invoice
-- read again from Bukku at the press and its View invoice button Bukku's own
-- share link (Bukku's API holds no PDF to attach).
--
--   invoice_emails.purpose   reminder (as before) or invoice; Sent recently
--                            and the Email log tell the two apart
--   invoice_send_template    the invoice email's words (Settings, Templates:
--                            Invoice email, team.settings), seeded once
--   invoice_mail_begin       the one filing both sends share, the purpose
--                            choosing the words; invoice_email_begin keeps its
--                            signature and every refusal, invoice_send_begin
--                            is the same for an invoice; the service role's
--   invoice_reminders, mail_log   name each row's purpose; invoice_email_done
--                            files an invoice as Invoice emailed to …
--
-- Rollback (the SQL Editor's): revoke and remove invoice_send_begin,
-- invoice_mail_begin and the send template's two functions, restore
-- invoice_email_begin, invoice_reminders and mail_log from their earlier
-- sections; the column and the table may stay.

alter table public.invoice_emails add column if not exists purpose text not null default 'reminder';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'invoice_emails_purpose_check') then
    alter table public.invoice_emails add constraint invoice_emails_purpose_check check (purpose in ('reminder', 'invoice'));
  end if;
end $$;

create table if not exists public.invoice_send_template (
  id            int primary key default 1 check (id = 1),
  subject_one   text not null,
  subject_many  text not null,
  body          text not null,
  legal         text not null default '',
  disclaimer    text not null default '',
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.team_members(id)
);
alter table public.invoice_send_template enable row level security;
revoke all on table public.invoice_send_template from public, anon, authenticated;

insert into public.invoice_send_template (id, subject_one, subject_many, body, legal, disclaimer)
select 1, 'Invoice {invoice no} · ADspace', '{count} invoices · ADspace',
  E'Dear {contact name},\n\nPlease find below the details of invoice {invoice no} for {client}, with a total of {total} due.\n\n{invoices}\n\nThe invoice may be viewed and downloaded through View PDF. Kindly arrange payment by the due date.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance',
  '', coalesce((select r.disclaimer from public.invoice_email_template r where r.id = 1), '')
where not exists (select 1 from public.invoice_send_template);

create or replace function public.invoice_mail_begin(p_purpose text, p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members;
  t      public.invoice_email_template;
  v_tpl  public.invoice_send_template;
  rcp    jsonb;
  inv    jsonb;
  hours  numeric;
  r      public.invoice_emails;
  v_n    int;
  v_to   text;
  v_cc   text;
  v_who  text;
  v_co   text;
  v_tot  text;
  v_nos  text;
  v_list text[];
  v_vals jsonb;
  v_s    text;
  v_b    text;
  v_id   uuid;
begin
  select * into me from public.team_members x where x.id = p_actor and x.active;
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose is null or p_purpose not in ('reminder', 'invoice') then return jsonb_build_object('error', 'bad-request'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-request'); end if;
  if jsonb_typeof(p_invoices) <> 'array' or jsonb_array_length(p_invoices) < 1 or jsonb_array_length(p_invoices) > 50 then
    return jsonb_build_object('error', 'bad-invoices');
  end if;
  for inv in select value from jsonb_array_elements(p_invoices) loop
    if btrim(coalesce(inv->>'number', '')) = '' or coalesce(inv->>'number', '') !~ '^[^[:cntrl:]]{1,60}$' or coalesce(inv->>'currency', '') !~ '^[A-Z]{3}$'
       or (inv->>'amount') is null or (inv->>'amount')::numeric <= 0
       or (coalesce(inv->>'link', '') <> '' and inv->>'link' !~ '^https://[a-z0-9-]+\.bukku\.my/[A-Za-z0-9/_-]+$') then
      return jsonb_build_object('error', 'bad-invoices');
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended('invoice-mail:' || p_contact::text, 0));
  select * into r from public.invoice_emails x
   where x.bukku_contact = p_contact and x.status = 'sending' and x.created_at > now() - interval '10 minutes'
   order by x.created_at desc limit 1;
  if r.id is not null then return jsonb_build_object('error', 'sending'); end if;
  hours := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  if hours > 0 and not coalesce(p_again, false) then
    select * into r from public.invoice_emails x
     where x.bukku_contact = p_contact and x.purpose = p_purpose and x.status <> 'failed' and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
    if r.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', r.created_at, 'to', r.to_email,
        'by', (select m.name from public.team_members m where m.id = r.sent_by)));
    end if;
  end if;
  rcp := case when p_client is null then null else public.invoice_recipient_for(p_client, p_contact) end;
  v_to := coalesce(rcp->>'email', nullif(btrim(coalesce(p_email, '')), ''));
  if v_to is null or v_to !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then return jsonb_build_object('error', 'no-email'); end if;
  v_cc := case when coalesce(p_cc, false) and lower(coalesce(rcp->>'cc', '')) <> lower(v_to) then rcp->>'cc' end;
  v_co := coalesce(rcp->>'company', nullif(btrim(coalesce(p_name, '')), ''), 'Client');
  v_who := coalesce(rcp->>'name', 'Sir or Madam');
  v_n := jsonb_array_length(p_invoices);
  select string_agg(public.invoice_money(s.amt, s.cur), ' and ' order by s.cur) into v_tot
    from (select x->>'currency' as cur, sum((x->>'amount')::numeric) as amt
            from jsonb_array_elements(p_invoices) x group by x->>'currency') s;
  select array_agg(x->>'number' order by o) into v_list from jsonb_array_elements(p_invoices) with ordinality as a (x, o);
  v_nos := case when v_n = 1 then v_list[1]
                else array_to_string(v_list[1:v_n - 1], ', ') || ' and ' || v_list[v_n] end;
  v_vals := jsonb_build_object('contact name', v_who, 'client', v_co, 'invoice no', v_nos, 'count', v_n::text,
    'total', v_tot, 'sign off', case when rcp->>'name' is not null then 'Yours sincerely' else 'Yours faithfully' end);
  if p_purpose = 'invoice' then
    select * into v_tpl from public.invoice_send_template x where x.id = 1;
    t.subject_one := v_tpl.subject_one; t.subject_many := v_tpl.subject_many; t.body := v_tpl.body;
    t.legal := v_tpl.legal; t.disclaimer := v_tpl.disclaimer;
  else
    select * into t from public.invoice_email_template x where x.id = 1;
  end if;
  v_s := btrim(regexp_replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_subject, '')), ''),
           case when v_n = 1 then t.subject_one else t.subject_many end), v_vals), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_body, '')), ''), t.body), v_vals), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  insert into public.invoice_emails (client_id, bukku_contact, client_name, invoices, to_email, cc_email, subject, body, sent_by, purpose)
  values (p_client, p_contact, v_co, p_invoices, v_to, v_cc, v_s, v_b, me.id, p_purpose)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', v_to, 'cc', v_cc, 'subject', v_s, 'body', v_b,
    'legal', t.legal, 'disclaimer', t.disclaimer);
end $$;
revoke all on function public.invoice_mail_begin(text, uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.invoice_mail_begin(text, uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) to service_role;

create or replace function public.invoice_email_begin(p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean default false)
returns jsonb
language sql volatile security definer set search_path = public as $$
  select public.invoice_mail_begin('reminder', p_actor, p_client, p_contact, p_name, p_email, p_invoices, p_cc, p_subject, p_body, p_again)
$$;
revoke all on function public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) to service_role;

create or replace function public.invoice_send_begin(p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean default false)
returns jsonb
language sql volatile security definer set search_path = public as $$
  select public.invoice_mail_begin('invoice', p_actor, p_client, p_contact, p_name, p_email, p_invoices, p_cc, p_subject, p_body, p_again)
$$;
revoke all on function public.invoice_send_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.invoice_send_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) to service_role;

create or replace function public.invoice_send_template_get()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t public.invoice_send_template;
begin
  if (public.ops_me()).id is null or not (public.allowed('clients.billing', 'view') or public.ops_granted('team.settings', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into t from public.invoice_send_template x where x.id = 1;
  return jsonb_build_object('ok', true, 'subject_one', t.subject_one, 'subject_many', t.subject_many, 'body', t.body,
    'legal', t.legal, 'disclaimer', t.disclaimer, 'updated_at', t.updated_at,
    'updated_by', (select m.name from public.team_members m where m.id = t.updated_by));
end $$;
revoke all on function public.invoice_send_template_get() from public, anon;
grant execute on function public.invoice_send_template_get() to authenticated;

create or replace function public.invoice_send_template_save(p_subject_one text, p_subject_many text, p_body text,
  p_legal text, p_disclaimer text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.invoice_send_template;
  v_1 text := btrim(regexp_replace(coalesce(p_subject_one, ''), '\s+', ' ', 'g'));
  v_n text := btrim(regexp_replace(coalesce(p_subject_many, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  v_l text := btrim(regexp_replace(coalesce(p_legal, ''), '\s+', ' ', 'g'));
  v_d text := btrim(regexp_replace(coalesce(p_disclaimer, ''), '\s+', ' ', 'g'));
  moved text[] := '{}';
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_1) < 2 or length(v_1) > 200 or length(v_n) < 2 or length(v_n) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  if length(v_l) > 1000 or length(v_d) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into t from public.invoice_send_template x where x.id = 1 for update;
  if t.subject_one is distinct from v_1 then moved := moved || ('Subject, one invoice: ' || t.subject_one || ' → ' || v_1); end if;
  if t.subject_many is distinct from v_n then moved := moved || ('Subject, several invoices: ' || t.subject_many || ' → ' || v_n); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if t.legal is distinct from v_l then moved := moved || 'Legal note'::text; end if;
  if t.disclaimer is distinct from v_d then moved := moved || 'Disclaimer'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.invoice_send_template x set subject_one = v_1, subject_many = v_n, body = v_b, legal = v_l,
    disclaimer = v_d, updated_at = now(), updated_by = me.id where x.id = 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Invoice email', array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.invoice_send_template_save(text, text, text, text, text) from public, anon;
grant execute on function public.invoice_send_template_save(text, text, text, text, text) to authenticated;

create or replace function public.invoice_reminders(p_contacts bigint[])
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_all boolean;
begin
  if me.id is null or not public.allowed('clients.billing', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  v_all := public.client_scope_free('view');
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(r order by (r->>'at') desc) from (
      select jsonb_build_object('id', e.id, 'contact', e.bukku_contact, 'client', e.client_id,
               'purpose', e.purpose, 'invoices', e.invoices, 'to', e.to_email, 'cc', e.cc_email, 'subject', e.subject,
               'status', e.status, 'error', e.error, 'at', e.created_at, 'delivered_at', e.delivered_at,
               'opened_at', e.opened_at, 'bounced_at', e.bounced_at, 'by', m.name) as r
        from public.invoice_emails e
        left join public.team_members m on m.id = e.sent_by
       where e.bukku_contact = any(coalesce(p_contacts, '{}'::bigint[]))
         and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
       order by e.created_at desc
       limit 500) q), '[]'::jsonb));
end $$;
revoke all on function public.invoice_reminders(bigint[]) from public, anon;
grant execute on function public.invoice_reminders(bigint[]) to authenticated;

create or replace function public.mail_log(p_month date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_from date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Kuala_Lumpur')::date))::date;
  v_a    timestamptz;
  v_b    timestamptz;
  v_sup  boolean;
  v_bill boolean;
  v_quo  boolean;
  v_all  boolean;
begin
  if me.id is null or not public.allowed('whatsapp', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_a := v_from::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_b := (v_from + interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_sup := public.allowed('suppliers', 'view');
  v_bill := public.allowed('clients.billing', 'view');
  v_quo := public.allowed('clients.quotes', 'view');
  v_all := public.client_scope_free('view');
  return jsonb_build_object(
    'month', v_from,
    'items', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
        select * from (
          select 'supplier'::text as source, e.id, e.purpose as kind, e.to_email, e.cc_email, e.subject, e.body,
                 t.name as sent_by, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 null::uuid as client_id, null::text as client, e.supplier_id, s.name as supplier, s.code as supplier_code,
                 d.serial as reference, null::text as to_name
            from public.supplier_emails e
            left join public.suppliers s on s.id = e.supplier_id
            left join public.documents d on d.id = e.document_id
            left join public.team_members t on t.id = e.sent_by
           where v_sup and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'client', e.id, e.kind, e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, null, null, null,
                 e.reference, k.name
            from public.client_emails e
            left join public.clients c on c.id = e.client_id
            left join public.client_contacts k on k.id = e.contact_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and public.client_email_may(e.kind, 'view')
             and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
          union all
          select 'invoice', e.id, e.purpose, e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, coalesce(c.name, e.client_name), null, null, null,
                 (select string_agg(i->>'number', ', ' order by o) from jsonb_array_elements(e.invoices) with ordinality as a (i, o)),
                 null
            from public.invoice_emails e
            left join public.clients c on c.id = e.client_id
            left join public.team_members t on t.id = e.sent_by
           where v_bill and e.created_at >= v_a and e.created_at < v_b
             and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
          union all
          select 'signing', g.id, 'signing', g.email, null, 'Your ADspace signing code for quotation ' || q.ref, null,
                 null, g.created_at,
                 case when g.used_at is not null then 'used' when g.expires_at < now() then 'expired' else 'requested' end,
                 null, g.created_at, null, null, null,
                 q.client_id, c.name, null, null, null,
                 q.ref, nullif(btrim(coalesce(g.payload->'contact'->>'salutation', '') || ' ' || coalesce(g.payload->'contact'->>'name', '')), '')
            from public.quote_sign_codes g
            join public.quotations q on q.id = g.quotation_id
            left join public.clients c on c.id = q.client_id
           where v_quo and g.created_at >= v_a and g.created_at < v_b
             and (case when q.client_id is null then v_all else public.client_seen(q.client_id, 'view') end)
        ) u
        order by u.created_at desc
        limit 2000) x), '[]'::jsonb));
end $$;
revoke all on function public.mail_log(date) from public, anon;
grant execute on function public.mail_log(date) to authenticated;

create or replace function public.invoice_email_done(p_id uuid, p_status text, p_provider text, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e public.invoice_emails;
  m public.team_members;
begin
  if p_status not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into e from public.invoice_emails x where x.id = p_id and x.status = 'sending' for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.invoice_emails x set status = p_status, provider_id = nullif(p_provider, ''),
    error = left(nullif(p_error, ''), 480), sent_at = case when p_status = 'sent' then now() end
   where x.id = p_id;
  select * into m from public.team_members x where x.id = e.sent_by;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, 'system'), 'client.edited',
          coalesce((select c.name from public.clients c where c.id = e.client_id), e.client_name),
          case e.purpose when 'invoice' then 'Invoice ' else 'Overdue reminder ' end ||
          case p_status when 'sent' then 'emailed to ' when 'unknown' then 'emailed, not confirmed, to ' else 'not emailed to ' end ||
          e.to_email || coalesce(', cc ' || e.cc_email, '') || ' · ' ||
          (select string_agg(x->>'number', ', ') from jsonb_array_elements(e.invoices) x));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.invoice_email_done(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.invoice_email_done(uuid, text, text, text) to service_role;

-- END OF INVOICES SENT BY EMAIL

select public.functions_tidy();
