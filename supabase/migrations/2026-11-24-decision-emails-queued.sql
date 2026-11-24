-- ===========================================================================
-- DECISION EMAILS QUEUED (2026-11-24)
-- ===========================================================================
-- WHY: the code review of 2026-11-24 (release A2). Keep in talent pool and
-- Not proceed emailed the candidate from a 30-second timer in the
-- colleague's tab: a tab shut in those seconds sent nothing. The Google
-- Meet of a confirmed interview was removed before the decision was asked,
-- so a refused decision left the interview with no meeting.
--
-- WHAT CHANGED
--   * `hiring_candidates.outcome_mail_due`: `hiring_outcome_mail_queue(p_id)`
--     (the part or the Owner) marks the decision's email Queued, due 30
--     seconds on, for Keep in talent pool and Not proceed whose email is
--     not already sent; Reopen (Undo) and a new decision clear it, so it is
--     never sent.
--   * `hiring_outcome_mail_claim()` and `hiring_outcome_mail_close(id,
--     status, error)`, the service role's: hiring-mail's drain claims each
--     due email once (Sending) and closes it as `hiring_outcome_mail_done`
--     files it.
--   * `hiring_outcome_mail_kick()`, every minute by pg_cron
--     (`hiring-outcome-mail`): wakes the drain only while one is due.
--   * `hiring_decide` answers `meets`, the interviews it cancelled that
--     hold a Google Meet; `hiring_interview_meet_prepare` answers such an
--     interview with no time, so meet-create removes its Meet and books
--     none.
--
-- ORDER: this file (connector), then hiring-mail, then the pages. An old
-- page still times its own send, which the database answers as before
-- (its prepare ignores the queue); a new page before this file reads its
-- queue call refused and says to use Email candidate. Safe to run twice.
-- ROLLBACK: unschedule `hiring-outcome-mail`; restate `hiring_decide` and
-- `hiring_interview_meet_prepare` from their last definitions before this
-- banner; the new functions and the column may stay.
-- ===========================================================================

alter table public.hiring_candidates add column if not exists outcome_mail_due timestamptz;

create or replace function public.hiring_decide(p_id uuid, p_outcome text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  v_back text;
  v_meets uuid[];
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_outcome, '') not in ('proceed', 'pool', 'not', 'reopen') then return jsonb_build_object('error', 'bad-outcome'); end if;
  if char_length(coalesce(p_note, '')) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage = 'hired' then return jsonb_build_object('error', 'closed'); end if;
  if p_outcome = 'reopen' then
    if c.outcome is null then return jsonb_build_object('ok', true, 'same', true); end if;
    v_back := case when exists (select 1 from public.hiring_interviews i where i.candidate_id = c.id and i.state = 'confirmed') then 'interview'
      when exists (select 1 from public.hiring_interviews i where i.candidate_id = c.id and i.state in ('invited', 'picked', 'none')) then 'invited'
      else 'new' end;
    update public.hiring_candidates set stage = v_back, outcome = null, outcome_note = null, outcome_by = null, outcome_at = null,
      pool_consent = null, pool_until = null, outcome_mail = null, outcome_mail_at = null, outcome_mail_due = null,
      decide_by = null, decide_note = null, decide_soon_at = null, decide_due_at = null, decide_moved_at = null, last_step_at = now(), updated_at = now()
     where id = c.id;
    update public.hiring_docs set state = 'withdrawn', updated_at = now() where candidate_id = c.id and state = 'sent';
    perform public.hiring_log(c.id, 'candidate.decided', 'Reopened');
    return jsonb_build_object('ok', true, 'was', c.outcome, 'note', c.outcome_note);
  end if;
  if c.outcome = p_outcome then return jsonb_build_object('ok', true, 'same', true); end if;
  update public.hiring_candidates set
    stage = case p_outcome when 'proceed' then 'offer' when 'pool' then 'pool' else 'closed' end,
    outcome = p_outcome, outcome_note = nullif(btrim(coalesce(p_note, '')), ''), outcome_by = me.id, outcome_at = now(),
    pool_consent = case when p_outcome = 'pool' then 'asked' end, pool_until = null, outcome_mail = null, outcome_mail_at = null, outcome_mail_due = null,
    decide_by = null, decide_note = null, decide_soon_at = null, decide_due_at = null, decide_moved_at = null,
    last_step_at = now(), updated_at = now()
   where id = c.id;
  -- The interviews it cancels whose Google Meet the page then removes.
  with gone as (
    update public.hiring_interviews set state = 'cancelled', updated_at = now()
     where candidate_id = c.id
       and (state in ('invited', 'none')
            or (p_outcome <> 'proceed' and (state = 'picked' or (state = 'confirmed' and held_at is null))))
    returning id, meeting_event_id)
  select coalesce(array_agg(g.id) filter (where g.meeting_event_id is not null), '{}') into v_meets from gone g;
  update public.hiring_docs set state = 'withdrawn', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and state = 'sent';
  perform public.hiring_log(c.id, 'candidate.decided',
    case p_outcome when 'proceed' then 'Proceed' when 'pool' then 'Keep in talent pool' else 'Do not proceed' end);
  return jsonb_build_object('ok', true, 'was', c.outcome, 'email', p_outcome in ('pool', 'not'), 'meets', to_jsonb(v_meets));
end $$;
grant execute on function public.hiring_decide(uuid, text, text) to authenticated;

create or replace function public.hiring_interview_meet_prepare(p_interview uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare i public.hiring_interviews; c public.hiring_candidates; v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  -- A confirmed interview the decision cancelled keeps its Google Meet for
  -- the page to remove: answered with no time, so only a delete proceeds.
  if not (i.state = 'confirmed' or (i.state = 'cancelled' and i.meeting_event_id is not null))
     or i.mode <> 'online' or i.picked is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id;
  return jsonb_build_object('id', i.id, 'meeting_at', case when i.state = 'confirmed' then i.slots[i.picked] end, 'meeting_minutes', i.minutes,
    'meeting_event_id', i.meeting_event_id, 'meeting_link', i.meeting_link, 'position', c.position);
end $$;
grant execute on function public.hiring_interview_meet_prepare(uuid) to authenticated;

/* The decision's email, queued for the drain once Undo's 30 seconds pass. */
create or replace function public.hiring_outcome_mail_queue(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_role text := public.hiring_role(p_id); c public.hiring_candidates;
begin
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.outcome is null or c.outcome not in ('pool', 'not') then return jsonb_build_object('error', 'no-email'); end if;
  if c.outcome_mail in ('sent', 'sending') then return jsonb_build_object('ok', true, 'same', true); end if;
  update public.hiring_candidates set outcome_mail = 'queued', outcome_mail_at = null,
    outcome_mail_due = now() + interval '30 seconds', updated_at = now() where id = c.id;
  return jsonb_build_object('ok', true, 'due', now() + interval '30 seconds');
end $$;
revoke all on function public.hiring_outcome_mail_queue(uuid) from public, anon;
grant execute on function public.hiring_outcome_mail_queue(uuid) to authenticated;

/* hiring-mail's drain (the service role's): each due decision email,
   claimed once, with what its words need. */
create or replace function public.hiring_outcome_mail_claim()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v jsonb;
begin
  with due as (
    select c.id from public.hiring_candidates c
     where c.outcome_mail = 'queued' and c.outcome_mail_due <= now() and c.outcome in ('pool', 'not')
       and c.removed_at is null and c.link_key is not null
     order by c.outcome_mail_due limit 20 for update skip locked),
  took as (
    update public.hiring_candidates c set outcome_mail = 'sending', outcome_mail_due = null from due where c.id = due.id
    returning c.id, c.outcome, c.email, c.name, c.position, c.link_key)
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.outcome, 'to', t.email, 'name', t.name,
      'position', t.position, 'key', t.link_key,
      'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12),
      'system', true)), '[]'::jsonb) into v
    from took t;
  return v;
end $$;
revoke all on function public.hiring_outcome_mail_claim() from public, anon, authenticated;
grant execute on function public.hiring_outcome_mail_claim() to service_role;

/* The drain's outcome, filed as hiring_outcome_mail_done files a send by hand. */
create or replace function public.hiring_outcome_mail_close(p_id uuid, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
begin
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-request'); end if;
  update public.hiring_candidates set outcome_mail = p_status, outcome_mail_at = now(), updated_at = now()
   where id = p_id and outcome_mail = 'sending';
  if not found then return jsonb_build_object('error', 'not-claimed'); end if;
  perform public.hiring_log(p_id, 'candidate.email', 'Decision' || case p_status when 'sent' then ' emailed to the candidate.'
    when 'unknown' then ' sent to the candidate, but its delivery could not be verified.'
    else ' could not be emailed to the candidate.' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hiring_outcome_mail_close(uuid, text, text) from public, anon, authenticated;
grant execute on function public.hiring_outcome_mail_close(uuid, text, text) to service_role;

/* Every minute: the drain is woken only while a decision email is due. */
create or replace function public.hiring_outcome_mail_kick()
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.hiring_candidates c where c.outcome_mail = 'queued' and c.outcome_mail_due <= now()) then
    perform public.hiring_mail_kick();
  end if;
end $$;
revoke all on function public.hiring_outcome_mail_kick() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: a queued decision email waits for the next wake.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'hiring-outcome-mail';
  perform cron.schedule('hiring-outcome-mail', '* * * * *', 'select public.hiring_outcome_mail_kick()');
end $$;

-- END OF DECISION EMAILS QUEUED ---------------------------------------------

select public.functions_tidy();
