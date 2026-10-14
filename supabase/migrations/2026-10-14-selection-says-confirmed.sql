-- ===========================================================================
-- SELECTION SAYS CONFIRMED — the creator selection page knows the client has
-- confirmed (2026-10-14)
-- ===========================================================================
-- WHY (the UX audit of the public pages, 2026-10-14, SELECTION-1): a client
-- who confirmed and opened the link again met the picking page with Confirm
-- selection live and no word that it had been confirmed; a second press
-- filed a second confirmation.
--
-- WHAT IT CHANGES
--   * `get_campaign` adds `campaign.confirmed`: the client's latest
--     confirmation (`campaign_confirmations`, kind `client`), its person and
--     time and the creators it named as chosen (its snapshot's shortlisted
--     ids), else null. Nothing else in the answer moves.
--
-- Safe to run twice. Rollback: run get_campaign from RELEASED FILES again.
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
      'selection_closed', c.selection_closed_at is not null,
      'deadline', c.deadline, 'state', c.state, 'deliverable', c.deliverable,
      'push_format', c.push_format, 'brief', c.brief, 'brief_zh', c.brief_zh,
      'invoice_no', case when billable then c.invoice_no end,
      'invoice_url', case when billable then c.invoice_url end,
      /* The client's last confirmation: who, when, and the creators it
         named, so a page opened again says the selection was confirmed and
         asks again only once the picks differ (2026-10-14). */
      'confirmed', (
        select jsonb_build_object('person', k.person, 'at', k.created_at,
                 'selected', coalesce((select jsonb_agg(x->>'id') from jsonb_array_elements(coalesce(k.snapshot, '[]'::jsonb)) x
                                        where x->>'as' = 'shortlisted'), '[]'::jsonb))
          from campaign_confirmations k
         where k.campaign_id = c.id and k.kind = 'client'
         order by k.created_at desc limit 1)),
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

-- END OF SELECTION SAYS CONFIRMED ---------------------------------------------

select public.functions_tidy();
