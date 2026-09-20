-- ==========================================================================
-- THE CREATOR NEVER SEES THE RATE
-- 2026-09-20. Safe to run twice. Rollback at the foot.
--
-- `campaign_options.rate` is what the CLIENT is quoted for that booking: it
-- carries our markup, and it is the figure the client-facing selection page
-- prints beside each creator. `get_creator` was sending the same column to
-- the creator's own page, which drew it as "Your fee".
--
-- So every creator on a campaign has been able to read the client's price,
-- and has been told it is theirs. Two different harms from one column: what
-- we charge a client is not the creator's business, and a creator quoted a
-- number they will not be paid will chase the difference.
--
-- What a creator is paid is agreed with them and claimed on AP01, which the
-- page already links to once the work is approved. Nothing on that page needs
-- a figure, so none is sent: the withholding is here and not on the page,
-- because the page is a page anybody can open and the function is the only
-- thing that decides what leaves the database.
--
-- `currency` goes with it. It existed only to format that one figure, and a
-- currency on its own tells a creator which market the client is in, which is
-- a fact about the client and not about the booking.
--
-- The client's own page is untouched: `get_campaign` still sends the rate,
-- because the client is the party being quoted.
-- ==========================================================================

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
grant execute on function public.get_creator(text) to anon, authenticated;

-- Rollback: restore the two keys in the booking object above
--   ('rate', o.rate and
--    'currency', case when coalesce(cl.market, 'MY') = 'SG' then 'SGD' else 'MYR' end)
-- and re-create the function.
