-- ============================================================================
-- CONTENT LOOP: A TASK FOLLOWS ITS POST (2026-11-10)
-- ============================================================================
-- The user, 2026-11-10: one task is one post; the draft uploaded meets Draft
-- due, the post published meets the Due date; changes a client sends on
-- WhatsApp are recorded on the post; Scheduled stays a person's move; no
-- switch in Settings: a task follows only once it is linked to its post.
--
--   1. `ops_task_links.post_id`: a link to a content set may name one post of
--      it. One live link a post, one post a task. The set's own backlinks
--      (`ops_record_tasks`) list it, with the post's number in the set.
--   2. `ops_link_post(p_task, p_post, p_version)`: links a client's task to a
--      post of that client's set (My Work at Work, Content Review at View;
--      `post-taken`, `has-post`, `other-client`), and brings the task to
--      where the post stands at once.
--   3. `ops_post_follow(p_post, p_note)`: where the post stands names the
--      task's stage: a file in the set AQC review, the set published Client
--      review, the client's changes Revision (Client), approval Approved. A
--      task moves only from Ready to start through Revision (Client), forward
--      along the line, or round the loop (Revision (Internal) to AQC review,
--      Revision (Client) to Client review once the next round is up); On
--      hold, Blocked, Approved and after are a person's. Filed on the task,
--      its owner told; a fault never fails the write that caused it.
--   4. Triggers on `posts` (its file, words or round changed, re-approval
--      asked), `reviews` (a decision made or taken back) and `batches` (the
--      set published) call it.
--   5. `review_record_changes(p_post, p_note)`: the client's changes received
--      on WhatsApp, recorded on the post as the team's (Content Review: Sets
--      at Work, a published set, no decision standing on the round); the
--      client's page reads Changes requested with the note, never the
--      colleague. `review_revert_confirm` takes back either team decision.
--
-- Re-runnable. Rollback: drop the three triggers, the functions in 2, 3 and
-- 5, the column and its indexes; restate `ops_record_tasks` and
-- `review_revert_confirm` as before.

alter table public.ops_task_links add column if not exists post_id uuid
  references public.posts(id) on delete set null;
create unique index if not exists ops_task_links_post_once
  on public.ops_task_links (post_id) where post_id is not null and archived_at is null;
create unique index if not exists ops_task_links_one_post
  on public.ops_task_links (task_id) where post_id is not null and archived_at is null;

/* A post's number in its set, as the console counts it. */
create or replace function public.ops_post_no(p_post uuid)
returns integer language sql stable security definer set search_path = public as $$
  select x.n::integer from (
    select q.id, row_number() over (order by q.position, q.created_at, q.id) as n
      from public.posts q where q.batch_id = (select p.batch_id from public.posts p where p.id = p_post)
  ) x where x.id = p_post
$$;
revoke all on function public.ops_post_no(uuid) from public, anon, authenticated;

/* Where a post stands, as the stage its task belongs at. */
create or replace function public.ops_post_target(p_post uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when d.decision = 'approved' then 'approved'
    when d.decision = 'changes' then 'revision_client'
    when coalesce(b.published, false) then 'client_review'
    when jsonb_array_length(coalesce(p.media, '[]'::jsonb)) > 0 then 'internal_review'
  end
    from public.posts p
    join public.batches b on b.id = p.batch_id
    left join lateral (
      select r.decision from public.reviews r
       where r.post_id = p.id and r.round = p.round and r.undone_at is null
         and (p.review_reset_at is null or r.created_at > p.review_reset_at)
       order by r.created_at desc limit 1) d on true
   where p.id = p_post
$$;
revoke all on function public.ops_post_target(uuid) from public, anon, authenticated;

create or replace function public.ops_post_follow(p_post uuid, p_note text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  k      public.ops_task_links;
  t      public.ops_tasks;
  v_to   text;
  v_from public.ops_workflow_stages;
  v_dest public.ops_workflow_stages;
  v_own  uuid;
  v_me   uuid := (public.ops_me()).id;
begin
  select * into k from public.ops_task_links x
   where x.post_id = p_post and x.archived_at is null limit 1;
  if k.id is null then return; end if;
  v_to := public.ops_post_target(p_post);
  if v_to is null then return; end if;
  select * into t from public.ops_tasks x where x.id = k.task_id for update;
  if t.id is null or t.completed_at is not null or t.cancelled_at is not null or t.archived_at is not null
     or t.stage_key = v_to then
    return;
  end if;
  if t.stage_key not in ('ready', 'in_production', 'internal_review', 'revision_internal',
                         'client_review', 'revision_client') then
    return;
  end if;
  v_from := public.ops_stage(t.workflow_id, t.stage_key);
  v_dest := public.ops_stage(t.workflow_id, v_to);
  if v_from.key is null or v_dest.key is null or coalesce(v_dest.retired, false) then return; end if;
  if not (v_dest.position > v_from.position
          or (t.stage_key = 'revision_internal' and v_to = 'internal_review')
          or (t.stage_key = 'revision_client' and v_to = 'client_review')) then
    return;
  end if;
  update public.ops_tasks set stage_key = v_to, version = version + 1, updated_at = now(),
         blocked_at = null, blocked_category = null
   where id = t.id;
  insert into public.ops_task_events (task_id, event_type, actor_id, actor_email, from_value, to_value, detail)
  values (t.id, 'stage_changed', v_me, null,
          jsonb_build_object('stage_key', t.stage_key), jsonb_build_object('stage_key', v_to),
          jsonb_build_object('note', p_note, 'post_id', p_post, 'content_review', true));
  select a.team_member_id into v_own from public.ops_task_assignees a
   where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null limit 1;
  if v_own is not null and v_own is distinct from v_me then
    perform public.ops_notify(v_own, t.id, 'stage_changed',
      public.ops_serial(t.task_no) || ' · ' || public.ops_title(t),
      'Moved to ' || v_dest.label || ': ' || p_note || '.',
      'stage_changed:' || t.id::text || ':' || v_own::text || ':' || to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MI'));
  end if;
exception when others then
  return;
end $$;
revoke all on function public.ops_post_follow(uuid, text) from public, anon, authenticated;

create or replace function public.ops_link_post(p_task uuid, p_post uuid, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me  public.team_members := public.ops_me();
  v_t   public.ops_tasks;
  v_p   public.posts;
  v_b   public.batches;
  v_l   public.ops_task_links;
  v_lbl text;
begin
  if v_me.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') or not public.allowed('review', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  select * into v_t from public.ops_tasks where id = p_task for update;
  if v_t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> v_t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  select * into v_p from public.posts where id = p_post;
  if v_p.id is null then return jsonb_build_object('error', 'record-not-found'); end if;
  select * into v_b from public.batches where id = v_p.batch_id;
  if v_t.client_id is null or v_b.client_id is distinct from v_t.client_id then
    return jsonb_build_object('error', 'other-client');
  end if;
  if exists (select 1 from public.ops_task_links x where x.task_id = p_task and x.post_id is not null and x.archived_at is null) then
    return jsonb_build_object('error', 'has-post');
  end if;
  if exists (select 1 from public.ops_task_links x where x.post_id = p_post and x.archived_at is null) then
    return jsonb_build_object('error', 'post-taken', 'task',
      (select public.ops_serial(y.task_no) from public.ops_task_links x join public.ops_tasks y on y.id = x.task_id
        where x.post_id = p_post and x.archived_at is null limit 1));
  end if;
  v_lbl := coalesce(nullif(btrim(v_b.title), ''), 'Content set') || ' · Post ' || public.ops_post_no(p_post);
  insert into public.ops_task_links (task_id, kind, label, url, created_by, ref_type, ref_id, post_id)
  values (p_task, 'record', v_lbl,
          (public.ops_ref_of('set', v_b.id))->>'url', v_me.id, 'set', v_b.id, p_post)
  returning * into v_l;
  update public.ops_tasks set version = version + 1, updated_at = now() where id = p_task;
  perform public.ops_ref_file(v_l, 'linked');
  perform public.ops_post_follow(p_post, 'Linked to its post in Content Review');
  return jsonb_build_object('link_id', v_l.id, 'task', public.ops_task_json(p_task));
end $$;
revoke all on function public.ops_link_post(uuid, uuid, integer) from public, anon;
grant execute on function public.ops_link_post(uuid, uuid, integer) to authenticated;

create or replace function public.posts_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.content_version is distinct from old.content_version or new.round is distinct from old.round
     or new.review_reset_at is distinct from old.review_reset_at then
    perform public.ops_post_follow(new.id,
      case when new.review_reset_at is distinct from old.review_reset_at then 'Re-approval requested in Content Review'
           else 'Post updated in Content Review' end);
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.posts_task_follow() from public, anon, authenticated;
create or replace trigger posts_task_follow after update on public.posts
  for each row execute function public.posts_task_follow();

create or replace function public.reviews_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.undone_at is not distinct from old.undone_at then return null; end if;
  perform public.ops_post_follow(new.post_id,
    case when tg_op = 'UPDATE' then 'Decision reverted in Content Review'
         when new.decision = 'approved' and new.source = 'team' then 'Confirmed internally in Content Review'
         when new.decision = 'approved' then 'Approved by the client in Content Review'
         when new.source = 'team' then 'Changes received on WhatsApp'
         else 'Changes requested by the client in Content Review' end);
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.reviews_task_follow() from public, anon, authenticated;
create or replace trigger reviews_task_follow after insert or update on public.reviews
  for each row execute function public.reviews_task_follow();

create or replace function public.batches_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not coalesce(new.published, false) or coalesce(old.published, false) then return null; end if;
  for v in select x.post_id from public.ops_task_links x join public.posts p on p.id = x.post_id
            where p.batch_id = new.id and x.archived_at is null loop
    perform public.ops_post_follow(v, 'Published to the client in Content Review');
  end loop;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.batches_task_follow() from public, anon, authenticated;
create or replace trigger batches_task_follow after update on public.batches
  for each row execute function public.batches_task_follow();

/* The client's changes received on WhatsApp, kept as the team's decision. */
create or replace function public.review_record_changes(p_post uuid, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me       public.team_members;
  v_post   public.posts%rowtype;
  v_pub    boolean;
  v_title  text;
  v_client text;
  v_now    text;
  v_note   text := btrim(coalesce(p_note, ''));
begin
  if not public.allowed('review.sets', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if v_note = '' then return jsonb_build_object('error', 'no-note'); end if;
  if char_length(v_note) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into v_post from public.posts where id = p_post for update;
  if v_post.id is null then return jsonb_build_object('error', 'no-post'); end if;
  select b.published, b.title, c.name into v_pub, v_title, v_client
    from public.batches b join public.clients c on c.id = b.client_id
   where b.id = v_post.batch_id;
  if not coalesce(v_pub, false) then return jsonb_build_object('error', 'not-published'); end if;
  select r.decision into v_now from public.reviews r
   where r.post_id = v_post.id and r.round = v_post.round and r.undone_at is null
     and (v_post.review_reset_at is null or r.created_at > v_post.review_reset_at)
   order by r.created_at desc limit 1;
  if v_now is not null then return jsonb_build_object('error', 'decided', 'decision', v_now); end if;

  insert into public.reviews (post_id, decision, note, reviewer, source)
  values (v_post.id, 'changes', v_note, me.name, 'team');

  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(nullif(auth.jwt() ->> 'email', ''), me.name), 'review.changes', v_client,
          v_title || ' · ' || coalesce(nullif(v_post.platform, ''), 'post') ||
          case when v_post.round > 1 then ' · revision ' || v_post.round else '' end ||
          ' · changes received on WhatsApp');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.review_record_changes(uuid, text) from public, anon;
grant execute on function public.review_record_changes(uuid, text) to authenticated;

/* Takes back the team's own decision on the round on show, approval or
   changes received on WhatsApp; a client's decision stays theirs. */
create or replace function public.review_revert_confirm(p_post uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me       public.team_members;
  v_post   public.posts%rowtype;
  v_rv     public.reviews%rowtype;
  v_title  text;
  v_client text;
begin
  if not public.allowed('review.sets', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into v_post from public.posts where id = p_post for update;
  if v_post.id is null then return jsonb_build_object('error', 'no-post'); end if;
  select r.* into v_rv from public.reviews r
   where r.post_id = v_post.id and r.round = v_post.round and r.undone_at is null
     and (v_post.review_reset_at is null or r.created_at > v_post.review_reset_at)
   order by r.created_at desc limit 1;
  if v_rv.id is null or v_rv.source <> 'team' then
    return jsonb_build_object('error', 'not-confirmed');
  end if;
  update public.reviews set undone_at = now(), undone_by = me.id where id = v_rv.id;

  select b.title, c.name into v_title, v_client
    from public.batches b join public.clients c on c.id = b.client_id
   where b.id = v_post.batch_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(nullif(auth.jwt() ->> 'email', ''), me.name), 'review.unconfirmed', v_client,
          coalesce(v_title, '') || ' · ' || coalesce(nullif(v_post.platform, ''), 'post') ||
          case when v_rv.decision = 'approved' then ' · internal confirmation reverted'
               else ' · changes received on WhatsApp reverted' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.review_revert_confirm(uuid) from public, anon;
grant execute on function public.review_revert_confirm(uuid) to authenticated;

/* The set's backlinks name the post a task follows. */
create or replace function public.ops_record_tasks(p_type text, p_ref uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null then return '[]'::jsonb; end if;
  if p_type = 'campaign' and not public.allowed('campaigns', 'view') then return '[]'::jsonb; end if;
  if p_type = 'set' and not public.allowed('review', 'view') then return '[]'::jsonb; end if;
  if p_type is null or p_type not in ('campaign', 'set') then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(x.j order by x.done, x.due nulls last, x.no)
      from (
        select distinct on (t.id)
               t.id, t.task_no as no,
               (t.completed_at is not null or t.cancelled_at is not null) as done,
               t.current_final_due_at as due,
               jsonb_build_object(
                 'id', t.id,
                 'serial', public.ops_serial(t.task_no),
                 'title', public.ops_title(t),
                 'stage_key', t.stage_key,
                 'stage', coalesce(s.label, initcap(replace(t.stage_key, '_', ' '))),
                 'stage_group', s.stage_group,
                 'owner', (select m.name from public.ops_task_assignees a
                             join public.team_members m on m.id = a.team_member_id
                            where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null
                            limit 1),
                 'final_due_at', t.current_final_due_at,
                 'completed_at', t.completed_at,
                 'cancelled_at', t.cancelled_at,
                 'link_id', k.id,
                 'post_id', k.post_id,
                 'post_no', case when k.post_id is not null then public.ops_post_no(k.post_id) end) as j
          from public.ops_task_links k
          join public.ops_tasks t on t.id = k.task_id
          left join public.ops_workflow_stages s
                 on s.workflow_id = t.workflow_id and s.key = t.stage_key
         where k.ref_type = p_type and k.ref_id = p_ref and k.archived_at is null
           and public.ops_may_see_task(t.id)
         order by t.id, (k.post_id is null), k.created_at
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.ops_record_tasks(text, uuid) from public, anon;
grant execute on function public.ops_record_tasks(text, uuid) to authenticated;

select public.functions_tidy();
