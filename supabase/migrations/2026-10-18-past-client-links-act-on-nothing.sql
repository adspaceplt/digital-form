-- ===========================================================================
-- PAST CLIENT LINKS ACT ON NOTHING — a past client's selection link saves,
-- confirms and decides nothing, as it already reads nothing, and its link
-- preview names nobody. 2026-10-18. Safe to run twice. Rollback at the foot.
-- Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/confirmonce.js compares the two.
--
-- WHAT CHANGED (second audit, item 7)
--   1. save_selection, confirm_selection, confirm_selection_with and
--      review_draft answer `not-found` for a campaign whose client is Past,
--      before the passcode is asked, as get_campaign has since SELECTION
--      LINK CLOSES. Each is restated whole from PASSCODE ATTEMPTS with only
--      that check added.
--   2. share_link_preview('campaign') answers nothing for a Past client's
--      campaign, so a chat app's preview of /s/{key} names no client.
--
-- ROLLBACK
--   Run the four functions from PASSCODE ATTEMPTS again
--   (2026-10-18-passcode-attempts.sql), and share_link_preview from SHORT
--   LINKS RE-LETTERED (2026-10-15-short-links-relettered.sql).
-- ===========================================================================

create or replace function public.save_selection(
  p_token text, p_selected uuid[], p_backup uuid[], p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
  n integer;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  -- A past client's link acts on nothing, as it reads nothing (second
  -- audit, item 7): answered as a key nobody knows, before the passcode.
  if exists (select 1 from public.clients cl where cl.id = c.client_id and cl.stage = 'past') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- Five wrong passcodes lock the link for 15 minutes, answered as a key
  -- nobody knows (second audit, item 6).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return jsonb_build_object('error', 'not-found');
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;

  n := coalesce(array_length(p_selected, 1), 0);
  /* Closed once the slots were full, until the team reopens it; backups
     alone may still be named where the team opened them. */
  if c.selection_closed_at is not null and not (coalesce(c.backups_open, false) and n = 0) then
    return jsonb_build_object('error', 'closed');
  end if;
  if n > c.slots then
    return jsonb_build_object('error', 'over-slots', 'slots', c.slots);
  end if;

  -- Anything already confirmed or further along is the team's to change.
  update campaign_options set state = 'option'
   where campaign_id = c.id and state in ('shortlisted', 'backup');

  if n > 0 then
    update campaign_options set state = 'shortlisted'
     where campaign_id = c.id and id = any(p_selected) and state = 'option';
  end if;
  -- Only where the team opened them: the page hides the control, and this is
  -- what makes that a fact rather than a courtesy.
  if coalesce(c.backups_open, false) and coalesce(array_length(p_backup, 1), 0) > 0 then
    update campaign_options set state = 'backup'
     where campaign_id = c.id and id = any(p_backup) and state = 'option';
  end if;

  return jsonb_build_object('ok', true, 'selected', n);
end $$;

revoke all on function public.save_selection(text, uuid[], uuid[], text) from public;
grant execute on function public.save_selection(text, uuid[], uuid[], text) to anon, authenticated;

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
  -- Five wrong passcodes lock the link for 15 minutes, answered as a key
  -- nobody knows (second audit, item 6).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return jsonb_build_object('error', 'not-found');
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
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

revoke all on function public.confirm_selection(text, text, text) from public;
grant execute on function public.confirm_selection(text, text, text) to anon, authenticated;

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
  -- Five wrong passcodes lock the link for 15 minutes, answered as a key
  -- nobody knows (second audit, item 6).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return jsonb_build_object('error', 'not-found');
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
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

revoke all on function public.confirm_selection_with(text, text, text, uuid[], uuid[], jsonb, text) from public;
grant execute on function public.confirm_selection_with(text, text, text, uuid[], uuid[], jsonb, text) to anon, authenticated;

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
  -- Five wrong passcodes lock the link for 15 minutes, answered as a key
  -- nobody knows (second audit, item 6).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return jsonb_build_object('error', 'not-found');
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;
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

revoke all on function public.review_draft(text, uuid, text, text, text, text) from public;
grant execute on function public.review_draft(text, uuid, text, text, text, text) to anon, authenticated;

create or replace function public.share_link_preview(p_kind text, p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(case p_kind
    when 'which' then (
      select case
        when exists (select 1 from public.campaigns k where k.access_token = p_key) then jsonb_build_object('kind', 'campaign')
        when exists (select 1 from public.clients c where c.script_key = p_key) then jsonb_build_object('kind', 'script')
      end
       where p_key ~ '^[A-Za-z0-9_-]{6,64}$')
    when 'script' then (
      select jsonb_strip_nulls(jsonb_build_object('brand', c.name))
        from public.clients c
       where p_key ~ '^[A-Za-z0-9_-]{6,64}$'
         and c.script_key = p_key and c.active
         and exists (select 1 from public.video_scripts s where s.client_id = c.id and s.status = 'shared')
       limit 1)
    when 'campaign' then (
      select jsonb_strip_nulls(jsonb_build_object('brand', c.name, 'title', nullif(btrim(k.title), '')))
        from public.campaigns k
        join public.clients c on c.id = k.client_id
       where p_key ~ '^[A-Za-z0-9_-]{6,64}$'
         and k.access_token = p_key
         and coalesce(k.passcode, '') = '' and k.state <> 'draft'
         and coalesce(c.stage, '') <> 'past'
       limit 1)
    when 'creator' then (
      select case when count(*) = 1 then jsonb_strip_nulls(jsonb_build_object('brand', min(c.name), 'title', nullif(btrim(min(k.title)), ''))) end
        from public.creators cr
        join public.campaign_options o on o.creator_id = cr.id
         and o.state in ('confirmed', 'pending_visit', 'pending_draft', 'submitted', 'reviewing', 'changes', 'scheduled', 'posted')
        join public.campaigns k on k.id = o.campaign_id
        join public.clients c on c.id = k.client_id
       where p_key ~ '^[A-Za-z0-9]{8}$'
         and cr.access_code = upper(p_key) and cr.active)
  end, '{}'::jsonb)
$$;
revoke all on function public.share_link_preview(text, text) from public;
grant execute on function public.share_link_preview(text, text) to anon, authenticated;

-- END OF PAST CLIENT LINKS ACT ON NOTHING -----------------------------------

select public.functions_tidy();
