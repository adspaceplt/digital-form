-- ===========================================================================
-- CLIENT DOCUMENT EMAILS — a quotation, a Letter of Offer or a client letter
-- emailed to a client's contact, by hand (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31, on a review of a client's Services tab: "ok
-- build but still same as whatsapp optionally send"): a quotation and a
-- Letter of Offer could be sent on WhatsApp alone, and a client letter
-- issued with Issue document could not be sent at all. Each gains Send by
-- email beside Send on WhatsApp: nothing goes by itself, the team presses it.
--
-- WHAT IT ADDS (built on SUPPLIER EMAILS: the same fill, the same Resend
-- send in `supplier-mail`, the same webhook and sweep)
--   * `client_email_templates`: one subject and body a kind (`quotation`,
--     `offer` Letter of Offer, `letter` a client letter), the team's words
--     with {fields} filled from the record; seeded once. Read and written
--     at `team.settings` (Settings, Templates), filed `team.changed` under
--     Client emails.
--   * `client_emails`: every email sent, the record it carried (kind,
--     `ref_id`, its reference), the contact, who sent it and to whom
--     replies go, its words as sent and what Resend said of it. Kept when
--     the client is deleted (the link set null).
--   * `client_email_may(p_kind, p_level)` (no page's to call): Clients:
--     Quotations for a quotation, Clients: Letters for a Letter of Offer,
--     Letters or Documents: Client documents (`register_may('client')`)
--     for a client letter.
--   * `client_email_prepare(p_kind, p_ref, p_contact)` (that part at Work,
--     the client in scope): the client's contacts holding an email, the
--     billing contact first, the one chosen (else the billing contact, else
--     the primary), the finance email where it differs, each {field}, the
--     template filled, the document's reference, and an email of the same
--     record within `wa_repeat_hours` (`recent`). Refused `not-found`,
--     `void` (a cancelled quotation, a voided or replaced letter),
--     `unreleased` (a website quotation the team has not sent), `no-contact`
--     (marked Do not contact), `no-file` (a letter added by hand), `no-email`
--     (no contact holds one), `bad-contact`.
--   * `client_email_begin` files the send before it goes (a lock on the
--     record; `sending` while one is on its way, then `recent` unless asked
--     again); `client_email_done` closes it as the sender, filed
--     `client.edited` under the client. `supplier-mail` calls both as the
--     colleague.
--   * `client_emails_of(p_client)`: the record's emails, the kinds the
--     reader may see.
--   * A gate (the user, 2026-10-31: "Can gate the send email settings?
--     Enable or disable at business settings"): the Business setting
--     `client_email_on` (0 Off, 1 On, from a day; seeded Off, as Meta
--     checks), Settings, Clients: Send by email. `client_email_set(p_on)`
--     (`team.settings`) sets it from today and files it under Settings;
--     while Off, prepare and begin refuse `email-off` and the page draws no
--     Send by email. Its own setter, so app_settings_set (whose body holds
--     a delete the connector will not apply) is not restated.
--   * `supplier_email_status` (Resend's webhook) and `mail_sweep` (Not
--     confirmed after ten minutes) restated with `client_emails`.
--
-- ORDER: this file (connector), then `supplier-mail`, then the pages. A page
-- served before draws no Send by email; a page served after on a database
-- without this reads "This needs a database update". Safe to run twice.
--
-- ROLLBACK: run OVERDUE INVOICE REMINDERS' `supplier_email_status` and
-- AUDIT SMALL FIXES' `mail_sweep` again, then
--   drop function if exists public.client_email_set(boolean);
--   drop function if exists public.client_emails_of(uuid);
--   drop function if exists public.client_email_done(uuid, text, text, text);
--   drop function if exists public.client_email_begin(text, uuid, uuid, boolean, text, text, boolean);
--   drop function if exists public.client_email_prepare(text, uuid, uuid);
--   drop function if exists public.client_email_template_save(text, text, text);
--   drop function if exists public.client_email_templates_list();
--   drop function if exists public.client_email_may(text, text);
--   drop table if exists public.client_emails;
--   drop table if exists public.client_email_templates;
-- ===========================================================================

-- CLIENT DOCUMENT EMAILS ----------------------------------------------------

insert into public.app_settings (key, from_date, value)
select 'client_email_on', date '2023-08-14', 0
 where not exists (select 1 from public.app_settings s where s.key = 'client_email_on');

create table if not exists public.client_email_templates (
  kind        text primary key check (kind in ('quotation', 'offer', 'letter')),
  subject     text not null,
  body        text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.team_members(id) on delete set null
);
alter table public.client_email_templates enable row level security;
revoke all on table public.client_email_templates from public, anon, authenticated;

insert into public.client_email_templates (kind, subject, body)
select x.kind, x.subject, x.body from (values
  ('quotation', 'Quotation {document reference} · ADspace',
   E'Dear {contact name},\n\nThank you for your interest in ADspace. Please find attached our Quotation {document reference} for {client name}, dated {document date} and valid until {valid until}.\n\nShould you have any questions, please reply to this email.\n\nYours sincerely,\n{sender name}\nADSPACE PLT'),
  ('offer', 'Letter of Offer {document reference} · ADspace',
   E'Dear {contact name},\n\nPlease find attached our Letter of Offer {document reference} for {client name}, dated {document date}.\n\nKindly sign the acceptance page and return it to us to confirm.\n\nYours sincerely,\n{sender name}\nADSPACE PLT'),
  ('letter', '{document title} {document reference} · ADspace',
   E'Dear {contact name},\n\nPlease find attached our {document title} {document reference} for {client name}, dated {document date}.\n\nYours sincerely,\n{sender name}\nADSPACE PLT')
) as x (kind, subject, body)
where not exists (select 1 from public.client_email_templates);

create table if not exists public.client_emails (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid references public.clients(id) on delete set null,
  kind          text not null check (kind in ('quotation', 'offer', 'letter')),
  ref_id        uuid not null,
  reference     text not null,
  contact_id    uuid references public.client_contacts(id) on delete set null,
  to_email      text not null,
  cc_email      text,
  reply_to      text,
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
create index if not exists client_emails_client_idx on public.client_emails (client_id, created_at desc);
create index if not exists client_emails_ref_idx on public.client_emails (kind, ref_id, created_at desc);
create unique index if not exists client_emails_provider_idx on public.client_emails (provider_id) where provider_id is not null;
alter table public.client_emails enable row level security;
revoke all on table public.client_emails from public, anon, authenticated;

create or replace function public.client_email_may(p_kind text, p_level text)
returns boolean
language sql stable security definer set search_path = public as $$
  select case p_kind
    when 'quotation' then public.allowed('clients.quotes', p_level)
    when 'offer'     then public.allowed('clients.documents', p_level)
    when 'letter'    then public.register_may('client', p_level)
    else false end
$$;
revoke all on function public.client_email_may(text, text) from public, anon, authenticated;

create or replace function public.client_email_templates_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.ops_granted('team.settings', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('kind', t.kind, 'subject', t.subject, 'body', t.body,
             'updated_at', t.updated_at, 'updated_by', m.name)
             order by array_position(array['quotation', 'offer', 'letter'], t.kind))
      from public.client_email_templates t left join public.team_members m on m.id = t.updated_by), '[]'::jsonb));
end $$;
revoke all on function public.client_email_templates_list() from public, anon;
grant execute on function public.client_email_templates_list() to authenticated;

create or replace function public.client_email_template_save(p_kind text, p_subject text, p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.client_email_templates;
  v_s text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  moved text[] := '{}';
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.client_email_templates x where x.kind = p_kind for update;
  if t.kind is null then return jsonb_build_object('error', 'bad-kind'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.client_email_templates x set subject = v_s, body = v_b, updated_at = now(), updated_by = me.id
   where x.kind = p_kind;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Client emails',
          case p_kind when 'quotation' then 'Quotation' when 'offer' then 'Letter of Offer' else 'Client letter' end ||
          ' · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_email_template_save(text, text, text) from public, anon;
grant execute on function public.client_email_template_save(text, text, text) to authenticated;

/* What one email is: the record, the client's contacts holding an email,
   the one it goes to, each {field} from the record as saved, and the
   template filled. Asked by the page to draw the sheet and by
   supplier-mail again at the send, as the colleague. */
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
  v_cc := nullif(btrim(coalesce(c.finance_email, '')), '');
  if v_cc is not null and (lower(v_cc) = lower(btrim(k.email)) or v_cc !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then v_cc := null; end if;

  v := jsonb_build_object(
    'contact name', public.contact_named(k.salutation, k.name),
    'client name', c.name,
    'company name', coalesce(nullif(c.legal_name, ''), c.name),
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

/* An email is filed before it goes, so a send whose answer is lost is still
   on the record (Not confirmed). Two presses send once: a lock on the
   record, then `sending` while the same record's email is on its way, then
   `recent` within the window unless asked again. */
create or replace function public.client_email_begin(p_kind text, p_ref uuid, p_contact uuid,
  p_cc boolean, p_subject text, p_body text, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  p   jsonb;
  v_s text;
  v_b text;
  v_id uuid;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  perform pg_advisory_xact_lock(hashtext('client-email:' || coalesce(p_kind, '') || ':' || coalesce(p_ref::text, '')));
  p := public.client_email_prepare(p_kind, p_ref, p_contact);
  if p ? 'error' then return p; end if;
  if exists (select 1 from public.client_emails x where x.kind = p_kind and x.ref_id = p_ref
              and x.status = 'sending' and x.created_at > now() - interval '10 minutes') then
    return jsonb_build_object('error', 'sending');
  end if;
  if jsonb_typeof(p->'recent') = 'object' and not coalesce(p_again, false) then
    return jsonb_build_object('error', 'recent', 'recent', p->'recent');
  end if;
  v_s := btrim(regexp_replace(public.supplier_email_fill(p_subject, p->'values'), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(p_body, p->'values'), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  insert into public.client_emails (client_id, kind, ref_id, reference, contact_id, to_email, cc_email, reply_to, subject, body, sent_by)
  values ((p->>'client_id')::uuid, p_kind, p_ref, p->'document'->>'serial', (p->'to'->>'id')::uuid, p->'to'->>'email',
          case when coalesce(p_cc, false) then p->>'cc' end, p->>'reply_to', v_s, v_b, me.id)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', p->'to', 'cc', case when coalesce(p_cc, false) then p->'cc' end,
    'reply_to', p->'reply_to', 'subject', v_s, 'body', v_b, 'document', p->'document');
end $$;
revoke all on function public.client_email_begin(text, uuid, uuid, boolean, text, text, boolean) from public, anon;
grant execute on function public.client_email_begin(text, uuid, uuid, boolean, text, text, boolean) to authenticated;

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
          e.to_email || coalesce(', copy to ' || e.cc_email, ''));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_email_done(uuid, text, text, text) from public, anon;
grant execute on function public.client_email_done(uuid, text, text, text) to authenticated;

create or replace function public.client_emails_of(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.client_seen(p_client, 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', e.id, 'kind', e.kind, 'ref_id', e.ref_id, 'reference', e.reference,
             'to', e.to_email, 'cc', e.cc_email, 'subject', e.subject, 'status', e.status, 'created_at', e.created_at,
             'delivered_at', e.delivered_at, 'opened_at', e.opened_at, 'bounced_at', e.bounced_at, 'by', m.name)
             order by e.created_at desc)
      from public.client_emails e
      left join public.team_members m on m.id = e.sent_by
     where e.client_id = p_client and public.client_email_may(e.kind, 'view')), '[]'::jsonb));
end $$;
revoke all on function public.client_emails_of(uuid) from public, anon;
grant execute on function public.client_emails_of(uuid) to authenticated;

/* Send by email on or off from today (Settings, Clients), filed from and
   to under Settings as a Business setting is. */
create or replace function public.client_email_set(p_on boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_was  numeric;
  v_to   numeric := case when coalesce(p_on, false) then 1 else 0 end;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_was := public.app_setting('client_email_on', v_today);
  if v_was is not distinct from v_to then return jsonb_build_object('ok', true); end if;
  insert into public.app_settings (key, from_date, value, set_by, set_at)
  values ('client_email_on', v_today, v_to, me.id, now())
  on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Settings',
          'Send by email: ' || case when v_was = 1 then 'On' else 'Off' end || ' → ' ||
          case when v_to = 1 then 'On' else 'Off' end || ' · from ' || public.register_day(v_today));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_email_set(boolean) from public, anon;
grant execute on function public.client_email_set(boolean) to authenticated;

/* Resend's word on a sent email (supplier-mail, its webhook, the service
   role): a supplier's email, an overdue reminder or a client's document
   alike. A later word never steps back: an opened email is never delivered
   again, a bounce stays. */
create or replace function public.supplier_email_status(p_provider text, p_event text, p_at timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e    public.supplier_emails;
  i    public.invoice_emails;
  ce   public.client_emails;
  rank constant jsonb := '{"sending":0,"unknown":1,"sent":1,"failed":1,"delivered":2,"opened":3,"complained":4,"bounced":4}';
  st   text := case p_event when 'email.delivered' then 'delivered' when 'email.opened' then 'opened'
                when 'email.clicked' then 'opened' when 'email.bounced' then 'bounced'
                when 'email.complained' then 'complained' when 'email.sent' then 'sent' end;
begin
  if st is null then return jsonb_build_object('ok', true, 'ignored', true); end if;
  select * into e from public.supplier_emails x where x.provider_id = p_provider for update;
  if e.id is not null then
    update public.supplier_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st <> 'bounced' then p_at end),
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
      sent_at = coalesce(x.sent_at, case when st <> 'bounced' then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = ce.id;
    return jsonb_build_object('ok', true);
  end if;
  select * into i from public.invoice_emails x where x.provider_id = p_provider for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.invoice_emails x set
    status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
    sent_at = coalesce(x.sent_at, case when st <> 'bounced' then p_at end),
    delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
    opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
    bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
   where x.id = i.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_email_status(text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.supplier_email_status(text, text, timestamptz) to service_role;

create or replace function public.mail_sweep()
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  n integer := 0;
  k integer;
begin
  update public.invoice_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.supplier_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.client_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_sweep() from public, anon, authenticated;

-- END OF CLIENT DOCUMENT EMAILS ---------------------------------------------

select public.functions_tidy();
