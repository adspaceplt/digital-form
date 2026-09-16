-- 2026-09-19 — the client's decision is recorded, and a creator can say how
-- the job went.
--
-- Three things this adds, all additive and safe to run twice:
--
--   1. `review_draft` writes the client's verdict to `activity_log`. It was
--      the one event on a campaign nobody on the team witnessed and the only
--      one the record never held: a draft went to Reviewing and reappeared as
--      Scheduled with nothing in between saying who had said yes.
--   2. `get_campaign` sends the last decision with the booking it is about, so
--      the client's own card can read "Approved by Wei Ling on 16 Sept"
--      instead of silently moving on.
--   3. `campaign_options.creator_rating` (1 to 5) plus `creator_rate`, asked
--      on the creator's page once the booking is completed and never before.
--      `get_creator` sends it back so the page shows what they gave.
--
-- Nothing is dropped and no data is rewritten. Rollback is at the foot.

-- ---- 1. the rating column ------------------------------------------------
alter table public.campaign_options add column if not exists creator_rating smallint;
do $$ begin
  alter table public.campaign_options
    add constraint campaign_options_creator_rating_range
    check (creator_rating is null or creator_rating between 1 and 5);
exception when duplicate_object then null; end $$;

-- ---- 2. the functions ----------------------------------------------------
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
  if c.passcode is not null and c.passcode <> ''
     and (p_passcode is null or p_passcode <> c.passcode) then
    return jsonb_build_object('error', 'passcode');
  end if;
  if p_decision not in ('approved', 'changes') then
    return jsonb_build_object('error', 'bad-decision');
  end if;

  select * into o from campaign_options
   where id = p_option and campaign_id = c.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;

  -- Only a draft that is actually with the client can be ruled on.
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
          from option_posts pp where pp.option_id = o.id), '[]'::jsonb),
        /* What the client last decided, so the card can say who approved it
           and when rather than jumping to the next step with nothing to show
           for the decision. Withheld with the draft it is about. */
        'review', case when s.released then (
            select jsonb_build_object('decision', r.decision, 'reviewer', r.reviewer,
                                      'note', r.note, 'at', r.created_at)
            from option_reviews r where r.option_id = o.id
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

create or replace function public.get_creator(p_code text)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  cr creators%rowtype;
begin
  if p_code is null or length(trim(p_code)) < 8 then
    return jsonb_build_object('error', 'not-found');
  end if;
  select * into cr from creators
   where access_code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not cr.active then return jsonb_build_object('error', 'inactive'); end if;

  return jsonb_build_object(
    'creator', jsonb_build_object('name', cr.name, 'code', cr.access_code),
    'bookings', coalesce((
      select jsonb_agg(b order by b->>'sort')
      from (
        select jsonb_build_object(
          'id', o.id,
          'sort', coalesce(o.visit_date::text, '9999') || c.title,
          'campaign', c.title,
          'campaign_zh', c.title_zh,
          'brand', cl.name,
          'brief', c.brief,
          'brief_zh', c.brief_zh,
          'deliverable', c.deliverable,
          'push_format', c.push_format,
          'platforms', o.platforms,
          'rate', o.rate,
          'currency', case when coalesce(cl.market, 'MY') = 'SG' then 'SGD' else 'MYR' end,
          'state', o.state,
          'visit_date', o.visit_date,
          'visit_time', o.visit_time,
          'visit_location', o.visit_location,
          'visit_pic', o.visit_pic,
          'visit_pic_phone', o.visit_pic_phone,
          'tracking_no', o.tracking_no,
          'submission_due', o.submission_due,
          'planned_publish', o.planned_publish,
          'revision_round', o.revision_round,
          'change_note', case when o.state = 'changes' then o.drop_reason end,
          'caption', o.draft_caption,
          'submitted_at', o.submitted_at,
          'rating', o.creator_rating,
          'can_deliver', public.creator_can_deliver(o.state),
          'files', coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', d.id, 'url', d.url, 'name', d.name, 'kind', d.kind,
              'bytes', d.bytes, 'round', d.round)
              order by d.uploaded_at)
            from campaign_deliverables d
             where d.option_id = o.id and d.removed_at is null), '[]'::jsonb)
        ) as b
        from campaign_options o
        join campaigns c on c.id = o.campaign_id
        join clients cl on cl.id = c.client_id
        where o.creator_id = cr.id
          and c.state <> 'draft'
          and o.state in ('confirmed', 'pending_visit', 'pending_delivery',
                          'pending_draft', 'submitted', 'reviewing', 'changes',
                          'scheduled', 'posted', 'completed', 'withdrawn', 'replaced')
      ) rows), '[]'::jsonb));
end $$;

create or replace function public.creator_rate(p_code text, p_option uuid, p_stars integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr creators%rowtype;
  o  campaign_options%rowtype;
begin
  if p_stars is not null and (p_stars < 1 or p_stars > 5) then
    return jsonb_build_object('error', 'range');
  end if;
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from campaign_options where id = p_option and creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if o.state <> 'completed' then return jsonb_build_object('error', 'closed'); end if;

  update campaign_options set creator_rating = p_stars where id = p_option;
  return jsonb_build_object('ok', true, 'rating', p_stars);
end $$;

grant execute on function public.creator_rate(text, uuid, integer) to anon, authenticated;

revoke all on function public.review_draft(text, uuid, text, text, text, text) from public;
grant execute on function public.review_draft(text, uuid, text, text, text, text) to anon, authenticated;

-- ---- 3. verification ------------------------------------------------------
-- Each row should read 1.
select 'creator_rating column' as check_name,
       count(*) from information_schema.columns
 where table_schema = 'public' and table_name = 'campaign_options'
   and column_name = 'creator_rating'
union all
select 'creator_rate function', count(*) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'creator_rate'
union all
select 'review_draft logs the decision', count(*) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'review_draft'
   and p.prosrc like '%activity_log%'
union all
select 'get_campaign sends the decision', count(*) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'get_campaign'
   and p.prosrc like '%option_reviews r%'
union all
select 'get_creator sends the rating', count(*) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'get_creator'
   and p.prosrc like '%creator_rating%';

/* ---- Rollback -------------------------------------------------------------
   The column is additive and holds the creators' own answers, so dropping it
   loses data; take it out only if the feature is being withdrawn.

   drop function if exists public.creator_rate(text, uuid, integer);
   alter table public.campaign_options
     drop constraint if exists campaign_options_creator_rating_range;
   alter table public.campaign_options drop column if exists creator_rating;

   `review_draft`, `get_campaign` and `get_creator` are restored by re-running
   the copies in supabase/schema.sql from before this change.
--------------------------------------------------------------------------- */
