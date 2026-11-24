-- ===========================================================================
-- CLIENT FEEDBACK — the portal's own Service rating and Performance review,
-- asked of a client only when a colleague requests one (2026-11-24)
-- ===========================================================================
-- WHY (the user, 2026-11-24): the agency's external surveys move into the
-- portal, "comprises of both Quick Feedback and Performance Review",
-- answered signed in to /client/ or on a client-specific link; then "dont
-- make it monthly recurring, only do it when our internal send a request",
-- "please allow to rate the account manager too"; mockups approved as
-- version 3 ("go feedback").
--
-- WHAT IT ADDS
--   * `feedback_questions`: the two forms' questions, fixed (kind `quick`,
--     the client's Service rating; kind `review`, the Performance review),
--     English and Chinese, each scale with its two ends; `{name}` stands for
--     the account manager. Seeded into an empty table alone.
--   * `feedback_requests`: one a request (the client, the form, its link key,
--     who sent it and to whom, the account manager at sending, opened,
--     answered, closed and why). A new request of the same form closes the
--     open one (`replaced`); an answer closes it (`answered`).
--   * `feedback_responses`: one a request (the answers, the lead score and
--     its band, the account manager's score, the contact where signed in,
--     a follow-up task).
--   * `feedback_hits`: one row a caller's address, the public path's count
--     for the hour (120 calls, 20 unknown keys).
--   All four: RLS on, no policy, no grant; functions alone read and write.
--   * `feedback_request(p_client, p_kind)` (Clients at Work, the client in
--     scope): to the client's primary contact with an email; answers the key.
--   * `feedback_withdraw(p_id)` (Clients at Work): closes an open request.
--   * `feedback_read(p_key)` (anon): the form for that request alone, else
--     `not_found`, `answered` (with its day) or `closed`.
--   * `feedback_submit(p_key, p_answers)` (anon): once a request, every
--     scale required, a note held to 2,000 characters; a signed-in contact of
--     the client is recorded; the account manager told (a low score said so).
--   * `portal_feedback(p_client)` (a signed-in contact): the open request's
--     key and the client's past answers, read only.
--   * `feedback_client(p_client)` (Clients at View, in scope): every request
--     and answer; the account manager's own score only to who may see it.
--   * `feedback_followup(p_response, p_task)` (My Work at Work): a low
--     score's follow-up task linked.
--   * `feedback_figures(p_from, p_to)` (Clients at View): the Service rating,
--     NPS, low scores open, by Person in charge, and clients not asked lately.
--   * `feedback_sees_manager(p_member)` (helper): the colleague, the group
--     their group reports to, Clients at Manage, an admin.
--
-- ORDER: 2026-10-07-function-hygiene.sql again (its `open_to_anon` now
-- names `feedback_read` and `feedback_submit`), then this file. No page calls
-- these yet, so an open tab meets nothing new. Safe to run twice. Rollback: drop the nine functions and
-- the four tables (`feedback_hits`, `feedback_responses`, `feedback_requests`,
-- `feedback_questions`), in that order.
-- ===========================================================================

create table if not exists public.feedback_questions (
  kind          text not null check (kind in ('quick', 'review')),
  key           text not null,
  n             int  not null,
  type          text not null check (type in ('scale', 'text')),
  scale_min     int,
  scale_max     int,
  band          text check (band in ('low', 'mid', 'high')),
  band_low_max  int,
  band_mid_max  int,
  lead          boolean not null default false,
  about_manager boolean not null default false,
  required      boolean not null default true,
  text_en       text not null,
  text_zh       text not null,
  low_en        text,
  low_zh        text,
  high_en       text,
  high_zh       text,
  primary key (kind, key)
);
alter table public.feedback_questions enable row level security;
revoke all on public.feedback_questions from anon, authenticated;

insert into public.feedback_questions
  (kind, key, n, type, scale_min, scale_max, band, band_low_max, band_mid_max, lead, about_manager, required,
   text_en, text_zh, low_en, low_zh, high_en, high_zh)
select * from (values
  ('quick', 'quality', 1, 'scale', 1, 10, null, 4, 7, true, false, true,
   'How would you rate the quality of ADspace''s services?', '您如何评价ADspace的服务质量？',
   'Very poor', '极差', 'Excellent', '极好'),
  ('quick', 'manager', 2, 'scale', 1, 5, null, null, null, false, true, true,
   'How satisfied are you with {name}, your account manager?', '您对客户经理{name}满意吗？',
   'Not satisfied', '不满意', 'Very satisfied', '非常满意'),
  ('quick', 'liked', 3, 'text', null, null, 'high', null, null, false, false, false,
   'Please describe what you liked most.', '请说明您最满意的地方。', null, null, null, null),
  ('quick', 'better', 3, 'text', null, null, 'mid', null, null, false, false, false,
   'Please describe where ADspace could do better.', '请说明ADspace可改进之处。', null, null, null, null),
  ('quick', 'short', 3, 'text', null, null, 'low', null, null, false, false, false,
   'Please describe what fell short, so that ADspace can put it right.', '请说明未达期望之处，以便ADspace及时改进。', null, null, null, null),
  ('review', 'nps', 1, 'scale', 0, 10, null, 6, 8, true, false, true,
   'How likely are you to recommend ADspace to a business associate?', '您向业务伙伴推荐ADspace的可能性有多大？',
   'Not at all likely', '完全不可能', 'Extremely likely', '极有可能'),
  ('review', 'creative', 2, 'scale', 1, 10, null, null, null, false, false, true,
   'How satisfied are you with the creativity and effectiveness of ADspace''s work?', '您对ADspace作品的创意与成效满意吗？',
   'Not satisfied', '不满意', 'Very satisfied', '非常满意'),
  ('review', 'content', 3, 'scale', 1, 10, null, null, null, false, false, true,
   'How would you rate the quality and relevance of the content produced?', '您如何评价所制作内容的质量与相关性？',
   'Very poor', '极差', 'Excellent', '极好'),
  ('review', 'design', 4, 'scale', 1, 10, null, null, null, false, false, true,
   'How would you rate the design quality of the materials produced?', '您如何评价所制作物料的设计质量？',
   'Very poor', '极差', 'Excellent', '极好'),
  ('review', 'brand', 5, 'scale', 1, 10, null, null, null, false, false, true,
   'How well does the ADspace team understand your brand and audience?', 'ADspace团队对您的品牌与受众了解程度如何？',
   'Not at all well', '完全不了解', 'Extremely well', '非常了解'),
  ('review', 'collab', 6, 'scale', 1, 10, null, null, null, false, false, true,
   'How would you rate communication and collaboration with the ADspace team?', '您如何评价与ADspace团队的沟通与协作？',
   'Very poor', '极差', 'Excellent', '极好'),
  ('review', 'respond', 7, 'scale', 1, 10, null, null, null, false, false, true,
   'How would you rate the team''s responsiveness and initiative?', '您如何评价团队的响应速度与主动性？',
   'Very poor', '极差', 'Excellent', '极好'),
  ('review', 'sales', 8, 'scale', 1, 10, null, null, null, false, false, true,
   'How much has ADspace''s work contributed to your sales performance?', 'ADspace的工作对您的销售业绩贡献有多大？',
   'No contribution', '没有贡献', 'Significant contribution', '贡献显著'),
  ('review', 'manager', 9, 'scale', 1, 10, null, null, null, false, true, true,
   'How would you rate {name} as your account manager?', '您如何评价客户经理{name}？',
   'Very poor', '极差', 'Excellent', '极好'),
  ('review', 'manager_note', 10, 'text', null, null, null, null, null, false, true, false,
   'Comments about {name}', '关于{name}的意见', null, null, null, null),
  ('review', 'comments', 11, 'text', null, null, null, null, null, false, false, false,
   'Additional comments or suggestions', '其他意见或建议', null, null, null, null)
) as v(kind, key, n, type, scale_min, scale_max, band, band_low_max, band_mid_max, lead, about_manager, required,
       text_en, text_zh, low_en, low_zh, high_en, high_zh)
where not exists (select 1 from public.feedback_questions);

create table if not exists public.feedback_requests (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.clients(id) on delete cascade,
  kind          text not null check (kind in ('quick', 'review')),
  access_key    text not null unique,
  sent_by       uuid references public.team_members(id) on delete set null,
  sent_by_name  text,
  contact_id    uuid references public.client_contacts(id) on delete set null,
  sent_to_name  text,
  sent_to_email text,
  manager_id    uuid references public.team_members(id) on delete set null,
  manager_name  text,
  created_at    timestamptz not null default now(),
  opened_at     timestamptz,
  answered_at   timestamptz,
  closed_at     timestamptz,
  closed_reason text check (closed_reason in ('answered', 'replaced', 'withdrawn'))
);
create index if not exists feedback_requests_client_idx on public.feedback_requests (client_id, created_at desc);
create unique index if not exists feedback_requests_one_open on public.feedback_requests (client_id, kind) where closed_at is null;
alter table public.feedback_requests enable row level security;
revoke all on public.feedback_requests from anon, authenticated;

create table if not exists public.feedback_responses (
  id               uuid primary key default gen_random_uuid(),
  request_id       uuid not null unique references public.feedback_requests(id) on delete cascade,
  client_id        uuid not null references public.clients(id) on delete cascade,
  kind             text not null check (kind in ('quick', 'review')),
  answers          jsonb not null default '{}'::jsonb,
  score            int not null,
  band             text not null check (band in ('low', 'mid', 'high')),
  manager_id       uuid references public.team_members(id) on delete set null,
  manager_score    int,
  contact_id       uuid references public.client_contacts(id) on delete set null,
  contact_name     text,
  submitted_at     timestamptz not null default now(),
  followup_task_id uuid references public.ops_tasks(id) on delete set null
);
create index if not exists feedback_responses_client_idx on public.feedback_responses (client_id, submitted_at desc);
create index if not exists feedback_responses_manager_idx on public.feedback_responses (manager_id, submitted_at desc);
alter table public.feedback_responses enable row level security;
revoke all on public.feedback_responses from anon, authenticated;

create table if not exists public.feedback_hits (
  ip    text primary key,
  hour  timestamptz not null,
  n     int not null default 0,
  bad   int not null default 0
);
alter table public.feedback_hits enable row level security;
revoke all on public.feedback_hits from anon, authenticated;

/* The public path's count: a caller's calls in the hour, and its unknown
   keys. One row an address, started again each hour, so nothing grows. */
create or replace function public.feedback_throttle(p_bad boolean default false)
returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare
  v_ip   text := coalesce(nullif(public.request_ip(), ''), 'none');
  v_hour timestamptz := date_trunc('hour', now());
  v_row  public.feedback_hits;
begin
  insert into public.feedback_hits as h (ip, hour, n, bad)
  values (v_ip, v_hour, 1, case when p_bad then 1 else 0 end)
  on conflict (ip) do update
     set n    = case when h.hour < v_hour then 1 else h.n + 1 end,
         bad  = case when h.hour < v_hour then (case when p_bad then 1 else 0 end)
                     else h.bad + (case when p_bad then 1 else 0 end) end,
         hour = v_hour
  returning * into v_row;
  return v_row.n <= 120 and v_row.bad <= 20;
end $$;
revoke all on function public.feedback_throttle(boolean) from public, anon, authenticated;

/* May the caller read a colleague's own score as account manager: the
   colleague, a colleague of the group theirs reports to, Clients at Manage,
   an admin. */
create or replace function public.feedback_sees_manager(p_member uuid)
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text;
begin
  if me.id is null or p_member is null then return false; end if;
  if me.id = p_member or me.is_admin or public.allowed('clients', 'manage') then return true; end if;
  select m.role into v_role from public.team_members m where m.id = p_member;
  return exists (select 1 from public.team_roles r where r.slug = v_role and r.reports_to = me.role);
end $$;
revoke all on function public.feedback_sees_manager(uuid) from public, anon, authenticated;

/* A request's questions, the account manager's name put in, theirs left
   out where none was named. */
create or replace function public.feedback_questions_of(p_kind text, p_manager text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', q.key, 'n', q.n, 'type', q.type, 'min', q.scale_min, 'max', q.scale_max,
           'band', q.band, 'band_low_max', q.band_low_max, 'band_mid_max', q.band_mid_max,
           'lead', q.lead, 'manager', q.about_manager, 'required', q.required,
           'en', replace(q.text_en, '{name}', coalesce(p_manager, '')),
           'zh', replace(q.text_zh, '{name}', coalesce(p_manager, '')),
           'low_en', q.low_en, 'low_zh', q.low_zh, 'high_en', q.high_en, 'high_zh', q.high_zh)
         order by q.n, q.band nulls first), '[]'::jsonb)
    from public.feedback_questions q
   where q.kind = p_kind
     and (not q.about_manager or nullif(btrim(coalesce(p_manager, '')), '') is not null)
$$;
revoke all on function public.feedback_questions_of(text, text) from public, anon, authenticated;

/* A request: to the client's primary contact, the open one of the same form
   closed first. The page sends the email; the key is answered to it. */
create or replace function public.feedback_request(p_client uuid, p_kind text)
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
  select * into v_cl from public.clients c where c.id = p_client;
  if v_cl.id is null or not public.client_seen(v_cl.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if v_cl.stage in ('lead', 'contacted', 'proposal', 'past') then return jsonb_build_object('error', 'not-active'); end if;
  select * into v_ct from public.client_contacts k
   where k.client_id = p_client and k.is_primary and k.archived_at is null
     and nullif(btrim(coalesce(k.email, '')), '') is not null
   limit 1;
  if v_ct.id is null then return jsonb_build_object('error', 'no-contact'); end if;
  perform pg_advisory_xact_lock(hashtext('feedback_request:' || p_client::text || ':' || p_kind));
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
    sent_to_name, sent_to_email, manager_id, manager_name)
  values (p_client, p_kind, v_key, me.id, me.name, v_ct.id, v_ct.name, lower(btrim(v_ct.email)),
    v_mgr.id, coalesce(v_mgr.name, nullif(btrim(coalesce(v_cl.owner, '')), '')))
  returning * into v_req;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', v_cl.name,
          (case p_kind when 'quick' then 'Service rating' else 'Performance review' end)
          || ' requested from ' || v_ct.name);
  return jsonb_build_object('ok', true, 'id', v_req.id, 'key', v_req.access_key, 'kind', v_req.kind,
    'to_name', v_req.sent_to_name, 'to_email', v_req.sent_to_email, 'lang', coalesce(v_ct.lang, 'en'),
    'manager', v_req.manager_name, 'created_at', v_req.created_at);
end $$;
revoke all on function public.feedback_request(uuid, text) from public, anon;
grant execute on function public.feedback_request(uuid, text) to authenticated;

create or replace function public.feedback_withdraw(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  v_req public.feedback_requests;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_req from public.feedback_requests r where r.id = p_id for update;
  if v_req.id is null or not public.client_seen(v_req.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if v_req.closed_at is not null then return jsonb_build_object('error', 'closed'); end if;
  update public.feedback_requests r set closed_at = now(), closed_reason = 'withdrawn' where r.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  select me.name, 'client.edited', c.name,
         (case v_req.kind when 'quick' then 'Service rating' else 'Performance review' end) || ' request withdrawn'
    from public.clients c where c.id = v_req.client_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.feedback_withdraw(uuid) from public, anon;
grant execute on function public.feedback_withdraw(uuid) to authenticated;

/* The public read: the form for this request alone. */
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
    return jsonb_build_object('error', 'answered', 'answered_at', v_req.answered_at, 'kind', v_req.kind, 'client', v_cl.name);
  end if;
  if v_req.closed_at is not null or v_cl.stage = 'past' then
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

/* The answer: once a request, whoever opens its link first. */
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
  if v_req.closed_reason = 'answered' then return jsonb_build_object('error', 'answered', 'answered_at', v_req.answered_at); end if;
  if v_req.closed_at is not null or v_cl.stage = 'past' then return jsonb_build_object('error', 'closed'); end if;

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
  returning id into v_resp;
  update public.feedback_requests r set answered_at = now(), closed_at = now(), closed_reason = 'answered',
         opened_at = coalesce(r.opened_at, now())
   where r.id = v_req.id;

  v_kword := case v_req.kind when 'quick' then 'Service rating' else 'Performance review' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_ct.name, 'Feedback form'), 'client.edited', v_cl.name,
          v_kword || ' answered: ' || v_lead || ' of ' ||
          (select x.scale_max from public.feedback_questions x where x.kind = v_req.kind and x.lead));
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
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.feedback_submit(text, jsonb) from public;
grant execute on function public.feedback_submit(text, jsonb) to anon, authenticated;

/* A response as a reader sees it: each question with its answer. */
create or replace function public.feedback_answers_of(p_resp public.feedback_responses, p_manager text, p_with_manager boolean)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', q.key, 'type', q.type, 'max', q.scale_max, 'band', q.band, 'manager', q.about_manager,
           'en', replace(q.text_en, '{name}', coalesce(p_manager, '')),
           'zh', replace(q.text_zh, '{name}', coalesce(p_manager, '')),
           'high_en', q.high_en, 'high_zh', q.high_zh, 'low_en', q.low_en, 'low_zh', q.low_zh,
           'value', p_resp.answers -> q.key)
         order by q.n), '[]'::jsonb)
    from public.feedback_questions q
   where q.kind = p_resp.kind and p_resp.answers ? q.key
     and (p_with_manager or not q.about_manager)
$$;
revoke all on function public.feedback_answers_of(public.feedback_responses, text, boolean) from public, anon, authenticated;

/* The client portal: the open request's key, and past answers read only. */
create or replace function public.portal_feedback(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_open public.feedback_requests;
begin
  if public.portal_contact_name(p_client) is null then return jsonb_build_object('error', 'no-access'); end if;
  select * into v_open from public.feedback_requests r
   where r.client_id = p_client and r.closed_at is null
   order by r.created_at desc limit 1;
  return jsonb_build_object('ok', true,
    'open', case when v_open.id is null then null else jsonb_build_object(
      'key', v_open.access_key, 'kind', v_open.kind, 'requested_at', v_open.created_at,
      'manager', v_open.manager_name,
      'questions', public.feedback_questions_of(v_open.kind, v_open.manager_name)) end,
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'kind', s.kind, 'requested_at', r.created_at, 'submitted_at', s.submitted_at,
               'by', s.contact_name, 'score', s.score,
               'max', (select x.scale_max from public.feedback_questions x where x.kind = s.kind and x.lead),
               'answers', public.feedback_answers_of(s, r.manager_name, true))
             order by s.submitted_at desc)
        from public.feedback_responses s
        join public.feedback_requests r on r.id = s.request_id
       where s.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.portal_feedback(uuid) from public, anon;
grant execute on function public.portal_feedback(uuid) to authenticated;

/* The client record's Feedback part. */
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
             'opened_at', r.opened_at, 'answered_at', r.answered_at, 'closed_at', r.closed_at,
             'closed_reason', r.closed_reason,
             'response', case when s.id is null then null else jsonb_build_object(
               'id', s.id, 'score', s.score, 'band', s.band, 'submitted_at', s.submitted_at, 'by', s.contact_name,
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

/* A low score's follow-up task, made by the page as the colleague, linked. */
create or replace function public.feedback_followup(p_response uuid, p_task uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_resp public.feedback_responses;
begin
  if me.id is null or not public.allowed('ops', 'work') or not public.allowed('clients', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into v_resp from public.feedback_responses s where s.id = p_response for update;
  if v_resp.id is null or not public.client_seen(v_resp.client_id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  if v_resp.band <> 'low' then return jsonb_build_object('error', 'not-low'); end if;
  if not exists (select 1 from public.ops_tasks t where t.id = p_task and t.client_id = v_resp.client_id) then
    return jsonb_build_object('error', 'bad-task');
  end if;
  update public.feedback_responses s set followup_task_id = p_task where s.id = p_response;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.feedback_followup(uuid, uuid) from public, anon;
grant execute on function public.feedback_followup(uuid, uuid) to authenticated;

/* The figures: a period's Service rating, NPS over the reviews in it, low
   scores still open, by Person in charge (their own score as account
   manager only to who may see it), and active clients not asked lately. */
create or replace function public.feedback_figures(p_from date, p_to date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_from  timestamptz;
  v_to    timestamptz;
  v_prev  timestamptz;
  v_quiet int;
begin
  if me.id is null or not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then return jsonb_build_object('error', 'bad-period'); end if;
  v_from := p_from::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_to   := (p_to + 1)::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_prev := (p_from - (p_to - p_from + 1))::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_quiet := coalesce(public.app_setting('feedback_quiet_months', (now() at time zone 'Asia/Kuala_Lumpur')::date), 6)::int;
  return jsonb_build_object('ok', true,
    'rating', (select round(avg(s.score)::numeric, 1) from public.feedback_responses s
                where s.kind = 'quick' and s.submitted_at >= v_from and s.submitted_at < v_to and public.client_seen(s.client_id, 'view')),
    'rating_n', (select count(*) from public.feedback_responses s
                  where s.kind = 'quick' and s.submitted_at >= v_from and s.submitted_at < v_to and public.client_seen(s.client_id, 'view')),
    'nps', (select round(100.0 * (count(*) filter (where s.band = 'high') - count(*) filter (where s.band = 'low')) / nullif(count(*), 0))
              from public.feedback_responses s
             where s.kind = 'review' and s.submitted_at >= v_from and s.submitted_at < v_to and public.client_seen(s.client_id, 'view')),
    'nps_n', (select count(*) from public.feedback_responses s
               where s.kind = 'review' and s.submitted_at >= v_from and s.submitted_at < v_to and public.client_seen(s.client_id, 'view')),
    'low_open', (select count(*) from public.feedback_responses s
                  left join public.ops_tasks t on t.id = s.followup_task_id
                  where s.band = 'low' and t.completed_at is null and public.client_seen(s.client_id, 'view')),
    'low_oldest', (select min(s.submitted_at) from public.feedback_responses s
                    left join public.ops_tasks t on t.id = s.followup_task_id
                    where s.band = 'low' and t.completed_at is null and public.client_seen(s.client_id, 'view')),
    'quiet_months', v_quiet,
    'quiet', (select count(*) from public.clients c
               where c.stage = 'active' and public.client_seen(c.id, 'view')
                 and not exists (select 1 from public.feedback_requests r where r.client_id = c.id
                                  and r.created_at >= (now() - make_interval(months => v_quiet)))),
    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.manager_id, 'name', p.manager_name,
               'requested', p.requested, 'answered', p.answered, 'rating', p.rating, 'nps', p.nps,
               'manager_score', case when public.feedback_sees_manager(p.manager_id) then p.mgr end,
               'manager_max', case when public.feedback_sees_manager(p.manager_id) then
                 (select x.scale_max from public.feedback_questions x where x.kind = 'quick' and x.key = 'manager') end,
               'manager_before', case when public.feedback_sees_manager(p.manager_id) then p.mgr_before end)
             order by p.manager_name)
        from (
          select r.manager_id, max(r.manager_name) as manager_name,
                 count(*) filter (where r.created_at >= v_from and r.created_at < v_to) as requested,
                 count(s.id) filter (where s.submitted_at >= v_from and s.submitted_at < v_to) as answered,
                 round(avg(s.score) filter (where s.kind = 'quick' and s.submitted_at >= v_from and s.submitted_at < v_to)::numeric, 1) as rating,
                 round(100.0 * (count(*) filter (where s.kind = 'review' and s.band = 'high' and s.submitted_at >= v_from and s.submitted_at < v_to)
                              - count(*) filter (where s.kind = 'review' and s.band = 'low' and s.submitted_at >= v_from and s.submitted_at < v_to))
                       / nullif(count(*) filter (where s.kind = 'review' and s.submitted_at >= v_from and s.submitted_at < v_to), 0)) as nps,
                 round(avg(s.manager_score) filter (where s.kind = 'quick' and s.submitted_at >= v_from and s.submitted_at < v_to)::numeric, 1) as mgr,
                 round(avg(s.manager_score) filter (where s.kind = 'quick' and s.submitted_at >= v_prev and s.submitted_at < v_from)::numeric, 1) as mgr_before
            from public.feedback_requests r
            left join public.feedback_responses s on s.request_id = r.id
           where r.manager_id is not null and public.client_seen(r.client_id, 'view')
             and r.created_at >= v_prev and r.created_at < v_to
           group by r.manager_id
        ) p
       where p.requested > 0 or p.answered > 0), '[]'::jsonb));
end $$;
revoke all on function public.feedback_figures(date, date) from public, anon;
grant execute on function public.feedback_figures(date, date) to authenticated;

-- END OF CLIENT FEEDBACK ------------------------------------------------------
select public.functions_tidy();
