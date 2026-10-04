-- ===========================================================================
-- REPORT REVIEWER — a report is submitted to a named reviewer, who is told,
-- and only that reviewer or an admin confirms it.
-- 2026-10-04. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `sm_reports.reviewer_id`: who checks the report. Set only by the
--      functions (the guard refuses it from a page). Kept through a send
--      back and a revision, so the next submit offers the same reviewer.
--   2. `ops_notifications.report_id`: a notification may open a report. The
--      push it queues opens `?s=reports&report=`.
--   3. `sm_report_may_review(p_member)`: an active colleague at Reports Full
--      Access, or an admin. `sm_report_reviewers(p_id)` (Reports at Work)
--      lists them for the report, the submitter never among them, with the
--      reviewer last named for the client marked `last`.
--   4. `sm_report_submit(p_id, p_reviewer)`: the reviewer is required
--      (`no-reviewer`), never the submitter (`self-review`), and must be
--      able to review (`bad-reviewer`). The reviewer is told; the record
--      names them.
--   5. `sm_report_assign(p_id, p_reviewer)`: while in review, the
--      submitter, the reviewer or an admin hands the review to another
--      colleague who may review and is not the submitter; they are told;
--      filed `report.reassigned` with from and to.
--   6. `sm_report_confirm(p_id)`: with a reviewer named, only that reviewer
--      or an admin confirms (`not-reviewer`); an admin confirming for
--      somebody else is filed "in place of" them. A report submitted before
--      reviewers keeps the earlier rule (Full Access, never the submitter
--      unless an admin). The submitter is told.
--   7. `sm_report_return(p_id, p_note)`: in review with a reviewer named,
--      the reviewer, an admin or the submitter (taking it back) sends it
--      back; the submitter is told with the note when somebody else does.
--   8. `activity_section` files `report.reassigned` under Reports.
--   Notifications never fail the step that caused them.
--
-- ROLLBACK
--   Run the REPORTS section's sm_report_submit and sm_report_return, the
--   REPORT ADMIN CONFIRM section's sm_report_confirm, the guard and the
--   push trigger from their sections, and the HANDBOOK section's
--   activity_section again, then
--   drop function if exists public.sm_report_submit(uuid, uuid);
--   drop function if exists public.sm_report_assign(uuid, uuid);
--   drop function if exists public.sm_report_reviewers(uuid);
--   drop function if exists public.sm_report_notify(uuid, uuid, text, text, text);
--   drop function if exists public.sm_report_may_review(uuid);
--   alter table public.ops_notifications drop column if exists report_id;
--   alter table public.sm_reports drop column if exists reviewer_id;
-- ===========================================================================

alter table public.sm_reports add column if not exists reviewer_id uuid
  references public.team_members(id) on delete set null;
alter table public.ops_notifications add column if not exists report_id uuid
  references public.sm_reports(id) on delete cascade;

-- The reviewer is a stamp like the submitter: only the functions move it.
create or replace function public.sm_report_guard()
returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('adspace.sm_fn', true), '') = 'on' then
    new.updated_at := now();
    return new;
  end if;
  if new.status is distinct from old.status or new.version_no is distinct from old.version_no
     or new.submitted_by is distinct from old.submitted_by or new.submitted_at is distinct from old.submitted_at
     or new.confirmed_by is distinct from old.confirmed_by or new.confirmed_at is distinct from old.confirmed_at
     or new.return_note is distinct from old.return_note or new.client_id is distinct from old.client_id
     or new.kind is distinct from old.kind or new.reviewer_id is distinct from old.reviewer_id
     or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'sm-status-by-function' using errcode = 'P0001';
  end if;
  if old.status <> 'draft' then
    raise exception 'sm-not-draft' using errcode = 'P0001';
  end if;
  new.updated_at := now();
  return new;
end $$;
revoke all on function public.sm_report_guard() from public, anon, authenticated;

create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.task_id is not null then '/admin/?s=work&open=' || new.task_id::text
         when new.report_id is not null then '/admin/?s=reports&report=' || new.report_id::text
         else '/admin/' end,
    case when new.task_id is not null then 'task-' || new.task_id::text
         when new.report_id is not null then 'report-' || new.report_id::text
         else null end);
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists ops_notifications_push on public.ops_notifications;
create trigger ops_notifications_push after insert on public.ops_notifications
  for each row execute function public.ops_notifications_push();

-- Who may check a report: an active colleague at Reports Full Access, or an admin.
create or replace function public.sm_report_may_review(p_member uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.team_members m
     where m.id = p_member and m.active
       and (coalesce(m.is_admin, false) or m.role = 'admin'
            or public.level_rank(coalesce(m.access ->> 'reports', 'none')) >= public.level_rank('manage')))
$$;
revoke all on function public.sm_report_may_review(uuid) from public, anon, authenticated;

-- A report's notification to one colleague, never to the one acting, and
-- never failing the step that sends it.
create or replace function public.sm_report_notify(p_member uuid, p_report uuid, p_kind text, p_title text, p_body text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_member is null or p_member = (public.ops_me()).id then return; end if;
  insert into public.ops_notifications (team_member_id, task_id, report_id, kind, title, body, dedupe_key)
  values (p_member, null, p_report, p_kind, p_title, p_body,
          p_kind || ':' || p_report::text || ':' || p_member::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'))
  on conflict (dedupe_key) do nothing;
exception when others then
  return;
end $$;
revoke all on function public.sm_report_notify(uuid, uuid, text, text, text) from public, anon, authenticated;

create or replace function public.sm_report_reviewers(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  author uuid;
  last_id uuid;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  author := case when r.status = 'review' then r.submitted_by else me.id end;
  select x.reviewer_id into last_id from public.sm_reports x
   where x.client_id = r.client_id and x.reviewer_id is not null and x.reviewer_id is distinct from author
     and public.sm_report_may_review(x.reviewer_id)
   order by coalesce(x.submitted_at, x.updated_at) desc nulls last limit 1;
  return jsonb_build_object('reviewers', coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'code', m.staff_code,
             'last', m.id = coalesce(r.reviewer_id, last_id))
             order by m.staff_code nulls last, m.name)
      from public.team_members m
     where m.id is distinct from author and public.sm_report_may_review(m.id)), '[]'::jsonb));
end $$;
revoke all on function public.sm_report_reviewers(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_reviewers(uuid) to authenticated;

-- PostgREST cannot choose between overloads, so the one-argument submit goes.
drop function if exists public.sm_report_submit(uuid);
create or replace function public.sm_report_submit(p_id uuid, p_reviewer uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  cname text;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft', 'status', r.status); end if;
  if r.kind = 'ads' then
    if not exists (select 1 from public.sm_report_ads where report_id = p_id) then
      return jsonb_build_object('error', 'no-ads');
    end if;
  else
    if not exists (select 1 from public.sm_report_platforms where report_id = p_id) then
      return jsonb_build_object('error', 'no-platforms');
    end if;
    if not exists (select 1 from public.sm_report_posts where report_id = p_id) then
      return jsonb_build_object('error', 'no-posts');
    end if;
  end if;
  if p_reviewer is null then return jsonb_build_object('error', 'no-reviewer'); end if;
  if p_reviewer = me.id then return jsonb_build_object('error', 'self-review'); end if;
  if not public.sm_report_may_review(p_reviewer) then return jsonb_build_object('error', 'bad-reviewer'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'review', submitted_by = me.id, submitted_at = now(),
    reviewer_id = p_reviewer, return_note = null, confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.submitted',
    'Reviewer: ' || (select name from public.team_members where id = p_reviewer));
  select c.name into cname from public.clients c where c.id = r.client_id;
  perform public.sm_report_notify(p_reviewer, p_id, 'report.review', 'Report to review',
    cname || ' · ' || public.sm_period_word(r.period_start, r.period_end));
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
revoke all on function public.sm_report_submit(uuid, uuid) from public, anon, authenticated;
grant execute on function public.sm_report_submit(uuid, uuid) to authenticated;

create or replace function public.sm_report_assign(p_id uuid, p_reviewer uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  was text;
  cname text;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'review' then return jsonb_build_object('error', 'not-in-review', 'status', r.status); end if;
  if not (me.id = r.submitted_by or me.id is not distinct from r.reviewer_id
          or coalesce(me.is_admin, false) or me.role = 'admin') then
    return jsonb_build_object('error', 'denied');
  end if;
  if p_reviewer is null then return jsonb_build_object('error', 'no-reviewer'); end if;
  if p_reviewer = r.submitted_by then return jsonb_build_object('error', 'self-review'); end if;
  if p_reviewer is not distinct from r.reviewer_id then return jsonb_build_object('error', 'same-reviewer'); end if;
  if not public.sm_report_may_review(p_reviewer) then return jsonb_build_object('error', 'bad-reviewer'); end if;
  select name into was from public.team_members where id = r.reviewer_id;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set reviewer_id = p_reviewer where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.reassigned',
    'Reviewer: ' || coalesce(was, 'not set') || ' → ' || (select name from public.team_members where id = p_reviewer));
  select c.name into cname from public.clients c where c.id = r.client_id;
  perform public.sm_report_notify(p_reviewer, p_id, 'report.review', 'Report to review',
    cname || ' · ' || public.sm_period_word(r.period_start, r.period_end));
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
revoke all on function public.sm_report_assign(uuid, uuid) from public, anon, authenticated;
grant execute on function public.sm_report_assign(uuid, uuid) to authenticated;

create or replace function public.sm_report_confirm(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  v_admin boolean;
  cname text;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'review' then return jsonb_build_object('error', 'not-in-review', 'status', r.status); end if;
  v_admin := coalesce(me.is_admin, false) or me.role = 'admin';
  if r.reviewer_id is not null and r.reviewer_id <> me.id and not v_admin then
    return jsonb_build_object('error', 'not-reviewer');
  end if;
  if r.submitted_by = me.id and not v_admin then
    return jsonb_build_object('error', 'self-confirm');
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'confirmed', confirmed_by = me.id, confirmed_at = now() where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.confirmed',
    case when r.reviewer_id is not null and r.reviewer_id <> me.id
         then 'in place of ' || (select name from public.team_members where id = r.reviewer_id) end);
  select c.name into cname from public.clients c where c.id = r.client_id;
  perform public.sm_report_notify(r.submitted_by, p_id, 'report.confirmed', 'Report confirmed',
    cname || ' · ' || public.sm_period_word(r.period_start, r.period_end));
  return jsonb_build_object('ok', true, 'status', 'confirmed');
end $$;
revoke all on function public.sm_report_confirm(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_confirm(uuid) to authenticated;

create or replace function public.sm_report_return(p_id uuid, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  cname text;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status not in ('review', 'confirmed') then return jsonb_build_object('error', 'not-returnable', 'status', r.status); end if;
  if r.status = 'review' and r.reviewer_id is not null then
    -- The reviewer sends it back, an admin may, and the submitter takes it back.
    if not (me.id = r.reviewer_id or me.id = r.submitted_by
            or ((coalesce(me.is_admin, false) or me.role = 'admin') and public.allowed('reports', 'manage'))) then
      return jsonb_build_object('error', 'not-reviewer');
    end if;
  elsif not public.allowed('reports', 'manage')
     and not (r.status = 'review' and r.submitted_by = me.id) then
    return jsonb_build_object('error', 'denied');
  end if;
  if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('error', 'note-required'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'draft', return_note = btrim(p_note),
    confirmed_by = null, confirmed_at = null where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.returned', btrim(p_note));
  select c.name into cname from public.clients c where c.id = r.client_id;
  perform public.sm_report_notify(r.submitted_by, p_id, 'report.returned', 'Report sent back',
    cname || ' · ' || public.sm_period_word(r.period_start, r.period_end) || ' · ' || btrim(p_note));
  return jsonb_build_object('ok', true, 'status', 'draft');
end $$;
revoke all on function public.sm_report_return(uuid, text) from public, anon, authenticated;
grant execute on function public.sm_report_return(uuid, text) to authenticated;

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
                    'client.service_removed', 'client.stage', 'client.touch',
                    'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.confirmed',
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

-- END OF REPORT REVIEWER -----------------------------------------------------
