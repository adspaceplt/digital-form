-- ===========================================================================
-- WHAT A CLIENT TYPES IS HELD TO A LENGTH — names 80, notes 2,000, captions
-- 5,000 in the functions a client page or a creator writes through
-- (2026-10-18)
-- ===========================================================================
-- WHY (audit 2026-10-18, item 12): `submit_review`, `review_draft`,
-- `confirm_selection`, `confirm_selection_with`, `creator_submit` and
-- `portal_request_once` (which `portal_request` calls) took a name, a note
-- or a caption of any length from a page with no sign-in, so one call could
-- write megabytes into the reviews, the requests and the Activity record.
--
-- WHAT IT CHANGES
--   * Each refuses `too-long` (`too_long` in `submit_review`, as its other
--     refusals are written) past 80 characters for a name, 2,000 for a note
--     and 5,000 for a caption, after the link and passcode are proved and
--     before anything is written. `submit_review_seen` and `portal_request`
--     call them and so refuse alike. Nothing else in any of them moves.
--   * The pages are unchanged: no real name, note or caption comes near the
--     limits (Instagram's own caption limit is 2,200), and a refusal reads
--     as Not sent.
--
-- ORDER: this file; the pages need nothing. Safe to run twice.
-- Rollback: run REVIEW DECISIONS ASK THE PASSCODE AS THE PAGE DOES's
-- `submit_review`, PASSCODE LOCKS PER CALLER's `review_draft`,
-- `confirm_selection` and `confirm_selection_with`, the schema's earlier
-- `creator_submit` and CONFIRM ONCE's `portal_request_once` again (each the
-- definition just before this file).
-- ===========================================================================

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
revoke all on function public.submit_review(text, uuid, text, text, text, text, text, text) from public;
grant execute on function public.submit_review(text, uuid, text, text, text, text, text, text) to anon, authenticated;


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

  select * into o from campaign_options
   where id = p_option and campaign_id = c.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;

  -- Only a draft that is actually with the client can be ruled on.
  if o.state not in ('reviewing', 'changes') then
    return jsonb_build_object('error', 'not-reviewing');
  end if;
  /* A draft the team sent back to the creator is not with the client: the
     selection page shows it as Pending draft, so only a hand-made call
     could rule on it (audit B, 2026-10-17). */
  if o.state = 'changes' and coalesce(o.changes_by, 'client') = 'team' then
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


create or replace function public.confirm_selection(
  p_token text, p_person text, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
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
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
  -- What a client types is held to a length (audit 2026-10-18, item 12).
  if length(btrim(p_person)) > 80 then return jsonb_build_object('error', 'too-long'); end if;
  if c.selection_closed_at is not null and not coalesce(c.backups_open, false) then
    return jsonb_build_object('error', 'closed');
  end if;
  -- Nothing saved is nothing to confirm (a save refused under the page).
  if not exists (select 1 from campaign_options o
                  where o.campaign_id = c.id
                    and o.state = case when c.selection_closed_at is not null
                                       then 'backup' else 'shortlisted' end) then
    return jsonb_build_object('error', 'empty');
  end if;

  insert into campaign_confirmations (campaign_id, kind, person, source)
  values (c.id, 'client', trim(p_person), 'portal');

  insert into public.activity_log (actor, action, subject, detail)
  values (trim(p_person), 'campaign.confirmed', c.title,
          (select count(*)::text || ' creator' || case when count(*) = 1 then '' else 's' end
             from campaign_options
            where campaign_id = c.id and state = 'shortlisted') || ' confirmed');

  return jsonb_build_object('ok', true);
end $$;


create or replace function public.confirm_selection_with(
  p_token text, p_person text, p_passcode text, p_selected uuid[], p_backup uuid[],
  p_seen jsonb, p_idem text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c      campaigns%rowtype;
  v_sel  uuid[];
  v_bak  uuid[];
  v_all  uuid[];
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
  v_now  jsonb;
  v_snap jsonb;
  n      integer;
  v_booked integer;
begin
  select * into c from campaigns where access_token = p_token for update;
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
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
  -- What a client types is held to a length (audit 2026-10-18, item 12).
  if length(btrim(p_person)) > 80 then return jsonb_build_object('error', 'too-long'); end if;
  -- The same press again: the first answer stands and nothing is filed twice.
  if v_idem is not null and exists (select 1 from campaign_confirmations k
                                     where k.campaign_id = c.id and k.idem = v_idem) then
    return jsonb_build_object('ok', true, 'again', true);
  end if;

  v_sel := array(select distinct x from unnest(coalesce(p_selected, '{}'::uuid[])) x where x is not null);
  v_bak := case when coalesce(c.backups_open, false)
                then array(select distinct x from unnest(coalesce(p_backup, '{}'::uuid[])) x
                            where x is not null and not (x = any (v_sel)))
                else '{}'::uuid[] end;
  v_all := v_sel || v_bak;
  n := cardinality(v_sel);

  if c.selection_closed_at is not null and not (coalesce(c.backups_open, false) and n = 0) then
    return jsonb_build_object('error', 'closed');
  end if;
  if cardinality(v_all) = 0 then return jsonb_build_object('error', 'empty'); end if;
  -- The slots left are the slots less the creators already booked: a
  -- selection reopened for four of ten never books sixteen.
  v_booked := public.campaign_booked(c.id);
  if n > 0 and n > c.slots - v_booked then
    return jsonb_build_object('error', 'over-slots', 'slots', c.slots, 'booked', v_booked);
  end if;
  -- Every creator named is still on the campaign and open to choose.
  if (select count(*) from campaign_options o
       where o.id = any (v_all) and o.campaign_id = c.id
         and o.state in ('option', 'shortlisted', 'backup')) <> cardinality(v_all) then
    return jsonb_build_object('error', 'stale');
  end if;
  -- The prices the client read are the prices now.
  select jsonb_object_agg(o.id::text, o.rate) into v_now
    from campaign_options o where o.id = any (v_all);
  if exists (select 1 from campaign_options o
              where o.id = any (v_all)
                and coalesce(p_seen -> (o.id::text), 'null'::jsonb)
                    is distinct from coalesce(to_jsonb(o.rate), 'null'::jsonb)) then
    return jsonb_build_object('error', 'prices', 'rates', v_now);
  end if;

  update campaign_options set state = 'option'
   where campaign_id = c.id and state in ('shortlisted', 'backup');
  if n > 0 then
    update campaign_options set state = 'shortlisted'
     where campaign_id = c.id and id = any (v_sel) and state = 'option';
  end if;
  if cardinality(v_bak) > 0 then
    update campaign_options set state = 'backup'
     where campaign_id = c.id and id = any (v_bak) and state = 'option';
  end if;

  select jsonb_agg(jsonb_build_object('id', o.id, 'creator', cr.name, 'rate', o.rate, 'as', o.state)
                   order by o.position, o.added_at)
    into v_snap
    from campaign_options o join creators cr on cr.id = o.creator_id
   where o.id = any (v_all);
  insert into campaign_confirmations (campaign_id, kind, person, source, idem, snapshot)
  values (c.id, 'client', trim(p_person), 'portal', v_idem, coalesce(v_snap, '[]'::jsonb));

  insert into public.activity_log (actor, action, subject, detail)
  values (trim(p_person), 'campaign.confirmed', c.title,
          case when n > 0 then n::text || ' creator' || case when n = 1 then '' else 's' end || ' confirmed'
               else cardinality(v_bak)::text || ' backup' || case when cardinality(v_bak) = 1 then '' else 's' end || ' confirmed' end);

  return jsonb_build_object('ok', true, 'selected', n);
end $$;


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
  select * into o from campaign_options where id = p_option and creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.creator_can_deliver(o.state) then
    return jsonb_build_object('error', 'closed');
  end if;
  -- What a creator types is held to a length (audit 2026-10-18, item 12).
  if length(coalesce(p_caption, '')) > 5000 then return jsonb_build_object('error', 'too-long'); end if;
  select count(*) into n from campaign_deliverables
   where option_id = p_option and removed_at is null;
  if n = 0 then return jsonb_build_object('error', 'empty'); end if;

  /* `submitted` is ours, not the client's. It used to move straight to
     `reviewing`, which on the client's page reads "Your approval": the chip
     asked them to act the moment a creator uploaded, while the files are
     team-only, so there was nothing there for them to open. The team reviews
     it and releases it. */
  update campaign_options
     set state = 'submitted', draft_caption = p_caption, submitted_at = now(),
         changes_by = null          -- that round is over, whoever raised it
   where id = p_option;

  -- A creator is a party to this too, and when they handed in is exactly the
  -- fact a late delivery turns on.
  insert into public.activity_log (actor, action, subject, detail)
  select cr.name, 'campaign.submitted', c.title,
         n::text || ' file' || case when n = 1 then '' else 's' end || ' handed in'
         || case when o.state = 'submitted' then ' · updated' else '' end
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'files', n);
end $$;


create or replace function public.portal_request_once(
  p_client uuid, p_kind text, p_service uuid, p_note text, p_idem text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  me     public.client_contacts%rowtype;
  sv     public.client_services%rowtype;
  rid    uuid;
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  -- The same request again (a reply lost on the way): the one already filed.
  if v_idem is not null then
    select r.id into rid from public.client_requests r
     where r.client_id = p_client and r.idem = v_idem;
    if rid is not null then return jsonb_build_object('ok', true, 'id', rid, 'again', true); end if;
  end if;
  if p_kind not in ('upgrade', 'downgrade', 'cancel', 'details') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  -- What a client types is held to a length (audit 2026-10-18, item 12).
  if length(coalesce(p_note, '')) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into cl from public.clients where id = p_client;
  select * into me from public.client_contacts
    where client_id = p_client and portal_access and archived_at is null and lower(email) = who
    order by is_primary desc limit 1;
  if p_kind <> 'details' then
    select * into sv from public.client_services
      where id = p_service and client_id = p_client and archived_at is null and state = 'confirmed';
    if sv.id is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if p_kind <> 'cancel' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note-required');
  end if;
  insert into public.client_requests (client_id, contact_id, contact_name, kind, service_id, service_label, note, idem)
  values (p_client, me.id, me.name, p_kind, sv.id, sv.label, nullif(btrim(p_note), ''), v_idem)
  on conflict (client_id, idem) where idem is not null do nothing
  returning id into rid;
  if rid is null then
    select r.id into rid from public.client_requests r
     where r.client_id = p_client and r.idem = v_idem;
    return jsonb_build_object('ok', true, 'id', rid, 'again', true);
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'request.raised', cl.name, p_kind || coalesce(' · ' || sv.label, ''));
  return jsonb_build_object('ok', true, 'id', rid);
end $$;
-- END OF WHAT A CLIENT TYPES IS HELD TO A LENGTH ----------------------------

select public.functions_tidy();
