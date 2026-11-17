-- ===========================================================================
-- EVERY EMAIL IN MESSAGES (2026-11-17)
-- ===========================================================================
-- WHY: the user, 2026-11-17: "The email sent out from Hiring did not log
-- inside Messages. All outgoing WhatsApp messages and emails should be
-- logged inside." Reply-to goes to a company mailbox, never a colleague's
-- own address, and every system sender is noreply-{section}@sc.adspace.me.
--
-- WHAT IT CHANGES
--   * `system_emails` (RLS on, no policy, no grant): the emails no other log
--     keeps, filed by their edge function after Resend answers
--     (`system_email_file`, the service role's): hiring-mail's invitation,
--     confirmation, outcome, document and code (the code's words never
--     kept), and invite-member's invitations (a colleague's and a client
--     contact's). Resend's word reaches it through `supplier_email_status`;
--     `mail_retention` clears its address and words after 12 months.
--   * `mail_log` lists them: hiring at the candidate's own access
--     (`hiring_role`), a colleague's invitation at Team View, a client's at
--     Clients: Contacts View on a client in scope; it answers `senders`.
--   * `mail_boxes` (General, Accounts payable, Finance, e-Invoice) and
--     `mail_senders` (a section each: its name, its noreply address and
--     the mailbox it replies to; RLS on, no policy, no grant), seeded once.
--     `mail_sender(p_key)` (the service role's) is what each edge function
--     sends from; `mail_senders_read()` the team's; `mail_boxes_set(p_values)`
--     (`team.settings`, Settings, Messages: Reply-to mailboxes), filed
--     `team.changed` under Email addresses from and to.
--
-- ORDER: this file (connector), then the edge functions (each reads
-- `mail_sender`, else its own fallback), then the pages. Safe to run twice.
--
-- ROLLBACK: drop the five functions and the three tables; run the MAIL LOG
-- and RESEND STATUS bands of CREATOR PAYMENT DETAILS again.

create table if not exists public.mail_boxes (
  key     text primary key check (key in ('general', 'payables', 'finance', 'einvoice')),
  label   text not null,
  address text not null check (address ~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$')
);
alter table public.mail_boxes enable row level security;
revoke all on public.mail_boxes from public, anon, authenticated;
insert into public.mail_boxes (key, label, address)
select v.k, v.l, v.a from (values
  ('general', 'General', 'advertise@adspacestudios.com'),
  ('payables', 'Accounts payable', 'ap@adspacestudios.com'),
  ('finance', 'Finance', 'finance@adspacestudios.com'),
  ('einvoice', 'e-Invoice', 'einvoice@adspacestudios.com')) v(k, l, a)
 where not exists (select 1 from public.mail_boxes);

create table if not exists public.mail_senders (
  key     text primary key,
  name    text not null,
  address text not null check (address ~ '^noreply-[a-z]+@(sc|br|rs)\.adspace\.me$'),
  box     text not null references public.mail_boxes(key)
);
alter table public.mail_senders enable row level security;
revoke all on public.mail_senders from public, anon, authenticated;
insert into public.mail_senders (key, name, address, box)
select v.k, v.n, v.a, v.b from (values
  ('clients', 'ADspace', 'noreply-clients@sc.adspace.me', 'general'),
  ('suppliers', 'ADspace', 'noreply-suppliers@sc.adspace.me', 'payables'),
  ('creators', 'ADspace', 'noreply-creators@sc.adspace.me', 'payables'),
  ('careers', 'ADspace', 'noreply-careers@sc.adspace.me', 'general'),
  ('finance', 'ADspace Finance', 'noreply-finance@sc.adspace.me', 'finance'),
  ('team', 'ADspace Digital Portal', 'noreply-team@sc.adspace.me', 'general')) v(k, n, a, b)
 where not exists (select 1 from public.mail_senders);

create or replace function public.mail_sender(p_key text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('from', m.name || ' <' || m.address || '>', 'reply_to', b.address)
    from public.mail_senders m join public.mail_boxes b on b.key = m.box
   where m.key = p_key;
$$;
revoke all on function public.mail_sender(text) from public, anon, authenticated;
grant execute on function public.mail_sender(text) to service_role;

create or replace function public.mail_senders_read()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_team() then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'boxes', (select jsonb_agg(jsonb_build_object('key', b.key, 'label', b.label, 'address', b.address)
                order by array_position(array['general', 'payables', 'finance', 'einvoice'], b.key)) from public.mail_boxes b),
    'senders', (select jsonb_object_agg(m.key, jsonb_build_object('from', m.name || ' <' || m.address || '>', 'reply_to', b.address))
                  from public.mail_senders m join public.mail_boxes b on b.key = m.box));
end $$;
revoke all on function public.mail_senders_read() from public, anon;
grant execute on function public.mail_senders_read() to authenticated;

create or replace function public.mail_boxes_set(p_values jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  b  public.mail_boxes;
  v  text;
  v_said text[] := '{}';
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  for b in select * from public.mail_boxes order by array_position(array['general', 'payables', 'finance', 'einvoice'], key) loop
    v := lower(btrim(coalesce(p_values ->> b.key, b.address)));
    if v !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then return jsonb_build_object('error', 'bad-email', 'field', b.key); end if;
    if v is distinct from b.address then
      update public.mail_boxes x set address = v where x.key = b.key;
      v_said := v_said || (b.label || ': ' || b.address || ' → ' || v);
    end if;
  end loop;
  if array_length(v_said, 1) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Email addresses', array_to_string(v_said, ' · '));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.mail_boxes_set(jsonb) from public, anon;
grant execute on function public.mail_boxes_set(jsonb) to authenticated;

create table if not exists public.system_emails (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null check (kind in ('hiring_invite', 'hiring_confirm', 'hiring_pool', 'hiring_not', 'hiring_doc',
                                             'hiring_code', 'invite_team', 'invite_client')),
  candidate_id uuid,
  client_id    uuid,
  to_email     text not null default '',
  to_name      text,
  subject      text not null default '',
  body         text,
  reference    text,
  sent_by      uuid,
  status       text not null default 'sent',
  provider_id  text,
  error        text,
  created_at   timestamptz not null default now(),
  sent_at      timestamptz,
  delivered_at timestamptz,
  opened_at    timestamptz,
  bounced_at   timestamptz
);
alter table public.system_emails enable row level security;
revoke all on public.system_emails from public, anon, authenticated;
create index if not exists system_emails_created_idx on public.system_emails (created_at);
create index if not exists system_emails_provider_idx on public.system_emails (provider_id) where provider_id is not null;

/* Filed by its edge function after Resend answers, as the service role:
   the sender by the email it signed in with, the candidate found from the
   interview, document or candidate the email was about. */
create or replace function public.system_email_file(p jsonb)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_ref  uuid := nullif(p ->> 'ref', '')::uuid;
  v_cand uuid;
  v_id   uuid;
begin
  if v_ref is not null and (p ->> 'kind') like 'hiring%' then
    v_cand := coalesce((select i.candidate_id from public.hiring_interviews i where i.id = v_ref),
                       (select d.candidate_id from public.hiring_docs d where d.id = v_ref),
                       (select c.id from public.hiring_candidates c where c.id = v_ref));
  end if;
  insert into public.system_emails (kind, candidate_id, client_id, to_email, to_name, subject, body, reference, sent_by,
                                    status, provider_id, error, sent_at)
  values (p ->> 'kind', v_cand, nullif(p ->> 'client', '')::uuid, coalesce(p ->> 'to', ''), nullif(p ->> 'to_name', ''),
          coalesce(p ->> 'subject', ''), nullif(p ->> 'body', ''), nullif(p ->> 'reference', ''),
          (select t.id from public.team_members t where nullif(p ->> 'by', '') is not null
              and lower(t.email) = lower(p ->> 'by') order by t.active desc limit 1),
          coalesce(nullif(p ->> 'status', ''), 'sent'), nullif(p ->> 'provider', ''), nullif(p ->> 'error', ''),
          case when coalesce(p ->> 'status', 'sent') = 'sent' then now() end)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.system_email_file(jsonb) from public, anon, authenticated;
grant execute on function public.system_email_file(jsonb) to service_role;

create or replace function public.supplier_email_status(p_provider text, p_event text, p_at timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e    public.supplier_emails;
  i    public.invoice_emails;
  ce   public.client_emails;
  te   public.team_emails;
  cm   public.creator_emails;
  se   public.system_emails;
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
  select * into cm from public.creator_emails x where x.provider_id = p_provider for update;
  if cm.id is not null then
    update public.creator_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = cm.id;
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
  select * into se from public.system_emails x where x.provider_id = p_provider for update;
  if se.id is not null then
    update public.system_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = se.id;
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
  update public.creator_emails x set to_email = '', body = ''
   where x.created_at < now() - interval '12 months' and x.status not in ('queued', 'sending') and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  update public.system_emails x set to_email = '', to_name = null, body = null
   where x.created_at < now() - interval '12 months' and (x.to_email <> '' or x.body is not null);
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
     set detail = regexp_replace(x.detail, '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+', '(address deleted)', 'g')
   where x.action in ('email.sent', 'client.edited', 'supplier.edited') and x.created_at < now() - interval '12 months'
     and (x.action = 'email.sent' or x.detail ~ '(^| )(not )?emailed(, not confirmed,| \(not confirmed\))? to ')
     and x.detail ~ '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_retention() from public, anon, authenticated;

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
  v_cr   boolean;
  v_team boolean;
  v_con  boolean;
begin
  if me.id is null or not public.allowed('whatsapp', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_a := v_from::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_b := (v_from + interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_sup := public.allowed('suppliers', 'view');
  v_bill := public.allowed('clients.billing', 'view');
  v_quo := public.allowed('clients.quotes', 'view');
  v_all := public.client_scope_free('view');
  v_cr := public.allowed('campaigns.creators', 'view');
  v_team := public.allowed('team', 'view');
  v_con := public.allowed('clients.contacts', 'view');
  return jsonb_build_object(
    'month', v_from,
    'senders', (select jsonb_object_agg(m.key, m.name || ' <' || m.address || '>') from public.mail_senders m),
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
          select 'creator', e.id, 'creator_' || e.purpose, e.to_email, null, e.subject, e.body,
                 null, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 null, null, null, null, null,
                 r.ref, k.name
            from public.creator_emails e
            left join public.creators k on k.id = e.creator_id
            left join public.creator_pay_requests r on r.id = e.request_id
           where v_cr and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'system', e.id, e.kind, e.to_email, null, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, null, null, null,
                 e.reference, e.to_name
            from public.system_emails e
            left join public.clients c on c.id = e.client_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and (case when e.kind like 'hiring%' then public.hiring_role(e.candidate_id) is not null
                       when e.kind = 'invite_team' then v_team
                       when e.kind = 'invite_client' then v_con and e.client_id is not null and public.client_seen(e.client_id, 'view')
                       else false end)
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

select public.functions_tidy();
