-- ===========================================================================
-- OVERDUE INVOICE REMINDERS — overdue invoices read from Bukku, and a
-- reminder emailed to a client by hand (2026-10-28)
-- ===========================================================================
-- WHY (the user, 2026-10-28: "pull those overdues data from bukku and inside
-- Portal and selectively send by users"; Bukku's own reminder is "fully
-- bukku labeled ... unprofessional"; replies go to einvoice@; the mockups
-- approved, WhatsApp held back): the team chased overdue invoices through a
-- Claude page, a Jotform letter and the Resend connector.
--
-- WHAT IT ADDS
--   * `invoice_emails`: every reminder sent, to whom, by whom, the invoices
--     it named (Bukku's ids, numbers and amounts as read at the send), its
--     words as sent and what Resend said of it. Kept when the client goes
--     (the link set null). Supplier emails keep their own table; Resend's
--     webhook (`supplier_email_status`, restated below) now finds an email
--     in either, so delivery is recorded in one function.
--   * `invoice_email_template`: the reminder's two subjects, its message
--     (holding `{invoices}`, where the table of invoices goes), the legal
--     note and the disclaimer; seeded once, edited at Business settings
--     (`invoice_email_template_save`, filed `team.changed` under Overdue
--     reminder), read at Clients: Billing View.
--   * `invoice_scope()` (Clients: Billing View): who is asking, whether they
--     see every client (`all`, so a Bukku contact linked to no client is
--     theirs too) and may send (Clients: Billing Work), and each Bukku
--     contact linked to a client they see, with that client's recipient:
--     the billing contact (else the main contact) with their salutation,
--     its email, the finance email to copy and the registered name.
--   * `invoice_reminders(p_contacts)` (Clients: Billing View): the reminders
--     sent to those Bukku contacts, newest first, held to the same scope.
--   * `invoice_email_begin` and `invoice_email_done`, the service role's
--     alone: bukku-sync calls them after checking the colleague through
--     `invoice_scope` and reading the invoices from Bukku itself, so a page
--     can never file a reminder or name its figures. Begin takes the
--     contact's lock first, so two colleagues pressing Send together send
--     once (`sending`), and refuses `recent` within `wa_repeat_hours`
--     unless asked again.
--
-- ORDER: this file (connector), then bukku-sync and supplier-mail (both
-- with _shared/mail.ts), then the pages. A page served before draws no
-- Overdue invoices. Safe to run twice.
--
-- ROLLBACK: supplier_email_status as schema.sql defined it before this
-- banner, then in the SQL Editor:
--   drop function if exists public.invoice_email_done(uuid, text, text, text);
--   drop function if exists public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean);
--   drop function if exists public.invoice_reminders(bigint[]);
--   drop function if exists public.invoice_scope();
--   drop function if exists public.invoice_recipient(uuid);
--   drop function if exists public.invoice_email_template_save(text, text, text, text, text);
--   drop function if exists public.invoice_email_template_get();
--   drop table if exists public.invoice_email_template;
--   drop table if exists public.invoice_emails;
-- ===========================================================================

create table if not exists public.invoice_emails (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid references public.clients(id) on delete set null,
  bukku_contact bigint not null,
  client_name   text not null,
  invoices      jsonb not null,
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
create index if not exists invoice_emails_contact_idx on public.invoice_emails (bukku_contact, created_at desc);
create index if not exists invoice_emails_client_idx on public.invoice_emails (client_id, created_at desc);
create unique index if not exists invoice_emails_provider_idx on public.invoice_emails (provider_id) where provider_id is not null;
alter table public.invoice_emails enable row level security;
revoke all on table public.invoice_emails from public, anon, authenticated;

create table if not exists public.invoice_email_template (
  id            int primary key default 1 check (id = 1),
  subject_one   text not null,
  subject_many  text not null,
  body          text not null,
  legal         text not null default '',
  disclaimer    text not null default '',
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.team_members(id) on delete set null
);
alter table public.invoice_email_template enable row level security;
revoke all on table public.invoice_email_template from public, anon, authenticated;

insert into public.invoice_email_template (id, subject_one, subject_many, body, legal, disclaimer)
select 1, 'Payment reminder · Invoice {invoice no}', 'Payment reminder · {count} overdue invoices',
  E'Dear {contact name},\n\nThis is a reminder that payment of {total} for {client} is now overdue.\n\n{invoices}\n\nWe would be grateful if payment could be arranged at your earliest convenience. If payment has already been made, please disregard this email.\n\nShould you have any questions, please reply to this email.\n\nThank you for your continued support.\n\n{sign off},\nADspace Finance',
  'Legal note: All services rendered will be invoiced accordingly unless a written cancellation is provided and acknowledged in advance. All invoices must be settled promptly to avoid overdue interest charges.',
  'This email and any attachment are private and confidential and intended solely for the addressee. If you have received it in error, please notify einvoice@adspacestudios.com and delete it. Any use, copying or disclosure by anyone else is not permitted.'
where not exists (select 1 from public.invoice_email_template);

/* Who a client's reminder goes to: the billing contact, else the live main
   contact, with their salutation; the finance email to copy where it
   differs; the registered name, else the brand. Internal. */
create or replace function public.invoice_recipient(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients;
  k public.client_contacts;
begin
  select * into c from public.clients x where x.id = p_client;
  if c.id is null then return null; end if;
  select * into k from public.client_contacts x
   where x.client_id = c.id and x.archived_at is null and (x.id = c.bill_contact_id or x.is_primary)
   order by (x.id = c.bill_contact_id) desc limit 1;
  return jsonb_build_object(
    'name', nullif(btrim(concat_ws(' ', nullif(btrim(coalesce(k.salutation, '')), ''), btrim(coalesce(k.name, '')))), ''),
    'email', nullif(btrim(coalesce(k.email, '')), ''),
    'cc', case when nullif(btrim(coalesce(c.finance_email, '')), '') is not null
                and lower(btrim(c.finance_email)) is distinct from lower(btrim(coalesce(k.email, '')))
               then btrim(c.finance_email) end,
    'company', coalesce(nullif(btrim(coalesce(c.legal_name, '')), ''), c.name));
end $$;
revoke all on function public.invoice_recipient(uuid) from public, anon, authenticated;

create or replace function public.invoice_scope()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('clients.billing', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true,
    'me', jsonb_build_object('id', me.id, 'name', me.name),
    'all', public.client_scope_free('view'),
    'send', public.allowed('clients.billing', 'work'),
    'links', coalesce((
      select jsonb_agg(jsonb_build_object('contact', l.contact_id, 'client', c.id, 'name', c.name, 'code', c.client_code,
               'slug', c.slug, 'stage', c.stage, 'to', public.invoice_recipient(c.id)) order by c.name)
        from (select distinct on (x.contact_id) x.contact_id, x.client_id
                from (select b.contact_id, b.record_id as client_id, 0 as pref
                        from public.bukku_links b where b.kind = 'client'
                      union all
                      select b.contact_id, s.client_id, 1
                        from public.bukku_links b join public.suppliers s on s.id = b.record_id
                       where b.kind = 'supplier' and s.client_id is not null) x
               order by x.contact_id, x.pref) l
        join public.clients c on c.id = l.client_id
       where public.client_seen(c.id, 'view')), '[]'::jsonb));
end $$;
revoke all on function public.invoice_scope() from public, anon;
grant execute on function public.invoice_scope() to authenticated;

create or replace function public.invoice_reminders(p_contacts bigint[])
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_all boolean;
begin
  if me.id is null or not public.allowed('clients.billing', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  v_all := public.client_scope_free('view');
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(r order by (r->>'at') desc) from (
      select jsonb_build_object('id', e.id, 'contact', e.bukku_contact, 'client', e.client_id,
               'invoices', e.invoices, 'to', e.to_email, 'cc', e.cc_email, 'subject', e.subject,
               'status', e.status, 'error', e.error, 'at', e.created_at, 'delivered_at', e.delivered_at,
               'opened_at', e.opened_at, 'bounced_at', e.bounced_at, 'by', m.name) as r
        from public.invoice_emails e
        left join public.team_members m on m.id = e.sent_by
       where e.bukku_contact = any(coalesce(p_contacts, '{}'::bigint[]))
         and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
       order by e.created_at desc
       limit 500) q), '[]'::jsonb));
end $$;
revoke all on function public.invoice_reminders(bigint[]) from public, anon;
grant execute on function public.invoice_reminders(bigint[]) to authenticated;

create or replace function public.invoice_email_template_get()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t public.invoice_email_template;
begin
  if (public.ops_me()).id is null or not (public.allowed('clients.billing', 'view') or public.ops_granted('team.settings', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into t from public.invoice_email_template x where x.id = 1;
  return jsonb_build_object('ok', true, 'subject_one', t.subject_one, 'subject_many', t.subject_many, 'body', t.body,
    'legal', t.legal, 'disclaimer', t.disclaimer, 'updated_at', t.updated_at,
    'updated_by', (select m.name from public.team_members m where m.id = t.updated_by));
end $$;
revoke all on function public.invoice_email_template_get() from public, anon;
grant execute on function public.invoice_email_template_get() to authenticated;

create or replace function public.invoice_email_template_save(p_subject_one text, p_subject_many text, p_body text,
  p_legal text, p_disclaimer text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.invoice_email_template;
  v_1 text := btrim(regexp_replace(coalesce(p_subject_one, ''), '\s+', ' ', 'g'));
  v_n text := btrim(regexp_replace(coalesce(p_subject_many, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  v_l text := btrim(regexp_replace(coalesce(p_legal, ''), '\s+', ' ', 'g'));
  v_d text := btrim(regexp_replace(coalesce(p_disclaimer, ''), '\s+', ' ', 'g'));
  moved text[] := '{}';
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_1) < 2 or length(v_1) > 200 or length(v_n) < 2 or length(v_n) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  if length(v_l) > 1000 or length(v_d) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into t from public.invoice_email_template x where x.id = 1 for update;
  if t.subject_one is distinct from v_1 then moved := moved || ('Subject, one invoice: ' || t.subject_one || ' → ' || v_1); end if;
  if t.subject_many is distinct from v_n then moved := moved || ('Subject, several invoices: ' || t.subject_many || ' → ' || v_n); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if t.legal is distinct from v_l then moved := moved || 'Legal note'::text; end if;
  if t.disclaimer is distinct from v_d then moved := moved || 'Disclaimer'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.invoice_email_template x set subject_one = v_1, subject_many = v_n, body = v_b, legal = v_l,
    disclaimer = v_d, updated_at = now(), updated_by = me.id where x.id = 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Overdue reminder', array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.invoice_email_template_save(text, text, text, text, text) from public, anon;
grant execute on function public.invoice_email_template_save(text, text, text, text, text) to authenticated;

/* An amount as the portal writes it: RM or S$, two decimals, the sign
   held to its figure (a no-break space), so a line never parts them. */
create or replace function public.invoice_money(p_amount numeric, p_currency text)
returns text
language sql immutable set search_path = public as $$
  select case upper(coalesce(p_currency, 'MYR')) when 'MYR' then 'RM' when 'SGD' then 'S$' else upper(p_currency) end
         || chr(160) || to_char(round(coalesce(p_amount, 0), 2), 'FM999,999,999,990.00')
$$;
revoke all on function public.invoice_money(numeric, text) from public, anon, authenticated;

/* A reminder filed before it goes (bukku-sync, the service role, after it
   checked the colleague through invoice_scope and read the invoices from
   Bukku itself). The contact's lock is taken first: a send already going
   to it answers `sending`, one made within the window `recent` unless
   asked again. The words are the colleague's, every {field} filled here. */
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
  v_who := coalesce(rcp->>'name', v_co);
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
  values (coalesce(m.name, 'system'), 'client.edited', e.client_name,
          'Overdue reminder ' ||
          case p_status when 'sent' then 'emailed to ' when 'unknown' then 'emailed, not confirmed, to ' else 'not emailed to ' end ||
          e.to_email || coalesce(', cc ' || e.cc_email, '') || ' · ' ||
          (select string_agg(x->>'number', ', ') from jsonb_array_elements(e.invoices) x));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.invoice_email_done(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.invoice_email_done(uuid, text, text, text) to service_role;

/* Resend's word on a sent email (supplier-mail, its webhook, the service
   role): delivered, opened, bounced or complained, a supplier's email or
   an overdue reminder alike. A later word never steps back: an opened
   email is never delivered again, a bounce stays. */
create or replace function public.supplier_email_status(p_provider text, p_event text, p_at timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e    public.supplier_emails;
  i    public.invoice_emails;
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

-- END OF OVERDUE INVOICE REMINDERS ------------------------------------------

select public.functions_tidy();
