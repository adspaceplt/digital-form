-- ===========================================================================
-- 2026-09-15  A creator's submission reaches the team before the client
--
-- WHAT WAS WRONG
--   creator_submit moved the step straight to `reviewing`, which on the
--   client's page reads "Your approval". The chip asked the client to decide
--   the moment a creator uploaded, while campaign_deliverables is team-only,
--   so there was nothing there for them to open and the Approve buttons only
--   drew when somebody had separately pasted a Drive link.
--
-- WHAT THIS CHANGES
--   A `submitted` step between Pending draft and Reviewing.
--     creator_submit  -> submitted        (the team's step)
--     team releases   -> reviewing        (the client's step, from the console)
--   get_campaign, which is the client's only door, now reports `submitted` as
--   `pending_draft`, and reports a `changes` the team raised the same way, so
--   an internal round never appears on their page. The creator's files and the
--   caption are sent only once the draft is with the client, and only for the
--   newest round handed in.
--
--   One new column, `campaign_options.changes_by` ('client' | 'team'), because
--   `changes` now serves two rounds that look alike from the row and are
--   opposite from the client's seat. Existing rows are backfilled to 'client':
--   before today the team had no way to raise one.
--
--   No data is destroyed and no step moves by itself. A booking already at
--   `reviewing` stays there and behaves exactly as it does now.
--
-- HOW TO RUN IT
--   Supabase dashboard > SQL editor > paste this file > Run. Safe to run more
--   than once. Nothing else in supabase/schema.sql needs re-running.
--
-- ROLLBACK
--   At the foot, commented out. It puts creator_submit back to `reviewing`
--   and get_campaign back to reporting the raw state. The column is left in
--   place, because dropping it would lose which side raised each open round.
-- ===========================================================================

alter table public.campaign_options add column if not exists changes_by text;

-- Before today, only the client could raise one.
update public.campaign_options set changes_by = 'client'
 where state = 'changes' and changes_by is null;

-- ---------------------------------------------------------------------------
-- Submitting reaches the team.
-- ---------------------------------------------------------------------------
create or replace function public.creator_submit(p_code text, p_option uuid, p_caption text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr creators%rowtype;
  o  campaign_options%rowtype;
  n  integer;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from campaign_options co
   where co.id = p_option and co.creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.creator_can_deliver(o.state) then
    return jsonb_build_object('error', 'closed');
  end if;
  select count(*) into n from campaign_deliverables
   where option_id = p_option and removed_at is null;
  if n = 0 then return jsonb_build_object('error', 'empty'); end if;

  update campaign_options
     set state = 'submitted', draft_caption = p_caption, submitted_at = now(),
         changes_by = null          -- that round is over, whoever raised it
   where id = p_option;
  return jsonb_build_object('ok', true, 'files', n);
end $$;

grant execute on function public.creator_submit(text, uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- The client's own decision says so.
-- ---------------------------------------------------------------------------
create or replace function public.review_draft(
  p_token text, p_option uuid, p_decision text, p_note text default null,
  p_reviewer text default null, p_passcode text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c campaigns%rowtype;
  o campaign_options%rowtype;
  n integer;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if c.passcode is not null and c.passcode <> ''
     and (p_passcode is null or p_passcode <> c.passcode) then
    return jsonb_build_object('error', 'passcode');
  end if;
  if p_decision not in ('approved', 'changes') then
    return jsonb_build_object('error', 'bad-decision');
  end if;

  select * into o from campaign_options co
   where co.id = p_option and co.campaign_id = c.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;

  -- Only a draft that is actually with the client can be ruled on. `submitted`
  -- is not, which is the whole point of this migration.
  if o.state not in ('reviewing', 'changes') then
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

  return jsonb_build_object('ok', true, 'decision', p_decision);
end $$;

revoke all on function public.review_draft(text, uuid, text, text, text, text) from public;
grant execute on function public.review_draft(text, uuid, text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- The client's only door, with the state mapping, the files and the caption.
-- Byte for byte the definition in supabase/schema.sql; tests/sql.js applies
-- this file and then asserts what it withholds, so the two cannot drift.
-- ---------------------------------------------------------------------------
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
        'revision_round', o.revision_round,
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
          from option_posts pp where pp.option_id = o.id), '[]'::jsonb))
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

grant execute on function public.get_campaign(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Check it took. All three should return true.
-- ---------------------------------------------------------------------------
-- select exists (select 1 from information_schema.columns
--   where table_name = 'campaign_options' and column_name = 'changes_by') as has_column;
--
-- select prosrc like '%submitted%' as submits_to_team
--   from pg_proc where proname = 'creator_submit';
--
-- select prosrc like '%changes_by%' as stamps_the_client
--   from pg_proc where proname = 'review_draft';

-- ---------------------------------------------------------------------------
-- ROLLBACK
-- ---------------------------------------------------------------------------
-- Put creator_submit back to reviewing. The column stays: dropping it would
-- lose which side raised every open round.
--
-- create or replace function public.creator_submit(p_code text, p_option uuid, p_caption text)
-- returns jsonb
-- language plpgsql security definer set search_path = public as $$
-- declare
--   cr creators%rowtype;
--   o  campaign_options%rowtype;
--   n  integer;
-- begin
--   select * into cr from creators where access_code = upper(p_code) and active;
--   if not found then return jsonb_build_object('error', 'not-found'); end if;
--   select * into o from campaign_options co
--    where co.id = p_option and co.creator_id = cr.id;
--   if not found then return jsonb_build_object('error', 'not-found'); end if;
--   if not public.creator_can_deliver(o.state) then
--     return jsonb_build_object('error', 'closed');
--   end if;
--   select count(*) into n from campaign_deliverables
--    where option_id = p_option and removed_at is null;
--   if n = 0 then return jsonb_build_object('error', 'empty'); end if;
--   update campaign_options
--      set state = 'reviewing', draft_caption = p_caption, submitted_at = now()
--    where id = p_option;
--   return jsonb_build_object('ok', true, 'files', n);
-- end $$;
--
-- Any booking left at `submitted` after a rollback is invisible to the client
-- until somebody moves it on, so move those first:
-- update public.campaign_options set state = 'reviewing' where state = 'submitted';
