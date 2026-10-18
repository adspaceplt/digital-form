-- ===========================================================================
-- SUPPLIER EMAILS — a supplier is emailed from its record, by hand
-- (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18: "for the email yes use resend"; "dont automate
-- first, propose me the build and mockups"; then, on the mockups: "ok build
-- it", replies to ap@adspacestudios.com, delivery status now, and after
-- Approve "prompt to either send or not, also keep the manual send option")
--
-- WHAT IT ADDS
--   * `supplier_email_templates`: one subject and body a purpose (`approved`,
--     Supplier approved; `document`, a supplier's document with its PDF),
--     the team's words with {fields} the saved supplier fills; seeded once.
--     Read at Suppliers View (`supplier_email_templates_list`), written at
--     Suppliers Manage (`supplier_email_template_save`), filed
--     `supplier.edited` under Supplier emails.
--   * `supplier_emails`: every email sent, who to, by whom, its words as
--     sent and what Resend said of it (sending, sent, failed, unknown, then
--     delivered, opened, bounced, complained). Kept when the supplier is
--     deleted (the link set null).
--   * `supplier_email_prepare(p_supplier, p_purpose, p_document)` (Suppliers
--     Work): the supplier's email and finance email, each {field} from the
--     record as saved, the template filled, and an email of the same
--     purpose and document sent within `wa_repeat_hours` (Settings, Sent
--     again). `supplier_email_begin` files the send before it goes,
--     refusing `recent` unless asked again, and `supplier_email_done` closes
--     it; `supplier-mail` calls both as the colleague. Resend's word on a
--     sent email reaches `supplier_email_status`, the service role's alone.
--   * `supplier_emails_of(p_supplier)` (Suppliers View): the record's
--     Emails.
--
-- ORDER: this file, then `supplier-mail`, then the pages. A page served
-- before draws no Emails and no Send email. Safe to run twice. Rollback:
-- drop the eight functions and the two tables.
-- ===========================================================================

create table if not exists public.supplier_email_templates (
  purpose     text primary key check (purpose in ('approved', 'document')),
  subject     text not null,
  body        text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.team_members(id) on delete set null
);
alter table public.supplier_email_templates enable row level security;
revoke all on table public.supplier_email_templates from public, anon, authenticated;

insert into public.supplier_email_templates (purpose, subject, body)
select x.purpose, x.subject, x.body from (values
  ('approved', 'Supplier registration approved · ADspace',
   E'Dear {contact name},\n\nThank you for completing your supplier registration. {supplier name} is now an approved supplier of ADSPACE PLT under Supplier ID {supplier id}.\n\nPayment is made on {payment term} terms in {currency}.\n\nYours sincerely,\n{sender name}\nADSPACE PLT'),
  ('document', '{document title} {document reference} · ADspace',
   E'Dear {contact name},\n\nPlease find attached our {document title} {document reference} for {supplier name} (Supplier ID {supplier id}), dated {document date}.\n\nYours sincerely,\n{sender name}\nADSPACE PLT')
) as x (purpose, subject, body)
where not exists (select 1 from public.supplier_email_templates);

create table if not exists public.supplier_emails (
  id            uuid primary key default gen_random_uuid(),
  supplier_id   uuid references public.suppliers(id) on delete set null,
  document_id   uuid,
  purpose       text not null check (purpose in ('approved', 'document')),
  to_email      text not null,
  cc_email      text,
  subject       text not null,
  body          text not null,
  sent_by       uuid references public.team_members(id) on delete set null,
  created_at    timestamptz not null default now(),
  status        text not null default 'sending'
                check (status in ('sending', 'sent', 'failed', 'unknown', 'delivered', 'opened', 'bounced', 'complained')),
  provider_id   text,
  error         text,
  sent_at       timestamptz,
  delivered_at  timestamptz,
  opened_at     timestamptz,
  bounced_at    timestamptz
);
create index if not exists supplier_emails_supplier_idx on public.supplier_emails (supplier_id, created_at desc);
create unique index if not exists supplier_emails_provider_idx on public.supplier_emails (provider_id) where provider_id is not null;
alter table public.supplier_emails enable row level security;
revoke all on table public.supplier_emails from public, anon, authenticated;

/* Each {field} in a text, named in any case and spacing, takes its value; a
   field nothing answers stays as typed, where the person sees it. */
create or replace function public.supplier_email_fill(p_text text, p_values jsonb)
returns text
language plpgsql immutable set search_path = public as $$
declare
  t text := coalesce(p_text, '');
  k text;
begin
  for k in select jsonb_object_keys(coalesce(p_values, '{}'::jsonb)) loop
    if coalesce(p_values->>k, '') <> '' then
      t := regexp_replace(t, '\{\s*' || replace(k, ' ', '\s+') || '\s*\}',
                          replace(p_values->>k, E'\\', E'\\\\'), 'gi');
    end if;
  end loop;
  return t;
end $$;
revoke all on function public.supplier_email_fill(text, jsonb) from public, anon, authenticated;

create or replace function public.supplier_email_templates_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('purpose', t.purpose, 'subject', t.subject, 'body', t.body,
             'updated_at', t.updated_at, 'updated_by', m.name) order by t.purpose)
      from public.supplier_email_templates t left join public.team_members m on m.id = t.updated_by), '[]'::jsonb));
end $$;
revoke all on function public.supplier_email_templates_list() from public, anon;
grant execute on function public.supplier_email_templates_list() to authenticated;

create or replace function public.supplier_email_template_save(p_purpose text, p_subject text, p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.supplier_email_templates;
  v_s text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  moved text[] := '{}';
begin
  if me.id is null or not public.allowed('suppliers', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.supplier_email_templates x where x.purpose = p_purpose for update;
  if t.purpose is null then return jsonb_build_object('error', 'bad-purpose'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Body'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.supplier_email_templates x set subject = v_s, body = v_b, updated_at = now(), updated_by = me.id
   where x.purpose = p_purpose;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'supplier.edited', 'Supplier emails',
          case p_purpose when 'approved' then 'Supplier approved' else 'Document' end || ' · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_email_template_save(text, text, text) from public, anon;
grant execute on function public.supplier_email_template_save(text, text, text) to authenticated;

/* What one email is: the supplier, its document, each {field} from the
   record as saved, and the template filled. Asked by the page to draw the
   sheet and by supplier-mail again at the send, as the colleague. */
create or replace function public.supplier_email_prepare(p_supplier uuid, p_purpose text, p_document uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.suppliers;
  d     public.documents;
  t     public.supplier_email_templates;
  v     jsonb;
  hours numeric;
  r     public.supplier_emails;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_supplier;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.supplier_email_templates x where x.purpose = p_purpose;
  if t.purpose is null then return jsonb_build_object('error', 'bad-purpose'); end if;
  if coalesce(s.email, '') = '' then return jsonb_build_object('error', 'no-email'); end if;
  if p_purpose = 'approved' and s.status <> 'active' then return jsonb_build_object('error', 'not-active'); end if;
  if p_purpose = 'document' then
    select * into d from public.documents x where x.id = p_document and x.supplier_id = s.id;
    if d.id is null or d.voided_at is not null then return jsonb_build_object('error', 'bad-document'); end if;
  end if;
  v := jsonb_build_object(
    'supplier name', coalesce(s.name, s.code), 'supplier id', s.code,
    'contact name', coalesce(s.contact_name, ''), 'designation', coalesce(s.designation, ''),
    'payment term', coalesce(s.payment_term, ''),
    'currency', case s.currency when 'SGD' then 'SGD' else 'MYR' end,
    'document title', coalesce(d.kind, ''), 'document reference', coalesce(d.serial, ''),
    'document date', case when d.issued_at is null then ''
      else to_char(d.issued_at at time zone 'Asia/Kuala_Lumpur', 'FMDD FMMonth YYYY') end,
    'sender name', coalesce(me.name, ''));
  hours := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  if hours > 0 then
    select * into r from public.supplier_emails x
     where x.supplier_id = s.id and x.purpose = p_purpose and x.document_id is not distinct from d.id
       and x.status not in ('failed') and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
  end if;
  return jsonb_build_object('ok', true,
    'to', jsonb_build_object('name', coalesce(s.contact_name, coalesce(s.name, s.code)), 'email', s.email),
    'cc', nullif(coalesce(s.finance_email, ''), s.email),
    'values', v,
    'subject', public.supplier_email_fill(t.subject, v),
    'body', public.supplier_email_fill(t.body, v),
    'document', case when d.id is null then null else jsonb_build_object('id', d.id, 'serial', d.serial, 'kind', d.kind) end,
    'recent', case when r.id is null then null else jsonb_build_object('at', r.created_at, 'to', r.to_email,
      'by', (select m.name from public.team_members m where m.id = r.sent_by)) end);
end $$;
revoke all on function public.supplier_email_prepare(uuid, text, uuid) from public, anon;
grant execute on function public.supplier_email_prepare(uuid, text, uuid) to authenticated;

/* An email is filed before it goes, so a send whose answer is lost is still
   on the record (Not confirmed); the same email sent within the window is
   refused `recent` unless asked again. The words are the page's, every
   {field} filled from the record as saved. */
create or replace function public.supplier_email_begin(p_supplier uuid, p_purpose text, p_document uuid,
  p_cc boolean, p_subject text, p_body text, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  p   jsonb := public.supplier_email_prepare(p_supplier, p_purpose, p_document);
  v_s text;
  v_b text;
  v_id uuid;
begin
  if p ? 'error' then return p; end if;
  if (p->'recent') is not null and jsonb_typeof(p->'recent') = 'object' and not coalesce(p_again, false) then
    return jsonb_build_object('error', 'recent', 'recent', p->'recent');
  end if;
  v_s := btrim(regexp_replace(public.supplier_email_fill(p_subject, p->'values'), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(p_body, p->'values'), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  insert into public.supplier_emails (supplier_id, document_id, purpose, to_email, cc_email, subject, body, sent_by)
  values (p_supplier, case when p_purpose = 'document' then p_document end, p_purpose, p->'to'->>'email',
          case when coalesce(p_cc, false) then p->>'cc' end, v_s, v_b, me.id)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', p->'to', 'cc', case when coalesce(p_cc, false) then p->'cc' end,
    'subject', v_s, 'body', v_b, 'values', p->'values', 'document', p->'document');
end $$;
revoke all on function public.supplier_email_begin(uuid, text, uuid, boolean, text, text, boolean) from public, anon;
grant execute on function public.supplier_email_begin(uuid, text, uuid, boolean, text, text, boolean) to authenticated;

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
          e.to_email || coalesce(', cc ' || e.cc_email, ''));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_email_done(uuid, text, text, text) from public, anon;
grant execute on function public.supplier_email_done(uuid, text, text, text) to authenticated;

/* Resend's word on a sent email (supplier-mail, its webhook, the service
   role): delivered, opened, bounced or complained. A later word never
   steps back: an opened email is never delivered again, a bounce stays. */
create or replace function public.supplier_email_status(p_provider text, p_event text, p_at timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e    public.supplier_emails;
  rank constant jsonb := '{"sending":0,"unknown":1,"sent":1,"failed":1,"delivered":2,"opened":3,"complained":4,"bounced":4}';
  st   text := case p_event when 'email.delivered' then 'delivered' when 'email.opened' then 'opened'
                when 'email.clicked' then 'opened' when 'email.bounced' then 'bounced'
                when 'email.complained' then 'complained' when 'email.sent' then 'sent' end;
begin
  if st is null then return jsonb_build_object('ok', true, 'ignored', true); end if;
  select * into e from public.supplier_emails x where x.provider_id = p_provider for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.supplier_emails x set
    status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
    sent_at = coalesce(x.sent_at, case when st <> 'bounced' then p_at end),
    delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
    opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
    bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
   where x.id = e.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_email_status(text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.supplier_email_status(text, text, timestamptz) to service_role;

create or replace function public.supplier_emails_of(p_supplier uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', e.id, 'purpose', e.purpose, 'to', e.to_email, 'cc', e.cc_email,
             'subject', e.subject, 'status', e.status, 'error', e.error, 'created_at', e.created_at,
             'delivered_at', e.delivered_at, 'opened_at', e.opened_at, 'bounced_at', e.bounced_at,
             'by', m.name, 'document', d.serial) order by e.created_at desc)
      from public.supplier_emails e
      left join public.team_members m on m.id = e.sent_by
      left join public.documents d on d.id = e.document_id
     where e.supplier_id = p_supplier), '[]'::jsonb));
end $$;
revoke all on function public.supplier_emails_of(uuid) from public, anon;
grant execute on function public.supplier_emails_of(uuid) to authenticated;

-- END OF SUPPLIER EMAILS ----------------------------------------------------
select public.functions_tidy();
