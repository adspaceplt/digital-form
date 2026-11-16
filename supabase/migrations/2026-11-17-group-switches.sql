-- ============================================================================
-- GROUP SWITCHES (2026-11-17)
-- ============================================================================
-- The access restructure, release 1 (the user, 2026-11-17: "approved, go
-- ahead and build all steps", plan version 4).
--
-- One rule, top to bottom: a portal switch (Business settings: AI, Email,
-- WhatsApp), then the group's switches (Use AI, Send email, Send WhatsApp,
-- Sensitive details, Clients they see), then the section's level, then a
-- tab's, which never exceeds its section.
--
--   * team_roles holds ai_on, email_on, whatsapp_on, sensitive_on and
--     reports_to; team_role_defaults copies the four switches onto each
--     colleague as it copies the access map. An admin holds every one.
--   * app_settings holds ai_on, email_on and whatsapp_on (1 from the start):
--     off stops every AI use, email or WhatsApp for everyone. The narrower
--     switches standing (Automatic emails, Automatic WhatsApp, Send by
--     email) stay under them.
--   * allowed(): a tab's level never exceeds its section's (a granted part
--     aside, which widens); client billing, creator payments and supplier
--     bank details answer only where Sensitive details is on, and the two
--     payment parts follow their section's level.
--   * ai_cap() answers 0 where AI is off for the portal or the group, so
--     every Write with AI refuses as stopped.
--   * Every send asks its switch (send_ok): WhatsApp in wa_may_send and a
--     quotation sent on WhatsApp; email in each email's prepare or begin;
--     an automatic send asks the portal switch (auto_send_on).
--   * access_keys lists every key the rule reads, its tier and what it
--     holds; the page's lists and the stand-in are held equal to it.
--
-- Backfilled as plan section 4: Admin every switch; Managers all four;
-- Members Use AI and Sensitive details; Ads Use AI; Business Development
-- Sensitive details. Reports to: Managers to Admin; Members, Ads and
-- Business Development to Managers. Members' Content sets stored at Full
-- Access under Content Review at Manage is taken back to the section.
--
-- Safe to run twice. Rollback: restore allowed, ops_granted, ai_cap,
-- wa_may_send, auto_send_on and the email and quotation functions from
-- 2026-11-17-access-security-fixes.sql and their own bands; drop the
-- columns, access_keys and the functions added here.

alter table public.team_roles add column if not exists ai_on boolean not null default false;
alter table public.team_roles add column if not exists email_on boolean not null default false;
alter table public.team_roles add column if not exists whatsapp_on boolean not null default false;
alter table public.team_roles add column if not exists sensitive_on boolean not null default false;
alter table public.team_roles add column if not exists reports_to text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'team_roles_reports_to_fkey') then
    alter table public.team_roles add constraint team_roles_reports_to_fkey
      foreign key (reports_to) references public.team_roles (slug) on update cascade on delete set null;
  end if;
end $$;
alter table public.team_members add column if not exists ai_on boolean not null default false;
alter table public.team_members add column if not exists email_on boolean not null default false;
alter table public.team_members add column if not exists whatsapp_on boolean not null default false;
alter table public.team_members add column if not exists sensitive_on boolean not null default false;

/* A group never reports to itself, nor round to itself. */
create or replace function public.team_roles_reports_to_check()
returns trigger language plpgsql set search_path = public as $$
declare v text := new.reports_to; n int := 0;
begin
  if new.reports_to is null then return new; end if;
  while v is not null and n < 50 loop
    if v = new.slug then raise exception 'reports-loop' using errcode = '23514',
      hint = 'A group cannot report to itself or to a group that reports to it.'; end if;
    select r.reports_to into v from public.team_roles r where r.slug = v;
    n := n + 1;
  end loop;
  return new;
end $$;
revoke all on function public.team_roles_reports_to_check() from public, anon, authenticated;
create or replace trigger team_roles_reports_to_check before insert or update of reports_to, slug on public.team_roles
  for each row execute function public.team_roles_reports_to_check();

create or replace function public.team_role_defaults()
returns trigger language plpgsql as $$
declare r public.team_roles;
begin
  /* The console's minute stamps when a colleague was last active; that
     alone is no change to their record (A COLLEAGUE'S LAST SIGN-IN). */
  if tg_op = 'UPDATE' and new.last_seen_at is distinct from old.last_seen_at
     and (to_jsonb(new) - 'last_seen_at') = (to_jsonb(old) - 'last_seen_at') then
    return new;
  end if;
  select * into r from public.team_roles where slug = new.role;
  if r.slug is null then
    select * into r from public.team_roles where slug = 'account';
    new.role := 'account';
  end if;
  new.is_admin      := r.is_admin;
  new.can_clients   := r.can_clients;   new.can_review   := r.can_review;
  new.can_campaigns := r.can_campaigns; new.can_links    := r.can_links;
  new.can_activity  := r.can_activity;  new.can_billing  := r.can_billing;
  new.can_remove    := r.can_remove;    new.can_doc_void := r.can_doc_void;
  new.access        := coalesce(r.access, '{}'::jsonb);
  new.client_scope  := coalesce(r.client_scope, 'all');
  /* The group's switches (GROUP SWITCHES, 2026-11-17); an admin holds all. */
  new.ai_on         := coalesce(r.is_admin, false) or coalesce(r.ai_on, false);
  new.email_on      := coalesce(r.is_admin, false) or coalesce(r.email_on, false);
  new.whatsapp_on   := coalesce(r.is_admin, false) or coalesce(r.whatsapp_on, false);
  new.sensitive_on  := coalesce(r.is_admin, false) or coalesce(r.sensitive_on, false);
  new.updated_at    := now();
  return new;
end $$;

/* Section 4 of the plan, once: while no group holds a switch (the columns
   just added), so a group an admin has since set keeps its own. */
do $$
begin
  if not exists (select 1 from public.team_roles where ai_on or email_on or whatsapp_on or sensitive_on) then
    update public.team_roles set ai_on = true, email_on = true, whatsapp_on = true, sensitive_on = true
     where is_admin or slug = 'admin';
    update public.team_roles set ai_on = true, email_on = true, whatsapp_on = true, sensitive_on = true,
           reports_to = 'admin' where slug = 'managers';
    update public.team_roles set ai_on = true, sensitive_on = true, reports_to = 'managers',
           access = access - 'review.sets' where slug = 'account';
    update public.team_roles set ai_on = true, reports_to = 'managers' where slug = 'marketing-ads';
    update public.team_roles set sensitive_on = true, reports_to = 'managers' where slug = 'sales-executive';
  end if;
end $$;
update public.team_members set role = role;

/* The portal's three switches, on from the start. */
insert into public.app_settings (key, from_date, value)
select k, date '2023-08-14', 1 from unnest(array['ai_on', 'email_on', 'whatsapp_on']) k
on conflict (key, from_date) do nothing;

create or replace function public.portal_on(p_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.app_setting(p_key, (now() at time zone 'Asia/Kuala_Lumpur')::date), 1) = 1
$$;
revoke all on function public.portal_on(text) from public, anon, authenticated;

create or replace function public.team_switch_of(p_member uuid, p_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select case when t.is_admin or t.role = 'admin' then true else case p_key
      when 'ai_on' then t.ai_on when 'email_on' then t.email_on when 'whatsapp_on' then t.whatsapp_on
      when 'sensitive_on' then t.sensitive_on else false end end
    from public.team_members t where t.id = p_member and t.active), false)
$$;
revoke all on function public.team_switch_of(uuid, text) from public, anon, authenticated;

/* Whether the caller may send by email or WhatsApp now: the portal's switch
   and the group's. */
create or replace function public.send_ok(p_channel text)
returns boolean language sql stable security definer set search_path = public as $$
  select p_channel in ('email', 'whatsapp') and public.portal_on(p_channel || '_on')
     and public.team_switch_of((public.ops_me()).id, p_channel || '_on')
$$;
revoke all on function public.send_ok(text) from public, anon, authenticated;

create or replace function public.send_ok_of(p_member uuid, p_channel text)
returns boolean language sql stable security definer set search_path = public as $$
  select p_channel in ('email', 'whatsapp') and public.portal_on(p_channel || '_on')
     and public.team_switch_of(p_member, p_channel || '_on')
$$;
revoke all on function public.send_ok_of(uuid, text) from public, anon, authenticated;

/* The portal's switches, set by Business settings (team.settings). */
create or replace function public.portal_switch_set(p_key text, p_on boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_was   numeric;
  v_to    numeric := case when coalesce(p_on, false) then 1 else 0 end;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_key is null or p_key not in ('ai_on', 'email_on', 'whatsapp_on') then return jsonb_build_object('error', 'bad-key'); end if;
  v_was := coalesce(public.app_setting(p_key, v_today), 1);
  if v_was is not distinct from v_to then return jsonb_build_object('ok', true); end if;
  insert into public.app_settings (key, from_date, value, set_by, set_at)
  values (p_key, v_today, v_to, me.id, now())
  on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Portal switches',
          case p_key when 'ai_on' then 'AI: ' when 'email_on' then 'Email: ' else 'WhatsApp: ' end ||
          case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_to = 1 then 'On' else 'Off' end ||
          ' · from ' || public.register_day(v_today));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.portal_switch_set(text, boolean) from public, anon;
grant execute on function public.portal_switch_set(text, boolean) to authenticated;

create or replace function public.allowed(p_section text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare
  t public.team_members;
  k text := lower(coalesce(p_section, ''));
  sv text;
  lv text;
begin
  select * into t from public.team_members x
    where lower(x.email) = lower(auth.jwt() ->> 'email') and x.active
      and (x.access_until is null or x.is_admin or x.role = 'admin'
           or public.team_access_ends(x.access_until, x.access_until_time) > now())
    limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  if not public.team_place_ok(false, t.id) then return false; end if;
  /* Sensitive details (GROUP SWITCHES, 2026-11-17). A part that widens its
     section (granted, the access_keys rows of that tier) is never capped. */
  if k in ('clients.billing', 'campaigns.pay', 'suppliers.pay') and not t.sensitive_on then return false; end if;
  lv := t.access ->> k;
  if position('.' in k) > 0 then
    sv := t.access ->> split_part(k, '.', 1);
    if k in ('campaigns.pay', 'suppliers.pay') or lv is null then lv := sv;
    elsif not (k = any (array['ops.all', 'ops.reports', 'ops.workflows', 'ops.time', 'ops.numbering', 'ops.override',
      'team.performance', 'team.perfadmin', 'team.settings', 'team.upgrade', 'team.invite', 'team.handbook',
      'team.announce', 'team.notice', 'team.analytics', 'team.personnel', 'team.hiring', 'reports.whitelabel',
      'reports.transfer', 'reports.ai', 'reports.meta', 'register.types', 'campaigns.files_delete', 'clients.vic']))
      and public.level_rank(lv) > public.level_rank(sv) then lv := sv;
    end if;
  end if;
  return public.level_rank(lv) >= public.level_rank(p_level);
end $$;
grant execute on function public.allowed(text, text) to authenticated;

create or replace function public.ops_granted(p_key text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
   where active and lower(email) = lower(auth.jwt() ->> 'email') limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  if t.access_until is not null
     and public.team_access_ends(t.access_until, t.access_until_time) <= now() then return false; end if;
  if not public.team_place_ok(false, t.id) then return false; end if;
  /* Creator payments and supplier bank details follow their section where
     Sensitive details is on (GROUP SWITCHES, 2026-11-17). */
  if p_key in ('campaigns.pay', 'suppliers.pay') then
    return t.sensitive_on and public.level_rank(t.access ->> split_part(p_key, '.', 1)) >= public.level_rank(p_level);
  end if;
  return public.level_rank(t.access ->> p_key) >= public.level_rank(p_level);
end $$;
grant execute on function public.ops_granted(text, text) to authenticated;

create or replace function public.ai_cap(p_member uuid, p_use text)
returns integer language sql stable security definer set search_path = public as $$
  select case when not public.portal_on('ai_on') or not public.team_switch_of(p_member, 'ai_on') then 0
    else coalesce(
      (select l.daily from public.ai_draft_limits l where l.scope = p_member::text || ':' || p_use),
      (select l.daily from public.ai_draft_limits l where l.scope = p_use),
      public.ai_cap_default(p_use)) end
$$;
revoke all on function public.ai_cap(uuid, text) from public, anon, authenticated;

create or replace function public.auto_send_on(p_kind text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.portal_on(case p_kind when 'email' then 'email_on' else 'whatsapp_on' end)
     and coalesce(public.app_setting(case p_kind when 'email' then 'auto_email_on' else 'auto_whatsapp_on' end,
                                     (now() at time zone 'Asia/Kuala_Lumpur')::date), 1) = 1
$$;
revoke all on function public.auto_send_on(text) from public, anon, authenticated;

/* A send on WhatsApp asks the switches, then the record it is about; the
   five WhatsApp parts are no longer read. */
create or replace function public.wa_may_send(p_purpose text, p_to_kind text)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.send_ok('whatsapp') and case p_purpose
    when 'report'   then public.allowed('reports', 'view')
    when 'feedback' then public.allowed('clients', 'view')
    when 'creator'  then public.allowed('campaigns', 'view')
    when 'approval' then p_to_kind = 'contact'
                         and (public.allowed('review.sets', 'view') or public.allowed('campaigns.campaigns', 'view'))
    when 'quotation' then p_to_kind = 'contact' and public.allowed('clients.quotes', 'view')
    when 'offer'    then p_to_kind = 'contact' and public.allowed('clients.documents', 'view')
    when 'representative' then p_to_kind = 'contact' and public.allowed('clients.leads', 'view')
    when 'message'  then case p_to_kind when 'contact' then public.allowed('clients.contacts', 'view')
                                        when 'creator' then public.allowed('campaigns.creators', 'view')
                                        else false end
    else false end
$$;
revoke all on function public.wa_may_send(text, text) from public, anon, authenticated;

/* Every key the rule reads: its tier and what it holds. The page's lists
   and the stand-in are held equal to it (tests/access.js). */
create table if not exists public.access_keys (
  key   text primary key,
  tier  text not null check (tier in ('portal', 'group', 'section', 'tab', 'granted')),
  label text not null,
  holds text not null default ''
);
alter table public.access_keys enable row level security;
revoke all on public.access_keys from public, anon, authenticated;
insert into public.access_keys (key, tier, label, holds) values
  ('ai_on', 'portal', 'AI', 'Write with AI, the Assistant and Draw with AI in every section'),
  ('email_on', 'portal', 'Email', 'Every email to clients, creators, suppliers and candidates'),
  ('whatsapp_on', 'portal', 'WhatsApp', 'Every WhatsApp template, sent by hand or automatically'),
  ('client_scope', 'group', 'Clients they see', 'All clients, or own clients only'),
  ('group.ai_on', 'group', 'Use AI', 'Write with AI, the Assistant and Draw with AI'),
  ('group.email_on', 'group', 'Send email', 'Emails sent by hand to clients, suppliers and others'),
  ('group.whatsapp_on', 'group', 'Send WhatsApp', 'WhatsApp templates sent by hand'),
  ('group.sensitive_on', 'group', 'Sensitive details', 'Client billing, creator payments and supplier bank details'),
  ('ops', 'section', 'My Work', ''), ('clients', 'section', 'Clients', ''), ('review', 'section', 'Content Review', ''),
  ('scripts', 'section', 'Video Scripts', ''), ('campaigns', 'section', 'Creator Campaigns', ''),
  ('reports', 'section', 'Reports', ''), ('whatsapp', 'section', 'Messages', ''), ('register', 'section', 'Documents', ''),
  ('suppliers', 'section', 'Suppliers', ''), ('links', 'section', 'Short Links', ''), ('services', 'section', 'Services', ''),
  ('team', 'section', 'Team', ''), ('activity', 'section', 'Activity record', ''),
  ('clients.billing', 'tab', 'Billing', 'Sensitive details'), ('campaigns.pay', 'tab', 'Creator payment details', 'Sensitive details'),
  ('suppliers.pay', 'tab', 'Supplier bank details', 'Sensitive details')
on conflict (key) do update set tier = excluded.tier, label = excluded.label, holds = excluded.holds;
insert into public.access_keys (key, tier, label)
select k, 'granted', k from unnest(array['ops.all', 'ops.reports', 'ops.workflows', 'ops.time', 'ops.numbering', 'ops.override',
    'team.performance', 'team.perfadmin', 'team.settings', 'team.upgrade', 'team.invite', 'team.handbook',
    'team.announce', 'team.notice', 'team.analytics', 'team.personnel', 'team.hiring', 'reports.whitelabel',
    'reports.transfer', 'reports.ai', 'reports.meta', 'register.types', 'campaigns.files_delete', 'clients.vic']) k
on conflict (key) do nothing;

/* Each send asks its switch first (send-off). */
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
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
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
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
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

create or replace function public.invoice_mail_begin(p_purpose text, p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean, p_to text, p_ccs text[])
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members;
  t      public.invoice_email_template;
  v_tpl  public.invoice_send_template;
  rcp    jsonb;
  opts   jsonb;
  pick   jsonb;
  inv    jsonb;
  hours  numeric;
  r      public.invoice_emails;
  v_n    int;
  v_k    int;
  v_m    int;
  v_d    int;
  v_to   text;
  v_cc   text;
  v_who  text;
  v_nm   boolean;
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
  if not public.send_ok_of(me.id, 'email') then return jsonb_build_object('error', 'send-off'); end if;
  if p_purpose is null or p_purpose not in ('reminder', 'invoice') then return jsonb_build_object('error', 'bad-request'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-request'); end if;
  if jsonb_typeof(p_invoices) <> 'array' or jsonb_array_length(p_invoices) < 1 or jsonb_array_length(p_invoices) > 50 then
    return jsonb_build_object('error', 'bad-invoices');
  end if;
  for inv in select value from jsonb_array_elements(p_invoices) loop
    if btrim(coalesce(inv->>'number', '')) = '' or coalesce(inv->>'number', '') !~ '^[^[:cntrl:]]{1,60}$' or coalesce(inv->>'currency', '') !~ '^[A-Z]{3}$'
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
     where x.bukku_contact = p_contact and x.purpose = p_purpose and x.status <> 'failed' and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
    if r.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', r.created_at, 'to', r.to_email,
        'by', (select m.name from public.team_members m where m.id = r.sent_by)));
    end if;
  end if;
  rcp := case when p_client is null then null else public.invoice_recipient_for(p_client, p_contact) end;
  /* The addresses chosen on the sheet: the client's own, nothing typed. */
  if p_to is not null or p_ccs is not null then opts := public.invoice_recipient_options(p_client, p_contact); end if;
  if p_to is not null then
    select x into pick from jsonb_array_elements(opts) x where lower(x->>'email') = lower(btrim(p_to)) limit 1;
    if pick is null then return jsonb_build_object('error', 'bad-recipient'); end if;
    v_to := pick->>'email';
    v_who := coalesce(pick->>'name', 'Sir or Madam');
    v_nm := pick->>'name' is not null;
  else
    v_to := coalesce(rcp->>'email', nullif(btrim(coalesce(p_email, '')), ''));
    v_who := coalesce(rcp->>'name', 'Sir or Madam');
    v_nm := rcp->>'name' is not null;
  end if;
  if v_to is null or v_to !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then return jsonb_build_object('error', 'no-email'); end if;
  if p_ccs is not null then
    select count(*), count(o.e), count(distinct lower(o.e)), count(*) filter (where lower(o.e) = lower(v_to)),
           string_agg(o.e, ', ' order by o.i)
      into v_k, v_m, v_d, v_n, v_cc
      from (select a.i, (select x->>'email' from jsonb_array_elements(opts) x where lower(x->>'email') = lower(btrim(a.v)) limit 1) as e
              from unnest(p_ccs) with ordinality as a (v, i)
             where nullif(btrim(coalesce(a.v, '')), '') is not null) o;
    if v_k > 5 or v_m <> v_k or v_d <> v_m or v_n > 0 then return jsonb_build_object('error', 'bad-copy'); end if;
  else
    v_cc := case when coalesce(p_cc, false) and lower(coalesce(rcp->>'cc', '')) <> lower(v_to) then rcp->>'cc' end;
  end if;
  v_co := coalesce(rcp->>'company', nullif(btrim(coalesce(p_name, '')), ''), 'Client');
  v_n := jsonb_array_length(p_invoices);
  select string_agg(public.invoice_money(s.amt, s.cur), ' and ' order by s.cur) into v_tot
    from (select x->>'currency' as cur, sum((x->>'amount')::numeric) as amt
            from jsonb_array_elements(p_invoices) x group by x->>'currency') s;
  select array_agg(x->>'number' order by o) into v_list from jsonb_array_elements(p_invoices) with ordinality as a (x, o);
  v_nos := case when v_n = 1 then v_list[1]
                else array_to_string(v_list[1:v_n - 1], ', ') || ' and ' || v_list[v_n] end;
  v_vals := jsonb_build_object('contact name', v_who, 'client', v_co, 'invoice no', v_nos, 'count', v_n::text,
    'total', v_tot, 'sign off', case when v_nm then 'Yours sincerely' else 'Yours faithfully' end);
  if p_purpose = 'invoice' then
    select * into v_tpl from public.invoice_send_template x where x.id = 1;
    t.subject_one := v_tpl.subject_one; t.subject_many := v_tpl.subject_many; t.body := v_tpl.body;
    t.legal := v_tpl.legal; t.disclaimer := v_tpl.disclaimer;
  else
    select * into t from public.invoice_email_template x where x.id = 1;
  end if;
  v_s := btrim(regexp_replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_subject, '')), ''),
           case when v_n = 1 then t.subject_one else t.subject_many end), v_vals), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_body, '')), ''), t.body), v_vals), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  insert into public.invoice_emails (client_id, bukku_contact, client_name, invoices, to_email, cc_email, subject, body, sent_by, purpose)
  values (p_client, p_contact, v_co, p_invoices, v_to, nullif(v_cc, ''), v_s, v_b, me.id, p_purpose)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', v_to, 'cc', nullif(v_cc, ''),
    'cc_list', coalesce(to_jsonb(string_to_array(nullif(v_cc, ''), ', ')), '[]'::jsonb), 'subject', v_s, 'body', v_b,
    'legal', t.legal, 'disclaimer', t.disclaimer);
end $$;

create or replace function public.quotation_release(p_id uuid, p_whatsapp boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days int;
  v_wa text;
  v_name text;
  v_queued boolean := false;
  v_on boolean;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_whatsapp and not public.send_ok('whatsapp') then return jsonb_build_object('error', 'send-off'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.source <> 'website' then return jsonb_build_object('error', 'bad-quotation'); end if;
  if q.released_at is not null then return jsonb_build_object('ok', true, 'again', true, 'valid_until', q.valid_until); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  -- A prospect marked Do not contact is not messaged (audit 2026-10-30);
  -- publishing sends them nothing.
  if coalesce(p_whatsapp, true) and q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  -- The day's WhatsApp messages for website quotations are held to
  -- `quote_wa_day` (counted under one lock); at the limit nothing changes and
  -- Publish still shows the rates.
  if coalesce(p_whatsapp, true) and not public.quote_wa_allowed(q.id) then
    return jsonb_build_object('error', 'wa-limit', 'cap', coalesce(public.app_setting('quote_wa_day', v_today), 30));
  end if;
  -- Valid from the day it is shown, as the prospect first sees it.
  v_days := coalesce(public.app_setting('quote_valid_days', v_today), 30)::int;
  update public.quotations
     set released_at = now(), released_by = me.name, valid_until = v_today + v_days
   where id = q.id returning * into q;
  if coalesce(p_whatsapp, true) then
    v_wa := public.quote_website_number(q.contact->>'whatsapp');
    v_name := coalesce(nullif(btrim(q.contact->>'name'), ''), q.brand);
    -- Sent on WhatsApp only where its template is on: wa_enqueue says nothing
    -- when it is off (audit 2026-10-30).
    select exists (select 1 from public.wa_templates x where x.purpose = 'quote_ready' and x.active and x.name <> '') into v_on;
    begin
      if v_on and v_wa ~ '^(60|65)[0-9]{8,10}$' then
        perform public.wa_enqueue('quote_ready', v_wa, v_name,
          jsonb_build_array(public.contact_greeting(q.contact->>'salutation', v_name),
                            coalesce(q.contact->>'brand', q.brand), q.ref),
          'quotation', q.id, q.client_id, q.access_key);
        v_queued := true;
      end if;
    exception when others then v_queued := false;
    end;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || case when coalesce(p_whatsapp, true)
                        then ' sent to the prospect' || case when v_queued then ' on WhatsApp' else '' end
                        else ' published on the quotation link' end ||
          ' · valid until ' || public.register_day(q.valid_until));
  return jsonb_build_object('ok', true, 'valid_until', q.valid_until, 'whatsapp', v_queued);
end $$;

create or replace function public.quotation_resend(p_id uuid, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  t  public.wa_templates;
  o  public.wa_outbox;
  k  public.client_contacts;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_hours numeric;
  v_wa text;
  v_name text;
  v_greet text;
  v_team boolean;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('whatsapp') then return jsonb_build_object('error', 'send-off'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  v_team := q.source <> 'website';
  if not v_team and q.access_key is null then return jsonb_build_object('error', 'bad-quotation'); end if;
  if not v_team and q.released_at is null then return jsonb_build_object('error', 'not-sent'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if q.valid_until is not null and q.valid_until < v_today then return jsonb_build_object('error', 'expired'); end if;
  if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  if v_team and q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  select * into t from public.wa_templates x where x.purpose = 'quote_ready' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  if v_team then
    select * into k from public.client_contacts x
     where x.client_id = q.client_id and x.archived_at is null and x.is_primary
     order by x.created_at limit 1;
    v_wa := public.wa_number(case when btrim(coalesce(k.whatsapp, '')) <> '' and btrim(k.whatsapp) !~ '^@' then k.whatsapp else k.phone end);
    v_name := coalesce(nullif(btrim(coalesce(k.name, '')), ''), q.brand);
    v_greet := public.contact_greeting(k.salutation, v_name);
  else
    v_wa := public.quote_website_number(q.contact->>'whatsapp');
    v_name := coalesce(nullif(btrim(q.contact->>'name'), ''), q.brand);
    v_greet := public.contact_greeting(q.contact->>'salutation', v_name);
  end if;
  if v_wa is null or v_wa !~ '^(60|65)[0-9]{8,10}$' then return jsonb_build_object('error', 'no-number'); end if;
  v_hours := coalesce(public.app_setting('wa_repeat_hours', v_today), 24);
  if v_hours > 0 and not coalesce(p_again, false) then
    select * into o from public.wa_outbox x
     where x.purpose = 'quote_ready' and x.ref_id = q.id and x.state <> 'failed'
       and x.created_at > now() - make_interval(secs => v_hours * 3600)
     order by x.created_at desc limit 1;
    if o.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', o.created_at,
        'by', case when coalesce(o.created_by, 'system') = 'system' then null else o.created_by end));
    end if;
  end if;
  if not v_team and not public.quote_wa_allowed(q.id) then
    return jsonb_build_object('error', 'wa-limit', 'cap', coalesce(public.app_setting('quote_wa_day', v_today), 30));
  end if;
  -- A team's quotation takes its link the first time it is sent.
  if q.access_key is null then
    update public.quotations set access_key = public.new_link_key() where id = q.id returning * into q;
  end if;
  perform public.wa_enqueue('quote_ready', v_wa, v_name,
    jsonb_build_array(v_greet, coalesce(q.contact->>'brand', q.brand), q.ref),
    'quotation', q.id, q.client_id, q.access_key);
  update public.wa_outbox x set created_by = me.name
   where x.purpose = 'quote_ready' and x.ref_id = q.id and x.created_at = now() and x.created_by = 'system';
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || case when v_team then ' link sent on WhatsApp to ' || v_name else ' sent again to the prospect on WhatsApp' end);
  return jsonb_build_object('ok', true, 'key', q.access_key);
end $$;

create or replace function public.hiring_mail_prepare(p_interview uuid, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
begin
  if not public.portal_on('email_on') then return jsonb_build_object('error', 'send-off'); end if;
  select * into i from public.hiring_interviews where id = p_interview;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_kind = 'invite' and i.state not in ('invited', 'none') then return jsonb_build_object('error', 'not-open'); end if;
  if p_kind = 'confirm' and i.state <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed'); end if;
  if p_kind = 'confirm' and i.mode = 'online' and i.meeting_link is null then return jsonb_build_object('error', 'no-meet'); end if;
  if p_kind not in ('invite', 'confirm') then return jsonb_build_object('error', 'bad-kind'); end if;
  return jsonb_build_object('id', i.id, 'kind', p_kind, 'to', c.email, 'name', c.name, 'position', c.position,
    'key', c.link_key, 'mode', i.mode, 'minutes', i.minutes, 'note', i.note, 'link', i.meeting_link,
    'times', (select jsonb_agg(public.hiring_when(s) order by s) from unnest(i.slots) s),
    'when', case when i.picked is not null then public.hiring_when(i.slots[i.picked]) end,
    'sender', me.name, 'reply_to', me.email);
end $$;

-- END OF GROUP SWITCHES ------------------------------------------------------

select public.functions_tidy();

