-- ===========================================================================
-- WHATSAPP SECTION — WhatsApp is a section of its own: every message the
-- portal sent, with Meta's delivery status; one composer every record
-- shares; the templates chosen from Meta's approved list.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. The activity map moves in its own file,
-- 2026-10-10-whatsapp-activity-map.sql, run after this one.
--
-- WHAT CHANGED (the user, 2026-10-10: WhatsApp Phase 1, a section with the
-- messages sent and their status, a composer, and the templates and
-- settings in it; the inbox and messages to colleagues are not built)
--   1. A section on the ladder, `whatsapp`, after Clients: View reads the
--      messages, Work (Manage on the panel) sends from the composer and
--      from a record, Manage (Full Access) chooses the templates and turns
--      them on or off. Every group starts once: Admin at Full Access, a
--      group at Clients Work or above at Work, at Clients View at View,
--      any other at No Access.
--   2. Three parts under it, each following the section unless a group
--      shuts it: `whatsapp.report` (a published report), `whatsapp.feedback`
--      (the feedback request), `whatsapp.booking` (a creator's booking).
--      They replace `reports.whatsapp`, `clients.whatsapp` and
--      `campaigns.whatsapp`: a group that shut one keeps it shut under the
--      new key, and the old keys are taken off every group and member. A
--      send asks the section at Work, its part at Work and the record's own
--      section at View (Reports, Clients or Creator Campaigns).
--   3. `wa_outbox` keeps who a message went to (`to_kind`: contact, creator
--      or colleague; `to_id`), its template's category (`category`:
--      utility, marketing, authentication) and Meta's delivery events
--      (`delivered_at`, `read_at`, `failed_at` with `fail_code` and
--      `fail_title`). `wa_templates.category` holds each purpose's.
--   4. `wa_status_record(p_wa_id, p_status, p_at, p_code, p_title,
--      p_category)`: the service role's alone, called by `wa-hook` for each
--      status Meta reports, against the message id `wa-send` kept. Closed
--      to every page.
--   5. `wa_messages(p_month)`: the month's messages for the section (View),
--      newest first, under the client scope rule, with the month's count of
--      templates sent by category and the queue's state.
--   6. `wa_recipients()`: every client contact (Clients: Contacts View, the
--      client in scope) and active creator (Creator Campaigns: Creators
--      List View) the composer may address, each with the number it will be
--      sent to, or why it cannot be.
--   7. `wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref)` answers the
--      number, the greeting, the client and the campaign a send needs, as
--      the colleague; `wa_sent(…)` files what was sent or refused, asking
--      the same again (`wa.sent`, under WhatsApp in the activity record).
--   8. `wa_template_set(p_purpose, p_name, p_lang, p_params, p_category,
--      p_active)`: a purpose's template, chosen from Meta's approved list,
--      and its switch, at WhatsApp Full Access, filed `wa.template`.
--      `wa_template_save` keeps its arguments and asks the same.
--   9. `wa_enqueue` stamps the template's category on what it queues;
--      `wa_report_prepare`, `wa_feedback_prepare`, `wa_record`,
--      `wa_creator_send` and `wa_recent` ask the new section and parts.
--
-- ROLLBACK
--   Pages first (the section reads "This needs a database update."), then
--   restate the nine functions of point 9 and wa_template_save from
--   2026-10-09-whatsapp-numbers-resend.sql, 2026-10-09-whatsapp-by-group.sql
--   and 2026-10-09-whatsapp.sql, and revoke wa_messages, wa_recipients,
--   wa_compose_prepare, wa_sent and wa_template_set from authenticated. The
--   columns may stay. The old part keys come back only where a group sets
--   them again on the Team panel.
-- ===========================================================================

alter table public.wa_outbox add column if not exists to_kind text;
alter table public.wa_outbox add column if not exists to_id uuid;
alter table public.wa_outbox add column if not exists category text;
alter table public.wa_outbox add column if not exists delivered_at timestamptz;
alter table public.wa_outbox add column if not exists read_at timestamptz;
alter table public.wa_outbox add column if not exists failed_at timestamptz;
alter table public.wa_outbox add column if not exists fail_code text;
alter table public.wa_outbox add column if not exists fail_title text;
create index if not exists wa_outbox_wa_id_idx on public.wa_outbox (wa_id) where wa_id is not null;
alter table public.wa_templates add column if not exists category text not null default '';

-- Who each earlier message went to, read off its purpose, once.
update public.wa_outbox o
   set to_kind = case o.purpose when 'reminder' then 'colleague' when 'creator' then 'creator' else 'contact' end
 where o.to_kind is null;

-- Every group starts once: Admin at Full Access, Clients Work or above at
-- Work, Clients View at View, else No Access.
update public.team_roles r
   set access = coalesce(r.access, '{}'::jsonb) || jsonb_build_object('whatsapp',
         case when r.is_admin or r.slug = 'admin' then 'manage'
              when public.level_rank(r.access ->> 'clients') >= 2 then 'work'
              when public.level_rank(r.access ->> 'clients') = 1 then 'view'
              else 'none' end)
 where not (coalesce(r.access, '{}'::jsonb) ? 'whatsapp');
update public.team_members m
   set access = coalesce(m.access, '{}'::jsonb) || jsonb_build_object('whatsapp',
         case when m.is_admin or m.role = 'admin' then 'manage'
              when public.level_rank(m.access ->> 'clients') >= 2 then 'work'
              when public.level_rank(m.access ->> 'clients') = 1 then 'view'
              else 'none' end)
 where not (coalesce(m.access, '{}'::jsonb) ? 'whatsapp');

-- The three sending parts move under WhatsApp, once: a part a group shut
-- stays shut under its new key; any other level followed its section and
-- is not carried. The old keys are taken off.
update public.team_roles r
   set access = (r.access - 'reports.whatsapp' - 'clients.whatsapp' - 'campaigns.whatsapp')
       || case when r.access ->> 'reports.whatsapp' = 'none' and not (r.access ? 'whatsapp.report')
               then jsonb_build_object('whatsapp.report', 'none') else '{}'::jsonb end
       || case when r.access ->> 'clients.whatsapp' = 'none' and not (r.access ? 'whatsapp.feedback')
               then jsonb_build_object('whatsapp.feedback', 'none') else '{}'::jsonb end
       || case when r.access ->> 'campaigns.whatsapp' = 'none' and not (r.access ? 'whatsapp.booking')
               then jsonb_build_object('whatsapp.booking', 'none') else '{}'::jsonb end
 where r.access ?| array['reports.whatsapp', 'clients.whatsapp', 'campaigns.whatsapp'];
update public.team_members m
   set access = (m.access - 'reports.whatsapp' - 'clients.whatsapp' - 'campaigns.whatsapp')
       || case when m.access ->> 'reports.whatsapp' = 'none' and not (m.access ? 'whatsapp.report')
               then jsonb_build_object('whatsapp.report', 'none') else '{}'::jsonb end
       || case when m.access ->> 'clients.whatsapp' = 'none' and not (m.access ? 'whatsapp.feedback')
               then jsonb_build_object('whatsapp.feedback', 'none') else '{}'::jsonb end
       || case when m.access ->> 'campaigns.whatsapp' = 'none' and not (m.access ? 'whatsapp.booking')
               then jsonb_build_object('whatsapp.booking', 'none') else '{}'::jsonb end
 where m.access ?| array['reports.whatsapp', 'clients.whatsapp', 'campaigns.whatsapp'];

/* Whether this colleague may send for a purpose: the section and the
   purpose's part at Work, and the record's own section at View. */
create or replace function public.wa_may_send(p_purpose text, p_to_kind text)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.allowed('whatsapp', 'work') and case p_purpose
    when 'report'   then public.allowed('whatsapp.report', 'work') and public.allowed('reports', 'view')
    when 'feedback' then public.allowed('whatsapp.feedback', 'work') and public.allowed('clients', 'view')
    when 'creator'  then public.allowed('whatsapp.booking', 'work') and public.allowed('campaigns', 'view')
    when 'message'  then case p_to_kind when 'contact' then public.allowed('clients.contacts', 'view')
                                        when 'creator' then public.allowed('campaigns.creators', 'view')
                                        else false end
    else false end
$$;
revoke all on function public.wa_may_send(text, text) from public, anon, authenticated;

/* A status Meta reported for a message `wa-send` sent, from `wa-hook`: the
   service role's alone. A read is delivered too; a message delivered or
   read is never marked failed after it. Answers whether the message is
   one of ours. */
create or replace function public.wa_status_record(p_wa_id text, p_status text, p_at timestamptz,
                                                   p_code text, p_title text, p_category text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_n  integer;
  v_at timestamptz := coalesce(p_at, now());
  v_st text := lower(coalesce(p_status, ''));
begin
  if nullif(btrim(coalesce(p_wa_id, '')), '') is null or v_st not in ('sent', 'delivered', 'read', 'failed') then
    return false;
  end if;
  update public.wa_outbox o
     set delivered_at = case when v_st in ('delivered', 'read') then coalesce(o.delivered_at, v_at) else o.delivered_at end,
         read_at      = case when v_st = 'read' then coalesce(o.read_at, v_at) else o.read_at end,
         failed_at    = case when v_st = 'failed' and o.delivered_at is null and o.read_at is null
                             then coalesce(o.failed_at, v_at) else o.failed_at end,
         fail_code    = case when v_st = 'failed' and o.delivered_at is null and o.read_at is null
                             then left(nullif(btrim(coalesce(p_code, '')), ''), 40) else o.fail_code end,
         fail_title   = case when v_st = 'failed' and o.delivered_at is null and o.read_at is null
                             then left(nullif(btrim(coalesce(p_title, '')), ''), 300) else o.fail_title end,
         category     = coalesce(nullif(lower(btrim(coalesce(p_category, ''))), ''), o.category)
   where o.wa_id = btrim(p_wa_id);
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;
revoke all on function public.wa_status_record(text, text, timestamptz, text, text, text) from public, anon, authenticated;

/* The section's list: the month's messages (Malaysia time), newest first,
   under the client scope rule; the month's count of templates sent by
   category; and the queue. */
create or replace function public.wa_messages(p_month date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_from date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Kuala_Lumpur')::date))::date;
  v_a    timestamptz;
  v_b    timestamptz;
begin
  if me.id is null or not public.allowed('whatsapp', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_a := v_from::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_b := (v_from + interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur';
  return jsonb_build_object(
    'month', v_from,
    'items', coalesce((select jsonb_agg(x order by x.created_at desc) from (
        select o.id, o.purpose, o.template, o.category, o.to_kind, o.to_name, o.to_number, o.client_id,
               c.name as client, o.state, o.error, o.created_at, o.sent_at, o.created_by,
               o.delivered_at, o.read_at, o.failed_at, o.fail_code, o.fail_title, o.ref_kind, o.ref_id
          from public.wa_outbox o
          left join public.clients c on c.id = o.client_id
         where o.created_at >= v_a and o.created_at < v_b
           and (o.client_id is null or public.client_seen(o.client_id, 'view'))
         order by o.created_at desc
         limit 2000) x), '[]'::jsonb),
    'counts', (select jsonb_build_object(
        'utility',        count(*) filter (where o.category = 'utility'),
        'marketing',      count(*) filter (where o.category = 'marketing'),
        'authentication', count(*) filter (where o.category = 'authentication'))
      from public.wa_outbox o
     where o.state = 'sent' and o.created_at >= v_a and o.created_at < v_b),
    'queue', (select jsonb_build_object(
        'queued',  count(*) filter (where o.state = 'queued'),
        'sending', count(*) filter (where o.state = 'sending'),
        'failed',  count(*) filter (where o.state = 'failed' and o.created_at > now() - interval '7 days'),
        'oldest',  min(o.created_at) filter (where o.state in ('queued', 'sending')))
      from public.wa_outbox o));
end $$;
revoke all on function public.wa_messages(date) from public, anon;
grant execute on function public.wa_messages(date) to authenticated;

/* Whom the composer may address: client contacts (Clients: Contacts View,
   the client in scope) and active creators (Creator Campaigns: Creators
   List View), each with the number it will be sent to, else why not. */
create or replace function public.wa_recipients()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('whatsapp', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'contacts', case when not public.allowed('clients.contacts', 'view') then '[]'::jsonb else
      coalesce((select jsonb_agg(x order by x.client, x.is_primary desc, x.name) from (
        select k.id, k.name, k.role, coalesce(k.is_primary, false) as is_primary, c.id as client_id, c.name as client,
               c.stage, public.contact_greeting(k.salutation, k.name) as greeting,
               public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market) as number,
               coalesce(k.whatsapp ~ '^@', false) as username
          from public.client_contacts k
          join public.clients c on c.id = k.client_id
         where k.archived_at is null and public.client_seen(c.id, 'view')) x), '[]'::jsonb) end,
    'creators', case when not public.allowed('campaigns.creators', 'view') then '[]'::jsonb else
      coalesce((select jsonb_agg(x order by x.name) from (
        select k.id, k.name, split_part(btrim(k.name), ' ', 1) as greeting,
               public.wa_number(k.whatsapp, 'MY') as number, false as username, k.access_code as code
          from public.creators k
         where k.active) x), '[]'::jsonb) end);
end $$;
revoke all on function public.wa_recipients() from public, anon;
grant execute on function public.wa_recipients() to authenticated;

/* What one send by hand needs, asked as the colleague: the recipient's
   number and greeting, the client, and for a report or a booking that the
   record is theirs. `p_purpose` is `report` (p_ref a published report of
   the contact's client), `feedback`, `creator` (p_ref the creator's booked
   option) or `message`. */
create or replace function public.wa_compose_prepare(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  k    public.client_contacts;
  cr   public.creators;
  c    public.clients;
  r    public.sm_reports;
  o    public.campaign_options;
  cp   public.campaigns;
  v_n  text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose not in ('message', 'report', 'feedback', 'creator') or p_to_kind not in ('contact', 'creator')
     or (p_purpose in ('report', 'feedback') and p_to_kind <> 'contact')
     or (p_purpose = 'creator' and p_to_kind <> 'creator') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if not public.wa_may_send(p_purpose, p_to_kind) then return jsonb_build_object('error', 'denied'); end if;
  if p_to_kind = 'contact' then
    select * into k from public.client_contacts x where x.id = p_to and x.archived_at is null;
    if k.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = k.client_id;
    if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    if p_purpose = 'report' then
      select * into r from public.sm_reports x where x.id = p_ref;
      if r.id is null or r.client_id <> c.id then return jsonb_build_object('error', 'not-found'); end if;
      if r.status <> 'published' then return jsonb_build_object('error', 'not-published'); end if;
    end if;
    v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
    if v_n is null then
      return jsonb_build_object('error', case when k.whatsapp ~ '^@' then 'username' else 'no-number' end);
    end if;
    return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'greeting', public.contact_greeting(k.salutation, k.name),
      'client_id', c.id, 'client', case when r.id is not null then coalesce(nullif(r.brand_name, ''), c.name) else c.name end,
      'subject', c.name);
  end if;
  select * into cr from public.creators x where x.id = p_to;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_purpose = 'creator' then
    select * into o from public.campaign_options x where x.id = p_ref;
    if o.id is null or o.creator_id <> cr.id then return jsonb_build_object('error', 'not-found'); end if;
    select * into cp from public.campaigns x where x.id = o.campaign_id;
    if cp.id is null or (cp.client_id is not null and not public.client_seen(cp.client_id, 'view')) then
      return jsonb_build_object('error', 'not-found');
    end if;
    if o.state in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced') then
      return jsonb_build_object('error', 'not-booked');
    end if;
  elsif not cr.active then
    return jsonb_build_object('error', 'not-found');
  end if;
  v_n := public.wa_number(cr.whatsapp, 'MY');
  if v_n is null then return jsonb_build_object('error', 'no-creator-number'); end if;
  return jsonb_build_object('ok', true, 'number', v_n, 'name', cr.name, 'greeting', split_part(btrim(cr.name), ' ', 1),
    'client_id', cp.client_id,
    'campaign', case when cp.id is not null then coalesce(nullif(btrim(cp.title), ''), 'Your campaign') end,
    'code', cr.access_code, 'subject', coalesce(nullif(btrim(cp.title), ''), cr.name));
end $$;
revoke all on function public.wa_compose_prepare(text, uuid, text, uuid) from public, anon;
grant execute on function public.wa_compose_prepare(text, uuid, text, uuid) to authenticated;

/* What a send by hand did, filed as the colleague: asked again as the
   composer asked, so the number, the name and the client are the
   database's own, never the caller's. */
create or replace function public.wa_sent(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid, p_template text,
                                          p_lang text, p_category text, p_params jsonb, p_ok boolean,
                                          p_wa_id text, p_error text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  p    jsonb := public.wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref);
  v_word text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p ? 'error' then return p; end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, state,
                                wa_id, error, created_by, sent_at, tries, to_kind, to_id, category)
  values (p_purpose, p ->> 'number', p ->> 'name', coalesce(nullif(btrim(p_template), ''), ''), coalesce(nullif(btrim(p_lang), ''), 'en'),
          case when jsonb_typeof(p_params) = 'array' then p_params else '[]'::jsonb end,
          case p_purpose when 'report' then 'report' when 'creator' then 'option' when 'feedback' then 'client' end,
          case when p_purpose in ('report', 'creator') then p_ref when p_purpose = 'feedback' then (p ->> 'client_id')::uuid end,
          (p ->> 'client_id')::uuid,
          case when p_ok then 'sent' else 'failed' end, left(p_wa_id, 200), left(p_error, 500), me.name,
          case when p_ok then now() end, 1, p_to_kind, p_to,
          nullif(lower(btrim(coalesce(p_category, ''))), ''));
  if p_ok then
    v_word := case p_purpose when 'report' then 'Report' when 'feedback' then 'Feedback request'
                             when 'creator' then 'Booking' else 'Message' end;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'wa.sent', p ->> 'subject',
            case when p_purpose = 'creator' then (p ->> 'name') || ' · Booking sent on WhatsApp'
                 else v_word || ' sent on WhatsApp to ' || coalesce(nullif(btrim(p ->> 'name'), ''), 'the contact') end);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_sent(text, uuid, text, uuid, text, text, text, jsonb, boolean, text, text) from public, anon;
grant execute on function public.wa_sent(text, uuid, text, uuid, text, text, text, jsonb, boolean, text, text) to authenticated;

/* A purpose's template, chosen from Meta's approved list, and its switch:
   WhatsApp Full Access, filed under WhatsApp. */
create or replace function public.wa_template_set(p_purpose text, p_name text, p_lang text, p_params integer,
                                                  p_category text, p_active boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  t      public.wa_templates;
  v_name text := btrim(coalesce(p_name, ''));
  v_lang text := btrim(coalesce(p_lang, ''));
  v_cat  text := lower(btrim(coalesce(p_category, '')));
  v_word text;
begin
  if me.id is null or not public.allowed('whatsapp', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.wa_templates x where x.purpose = p_purpose;
  if t.purpose is null then return jsonb_build_object('error', 'not-found'); end if;
  if (v_name !~ '^[a-z0-9_]+$' or length(v_name) > 512) and not (v_name = '' and not coalesce(p_active, false)) then
    return jsonb_build_object('error', 'bad-name');
  end if;
  if v_lang !~ '^[a-z]{2,3}(_[A-Z]{2})?$' then return jsonb_build_object('error', 'bad-lang'); end if;
  if p_params is null or p_params not between 0 and 5 then return jsonb_build_object('error', 'bad-params'); end if;
  if v_cat not in ('', 'utility', 'marketing', 'authentication') then return jsonb_build_object('error', 'bad-category'); end if;
  if t.name = v_name and t.lang = v_lang and t.params = p_params and t.category = v_cat and t.active = coalesce(p_active, false) then
    return jsonb_build_object('ok', true, 'same', true);
  end if;
  update public.wa_templates x
     set name = v_name, lang = v_lang, params = p_params, category = v_cat, active = coalesce(p_active, false),
         set_by = me.name, set_at = now()
   where x.purpose = p_purpose;
  v_word := case p_purpose when 'report' then 'Report to client' when 'feedback' then 'Feedback request'
                           when 'reminder' then 'Team reminders' else 'Creator updates' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'wa.template', 'WhatsApp',
          v_word || ': ' || coalesce(nullif(t.name, ''), 'not set') || ' (' || t.lang || ', ' || case when t.active then 'on' else 'off' end
          || ') → ' || coalesce(nullif(v_name, ''), 'not set') || ' (' || v_lang || ', ' || case when coalesce(p_active, false) then 'on' else 'off' end || ')');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_template_set(text, text, text, integer, text, boolean) from public, anon;
grant execute on function public.wa_template_set(text, text, text, integer, text, boolean) to authenticated;

/* The earlier form, kept for a page loaded before this file: the same
   question, the category left as it stands. */
create or replace function public.wa_template_save(p_purpose text, p_name text, p_lang text, p_params integer, p_active boolean)
returns jsonb
language sql security definer set search_path = public as $$
  select public.wa_template_set(p_purpose, p_name, p_lang, p_params,
           (select t.category from public.wa_templates t where t.purpose = p_purpose), p_active)
$$;
revoke all on function public.wa_template_save(text, text, text, integer, boolean) from public, anon;
grant execute on function public.wa_template_save(text, text, text, integer, boolean) to authenticated;

/* One message into the queue, where its purpose has a template on and the
   number reads; its template's category kept with it. */
create or replace function public.wa_enqueue(p_purpose text, p_number text, p_name text, p_params jsonb,
                                             p_ref_kind text, p_ref_id uuid, p_client uuid, p_button text)
returns void
language plpgsql security definer set search_path = public as $$
declare t public.wa_templates;
begin
  select * into t from public.wa_templates x where x.purpose = p_purpose and x.active and x.name <> '';
  if t.purpose is null or p_number is null then return; end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, created_by, button,
                                to_kind, to_id, category)
  values (p_purpose, p_number, p_name, t.name, t.lang,
          coalesce((select jsonb_agg(e.value) from (select value from jsonb_array_elements(coalesce(p_params, '[]'::jsonb)) with ordinality e(value, n)
                     where n <= t.params order by n) e), '[]'::jsonb),
          p_ref_kind, p_ref_id, p_client, 'system', nullif(btrim(coalesce(p_button, '')), ''),
          case p_purpose when 'reminder' then 'colleague' when 'creator' then 'creator' else 'contact' end,
          case when p_purpose = 'reminder' then (select n.team_member_id from public.ops_notifications n where n.id = p_ref_id)
               when p_purpose = 'creator' then (select o.creator_id from public.campaign_options o where o.id = p_ref_id) end,
          nullif(t.category, ''));
  perform public.wa_kick();
end $$;

revoke all on function public.wa_enqueue(text, text, text, jsonb, text, uuid, uuid, text) from public, anon, authenticated;

/* The earlier sends by hand, kept for a page loaded before this file: the
   section and the purpose's part as the composer asks them. */
create or replace function public.wa_report_prepare(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r   public.sm_reports;
  c   public.clients;
  k   public.client_contacts;
  t   public.wa_templates;
  v_n text;
begin
  if not public.wa_may_send('report', 'contact') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports x where x.id = p_id;
  if r.id is null or not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'published' then return jsonb_build_object('error', 'not-published'); end if;
  select * into t from public.wa_templates x where x.purpose = 'report' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  select * into c from public.clients x where x.id = r.client_id;
  select * into k from public.client_contacts x where x.client_id = r.client_id and x.archived_at is null
   order by x.is_primary desc nulls last, x.created_at limit 1;
  v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
  if v_n is null then return jsonb_build_object('error', 'no-number'); end if;
  return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'first', public.contact_greeting(k.salutation, k.name),
    'client', coalesce(nullif(r.brand_name, ''), c.name), 'client_id', c.id,
    'template', t.name, 'lang', t.lang, 'params', t.params);
end $$;

revoke all on function public.wa_report_prepare(uuid) from public, anon;
grant execute on function public.wa_report_prepare(uuid) to authenticated;

create or replace function public.wa_feedback_prepare(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c   public.clients;
  k   public.client_contacts;
  t   public.wa_templates;
  v_n text;
begin
  if not public.wa_may_send('feedback', 'contact') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.clients x where x.id = p_client;
  if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.wa_templates x where x.purpose = 'feedback' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  select * into k from public.client_contacts x where x.client_id = c.id and x.archived_at is null
   order by x.is_primary desc nulls last, x.created_at limit 1;
  v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
  if v_n is null then return jsonb_build_object('error', 'no-number'); end if;
  return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'first', public.contact_greeting(k.salutation, k.name),
    'client', c.name, 'client_id', c.id, 'template', t.name, 'lang', t.lang, 'params', t.params);
end $$;

revoke all on function public.wa_feedback_prepare(uuid) from public, anon;
grant execute on function public.wa_feedback_prepare(uuid) to authenticated;

create or replace function public.wa_record(p_purpose text, p_ref uuid, p_client uuid, p_number text, p_name text,
                                            p_template text, p_params jsonb, p_ok boolean, p_wa_id text, p_error text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  v_cl text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose not in ('report', 'feedback') then return jsonb_build_object('error', 'bad-purpose'); end if;
  if not public.wa_may_send(p_purpose, 'contact') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, params, ref_kind, ref_id, client_id, state,
                                wa_id, error, created_by, sent_at, tries, to_kind, category)
  values (p_purpose, coalesce(p_number, ''), p_name, coalesce(p_template, ''), coalesce(p_params, '[]'::jsonb),
          case when p_purpose = 'report' then 'report' else 'client' end, p_ref, p_client,
          case when p_ok then 'sent' else 'failed' end, left(p_wa_id, 200), left(p_error, 500), me.name,
          case when p_ok then now() end, 1, 'contact',
          nullif((select t.category from public.wa_templates t where t.purpose = p_purpose), ''));
  select c.name into v_cl from public.clients c where c.id = p_client;
  if p_ok then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'wa.sent', v_cl, case when p_purpose = 'report' then 'Report sent on WhatsApp' else 'Feedback request sent on WhatsApp' end
            || coalesce(' to ' || nullif(btrim(p_name), ''), ''));
  end if;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.wa_record(text, uuid, uuid, text, text, text, jsonb, boolean, text, text) from public, anon;
grant execute on function public.wa_record(text, uuid, uuid, text, text, text, jsonb, boolean, text, text) to authenticated;

/* A creator's booking queued again, kept for a page loaded before this
   file; the composer sends it at the press now. */
create or replace function public.wa_creator_send(p_option uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  o    public.campaign_options;
  c    public.campaigns;
  k    public.creators;
  t    public.wa_templates;
  v_n  text;
begin
  if me.id is null or not public.wa_may_send('creator', 'creator') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.campaigns x where x.id = o.campaign_id;
  if c.id is null or (c.client_id is not null and not public.client_seen(c.client_id, 'view')) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if o.state in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced') then
    return jsonb_build_object('error', 'not-booked');
  end if;
  select * into t from public.wa_templates x where x.purpose = 'creator' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  select * into k from public.creators x where x.id = o.creator_id;
  v_n := public.wa_number(k.whatsapp, 'MY');
  if v_n is null then return jsonb_build_object('error', 'no-number'); end if;
  perform public.wa_enqueue('creator', v_n, k.name,
    jsonb_build_array(split_part(btrim(k.name), ' ', 1), coalesce(nullif(btrim(c.title), ''), 'Your campaign')),
    'option', o.id, c.client_id, k.access_code);
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'campaign.whatsapp', coalesce(c.title, ''), k.name || ' · Booking sent on WhatsApp');
  return jsonb_build_object('ok', true, 'to', k.name);
end $$;

revoke all on function public.wa_creator_send(uuid) from public, anon;
grant execute on function public.wa_creator_send(uuid) to authenticated;

/* The last fifty messages, kept for a page loaded before this file: the
   section's list reads wa_messages now. */
create or replace function public.wa_recent()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.allowed('whatsapp', 'view') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('items', coalesce((select jsonb_agg(x order by x.created_at desc) from (
      select o.id, o.purpose, o.to_name, '••••' || right(o.to_number, 4) as to_number, o.state, o.error,
             o.created_at, o.sent_at, o.created_by
        from public.wa_outbox o
       where o.client_id is null or public.client_seen(o.client_id, 'view')
       order by o.created_at desc limit 50) x), '[]'::jsonb)) end
$$;
revoke all on function public.wa_recent() from public, anon;
grant execute on function public.wa_recent() to authenticated;

-- END OF WHATSAPP SECTION -----------------------------------------------------

select public.functions_tidy();
