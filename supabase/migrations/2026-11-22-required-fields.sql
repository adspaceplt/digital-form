-- ===========================================================================
-- REQUIRED FIELDS -------------------------------------------------------------
-- ===========================================================================
-- WHY (2026-11-22): the user: required fields could be left empty and the
-- record still saved. Every form now refuses at save (js/form.js §10); where
-- a wrong value would damage records, the database refuses it too.
--
-- WHAT IT CHANGES
--   * Checks on the tables pages write directly: a name or title of one
--     character at least (clients, client_contacts, creators, team_members,
--     campaigns, client_services, services); an email of an address's shape
--     or none (client_contacts, clients.finance_email, team_members; the
--     reading ADspaceWords.emailOk holds); an amount from 0
--     (campaign_options.rate and creators.client_rate to 1,000,000,
--     services.rate); a count from 1 (campaigns.slots, client_services
--     .tenure); a date from 14 Aug 2023 to 31 Dec 2099 (campaigns.deadline,
--     a booking's five dates); a report's figures from 0. Every live row
--     met them on 2026-11-22 (read before this was applied), so each is
--     added valid.
--   * `submit_review` refuses a blank reviewer (`name_required`) and
--     `review_draft` a blank reviewer (`name-required`) and a request for
--     changes with no note (`note-required`), each restated whole from its
--     last definition, every earlier refusal, grant and revoke kept.
--
-- ORDER: the pages (they already refuse each of these), then this file
-- (Management API). An open page sends nothing these refuse.
-- Safe to run twice. Rollback: drop each constraint by name
-- (`alter table … drop constraint if exists …`), and run submit_review and
-- review_draft from their earlier bands again.
-- ===========================================================================

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'campaign_options_rate_range') then
    alter table public.campaign_options add constraint campaign_options_rate_range check (rate is null or rate between 0 and 1000000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'creators_client_rate_range') then
    alter table public.creators add constraint creators_client_rate_range check (client_rate is null or client_rate between 0 and 1000000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'creators_name_given') then
    alter table public.creators add constraint creators_name_given check (char_length(btrim(name)) >= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'client_contacts_name_given') then
    alter table public.client_contacts add constraint client_contacts_name_given check (char_length(btrim(name)) >= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'client_contacts_email_shape') then
    alter table public.client_contacts add constraint client_contacts_email_shape check (email is null or btrim(email) = '' or email ~* '^[^\s@,;:<>"''()\[\]\\]+@[^\s@,;:<>"''()\[\]\\]+\.[a-z]{2,}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'clients_name_given') then
    alter table public.clients add constraint clients_name_given check (char_length(btrim(name)) >= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'clients_finance_email_shape') then
    alter table public.clients add constraint clients_finance_email_shape check (finance_email is null or btrim(finance_email) = '' or finance_email ~* '^[^\s@,;:<>"''()\[\]\\]+@[^\s@,;:<>"''()\[\]\\]+\.[a-z]{2,}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'team_members_name_given') then
    alter table public.team_members add constraint team_members_name_given check (char_length(btrim(name)) >= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'team_members_email_shape') then
    alter table public.team_members add constraint team_members_email_shape check (email is null or btrim(email) = '' or email ~* '^[^\s@,;:<>"''()\[\]\\]+@[^\s@,;:<>"''()\[\]\\]+\.[a-z]{2,}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'campaigns_title_given') then
    alter table public.campaigns add constraint campaigns_title_given check (char_length(btrim(title)) >= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'campaigns_slots_one') then
    alter table public.campaigns add constraint campaigns_slots_one check (slots is null or slots >= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'campaigns_deadline_range') then
    alter table public.campaigns add constraint campaigns_deadline_range check (deadline is null or deadline between date '2023-08-14' and date '2099-12-31');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'campaign_options_dates_range') then
    alter table public.campaign_options add constraint campaign_options_dates_range check (coalesce(least(visit_date, submission_due, planned_publish, posted_on, pay_by), date '2023-08-14') >= date '2023-08-14' and coalesce(greatest(visit_date, submission_due, planned_publish, posted_on, pay_by), date '2099-12-31') <= date '2099-12-31');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'sm_report_posts_figures') then
    alter table public.sm_report_posts add constraint sm_report_posts_figures check (coalesce(least(comments, engagements, impressions, interactions, likes, reach, saves, shares, views), 0) >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'sm_report_platforms_followers') then
    alter table public.sm_report_platforms add constraint sm_report_platforms_followers check (coalesce(least(followers_start, followers_end), 0) >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'client_services_label_given') then
    alter table public.client_services add constraint client_services_label_given check (char_length(btrim(label)) >= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'client_services_tenure_one') then
    alter table public.client_services add constraint client_services_tenure_one check (tenure is null or tenure >= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'services_rate_floor') then
    alter table public.services add constraint services_rate_floor check (rate is null or rate >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'services_name_given') then
    alter table public.services add constraint services_name_given check (char_length(btrim(name)) >= 1);
  end if;
end $$;

create or replace function public.submit_review(
  p_token      text,
  p_post_id    uuid,
  p_decision   text,
  p_note       text default null,
  p_reviewer   text default null,
  p_passcode   text default null,
  p_caption    text default null,
  p_caption_zh text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client_id uuid;
  v_stored    text;
  v_post      public.posts%rowtype;
  v_cap       text;
  v_cap_zh    text;
begin
  if p_decision not in ('approved', 'changes') then
    return jsonb_build_object('error', 'bad_decision');
  end if;

  select c.id, c.passcode into v_client_id, v_stored
  from public.clients c
  where c.access_token = p_token
    and c.active
    and not c.review_hidden;

  if v_client_id is null then
    return jsonb_build_object('error', 'not_found');
  end if;
  -- The passcode as the link's own page asks it: counted per caller, and a
  -- caller locked out stays out here too (audit 2026-10-18, item 13).
  case public.link_passcode('review', p_token, v_stored, p_passcode)
    when 'locked' then return public.link_locked('review', p_token);
    when 'wrong' then return jsonb_build_object('error', 'not_found');
    else null;
  end case;
  -- What a client types is held to a length (audit 2026-10-18, item 12).
  if length(coalesce(p_reviewer, '')) > 80 or length(coalesce(p_note, '')) > 2000
     or length(coalesce(p_caption, '')) > 5000 or length(coalesce(p_caption_zh, '')) > 5000 then
    return jsonb_build_object('error', 'too_long');
  end if;
  -- A decision names who made it (REQUIRED FIELDS, 2026-11-22): a blank
  -- name is refused, never filed as Client.
  if coalesce(btrim(p_reviewer), '') = '' then
    return jsonb_build_object('error', 'name_required');
  end if;

  -- the post must belong to a published batch of this client
  select p.* into v_post
  from public.posts p
  join public.batches b on b.id = p.batch_id
  where p.id = p_post_id and b.client_id = v_client_id and b.published;

  if v_post.id is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  /* A suggested copy is kept only where it differs from the copy on show,
     and only on a request for changes. */
  if p_decision = 'changes' then
    v_cap    := case when p_caption is not null
                      and p_caption is distinct from coalesce(v_post.caption, '') then p_caption end;
    v_cap_zh := case when p_caption_zh is not null
                      and p_caption_zh is distinct from coalesce(v_post.caption_zh, '') then p_caption_zh end;
  end if;

  if p_decision = 'changes' and coalesce(btrim(p_note), '') = ''
     and v_cap is null and v_cap_zh is null then
    return jsonb_build_object('error', 'note_required');
  end if;

  insert into public.reviews (post_id, decision, note, reviewer, suggested_caption, suggested_caption_zh)
  values (p_post_id, p_decision, nullif(btrim(p_note), ''), nullif(btrim(p_reviewer), ''), v_cap, v_cap_zh);

  /* The activity record is the portal's account of what was decided and by
     whom, and it held only what the team did. A client approving a post is
     the decision the whole section exists to collect, and it left nothing
     anybody could produce later: the verdict sat in `reviews` alone, which
     no screen reads as a history. The reviewer's own typed name is the
     actor, because a person decided it. */
  insert into public.activity_log (actor, action, subject, detail)
  select coalesce(nullif(btrim(coalesce(p_reviewer, '')), ''), 'Client'),
         case when p_decision = 'approved' then 'review.approved' else 'review.changes' end,
         c.name,
         b.title || ' · ' || coalesce(nullif(p.platform, ''), 'post') ||
         case when p.round > 1 then ' · revision ' || p.round else '' end ||
         coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), '') ||
         case when v_cap is not null or v_cap_zh is not null then ' · caption edited' else '' end
    from public.posts p
    join public.batches b on b.id = p.batch_id
    join public.clients c on c.id = b.client_id
   where p.id = p_post_id;

  return jsonb_build_object('ok', true);
end $$;

create or replace function public.review_draft(
  p_token text, p_option uuid, p_decision text, p_note text default null,
  p_reviewer text default null, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
  o campaign_options%rowtype;
  n integer;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  -- A past client's link acts on nothing, as it reads nothing (second
  -- audit, item 7): answered as a key nobody knows, before the passcode.
  if exists (select 1 from public.clients cl where cl.id = c.client_id and cl.stage = 'past') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return public.link_locked('selection', c.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;
  if p_decision not in ('approved', 'changes') then
    return jsonb_build_object('error', 'bad-decision');
  end if;
  -- What a client types is held to a length (audit 2026-10-18, item 12).
  if length(coalesce(p_reviewer, '')) > 80 or length(coalesce(p_note, '')) > 2000 then
    return jsonb_build_object('error', 'too-long');
  end if;
  -- A decision names who made it, and a request for changes says what
  -- (REQUIRED FIELDS, 2026-11-22), as confirm_selection_with does.
  if coalesce(btrim(p_reviewer), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
  if p_decision = 'changes' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note-required');
  end if;

  -- The booking is held while it is ruled on, so two decisions at once
  -- are taken one after the other (audit 2026-10-29, 2).
  select * into o from campaign_options
   where id = p_option and campaign_id = c.id
   for update;
  if not found then return jsonb_build_object('error', 'not-found'); end if;

  /* Only a draft that is with the client can be ruled on: Reviewing, as
     the selection page draws the decision. A draft already sent back for
     changes is with the creator, so a page left open from before can no
     longer approve it unrevised (audit 2026-10-29, 2; the team's send-back
     too, audit B, 2026-10-17). */
  if o.state <> 'reviewing' then
    return jsonb_build_object('error', 'not-reviewing');
  end if;

  n := coalesce(o.revision_round, 0);

  insert into option_reviews (option_id, round, decision, note, reviewer)
  values (p_option, greatest(n, 1), p_decision, nullif(trim(coalesce(p_note, '')), ''), p_reviewer);

  if p_decision = 'approved' then
    update campaign_options set state = 'scheduled' where id = p_option;
  else
    update campaign_options
       set state = 'changes', revision_round = greatest(n, 1) + 1,
           changes_by = 'client'
     where id = p_option;
  end if;

  /* The client's decision is the one event on a campaign that nobody on the
     team witnesses, and it was the only one the activity record never held:
     a draft went to Reviewing and appeared as Scheduled with nothing in
     between saying who had said yes. The reviewer's own name is the actor,
     because a person decided it. */
  insert into activity_log (actor, action, subject, detail)
  select coalesce(nullif(trim(coalesce(p_reviewer, '')), ''), 'Client'),
         'campaign.review', c.title,
         cr.name || ' · ' ||
         case when p_decision = 'approved' then 'Approved' else 'Changes requested' end ||
         coalesce(': ' || nullif(trim(coalesce(p_note, '')), ''), '')
    from creators cr where cr.id = o.creator_id;

  return jsonb_build_object('ok', true, 'decision', p_decision);
end $$;

-- END OF REQUIRED FIELDS ----------------------------------------------------

select public.functions_tidy();
