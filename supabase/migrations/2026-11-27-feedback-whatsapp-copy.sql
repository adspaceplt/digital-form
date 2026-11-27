-- ===========================================================================
-- FEEDBACK COPIED FOR WHATSAPP (2026-11-27)
-- ===========================================================================
-- WHY (the user, 2026-11-27: "A, add copy for WhatsApp"): Request feedback
-- emailed the primary contact alone (FEEDBACK SENT BY EMAIL). Most clients
-- talk to the team in a WhatsApp group, so the same sheet also makes the
-- request and copies its message with the link, pasted into the group by
-- hand. Nothing is sent by the portal on WhatsApp.
--
-- WHAT IT CHANGES
--   * `feedback_requests.channel` (email, whatsapp; email for every row
--     before): how the request went, read by the record's Feedback part.
--   * `feedback_request(p_client, p_kind, p_again, p_channel)`: the
--     channel added (email by default), every refusal kept; a copy needs a
--     primary contact but not their email address; the Activity record
--     says "copied for WhatsApp". Sending and Sent recently hold across
--     both channels: a request made either way within the repeat hours
--     asks first.
--   * `feedback_wa_copy(p_client, p_kind, p_again)` (Clients at Work, Send
--     on WhatsApp by hand: `send_ok('whatsapp')`): the request made as
--     above, then the form's Email template in the contact's language as
--     plain text, its button's words and the link under it. No mail state:
--     the request stands open until answered, replaced or withdrawn, as
--     an emailed one does.
--   * `feedback_client`: each request names its channel.
--
-- ORDER: this file, then the pages (an open tab keeps emailing as before;
-- a new page's Copy for WhatsApp before this file reads Not available
-- yet). `supplier-mail` is unchanged: `feedback_mail_begin` calls
-- `feedback_request` with three arguments, which the new default fills.
-- Safe to run twice. Its only drop is the three-argument
-- `feedback_request`, made again below with four.
-- ROLLBACK: drop `feedback_wa_copy` and the four-argument
-- `feedback_request`; run RETENTION AND JOBS HELD's `feedback_request` and
-- ONE REQUEST REFERENCE's `feedback_client` again; the column may stay.
-- ===========================================================================

-- FEEDBACK COPIED FOR WHATSAPP -------------------------------------------------

alter table public.feedback_requests add column if not exists channel text not null default 'email';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'feedback_requests_channel_check') then
    alter table public.feedback_requests add constraint feedback_requests_channel_check
      check (channel in ('email', 'whatsapp'));
  end if;
end $$;

-- A changed signature drops the old one first: PostgREST cannot choose
-- between overloads a call fits.
drop function if exists public.feedback_request(uuid, text, boolean);

create or replace function public.feedback_request(p_client uuid, p_kind text, p_again boolean default false,
  p_channel text default 'email')
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_cl   public.clients;
  v_ct   public.client_contacts;
  v_mgr  public.team_members;
  v_key  text;
  v_req  public.feedback_requests;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind is null or p_kind not in ('quick', 'review') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_channel is null or p_channel not in ('email', 'whatsapp') then return jsonb_build_object('error', 'bad-channel'); end if;
  select * into v_cl from public.clients c where c.id = p_client;
  if v_cl.id is null or not public.client_seen(v_cl.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if v_cl.stage in ('lead', 'contacted', 'proposal', 'past') then return jsonb_build_object('error', 'not-active'); end if;
  -- An email needs the primary contact's address; a copy for WhatsApp
  -- needs the contact alone (their name and language).
  select * into v_ct from public.client_contacts k
   where k.client_id = p_client and k.is_primary and k.archived_at is null
     and (p_channel = 'whatsapp' or nullif(btrim(coalesce(k.email, '')), '') is not null)
   limit 1;
  if v_ct.id is null then
    return jsonb_build_object('error', case when p_channel = 'whatsapp' then 'no-primary' else 'no-contact' end);
  end if;
  perform pg_advisory_xact_lock(hashtext('feedback_request:' || p_client::text || ':' || p_kind));
  -- None while one is still going out, and none again within the repeat
  -- hours unless asked again, whichever way either went.
  if exists (select 1 from public.feedback_requests r where r.client_id = p_client and r.kind = p_kind
              and r.mail_status = 'sending' and r.created_at > now() - interval '10 minutes') then
    return jsonb_build_object('error', 'sending');
  end if;
  select * into v_req from public.feedback_requests r
   where r.client_id = p_client and r.kind = p_kind and coalesce(r.mail_status, 'sent') not in ('failed', 'sending')
     and r.closed_reason is distinct from 'withdrawn'
     and r.created_at > now() - make_interval(hours => coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24)::int)
   order by r.created_at desc limit 1;
  if v_req.id is not null and not coalesce(p_again, false) then
    return jsonb_build_object('error', 'recent', 'recent',
      jsonb_build_object('at', v_req.created_at, 'by', v_req.sent_by_name, 'to', v_req.sent_to_name,
        'channel', v_req.channel));
  end if;
  v_req := null;
  select * into v_mgr from public.team_members m
   where m.active and lower(btrim(m.name)) = lower(btrim(coalesce(v_cl.owner, '')))
   order by m.created_at limit 1;
  update public.feedback_requests r set closed_at = now(), closed_reason = 'replaced'
   where r.client_id = p_client and r.kind = p_kind and r.closed_at is null;
  loop
    v_key := public.new_link_key() || public.new_link_key();
    exit when not exists (select 1 from public.feedback_requests r where r.access_key = v_key);
  end loop;
  insert into public.feedback_requests (client_id, kind, access_key, sent_by, sent_by_name, contact_id,
    sent_to_name, sent_to_email, manager_id, manager_name, channel)
  values (p_client, p_kind, v_key, me.id, me.name, v_ct.id, v_ct.name, nullif(lower(btrim(coalesce(v_ct.email, ''))), ''),
    v_mgr.id, coalesce(v_mgr.name, nullif(btrim(coalesce(v_cl.owner, '')), '')), p_channel)
  returning * into v_req;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', v_cl.name,
          (case p_kind when 'quick' then 'Service rating' else 'Performance review' end)
          || ' requested from ' || v_ct.name
          || case when p_channel = 'whatsapp' then ', copied for WhatsApp' else '' end);
  return jsonb_build_object('ok', true, 'id', v_req.id, 'key', v_req.access_key, 'kind', v_req.kind,
    'to_name', v_req.sent_to_name, 'to_email', v_req.sent_to_email, 'lang', coalesce(v_ct.lang, 'en'),
    'manager', v_req.manager_name, 'created_at', v_req.created_at, 'channel', v_req.channel);
end $$;
revoke all on function public.feedback_request(uuid, text, boolean, text) from public, anon;
grant execute on function public.feedback_request(uuid, text, boolean, text) to authenticated;

/* Copy for WhatsApp: the request made, then its words as plain text for
   the colleague to paste into the client's group. */
create or replace function public.feedback_wa_copy(p_client uuid, p_kind text, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  r     jsonb;
  v_cl  public.clients;
  v_ct  public.client_contacts;
  v_t   public.feedback_email_templates;
  v_zh  boolean;
  v_url text;
  v_b   text;
  v_btn text;
  v_k   text;
  v_v   text;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('whatsapp') then return jsonb_build_object('error', 'send-off'); end if;
  if p_kind in ('quick', 'review')
     and (select count(*) from public.feedback_email_templates x where x.kind = p_kind) < 2 then
    return jsonb_build_object('error', 'not-found');
  end if;
  r := public.feedback_request(p_client, p_kind, p_again, 'whatsapp');
  if r ? 'error' then return r; end if;
  select * into v_cl from public.clients c where c.id = p_client;
  select * into v_ct from public.client_contacts k
   where k.id = (select q.contact_id from public.feedback_requests q where q.id = (r->>'id')::uuid);
  v_zh := coalesce(v_ct.lang, 'en') = 'zh';
  select * into v_t from public.feedback_email_templates x
   where x.kind = p_kind and x.lang = case when v_zh then 'zh' else 'en' end;
  v_url := 'https://digital.adspace.me/feedback/?k=' || (r->>'key');
  v_b := v_t.body;
  v_btn := v_t.button;
  foreach v_k in array array['contact name', 'client name', 'link'] loop
    v_v := case v_k when 'contact name' then public.contact_named(v_ct.salutation, v_ct.name)
      when 'client name' then v_cl.name else v_url end;
    v_b := regexp_replace(v_b, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_btn := regexp_replace(v_btn, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  -- The email's button is the link's words here; a message already
  -- holding the link keeps it where it was written.
  if position(v_url in v_b) = 0 then
    v_b := btrim(v_b) || E'\n\n' || btrim(v_btn) || case when v_zh then '：' else ': ' end || v_url;
  end if;
  return r || jsonb_build_object('text', v_b, 'lang', case when v_zh then 'zh' else 'en' end);
end $$;
revoke all on function public.feedback_wa_copy(uuid, text, boolean) from public, anon;
grant execute on function public.feedback_wa_copy(uuid, text, boolean) to authenticated;

create or replace function public.feedback_client(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true, 'requests', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'kind', r.kind, 'created_at', r.created_at, 'sent_by', r.sent_by_name,
             'to_name', r.sent_to_name, 'to_email', r.sent_to_email, 'manager', r.manager_name,
             'channel', r.channel,
             'opened_at', r.opened_at, 'answered_at', r.answered_at, 'closed_at', r.closed_at,
             'closed_reason', r.closed_reason,
             'response', case when s.id is null then null else jsonb_build_object(
               'id', s.id, 'score', s.score, 'band', s.band, 'submitted_at', s.submitted_at, 'by', s.contact_name, 'request_ref', s.request_ref,
               'max', (select x.scale_max from public.feedback_questions x where x.kind = s.kind and x.lead),
               'manager_score', case when public.feedback_sees_manager(s.manager_id) then s.manager_score end,
               'answers', public.feedback_answers_of(s, r.manager_name, public.feedback_sees_manager(s.manager_id)),
               'task_id', s.followup_task_id,
               'task_done', (select t.completed_at is not null from public.ops_tasks t where t.id = s.followup_task_id)) end)
           order by r.created_at desc)
      from public.feedback_requests r
      left join public.feedback_responses s on s.request_id = r.id
     where r.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.feedback_client(uuid) from public, anon;
grant execute on function public.feedback_client(uuid) to authenticated;

-- END OF FEEDBACK COPIED FOR WHATSAPP ------------------------------------------

select public.functions_tidy();
