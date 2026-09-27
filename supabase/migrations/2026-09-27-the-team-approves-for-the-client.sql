-- ===========================================================================
-- THE TEAM APPROVES FOR THE CLIENT — a draft the client agreed to by word of
-- mouth is approved from the console, and the client's page says who did.
-- 2026-09-27. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-09-27: "add one Confirm internally button for
-- the creator draft (even after revisions) so sometimes if clients never
-- response but once we got their verbal comms or confirmation, we could
-- proceeded to approve internally. Client-facing side will show Proceed by
-- {internal user} {timestamp}"):
--  1. `campaign_proceed` approves a draft at Client review on the client's
--     behalf: one row in `option_reviews` (`source` team, decision approved,
--     the colleague's name), and the booking moves to Scheduled. Campaigns
--     Work, as every other step on the card.
--  2. `campaign_revert_approval` takes an approval back, the client's or the
--     team's: the booking goes back to Client review and the approval stays
--     on the record, taken back (`undone_at`, `undone_by`).
--  3. `get_campaign` sends the team's approval as the last decision
--     (`by_team`), so the client's page reads "Proceeded by {name}". A team
--     send-back is still withheld, and a team row never carries its note.
--
-- ROLLBACK
--   drop function if exists public.campaign_proceed(uuid);
--   drop function if exists public.campaign_revert_approval(uuid);
--   Re-run get_campaign from THE REVIEW LOOP REACHES EVERYONE.
-- ===========================================================================

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
        /* What the creator uploaded, once it has been released: the newest
           round handed in, which at `changes` is the one the client turned
           down and wants to refer back to. Never the round sitting with the
           team. */
        'files', case when s.released then coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', d.id, 'url', d.url, 'name', d.name, 'kind', d.kind,
              'bytes', d.bytes) order by d.uploaded_at)
            from campaign_deliverables d
            where d.option_id = o.id and d.removed_at is null
              and d.round = (select max(d2.round) from campaign_deliverables d2
                             where d2.option_id = o.id and d2.removed_at is null)
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

create or replace function public.campaign_proceed(p_option uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me  public.team_members;
  o   public.campaign_options;
  v_n integer;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options where id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'no-booking'); end if;
  if o.state <> 'reviewing' then return jsonb_build_object('error', 'not-reviewing'); end if;
  v_n := greatest(coalesce(o.revision_round, 0), 1);
  insert into public.option_reviews (option_id, round, decision, note, reviewer, source)
  values (p_option, v_n, 'approved', null, me.name, 'team');
  update public.campaign_options set state = 'scheduled', changes_by = null
   where id = p_option;
  return jsonb_build_object('ok', true, 'reviewer', me.name);
end $$;
revoke all on function public.campaign_proceed(uuid) from public, anon;
grant execute on function public.campaign_proceed(uuid) to authenticated;

create or replace function public.campaign_revert_approval(p_option uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members;
  o    public.campaign_options;
  v_rv uuid;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options where id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'no-booking'); end if;
  if o.state <> 'scheduled' then return jsonb_build_object('error', 'not-scheduled'); end if;
  select r.id into v_rv from public.option_reviews r
   where r.option_id = p_option and r.decision = 'approved' and r.undone_at is null
   order by r.created_at desc limit 1;
  update public.campaign_options set state = 'reviewing' where id = p_option;
  if v_rv is not null then
    update public.option_reviews set undone_at = now(), undone_by = me.id where id = v_rv;
  end if;
  return jsonb_build_object('ok', true, 'state', 'reviewing');
end $$;
revoke all on function public.campaign_revert_approval(uuid) from public, anon;
grant execute on function public.campaign_revert_approval(uuid) to authenticated;

-- END OF THE TEAM APPROVES FOR THE CLIENT ----------------------------------
