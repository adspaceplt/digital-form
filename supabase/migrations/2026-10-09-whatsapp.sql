-- ===========================================================================
-- WHATSAPP — messages sent from the portal through the WhatsApp Business
-- Platform (Cloud API), each with a template Meta approved: a published
-- report to the client's main contact, a feedback request sent by hand, the
-- team's reminders and a creator's booking steps.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-09: "Report to client, Team reminders,
-- Creator updates, Manually send with button a feedback approved template on
-- whatsapp")
--   1. `wa_templates`: one approved template a purpose (`report`, `feedback`,
--      `reminder`, `creator`): its name and language as Meta holds them, how
--      many body variables it takes, and whether it is on. Read by the team
--      (`wa_templates_read`), set by Business settings
--      (`wa_template_save`, filed `team.changed` under WhatsApp). A purpose
--      with no template on sends nothing.
--   2. `wa_outbox`: every message, queued or sent by hand: the purpose, the
--      number, the template and its values, what it is about, its state
--      (`queued`, `sent`, `failed`) with Meta's message id or its refusal.
--      RLS on, no policy, no grant; the sender alone claims and closes the
--      queue (`wa_claim`, `wa_done`, the service role's), and the team reads
--      the last fifty (`wa_recent`, Business settings).
--   3. A number is the WhatsApp number in its international form
--      (`wa_number`): digits only, a Malaysian number's leading 0 taking 60,
--      a Singapore number of eight digits taking 65; a WhatsApp username
--      (`@name`) cannot be messaged and is left out.
--   4. Queued by trigger, sent by `wa-send` once the write commits
--      (`wa_kick`, pg_net): each reminder in a colleague's bell (the notice
--      kinds `tasks.empty`, `outstation`, `perf.remind`, `perf.reflect`,
--      `health.remind`) to the colleague's mobile; a creator booked, asked
--      for changes or cleared to post, to the creator's WhatsApp number
--      (`creators.whatsapp`, new). A trigger never fails the write that
--      caused it.
--   5. By hand, through `wa-send` as the colleague: `wa_report_prepare`
--      (Reports Work, a published report, the client's main contact with a
--      WhatsApp number) and `wa_feedback_prepare` (Clients Work, the main
--      contact) answer the number, the name and the template; `wa_record`
--      files what was sent (`wa.sent` under the client) or refused.
--
-- ROLLBACK
--   In the SQL Editor: drop the triggers ops_notifications_wa and
--   campaign_options_wa, then the functions of this file, then the tables
--   wa_outbox and wa_templates. The column creators.whatsapp may stay.
-- ===========================================================================

alter table public.creators add column if not exists whatsapp text;

create table if not exists public.wa_templates (
  purpose   text primary key check (purpose in ('report', 'feedback', 'reminder', 'creator')),
  name      text not null default '',
  lang      text not null default 'en',
  params    integer not null default 0 check (params between 0 and 5),
  active    boolean not null default false,
  set_by    text,
  set_at    timestamptz
);
insert into public.wa_templates (purpose) values ('report'), ('feedback'), ('reminder'), ('creator')
on conflict (purpose) do nothing;
alter table public.wa_templates enable row level security;
revoke all on public.wa_templates from public, anon, authenticated;

create table if not exists public.wa_outbox (
  id          uuid primary key default gen_random_uuid(),
  purpose     text not null,
  to_number   text not null,
  to_name     text,
  template    text not null,
  lang        text not null default 'en',
  params      jsonb not null default '[]'::jsonb,
  ref_kind    text,
  ref_id      uuid,
  client_id   uuid,
  state       text not null default 'queued' check (state in ('queued', 'sending', 'sent', 'failed')),
  wa_id       text,
  error       text,
  tries       integer not null default 0,
  created_by  text,
  created_at  timestamptz not null default now(),
  claimed_at  timestamptz,
  sent_at     timestamptz
);
create index if not exists wa_outbox_state_idx on public.wa_outbox (state, created_at);
alter table public.wa_outbox enable row level security;
revoke all on public.wa_outbox from public, anon, authenticated;

/* A WhatsApp number in its international form, or null. */
create or replace function public.wa_number(p_raw text, p_market text default 'MY')
returns text
language sql immutable set search_path = public as $$
  select case
    when p_raw is null or btrim(p_raw) like '@%' then null
    else (select case
            when length(d) < 8 or length(d) > 15 then null
            when upper(coalesce(p_market, 'MY')) = 'SG' and length(d) = 8 then '65' || d
            when d like '0%' then '60' || substr(d, 2)
            else d end
          from (select regexp_replace(p_raw, '[^0-9]', '', 'g') as d) x)
  end
$$;
revoke all on function public.wa_number(text, text) from public, anon, authenticated;

create or replace function public.wa_templates_read()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.ops_me() is null or (public.ops_me()).id is null then jsonb_build_object('error', 'denied')
    else jsonb_build_object('templates', coalesce((select jsonb_agg(jsonb_build_object(
      'purpose', t.purpose, 'name', t.name, 'lang', t.lang, 'params', t.params, 'active', t.active,
      'set_by', t.set_by, 'set_at', t.set_at) order by array_position(array['report', 'feedback', 'reminder', 'creator'], t.purpose))
      from public.wa_templates t), '[]'::jsonb)) end
$$;
revoke all on function public.wa_templates_read() from public, anon;
grant execute on function public.wa_templates_read() to authenticated;

create or replace function public.wa_template_save(p_purpose text, p_name text, p_lang text, p_params integer, p_active boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  t      public.wa_templates;
  v_name text := btrim(coalesce(p_name, ''));
  v_lang text := btrim(coalesce(p_lang, ''));
  v_word text;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.wa_templates x where x.purpose = p_purpose;
  if t.purpose is null then return jsonb_build_object('error', 'not-found'); end if;
  if (v_name !~ '^[a-z0-9_]+$' or length(v_name) > 512) and not (v_name = '' and not coalesce(p_active, false)) then
    return jsonb_build_object('error', 'bad-name');
  end if;
  if v_lang !~ '^[a-z]{2,3}(_[A-Z]{2})?$' then return jsonb_build_object('error', 'bad-lang'); end if;
  if p_params is null or p_params not between 0 and 5 then return jsonb_build_object('error', 'bad-params'); end if;
  if t.name = v_name and t.lang = v_lang and t.params = p_params and t.active = coalesce(p_active, false) then
    return jsonb_build_object('ok', true, 'same', true);
  end if;
  update public.wa_templates x
     set name = v_name, lang = v_lang, params = p_params, active = coalesce(p_active, false), set_by = me.name, set_at = now()
   where x.purpose = p_purpose;
  v_word := case p_purpose when 'report' then 'Report to client' when 'feedback' then 'Feedback request'
                           when 'reminder' then 'Team reminders' else 'Creator updates' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'WhatsApp',
          v_word || ': ' || coalesce(nullif(t.name, ''), 'not set') || ' (' || t.lang || ', ' || case when t.active then 'on' else 'off' end
          || ') → ' || coalesce(nullif(v_name, ''), 'not set') || ' (' || v_lang || ', ' || case when coalesce(p_active, false) then 'on' else 'off' end || ')');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_template_save(text, text, text, integer, boolean) from public, anon;
grant execute on function public.wa_template_save(text, text, text, integer, boolean) to authenticated;

/* The last fifty messages, newest first, for Business settings. */
create or replace function public.wa_recent()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('items', coalesce((select jsonb_agg(x order by x.created_at desc) from (
      select o.id, o.purpose, o.to_name, '••••' || right(o.to_number, 4) as to_number, o.state, o.error,
             o.created_at, o.sent_at, o.created_by
        from public.wa_outbox o order by o.created_at desc limit 50) x), '[]'::jsonb)) end
$$;
revoke all on function public.wa_recent() from public, anon;
grant execute on function public.wa_recent() to authenticated;

/* Wakes wa-send once the write has committed. Silent where pg_net is not
   installed or refuses: the queue is kept, and the next wake sends it. */
create or replace function public.wa_kick()
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'net' and p.proname = 'http_post') then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2)'
    using 'https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/wa-send', '{"action":"drain"}'::jsonb;
exception when others then
  return;
end $$;
revoke all on function public.wa_kick() from public, anon, authenticated;

/* One message into the queue, where its purpose has a template on and the
   number reads. */
create or replace function public.wa_queue(p_purpose text, p_number text, p_name text, p_params jsonb,
                                           p_ref_kind text, p_ref_id uuid, p_client uuid default null)
returns void
language plpgsql security definer set search_path = public as $$
declare t public.wa_templates;
begin
  select * into t from public.wa_templates x where x.purpose = p_purpose and x.active and x.name <> '';
  if t.purpose is null or p_number is null then return; end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, created_by)
  values (p_purpose, p_number, p_name, t.name, t.lang,
          coalesce((select jsonb_agg(e.value) from (select value from jsonb_array_elements(coalesce(p_params, '[]'::jsonb)) with ordinality e(value, n)
                     where n <= t.params order by n) e), '[]'::jsonb),
          p_ref_kind, p_ref_id, p_client, 'system');
  perform public.wa_kick();
end $$;
revoke all on function public.wa_queue(text, text, text, jsonb, text, uuid, uuid) from public, anon, authenticated;

/* A reminder in a colleague's bell, to their WhatsApp too. */
create or replace function public.ops_notifications_wa()
returns trigger
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  if new.kind not in ('tasks.empty', 'outstation', 'perf.remind', 'perf.reflect', 'health.remind') then return new; end if;
  select * into m from public.team_members x where x.id = new.team_member_id and x.active;
  if m.id is null then return new; end if;
  perform public.wa_queue('reminder', public.wa_number(m.mobile, 'MY'), m.name,
    jsonb_build_array(split_part(btrim(m.name), ' ', 1), coalesce(new.title, ''), coalesce(new.body, '')),
    'notice', new.id);
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.ops_notifications_wa() from public, anon, authenticated;
create or replace trigger ops_notifications_wa after insert on public.ops_notifications
  for each row execute function public.ops_notifications_wa();

/* A creator booked, asked for changes, or cleared to post: told on WhatsApp
   as on their phone's notifications. Only a forward move. */
create or replace function public.campaign_options_wa()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  k       public.creators;
  v_title text;
  v_cl    uuid;
  v_what  text;
begin
  if new.state is not distinct from old.state then return new; end if;
  v_what := case
    when new.state = 'confirmed' and old.state in ('option', 'shortlisted', 'backup') then 'Booking confirmed'
    when new.state = 'changes' then 'Changes requested'
    when new.state = 'scheduled' and old.state in ('submitted', 'reviewing', 'changes') then 'Approved: ready to post'
    else null end;
  if v_what is null then return new; end if;
  select * into k from public.creators x where x.id = new.creator_id;
  if k.id is null then return new; end if;
  select coalesce(nullif(btrim(c.title), ''), 'Your campaign'), c.client_id into v_title, v_cl
    from public.campaigns c where c.id = new.campaign_id;
  perform public.wa_queue('creator', public.wa_number(k.whatsapp, 'MY'), k.name,
    jsonb_build_array(split_part(btrim(k.name), ' ', 1), v_title, v_what), 'option', new.id, v_cl);
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.campaign_options_wa() from public, anon, authenticated;
create or replace trigger campaign_options_wa after update of state on public.campaign_options
  for each row execute function public.campaign_options_wa();

/* The sender's side, the service role's alone: claim what is queued (and
   what was claimed over five minutes ago without an answer), then close it. */
create or replace function public.wa_claim(p_limit integer default 20)
returns setof public.wa_outbox
language sql security definer set search_path = public as $$
  update public.wa_outbox o set state = 'sending', claimed_at = now(), tries = o.tries + 1
   where o.id in (select x.id from public.wa_outbox x
                   where (x.state = 'queued' or (x.state = 'sending' and x.claimed_at < now() - interval '5 minutes'))
                     and x.tries < 3
                   order by x.created_at limit greatest(1, least(coalesce(p_limit, 20), 50))
                   for update skip locked)
  returning o.*
$$;
create or replace function public.wa_done(p_id uuid, p_ok boolean, p_wa_id text, p_error text)
returns void
language sql security definer set search_path = public as $$
  update public.wa_outbox o
     set state = case when p_ok then 'sent' when o.tries >= 3 then 'failed' else 'queued' end,
         wa_id = left(p_wa_id, 200), error = left(p_error, 500), sent_at = case when p_ok then now() end
   where o.id = p_id
$$;
revoke all on function public.wa_claim(integer) from public, anon, authenticated;
revoke all on function public.wa_done(uuid, boolean, text, text) from public, anon, authenticated;

/* By hand: what a published report's message needs, asked as the colleague. */
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
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
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
  return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'first', split_part(btrim(coalesce(k.name, '')), ' ', 1),
    'client', coalesce(nullif(r.brand_name, ''), c.name), 'client_id', c.id,
    'template', t.name, 'lang', t.lang, 'params', t.params);
end $$;
revoke all on function public.wa_report_prepare(uuid) from public, anon;
grant execute on function public.wa_report_prepare(uuid) to authenticated;

/* By hand: a feedback request to the client's main contact. */
create or replace function public.wa_feedback_prepare(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c   public.clients;
  k   public.client_contacts;
  t   public.wa_templates;
  v_n text;
begin
  if not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.clients x where x.id = p_client;
  if c.id is null or not public.client_seen(c.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.wa_templates x where x.purpose = 'feedback' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  select * into k from public.client_contacts x where x.client_id = c.id and x.archived_at is null
   order by x.is_primary desc nulls last, x.created_at limit 1;
  v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
  if v_n is null then return jsonb_build_object('error', 'no-number'); end if;
  return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'first', split_part(btrim(coalesce(k.name, '')), ' ', 1),
    'client', c.name, 'client_id', c.id, 'template', t.name, 'lang', t.lang, 'params', t.params);
end $$;
revoke all on function public.wa_feedback_prepare(uuid) from public, anon;
grant execute on function public.wa_feedback_prepare(uuid) to authenticated;

/* What was sent by hand (or refused), filed under the client. */
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
  if (p_purpose = 'report' and not public.allowed('reports', 'work'))
     or (p_purpose = 'feedback' and not public.allowed('clients', 'work')) then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, params, ref_kind, ref_id, client_id, state,
                                wa_id, error, created_by, sent_at, tries)
  values (p_purpose, coalesce(p_number, ''), p_name, coalesce(p_template, ''), coalesce(p_params, '[]'::jsonb),
          case when p_purpose = 'report' then 'report' else 'client' end, p_ref, p_client,
          case when p_ok then 'sent' else 'failed' end, left(p_wa_id, 200), left(p_error, 500), me.name,
          case when p_ok then now() end, 1);
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

-- WhatsApp sends file under the client (js/admin.js ACTION_LABEL 'wa.sent').
create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch', 'wa.sent',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished') then 'reports'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'review.unconfirmed',
                    'set.created', 'set.deleted', 'set.published', 'set.renamed',
                    'set.task_linked', 'set.task_unlinked',
                    'set.withdrawn') then 'review'
    when action in ('script.approved', 'script.changes', 'script.created', 'script.deleted',
                    'script.link', 'script.saved', 'script.shared', 'script.shot',
                    'script.unshared') then 'scripts'
    when action in ('handbook.added', 'handbook.archived', 'handbook.deleted',
                    'handbook.edited', 'handbook.restored', 'handbook.version') then 'handbook'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

-- END OF WHATSAPP -------------------------------------------------------------

select public.functions_tidy();
