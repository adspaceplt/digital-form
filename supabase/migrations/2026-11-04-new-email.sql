-- NEW EMAIL ---------------------------------------------------------------------
-- 2026-11-04, the user: "for the New email button could it be added here and
-- the email requires us to manually send to others; remember the email
-- template?", then: recipients by selection (a client's contacts, a
-- supplier) or typed freely; a saved template to pick for clients or for
-- suppliers, else a custom message in the branded layout; a file optional
-- (never the invoice email, which keeps its own sheet).
--
--   email_templates      a team's saved words, for clients or for suppliers
--                        (Settings, Templates: Email templates, team.settings);
--                        RLS on, no policy, no grant
--   team_emails          every New email, filed before it goes, closed by its
--                        sender, its status from Resend's webhook; RLS on, no
--                        policy, no grant; no foreign key, so a record removed
--                        leaves the email in the log
--   email_templates_list, email_template_save
--   email_parties        the clients and suppliers holding an email the
--                        sender may write to
--   email_recipients     a client's addresses (as an invoice email's) or a
--                        supplier's email and finance email
--   email_new_begin      files the email at Messages Work: To and Copy among
--                        the record's own addresses, any well-formed address
--                        for Other; five copies at most; the fields filled;
--                        one key a sheet; a hundred a colleague a day
--   email_new_done       closes it as its sender, filed email.sent
--   supplier_email_status, mail_sweep, mail_log   read team_emails too; a
--                        client's at Clients: Contacts View alone, as its
--                        addresses are
--   team_emails_of       a client's New emails, on its Contacts
--   supplier_emails_of   a supplier's emails, its New emails among them
--   mail_retention       an email's addresses and words cleared a year on
--                        (pg_cron mail-retention, the 2nd of each month)
--
-- The SQL Editor part (2026-11-04-new-email-editor.sql): email.sent named
-- under Messages in activity_section, and a saved template removed for good.
--
-- Rollback (the SQL Editor's): restore the three functions above from their
-- earlier sections, revoke and remove the new ones; the tables may stay.

create table if not exists public.email_templates (
  id          uuid primary key default gen_random_uuid(),
  audience    text not null check (audience in ('client', 'supplier')),
  name        text not null,
  subject     text not null,
  body        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
create unique index if not exists email_templates_name_idx on public.email_templates (audience, lower(name));
alter table public.email_templates enable row level security;
revoke all on table public.email_templates from public, anon, authenticated;

create table if not exists public.team_emails (
  id            uuid primary key default gen_random_uuid(),
  audience      text not null check (audience in ('client', 'supplier', 'other')),
  client_id     uuid,
  supplier_id   uuid,
  template_id   uuid,
  to_email      text not null,
  to_name       text,
  cc_email      text,
  reply_to      text,
  subject       text not null,
  body          text not null,
  attachment    text,
  idem          text,
  sent_by       uuid,
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
create index if not exists team_emails_created_idx on public.team_emails (created_at desc);
create unique index if not exists team_emails_provider_idx on public.team_emails (provider_id) where provider_id is not null;
create unique index if not exists team_emails_idem_idx on public.team_emails (sent_by, idem) where idem is not null;
alter table public.team_emails enable row level security;
revoke all on table public.team_emails from public, anon, authenticated;

create or replace function public.email_templates_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not (public.allowed('whatsapp', 'work') or public.ops_granted('team.settings', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', t.id, 'audience', t.audience, 'name', t.name, 'subject', t.subject, 'body', t.body,
             'updated_at', t.updated_at, 'updated_by', (select m.name from public.team_members m where m.id = t.updated_by))
             order by t.audience, lower(t.name))
      from public.email_templates t), '[]'::jsonb));
end $$;
revoke all on function public.email_templates_list() from public, anon;
grant execute on function public.email_templates_list() to authenticated;

create or replace function public.email_template_save(p_id uuid, p_audience text, p_name text, p_subject text, p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  t     public.email_templates;
  v_n   text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_s   text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b   text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  moved text[] := '{}';
  v_id  uuid;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_n) < 2 or length(v_n) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if p_id is null then
    if p_audience is null or p_audience not in ('client', 'supplier') then return jsonb_build_object('error', 'bad-request'); end if;
    if exists (select 1 from public.email_templates x where x.audience = p_audience and lower(x.name) = lower(v_n)) then
      return jsonb_build_object('error', 'taken');
    end if;
    insert into public.email_templates (audience, name, subject, body, updated_by) values (p_audience, v_n, v_s, v_b, me.id)
    returning id into v_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Email templates', 'Added: ' || v_n || ' (' || case p_audience when 'client' then 'Clients' else 'Suppliers' end || ')');
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;
  select * into t from public.email_templates x where x.id = p_id for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.email_templates x where x.audience = t.audience and lower(x.name) = lower(v_n) and x.id <> t.id) then
    return jsonb_build_object('error', 'taken');
  end if;
  if t.name is distinct from v_n then moved := moved || ('Name: ' || t.name || ' → ' || v_n); end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true, 'id', t.id); end if;
  update public.email_templates x set name = v_n, subject = v_s, body = v_b, updated_at = now(), updated_by = me.id where x.id = t.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Email templates', t.name || ' · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true, 'id', t.id);
end $$;
revoke all on function public.email_template_save(uuid, text, text, text, text) from public, anon;
grant execute on function public.email_template_save(uuid, text, text, text, text) to authenticated;

/* A supplier's addresses: its email under its contact's name, then its
   finance email where it differs. Internal. */
create or replace function public.email_supplier_options(p_supplier uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(o.x order by o.ord), '[]'::jsonb) from (
    select jsonb_build_object('email', btrim(s.email), 'name', nullif(btrim(coalesce(s.contact_name, '')), ''), 'role', null,
             'finance', false, 'billing', true) as x, 0 as ord
      from public.suppliers s where s.id = p_supplier and coalesce(btrim(s.email), '') ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$'
    union all
    select jsonb_build_object('email', btrim(s.finance_email), 'name', null, 'role', null, 'finance', true, 'billing', false), 1
      from public.suppliers s where s.id = p_supplier and coalesce(btrim(s.finance_email), '') ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$'
       and lower(btrim(s.finance_email)) is distinct from lower(btrim(coalesce(s.email, '')))) o
$$;
revoke all on function public.email_supplier_options(uuid) from public, anon, authenticated;

create or replace function public.email_parties()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('whatsapp', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true,
    'clients', case when public.allowed('clients.contacts', 'view') then coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'code', c.client_code, 'stage', c.stage)
                 order by c.client_code nulls last, lower(c.name))
                 from public.clients c
                where public.client_seen(c.id, 'view')
                  and (coalesce(btrim(c.finance_email), '') ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$'
                       or exists (select 1 from public.client_contacts k where k.client_id = c.id and k.archived_at is null
                                    and coalesce(btrim(k.email), '') ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$'))), '[]'::jsonb)
                 else '[]'::jsonb end,
    'suppliers', case when public.allowed('suppliers', 'view') then coalesce((
                 select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'code', s.code) order by s.code)
                   from public.suppliers s
                  where s.status <> 'inactive'
                    and (coalesce(btrim(s.email), '') ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' or coalesce(btrim(s.finance_email), '') ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$')), '[]'::jsonb)
                 else '[]'::jsonb end);
end $$;
revoke all on function public.email_parties() from public, anon;
grant execute on function public.email_parties() to authenticated;

create or replace function public.email_recipients(p_client uuid, p_supplier uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('whatsapp', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_client is not null then
    if not public.allowed('clients.contacts', 'view') then return jsonb_build_object('error', 'denied'); end if;
    if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    return jsonb_build_object('ok', true, 'options', public.invoice_recipient_options(p_client, null));
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
  if exists (select 1 from public.team_emails x where x.sent_by = me.id and x.idem = p_idem) then
    return jsonb_build_object('error', 'again');
  end if;
  if (select count(*) from public.team_emails x where x.sent_by = me.id and x.created_at > now() - interval '24 hours') >= 100 then
    return jsonb_build_object('error', 'too-many');
  end if;
  if p_audience = 'client' then
    if not public.allowed('clients.contacts', 'view') then return jsonb_build_object('error', 'denied'); end if;
    select * into c from public.clients x where x.id = p_client;
    if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    opts := public.invoice_recipient_options(c.id, null);
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
           'contact name', v_who, 'client name', coalesce(c.name, ''), 'company name', coalesce(nullif(c.legal_name, ''), c.name, su.name, ''),
           'supplier name', coalesce(su.name, ''), 'sender name', me.name)), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(coalesce(p_body, ''), jsonb_build_object(
           'contact name', v_who, 'client name', coalesce(c.name, ''), 'company name', coalesce(nullif(c.legal_name, ''), c.name, su.name, ''),
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
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'email.sent',
          coalesce((select c.name from public.clients c where c.id = e.client_id), (select s.name from public.suppliers s where s.id = e.supplier_id), e.to_email),
          e.subject || case p_status when 'sent' then ' · emailed to ' when 'unknown' then ' · emailed, not confirmed, to ' else ' · not emailed to ' end ||
          e.to_email || coalesce(', copy to ' || e.cc_email, '') || coalesce(' · ' || e.attachment, ''));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.email_new_done(uuid, text, text, text) from public, anon;
grant execute on function public.email_new_done(uuid, text, text, text) to authenticated;

create or replace function public.supplier_email_status(p_provider text, p_event text, p_at timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e    public.supplier_emails;
  i    public.invoice_emails;
  ce   public.client_emails;
  te   public.team_emails;
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
  select * into te from public.team_emails x where x.provider_id = p_provider for update;
  if te.id is not null then
    update public.team_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st <> 'bounced' then p_at end),
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
  update public.team_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_sweep() from public, anon, authenticated;

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
     where e.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.team_emails_of(uuid) from public, anon;
grant execute on function public.team_emails_of(uuid) to authenticated;

create or replace function public.supplier_emails_of(p_supplier uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(x.r order by x.at desc) from (
      select jsonb_build_object('id', e.id, 'purpose', e.purpose, 'to', e.to_email, 'cc', e.cc_email,
               'subject', e.subject, 'status', e.status, 'error', e.error, 'created_at', e.created_at,
               'delivered_at', e.delivered_at, 'opened_at', e.opened_at, 'bounced_at', e.bounced_at,
               'by', m.name, 'document', d.serial) as r, e.created_at as at
        from public.supplier_emails e
        left join public.team_members m on m.id = e.sent_by
        left join public.documents d on d.id = e.document_id
       where e.supplier_id = p_supplier
      union all
      select jsonb_build_object('id', e.id, 'purpose', 'message', 'to', e.to_email, 'cc', e.cc_email,
               'subject', e.subject, 'status', e.status, 'error', e.error, 'created_at', e.created_at,
               'delivered_at', e.delivered_at, 'opened_at', e.opened_at, 'bounced_at', e.bounced_at,
               'by', m.name, 'document', e.attachment), e.created_at
        from public.team_emails e
        left join public.team_members m on m.id = e.sent_by
       where e.supplier_id = p_supplier) x), '[]'::jsonb));
end $$;
revoke all on function public.supplier_emails_of(uuid) from public, anon;
grant execute on function public.supplier_emails_of(uuid) to authenticated;

/* An email's addresses and words are cleared a year after it was sent, as a
   WhatsApp message's number is (PDPA 2010): the row stays, with its subject,
   status and times, so the log still says what went and when. */
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
  return n;
end $$;
revoke all on function public.mail_retention() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: emails are cleared a year on only by hand.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'mail-retention';
  perform cron.schedule('mail-retention', '45 19 1 * *', 'select public.mail_retention()');
end $$;

-- END OF NEW EMAIL

select public.functions_tidy();
