-- ===========================================================================
-- FEEDBACK FROM PAST CLIENTS (2026-11-27)
-- ===========================================================================
-- WHY (the user, 2026-11-27: "what if clients ended and the following month
-- i wanna get feedback"): Request feedback was refused for a Past client,
-- and a link already sent read Closed the day its client moved to Past. A
-- client is asked while Active, Paused or Past; a lead never.
--
-- WHAT CHANGES
--   * `feedback_request` (restated whole from FEEDBACK COPIED FOR WHATSAPP)
--     refuses a lead alone (`not-active`), no longer a Past client; by email
--     and copied for WhatsApp alike.
--   * `feedback_read` and `feedback_submit` (restated whole from ONE
--     REQUEST REFERENCE FOR EVERY PUBLIC SUBMISSION) no longer close a link
--     because its client is Past. The link answers its one request whatever
--     the client's portal access: neither asks `portal_client_open`.
--
-- ORDER: this file, then the pages (an open tab draws Request feedback on a
-- Past client already; before this file it is refused as before). Safe to
-- run twice.
-- ROLLBACK: run `feedback_request` from FEEDBACK COPIED FOR WHATSAPP and
-- `feedback_read` and `feedback_submit` from ONE REQUEST REFERENCE FOR
-- EVERY PUBLIC SUBMISSION again.
-- ===========================================================================

-- FEEDBACK FROM PAST CLIENTS ---------------------------------------------------

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
  if v_cl.stage in ('lead', 'contacted', 'proposal') then return jsonb_build_object('error', 'not-active'); end if;
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

create or replace function public.feedback_read(p_key text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_req  public.feedback_requests;
  v_cl   public.clients;
  v_lang text;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{16}$' then
    perform public.feedback_throttle(true);
    return jsonb_build_object('error', 'not_found');
  end if;
  select * into v_req from public.feedback_requests r where r.access_key = p_key;
  if not public.feedback_throttle(v_req.id is null) then return jsonb_build_object('error', 'busy'); end if;
  if v_req.id is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_cl from public.clients c where c.id = v_req.client_id;
  if v_req.closed_reason = 'answered' then
    return jsonb_build_object('error', 'answered', 'answered_at', v_req.answered_at, 'kind', v_req.kind, 'client', v_cl.name,
      'request_ref', (select s.request_ref from public.feedback_responses s where s.request_id = v_req.id));
  end if;
  if v_req.closed_at is not null then
    return jsonb_build_object('error', 'closed', 'client', v_cl.name);
  end if;
  if v_req.opened_at is null then
    update public.feedback_requests r set opened_at = now() where r.id = v_req.id;
  end if;
  select k.lang into v_lang from public.client_contacts k where k.id = v_req.contact_id;
  return jsonb_build_object('ok', true, 'kind', v_req.kind, 'client', v_cl.name,
    'requested_at', v_req.created_at, 'manager', v_req.manager_name, 'lang', coalesce(v_lang, 'en'),
    'questions', public.feedback_questions_of(v_req.kind, v_req.manager_name));
end $$;
revoke all on function public.feedback_read(text) from public;
grant execute on function public.feedback_read(text) to anon, authenticated;

create or replace function public.feedback_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_req   public.feedback_requests;
  v_cl    public.clients;
  a       jsonb := coalesce(p_answers, '{}'::jsonb);
  q       record;
  v_out   jsonb := '{}'::jsonb;
  v_val   text;
  v_int   int;
  v_lead  int;
  v_band  text;
  v_mgr   int;
  v_ct    public.client_contacts;
  v_resp  uuid;
  v_kword text;
  v_ref   text;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{16}$' then
    perform public.feedback_throttle(true);
    return jsonb_build_object('error', 'not_found');
  end if;
  if jsonb_typeof(a) <> 'object' then return jsonb_build_object('error', 'bad-answers'); end if;
  select * into v_req from public.feedback_requests r where r.access_key = p_key for update;
  if not public.feedback_throttle(v_req.id is null) then return jsonb_build_object('error', 'busy'); end if;
  if v_req.id is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_cl from public.clients c where c.id = v_req.client_id;
  if v_req.closed_reason = 'answered' then
    return jsonb_build_object('error', 'answered', 'answered_at', v_req.answered_at,
      'request_ref', (select s.request_ref from public.feedback_responses s where s.request_id = v_req.id));
  end if;
  if v_req.closed_at is not null then return jsonb_build_object('error', 'closed'); end if;

  -- The lead question first: its band chooses which note is asked.
  for q in select * from public.feedback_questions x
            where x.kind = v_req.kind and x.lead loop
    v_val := a ->> q.key;
    if v_val is null or v_val !~ '^[0-9]{1,2}$' then return jsonb_build_object('error', 'required', 'key', q.key); end if;
    v_lead := v_val::int;
    if v_lead < q.scale_min or v_lead > q.scale_max then return jsonb_build_object('error', 'bad-score', 'key', q.key); end if;
    v_band := case when v_lead <= q.band_low_max then 'low' when v_lead <= q.band_mid_max then 'mid' else 'high' end;
  end loop;
  if v_lead is null then return jsonb_build_object('error', 'bad-kind'); end if;

  for q in select * from public.feedback_questions x
            where x.kind = v_req.kind
              and (not x.about_manager or v_req.manager_name is not null)
              and (x.band is null or x.band = v_band)
            order by x.n loop
    v_val := a ->> q.key;
    if q.type = 'scale' then
      if v_val is null or v_val !~ '^[0-9]{1,2}$' then
        if q.required then return jsonb_build_object('error', 'required', 'key', q.key); end if;
        continue;
      end if;
      v_int := v_val::int;
      if v_int < q.scale_min or v_int > q.scale_max then return jsonb_build_object('error', 'bad-score', 'key', q.key); end if;
      v_out := v_out || jsonb_build_object(q.key, v_int);
      if q.about_manager then v_mgr := v_int; end if;
    else
      v_val := nullif(btrim(coalesce(v_val, '')), '');
      if v_val is null then
        if q.required then return jsonb_build_object('error', 'required', 'key', q.key); end if;
        continue;
      end if;
      if length(v_val) > 2000 then return jsonb_build_object('error', 'too-long', 'key', q.key); end if;
      v_out := v_out || jsonb_build_object(q.key, v_val);
    end if;
  end loop;

  -- A signed-in contact of this client is named; anyone else is the link.
  if public.portal_contact_name(v_req.client_id) is not null then
    select * into v_ct from public.client_contacts k
     where k.client_id = v_req.client_id and k.portal_access and k.archived_at is null
       and lower(k.email) = lower(auth.jwt() ->> 'email')
     order by k.is_primary desc limit 1;
  end if;

  insert into public.feedback_responses (request_id, client_id, kind, answers, score, band,
    manager_id, manager_score, contact_id, contact_name)
  values (v_req.id, v_req.client_id, v_req.kind, v_out, v_lead, v_band,
    v_req.manager_id, v_mgr, v_ct.id, v_ct.name)
  returning id, request_ref into v_resp, v_ref;
  update public.feedback_requests r set answered_at = now(), closed_at = now(), closed_reason = 'answered',
         opened_at = coalesce(r.opened_at, now())
   where r.id = v_req.id;

  v_kword := case v_req.kind when 'quick' then 'Service rating' else 'Performance review' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_ct.name, 'Feedback form'), 'client.edited', v_cl.name,
          v_kword || ' answered: ' || v_lead || ' of ' ||
          (select x.scale_max from public.feedback_questions x where x.kind = v_req.kind and x.lead) ||
          coalesce(' · ' || v_ref, ''));
  -- The account manager told, else whoever sent it; a low score says so.
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.feedback',
         case when v_band = 'low' then 'Low score · ' else 'Feedback received · ' end || v_cl.name,
         v_kword || ': ' || v_lead || ' of ' ||
         (select x.scale_max from public.feedback_questions x where x.kind = v_req.kind and x.lead) ||
         case when v_band = 'low' then '. Open the client''s Feedback to follow up.' else '.' end,
         v_cl.id, 'client.feedback:' || v_resp || ':' || m.id
    from public.team_members m
   where m.active and m.id = coalesce(v_req.manager_id, v_req.sent_by)
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true, 'request_ref', v_ref);
end $$;
revoke all on function public.feedback_submit(text, jsonb) from public;
grant execute on function public.feedback_submit(text, jsonb) to anon, authenticated;

-- END OF FEEDBACK FROM PAST CLIENTS --------------------------------------------

select public.functions_tidy();
