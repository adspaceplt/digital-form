-- ===========================================================================
-- REVIEW DECISIONS ASK THE PASSCODE AS THE PAGE DOES — submit_review and
-- submit_review_seen count a wrong passcode and keep a locked caller out
-- (2026-10-18)
-- ===========================================================================
-- WHY (audit 2026-10-18, item 13): both compared `c.passcode = p_passcode`
-- themselves, so a guesser locked out of `get_review_feed` (five wrong
-- tries, #618) could go on guessing through Approve, uncounted.
--
-- WHAT IT CHANGES
--   * Both ask `link_passcode('review', …)`, as `get_review_feed` does: a
--     wrong passcode is counted against its caller and answers `not_found`
--     as before; a locked caller is answered `locked` with its minutes
--     (`link_locked`), which the page reads as Not sent.
--   * Nothing else in either function moves.
--
-- ORDER: this file; the page needs nothing. Safe to run twice.
-- Rollback: HIDDEN FROM CONTENT REVIEW's `submit_review` and APPROVAL AS
-- SEEN's `submit_review_seen`.
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

create or replace function public.submit_review_seen(
  p_token      text,
  p_post_id    uuid,
  p_decision   text,
  p_version    integer,
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
  v_post   public.posts%rowtype;
  v_res    jsonb;
  v_stored text;
begin
  -- The link first, as submit_review asks it, so a post id alone says nothing;
  -- the passcode through link_passcode, counted per caller (audit
  -- 2026-10-18, item 13).
  select c.passcode into v_stored
    from public.posts p
    join public.batches b on b.id = p.batch_id
    join public.clients c on c.id = b.client_id
   where p.id = p_post_id and b.published
     and c.access_token = p_token and c.active and not c.review_hidden;
  if not found then
    return jsonb_build_object('error', 'not_found');
  end if;
  case public.link_passcode('review', p_token, v_stored, p_passcode)
    when 'locked' then return public.link_locked('review', p_token);
    when 'wrong' then return jsonb_build_object('error', 'not_found');
    else null;
  end case;
  select * into v_post from public.posts where id = p_post_id for update;
  if p_version is null or p_version is distinct from v_post.content_version then
    return jsonb_build_object('error', 'changed', 'version', v_post.content_version);
  end if;
  v_res := public.submit_review(p_token, p_post_id, p_decision, p_note, p_reviewer,
                                p_passcode, p_caption, p_caption_zh);
  if coalesce((v_res ->> 'ok')::boolean, false) then
    update public.reviews r
       set seen = jsonb_build_object('version', v_post.content_version, 'round', v_post.round,
                                     'title', v_post.title, 'caption', v_post.caption,
                                     'caption_zh', v_post.caption_zh, 'media', v_post.media)
     where r.post_id = p_post_id and r.created_at = now() and r.seen is null;
  end if;
  return v_res;
end $$;

revoke all on function public.submit_review_seen(text, uuid, text, integer, text, text, text, text, text) from public;
grant execute on function public.submit_review_seen(text, uuid, text, integer, text, text, text, text, text) to anon, authenticated;
-- END OF REVIEW DECISIONS ASK THE PASSCODE AS THE PAGE DOES -----------------

select public.functions_tidy();
