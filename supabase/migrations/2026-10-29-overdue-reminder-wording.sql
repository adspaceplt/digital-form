-- ===========================================================================
-- OVERDUE REMINDER WORDING — the reminder reads as a creditor writes it, and
-- its fine print is every email's (2026-10-29)
-- ===========================================================================
-- WHY (the review of the Overdue invoices section, 2026-10-28; the user,
-- 2026-10-29: "1-5"): "payment of {total} for {client}" read as if ADspace
-- owed the money; a company with no named contact was greeted by its
-- registered name above "Yours faithfully"; the legal note spoke of overdue
-- interest that no agreement states; the disclaimer differed from the
-- confidentiality line every other portal email carries.
--
-- WHAT IT CHANGES
--   * `invoice_email_template`: the message reads "payment of {total} due
--     from {client}", the legal note ends "settled in accordance with the
--     agreed payment terms", the disclaimer is the standing confidentiality
--     line (_shared/mail.ts). Each is changed only where it still holds the
--     seed's words: wording a colleague changed at Business settings is
--     left as it is (the preview file reports which).
--   * `invoice_email_begin` (restated whole from OVERDUE INVOICE REMINDERS,
--     every refusal kept): {contact name} with no named contact reads
--     "Sir or Madam", never the company.
--
-- ORDER: the pages (the preview fills the same greeting), then this file
-- (connector). An open tab before the pages greets the company in its
-- preview while the email greets Sir or Madam. Safe to run twice.
--
-- ROLLBACK: invoice_email_begin from OVERDUE INVOICE REMINDERS again, and the
-- three seeds written back where they hold this file's words.
-- ===========================================================================

update public.invoice_email_template x set body =
  E'Dear {contact name},\n\nThis is a reminder that payment of {total} due from {client} is now overdue.\n\n{invoices}\n\nWe would be grateful if payment could be arranged at your earliest convenience. If payment has already been made, please disregard this email.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance',
  updated_at = now()
 where x.id = 1 and x.body =
  E'Dear {contact name},\n\nThis is a reminder that payment of {total} for {client} is now overdue.\n\n{invoices}\n\nWe would be grateful if payment could be arranged at your earliest convenience. If payment has already been made, please disregard this email.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance';
update public.invoice_email_template x set legal =
  'Legal note: All services rendered will be invoiced accordingly unless a written cancellation is provided and acknowledged in advance. All invoices are to be settled in accordance with the agreed payment terms.',
  updated_at = now()
 where x.id = 1 and x.legal =
  'Legal note: All services rendered will be invoiced accordingly unless a written cancellation is provided and acknowledged in advance. All invoices must be settled promptly to avoid overdue interest charges.';
update public.invoice_email_template x set disclaimer =
  'This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.',
  updated_at = now()
 where x.id = 1 and x.disclaimer =
  'This email and any attachment are private and confidential and intended solely for the addressee. If you have received it in error, please notify einvoice@adspacestudios.com and delete it. Any use, copying or disclosure by anyone else is not permitted.';

create or replace function public.invoice_email_begin(p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members;
  t      public.invoice_email_template;
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
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-request'); end if;
  if jsonb_typeof(p_invoices) <> 'array' or jsonb_array_length(p_invoices) < 1 or jsonb_array_length(p_invoices) > 50 then
    return jsonb_build_object('error', 'bad-invoices');
  end if;
  for inv in select value from jsonb_array_elements(p_invoices) loop
    if coalesce(inv->>'number', '') !~ '^[A-Za-z0-9/._ -]{1,40}$' or coalesce(inv->>'currency', '') !~ '^[A-Z]{3}$'
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
     where x.bukku_contact = p_contact and x.status <> 'failed' and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
    if r.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', r.created_at, 'to', r.to_email,
        'by', (select m.name from public.team_members m where m.id = r.sent_by)));
    end if;
  end if;
  rcp := case when p_client is null then null else public.invoice_recipient(p_client) end;
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
  select * into t from public.invoice_email_template x where x.id = 1;
  v_s := btrim(regexp_replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_subject, '')), ''),
           case when v_n = 1 then t.subject_one else t.subject_many end), v_vals), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_body, '')), ''), t.body), v_vals), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  insert into public.invoice_emails (client_id, bukku_contact, client_name, invoices, to_email, cc_email, subject, body, sent_by)
  values (p_client, p_contact, v_co, p_invoices, v_to, v_cc, v_s, v_b, me.id)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', v_to, 'cc', v_cc, 'subject', v_s, 'body', v_b,
    'legal', t.legal, 'disclaimer', t.disclaimer);
end $$;
revoke all on function public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) to service_role;

-- END OF OVERDUE REMINDER WORDING --------------------------------------------

select public.functions_tidy();
