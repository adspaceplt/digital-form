-- INVOICE RECIPIENTS CHOSEN ---------------------------------------------------
-- 2026-11-04, the user: "can we have option to choose which email to send,
-- which email to cc but only related to the client contacts": Review and send
-- (an overdue reminder, an invoice sent by email) asks To among the client's
-- contacts holding an email, and Copy among the rest and the finance email,
-- never an address typed in.
--
--   invoice_recipient_options   the addresses an invoice email to a client may
--                               go to: its live contacts holding an email, the
--                               billing contact the email goes to by default
--                               (an entity's shared one may be another brand's)
--                               and the finance email; internal
--   invoice_recipients          the same for the sheet, at Clients: Billing
--                               View on a client the colleague sees
--   invoice_mail_begin          takes the chosen To (p_to) and Copy (p_ccs, five
--                               at most) and refuses any other address
--                               (`bad-recipient`, `bad-copy`); the greeting
--                               follows the contact chosen; null for both reads
--                               as before, which the eleven-argument form keeps
--
-- Rollback (the SQL Editor's): restore invoice_mail_begin's eleven-argument
-- body from INVOICES SENT BY EMAIL, then revoke and remove the thirteen-
-- argument form, invoice_recipients and invoice_recipient_options.

create or replace function public.invoice_recipient_options(p_client uuid, p_contact bigint)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  rcp  jsonb;
  v_to text;
  v_cc text;
begin
  if p_client is null then return '[]'::jsonb; end if;
  rcp := public.invoice_recipient_for(p_client, p_contact);
  v_to := lower(nullif(btrim(coalesce(rcp->>'email', '')), ''));
  v_cc := lower(nullif(btrim(coalesce(rcp->>'cc', '')), ''));
  return coalesce((
    select jsonb_agg(jsonb_build_object('email', o.email, 'name', o.name, 'role', o.role, 'finance', o.fin, 'billing', o.bill)
             order by o.ord, o.name nulls last, o.email)
      from (select distinct on (lower(u.email)) u.*
              from (select btrim(x.email) as email, nullif(public.contact_named(x.salutation, x.name), '') as name,
                           nullif(btrim(coalesce(x.role, '')), '') as role, false as fin,
                           coalesce(lower(btrim(x.email)) = v_to, false) as bill,
                           case when lower(btrim(x.email)) = v_to then 0 when x.is_primary then 1 else 2 end as ord
                      from public.client_contacts x
                     where x.client_id = p_client and x.archived_at is null
                       and coalesce(btrim(x.email), '') ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$'
                    union all
                    select btrim(rcp->>'email'), nullif(rcp->>'name', ''), null, false, true, 0
                     where v_to is not null and v_to ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$'
                    union all
                    select btrim(rcp->>'cc'), null, null, true, false, 3
                     where v_cc is not null and v_cc ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$') u
             order by lower(u.email), u.ord) o), '[]'::jsonb);
end $$;
revoke all on function public.invoice_recipient_options(uuid, bigint) from public, anon, authenticated;

create or replace function public.invoice_recipients(p_client uuid, p_contact bigint)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  rcp jsonb;
begin
  if (public.ops_me()).id is null or not public.allowed('clients.billing', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if p_client is null or not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  rcp := public.invoice_recipient_for(p_client, p_contact);
  return jsonb_build_object('ok', true, 'to', nullif(btrim(coalesce(rcp->>'email', '')), ''),
    'cc', nullif(btrim(coalesce(rcp->>'cc', '')), ''), 'options', public.invoice_recipient_options(p_client, p_contact));
end $$;
revoke all on function public.invoice_recipients(uuid, bigint) from public, anon;
grant execute on function public.invoice_recipients(uuid, bigint) to authenticated;

create or replace function public.invoice_mail_begin(p_purpose text, p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean, p_to text, p_ccs text[])
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members;
  t      public.invoice_email_template;
  v_tpl  public.invoice_send_template;
  rcp    jsonb;
  opts   jsonb;
  pick   jsonb;
  inv    jsonb;
  hours  numeric;
  r      public.invoice_emails;
  v_n    int;
  v_k    int;
  v_m    int;
  v_d    int;
  v_to   text;
  v_cc   text;
  v_who  text;
  v_nm   boolean;
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
  /* The addresses chosen on the sheet: the client's own, nothing typed. */
  if p_to is not null or p_ccs is not null then opts := public.invoice_recipient_options(p_client, p_contact); end if;
  if p_to is not null then
    select x into pick from jsonb_array_elements(opts) x where lower(x->>'email') = lower(btrim(p_to)) limit 1;
    if pick is null then return jsonb_build_object('error', 'bad-recipient'); end if;
    v_to := pick->>'email';
    v_who := coalesce(pick->>'name', 'Sir or Madam');
    v_nm := pick->>'name' is not null;
  else
    v_to := coalesce(rcp->>'email', nullif(btrim(coalesce(p_email, '')), ''));
    v_who := coalesce(rcp->>'name', 'Sir or Madam');
    v_nm := rcp->>'name' is not null;
  end if;
  if v_to is null or v_to !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then return jsonb_build_object('error', 'no-email'); end if;
  if p_ccs is not null then
    select count(*), count(o.e), count(distinct lower(o.e)), count(*) filter (where lower(o.e) = lower(v_to)),
           string_agg(o.e, ', ' order by o.i)
      into v_k, v_m, v_d, v_n, v_cc
      from (select a.i, (select x->>'email' from jsonb_array_elements(opts) x where lower(x->>'email') = lower(btrim(a.v)) limit 1) as e
              from unnest(p_ccs) with ordinality as a (v, i)
             where nullif(btrim(coalesce(a.v, '')), '') is not null) o;
    if v_k > 5 or v_m <> v_k or v_d <> v_m or v_n > 0 then return jsonb_build_object('error', 'bad-copy'); end if;
  else
    v_cc := case when coalesce(p_cc, false) and lower(coalesce(rcp->>'cc', '')) <> lower(v_to) then rcp->>'cc' end;
  end if;
  v_co := coalesce(rcp->>'company', nullif(btrim(coalesce(p_name, '')), ''), 'Client');
  v_n := jsonb_array_length(p_invoices);
  select string_agg(public.invoice_money(s.amt, s.cur), ' and ' order by s.cur) into v_tot
    from (select x->>'currency' as cur, sum((x->>'amount')::numeric) as amt
            from jsonb_array_elements(p_invoices) x group by x->>'currency') s;
  select array_agg(x->>'number' order by o) into v_list from jsonb_array_elements(p_invoices) with ordinality as a (x, o);
  v_nos := case when v_n = 1 then v_list[1]
                else array_to_string(v_list[1:v_n - 1], ', ') || ' and ' || v_list[v_n] end;
  v_vals := jsonb_build_object('contact name', v_who, 'client', v_co, 'invoice no', v_nos, 'count', v_n::text,
    'total', v_tot, 'sign off', case when v_nm then 'Yours sincerely' else 'Yours faithfully' end);
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
  values (p_client, p_contact, v_co, p_invoices, v_to, nullif(v_cc, ''), v_s, v_b, me.id, p_purpose)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', v_to, 'cc', nullif(v_cc, ''),
    'cc_list', coalesce(to_jsonb(string_to_array(nullif(v_cc, ''), ', ')), '[]'::jsonb), 'subject', v_s, 'body', v_b,
    'legal', t.legal, 'disclaimer', t.disclaimer);
end $$;
revoke all on function public.invoice_mail_begin(text, uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean, text, text[]) from public, anon, authenticated;
grant execute on function public.invoice_mail_begin(text, uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean, text, text[]) to service_role;

create or replace function public.invoice_mail_begin(p_purpose text, p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean)
returns jsonb
language sql volatile security definer set search_path = public as $$
  select public.invoice_mail_begin(p_purpose, p_actor, p_client, p_contact, p_name, p_email, p_invoices, p_cc, p_subject, p_body, p_again,
    null::text, null::text[])
$$;
revoke all on function public.invoice_mail_begin(text, uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.invoice_mail_begin(text, uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) to service_role;

-- END OF INVOICE RECIPIENTS CHOSEN

select public.functions_tidy();
