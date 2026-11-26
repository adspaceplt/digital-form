-- ===========================================================================
-- RETENTION AND JOBS HELD (2026-11-25)
-- ===========================================================================
-- WHY (the review of everything merged since 15 Nov, approved by the user
-- on 2026-11-25): personal data kept past its time, scheduled jobs that
-- miss a day or run twice, and emails that could go twice or stay stuck.
--
-- WHAT CHANGES
--   * `team_members.inactive_at`, stamped by `team_members_inactive_stamp`
--     (before update of active) when a colleague is set inactive and
--     cleared when set active; the colleagues already inactive take their
--     last change. `privacy_retention` (restated from ADDRESSES LET GO)
--     counts a leaver's health months from `coalesce(removed_at,
--     expired_at, inactive_at)`: one set inactive kept theirs for good. It
--     runs daily (`45 18 * * *`), not monthly.
--   * `hiring_retention` (restated from HIRING OUTCOMES) deletes a
--     candidate's offer and contract signing steps before the candidate.
--   * `health_daily` (restated from HEALTH CHECK-INS BY WORKLOAD) reminds
--     on any day from the reminder day to the period's end, so a day the
--     job missed is made up; the dedupe key still sends one.
--   * `supplier_email_begin` (restated from SUPPLIER EMAILS) takes the
--     supplier, purpose and document's lock and refuses `sending` for a
--     send under 10 minutes old, before `recent`, as `client_email_begin`.
--   * `feedback_request` and `feedback_mail_begin` take `p_again` (the old
--     two-argument ones dropped) and refuse, after the lock, `sending`
--     (under 10 minutes) and `recent` (within `wa_repeat_hours`, with when,
--     by whom and to whom) unless asked again.
--   * `hiring_outcome_mail_claim` and `hiring_expire_mail_claim` mark a
--     send still going out after 10 minutes `unknown` (the decision filed
--     on the candidate); the claim stamps `outcome_mail_at`.
--     `hiring_outcome_mail_kick` also wakes for a queued expiry email, and
--     `jobs_watch` tells the failed or unconfirmed candidate emails.
--   * `ops_tasks_nudge` and `ops_tasks_remind` send nothing on a public
--     holiday.
--   * `team_expire_access` ends access only while it still stands (active,
--     its end passed) and hands nothing back when no row changed.
--   * `ops_generate_recurring` takes the rule's lock before its made check.
--   * `ops_notifications (team_member_id, kind, created_at desc)` indexed.
--
-- ORDER: this file, then the pages and supplier-mail (which pass `again`
-- to the feedback request). An old page meanwhile reads `sending` or
-- `recent` as its general refusal; the old supplier-mail calls
-- feedback_mail_begin with two arguments, which the default answers.
-- Safe to run twice.
-- ROLLBACK: run each function from the band named above again (for the
-- feedback pair, drop the three-argument ones first), schedule
-- `privacy-retention` at `45 18 1 * *`, and drop the trigger; the column
-- and the index may stay.
-- ===========================================================================

-- RETENTION AND JOBS HELD ------------------------------------------------------

alter table public.team_members add column if not exists inactive_at timestamptz;
-- Those set inactive before this ran: their last change stands in.
update public.team_members t set inactive_at = coalesce(t.updated_at, now())
 where not t.active and t.inactive_at is null;

/* When a colleague was set inactive, cleared when they are set active
   again; privacy_retention counts a leaver's months from it. */
create or replace function public.team_members_inactive_stamp()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.active is distinct from old.active then
    new.inactive_at := case when new.active then null else coalesce(new.inactive_at, now()) end;
  end if;
  return new;
end $$;
revoke all on function public.team_members_inactive_stamp() from public, anon, authenticated;
create or replace trigger team_members_inactive_stamp before update of active on public.team_members
  for each row execute function public.team_members_inactive_stamp();

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0; v_hc integer := 0; v_hl integer := 0; v_lt integer := 0; v_vt integer := 0; v_vd integer := 0; v_vc integer := 0; v_hm integer := 0; v_qc integer := 0;
  v_fh integer := 0; v_qh integer := 0; v_vn integer := 0;
  v_today date := (p_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_keep integer := coalesce(public.app_setting('health_keep_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 24)::integer;
  v_left integer := coalesce(public.app_setting('health_leaver_months', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 6)::integer;
  v_gone uuid[];
begin
  update public.wa_outbox o
     set to_number = '', to_name = null, params = '[]'::jsonb, button = null
   where o.created_at < p_now - interval '12 months'
     and o.state not in ('queued', 'sending')
     and (o.to_number <> '' or o.to_name is not null or o.params <> '[]'::jsonb or o.button is not null);
  get diagnostics v_wa = row_count;
  delete from public.activity_log a where a.created_at < p_now - interval '3 years';
  get diagnostics v_act = row_count;
  delete from public.health_checkins k where k.half < v_today - make_interval(months => v_keep);
  get diagnostics v_hc = row_count;
  delete from public.health_moods k where k.period_start < v_today - make_interval(months => v_keep);
  get diagnostics v_hm = row_count;
  v_hc := v_hc + v_hm;
  select coalesce(array_agg(m.id), '{}') into v_gone from public.team_members m
   where not m.active and coalesce(m.removed_at, m.expired_at, m.inactive_at) < p_now - make_interval(months => v_left);
  if array_length(v_gone, 1) > 0 then
    delete from public.health_checkins k where k.team_member_id = any(v_gone);
    get diagnostics v_hl = row_count;
    delete from public.health_moods k where k.team_member_id = any(v_gone);
    get diagnostics v_hm = row_count;
    v_hl := v_hl + v_hm;
    delete from public.health_talks t where t.team_member_id = any(v_gone) or t.with_id = any(v_gone);
    delete from public.health_log l where l.team_member_id = any(v_gone);
    delete from public.health_consents c where c.team_member_id = any(v_gone);
  end if;
  -- A caller's address against a link's passcode, once it has had nothing
  -- to say for 30 days and holds no lock (audit 2026-10-18, item 14).
  delete from public.link_tries t
   where greatest(t.last_at, coalesce(t.ok_at, t.last_at)) < p_now - interval '30 days'
     and coalesce(t.locked_until, t.last_at) < p_now;
  get diagnostics v_lt = row_count;
  -- A caller's address against /verify/, once its hour began 30 days ago.
  delete from public.verify_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vt = row_count;
  -- And against /verify/'s details (VERIFY DETAILS, 2026-11-20).
  delete from public.verify_detail_tries v where v.since < p_now - interval '30 days';
  get diagnostics v_vd = row_count;
  -- And a check's address hash, 30 days after its day; the document's
  -- total stays (VERIFY CHECKS COUNTED, 2026-11-21).
  delete from public.verify_checks v where v.day < v_today - 30;
  get diagnostics v_vc = row_count;
  -- A caller's hourly count on /feedback/ and /quote/, a day after its
  -- hour (ADDRESSES LET GO, 2026-11-25): the count is read for the hour
  -- alone, so nothing older is needed.
  delete from public.feedback_hits h where h.hour < (p_now at time zone 'Asia/Kuala_Lumpur') - interval '1 day';
  get diagnostics v_fh = row_count;
  delete from public.quote_hits h where h.hour < (p_now at time zone 'Asia/Kuala_Lumpur') - interval '1 day';
  get diagnostics v_qh = row_count;
  -- And against /verify/'s name check, once its count began 30 days ago
  -- and it holds no lock.
  delete from public.verify_name_caller_tries v
   where v.since < p_now - interval '30 days'
     and coalesce(v.locked_until, v.since) < p_now;
  get diagnostics v_vn = row_count;
  -- And where a colleague copied a quotation's link, 30 days after the copy
  -- (QUOTATION COPIER'S OPENING, 2026-11-25).
  update public.quotation_link_copies c set ip = null where c.ip is not null and c.at < p_now - interval '30 days';
  get diagnostics v_qc = row_count;
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act,
    'health_checkins_removed', v_hc + v_hl, 'health_leavers', coalesce(array_length(v_gone, 1), 0),
    'link_tries_removed', v_lt, 'verify_tries_removed', v_vt, 'verify_detail_tries_removed', v_vd,
    'verify_checks_removed', v_vc, 'quotation_copiers_cleared', v_qc, 'feedback_hits_removed', v_fh, 'quote_hits_removed', v_qh,
    'verify_name_tries_removed', v_vn);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then return; end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'privacy-retention';
  perform cron.schedule('privacy-retention', '45 18 * * *', 'select public.privacy_retention()');
end $$;

create or replace function public.hiring_retention()
returns integer language plpgsql volatile security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days int := coalesce(public.app_setting('hiring_link_days', v_today)::int, 30);
  v_keep int := coalesce(public.app_setting('hiring_keep_months', v_today)::int, 12);
  v_n int;
  v_ids uuid[];
begin
  select coalesce(array_agg(c.id), '{}') into v_ids from public.hiring_candidates c
   where c.stage <> 'hired' and (
         (c.stage = 'pool' and c.pool_consent = 'yes' and c.pool_until < now())
      or (c.stage = 'pool' and c.pool_consent = 'asked' and c.outcome_at + make_interval(days => v_days) < now())
      or (c.stage = 'closed' and coalesce(c.outcome_at, c.updated_at) + make_interval(months => v_keep) < now())
      or (c.removed_at is not null and c.removed_at + make_interval(months => v_keep) < now()));
  -- Their offer's and contract's signing steps go with them (RETENTION AND
  -- JOBS HELD): the steps name the document, never the candidate, so the
  -- cascade never reached them.
  delete from public.signing_steps g
   where g.doc_kind = 'hiring_doc'
     and g.doc_id in (select d.id from public.hiring_docs d where d.candidate_id = any(v_ids));
  with gone as (
    delete from public.hiring_candidates c
     where c.id = any(v_ids)
    returning c.cv_path)
  insert into public.hiring_files_gone (path) select g.cv_path from gone g where g.cv_path is not null
  on conflict (path) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.hiring_retention() from public, anon, authenticated;

create or replace function public.health_daily(p_today date default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_today  date := coalesce(p_today, public.health_today());
  v_days   integer := coalesce(public.app_setting('health_remind_days', coalesce(p_today, public.health_today())), 2)::integer;
  v_alert  boolean := coalesce(public.app_setting('health_alert', coalesce(p_today, public.health_today())), 1) = 1;
  v_hol    boolean := public.public_holiday_on(coalesce(p_today, public.health_today())) is not null;
  v_p      jsonb;
  v_end    date;
  m        record;
  a        record;
  n        integer := 0;
begin
  for m in select t.id, t.name from public.team_members t
            where t.active and not coalesce(t.system, false) order by t.id loop
    v_p := public.health_period(m.id, v_today);
    v_end := (v_p ->> 'end')::date;
    if v_days > 0 and not v_hol and (v_p ->> 'due')::boolean and public.health_agreed(m.id)
       and v_today >= (v_p ->> 'start')::date + v_days and v_today <= v_end then
      insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
      values (m.id, null, 'health.remind',
              'Check in on your health by ' || public.register_day(v_end) || ' (' || trim(to_char(v_end, 'FMDay')) || ').',
              null, 'health.remind.' || m.id || '.' || (v_p ->> 'start'))
      on conflict (dedupe_key) do nothing;
      if found then n := n + 1; end if;
    end if;
    if v_alert and coalesce((v_p #>> '{load,heavy}')::boolean, false) then
      for a in select t.id from public.team_members t
                where t.active and t.id <> m.id and not coalesce(t.system, false)
                  and (coalesce(t.is_admin, false) or t.role = 'admin') loop
        insert into public.ops_notifications (team_member_id, task_id, kind, title, body, link, dedupe_key)
        values (a.id, null, 'health.load', 'Check in with ' || m.name || '.',
                'Their work this week is near their weekly capacity.',
                'https://digital.adspace.me/admin/?s=team&tab=health',
                'health.load.' || m.id || '.' || (v_p #>> '{load,week}') || '.' || a.id)
        on conflict (dedupe_key) do nothing;
        n := n + 1;
      end loop;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.health_daily(date) from public, anon, authenticated;

create or replace function public.supplier_email_begin(p_supplier uuid, p_purpose text, p_document uuid,
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
  -- One send at a time for a supplier, a purpose and a document, and none
  -- while one is still going out (RETENTION AND JOBS HELD), as
  -- client_email_begin does.
  perform pg_advisory_xact_lock(hashtext('supplier-email:' || coalesce(p_supplier::text, '') || ':' ||
    coalesce(p_purpose, '') || ':' || coalesce(p_document::text, '')));
  p := public.supplier_email_prepare(p_supplier, p_purpose, p_document);
  if p ? 'error' then return p; end if;
  if exists (select 1 from public.supplier_emails x where x.supplier_id = p_supplier and x.purpose = p_purpose
              and x.document_id is not distinct from case when p_purpose = 'document' then p_document end
              and x.status = 'sending' and x.created_at > now() - interval '10 minutes') then
    return jsonb_build_object('error', 'sending');
  end if;
  if (p->'recent') is not null and jsonb_typeof(p->'recent') = 'object' and not coalesce(p_again, false) then
    return jsonb_build_object('error', 'recent', 'recent', p->'recent');
  end if;
  v_s := btrim(regexp_replace(public.supplier_email_fill(p_subject, p->'values'), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(p_body, p->'values'), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  insert into public.supplier_emails (supplier_id, document_id, purpose, to_email, cc_email, subject, body, sent_by)
  values (p_supplier, case when p_purpose = 'document' then p_document end, p_purpose, p->'to'->>'email',
          case when coalesce(p_cc, false) then p->>'cc' end, v_s, v_b, me.id)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', p->'to', 'cc', case when coalesce(p_cc, false) then p->'cc' end,
    'subject', v_s, 'body', v_b, 'values', p->'values', 'document', p->'document');
end $$;
revoke all on function public.supplier_email_begin(uuid, text, uuid, boolean, text, text, boolean) from public, anon;
grant execute on function public.supplier_email_begin(uuid, text, uuid, boolean, text, text, boolean) to authenticated;

-- A changed signature drops the old one first: PostgREST cannot choose
-- between overloads a call fits.
drop function if exists public.feedback_mail_begin(uuid, text);
drop function if exists public.feedback_request(uuid, text);

create or replace function public.feedback_request(p_client uuid, p_kind text, p_again boolean default false)
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
  -- None while one is still going out, and none again within the repeat
  -- hours unless asked again (RETENTION AND JOBS HELD).
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
      jsonb_build_object('at', v_req.created_at, 'by', v_req.sent_by_name, 'to', v_req.sent_to_name));
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
revoke all on function public.feedback_request(uuid, text, boolean) from public, anon;
grant execute on function public.feedback_request(uuid, text, boolean) to authenticated;

create or replace function public.feedback_mail_begin(p_client uuid, p_kind text, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  r     jsonb;
  v_cl  public.clients;
  v_ct  public.client_contacts;
  v_t   public.feedback_email_templates;
  v_zh  boolean;
  v_s   text;
  v_b   text;
  v_btn text;
  v_k   text;
  v_v   text;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if coalesce(public.app_setting('client_email_on', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) <> 1 then
    return jsonb_build_object('error', 'email-off');
  end if;
  if p_kind in ('quick', 'review')
     and (select count(*) from public.feedback_email_templates x where x.kind = p_kind) < 2 then
    return jsonb_build_object('error', 'not-found');
  end if;
  r := public.feedback_request(p_client, p_kind, p_again);
  if r ? 'error' then return r; end if;
  select * into v_cl from public.clients c where c.id = p_client;
  select * into v_ct from public.client_contacts k
   where k.id = (select q.contact_id from public.feedback_requests q where q.id = (r->>'id')::uuid);
  v_zh := coalesce(v_ct.lang, 'en') = 'zh';
  select * into v_t from public.feedback_email_templates x
   where x.kind = p_kind and x.lang = case when v_zh then 'zh' else 'en' end;
  v_s := v_t.subject;
  v_b := v_t.body;
  v_btn := v_t.button;
  foreach v_k in array array['contact name', 'client name', 'link'] loop
    v_v := case v_k when 'contact name' then public.contact_named(v_ct.salutation, v_ct.name)
      when 'client name' then v_cl.name
      else 'https://digital.adspace.me/feedback/?k=' || (r->>'key') end;
    v_s := regexp_replace(v_s, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_b := regexp_replace(v_b, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_btn := regexp_replace(v_btn, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  update public.feedback_requests q set mail_status = 'sending' where q.id = (r->>'id')::uuid;
  return r || jsonb_build_object('subject', left(v_s, 200), 'body', v_b, 'button', v_btn, 'lang', case when v_zh then 'zh' else 'en' end);
end $$;
revoke all on function public.feedback_mail_begin(uuid, text, boolean) from public, anon;
grant execute on function public.feedback_mail_begin(uuid, text, boolean) to authenticated;

create or replace function public.hiring_outcome_mail_claim()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v jsonb; v_stuck uuid[];
begin
  -- A send still marked going out after 10 minutes never answered: it is
  -- marked not confirmed, filed, and told by the morning check
  -- (RETENTION AND JOBS HELD).
  with stuck as (
    update public.hiring_candidates c set outcome_mail = 'unknown', outcome_mail_at = now()
     where c.outcome_mail = 'sending' and coalesce(c.outcome_mail_at, c.updated_at) < now() - interval '10 minutes'
    returning c.id)
  select coalesce(array_agg(x.id), '{}') into v_stuck from stuck x;
  perform public.hiring_log(x, 'candidate.email', 'Decision sent to the candidate, but its delivery could not be verified.')
    from unnest(v_stuck) x;
  with due as (
    select c.id from public.hiring_candidates c
     where c.outcome_mail = 'queued' and c.outcome_mail_due <= now() and c.outcome in ('pool', 'not')
       and c.removed_at is null and c.link_key is not null
     order by c.outcome_mail_due limit 20 for update skip locked),
  took as (
    update public.hiring_candidates c set outcome_mail = 'sending', outcome_mail_due = null, outcome_mail_at = now() from due where c.id = due.id
    returning c.id, c.outcome, c.email, c.name, c.position, c.link_key)
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.outcome, 'to', t.email, 'name', t.name,
      'position', t.position, 'key', t.link_key,
      'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12),
      'system', true)), '[]'::jsonb) into v
    from took t;
  return v;
end $$;
revoke all on function public.hiring_outcome_mail_claim() from public, anon, authenticated;
grant execute on function public.hiring_outcome_mail_claim() to service_role;

create or replace function public.hiring_expire_mail_claim()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v jsonb;
begin
  -- As the decision emails: a send going out for 10 minutes is not confirmed.
  update public.hiring_docs d set expire_mail = 'unknown', expire_mail_at = now()
   where d.expire_mail = 'sending' and coalesce(d.expire_mail_at, d.expired_told_at) < now() - interval '10 minutes';
  /* Only the rows this call takes: a second wake meanwhile claims none of them. */
  with due as (
    select d.id from public.hiring_docs d join public.hiring_candidates c on c.id = d.candidate_id
     where d.expire_mail = 'queued' and c.removed_at is null and c.link_key is not null
     order by d.expired_told_at limit 20 for update of d skip locked),
  took as (
    update public.hiring_docs d set expire_mail = 'sending', expire_mail_at = now() from due where d.id = due.id
    returning d.id, d.kind, d.serial, d.terms, d.sent_at, d.reply_by, d.candidate_id)
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'kind', 'expired', 'doc', t.kind, 'ref', t.serial, 'to', c.email,
      'name', c.name, 'position', t.terms->>'position', 'key', c.link_key,
      'sent', public.register_day((t.sent_at at time zone 'Asia/Kuala_Lumpur')::date), 'reply_by', public.hiring_when(t.reply_by),
      'contact', public.mail_sender('careers')->>'reply_to', 'system', true)), '[]'::jsonb) into v
    from took t join public.hiring_candidates c on c.id = t.candidate_id;
  return v;
end $$;
revoke all on function public.hiring_expire_mail_claim() from public, anon, authenticated;
grant execute on function public.hiring_expire_mail_claim() to service_role;

create or replace function public.hiring_outcome_mail_kick()
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.hiring_candidates c where c.outcome_mail = 'queued' and c.outcome_mail_due <= now())
     or exists (select 1 from public.hiring_docs d where d.expire_mail = 'queued') then
    perform public.hiring_mail_kick();
  end if;
end $$;
revoke all on function public.hiring_outcome_mail_kick() from public, anon, authenticated;

create or replace function public.jobs_watch(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_jobs jsonb := '[]'::jsonb;
  v_runs integer := 0;
  v_self integer := 0;
  v_sweeps integer := 0;
  v_quiet boolean := false;
  v_words text;
  v_day text := to_char(p_now at time zone 'Asia/Kuala_Lumpur', 'YYYY-MM-DD');
  v_told integer := 0;
  v_rules integer := 0;
  v_wa integer := 0;
  v_agent integer := 0;
  v_mail integer := 0;
  v_hire integer := 0;
  v_bukku text;
  v_names text;
  v_task uuid;
  v_since timestamptz := p_now - interval '24 hours';
  v_last timestamptz;
begin
  if to_regclass('cron.job_run_details') is not null then
    /* Back to this check's own last successful run, so a morning whose
       check failed is reported by the next: at least 24 hours, at most
       seven days. */
    select max(d.start_time) into v_last
      from cron.job_run_details d join cron.job j on j.jobid = d.jobid
     where j.jobname = 'jobs-watch' and d.status = 'succeeded' and d.start_time < p_now - interval '1 minute';
    v_since := greatest(p_now - interval '7 days', least(p_now - interval '24 hours', coalesce(v_last, p_now - interval '24 hours')));
    select coalesce(jsonb_agg(jsonb_build_object('job', x.name, 'failed', x.n) order by x.n desc, x.name), '[]'::jsonb),
           coalesce(sum(x.n), 0)::int
      into v_jobs, v_runs
      from (select coalesce(j.jobname, 'job ' || d.jobid) as name, count(*)::int as n
              from cron.job_run_details d
              left join cron.job j on j.jobid = d.jobid
             where d.status = 'failed' and d.start_time >= v_since and d.start_time < p_now
             group by 1) x;
    select coalesce(sum((e ->> 'failed')::int), 0)::int into v_self
      from jsonb_array_elements(v_jobs) e where e ->> 'job' = 'jobs-watch';
    /* The S3 report's job posts to its edge function and succeeds either
       way: a report that never arrived is a failure too. */
    v_quiet := exists (select 1 from cron.job j where j.jobname = 's3-sweep-daily' and j.active)
           and not exists (select 1 from public.s3_sweeps s where s.ran_at >= p_now - interval '26 hours' and s.ran_at < p_now);
  end if;
  select count(*)::int into v_sweeps from public.s3_sweeps s
   where s.mode = 'failed' and s.ran_at >= v_since and s.ran_at < p_now;
  /* The WhatsApp messages the portal sends by itself (a reminder, a
     booking): one Meta refused, or that could not be sent at all. An
     expired token fails every one, and nobody sees it otherwise. */
  select count(*)::int into v_wa
    from (select coalesce(o.failed_at, case when o.state = 'failed' then coalesce(o.sent_at, o.claimed_at, o.created_at) end) as at
            from public.wa_outbox o where o.created_by = 'system') w
   where w.at >= v_since and w.at < p_now;
  /* What colleagues scheduled through the Assistant that could not be done
     (each colleague is told of their own at the run). */
  select count(*)::int into v_agent from public.agent_schedules s
   where s.state = 'failed' and s.ran_at >= v_since and s.ran_at < p_now;

  /* Each repeat rule that could not make its task, named: its client (else
     Internal), the rule or its task, and the task number. */
  select count(*)::int,
         string_agg(w.label, '; ' order by w.at) filter (where w.n <= 5),
         (array_agg(w.task order by w.at) filter (where w.task is not null))[1]
    into v_rules, v_names, v_task
    from (select coalesce(c.name, 'Internal') || ': ' || coalesce(nullif(btrim(x.name), ''), public.ops_title(t), 'Repeating task')
                 || coalesce(' (' || public.ops_serial(t.task_no) || ')', '') as label,
                 x.last_error_at as at, t.id as task,
                 row_number() over (order by x.last_error_at) as n
            from public.ops_recurring_rules x
            left join public.ops_tasks t on t.id = x.source_task_id
            left join public.clients c on c.id = coalesce(case when t.id is not null then case when t.scope = 'client' then t.client_id end
                                                              else x.client_id end, x.client_id)
           where x.active and x.last_error_at >= v_since and x.last_error_at < p_now) w;

  /* The creator emails the portal sends by itself that failed or were not
     confirmed, and the nightly Bukku read: its job only wakes an edge
     function and succeeds either way, so the run writes a beat when it ends
     (`job_beats`), and none in 26 hours, or one that failed, is told
     (audit 2026-11-15). */
  select count(*)::int into v_mail from public.creator_emails e
   where e.status in ('failed', 'unknown', 'bounced') and e.created_at >= v_since and e.created_at < p_now;
  -- And the candidate emails the portal sends by itself (RETENTION AND JOBS HELD).
  select (select count(*) from public.hiring_candidates c
           where c.outcome_mail in ('failed', 'unknown') and c.outcome_mail_at >= v_since and c.outcome_mail_at < p_now)
       + (select count(*) from public.hiring_docs d
           where d.expire_mail in ('failed', 'unknown') and d.expire_mail_at >= v_since and d.expire_mail_at < p_now)
    into v_hire;
  if to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job j where j.jobname = 'bukku-read-nightly' and j.active) then
    select case when b.job is null or b.ran_at < p_now - interval '26 hours' then 'the nightly read from Bukku did not run'
                when not b.ok then 'the nightly read from Bukku failed: ' || coalesce(b.detail, 'no reason given') end
      into v_bukku
      from (select 1) one left join public.job_beats b on b.job = 'bukku-nightly';
    end if;
  end if;
  if v_runs = 0 and v_sweeps = 0 and not v_quiet and v_rules = 0 and v_wa = 0 and v_agent = 0 and v_mail = 0 and v_hire = 0 and v_bukku is null then
    return jsonb_build_object('failed', 0, 'told', 0);
  end if;
  v_words := concat_ws('; ',
    case when v_self > 0 then 'the morning check of scheduled jobs failed ' || v_self ||
                              case when v_self = 1 then ' time' else ' times' end end,
    nullif((select string_agg((e ->> 'job') || ' failed ' || (e ->> 'failed') ||
                              case when (e ->> 'failed')::int = 1 then ' time' else ' times' end, '; ')
              from jsonb_array_elements(v_jobs) e where e ->> 'job' <> 'jobs-watch'), ''),
    case when v_sweeps > 0 then 'the S3 report was filed as failed' end,
    case when v_quiet then 'the S3 report did not arrive' end,
    case when v_wa > 0 then v_wa || case when v_wa = 1 then ' automatic WhatsApp message' else ' automatic WhatsApp messages' end
                            || ' failed to send' end,
    v_bukku,
    case when v_mail > 0 then v_mail || case when v_mail = 1 then ' creator email was not sent or not confirmed'
                                            else ' creator emails were not sent or not confirmed' end end,
    case when v_hire > 0 then v_hire || case when v_hire = 1 then ' candidate email was not sent or not confirmed'
                                            else ' candidate emails were not sent or not confirmed' end end,
    case when v_agent > 0 then v_agent || case when v_agent = 1 then ' scheduled Assistant action' else ' scheduled Assistant actions' end
                               || ' could not be done' end,
    case when v_rules > 0 then v_rules || case when v_rules = 1 then ' repeating task could' else ' repeating tasks could' end
                               || ' not be made: ' || v_names
                               || case when v_rules > 5 then ' and ' || (v_rules - 5) || ' more' else '' end end) || '.';
  insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
  select t.id, v_task, 'jobs.failed',
         case when v_since < p_now - interval '25 hours' then 'Scheduled jobs failed since the last check'
              else 'Scheduled jobs failed in the last 24 hours' end,
         v_words, 'jobs.failed.' || v_day || '.' || t.id
    from public.team_members t
   where t.active
     and (t.is_admin
          or (not exists (select 1 from public.team_members o where o.active and o.is_admin)
              and public.level_rank(t.access ->> 'team') >= 3))
  on conflict (dedupe_key) do nothing;
  get diagnostics v_told = row_count;
  return jsonb_build_object('failed', v_runs + v_sweeps + case when v_quiet then 1 else 0 end + v_rules + v_wa + v_agent + v_mail + v_hire
      + case when v_bukku is null then 0 else 1 end, 'whatsapp', v_wa, 'creator_mail', v_mail, 'candidate_mail', v_hire, 'bukku', v_bukku,
    'assistant', v_agent, 'jobs', v_jobs, 'self', v_self, 'since', v_since, 'sweeps', v_sweeps, 'sweep_missing', v_quiet,
    'repeats', v_rules, 'told', v_told);
end $$;
revoke all on function public.jobs_watch(timestamptz) from public, anon, authenticated;

create or replace function public.ops_tasks_nudge(p_at timestamptz default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_at    timestamptz := coalesce(p_at, now());
  v_local timestamp := coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur';
  v_today date := (coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur')::date;
  v_every integer;
  v_start integer;
  m record;
  v_title text;
  v_body text;
  v_parts text[];
  v_last timestamptz;
  n integer := 0;
begin
  -- Nothing on a public holiday (RETENTION AND JOBS HELD).
  if public.public_holiday_on(v_today) is not null then return 0; end if;
  v_every := coalesce(public.app_setting('task_remind_hours', v_today), 3)::integer;
  v_start := coalesce(public.app_setting('task_start_days', v_today), 2)::integer;
  if v_every <= 0 or extract(isodow from v_today) > 5
     or extract(hour from v_local) < 10 or extract(hour from v_local) >= 18 then
    return 0;
  end if;
  for m in
    with floors as (
      select workflow_id, min(position) as at
        from public.ops_workflow_stages
       where stage_group = 'client_review'
       group by workflow_id
    ),
    pfloors as (
      select workflow_id,
             coalesce(min(position) filter (where stage_group = 'client_review'),
                      min(position) filter (where stage_group = 'internal_review')) as at
        from public.ops_workflow_stages
       group by workflow_id
    ),
    mine as (
      select a.team_member_id as member, k.id, a.assigned_at, k.priority_level, (c.vic_at is not null) as vic,
             public.ops_serial(k.task_no) || ' · ' || public.ops_title(k) as label,
             coalesce(c.name, 'Internal') as client,
             s.stage_group, s.position, f.at as review_at, pf.at as prio_at,
             public.ops_priority_by(coalesce(k.priority_at, k.created_at), k.priority_level) as prio_by,
             (k.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date as due_day,
             (coalesce(k.current_first_draft_due_at, k.current_final_due_at) at time zone 'Asia/Kuala_Lumpur')::date as first_day
        from public.ops_task_assignees a
        join public.ops_tasks k on k.id = a.task_id
        join public.team_members tm on tm.id = a.team_member_id
        join public.ops_workflow_stages s on s.workflow_id = k.workflow_id and s.key = k.stage_key
        left join public.clients c on c.id = k.client_id
        left join floors f on f.workflow_id = k.workflow_id
        left join pfloors pf on pf.workflow_id = k.workflow_id
       where a.responsibility = 'owner' and a.ended_at is null
         and tm.active and not coalesce(tm.system, false)
         and k.completed_at is null and k.cancelled_at is null and k.archived_at is null
         and coalesce(s.stage_group, '') <> 'cancelled'
    ),
    sorted as (
      select x.*,
             (x.prio_by is not null and (x.prio_at is null or x.position < x.prio_at
                                         or x.stage_group in ('kiv', 'blocked'))) as prio_runs,
             (x.review_at is null or x.position < x.review_at) as short_of_review
        from mine x
    ),
    sized as (
      select y.*,
             /* When it became overdue: the earlier of its priority's deadline
                and the end of its due day. */
             least(case when y.prio_runs and y.prio_by < v_at then y.prio_by end,
                   case when y.due_day < v_today and y.short_of_review
                        then (y.due_day + 1)::timestamp at time zone 'Asia/Kuala_Lumpur' end) as late_at,
             case
        when (y.due_day < v_today and y.short_of_review) or (y.prio_runs and y.prio_by < v_at) then 1
        when y.prio_runs and y.priority_level = 1 then 2
        when (y.due_day = v_today and y.short_of_review)
          or (y.prio_runs and (y.prio_by at time zone 'Asia/Kuala_Lumpur')::date = v_today) then 3
        when v_start > 0 and y.stage_group in ('intake', 'ready')
          and ((y.first_day is not null and y.first_day <= v_today + v_start)
            or (y.first_day is null and y.assigned_at <= v_at - make_interval(days => v_start))) then 4
      end as bucket
        from sorted y
    )
    select z.member,
           count(*) as total,
           count(*) filter (where z.bucket = 1) as late,
           count(*) filter (where z.bucket = 2) as urgent,
           count(*) filter (where z.bucket = 3) as today,
           count(*) filter (where z.bucket = 4) as idle,
           count(*) filter (where z.vic) as vic,
           max(z.late_at) filter (where z.vic and z.bucket = 1) as vic_late_at,
           (array_agg(z.id order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_id,
           (array_agg(z.bucket order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_bucket,
           (array_agg(z.client order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_client,
           (array_agg(z.prio_by order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_by,
           (array_agg(z.label order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1:3] as labels
      from sized z
     where z.bucket is not null
     group by z.member
     order by z.member
  loop
    /* Within the window nothing is sent, but a VIC client's task that has
       become overdue since this colleague's last reminder is told at once. */
    select max(o.created_at) into v_last from public.ops_notifications o
     where o.team_member_id = m.member and o.kind = 'tasks.nudge';
    if v_last > v_at - make_interval(mins => v_every * 60 - 10)
       and (m.vic_late_at is null or m.vic_late_at <= v_last) then
      continue;
    end if;
    if m.total = 1 then
      v_title := m.labels[1] || case m.first_bucket when 1 then ' is overdue.' when 2 then ' is Urgent.'
                                                  when 3 then ' is due today.' else ' has not started.' end;
      v_body := m.first_client || case when m.first_bucket = 2 and m.first_by is not null then
        ' · deliver by ' || to_char(m.first_by at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam') || ', ' ||
        public.register_day((m.first_by at time zone 'Asia/Kuala_Lumpur')::date) || '.' else '' end;
    else
      v_parts := array_remove(array[
        case when m.vic > 0 then m.vic || ' for VIC clients' end,
        case when m.late > 0 then m.late || ' overdue' end,
        case when m.urgent > 0 then m.urgent || ' Urgent' end,
        case when m.today > 0 then m.today || ' due today' end,
        case when m.idle > 0 then m.idle || ' not started' end], null);
      v_title := m.total || ' tasks need attention: ' || array_to_string(v_parts, ', ') || '.';
      v_body := array_to_string(m.labels, '; ') ||
                case when m.total > 3 then '; and ' || (m.total - 3) || ' more.' else '.' end;
    end if;
    insert into public.ops_notifications (team_member_id, task_id, kind, title, body, created_at, dedupe_key)
    values (m.member, case when m.total = 1 then m.first_id end, 'tasks.nudge', v_title, v_body, v_at,
            'tasks.nudge.' || m.member || '.' || to_char(v_local, 'YYYY-MM-DD-HH24'))
    on conflict (dedupe_key) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.ops_tasks_nudge(timestamptz) from public, anon, authenticated;

create or replace function public.ops_tasks_remind(p_today date default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Kuala_Lumpur')::date);
  m record;
  v_open boolean;
  v_made boolean;
  n integer := 0;
begin
  if extract(isodow from v_today) > 5 or public.public_holiday_on(v_today) is not null then return 0; end if;
  for m in select t.id from public.team_members t
            where t.active and not coalesce(t.is_admin, false) and coalesce(t.role, '') <> 'admin'
              and public.ops_takes_tasks(t.id)
            order by t.id loop
    v_open := exists (select 1 from public.ops_task_assignees a
                        join public.ops_tasks k on k.id = a.task_id
                       where a.team_member_id = m.id and a.responsibility = 'owner' and a.ended_at is null
                         and k.completed_at is null and k.cancelled_at is null and k.archived_at is null);
    v_made := exists (select 1 from public.ops_tasks k where k.created_by = m.id);
    if v_open and v_made then continue; end if;
    insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
    values (m.id, null, 'tasks.empty',
            case when not v_open then 'No open tasks are assigned to you. Add the work you are on in My Work.'
                 else 'Add the tasks you are working on in My Work.' end,
            null, 'tasks.remind.' || m.id || '.' || v_today)
    on conflict (dedupe_key) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.ops_tasks_remind(date) from public, anon, authenticated;

create or replace function public.team_expire_access()
returns int language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  n int := 0;
begin
  for m in select * from public.team_members t
            where t.active and t.access_until is not null
              and public.team_access_ends(t.access_until, t.access_until_time) <= now()
            order by t.access_until, t.access_until_time nulls last, t.name loop
    if (m.is_admin or m.role = 'admin') and not exists (
         select 1 from public.team_members o
          where o.id <> m.id and o.active and (o.is_admin or o.role = 'admin')
            and (o.access_until is null
                 or public.team_access_ends(o.access_until, o.access_until_time) > now())) then
      continue;
    end if;
    -- Only while it still stands: set active again or given more time
    -- meanwhile, the row is left alone and nothing is handed back.
    update public.team_members set active = false, expired_at = now()
     where id = m.id and active and public.team_access_ends(access_until, access_until_time) <= now();
    if not found then continue; end if;
    perform public.team_expiry_hand_back(m.id);
    insert into public.activity_log (actor, action, subject, detail)
    values ('system', 'team.changed', m.name,
            case when m.access_until_time is null
                 then 'Access expired after ' || public.team_access_word(m.access_until, null)
                 else 'Access expired at ' || public.team_access_word(m.access_until, m.access_until_time) end);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.team_expire_access() from public, anon, authenticated;

create or replace function public.ops_generate_recurring(
  p_period text, p_rules uuid[] default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  r     public.ops_recurring_rules;
  src   public.ops_tasks;
  made  integer := 0;
  skip  integer := 0;
  key   text;
  first_day date;
  last_day date;
  anchor date;
  d     date;
  stepd integer;
  one   jsonb;
  wk    integer;
  held  integer := 0;
  ccl   uuid;
  mon   public.ops_engagements;
  errs  jsonb := '[]'::jsonb;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  first_day := (p_period || '-01')::date;
  last_day := (first_day + interval '1 month' - interval '1 day')::date;

  for r in select * from public.ops_recurring_rules
            where active and (p_rules is null or id = any (p_rules))
              and (source_task_id is null or public.ops_may_see_task(source_task_id)) loop
    if r.source_task_id is not null then
      select * into src from public.ops_tasks where id = r.source_task_id;
    else
      src := null;
    end if;

    /* A client's repeats wait for the client's month: one that exists, is
       open and has its content meeting set or marked not applicable. Until
       then the rule is held and counted, and a later run makes them. */
    ccl := case when src.id is not null then case when src.scope = 'client' then src.client_id end
                else r.client_id end;
    mon := null;
    if ccl is not null then
      select * into mon from public.ops_engagements x where x.client_id = ccl and x.period = p_period;
      if mon.id is null or mon.status in ('completed', 'cancelled')
         or (mon.meeting_at is null and not mon.meeting_na) then
        held := held + 1;
        continue;
      end if;
    end if;

    /* The dates this rule falls on inside the month. */
    if r.frequency = 'monthly' then
      d := first_day + (least(coalesce(r.day_of_month,
              case when src.publish_at is not null then extract(day from src.publish_at)::integer else 1 end),
              extract(day from last_day)::integer) - 1);
      stepd := null;
    else
      stepd := case when r.frequency = 'weekly' then 7 else greatest(1, coalesce(r.interval_days, 7)) end;
      anchor := coalesce(src.publish_at::date, (r.created_at at time zone 'Asia/Kuala_Lumpur')::date, first_day);
      if anchor > first_day then d := anchor;
      else d := anchor + ((((first_day - anchor) + stepd - 1) / stepd) * stepd); end if;
    end if;

    while d is not null and d <= last_day loop
      if d >= first_day
         /* The task a rule copies is its first occurrence: nothing on or
            before its day is made again. */
         and (src.id is null or d > coalesce(src.publish_at::date, (r.created_at at time zone 'Asia/Kuala_Lumpur')::date))
         and (r.ends_on is null or d <= r.ends_on)
         and (r.max_count is null or r.generated_count < r.max_count) then
        key := 'recur:' || r.id::text || ':' || to_char(d, 'YYYY-MM-DD');
        -- One maker of a rule's dates at a time (RETENTION AND JOBS HELD):
        -- two presses at once read the same dates as free.
        perform pg_advisory_xact_lock(hashtext('recur:' || r.id::text));
        /* Made once is made: a copy since deleted stays deleted, and a rule
           set again on the same task makes none of its dates twice. */
        if exists (select 1 from public.ops_tasks where idem_key = key)
           or exists (select 1 from public.ops_recurring_made x
                       where x.on_date = d
                         and (x.rule_id = r.id
                              or (r.source_task_id is not null and x.source_task_id = r.source_task_id))) then
          skip := skip + 1;
        else
          wk := coalesce(r.code_week, least(5, ((extract(day from d)::integer - 1) / 7) + 1));
          /* One rule that cannot make its task never stops the others: the
             attempt is undone, its error kept on the rule and answered, and
             the run goes on to the next rule. */
          one := null;
          begin
            if src.id is not null then
              one := public.ops_duplicate_task(src.id, jsonb_build_object(
                'keep_desc', true, 'copy_dates', false, 'copy_assignees', true,
                'publish_at', d::timestamptz, 'code_period', p_period, 'code_week', wk,
                'engagement_id', mon.id), key);
            else
              one := public.ops_create_task(jsonb_build_object(
                'scope', case when r.client_id is null then 'internal' else 'client' end,
                'client_id', r.client_id, 'template_id', r.template_id,
                'title', r.name || ' — ' || p_period, 'content_desc', r.name,
                'owner_id', r.owner_id, 'publish_at', d::timestamptz,
                'code_period', p_period, 'code_week', wk, 'engagement_id', mon.id), key);
            end if;
            if one ? 'error' then raise exception using message = 'repeat-refused'; end if;
          exception when others then
            if one is null or not (one ? 'error') then one := jsonb_build_object('error', sqlerrm); end if;
          end;
          if one ? 'error' then
            errs := errs || jsonb_build_array(jsonb_build_object('rule', r.id, 'on', d, 'error', one ->> 'error'));
            update public.ops_recurring_rules
               set last_error = left(one ->> 'error', 500), last_error_at = now()
             where id = r.id;
            exit;
          end if;
          made := made + 1;
          insert into public.ops_recurring_made (rule_id, source_task_id, on_date)
          values (r.id, r.source_task_id, d) on conflict do nothing;
          update public.ops_recurring_rules
             set generated_count = generated_count + 1, last_generated_period = p_period, updated_at = now(),
                 last_error = null, last_error_at = null
           where id = r.id;
          r.generated_count := r.generated_count + 1;
        end if;
      end if;
      exit when stepd is null;
      d := d + stepd;
    end loop;
  end loop;
  return jsonb_build_object('created', made, 'skipped', skip, 'held', held, 'period', p_period,
    'failed', jsonb_array_length(errs), 'errors', errs);
end $$;
grant execute on function public.ops_generate_recurring(text, uuid[], text) to authenticated;

create index if not exists ops_notifications_member_kind_idx
  on public.ops_notifications (team_member_id, kind, created_at desc);

-- END OF RETENTION AND JOBS HELD ----------------------------------------------

select public.functions_tidy();
