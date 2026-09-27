-- ===========================================================================
-- THE REVIEW LOOP REACHES EVERYONE — a request for changes is read where it
-- is acted on, and one made by mistake can be taken back.
-- 2026-09-27. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-09-27: "when client submitted changes, why is
-- the change comments from client portal are not shown inside"; "the problem
-- happens same in the admin portal too"; "revert for changes"):
--  1. Every decision on a draft is one row in `option_reviews`, whoever made
--     it: the client's (`review_draft`, `source` client) and the team's own
--     send-back (`campaign_send_back`, `source` team). The team's note lived
--     only in `drop_reason` and the console read neither; the client's
--     reached the creator only with the hotfix of the same day
--     (THE CREATOR READS THE CLIENT'S NOTE).
--  2. `get_creator` sends the open request's note from the record, from
--     either side and never one taken back (`drop_reason` still answers for
--     a team round sent back before this).
--  3. `get_campaign` counts the client's own rounds only, and never shows a
--     request that was taken back; a team round stays withheld as before.
--  4. `campaign_revert_changes` takes a request back. The client's goes back
--     to Client review on the round that was checked and released to them,
--     refused once the creator has handed in new files (they would reach the
--     client unchecked); the team's goes back to Submitted. The request stays
--     on the record as taken back (`undone_at`, `undone_by`). A direct move
--     into Client review from Changes requested was refused by the release
--     gate, because the client's request moves the round the check counts.
--
-- ROLLBACK
--   drop function if exists public.campaign_send_back(uuid, text);
--   drop function if exists public.campaign_revert_changes(uuid);
--   Re-run get_creator and get_campaign from their canonical sections above.
--   alter table public.option_reviews drop constraint if exists option_reviews_source_check;
--   alter table public.option_reviews drop column if exists source,
--     drop column if exists undone_at, drop column if exists undone_by;
-- ===========================================================================

alter table public.option_reviews add column if not exists source text not null default 'client';
alter table public.option_reviews add column if not exists undone_at timestamptz;
alter table public.option_reviews add column if not exists undone_by uuid references public.team_members(id);
do $$ begin
  alter table public.option_reviews add constraint option_reviews_source_check
    check (source in ('client', 'team'));
exception when duplicate_object then null;
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
        /* What the client last decided, so the card can say who approved it
           and when rather than jumping to the next step with nothing to show
           for the decision. Withheld with the draft it is about. */
        'review', case when s.released then (
            select jsonb_build_object('decision', r.decision, 'reviewer', r.reviewer,
                                      'note', r.note, 'at', r.created_at)
            from option_reviews r where r.option_id = o.id
              and r.source = 'client' and r.undone_at is null
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
    /* Who they are to us: the name the team keyed, since when, and the
       profile links the client's selection page opens, which they may keep
       up to date themselves. Never `client_rate`: that is the client's
       price, not theirs to read. */
    'creator', jsonb_build_object('name', cr.name, 'code', cr.access_code,
      'since', cr.created_at,
      'profiles', coalesce((
        select jsonb_agg(jsonb_build_object('platform', p.platform, 'handle', p.handle, 'url', p.url)
                         order by p.platform, p.url)
          from creator_profiles p where p.creator_id = cr.id), '[]'::jsonb)),
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
          /* NO RATE, AND NO CURRENCY. `campaign_options.rate` is what the
             client is quoted for this booking and carries our markup, so it
             is not the creator's to read and is certainly not "their fee";
             what a creator is paid is agreed with them and claimed on AP01,
             which the page links to once the work is approved. `currency`
             existed only to format that one figure and names the client's
             market, which is a fact about the client. */
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
          /* The open request's note, whoever made it: the client's through
             their page, the team's through the send-back (2026-09-27). A
             team round sent back before the record held it is in
             `drop_reason`. */
          'change_note', case when o.state = 'changes' then coalesce(
            (select r.note from public.option_reviews r
              where r.option_id = o.id and r.decision = 'changes' and r.undone_at is null
                and r.source = case when coalesce(o.changes_by, 'client') = 'team' then 'team' else 'client' end
              order by r.created_at desc limit 1),
            case when o.changes_by = 'team' then o.drop_reason end) end,
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

revoke all on function public.get_campaign(text, text) from public;
grant execute on function public.get_campaign(text, text) to anon, authenticated;
grant execute on function public.get_creator(text) to anon, authenticated;

/* The team's own send-back: the draft goes back to the creator with what to
   change, on the record beside the client's decisions, and the check starts
   again on the next round. The client's page never learns of it. */
create or replace function public.campaign_send_back(p_option uuid, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members;
  o      public.campaign_options;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_n    integer;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if v_note is null then return jsonb_build_object('error', 'note-required'); end if;
  select * into o from public.campaign_options where id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'no-booking'); end if;
  if o.state <> 'submitted' then return jsonb_build_object('error', 'not-submitted'); end if;
  v_n := greatest(coalesce(o.revision_round, 0), 1);
  insert into public.option_reviews (option_id, round, decision, note, reviewer, source)
  values (p_option, v_n, 'changes', v_note, me.name, 'team');
  update public.campaign_options
     set state = 'changes', changes_by = 'team', revision_round = v_n + 1,
         qc_second_wanted = false
   where id = p_option;
  return jsonb_build_object('ok', true, 'round', v_n + 1);
end $$;
revoke all on function public.campaign_send_back(uuid, text) from public, anon;
grant execute on function public.campaign_send_back(uuid, text) to authenticated;

/* Taking a request for changes back. The client's goes back to Client review
   on the round that was checked and released to them, which is the round the
   release gate counts; it is refused once the creator has handed in files
   for the next round, because Client review would show them unchecked. The
   team's goes back to Submitted. Either way the request stays on the record,
   marked taken back. */
create or replace function public.campaign_revert_changes(p_option uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me      public.team_members;
  o       public.campaign_options;
  v_rv    uuid;
  v_team  boolean;
  v_round integer;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options where id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'no-booking'); end if;
  if o.state <> 'changes' then return jsonb_build_object('error', 'not-changes'); end if;
  v_team := coalesce(o.changes_by, 'client') = 'team';
  select r.id into v_rv from public.option_reviews r
   where r.option_id = p_option and r.decision = 'changes' and r.undone_at is null
     and r.source = case when v_team then 'team' else 'client' end
   order by r.created_at desc limit 1;
  if v_team then
    update public.campaign_options set state = 'submitted', changes_by = null
     where id = p_option;
  else
    select max(q.round) into v_round from public.option_qc q where q.option_id = p_option;
    if v_round is null then return jsonb_build_object('error', 'qc-required'); end if;
    if exists (select 1 from public.campaign_deliverables d
                where d.option_id = p_option and d.removed_at is null
                  and d.round > greatest(v_round, 1)) then
      return jsonb_build_object('error', 'new-files');
    end if;
    /* The round first, then the state: the gate reads the row as it stands,
       so it has to find the checked round there before the move. */
    update public.campaign_options set revision_round = v_round where id = p_option;
    update public.campaign_options set state = 'reviewing', changes_by = null
     where id = p_option;
  end if;
  if v_rv is not null then
    update public.option_reviews set undone_at = now(), undone_by = me.id where id = v_rv;
  end if;
  return jsonb_build_object('ok', true, 'state', case when v_team then 'submitted' else 'reviewing' end);
end $$;
revoke all on function public.campaign_revert_changes(uuid) from public, anon;
grant execute on function public.campaign_revert_changes(uuid) to authenticated;

-- END OF THE REVIEW LOOP REACHES EVERYONE ----------------------------------
