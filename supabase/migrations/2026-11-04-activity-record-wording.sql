-- ===========================================================================
-- ACTIVITY RECORD WORDING — the lines these functions file read as the
-- console reads (2026-11-04)
-- ===========================================================================
-- WHY (the copy review of releases #908 to #913; the user: "Check since last
-- sessions tone etc."): the Activity record read "already held" and "main"
-- for a billing entity, "emailed, not confirmed, to", "an address outside
-- the portal", "a copy to 1 other", "a deleted address", the quotation
-- review's own field names beside Billing's, "Bukku holds the billing
-- details", and a website lead filed under Website where every other line
-- of the quotation website reads Quotation website.
--
-- WHAT IT CHANGES (each function restated whole from its latest section,
-- every refusal, grant and revoke kept; only the words filed change):
--   * client_entity_add: Billing entity added (already in the portal),
--     · primary.
--   * supplier_email_done, invoice_email_done, email_new_done,
--     client_email_done: emailed (not confirmed) to; a New email to Other
--     reads another address, a copy to n other addresses.
--   * mail_retention: an address past its year reads (address deleted).
--   * quotation_submit: a corrected field is named as Billing names it.
--   * quotation_review: Billing not changed, as Bukku keeps this client's
--     billing details.
--   * quote_website_create: filed under Quotation website.
--
-- ORDER: this file alone (connector), any time; no page reads these words.
-- Lines filed before keep their words. Safe to run twice.
--
-- ROLLBACK: each function from the section before (BILLING AUDIT FIXES,
-- SUPPLIER EMAILS, INVOICES SENT BY EMAIL, EMAIL AUDIT FIXES, QUOTATION
-- AUDIT FIXES, INDUSTRIES).
-- ===========================================================================

create or replace function public.client_entity_add(p_client uuid, p_entity uuid default null, p_values jsonb default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_name  text;
  v_vals  jsonb;
  v_ent   uuid := p_entity;
  v_main  boolean;
  v_held  public.billing_entities;
begin
  if not public.billing_entity_may(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  if v_name is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_ent is not null then
    if not exists (select 1 from public.billing_entities e where e.id = v_ent) then
      return jsonb_build_object('error', 'not-found');
    end if;
    if not public.billing_entity_reached(v_ent) then
      return jsonb_build_object('error', 'denied');
    end if;
    if exists (select 1 from public.client_entities ce where ce.entity_id = v_ent and ce.client_id = p_client) then
      return jsonb_build_object('error', 'taken');
    end if;
  else
    v_vals := public.billing_entity_clean(p_values);
    if v_vals ? 'error' then return v_vals; end if;
    if v_vals ->> 'bill_contact_id' is not null and not exists (
         select 1 from public.client_contacts k
          where k.id = (v_vals ->> 'bill_contact_id')::uuid and k.client_id = p_client and k.archived_at is null) then
      return jsonb_build_object('error', 'bad-contact');
    end if;
    if length(regexp_replace(coalesce(v_vals ->> 'company_no', ''), '\D', '', 'g')) > 0 then
    -- One BRN is checked and taken at a time across every client, so two
    -- presses at once never make it twice (audit 2026-11-04).
    perform pg_advisory_xact_lock(hashtextextended('entity-brn:' || regexp_replace(v_vals ->> 'company_no', '\D', '', 'g'), 0));
      select * into v_held from public.billing_entities e
       where regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = regexp_replace(v_vals ->> 'company_no', '\D', '', 'g')
       order by e.created_at limit 1;
      if v_held.id is not null then
        return jsonb_build_object('error', 'brn-taken', 'entity',
                                  jsonb_build_object('id', v_held.id, 'legal_name', v_held.legal_name));
      end if;
    end if;
    insert into public.billing_entities (legal_name, company_no, company_no_old, tin, sst_no, bill_contact_id,
                                         finance_email, billing_address, created_by)
    values (v_vals ->> 'legal_name', v_vals ->> 'company_no', v_vals ->> 'company_no_old', v_vals ->> 'tin',
            v_vals ->> 'sst_no', (v_vals ->> 'bill_contact_id')::uuid, v_vals ->> 'finance_email',
            v_vals ->> 'billing_address', me.id)
    returning id into v_ent;
  end if;
  -- One first entity at a time for a client (audit 2026-10-30).
  perform 1 from public.clients x where x.id = p_client for update;
  v_main := not exists (select 1 from public.client_entities ce where ce.client_id = p_client and ce.is_main);
  insert into public.client_entities (client_id, entity_id, is_main, added_by) values (p_client, v_ent, v_main, me.id);
  update public.billing_entities e set orphan_of = null where e.id = v_ent and e.orphan_of is not null;
  if v_main then perform public.billing_entity_put(v_ent, p_client); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name,
          case when p_entity is null then 'Billing entity added' else 'Billing entity added (already in the portal)' end
          || case when v_main then ' · primary' else '' end);
  return jsonb_build_object('ok', true, 'id', v_ent, 'main', v_main);
end $$;
revoke all on function public.client_entity_add(uuid, uuid, jsonb) from public, anon;
grant execute on function public.client_entity_add(uuid, uuid, jsonb) to authenticated;

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
          case p_status when 'sent' then ' emailed to ' when 'unknown' then ' emailed (not confirmed) to ' else ' not emailed to ' end ||
          e.to_email || coalesce(', cc ' || e.cc_email, ''));
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
          case p_status when 'sent' then 'emailed to ' when 'unknown' then 'emailed (not confirmed) to ' else 'not emailed to ' end ||
          e.to_email || coalesce(', cc ' || e.cc_email, '') || ' · ' ||
          (select string_agg(x->>'number', ', ') from jsonb_array_elements(e.invoices) x));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.invoice_email_done(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.invoice_email_done(uuid, text, text, text) to service_role;

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
          e.subject || case p_status when 'sent' then ' · emailed to ' when 'unknown' then ' · emailed (not confirmed) to ' else ' · not emailed to ' end ||
          coalesce(e.to_name, case e.audience when 'client' then 'the client' when 'supplier' then 'the supplier' else 'another address' end) ||
          case when nullif(e.cc_email, '') is null then ''
               when array_length(string_to_array(e.cc_email, ', '), 1) = 1 then ', with a copy to 1 other address'
               else ', with a copy to ' || array_length(string_to_array(e.cc_email, ', '), 1) || ' other addresses' end ||
          coalesce(' · ' || e.attachment, ''));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.email_new_done(uuid, text, text, text) from public, anon;
grant execute on function public.email_new_done(uuid, text, text, text) to authenticated;

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
          case p_status when 'sent' then ' emailed to ' when 'unknown' then ' emailed (not confirmed) to ' else ' not emailed to ' end ||
          coalesce((select nullif(public.contact_named(k.salutation, k.name), '') from public.client_contacts k
                     where k.client_id = e.client_id and lower(btrim(coalesce(k.email, ''))) = lower(btrim(e.to_email))
                     order by k.archived_at nulls first limit 1), 'the client') ||
          case when nullif(e.cc_email, '') is not null then ' with a copy to the finance email' else '' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_email_done(uuid, text, text, text) from public, anon;
grant execute on function public.client_email_done(uuid, text, text, text) to authenticated;

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
     set detail = regexp_replace(x.detail, '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+', '(address deleted)', 'g')
   where x.action in ('email.sent', 'client.edited', 'supplier.edited') and x.created_at < now() - interval '12 months'
     and x.detail ~ '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_retention() from public, anon, authenticated;

create or replace function public.quotation_submit(p_id uuid, p_reviewer uuid, p_company jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  rv public.team_members;
  v_fix jsonb;
  v_moved jsonb := '[]'::jsonb;
  v_k text;
  v_words text := '';
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  if q.submitted_at is not null and q.returned_at is null then return jsonb_build_object('error', 'in-review'); end if;
  select * into rv from public.team_members where id = p_reviewer;
  if rv.id is null or not public.quote_sign_may_review(rv.id) or not public.quote_sign_member_sees(rv.id, q.client_id) then
    return jsonb_build_object('error', 'bad-reviewer');
  end if;
  if rv.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if p_company is not null and jsonb_typeof(p_company) = 'object' then
    v_fix := public.quote_sign_company((q.signed->'company') || p_company);
    if v_fix ? 'error' then return v_fix; end if;
    for v_k in select jsonb_object_keys(v_fix->'company') loop
      if (v_fix->'company'->>v_k) is distinct from (q.signed->'company'->>v_k) then
        v_moved := v_moved || jsonb_build_array(jsonb_build_object('field', v_k, 'from', q.signed->'company'->v_k,
                     'to', v_fix->'company'->v_k, 'by', me.name, 'at', now()));
        v_words := v_words || '; ' || case v_k when 'legal_name' then 'Company name as registered' when 'company_no' then 'Business registration no.'
                                          when 'company_no_old' then 'Old registration no.' when 'tin' then 'TIN' when 'sst_no' then 'SST registration no.'
                                          when 'billing_address' then 'Company billing address' when 'finance_email' then 'Finance department email' else v_k end || ': ' || coalesce(q.signed->'company'->>v_k, 'not set') || ' → ' || coalesce(v_fix->'company'->>v_k, 'not set');
      end if;
    end loop;
    if jsonb_array_length(v_moved) > 0 then
      q.signed := q.signed
        || jsonb_build_object('company_signed', coalesce(q.signed->'company_signed', q.signed->'company'))
        || jsonb_build_object('company', v_fix->'company')
        || jsonb_build_object('corrections', coalesce(q.signed->'corrections', '[]'::jsonb) || v_moved);
    end if;
  end if;
  update public.quotations
     set signed = q.signed, submitted_at = now(), submitted_by = me.name, reviewer_id = rv.id, reviewer_name = rv.name,
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · checked and submitted to ' || rv.name || case when v_words <> '' then ' ·' || substr(v_words, 2) else '' end);
  perform public.quote_sign_tell(array[rv.id], 'quote.review', 'Quotation to review · ' || q.brand,
    q.ref || ' · from ' || me.name, q.client_id, q.id::text || ':' || now()::text);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_submit(uuid, uuid, jsonb) from public, anon;
grant execute on function public.quotation_submit(uuid, uuid, jsonb) to authenticated;

create or replace function public.quotation_review(p_id uuid, p_ok boolean, p_note text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  c  public.clients;
  co jsonb;
  v_note text := btrim(coalesce(p_note, ''));
  v_billing text := 'kept';
  v_lines int := 0;
  v_l jsonb;
  v_admin boolean;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  if q.submitted_at is null or q.returned_at is not null then return jsonb_build_object('error', 'not-submitted'); end if;
  -- A colleague with no role is no admin: a null here would let anyone through.
  v_admin := coalesce(me.is_admin, false) or coalesce(me.role, '') = 'admin';
  if q.reviewer_id is distinct from me.id and not v_admin then return jsonb_build_object('error', 'not-reviewer'); end if;

  if not coalesce(p_ok, false) then
    if length(v_note) < 2 or length(v_note) > 1000 then return jsonb_build_object('error', 'note-required'); end if;
    update public.quotations set returned_at = now(), return_note = v_note, returned_by = me.name where id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', q.brand, q.ref || ' · sent back by ' || me.name || ': ' || v_note);
    perform public.quote_sign_tell(array[public.quote_sign_member(q.submitted_by)], 'quote.returned',
      'Quotation sent back · ' || q.brand, q.ref || ' · ' || v_note, q.client_id, q.id::text || ':' || now()::text);
    return jsonb_build_object('ok', true, 'returned', true);
  end if;

  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  select * into c from public.clients where id = q.client_id for update;
  co := q.signed->'company';
  if exists (select 1 from public.bukku_links b where b.kind = 'client' and b.record_id = c.id and b.held_at is not null) then
    v_billing := 'held';
  elsif coalesce(btrim(c.legal_name), '') = '' and coalesce(btrim(c.company_no), '') = '' and coalesce(btrim(c.billing_address), '') = '' then
    if not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'billing-access'); end if;
    update public.clients
       set legal_name = co->>'legal_name', company_no = co->>'company_no',
           company_no_old = coalesce(co->>'company_no_old', company_no_old), tin = coalesce(co->>'tin', tin),
           sst_no = coalesce(co->>'sst_no', sst_no), billing_address = co->>'billing_address',
           finance_email = coalesce(co->>'finance_email', finance_email)
     where id = c.id;
    v_billing := 'filled';
  end if;

  update public.client_services set state = 'confirmed'
   where quotation_id = q.id and archived_at is null and state <> 'confirmed';
  select count(*) into v_lines from public.client_services where quotation_id = q.id and archived_at is null;
  if v_lines = 0 then
    for v_l in select * from jsonb_array_elements(q.lines) loop
      insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                          tenure, term_adjust, term_pct, detail, quotation_id, tax_code)
      values (q.client_id,
              case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
              v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
              case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'confirmed',
              'Quotation ' || q.ref,
              case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
              v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (q.totals->>'term_pct')::numeric else 0 end,
              nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
              q.id, nullif(v_l->>'tax_code', ''));
      v_lines := v_lines + 1;
    end loop;
  end if;

  update public.quotations set reviewed_at = now(), reviewed_by = me.name, reviewed_role = nullif(btrim(coalesce(me.designation, '')), '')
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · reviewed and approved by ' || me.name ||
          case when q.reviewer_id is distinct from me.id then ' in place of ' || coalesce(q.reviewer_name, 'the reviewer') else '' end ||
          ' · ' || v_lines || case when v_lines = 1 then ' service line confirmed · ' else ' service lines confirmed · ' end ||
          case v_billing when 'filled' then 'Billing filled from the signed quotation' when 'held' then 'Billing not changed, as Bukku keeps this client''s billing details'
               else 'Billing not changed' end);
  perform public.quote_sign_tell(array_remove(array[public.quote_sign_member(q.submitted_by), public.quote_sign_member(c.owner)], me.id),
    'quote.reviewed', 'Quotation approved · ' || q.brand, q.ref || ' · by ' || me.name, q.client_id, q.id::text);
  return jsonb_build_object('ok', true, 'billing', v_billing, 'lines', v_lines);
end $$;
revoke all on function public.quotation_review(uuid, boolean, text) from public, anon;
grant execute on function public.quotation_review(uuid, boolean, text) to authenticated;

create or replace function public.quote_website_create(p_sel jsonb, p_contact jsonb, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name  text := btrim(regexp_replace(coalesce(p_contact->>'name', ''), '\s+', ' ', 'g'));
  v_email text := lower(btrim(coalesce(p_contact->>'email', '')));
  v_wa    text := public.quote_website_number(p_contact->>'whatsapp');
  v_brand text := btrim(regexp_replace(coalesce(p_contact->>'brand', ''), '\s+', ' ', 'g'));
  v_ind   text := nullif(btrim(coalesce(p_contact->>'industry', '')), '');
  v_lang  text := case when p_contact->>'lang' = 'zh' then 'zh' else 'en' end;
  v_sal   text := nullif(btrim(coalesce(p_contact->>'salutation', '')), '');
  v_start text := nullif(btrim(coalesce(p_contact->>'commence', '')), '');
  v_idem  text := nullif(btrim(coalesce(p_idem, '')), '');
  v_sel   jsonb;
  v_q     public.quotations;
  v_c     public.clients;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_r     jsonb;
  v_new   boolean := false;
begin
  if v_idem is null or length(v_idem) > 80 then return jsonb_build_object('error', 'bad-request'); end if;
  -- The quotation website covered (Page availability) makes nothing.
  if public.page_covered('quote') then return jsonb_build_object('error', 'unavailable'); end if;
  select * into v_q from public.quotations q
   where q.idem = v_idem and q.source = 'website' and lower(q.contact->>'email') = v_email;
  if v_q.id is not null then
    return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key, 'again', true);
  end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 160 then return jsonb_build_object('error', 'bad-email'); end if;
  if v_wa !~ '^(60(1[0-9]{8,9}|7[0-9]{7,8})|65[0-9]{8})$' then return jsonb_build_object('error', 'bad-whatsapp'); end if;
  if length(v_brand) < 2 or length(v_brand) > 120 then return jsonb_build_object('error', 'bad-brand'); end if;
  -- A name or brand is never a web address: both go into the WhatsApp the
  -- prospect is sent from ADspace's number (2026-10-26, audit).
  if v_name ~* public.quote_link_like() then return jsonb_build_object('error', 'bad-name'); end if;
  if v_brand ~* public.quote_link_like() then return jsonb_build_object('error', 'bad-brand'); end if;
  -- An industry on the list kept in Settings (INDUSTRIES, 2026-11-04).
  if v_ind is not null and not exists (select 1 from public.industries i where i.name = v_ind) then
    return jsonb_build_object('error', 'bad-industry');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-salutation');
  end if;
  -- When they plan to start: the console's Urgency to commence, for the
  -- team's planning; it changes no price. Left out by a page served before.
  if v_start is not null and v_start not in ('1_3', '3_6', '6_plus') then
    return jsonb_build_object('error', 'bad-commence');
  end if;
  if coalesce((p_contact->>'consent')::boolean, false) is not true then return jsonb_build_object('error', 'consent'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if jsonb_typeof(p_sel->'once') = 'array' and jsonb_array_length(p_sel->'once') > 20
     or jsonb_typeof(p_sel->'extra') = 'object' and (select count(*) from jsonb_object_keys(p_sel->'extra')) > 10 then
    return jsonb_build_object('error', 'bad-selection');
  end if;

  -- What the price reads, and nothing else.
  v_sel := jsonb_strip_nulls(jsonb_build_object(
    'mix', case when jsonb_typeof(p_sel->'mix') = 'string' and length(p_sel->>'mix') <= 20 then p_sel->'mix' end,
    'plan', case when jsonb_typeof(p_sel->'plan') = 'string' and length(p_sel->>'plan') <= 80 then p_sel->'plan' end,
    'term', case when jsonb_typeof(p_sel->'term') in ('number', 'string') and length(p_sel->>'term') <= 4 then p_sel->'term' end,
    'budget', case when jsonb_typeof(p_sel->'budget') in ('number', 'string') and length(p_sel->>'budget') <= 12 then p_sel->'budget' end,
    'translate', case when jsonb_typeof(p_sel->'translate') = 'boolean' then p_sel->'translate' end,
    'platforms', (select jsonb_agg(distinct v) from jsonb_array_elements_text(
                    case when jsonb_typeof(p_sel->'platforms') = 'array' then p_sel->'platforms' else '[]'::jsonb end) v
                   where v in ('meta', 'tiktok', 'rednote', 'linkedin')),
    'langs', (select jsonb_agg(distinct l) from jsonb_array_elements_text(
                case when jsonb_typeof(p_sel->'langs') = 'array' then p_sel->'langs' else '[]'::jsonb end) l
               where l in ('en', 'zh', 'ms')),
    'extra', case when jsonb_typeof(p_sel->'extra') = 'object' then
               (select jsonb_object_agg(left(k, 80), p_sel->'extra'->k) from jsonb_object_keys(p_sel->'extra') k) end,
    'once', case when jsonb_typeof(p_sel->'once') = 'array' then
              (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('slug', left(o->>'slug', 80), 'qty', o->'qty')))
                 from jsonb_array_elements(p_sel->'once') o where jsonb_typeof(o) = 'object') end));

  -- Two posts at once are counted one after the other.
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || least(v_email, v_wa), 0));
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || greatest(v_email, v_wa), 0));
  if (select count(*) from public.quotations q
       where q.source = 'website' and q.issued_at > now() - interval '1 day'
         and (lower(q.contact->>'email') = v_email or q.contact->>'whatsapp' = '+' || v_wa)) >= 5 then
    return jsonb_build_object('error', 'limit');
  end if;

  -- A lead this person already is (the same contact holds both the email
  -- and the number), else a new one.
  select c.* into v_c from public.clients c
    join public.client_contacts k on k.client_id = c.id
   where c.stage in ('lead', 'contacted', 'proposal')
     and k.archived_at is null
     and lower(k.email) = v_email
     and public.quote_website_number(k.whatsapp) = v_wa
   order by c.created_at desc limit 1;
  if v_c.id is null then
    v_base := btrim(regexp_replace(lower(v_brand), '[^a-z0-9]+', '-', 'g'), '-');
    if v_base = '' then v_base := 'client'; end if;
    v_slug := v_base;
    while exists (select 1 from public.clients c where lower(c.slug) = v_slug) loop
      v_n := v_n + 1; v_slug := v_base || '-' || v_n;
    end loop;
    insert into public.clients (name, access_token, stage, industry, source, market, slug, deal_note, commence)
    values (v_brand, public.new_link_key(), 'lead', v_ind, 'website',
            case when v_wa like '65%' then 'SG' else 'MY' end, v_slug,
            'Quotation requested on the website.', v_start)
    returning * into v_c;
    insert into public.client_contacts (client_id, salutation, name, email, whatsapp, lang, is_primary)
    values (v_c.id, v_sal, v_name, v_email, '+' || v_wa, v_lang, true);
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.added', v_c.name, 'Website · ' || coalesce(v_sal || ' ', '') || v_name);
    v_new := true;
  end if;

  v_r := public.quotation_make(v_c.id, v_sel, v_idem, 'website', null,
    jsonb_strip_nulls(jsonb_build_object('salutation', v_sal, 'name', v_name, 'email', v_email,
      'whatsapp', '+' || v_wa, 'lang', v_lang, 'brand', v_brand)));
  if v_r ? 'error' then
    if v_new then raise exception using message = 'quote:' || (v_r->>'error'); end if;
    return v_r;
  end if;
  select * into v_q from public.quotations where id = (v_r->>'id')::uuid;
  -- A lead asking again says when it plans to start now, once its
  -- quotation is made (a refused one changes nothing).
  if not v_new and v_start is not null and v_c.commence is distinct from v_start then
    update public.clients set commence = v_start where id = v_c.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.edited', v_c.name, 'Urgency to commence: ' ||
      coalesce(public.quote_commence_word(v_c.commence), 'not set') || ' → ' || public.quote_commence_word(v_start));
  end if;
  -- The price waits for the team (the user, 2026-10-29: "the price
  -- shouldnt send out straight"): the quotation is owed a reply by working
  -- days, the team is told to review it, and the prospect is sent nothing
  -- until a colleague sends it (`quotation_send`).
  update public.quotations set reply_due = public.quote_reply_by(now()) where id = v_q.id
   returning * into v_q;
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation to review · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('Monthly incl. SST RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') || ' · ' || v_name
      || coalesce(' · Starts ' || lower(public.quote_commence_word(v_start)), '')
      || ' · send by ' || public.register_day((v_q.reply_due at time zone 'Asia/Kuala_Lumpur')::date) || ', ' ||
      lower(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
    v_q.id::text);
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

-- END OF ACTIVITY RECORD WORDING ----------------------------------------------

select public.functions_tidy();
