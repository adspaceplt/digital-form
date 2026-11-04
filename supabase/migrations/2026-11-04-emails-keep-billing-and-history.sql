-- ===========================================================================
-- EMAILS KEEP BILLING AND HISTORY WHERE THEY BELONG (2026-11-04)
-- ===========================================================================
-- The audit of 2026-11-04 (1, 4): a New email sent to the client's finance
-- email, or copying it, showed that address in the client's Emails and the
-- Email log to a colleague without Clients: Billing; such an email is now
-- marked (`team_emails.finance`) and read at Billing View alone. The yearly
-- address clean-up of the Activity record took every client and supplier
-- edit holding an address, a contact's change of email included; it now
-- takes the email senders' own lines (emailed to …) alone. The supplier and
-- invoice senders file the recipient by name, as the client documents' do,
-- never the address. Every refusal of each function before stays. Safe to
-- run twice. Rollback: remove the column and run each function from its
-- earlier file (2026-11-04-new-email.sql, 2026-11-04-email-audit-fixes.sql,
-- 2026-11-04-invoices-sent-by-email.sql, the SUPPLIER EMAILS section).
-- ===========================================================================

alter table public.team_emails add column if not exists finance boolean not null default false;
-- An email sent before, to or copying a finance email a client or a billing
-- entity holds, is marked once.
update public.team_emails e set finance = true
 where not e.finance and e.client_id is not null
   and exists (select 1 from (select c.finance_email as f from public.clients c
                              union select b.finance_email from public.billing_entities b) a
                where nullif(btrim(a.f), '') is not null
                  and (lower(e.to_email) = lower(btrim(a.f))
                       or lower(btrim(a.f)) = any (string_to_array(lower(replace(coalesce(e.cc_email, ''), ' ', '')), ','))));

create or replace function public.email_new_begin(p_audience text, p_client uuid, p_supplier uuid, p_template uuid,
  p_to text, p_ccs text[], p_subject text, p_body text, p_attachment text, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  opts  jsonb := '[]'::jsonb;
  pick  jsonb;
  c     public.clients;
  su    public.suppliers;
  v_to  text;
  v_who text;
  v_cc  text;
  v_k   int;
  v_m   int;
  v_d   int;
  v_x   int;
  v_bad int;
  v_s   text;
  v_b   text;
  v_att text := nullif(btrim(regexp_replace(coalesce(p_attachment, ''), '[\\/:*?"<>|[:cntrl:]]+', ' ', 'g')), '');
  v_rep text;
  v_id  uuid;
  v_fin boolean := false;
begin
  if me.id is null or not public.allowed('whatsapp', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_audience is null or p_audience not in ('client', 'supplier', 'other') then return jsonb_build_object('error', 'bad-request'); end if;
  if p_idem is null or p_idem !~ '^[A-Za-z0-9_-]{8,64}$' then return jsonb_build_object('error', 'bad-request'); end if;
  perform pg_advisory_xact_lock(hashtextextended('team-email:' || me.id::text, 0));
  -- The same key again is the same email: its status goes back, so one
  -- never confirmed is not said to have gone (audit 2026-11-04).
  if exists (select 1 from public.team_emails x where x.sent_by = me.id and x.idem = p_idem) then
    return jsonb_build_object('error', 'again',
      'status', (select x.status from public.team_emails x where x.sent_by = me.id and x.idem = p_idem limit 1));
  end if;
  if (select count(*) from public.team_emails x where x.sent_by = me.id and x.created_at > now() - interval '24 hours') >= 100 then
    return jsonb_build_object('error', 'too-many');
  end if;
  if p_audience = 'client' then
    if not public.allowed('clients.contacts', 'view') then return jsonb_build_object('error', 'denied'); end if;
    select * into c from public.clients x where x.id = p_client;
    if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    opts := public.email_client_options(c.id);
  elsif p_audience = 'supplier' then
    if not public.allowed('suppliers', 'view') then return jsonb_build_object('error', 'denied'); end if;
    select * into su from public.suppliers x where x.id = p_supplier;
    if su.id is null then return jsonb_build_object('error', 'not-found'); end if;
    opts := public.email_supplier_options(su.id);
  end if;
  if p_audience = 'other' then
    v_to := lower(btrim(coalesce(p_to, '')));
    if v_to !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' or length(v_to) > 254 then return jsonb_build_object('error', 'bad-email'); end if;
    v_who := 'Sir or Madam';
  else
    select x into pick from jsonb_array_elements(opts) x where lower(x->>'email') = lower(btrim(coalesce(p_to, ''))) limit 1;
    if pick is null then return jsonb_build_object('error', 'bad-recipient'); end if;
    v_to := pick->>'email';
    v_who := coalesce(pick->>'name', 'Sir or Madam');
    v_fin := coalesce((pick->>'finance')::boolean, false);
  end if;
  if p_ccs is not null then
    select count(*), count(o.e), count(distinct lower(o.e)), count(*) filter (where lower(o.e) = lower(v_to)),
           count(*) filter (where o.e is not null and (o.e !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' or length(o.e) > 254)), string_agg(o.e, ', ' order by o.i)
      into v_k, v_m, v_d, v_x, v_bad, v_cc
      from (select a.i, case when p_audience = 'other' then lower(btrim(a.v))
                        else (select x->>'email' from jsonb_array_elements(opts) x where lower(x->>'email') = lower(btrim(a.v)) limit 1) end as e
              from unnest(p_ccs) with ordinality as a (v, i)
             where nullif(btrim(coalesce(a.v, '')), '') is not null) o;
    if v_k > 5 or v_m <> v_k or v_d <> v_m or v_x > 0 or v_bad > 0 then return jsonb_build_object('error', 'bad-copy'); end if;
    -- A copy to the finance email is Billing's to read too (audit 2026-11-04, 1).
    v_fin := v_fin or exists (select 1 from unnest(p_ccs) a (v) join jsonb_array_elements(opts) x on lower(x->>'email') = lower(btrim(a.v))
                               where coalesce((x->>'finance')::boolean, false));
  end if;
  if p_template is not null and not exists (select 1 from public.email_templates x where x.id = p_template) then
    return jsonb_build_object('error', 'bad-template');
  end if;
  v_s := btrim(regexp_replace(public.supplier_email_fill(coalesce(p_subject, ''), jsonb_build_object(
           'contact name', v_who, 'client name', coalesce(c.name, ''), 'company name', coalesce(case when public.allowed('clients.billing', 'view') then nullif(c.legal_name, '') end, c.name, su.name, ''),
           'supplier name', coalesce(su.name, ''), 'sender name', me.name)), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(coalesce(p_body, ''), jsonb_build_object(
           'contact name', v_who, 'client name', coalesce(c.name, ''), 'company name', coalesce(case when public.allowed('clients.billing', 'view') then nullif(c.legal_name, '') end, c.name, su.name, ''),
           'supplier name', coalesce(su.name, ''), 'sender name', me.name)), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_att is not null and (length(v_att) > 200 or v_att !~* '\.(pdf|png|jpe?g|webp|docx?|xlsx?|pptx?|csv)$') then
    return jsonb_build_object('error', 'bad-file');
  end if;
  v_rep := case when coalesce(btrim(me.email), '') ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then btrim(me.email) end;
  insert into public.team_emails (audience, client_id, supplier_id, template_id, to_email, to_name, cc_email, reply_to, subject, body,
                                  attachment, idem, sent_by, finance)
  values (p_audience, c.id, su.id, p_template, v_to, case when v_who <> 'Sir or Madam' then v_who end, nullif(v_cc, ''), v_rep,
          v_s, v_b, v_att, p_idem, me.id, v_fin)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', v_to, 'cc', nullif(v_cc, ''),
    'cc_list', coalesce(to_jsonb(string_to_array(nullif(v_cc, ''), ', ')), '[]'::jsonb), 'reply_to', v_rep,
    'subject', v_s, 'body', v_b, 'audience', p_audience);
end $$;
revoke all on function public.email_new_begin(text, uuid, uuid, uuid, text, text[], text, text, text, text) from public, anon;
grant execute on function public.email_new_begin(text, uuid, uuid, uuid, text, text[], text, text, text, text) to authenticated;

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
          select 'manual', e.id, 'message', e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, e.supplier_id, s.name, s.code,
                 e.attachment, e.to_name
            from public.team_emails e
            left join public.clients c on c.id = e.client_id
            left join public.suppliers s on s.id = e.supplier_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and (case when e.client_id is not null then public.allowed('clients.contacts', 'view') and public.client_seen(e.client_id, 'view')
                       when e.supplier_id is not null then v_sup else true end)
             and (not e.finance or v_bill)
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

create or replace function public.team_emails_of(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('clients.contacts', 'view') or not public.client_seen(p_client, 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    /* In the Email log's own shape, so its sheet opens one as it is. */
    select jsonb_agg(jsonb_build_object('source', 'manual', 'id', e.id, 'kind', 'message', 'to_email', e.to_email,
             'to_name', e.to_name, 'cc_email', e.cc_email, 'subject', e.subject, 'body', e.body, 'reference', e.attachment,
             'status', e.status, 'error', e.error, 'created_at', e.created_at, 'sent_at', e.sent_at,
             'delivered_at', e.delivered_at, 'opened_at', e.opened_at, 'bounced_at', e.bounced_at,
             'sent_by', m.name, 'client_id', e.client_id) order by e.created_at desc)
      from public.team_emails e
      left join public.team_members m on m.id = e.sent_by
     where e.client_id = p_client and (not e.finance or public.allowed('clients.billing', 'view'))), '[]'::jsonb));
end $$;
revoke all on function public.team_emails_of(uuid) from public, anon;
grant execute on function public.team_emails_of(uuid) to authenticated;

create or replace function public.supplier_email_done(p_id uuid, p_status text, p_provider text, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  e  public.supplier_emails;
  s  public.suppliers;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_status not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into e from public.supplier_emails x where x.id = p_id and x.sent_by = me.id and x.status = 'sending' for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.supplier_emails x set status = p_status, provider_id = nullif(p_provider, ''),
    error = left(nullif(p_error, ''), 480), sent_at = case when p_status = 'sent' then now() end
   where x.id = p_id;
  select * into s from public.suppliers x where x.id = e.supplier_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'supplier.edited', coalesce(s.name, s.code, 'Supplier'),
          coalesce(s.code, '') || ' · ' ||
          case e.purpose when 'approved' then 'Supplier approved'
            else coalesce((select d.kind || ' ' || d.serial from public.documents d where d.id = e.document_id), 'Document') end ||
          case p_status when 'sent' then ' emailed to ' when 'unknown' then ' emailed, not confirmed, to ' else ' not emailed to ' end ||
          case when lower(btrim(coalesce(s.email, ''))) = lower(btrim(e.to_email)) then coalesce(nullif(btrim(s.contact_name), ''), 'the supplier')
               when lower(btrim(coalesce(s.finance_email, ''))) = lower(btrim(e.to_email)) then 'the finance email' else 'the supplier' end ||
          case when nullif(e.cc_email, '') is not null then ' with a copy to the finance email' else '' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_email_done(uuid, text, text, text) from public, anon;
grant execute on function public.supplier_email_done(uuid, text, text, text) to authenticated;

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
          coalesce((select nullif(public.contact_named(k.salutation, k.name), '') from public.client_contacts k
                     where k.client_id = e.client_id and lower(btrim(coalesce(k.email, ''))) = lower(btrim(e.to_email))
                     order by k.archived_at nulls first limit 1),
                   case when exists (select 1 from public.clients c where c.id = e.client_id and lower(btrim(coalesce(c.finance_email, ''))) = lower(btrim(e.to_email)))
                        then 'the finance email' else 'the client' end) ||
          case when nullif(e.cc_email, '') is not null then ', copied to ' ||
            case when array_length(string_to_array(e.cc_email, ','), 1) = 1 then '1 contact' else array_length(string_to_array(e.cc_email, ','), 1) || ' contacts' end
          else '' end || ' · ' ||
          (select string_agg(x->>'number', ', ') from jsonb_array_elements(e.invoices) x));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.invoice_email_done(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.invoice_email_done(uuid, text, text, text) to service_role;

create or replace function public.mail_retention()
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  n integer := 0;
  k integer;
begin
  update public.team_emails x set to_email = '', to_name = null, cc_email = null, reply_to = null, body = ''
   where x.created_at < now() - interval '12 months' and x.status <> 'sending' and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  update public.client_emails x set to_email = '', cc_email = null, reply_to = null, body = ''
   where x.created_at < now() - interval '12 months' and x.status <> 'sending' and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  update public.supplier_emails x set to_email = '', cc_email = null, body = ''
   where x.created_at < now() - interval '12 months' and x.status <> 'sending' and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  update public.invoice_emails x set to_email = '', cc_email = null, body = ''
   where x.created_at < now() - interval '12 months' and x.status <> 'sending' and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  -- A signing code's details: an unused one 30 days after it expired, a
  -- used one a year on (the signature itself is kept on its quotation).
  update public.quote_sign_codes x set email = '', payload = '{}'::jsonb
   where (x.email <> '' or x.payload <> '{}'::jsonb)
     and ((x.used_at is null and x.expires_at < now() - interval '30 days') or x.used_at < now() - interval '12 months');
  get diagnostics k = row_count; n := n + k;
  -- An address an email filed in the Activity record before 2026-11-04,
  -- deleted on the email's own clock (audit 2026-11-04): the senders' own
  -- lines alone (emailed to …), never a contact or supplier edit's from
  -- and to, which the record keeps its three years (audit 2026-11-04, 4).
  update public.activity_log x
     set detail = regexp_replace(x.detail, '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+', 'a deleted address', 'g')
   where x.action in ('email.sent', 'client.edited', 'supplier.edited') and x.created_at < now() - interval '12 months'
     and (x.action = 'email.sent' or x.detail ~ '(^| )(not )?emailed(, not confirmed,)? to ')
     and x.detail ~ '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_retention() from public, anon, authenticated;

-- END OF EMAILS KEEP BILLING AND HISTORY WHERE THEY BELONG -------------------

select public.functions_tidy();
