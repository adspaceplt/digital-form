-- ===========================================================================
-- RELEASED FILES — the client sees the round the team released and nothing
-- newer, a file changed after the quality check is checked again, and a file
-- the client approved is hidden rather than removed (audit S5, S6,
-- 2026-10-10). 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored
-- byte for byte in supabase/schema.sql under the same banner;
-- tests/releasedfiles.js compares the two. It replaces a policy, so it runs
-- in the SQL Editor.
--
-- WHAT CHANGED
--   1. `campaign_options.released_round`, stamped by `campaign_qc_pass` at
--      release with the newest round handed in; `get_campaign` sends that
--      round's files alone, never a hidden one. Rows released before are
--      stamped once from their files.
--   2. `option_qc.voided_at`: a file added or removed while the booking is
--      Submitted voids that round's checks (trigger
--      `campaign_deliverables_qc_void`); `option_qc_count` reads only checks
--      standing, and the same colleague's check is taken again.
--   3. `campaign_deliverables.hidden_at` / `hidden_by`: from the client's
--      approval on (Scheduled, Posted, Completed) a file is hidden, never
--      removed: `campaign_file_hide(p_file, p_hide)`, Creator Campaigns at
--      Work, client scope, filed `campaign.file_hidden` /
--      `campaign.file_shown`. Trigger `campaign_deliverables_guard` refuses a
--      page removing such a file (`approved-hide`). Once hidden it is
--      deleted only by `campaign_file_delete(p_file)` at the granted part
--      `campaigns.files_delete`, filed `campaign.file_deleted`; the record's
--      section map files the three tags under Creator Campaigns.
--   4. The one `for all` policy is four: read at Creator Campaigns:
--      Campaigns View, add and change at Work, and a permanent delete at the
--      granted part `campaigns.files_delete` (an admin's alone until given).
--
-- ROLLBACK
--   Pages first (they read the new columns where present), then put back
--   `campaign_deliverables_team` (for all, is_team()), re-run the earlier
--   get_campaign, campaign_qc_pass and option_qc_count, and remove the
--   triggers, the function and the columns, in the SQL Editor.
-- ===========================================================================

alter table public.campaign_options add column if not exists released_round integer;
alter table public.option_qc add column if not exists voided_at timestamptz;
alter table public.campaign_deliverables add column if not exists hidden_at timestamptz;
alter table public.campaign_deliverables add column if not exists hidden_by text;

-- Rows released before: the round on show today.
update public.campaign_options o
   set released_round = (select max(d.round) from public.campaign_deliverables d
                          where d.option_id = o.id and d.removed_at is null)
 where o.released_round is null
   and o.state in ('reviewing', 'scheduled', 'posted', 'completed');
update public.campaign_options o
   set released_round = (select max(d.round) from public.campaign_deliverables d
                          where d.option_id = o.id and d.removed_at is null
                            and d.round < coalesce(o.revision_round, 0))
 where o.released_round is null and o.state = 'changes'
   and coalesce(o.changes_by, 'client') = 'client';

create or replace function public.option_qc_count(p_option uuid)
returns integer
language sql security definer stable set search_path = public as $$
  select count(distinct q.team_member_id)::int
    from public.option_qc q
    join public.campaign_options o on o.id = q.option_id
   where q.option_id = p_option
     and q.round = coalesce(o.revision_round, 0)
     and q.voided_at is null
$$;
grant execute on function public.option_qc_count(uuid) to authenticated;

create or replace function public.campaign_qc_pass(
  p_option uuid, p_want_second boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members;
  o    public.campaign_options;
  n    integer;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;

  select * into o from public.campaign_options where id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'no-booking'); end if;
  if o.state <> 'submitted' then
    return jsonb_build_object('error', 'not-submitted');
  end if;

  /* A check voided by a file added since (audit S5) is taken again. */
  insert into public.option_qc (option_id, team_member_id, round)
  values (p_option, me.id, coalesce(o.revision_round, 0))
  on conflict (option_id, team_member_id, round)
  do update set voided_at = null, checked_at = now()
   where public.option_qc.voided_at is not null;

  if p_want_second and not coalesce(o.qc_second_wanted, false) then
    update public.campaign_options set qc_second_wanted = true where id = p_option;
    o.qc_second_wanted := true;
  end if;

  n := public.option_qc_count(p_option);
  if coalesce(o.qc_second_wanted, false) and n < 2 then
    return jsonb_build_object('state', 'waiting', 'checks', n, 'second', true);
  end if;

  update public.campaign_options
     set state = 'reviewing', changes_by = null,
         released_round = coalesce((select max(d.round) from public.campaign_deliverables d
                                     where d.option_id = p_option and d.removed_at is null
                                       and d.hidden_at is null), released_round)
   where id = p_option;
  return jsonb_build_object('state', 'reviewing', 'checks', n,
                            'second', coalesce(o.qc_second_wanted, false));
end $$;
grant execute on function public.campaign_qc_pass(uuid, boolean) to authenticated;

create or replace function public.campaign_deliverables_qc_void() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.removed_at is not distinct from old.removed_at then
    return new;
  end if;
  update public.option_qc q set voided_at = now()
    from public.campaign_options o
   where o.id = new.option_id and o.state = 'submitted'
     and q.option_id = o.id and q.round = coalesce(o.revision_round, 0)
     and q.voided_at is null;
  return new;
end $$;
revoke all on function public.campaign_deliverables_qc_void() from public, anon, authenticated;
create or replace trigger campaign_deliverables_qc_void
  after insert or update on public.campaign_deliverables
  for each row execute function public.campaign_deliverables_qc_void();

/* A file the client approved is the client's record of what they approved:
   a page hides it, and never removes it. Run as the caller, so
   `current_user` tells a page's write from a function's. */
create or replace function public.campaign_deliverables_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon')
     and new.removed_at is not null and old.removed_at is null
     and exists (select 1 from public.campaign_options o
                  where o.id = new.option_id and o.state in ('scheduled', 'posted', 'completed')) then
    raise exception 'approved-hide' using hint = 'An approved file is hidden, not removed.';
  end if;
  if current_user in ('authenticated', 'anon')
     and (new.hidden_at, new.hidden_by) is distinct from (old.hidden_at, old.hidden_by) then
    raise exception 'hide-function' using hint = 'Hide and Restore go through campaign_file_hide.';
  end if;
  return new;
end $$;
revoke all on function public.campaign_deliverables_guard() from public, anon, authenticated;
create or replace trigger campaign_deliverables_guard
  before update on public.campaign_deliverables
  for each row execute function public.campaign_deliverables_guard();

create or replace function public.campaign_file_hide(p_file uuid, p_hide boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members;
  d    public.campaign_deliverables%rowtype;
  o    public.campaign_options%rowtype;
  c    public.campaigns%rowtype;
  cr   text;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.campaign_deliverables where id = p_file for update;
  if d.id is null or d.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from public.campaign_options where id = d.option_id;
  select * into c from public.campaigns where id = o.campaign_id;
  if not public.client_scope_ok('campaign', c.id, 'work') then
    return jsonb_build_object('error', 'client-scope');
  end if;
  if o.state not in ('scheduled', 'posted', 'completed') then
    return jsonb_build_object('error', 'not-approved');
  end if;
  if coalesce(p_hide, true) = (d.hidden_at is not null) then
    return jsonb_build_object('ok', true, 'again', true);
  end if;
  update public.campaign_deliverables
     set hidden_at = case when coalesce(p_hide, true) then now() end,
         hidden_by = case when coalesce(p_hide, true) then me.name end
   where id = d.id;
  select cx.name into cr from public.creators cx where cx.id = o.creator_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, case when coalesce(p_hide, true) then 'campaign.file_hidden' else 'campaign.file_shown' end,
          c.title, coalesce(cr, 'Creator') || ' · ' || coalesce(d.name, 'file'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.campaign_file_hide(uuid, boolean) from public, anon;
grant execute on function public.campaign_file_hide(uuid, boolean) to authenticated;

drop policy if exists campaign_deliverables_team on public.campaign_deliverables;
drop policy if exists campaign_deliverables_read on public.campaign_deliverables;
drop policy if exists campaign_deliverables_write on public.campaign_deliverables;
drop policy if exists campaign_deliverables_edit on public.campaign_deliverables;
drop policy if exists campaign_deliverables_del on public.campaign_deliverables;
create policy campaign_deliverables_read on public.campaign_deliverables
  for select to authenticated using (public.allowed('campaigns.campaigns', 'view'));
create policy campaign_deliverables_write on public.campaign_deliverables
  for insert to authenticated with check (public.allowed('campaigns.campaigns', 'work'));
create policy campaign_deliverables_edit on public.campaign_deliverables
  for update to authenticated using (public.allowed('campaigns.campaigns', 'work'))
  with check (public.allowed('campaigns.campaigns', 'work'));
create policy campaign_deliverables_del on public.campaign_deliverables
  for delete to authenticated using (public.ops_granted('campaigns.files_delete', 'work'));

/* A file the client approved leaves for good only by a colleague holding
   the granted part `campaigns.files_delete` (an admin's until given), and
   only once hidden: the stored file itself is kept, as every upload is. */
create or replace function public.campaign_file_delete(p_file uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members;
  d    public.campaign_deliverables%rowtype;
  o    public.campaign_options%rowtype;
  c    public.campaigns%rowtype;
  cr   text;
begin
  if not public.ops_granted('campaigns.files_delete', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.campaign_deliverables where id = p_file for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.hidden_at is null then return jsonb_build_object('error', 'not-hidden'); end if;
  select * into o from public.campaign_options where id = d.option_id;
  select * into c from public.campaigns where id = o.campaign_id;
  if not public.client_scope_ok('campaign', c.id, 'manage') then
    return jsonb_build_object('error', 'client-scope');
  end if;
  select cx.name into cr from public.creators cx where cx.id = o.creator_id;
  delete from public.campaign_deliverables where id = d.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'campaign.file_deleted', c.title,
          coalesce(cr, 'Creator') || ' · ' || coalesce(d.name, 'file'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.campaign_file_delete(uuid) from public, anon;
grant execute on function public.campaign_file_delete(uuid) to authenticated;

create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.file_deleted', 'campaign.file_hidden',
                    'campaign.file_shown', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.whatsapp', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('wa.sent', 'wa.template') then 'whatsapp'
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
                    'set.created', 'set.deleted', 'set.month', 'set.published', 'set.renamed',
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

create or replace function public.get_campaign(p_token text, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
  cl clients%rowtype;
  billable boolean;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into cl from clients where id = c.client_id;

  -- An invoice belongs to an accepted booking. Until the client has chosen and
  -- the team has confirmed at least one creator, the number and the PDF stay
  -- off the client's page, and reverting the last confirmation takes them off
  -- it again. The gate is here rather than on the page so nothing the client
  -- can open carries what it should not show.
  select exists (
    select 1 from campaign_options o
     where o.campaign_id = c.id
       and o.state in ('confirmed', 'pending_visit', 'pending_draft', 'submitted',
                       'reviewing', 'changes', 'scheduled', 'posted', 'completed')
  ) into billable;

  if c.passcode is not null and c.passcode <> '' then
    if p_passcode is null or p_passcode <> c.passcode then
      return jsonb_build_object('error', 'passcode', 'client', cl.name);
    end if;
  end if;

  return jsonb_build_object(
    'campaign', jsonb_build_object(
      'title', c.title, 'title_zh', c.title_zh,
      'purpose', c.purpose, 'purpose_zh', c.purpose_zh, 'slots', c.slots,
      'backups_open', coalesce(c.backups_open, false),
      'selection_closed', c.selection_closed_at is not null,
      'deadline', c.deadline, 'state', c.state, 'deliverable', c.deliverable,
      'push_format', c.push_format, 'brief', c.brief, 'brief_zh', c.brief_zh,
      'invoice_no', case when billable then c.invoice_no end,
      'invoice_url', case when billable then c.invoice_url end),
    -- Currency and tax travel with the campaign, because the client's page
    -- prints both and must not assume Malaysia.
    'client', jsonb_build_object('name', cl.name, 'logo_url', cl.logo_url,
      'market', coalesce(cl.market, 'MY'), 'sst_applies', coalesce(cl.sst_applies, true)),
    /* A draft reaches the client when the team releases it, and not a moment
       before. `submitted` is the team's own step, so it is reported as
       `pending_draft`: the client is not asked to approve something they
       cannot open, and does not learn that a round exists. A `changes` the
       team raised is the same round going back to the creator, so it is
       withheld the same way; a `changes` the client raised is their own and
       is reported as it is. The mapping is here and not on the page, because
       what a client may not see is withheld by this function. */
    'options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'name', cr.name,
        'rate', o.rate, 'platforms', o.platforms, 'state', s.shown,
        'is_replacement', o.is_replacement, 'added_at', o.added_at,
        -- Production. Present once a creator is locked; null before that, so
        -- the page can tell "not started" from "nothing to say".
        'visit_date', o.visit_date, 'visit_time', o.visit_time,
        'visit_location', o.visit_location, 'visit_pic', o.visit_pic,
        'visit_pic_phone', o.visit_pic_phone, 'tracking_no', o.tracking_no,
        'draft_url', case when s.released then o.draft_url end,
        /* The client's own rounds: a round the team sent back, or a request
           taken back, is not one the client made (2026-09-27). */
        'revision_round', (select count(*) from public.option_reviews r
                            where r.option_id = o.id and r.source = 'client'
                              and r.decision = 'changes' and r.undone_at is null)::int + 1,
        'planned_publish', o.planned_publish,
        /* What the creator uploaded, once it has been released: the round
           the team last released (`released_round`, stamped at release), so
           a creator's next round, uploaded after the client asked for
           changes, stays with the team until it is released in its turn
           (audit S5, 2026-10-10). A file hidden after the client's approval
           is never sent (audit S6). */
        'files', case when s.released then coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', d.id, 'url', d.url, 'name', d.name, 'kind', d.kind,
              'bytes', d.bytes) order by d.uploaded_at)
            from campaign_deliverables d
            where d.option_id = o.id and d.removed_at is null and d.hidden_at is null
              and d.round = coalesce(o.released_round,
                            (select max(d2.round) from campaign_deliverables d2
                              where d2.option_id = o.id and d2.removed_at is null))
          ), '[]'::jsonb) else '[]'::jsonb end,
        -- The caption is part of what is being approved, so it travels with
        -- the files and is withheld with them.
        'caption', case when s.released then o.draft_caption end,
        'profiles', coalesce((
          select jsonb_agg(jsonb_build_object('platform', p.platform, 'url', p.url))
          from creator_profiles p where p.creator_id = cr.id), '[]'::jsonb),
        -- One row per platform posted on, so two placements stay two numbers.
        'posts', coalesce((
          select jsonb_agg(jsonb_build_object(
            'platform', pp.platform, 'post_url', pp.post_url,
            'published_at', pp.published_at, 'window_days', pp.window_days,
            'impressions', pp.impressions, 'engagements', pp.engagements,
            'views', pp.views, 'measured_at', pp.measured_at) order by pp.platform)
          from option_posts pp where pp.option_id = o.id), '[]'::jsonb),
        /* What was last decided, so the card can say who approved it and
           when rather than jumping to the next step with nothing to show for
           the decision. The client's own decisions, and an approval the team
           gave on the client's behalf (`by_team`, read "Proceeded by"); a
           team send-back stays withheld. Withheld with the draft it is about. */
        'review', case when s.released then (
            select jsonb_build_object('decision', r.decision, 'reviewer', r.reviewer,
                                      'note', case when r.source = 'client' then r.note end,
                                      'at', r.created_at, 'by_team', r.source = 'team')
            from option_reviews r where r.option_id = o.id
              and (r.source = 'client' or r.decision = 'approved') and r.undone_at is null
            order by r.created_at desc limit 1) end)
        order by o.position, o.added_at)
      from campaign_options o
      join creators cr on cr.id = o.creator_id
      cross join lateral (
        select sh.shown,
               sh.shown in ('reviewing', 'changes', 'scheduled', 'posted', 'completed')
                 as released
        from (select case
                       when o.state = 'submitted' then 'pending_draft'
                       when o.state = 'changes'
                            and coalesce(o.changes_by, 'client') = 'team' then 'pending_draft'
                       else o.state
                     end as shown) sh
      ) s
      where o.campaign_id = c.id and o.state <> 'replaced'), '[]'::jsonb)
  );
end $$;

revoke all on function public.get_campaign(text, text) from public;
grant execute on function public.get_campaign(text, text) to anon, authenticated;

-- END OF RELEASED FILES -------------------------------------------------------

select public.functions_tidy();
