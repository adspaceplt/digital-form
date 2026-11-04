-- ===========================================================================
-- EMAIL AUDIT FIXES — billing behind its part, no addresses kept past their
-- time (2026-11-04)
-- ===========================================================================
-- WHY (the audit of 2026-11-04; the user: "fix all"): New email and Send by
-- email offered a client's finance email and filled its registered name for
-- a colleague without Clients: Billing; New email offered an entity's shared
-- billing contact, another brand's, to a colleague outside that brand's
-- scope; every email filed its addresses in the Activity record, kept three
-- years where the email keeps them one; a signing code kept the signer's
-- details and signature for good; an entity removed from a brand still
-- answered with that brand's contact for the others; the Billing pane named
-- a client outside the reader's scope beside its contact; a key sent again
-- read "already sent" where the email was never confirmed; and Resend's
-- email.failed was not taken.
--
-- WHAT CHANGED
--   * `email_client_options(p_client)` (internal): a client's own live
--     contacts and, at Clients: Billing View, its finance email; read by
--     `email_recipients` and `email_new_begin`.
--   * `email_new_begin`, `client_email_prepare`: {company name} the
--     registered name at Billing View alone, else the brand; the prepare's
--     finance copy at Billing View alone. A key again answers `again` with
--     its email's status.
--   * `email_new_done`, `client_email_done`: filed by the recipient's name
--     and the number of copies, never an address.
--   * `mail_retention`: a signing code's email and details cleared 30 days
--     after an unused code expired or a year after one was used; an address
--     an email filed in the Activity record before today replaced by
--     "a deleted address" a year on.
--   * `entity_contact`: the shared contact only while its brand is billed by
--     the entity. `billing_entity_json`: a contact's client named only where
--     the reader sees it.
--   * `supplier_email_status`: Resend's email.failed is Failed.
--
-- ORDER: this file (connector), then `supplier-mail` (a status that arrives
-- before its email is closed is asked again), then the pages. Safe to run
-- twice.
--
-- ROLLBACK: run NEW EMAIL's, CLIENT DOCUMENT EMAILS', ENTITY CONTACT PER
-- BRAND's and EMAIL LOG's functions again; the helper is then unused.
-- ===========================================================================

/* A client's addresses for New email: its own live contacts holding an
   email, and its finance email at Clients: Billing View alone, in the
   invoice email's order. Never another brand's contact (audit 2026-11-04).
   Internal. */
create or replace function public.email_client_options(p_client uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(o.x order by o.n), '[]'::jsonb)
    from jsonb_array_elements(public.invoice_recipient_options(p_client, null)) with ordinality as o (x, n)
   where case when coalesce((o.x ->> 'finance')::boolean, false) then public.allowed('clients.billing', 'view')
              else exists (select 1 from public.client_contacts k
                            where k.client_id = p_client and k.archived_at is null
                              and lower(btrim(coalesce(k.email, ''))) = lower(o.x ->> 'email')) end
$$;
revoke all on function public.email_client_options(uuid) from public, anon, authenticated;

create or replace function public.email_recipients(p_client uuid, p_supplier uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('whatsapp', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_client is not null then
    if not public.allowed('clients.contacts', 'view') then return jsonb_build_object('error', 'denied'); end if;
    if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    return jsonb_build_object('ok', true, 'options', public.email_client_options(p_client));
  end if;
  if p_supplier is not null then
    if not public.allowed('suppliers', 'view') then return jsonb_build_object('error', 'denied'); end if;
    return jsonb_build_object('ok', true, 'options', public.email_supplier_options(p_supplier));
  end if;
  return jsonb_build_object('error', 'bad-request');
end $$;
revoke all on function public.email_recipients(uuid, uuid) from public, anon;
grant execute on function public.email_recipients(uuid, uuid) to authenticated;

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
                                  attachment, idem, sent_by)
  values (p_audience, c.id, su.id, p_template, v_to, case when v_who <> 'Sir or Madam' then v_who end, nullif(v_cc, ''), v_rep,
          v_s, v_b, v_att, p_idem, me.id)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', v_to, 'cc', nullif(v_cc, ''),
    'cc_list', coalesce(to_jsonb(string_to_array(nullif(v_cc, ''), ', ')), '[]'::jsonb), 'reply_to', v_rep,
    'subject', v_s, 'body', v_b, 'audience', p_audience);
end $$;
revoke all on function public.email_new_begin(text, uuid, uuid, uuid, text, text[], text, text, text, text) from public, anon;
grant execute on function public.email_new_begin(text, uuid, uuid, uuid, text, text[], text, text, text, text) to authenticated;

create or replace function public.email_new_done(p_id uuid, p_status text, p_provider text, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  e  public.team_emails;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_status not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into e from public.team_emails x where x.id = p_id and x.sent_by = me.id and x.status = 'sending' for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.team_emails x set status = p_status, provider_id = nullif(p_provider, ''),
    error = left(nullif(p_error, ''), 480), sent_at = case when p_status = 'sent' then now() end
   where x.id = p_id;
  -- Filed by whom it went to, never an address: the record keeps three
  -- years, an email's addresses one (audit 2026-11-04).
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'email.sent',
          coalesce((select c.name from public.clients c where c.id = e.client_id), (select s.name from public.suppliers s where s.id = e.supplier_id),
                   'Other recipient'),
          e.subject || case p_status when 'sent' then ' · emailed to ' when 'unknown' then ' · emailed, not confirmed, to ' else ' · not emailed to ' end ||
          coalesce(e.to_name, case e.audience when 'client' then 'the client' when 'supplier' then 'the supplier' else 'an address outside the portal' end) ||
          case when nullif(e.cc_email, '') is null then ''
               when array_length(string_to_array(e.cc_email, ', '), 1) = 1 then ', with a copy to 1 other'
               else ', with a copy to ' || array_length(string_to_array(e.cc_email, ', '), 1) || ' others' end ||
          coalesce(' · ' || e.attachment, ''));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.email_new_done(uuid, text, text, text) from public, anon;
grant execute on function public.email_new_done(uuid, text, text, text) to authenticated;

create or replace function public.client_email_prepare(p_kind text, p_ref uuid, p_contact uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  c      public.clients;
  q      public.quotations;
  o      public.client_documents;
  d      public.documents;
  k      public.client_contacts;
  t      public.client_email_templates;
  v_cid  uuid;
  v_ref  text;
  v_tit  text;
  v_day  date;
  v_val  date;
  v      jsonb;
  ppl    jsonb;
  hours  numeric;
  r      public.client_emails;
  v_cc   text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_kind not in ('quotation', 'offer', 'letter') then return jsonb_build_object('error', 'bad-request'); end if;
  if not public.client_email_may(p_kind, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(public.app_setting('client_email_on', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) <> 1 then
    return jsonb_build_object('error', 'email-off');
  end if;
  if p_kind = 'quotation' then
    select * into q from public.quotations x where x.id = p_ref;
    if q.id is null or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
    if q.status = 'not_proceeding' then return jsonb_build_object('error', 'void'); end if;
    if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'unreleased'); end if;
    if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
    v_cid := q.client_id; v_ref := q.ref; v_tit := 'Quotation';
    v_day := (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date; v_val := q.valid_until;
  elsif p_kind = 'offer' then
    select * into o from public.client_documents x where x.id = p_ref;
    if o.id is null or o.kind not in ('offer', 'intent', 'cover') then return jsonb_build_object('error', 'not-found'); end if;
    if o.voided_at is not null or o.superseded_by is not null then return jsonb_build_object('error', 'void'); end if;
    v_cid := o.client_id; v_ref := o.number; v_tit := 'Letter of Offer'; v_day := o.issued_at;
  else
    select * into d from public.documents x where x.id = p_ref and x.family = 'client';
    if d.id is null or d.client_id is null then return jsonb_build_object('error', 'not-found'); end if;
    if d.voided_at is not null then return jsonb_build_object('error', 'void'); end if;
    if d.source <> 'portal' then return jsonb_build_object('error', 'no-file'); end if;
    v_cid := d.client_id; v_ref := d.serial; v_tit := coalesce(nullif(d.kind, ''), 'Letter'); v_day := d.issued_at;
  end if;
  select * into c from public.clients x where x.id = v_cid;
  if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.client_email_templates x where x.kind = p_kind;
  if t.kind is null then return jsonb_build_object('error', 'needs-update'); end if;

  /* The client's contacts holding an email, the billing contact first, then
     the primary, then by name. */
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', public.contact_named(x.salutation, x.name),
           'email', btrim(x.email), 'role', x.role, 'billing', coalesce(x.id = c.bill_contact_id, false), 'primary', x.is_primary)
           order by (x.id = c.bill_contact_id) desc nulls last, x.is_primary desc, x.name), '[]'::jsonb)
    into ppl
    from public.client_contacts x
   where x.client_id = c.id and x.archived_at is null and coalesce(btrim(x.email), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
  if jsonb_array_length(ppl) = 0 then return jsonb_build_object('error', 'no-email'); end if;
  if p_contact is not null then
    select * into k from public.client_contacts x
     where x.id = p_contact and x.client_id = c.id and x.archived_at is null
       and coalesce(btrim(x.email), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
    if k.id is null then return jsonb_build_object('error', 'bad-contact'); end if;
  else
    select * into k from public.client_contacts x where x.id = (ppl->0->>'id')::uuid;
  end if;
  -- The finance email and registered name are Billing's (audit 2026-11-04).
  v_cc := case when public.allowed('clients.billing', 'view') then nullif(btrim(coalesce(c.finance_email, '')), '') end;
  if v_cc is not null and (lower(v_cc) = lower(btrim(k.email)) or v_cc !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then v_cc := null; end if;

  v := jsonb_build_object(
    'contact name', public.contact_named(k.salutation, k.name),
    'client name', c.name,
    'company name', coalesce(case when public.allowed('clients.billing', 'view') then nullif(c.legal_name, '') end, c.name),
    'document title', v_tit, 'document reference', v_ref,
    'document date', case when v_day is null then '' else to_char(v_day, 'FMDD FMMonth YYYY') end,
    'valid until', case when v_val is null then '' else to_char(v_val, 'FMDD FMMonth YYYY') end,
    'sender name', coalesce(me.name, ''));
  hours := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  if hours > 0 then
    select * into r from public.client_emails x
     where x.kind = p_kind and x.ref_id = p_ref and x.status <> 'failed'
       and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
  end if;
  return jsonb_build_object('ok', true,
    'client_id', c.id, 'client', c.name,
    'contacts', ppl,
    'to', jsonb_build_object('id', k.id, 'name', public.contact_named(k.salutation, k.name), 'email', btrim(k.email)),
    'cc', v_cc,
    'reply_to', nullif(btrim(coalesce(me.email, '')), ''),
    'values', v,
    'subject', public.supplier_email_fill(t.subject, v),
    'body', public.supplier_email_fill(t.body, v),
    'document', jsonb_build_object('id', p_ref, 'kind', p_kind, 'serial', v_ref, 'title', v_tit),
    'recent', case when r.id is null then null else jsonb_build_object('at', r.created_at, 'to', r.to_email,
      'by', (select m.name from public.team_members m where m.id = r.sent_by)) end);
end $$;
revoke all on function public.client_email_prepare(text, uuid, uuid) from public, anon;
grant execute on function public.client_email_prepare(text, uuid, uuid) to authenticated;

create or replace function public.client_email_done(p_id uuid, p_status text, p_provider text, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  e  public.client_emails;
  c  public.clients;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_status not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into e from public.client_emails x where x.id = p_id and x.sent_by = me.id and x.status = 'sending' for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.client_emails x set status = p_status, provider_id = nullif(p_provider, ''),
    error = left(nullif(p_error, ''), 480), sent_at = case when p_status = 'sent' then now() end
   where x.id = p_id;
  select * into c from public.clients x where x.id = e.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', coalesce(c.name, 'Client'),
          case e.kind when 'quotation' then 'Quotation ' when 'offer' then 'Letter of Offer ' else '' end || e.reference ||
          case p_status when 'sent' then ' emailed to ' when 'unknown' then ' emailed, not confirmed, to ' else ' not emailed to ' end ||
          coalesce((select nullif(public.contact_named(k.salutation, k.name), '') from public.client_contacts k
                     where k.client_id = e.client_id and lower(btrim(coalesce(k.email, ''))) = lower(btrim(e.to_email))
                     order by k.archived_at nulls first limit 1), 'the client') ||
          case when nullif(e.cc_email, '') is not null then ' with a copy to the finance email' else '' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_email_done(uuid, text, text, text) from public, anon;
grant execute on function public.client_email_done(uuid, text, text, text) to authenticated;

create or replace function public.entity_contact(p_entity uuid, p_client uuid)
returns public.client_contacts
language sql stable security definer set search_path = public as $$
  select k.* from public.client_contacts k
   where p_entity is not null and k.archived_at is null
     and (k.id = (select ce.bill_contact_id from public.client_entities ce
                   where ce.entity_id = p_entity and ce.client_id = p_client)
          -- The shared contact only while its brand is still billed by the
          -- entity (audit 2026-11-04).
          or (k.id = (select e.bill_contact_id from public.billing_entities e where e.id = p_entity)
              and exists (select 1 from public.client_entities ce2 where ce2.entity_id = p_entity and ce2.client_id = k.client_id))
          or (k.client_id = p_client and k.is_primary))
   order by (k.id is not distinct from (select ce.bill_contact_id from public.client_entities ce
                                         where ce.entity_id = p_entity and ce.client_id = p_client)) desc,
            (k.id is not distinct from (select e.bill_contact_id from public.billing_entities e where e.id = p_entity)) desc,
            k.name
   limit 1
$$;
revoke all on function public.entity_contact(uuid, uuid) from public, anon, authenticated;

create or replace function public.billing_entity_json(p_entity uuid, p_client uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id,
    'main', coalesce((select ce.is_main from public.client_entities ce
                       where ce.entity_id = e.id and ce.client_id = p_client), false),
    'legal_name', e.legal_name, 'company_no', e.company_no, 'company_no_old', e.company_no_old,
    'tin', e.tin, 'sst_no', e.sst_no, 'bill_contact_id', e.bill_contact_id,
    'bill_contact', (select jsonb_build_object('name', k.name, 'salutation', k.salutation,
                                               'client_id', k.client_id,
                                               'client', case when public.client_seen(k.client_id, 'view') then (select x.name from public.clients x where x.id = k.client_id) end)
                       from public.client_contacts k where k.id = e.bill_contact_id and k.archived_at is null),
    'own_contact_id', (select ce.bill_contact_id from public.client_entities ce
                        where ce.entity_id = e.id and ce.client_id = p_client),
    'contact', (select jsonb_build_object('id', k.id, 'name', k.name, 'salutation', k.salutation,
                                          'client_id', k.client_id,
                                          'client', case when public.client_seen(k.client_id, 'view') then (select x.name from public.clients x where x.id = k.client_id) end)
                  from public.entity_contact(e.id, p_client) k where p_client is not null and k.id is not null),
    'finance_email', e.finance_email, 'billing_address', e.billing_address, 'updated_at', e.updated_at,
    'missing', to_jsonb(array_remove(array[
        case when coalesce(btrim(e.legal_name), '') = '' then 'legal_name' end,
        case when coalesce(btrim(e.company_no), '') = '' then 'company_no' end,
        case when coalesce(btrim(e.billing_address), '') = '' then 'billing_address' end], null)),
    'brands', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'slug', x.slug,
                                                            'code', x.client_code) order by x.name)
                          from public.client_entities ce join public.clients x on x.id = ce.client_id
                         where ce.entity_id = e.id and ce.client_id is distinct from p_client
                           and public.client_seen(x.id, 'view')), '[]'::jsonb),
    'hidden', (select count(*) from public.client_entities ce
                where ce.entity_id = e.id and ce.client_id is distinct from p_client
                  and not public.client_seen(ce.client_id, 'view')))
    from public.billing_entities e where e.id = p_entity
$$;
revoke all on function public.billing_entity_json(uuid, uuid) from public, anon, authenticated;

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
  -- deleted on the email's own clock (audit 2026-11-04).
  update public.activity_log x
     set detail = regexp_replace(x.detail, '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+', 'a deleted address', 'g')
   where x.action in ('email.sent', 'client.edited', 'supplier.edited') and x.created_at < now() - interval '12 months'
     and x.detail ~ '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_retention() from public, anon, authenticated;

create or replace function public.supplier_email_status(p_provider text, p_event text, p_at timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e    public.supplier_emails;
  i    public.invoice_emails;
  ce   public.client_emails;
  te   public.team_emails;
  rank constant jsonb := '{"sending":0,"unknown":1,"sent":1,"failed":4,"delivered":2,"opened":3,"complained":4,"bounced":4}';
  st   text := case p_event when 'email.delivered' then 'delivered' when 'email.opened' then 'opened'
                when 'email.clicked' then 'opened' when 'email.bounced' then 'bounced'
                when 'email.complained' then 'complained' when 'email.sent' then 'sent'
                when 'email.failed' then 'failed' end;
begin
  if st is null then return jsonb_build_object('ok', true, 'ignored', true); end if;
  select * into e from public.supplier_emails x where x.provider_id = p_provider for update;
  if e.id is not null then
    update public.supplier_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = e.id;
    return jsonb_build_object('ok', true);
  end if;
  select * into ce from public.client_emails x where x.provider_id = p_provider for update;
  if ce.id is not null then
    update public.client_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = ce.id;
    return jsonb_build_object('ok', true);
  end if;
  select * into te from public.team_emails x where x.provider_id = p_provider for update;
  if te.id is not null then
    update public.team_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = te.id;
    return jsonb_build_object('ok', true);
  end if;
  select * into i from public.invoice_emails x where x.provider_id = p_provider for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.invoice_emails x set
    status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
    sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
    delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
    opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
    bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
   where x.id = i.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_email_status(text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.supplier_email_status(text, text, timestamptz) to service_role;

-- END OF EMAIL AUDIT FIXES -------------------------------------------------

select public.functions_tidy();
