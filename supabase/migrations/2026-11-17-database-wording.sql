-- ===========================================================================
-- DATABASE WORDING — five lines the database puts in front of a person read
-- as DESIGN.md §6 asks (2026-11-17)
-- ===========================================================================
-- WHY (the user, 2026-11-17: the whole repository held to §6, part 3 of the
-- tone check): reviewers who did not write the words read the database's
-- live lines against §6.
--
-- WHAT CHANGED (words only; no key, tag, argument or refusal code moves)
--   * `perf_grade_word`: grades D and E read Needs support and Improvement
--     plan, §6's Performance vocabulary (they read Needs Guidance and
--     Performance Review on every review screen).
--   * `letter_set_void`: one service line reverted reads in the singular.
--   * `campaign_options_push`: a creator cleared to post is told "Draft
--     approved for posting".
--   * `clients_owner_guard`: the refusal says who can change the Person in
--     charge (its hint, owner-change, unchanged).
--   * `ops_request_due_change`: the extension notice dates the day as every
--     notice does (`register_day`, 5 Sept 2026, never 05 Sep) and names "A
--     colleague" where the asker has no name.
--
-- ORDER: this file (connector), then the pages (none change). Safe to run
-- twice.
--
-- ROLLBACK: each function from its last section before this one in
-- schema.sql.
-- ===========================================================================

-- DATABASE WORDING -----------------------------------------------------------

create or replace function public.perf_grade_word(p_grade text)
returns text language sql immutable as $$
  select case p_grade when 'A' then 'Distinction' when 'B' then 'Strong' when 'C' then 'Baseline'
                      when 'D' then 'Needs support' when 'E' then 'Improvement plan' end
$$;

create or replace function public.letter_set_void(p_doc uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.client_documents%rowtype;
  cl  public.clients%rowtype;
  ids uuid[];
begin
  -- Voiding is the Clients section's Manage level, the same authority that
  -- deletes a letter: one level of trust, one switch.
  if not public.allowed('clients.documents', 'manage') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('ok', true, 'repeat', true); end if;
  if d.verified_at is null then return jsonb_build_object('error', 'not-verified'); end if;

  ids := public.letter_sole_services(p_doc);

  update public.client_documents
     set voided_at = now(), voided_by = who, void_reason = btrim(p_reason)
   where id = p_doc;
  update public.client_services set state = 'quoted' where id = any(ids);

  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.voided', cl.name,
          d.number || ' · ' || btrim(p_reason) || ' · ' ||
          coalesce(array_length(ids, 1), 0) || case when coalesce(array_length(ids, 1), 0) = 1 then ' service line reverted' else ' service lines reverted' end);
  return jsonb_build_object('ok', true, 'reverted', coalesce(array_length(ids, 1), 0));
end $$;
grant execute on function public.letter_set_void(uuid, text) to authenticated;

create or replace function public.campaign_options_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title    text;
  v_title_zh text;
  v_token    text;
  v_creator  text;
  v_msg      jsonb;
begin
  if new.state is not distinct from old.state then return new; end if;
  select coalesce(nullif(btrim(c.title), ''), 'Your campaign'),
         coalesce(nullif(btrim(c.title_zh), ''), nullif(btrim(c.title), ''), '您的活动'),
         c.access_token
    into v_title, v_title_zh, v_token from public.campaigns c where c.id = new.campaign_id;
  select coalesce(nullif(btrim(k.name), ''), 'A creator') into v_creator
    from public.creators k where k.id = new.creator_id;
  v_creator := coalesce(v_creator, 'A creator');

  if v_token is not null and ((new.state = 'reviewing' and old.state = 'submitted')
                           or (new.state = 'posted' and old.state = 'scheduled')) then
    v_msg := case new.state
      when 'reviewing' then jsonb_build_object(
        'en', jsonb_build_object('title', 'Draft ready for review', 'body', v_creator || ' · ' || v_title),
        'zh', jsonb_build_object('title', '初稿待审阅', 'body', v_creator || ' · ' || v_title_zh))
      else jsonb_build_object(
        'en', jsonb_build_object('title', 'Post is live', 'body', v_creator || ' · ' || v_title),
        'zh', jsonb_build_object('title', '帖子已发布', 'body', v_creator || ' · ' || v_title_zh))
    end;
    perform public.push_queue('client', new.campaign_id, v_msg,
      '/creators/?k=' || v_token, 'option-' || new.id::text);
  end if;

  if (new.state = 'confirmed' and old.state in ('option', 'shortlisted', 'backup'))
     or new.state = 'changes'
     or (new.state = 'scheduled' and old.state in ('submitted', 'reviewing', 'changes')) then
    v_msg := case new.state
      when 'confirmed' then jsonb_build_object(
        'en', jsonb_build_object('title', 'Booking confirmed', 'body', v_title),
        'zh', jsonb_build_object('title', '合作已确认', 'body', v_title_zh))
      when 'changes' then jsonb_build_object(
        'en', jsonb_build_object('title', 'Changes requested', 'body', v_title),
        'zh', jsonb_build_object('title', '需要修改', 'body', v_title_zh))
      else jsonb_build_object(
        'en', jsonb_build_object('title', 'Draft approved for posting', 'body', v_title),
        'zh', jsonb_build_object('title', '已通过，可以发布', 'body', v_title_zh))
    end;
    perform public.push_queue('creator', new.creator_id, v_msg,
      '/creator/#b=' || new.id::text, 'option-' || new.id::text);
  end if;
  return new;
exception when others then
  return new;
end $$;

create or replace function public.clients_owner_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  if nullif(btrim(coalesce(old.owner, '')), '') is not null
     and coalesce(btrim(new.owner), '') is distinct from btrim(old.owner)
     and (select t.id from public.team_members t
           where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1) is not null
     and not public.allowed('clients', 'manage') and not public.allowed('team', 'manage') then
    raise exception 'Only a colleague at Clients Full Access can change the Person in charge. Please ask one.' using errcode = '42501', hint = 'owner-change';
  end if;
  return new;
end $$;
revoke all on function public.clients_owner_guard() from public, anon, authenticated;

create or replace function public.ops_request_due_change(
  p_task uuid, p_kind text, p_value timestamptz, p_reason text,
  p_note text default null, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  t     public.ops_tasks;
  who   uuid;
  was   timestamptz;
  v_id  uuid;
  nm    text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_reason, '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  if p_kind not in ('first_draft', 'final') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_value is null then return jsonb_build_object('error', 'no-date'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;

  /* Refused before an ask is raised as well as before a move is made: an ask
     nobody could approve without breaking the plan is one to turn away at the
     door, with the word the move itself would have used. */
  if not public.ops_due_order_ok(
       case when p_kind = 'first_draft' then p_value else t.current_first_draft_due_at end,
       case when p_kind = 'final'       then p_value else t.current_final_due_at end) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  who := public.ops_due_decider(p_task, p_kind);
  /* Nobody to ask — the team's own first draft milestone, or a task whose
     creator is the person asking — so the move is theirs to make and the
     round would be a form with one name on both ends. */
  /* An admin moves any date directly: the round protects the person who set
     the date from somebody else, and an admin is the one who may overwrite
     anybody's. The move still files its event and keeps the original. */
  if who is null or who = m.id or public.ops_granted('ops.override', 'work') then
    return public.ops_change_due_date(p_task, p_kind, p_value, p_reason, p_note, p_version);
  end if;

  was := case when p_kind = 'final' then t.current_final_due_at
              else t.current_first_draft_due_at end;

  insert into public.ops_due_requests
    (task_id, kind, was_at, wants_at, reason, note, asked_by, decider_id)
  values (p_task, p_kind, was, p_value, p_reason, nullif(btrim(p_note), ''), m.id, who)
  on conflict (task_id, kind) where state = 'asked' do nothing
  returning id into v_id;

  /* The same press twice is the same ask. The open one is handed back so the
     page can say it is already with somebody. */
  if v_id is null then
    select id into v_id from public.ops_due_requests
      where task_id = p_task and kind = p_kind and state = 'asked';
    return jsonb_build_object('ok', true, 'repeat', true, 'request', v_id,
                              'task', public.ops_task_json(p_task));
  end if;

  select name into nm from public.team_members where id = m.id;
  perform public.ops_notify(who, p_task, 'due_requested',
    'Extension requested',
    coalesce(nm, 'A colleague') || ' asked to move ' ||
      case when p_kind = 'final' then 'the due date' else 'the first draft date' end ||
      ' to ' || public.register_day((timezone('Asia/Kuala_Lumpur', p_value))::date),
    'due_req:' || v_id::text);

  perform public.ops_log(p_task, 'due_requested',
    jsonb_build_object('kind', p_kind, 'value', was),
    jsonb_build_object('kind', p_kind, 'value', p_value),
    jsonb_build_object('reason', p_reason, 'note', p_note, 'request', v_id));

  return jsonb_build_object('ok', true, 'request', v_id, 'asked', true,
                            'task', public.ops_task_json(p_task));
end $$;
grant execute on function public.ops_request_due_change(uuid, text, timestamptz, text, text, integer) to authenticated;

-- END OF DATABASE WORDING ---------------------------------------------------

select public.functions_tidy();
