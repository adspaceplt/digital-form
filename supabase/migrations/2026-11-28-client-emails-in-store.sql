-- ===========================================================================
-- CLIENT EMAILS IN THE TEMPLATE STORE (2026-11-28)
-- ===========================================================================
-- WHY: restructure release 12 (docs/MAP.md §G, layer 3; the release 11
-- handover: Settings › Messages moves onto the store a family at a time,
-- the Letter of Offer's and client letters' emails first). And HANDOVER
-- item 19 (the user, 28 Nov, release 8 decision 3): a saved subject or
-- sign-off that types the agency's name reads a field filled from the
-- agency profile, so another agency's install never sends ours.
-- WHAT IT CHANGES
--   * Two fields, `{agency}` (the profile's trading_name) and
--     `{agency legal name}` (its legal_name), join the lists of the kinds
--     whose senders fill through `supplier_email_fill` or
--     `creator_mail_fill` (client, supplier, free, invoice, creator-details,
--     creator-booking; `template_fields`). Both helpers fill them from the
--     profile wherever the sender's values hold none (now `stable`: they
--     read the profile). `template_values` gives them to the store's
--     engine for those kinds.
--   * The client family (a quotation's, a Letter of Offer's and a client
--     letter's email) moves into `templates`: keys `client.quotation`,
--     `client.offer`, `client.letter`, kind `client`, English, version 1
--     live from the day its words were last saved, copied from
--     `client_email_templates` as they stand (never typed here: the
--     repository is public). `client_email_prepare` reads the version in
--     force today; `client_email_templates_list` reads the store; a save
--     (`client_email_template_save`, the same check and access) adds the
--     next version, live from today, and files what changed as before.
--     `client_email_templates` is kept, read by nothing, for the rollback.
--   * Saved words: where a subject or a message of these families types the
--     profile's legal name or trading name, it reads `{agency legal name}`
--     or `{agency}` (the store's client versions, supplier_email_templates,
--     email_templates, invoice_email_template, invoice_send_template,
--     creator_email_templates). Filled, every email reads as it did.
-- NOT IN THIS RELEASE: the feedback, quotation request, candidate, sign-in
--   code and meeting families (their senders fill by their own loops, the
--   candidate's and the code's in edge functions) and the Letter of
--   Offer's and client letters' own words (Documents, release 12b).
-- ORDER: this file, then the pages (js/invoices.js fills the two fields
--   in an invoice email it draws). An open tab's invoice email drawn before
--   the page loads anew shows {agency} in its subject until it is sent;
--   the database fills it at the send.
-- ROLLBACK: restate client_email_prepare, client_email_templates_list,
--   client_email_template_save, template_fields, template_values,
--   supplier_email_fill and creator_mail_fill from their earlier bands;
--   copy each in-force client.* version back into client_email_templates;
--   replace '{agency legal name}' and '{agency}' with the profile's values
--   in the five tables; delete from public.templates where key like
--   'client.%' (as the table owner: templates_guard refuses a live row,
--   so disable it for that statement); drop function
--   public.template_agency_fields(text). Safe to run twice.

-- CLIENT EMAILS IN THE TEMPLATE STORE ---------------------------------------

create or replace function public.template_fields(p_kind text) returns text[]
language sql immutable set search_path = public as $$
  select case p_kind
    when 'supplier' then array['contact name', 'supplier name', 'supplier id', 'payment term', 'currency',
      'document title', 'document reference', 'document date', 'sender name', 'agency', 'agency legal name']
    when 'client' then array['contact name', 'client name', 'company name', 'document title', 'document reference',
      'document date', 'valid until', 'sender name', 'agency', 'agency legal name']
    when 'free' then array['contact name', 'company name', 'client name', 'supplier name', 'sender name', 'agency', 'agency legal name']
    when 'invoice' then array['contact name', 'client', 'invoice no', 'count', 'total', 'sign off', 'invoices', 'agency', 'agency legal name']
    when 'creator-details' then array['creator name', 'creator id', 'reference', 'payee', 'method', 'account ending',
      'review link', 'date', 'chinese date', 'changes', 'agency', 'agency legal name']
    when 'creator-booking' then array['creator name', 'creator id', 'job reference', 'campaign', 'posted date', 'pay by',
      'payee', 'method', 'account ending', 'amount', 'bill number', 'review link', 'agency', 'agency legal name']
    when 'meeting' then array['meeting', 'date', 'time', 'month', 'channel', 'link']
    when 'code' then array['name', 'code', 'minutes', 'purpose']
    when 'candidate' then array['candidate name', 'position', 'interview length', 'where', 'times', 'reply by', 'note',
      'time', 'previous time', 'new time', 'place', 'google meet notice', 'decision date', 'months', 'document', 'reference',
      'requested action', 'purpose', 'reason', 'document date', 'contact', 'sign-off', 'button']
    when 'feedback' then array['contact name', 'client name', 'link']
    when 'quote' then array['contact name', 'brand', 'reference', 'details', 'reply by', 'link']
  end $$;
revoke all on function public.template_fields(text) from public, anon, authenticated;

create or replace function public.supplier_email_fill(p_text text, p_values jsonb)
returns text
language plpgsql stable set search_path = public as $$
declare
  t text := coalesce(p_text, '');
  k text;
  v jsonb := jsonb_build_object('agency', public.agency('trading_name'), 'agency legal name', public.agency('legal_name'))
             || coalesce(p_values, '{}'::jsonb);
begin
  for k in select jsonb_object_keys(v) loop
    if coalesce(v->>k, '') <> '' then
      t := regexp_replace(t, '\{\s*' || replace(k, ' ', '\s+') || '\s*\}',
                          replace(v->>k, E'\\', E'\\\\'), 'gi');
    end if;
  end loop;
  return t;
end $$;
revoke all on function public.supplier_email_fill(text, jsonb) from public, anon, authenticated;

create or replace function public.creator_mail_fill(p_text text, p_vals jsonb)
returns text
language plpgsql stable set search_path = public as $$
declare
  v_out text := coalesce(p_text, '');
  v_k text;
  v jsonb := jsonb_build_object('agency', public.agency('trading_name'), 'agency legal name', public.agency('legal_name'))
             || coalesce(p_vals, '{}'::jsonb);
begin
  for v_k in select jsonb_object_keys(v) loop
    v_out := regexp_replace(v_out, '\{\s*' || v_k || '\s*\}', replace(coalesce(v->>v_k, ''), '\', '\\'), 'gi');
  end loop;
  return v_out;
end $$;
revoke all on function public.creator_mail_fill(text, jsonb) from public, anon, authenticated;

create or replace function public.template_values(p_kind text, p_record uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_c public.clients;
  v_su public.suppliers;
  v_out jsonb := '{}'::jsonb;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if 'sender name' = any (coalesce(public.template_fields(p_kind), '{}'::text[])) then
    v_out := v_out || jsonb_build_object('sender name', me.name);
  end if;
  if 'agency' = any (coalesce(public.template_fields(p_kind), '{}'::text[])) then
    v_out := v_out || jsonb_build_object('agency', public.agency('trading_name'), 'agency legal name', public.agency('legal_name'));
  end if;
  if p_record is null then return v_out; end if;
  if p_kind = 'client' then
    if not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
    select * into v_c from public.clients x where x.id = p_record;
    if v_c.id is null or not public.client_seen(v_c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    v_out := v_out || jsonb_build_object('client name', v_c.name, 'company name',
      coalesce(case when public.allowed('clients.billing', 'view') then nullif(btrim(v_c.legal_name), '') end, v_c.name));
    if public.allowed('clients.contacts', 'view') then
      v_out := v_out || jsonb_strip_nulls(jsonb_build_object('contact name',
        (select k.name from public.client_contacts k
          where k.client_id = v_c.id and k.is_primary and k.archived_at is null limit 1)));
    end if;
  elsif p_kind = 'supplier' then
    if not public.allowed('suppliers', 'view') then return jsonb_build_object('error', 'denied'); end if;
    select * into v_su from public.suppliers x where x.id = p_record;
    if v_su.id is null then return jsonb_build_object('error', 'not-found'); end if;
    v_out := v_out || jsonb_strip_nulls(jsonb_build_object('supplier name', v_su.name, 'supplier id', v_su.code,
      'contact name', nullif(btrim(v_su.contact_name), ''), 'payment term', v_su.payment_term, 'currency', v_su.currency));
  else
    return jsonb_build_object('error', 'no-record');
  end if;
  return v_out;
end $$;
revoke all on function public.template_values(text, uuid) from public, anon, authenticated;

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
  t      public.templates;
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
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if p_kind not in ('quotation', 'offer', 'letter') then return jsonb_build_object('error', 'bad-request'); end if;
  if not public.client_email_may(p_kind, 'work') or not public.allowed('clients.contacts', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if coalesce(public.app_setting('client_email_on', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) <> 1 then
    return jsonb_build_object('error', 'email-off');
  end if;
  if p_kind = 'quotation' then
    select * into q from public.quotations x where x.id = p_ref;
    if q.id is null or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
    if q.status = 'not_proceeding' then return jsonb_build_object('error', 'void'); end if;
    if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'unreleased'); end if;
    if q.confirmed_at is null then return jsonb_build_object('error', 'not-confirmed'); end if;
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
  t := public.template_in_force('client.' || p_kind, 'en', (now() at time zone 'Asia/Kuala_Lumpur')::date);
  if t.id is null then return jsonb_build_object('error', 'needs-update'); end if;

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
     where x.kind = p_kind and x.ref_id = p_ref and x.status not in ('failed', 'cancelled')
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

create or replace function public.client_email_templates_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if (public.ops_me()).id is null or not public.ops_granted('team.settings', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('kind', k.kind, 'subject', t.subject, 'body', t.body,
             'version', t.version, 'updated_at', t.created_at, 'updated_by', m.name)
             order by k.o)
      from unnest(array['quotation', 'offer', 'letter']) with ordinality as k (kind, o)
      cross join lateral public.template_in_force('client.' || k.kind, 'en', v_today) t
      left join public.team_members m on m.id = t.created_by_id
     where t.id is not null), '[]'::jsonb));
end $$;
revoke all on function public.client_email_templates_list() from public, anon;
grant execute on function public.client_email_templates_list() to authenticated;

/* A client email's words saved: the next version of its key, live from
   today (Malaysia), the one before kept for the days before. */
create or replace function public.client_email_template_save(p_kind text, p_subject text, p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  t   public.templates;
  v_s text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  moved text[] := '{}';
  v_bad jsonb;
  v_ver int;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind is null or p_kind not in ('quotation', 'offer', 'letter') then return jsonb_build_object('error', 'bad-kind'); end if;
  perform pg_advisory_xact_lock(hashtext('templates:client.' || p_kind));
  t := public.template_in_force('client.' || p_kind, 'en', v_today);
  if t.id is null then return jsonb_build_object('error', 'bad-kind'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  v_bad := public.template_check(v_s || E'\n' || v_b, 'client');
  if v_bad is not null then return v_bad; end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  select coalesce(max(x.version), 0) + 1 into v_ver from public.templates x where x.key = t.key and x.language = 'en';
  insert into public.templates (key, kind, language, version, subject, body, status, effective_from,
                                created_by_id, published_by_id, published_at)
  values (t.key, 'client', 'en', v_ver, v_s, v_b, 'live', v_today, me.id, me.id, now());
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Client emails',
          case p_kind when 'quotation' then 'Quotation' when 'offer' then 'Letter of Offer' else 'Client letter' end ||
          ' · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true, 'version', v_ver);
end $$;
revoke all on function public.client_email_template_save(text, text, text) from public, anon;
grant execute on function public.client_email_template_save(text, text, text) to authenticated;

/* The agency's name in saved words becomes its field, the legal name
   first. Filled, each email reads as before. */
create or replace function public.template_agency_fields(p_text text) returns text
language sql stable set search_path = public as $$
  select case when coalesce(public.agency('trading_name'), '') = '' or coalesce(public.agency('legal_name'), '') = ''
              then p_text
              else replace(replace(p_text, public.agency('legal_name'), '{agency legal name}'),
                           public.agency('trading_name'), '{agency}') end $$;
revoke all on function public.template_agency_fields(text) from public, anon, authenticated;

/* The client family, copied once from the table it was kept in. */
insert into public.templates (key, kind, language, version, subject, body, status, effective_from,
                              created_by_id, created_at, updated_at, published_by_id, published_at)
select 'client.' || c.kind, 'client', 'en', 1,
       public.template_agency_fields(c.subject), public.template_agency_fields(c.body), 'live',
       (c.updated_at at time zone 'Asia/Kuala_Lumpur')::date,
       c.updated_by, c.updated_at, c.updated_at, c.updated_by, c.updated_at
  from public.client_email_templates c
 where not exists (select 1 from public.templates x where x.key = 'client.' || c.kind);

update public.supplier_email_templates x
   set subject = public.template_agency_fields(x.subject), body = public.template_agency_fields(x.body)
 where (x.subject, x.body) is distinct from (public.template_agency_fields(x.subject), public.template_agency_fields(x.body));
update public.email_templates x
   set subject = public.template_agency_fields(x.subject), body = public.template_agency_fields(x.body)
 where (x.subject, x.body) is distinct from (public.template_agency_fields(x.subject), public.template_agency_fields(x.body));
update public.invoice_email_template x
   set subject_one = public.template_agency_fields(x.subject_one), subject_many = public.template_agency_fields(x.subject_many),
       body = public.template_agency_fields(x.body)
 where (x.subject_one, x.subject_many, x.body) is distinct from
       (public.template_agency_fields(x.subject_one), public.template_agency_fields(x.subject_many), public.template_agency_fields(x.body));
update public.invoice_send_template x
   set subject_one = public.template_agency_fields(x.subject_one), subject_many = public.template_agency_fields(x.subject_many),
       body = public.template_agency_fields(x.body)
 where (x.subject_one, x.subject_many, x.body) is distinct from
       (public.template_agency_fields(x.subject_one), public.template_agency_fields(x.subject_many), public.template_agency_fields(x.body));
update public.creator_email_templates x
   set subject = public.template_agency_fields(x.subject), body = public.template_agency_fields(x.body)
 where (x.subject, x.body) is distinct from (public.template_agency_fields(x.subject), public.template_agency_fields(x.body));

-- END OF CLIENT EMAILS IN THE TEMPLATE STORE --------------------------------

select public.functions_tidy();
