-- ===========================================================================
-- AUDIT FIXES OF 11 NOVEMBER — automatic sends, task moves and creator
-- details hold to the rules a person meets (2026-11-12)
-- ===========================================================================
-- WHY (the audit of #987 to #1031, 2026-11-11; the user: "ok" to each).
--
-- WHAT CHANGED
--   * `wa_claim`, `creator_mail_claim`: with Automatic WhatsApp or Automatic
--     emails off, what the portal queued by itself (a reminder, a creator's
--     booking message, a creator email) is failed as Not sent at the claim,
--     not only at the queue, so a message queued before the switch moved, or
--     put back after an outage, never goes.
--   * `sm_reports_task_follow`: reads the task's stage again once a new
--     owner's row has caught it up, so a report started by someone other
--     than the month's manager moves its task once, not twice.
--   * `ops_post_follow`, `ops_script_follow`: a task is moved for a person
--     only where that person could move it: a task never through AQC review
--     goes to AQC review, not Client review; a task not started waits on its
--     month (`ops_month_open_for_work`, the readiness ticks and the meeting,
--     as `ops_transition_task` asks); entering a review stamps Draft in.
--     An approval taken back, or asked again, takes a task Content Review
--     moved to Approved back with it.
--   * `review_revert_confirm`: Undo of Add changes puts back the final date
--     the client's changes pushed, where nothing has moved it since.
--   * `wa_compose_prepare`: Introduce representative refuses `no-contact`
--     for a prospect marked Do not contact.
--   * `creator_mask_email`: a short address shows its first letter alone.
--   * `creator_earlier_job_set`, `creator_earlier_job_remove`: take the job
--     ID's lock before their taken check, as Add does.
--   * `ops_set_link_archived`: restoring a post or script link taken
--     meanwhile refuses `post-taken` / `script-taken`, never the database's
--     words.
--   * `month_invoice_contacts`: a company billing other brands too is left
--     out of a brand's month, so another brand's invoice never marks it.
--   * `clients_stage_log_guard`: shortening a client's stage history (a
--     Timeline stage deleted) asks Clients at Full Access of a signed-in
--     colleague (`stage-log`).
--
-- ORDER: this file (connector), then the pages. Safe to run twice.
--
-- ROLLBACK: each function from its section before this one in schema.sql;
-- drop function public.ops_month_open_for_work(uuid); drop trigger
-- clients_stage_log_guard on public.clients.
-- ===========================================================================

-- AUDIT FIXES OF 11 NOVEMBER ------------------------------------------------

create or replace function public.ops_month_open_for_work(p_engagement uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select p_engagement is null or exists (
    select 1 from public.ops_engagements e
     where e.id = p_engagement
       and (e.meeting_na or (e.meeting_at is not null and e.meeting_at <= now()))
       and not exists (select 1 from public.ops_engagement_checks c
                        where c.engagement_id = e.id
                          and c.state in ('not_started', 'waiting_client', 'in_progress')))
$$;
revoke all on function public.ops_month_open_for_work(uuid) from public, anon, authenticated;

create or replace function public.wa_claim(p_limit integer default 1)
returns setof public.wa_outbox
language plpgsql security definer set search_path = public as $$
begin
  /* A message that has not left in 48 hours is failed, so it can be sent again. */
  perform public.wa_expire();
  /* Automatic WhatsApp off: what the portal queued by itself stays unsent,
     queued before the switch moved or put back after an outage alike. */
  if not public.auto_send_on('whatsapp') then
    update public.wa_outbox o set state = 'failed', error = 'off: Automatic WhatsApp is off.'
     where o.state = 'queued' and o.purpose in ('reminder', 'creator');
  end if;
  /* A send cut off mid-way may have reached Meta: it is never sent again. */
  update public.wa_outbox o
     set state = 'unknown', error = 'unknown: the send was cut off before WhatsApp answered'
   where o.state = 'sending' and o.claimed_at < now() - interval '5 minutes';
  return query
  update public.wa_outbox o set state = 'sending', claimed_at = now(), tries = o.tries + 1
   where o.id in (select x.id from public.wa_outbox x
                   where x.state = 'queued' and x.tries < 3
                   order by x.created_at limit greatest(1, least(coalesce(p_limit, 1), 5))
                   for update skip locked)
  returning o.*;
end $$;
revoke all on function public.wa_claim(integer) from public, anon, authenticated;

create or replace function public.creator_mail_claim(p_n int default 5)
returns setof public.creator_emails
language plpgsql volatile security definer set search_path = public as $$
begin
  /* Automatic emails off: an email queued before the switch moved is kept
     as Not sent, never sent later. */
  if not public.auto_send_on('email') then
    update public.creator_emails x set status = 'failed', error = 'off: Automatic emails are off.'
     where x.status = 'queued';
  end if;
  return query
  update public.creator_emails x set status = 'sending', claimed_at = now()
   where x.id in (select y.id from public.creator_emails y where y.status = 'queued'
                   order by y.created_at limit least(greatest(coalesce(p_n, 5), 1), 10) for update skip locked)
  returning x.*;
end $$;
revoke all on function public.creator_mail_claim(int) from public, anon, authenticated;
grant execute on function public.creator_mail_claim(int) to service_role;

create or replace function public.sm_reports_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e public.ops_engagements;
  t public.ops_tasks;
  v_to text;
  v_was uuid;
  v_note text;
begin
  if new.brand_id is not null or new.on_request then return null; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status
     and new.sent_on is not distinct from old.sent_on then
    return null;
  end if;
  v_to := public.sm_report_task_target(new.status, new.sent_on);
  if v_to is null then return null; end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = new.client_id and x.status <> 'cancelled'
     and new.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then return null; end if;
  select * into t from public.ops_tasks x
   where x.engagement_id = e.id and x.source_type = 'report_' || new.kind
     and x.cancelled_at is null and x.archived_at is null
   order by x.created_at desc limit 1
   for update;
  if t.id is null or t.completed_at is not null then return null; end if;

  if tg_op = 'INSERT' and new.created_by is not null then
    select team_member_id into v_was from public.ops_task_assignees
     where task_id = t.id and responsibility = 'owner' and ended_at is null;
    if v_was is distinct from new.created_by then
      update public.ops_task_assignees set ended_at = now()
       where task_id = t.id and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (t.id, new.created_by, 'owner', new.created_by);
      perform public.ops_log(t.id, 'assignment_changed',
        jsonb_build_object('owner_id', v_was), jsonb_build_object('owner_id', new.created_by),
        jsonb_build_object('report', true, 'report_id', new.id, 'stage_key', t.stage_key));
      /* The new owner's row may already have caught the task up
         (ops_tasks_report_catch_up): read its stage again, so the move is
         filed once. */
      select x.stage_key into t.stage_key from public.ops_tasks x where x.id = t.id;
    end if;
  end if;

  if t.stage_key is distinct from v_to then
    v_note := case
      when tg_op = 'INSERT' then 'Report started'
      when new.status = 'draft' then 'Report back in draft'
      when new.status = 'review' then 'Report submitted for review'
      when new.status = 'confirmed' then 'Report confirmed'
      when new.sent_on is null then 'Report published'
      else 'Report sent to the client' end;
    update public.ops_tasks set stage_key = v_to, version = version + 1, updated_at = now(),
           completed_at = null, blocked_at = null, blocked_category = null
     where id = t.id;
    perform public.ops_log(t.id, 'stage_changed',
      jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', v_to),
      jsonb_build_object('note', v_note, 'report_id', new.id));
  elsif tg_op = 'INSERT' then
    update public.ops_tasks set version = version + 1, updated_at = now() where id = t.id;
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_task_follow() from public, anon, authenticated;

create or replace function public.ops_post_follow(p_post uuid, p_note text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  k      public.ops_task_links;
  t      public.ops_tasks;
  v_to   text;
  v_from public.ops_workflow_stages;
  v_dest public.ops_workflow_stages;
  v_own  uuid;
  v_me   uuid := (public.ops_me()).id;
  v_back boolean := false;
begin
  select * into k from public.ops_task_links x
   where x.post_id = p_post and x.archived_at is null limit 1;
  if k.id is null then return; end if;
  v_to := public.ops_post_target(p_post);
  if v_to is null then return; end if;
  select * into t from public.ops_tasks x where x.id = k.task_id for update;
  if t.id is null or t.completed_at is not null or t.cancelled_at is not null or t.archived_at is not null
     or t.stage_key = v_to then
    return;
  end if;
  /* Approved is the content loop's own while Content Review moved it there:
     an approval taken back, or asked again, takes the task back with it
     (audit 2026-11-11). */
  v_back := t.stage_key = 'approved' and v_to in ('client_review', 'revision_client')
    and coalesce((select (e.detail ->> 'content_review')::boolean from public.ops_task_events e
                    where e.task_id = t.id and e.event_type = 'stage_changed'
                    order by e.created_at desc limit 1), false);
  if t.stage_key not in ('ready', 'in_production', 'internal_review', 'revision_internal',
                         'client_review', 'revision_client') and not v_back then
    return;
  end if;
  /* A move a person could not make is not made for them: the client sees
     the work only after AQC review, so a task that has not been through it
     goes to AQC review instead. */
  if v_to = 'client_review'
     and exists (select 1 from public.ops_workflow_stages s
                  where s.workflow_id = t.workflow_id and s.key = 'internal_review')
     and not exists (select 1 from public.ops_task_events e
                      where e.task_id = t.id and e.event_type = 'stage_changed'
                        and e.to_value ->> 'stage_key' = 'internal_review') then
    v_to := 'internal_review';
    if t.stage_key = v_to then return; end if;
  end if;
  /* Work not started waits on its month: the readiness ticks answered and
     the content meeting held or not needed, as ops_transition_task asks. */
  if t.stage_key = 'ready' and not public.ops_month_open_for_work(t.engagement_id) then return; end if;
  v_from := public.ops_stage(t.workflow_id, t.stage_key);
  v_dest := public.ops_stage(t.workflow_id, v_to);
  if v_from.key is null or v_dest.key is null or coalesce(v_dest.retired, false) then return; end if;
  if not (v_back or v_dest.position > v_from.position
          or (t.stage_key = 'revision_internal' and v_to = 'internal_review')
          or (t.stage_key = 'revision_client' and v_to = 'client_review')) then
    return;
  end if;
  update public.ops_tasks set stage_key = v_to, version = version + 1, updated_at = now(),
         blocked_at = null, blocked_category = null,
         first_draft_submitted_at = case when first_draft_submitted_at is null and coalesce(v_dest.is_review, false)
                                         then now() else first_draft_submitted_at end
   where id = t.id;
  insert into public.ops_task_events (task_id, event_type, actor_id, actor_email, from_value, to_value, detail)
  values (t.id, 'stage_changed', v_me, null,
          jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', v_to),
          jsonb_build_object('note', p_note, 'post_id', p_post, 'content_review', true));
  select a.team_member_id into v_own from public.ops_task_assignees a
   where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null limit 1;
  if v_own is not null and v_own is distinct from v_me then
    perform public.ops_notify(v_own, t.id, 'stage_changed',
      public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
      'Moved to ' || v_dest.label || ': ' || p_note || '.',
      'stage_changed:' || t.id::text || ':' || v_own::text || ':' || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI'));
  end if;
exception when others then
  return;
end $$;
revoke all on function public.ops_post_follow(uuid, text) from public, anon, authenticated;

create or replace function public.ops_script_follow(p_script uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  k      public.ops_task_links;
  t      public.ops_tasks;
  s      public.video_scripts;
  v      public.ops_video_details;
  v_shot boolean;
  v_at   timestamptz;
  v_own  uuid;
  v_me   uuid := (public.ops_me()).id;
  v_dest public.ops_workflow_stages;
begin
  select * into k from public.ops_task_links x
   where x.script_id = p_script and x.archived_at is null limit 1;
  if k.id is null then return; end if;
  select * into s from public.video_scripts x where x.id = p_script;
  select * into t from public.ops_tasks x where x.id = k.task_id for update;
  if s.id is null or t.id is null or t.completed_at is not null or t.cancelled_at is not null
     or t.archived_at is not null then
    return;
  end if;
  select count(*) > 0 and count(*) filter (where c.shot_at is null) = 0 into v_shot
    from public.video_script_scenes c where c.script_id = s.id;
  v_at := case when s.shoot_on is null then null
               else (s.shoot_on + coalesce(s.shoot_time, time '09:00')) at time zone 'Asia/Kuala_Lumpur' end;
  insert into public.ops_video_details (task_id) values (t.id) on conflict (task_id) do nothing;
  select * into v from public.ops_video_details x where x.task_id = t.id for update;
  if v.script_ready is distinct from (s.status = 'shared') or v.footage_ready is distinct from v_shot
     or v.shoot_at is distinct from v_at or v.shoot_required is distinct from (s.shoot_on is not null) then
    update public.ops_video_details set script_ready = (s.status = 'shared'), footage_ready = v_shot,
           shoot_at = v_at, shoot_required = (s.shoot_on is not null)
     where task_id = t.id;
    insert into public.ops_task_events (task_id, event_type, actor_id, actor_email, from_value, to_value, detail)
    values (t.id, 'video_changed', v_me, null,
            jsonb_build_object('script_ready', v.script_ready, 'footage_ready', v.footage_ready, 'shoot_at', v.shoot_at),
            jsonb_build_object('script_ready', s.status = 'shared', 'footage_ready', v_shot, 'shoot_at', v_at),
            jsonb_build_object('note', 'Updated from its script in Video Scripts', 'script_id', s.id));
    update public.ops_tasks set version = version + 1, updated_at = now() where id = t.id;
  end if;
  -- The footage in: a task not started moves into its work.
  if v_shot and v.footage_ready is distinct from true and t.stage_key = 'ready'
     and public.ops_month_open_for_work(t.engagement_id) then
    v_dest := public.ops_stage(t.workflow_id, 'in_production');
    if v_dest.key is not null and not coalesce(v_dest.retired, false) then
      update public.ops_tasks set stage_key = 'in_production', version = version + 1, updated_at = now()
       where id = t.id;
      insert into public.ops_task_events (task_id, event_type, actor_id, actor_email, from_value, to_value, detail)
      values (t.id, 'stage_changed', v_me, null,
              jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', 'in_production'),
              jsonb_build_object('note', 'Every scene shot in Video Scripts', 'script_id', s.id));
      select a.team_member_id into v_own from public.ops_task_assignees a
       where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null limit 1;
      if v_own is not null and v_own is distinct from v_me then
        perform public.ops_notify(v_own, t.id, 'stage_changed',
          public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
          'Moved to ' || v_dest.label || ': every scene shot in Video Scripts.',
          'stage_changed:' || t.id::text || ':' || v_own::text || ':' ||
            to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI'));
      end if;
    end if;
  end if;
exception when others then
  return;
end $$;
revoke all on function public.ops_script_follow(uuid) from public, anon, authenticated;

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
  b    public.batches;
  q    public.quotations;
  d    public.client_documents;
  t    public.team_members;
  v_n  text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose not in ('message', 'report', 'feedback', 'creator', 'approval', 'quotation', 'offer', 'representative')
     or p_to_kind not in ('contact', 'creator')
     or (p_purpose in ('report', 'feedback', 'approval', 'quotation', 'offer', 'representative') and p_to_kind <> 'contact')
     or (p_purpose = 'creator' and p_to_kind <> 'creator') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if not public.wa_may_send(p_purpose, p_to_kind) then return jsonb_build_object('error', 'denied'); end if;
  if p_to_kind = 'contact' then
    select * into k from public.client_contacts x where x.id = p_to and x.archived_at is null;
    if k.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = k.client_id;
    if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    /* A feedback request asks a client about work done for them: a lead,
       contacted or proposed, has none (MENU-1, 2026-10-22). */
    if p_purpose = 'feedback' and coalesce(c.stage, 'lead') in ('lead', 'contacted', 'proposal') then
      return jsonb_build_object('error', 'not-client');
    end if;
    /* A representative is named to a lead alone, and is its Sales by
       colleague: active, their namecard on, its short link the button's. */
    if p_purpose = 'representative' then
      if coalesce(c.stage, 'lead') not in ('lead', 'contacted', 'proposal') then
        return jsonb_build_object('error', 'not-lead');
      end if;
      select * into t from public.team_members x where x.id = c.sales_by and x.active and x.removed_at is null;
      if t.id is null then return jsonb_build_object('error', 'no-sales-by'); end if;
      /* A prospect who asked not to be contacted is not introduced either. */
      if exists (select 1 from public.quotations q where q.client_id = c.id and q.source = 'website'
                    and q.no_contact_at is not null) then
        return jsonb_build_object('error', 'no-contact');
      end if;
      if not coalesce(t.card_on, false) or nullif(btrim(coalesce(t.card_slug, '')), '') is null then
        return jsonb_build_object('error', 'no-card', 'rep', t.name);
      end if;
    end if;
    if p_purpose = 'report' then
      select * into r from public.sm_reports x where x.id = p_ref;
      if r.id is null or r.client_id <> c.id then return jsonb_build_object('error', 'not-found'); end if;
      if r.status <> 'published' then return jsonb_build_object('error', 'not-published'); end if;
    end if;
    /* A quotation or a Letter of Offer is the contact's own client's: a
       quotation not removed, a letter not voided. */
    if p_purpose = 'quotation' then
      select * into q from public.quotations x where x.id = p_ref;
      if q.id is null or q.client_id <> c.id or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
      if q.status = 'not_proceeding' then return jsonb_build_object('error', 'void'); end if;
    end if;
    if p_purpose = 'offer' then
      select * into d from public.client_documents x where x.id = p_ref;
      if d.id is null or d.client_id <> c.id or d.kind not in ('offer', 'intent', 'cover') then
        return jsonb_build_object('error', 'not-found');
      end if;
      if (d.voided_at is not null or d.superseded_by is not null) then return jsonb_build_object('error', 'void'); end if;
    end if;
    /* An approval reminder names what waits on the client: a published
       content set of theirs, or a creator's draft at Reviewing on a
       campaign of theirs, each read at its own section. */
    if p_purpose = 'approval' then
      select * into b from public.batches x where x.id = p_ref;
      if b.id is not null then
        if b.client_id <> c.id or not public.allowed('review.sets', 'view') then return jsonb_build_object('error', 'not-found'); end if;
        if not coalesce(b.published, false) then return jsonb_build_object('error', 'not-waiting'); end if;
      else
        select * into o from public.campaign_options x where x.id = p_ref;
        if o.id is not null then select * into cp from public.campaigns x where x.id = o.campaign_id; end if;
        if o.id is null or cp.id is null or cp.client_id is distinct from c.id or not public.allowed('campaigns.campaigns', 'view') then
          return jsonb_build_object('error', 'not-found');
        end if;
        if o.state <> 'reviewing' then return jsonb_build_object('error', 'not-waiting'); end if;
      end if;
    end if;
    v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
    if v_n is null then
      return jsonb_build_object('error', case when k.whatsapp ~ '^@' then 'username' else 'no-number' end);
    end if;
    return jsonb_strip_nulls(jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'greeting', public.contact_greeting(k.salutation, k.name),
      'client_id', c.id, 'client', case when r.id is not null then coalesce(nullif(r.brand_name, ''), c.name) else c.name end,
      'subject', c.name, 'ref_kind', case when b.id is not null then 'set' when o.id is not null then 'option'
                       when q.id is not null then 'quotation' when d.id is not null then 'offer' end,
      -- an approval reminder's link button: the page that waits, past the
      -- site's root (the client's review page, the campaign's selection page)
      'link', case when b.id is not null then 'review/?k=' || c.access_token
                   when o.id is not null then 'creators/?k=' || cp.access_token end,
      -- the representative: their name, and their namecard's short link for
      -- the link button
      'rep', t.name, 'code', t.card_slug));
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
  return jsonb_build_object('ok', true, 'number', v_n, 'name', cr.name, 'greeting', public.contact_greeting(null, cr.name),
    'client_id', cp.client_id,
    'campaign', case when cp.id is not null then coalesce(nullif(btrim(cp.title), ''), 'Your campaign') end,
    'code', cr.access_code, 'subject', coalesce(nullif(btrim(cp.title), ''), cr.name));
end $$;
revoke all on function public.wa_compose_prepare(text, uuid, text, uuid) from public, anon;
grant execute on function public.wa_compose_prepare(text, uuid, text, uuid) to authenticated;

create or replace function public.creator_mask_email(p text)
returns text language sql immutable set search_path = public as $$
  select case when coalesce(p, '') !~ '@' then public.creator_mask_words(p) else
    (select case when char_length(l) <= 4 then left(l, 1) || repeat('*', greatest(char_length(l) - 1, 3))
                 else left(l, 2) || repeat('*', greatest(char_length(l) - 3, 3)) || right(l, 1) end
            || '@' || split_part(p, '@', 2)
       from (select split_part(p, '@', 1) as l) x) end
$$;
revoke all on function public.creator_mask_email(text) from public, anon, authenticated;

create or replace function public.creator_earlier_job_set(p_option uuid, p_ref text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  o  public.campaign_options;
  c  public.creators;
  v  text := nullif(upper(regexp_replace(btrim(coalesce(p_ref, '')), '\s+', '', 'g')), '');
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v is not null and v !~ '^[A-Z0-9][A-Z0-9/._-]{1,39}$' then return jsonb_build_object('error', 'bad-ref'); end if;
  if v is not null then perform pg_advisory_xact_lock(hashtextextended('creator_earlier_job:' || v, 0)); end if;
  if v is not null and (exists (select 1 from public.campaign_options x where x.earlier_job = v and x.id <> o.id)
                        or exists (select 1 from public.creator_earlier_jobs x where x.ref = v and x.removed_at is null)) then
    return jsonb_build_object('error', 'taken');
  end if;
  if v is not distinct from o.earlier_job then return jsonb_build_object('ok', true); end if;
  update public.campaign_options x set earlier_job = v where x.id = o.id;
  select * into c from public.creators x where x.id = o.creator_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', c.name,
          coalesce(public.creator_job_ref(o.id) || ' · ', '') || 'Earlier job ID: ' || coalesce(o.earlier_job, 'not set') || ' → ' || coalesce(v, 'not set'));
  update public.creator_bills b set option_id = public.creator_bill_option(b.creator_id, b.ref, b.number)
   where b.creator_id = o.creator_id;
  return jsonb_build_object('ok', true, 'earlier_job', v);
end $$;
revoke all on function public.creator_earlier_job_set(uuid, text) from public, anon;
grant execute on function public.creator_earlier_job_set(uuid, text) to authenticated;

create or replace function public.creator_earlier_job_remove(p_id uuid, p_restore boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  j  public.creator_earlier_jobs;
  c  public.creators;
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into j from public.creator_earlier_jobs x where x.id = p_id for update;
  if j.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.creators x where x.id = j.creator_id;
  if coalesce(p_restore, false) then
    if j.removed_at is null then return jsonb_build_object('ok', true); end if;
    perform pg_advisory_xact_lock(hashtextextended('creator_earlier_job:' || j.ref, 0));
    if exists (select 1 from public.campaign_options x where x.earlier_job = j.ref)
       or exists (select 1 from public.creator_earlier_jobs x where x.ref = j.ref and x.removed_at is null) then
      return jsonb_build_object('error', 'taken');
    end if;
    update public.creator_earlier_jobs x set removed_at = null, removed_by = null where x.id = j.id;
  else
    if j.removed_at is not null then return jsonb_build_object('ok', true); end if;
    update public.creator_earlier_jobs x set removed_at = now(), removed_by = me.name where x.id = j.id;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', c.name, coalesce(c.creator_code || ' · ', '') ||
          case when coalesce(p_restore, false) then 'Earlier job restored: ' else 'Earlier job removed: ' end || j.ref);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_earlier_job_remove(uuid, boolean) from public, anon;
grant execute on function public.creator_earlier_job_remove(uuid, boolean) to authenticated;

create or replace function public.ops_set_link_archived(p_link uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.ops_task_links;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into l from public.ops_task_links where id = p_link for update;
  if l.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.ops_may_see_task(l.task_id) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if (l.archived_at is not null) = p_on then
    return jsonb_build_object('link_id', l.id, 'archived', p_on,
                              'task', public.ops_task_json(l.task_id));
  end if;

  /* A post or a script linked to another task meanwhile is not taken
     back: one task a post, one post a task (and so for a script). */
  if not p_on and l.post_id is not null and exists (
       select 1 from public.ops_task_links x where x.archived_at is null and x.id <> l.id
          and (x.post_id = l.post_id or (x.task_id = l.task_id and x.post_id is not null))) then
    return jsonb_build_object('error', 'post-taken');
  end if;
  if not p_on and l.script_id is not null and exists (
       select 1 from public.ops_task_links x where x.archived_at is null and x.id <> l.id
          and (x.script_id = l.script_id or (x.task_id = l.task_id and x.script_id is not null))) then
    return jsonb_build_object('error', 'script-taken');
  end if;
  update public.ops_task_links
     set archived_at = case when p_on then now() else null end
   where id = p_link;
  update public.ops_tasks set version = version + 1, updated_at = now() where id = l.task_id;
  if l.ref_type is not null then
    perform public.ops_ref_file(l, case when p_on then 'unlinked' else 'relinked' end);
  else
    perform public.ops_log(l.task_id,
      case when p_on then 'file_removed' else 'file_restored' end, null,
      jsonb_build_object('link_id', l.id, 'kind', l.kind, 'label', l.label), '{}'::jsonb);
  end if;
  return jsonb_build_object('link_id', l.id, 'archived', p_on,
                            'task', public.ops_task_json(l.task_id));
end $$;
grant execute on function public.ops_set_link_archived(uuid, boolean) to authenticated;

create or replace function public.month_invoice_contacts(p_client uuid)
returns bigint[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct x.contact_id), '{}'::bigint[]) from (
    select b.contact_id from public.bukku_links b where b.kind = 'client' and b.record_id = p_client
    union all
    select b.contact_id from public.bukku_links b join public.suppliers s on s.id = b.record_id
     where b.kind = 'supplier' and s.client_id = p_client
    union all
    select b.contact_id from public.bukku_links b join public.client_entities ce on ce.entity_id = b.record_id
     where b.kind = 'entity' and ce.client_id = p_client
       -- a company billing other brands too is left out: its invoice may be
       -- another brand's month (audit 2026-11-11)
       and not exists (select 1 from public.client_entities o
                        where o.entity_id = ce.entity_id and o.client_id <> p_client)
  ) x where x.contact_id is not null
$$;
revoke all on function public.month_invoice_contacts(uuid) from public, anon, authenticated;

create or replace function public.review_revert_confirm(p_post uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me       public.team_members;
  v_post   public.posts%rowtype;
  v_rv     public.reviews%rowtype;
  v_title  text;
  v_client text;
  v_task   uuid;
  v_was    text;
  v_now    text;
begin
  if not public.allowed('review.sets', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into v_post from public.posts where id = p_post for update;
  if v_post.id is null then return jsonb_build_object('error', 'no-post'); end if;
  select r.* into v_rv from public.reviews r
   where r.post_id = v_post.id and r.round = v_post.round and r.undone_at is null
     and (v_post.review_reset_at is null or r.created_at > v_post.review_reset_at)
   order by r.created_at desc limit 1;
  if v_rv.id is null or v_rv.source <> 'team' then
    return jsonb_build_object('error', 'not-confirmed');
  end if;
  update public.reviews set undone_at = now(), undone_by = me.id where id = v_rv.id;
  /* Changes taken back: the final date they pushed goes back too, where
     nothing has moved it since (audit 2026-11-11). */
  if v_rv.decision = 'changes' then
    for v_task, v_was, v_now in
      select t.id, e.from_value ->> 'value', e.to_value ->> 'value' from public.ops_task_links l
        join public.ops_tasks t on t.id = l.task_id
        cross join lateral (
          select x.* from public.ops_task_events x
           where x.task_id = t.id and x.event_type = 'due_changed'
             and x.to_value ->> 'kind' = 'final'
           order by x.created_at desc limit 1) e
       where l.post_id = v_post.id and l.archived_at is null
         and coalesce((e.detail ->> 'auto')::boolean, false) and e.created_at >= v_rv.created_at
         and t.current_final_due_at is not distinct from (e.to_value ->> 'value')::timestamptz
    loop
      update public.ops_tasks set current_final_due_at = v_was::timestamptz,
             version = version + 1, updated_at = now()
       where id = v_task;
      perform public.ops_log(v_task, 'due_changed',
        jsonb_build_object('kind', 'final', 'value', v_now),
        jsonb_build_object('kind', 'final', 'value', v_was),
        jsonb_build_object('reason', 'client_request', 'note', 'The client''s changes were taken back.', 'auto', true));
    end loop;
  end if;

  select b.title, c.name into v_title, v_client
    from public.batches b join public.clients c on c.id = b.client_id
   where b.id = v_post.batch_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(nullif(auth.jwt() ->> 'email', ''), me.name), 'review.unconfirmed', v_client,
          coalesce(v_title, '') || ' · ' || coalesce(nullif(v_post.platform, ''), 'post') ||
          case when v_rv.decision = 'approved' then ' · internal confirmation reverted'
               else ' · changes received on WhatsApp reverted' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.review_revert_confirm(uuid) from public, anon;

create or replace function public.clients_stage_log_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and jsonb_array_length(coalesce(new.stage_log, '[]'::jsonb)) < jsonb_array_length(coalesce(old.stage_log, '[]'::jsonb))
     and not public.allowed('clients', 'manage') then
    raise exception 'stage-log' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.clients_stage_log_guard() from public, anon, authenticated;
create or replace trigger clients_stage_log_guard before update of stage_log on public.clients
  for each row execute function public.clients_stage_log_guard();

-- END OF AUDIT FIXES OF 11 NOVEMBER -----------------------------------------

select public.functions_tidy();
