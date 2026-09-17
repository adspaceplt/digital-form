-- 2026-09-21  The activity record holds what clients and creators did.
--
-- The portal's account of who decided what held one side of every
-- conversation. A client approving a post wrote to `reviews` and nothing else;
-- a client confirming a set of creators wrote to `campaign_confirmations`; a
-- creator handing work in and rating a finished booking wrote nothing at all.
-- None of those reach the Activity record, which is the screen anybody would
-- open to answer "who approved this, and when".
--
-- Five security-definer functions, redefined to log what they already do. No
-- table, column, policy or permission changes, and no behaviour changes for
-- anyone: each one writes one extra row to `activity_log` and returns exactly
-- what it returned before. Safe to run twice — `create or replace` is the
-- whole file.
--
-- `save_selection` is deliberately NOT among them: it fires on every tick as
-- an autosave, and a record full of half-made selections is one nobody can
-- read. `confirm_selection` is the commitment and the one that carries a name.
--
-- Rollback: re-run this repository's `supabase/schema.sql` at the commit
-- before this migration, or drop the `insert into public.activity_log`
-- statement from each function below. Nothing else has to be undone; the rows
-- already written are ordinary activity rows.

create or replace function public.submit_review(
  p_token    text,
  p_post_id  uuid,
  p_decision text,
  p_note     text default null,
  p_reviewer text default null,
  p_passcode text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client_id uuid;
  v_ok        boolean;
begin
  if p_decision not in ('approved', 'changes') then
    return jsonb_build_object('error', 'bad_decision');
  end if;

  if p_decision = 'changes' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note_required');
  end if;

  select c.id into v_client_id
  from public.clients c
  where c.access_token = p_token
    and c.active
    and (c.passcode is null or c.passcode = p_passcode);

  if v_client_id is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  -- the post must belong to a published batch of this client
  select true into v_ok
  from public.posts p
  join public.batches b on b.id = p.batch_id
  where p.id = p_post_id and b.client_id = v_client_id and b.published;

  if v_ok is not true then
    return jsonb_build_object('error', 'not_found');
  end if;

  insert into public.reviews (post_id, decision, note, reviewer)
  values (p_post_id, p_decision, nullif(btrim(p_note), ''), nullif(btrim(p_reviewer), ''));

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
         coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), '')
    from public.posts p
    join public.batches b on b.id = p.batch_id
    join public.clients c on c.id = b.client_id
   where p.id = p_post_id;

  return jsonb_build_object('ok', true);
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
  if c.passcode is not null and c.passcode <> ''
     and (p_passcode is null or p_passcode <> c.passcode) then
    return jsonb_build_object('error', 'passcode');
  end if;
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;

  insert into campaign_confirmations (campaign_id, kind, person, source)
  values (c.id, 'client', trim(p_person), 'portal');

  /* Logged here and not in `save_selection`: that one fires on every tick as
     an autosave, and a record full of half-made selections is a record nobody
     can read. This is the commitment, and it is the one that carries a name. */
  insert into public.activity_log (actor, action, subject, detail)
  values (trim(p_person), 'campaign.confirmed', c.title,
          (select count(*)::text || ' creator' || case when count(*) = 1 then '' else 's' end
             from campaign_options
            where campaign_id = c.id and state = 'shortlisted') || ' confirmed');

  return jsonb_build_object('ok', true);
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
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'files', n);
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

  insert into public.activity_log (actor, action, subject, detail)
  select cr.name, 'campaign.rated', c.title,
         coalesce(p_stars::text || ' of 5', 'rating cleared')
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'rating', p_stars);
end $$;

create or replace function public.portal_withdraw(p_id uuid, p_undo boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  n int;
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  update public.client_requests
     set withdrawn_at = case when p_undo then null else now() end
   where id = p_id and client_id in (select public.portal_clients())
     and state = 'requested'
     and (withdrawn_at is null) = (not p_undo);
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error', 'not-found'); end if;

  insert into public.activity_log (actor, action, subject, detail)
  select who, case when p_undo then 'request.reinstated' else 'request.withdrawn' end,
         c.name, r.kind
    from public.client_requests r
    join public.clients c on c.id = r.client_id
   where r.id = p_id;

  return jsonb_build_object('ok', true);
end $$;
