-- ===========================================================================
-- INTERVIEW CANCELLED MOVES THE STAGE (2026-11-26)
-- ===========================================================================
-- WHY: the user, 2026-11-26: "hiring tab, interview stage, when cancelled
-- interview, it still stucked at interview" (F7). `hiring_interview_cancel`
-- cancelled the interview and left the candidate at Interview; Send new
-- times on a confirmed interview likewise left them there, since
-- `hiring_invite` moved only New, Pool and Invited.
--
-- WHAT IT CHANGES
--   * `hiring_interview_stage(candidate, else)`: the one derivation of where
--     a candidate's interviews leave them (Interview while one is
--     confirmed, Invited while one waits on the candidate, else the stage
--     given). Internal.
--   * `hiring_interview_cancel`: a candidate at Invited or Interview with no
--     decision moves to where their interviews now leave them: Interview
--     while another confirmed one stands, Invited while another waits,
--     else New.
--   * `hiring_invite` (Send new times): New, Pool, Invited and Interview
--     move by the same derivation, so new times after a confirmed
--     interview read Invited (Interview while a held round stands).
--   * `hiring_decide` Reopen: the same derivation in place of its own copy.
--   * `careers_read`: a candidate back at New after a cancellation still
--     reads Interview cancelled on their page, as at Invited or Interview.
--   Every refusal of each function stands.
--
-- ORDER: this file alone (no page reads a new field). Safe to run twice.
-- Holds no drop or delete.
-- ROLLBACK: run each function's last definition before this band again;
-- the helper may stay. A candidate this file moved stays where it moved.
-- ===========================================================================

-- INTERVIEW CANCELLED MOVES THE STAGE ------------------------------------------

/* Where a candidate's interviews leave them: Interview while one is
   confirmed (held or not), Invited while one waits on the candidate (times
   offered, a time chosen, other times asked for), else p_else. The one
   derivation a cancel, new times and a reopened decision share. */
create or replace function public.hiring_interview_stage(p_candidate uuid, p_else text)
returns text language sql stable set search_path = public as $$
  select case
    when exists (select 1 from public.hiring_interviews i where i.candidate_id = p_candidate and i.state = 'confirmed') then 'interview'
    when exists (select 1 from public.hiring_interviews i where i.candidate_id = p_candidate and i.state in ('invited', 'picked', 'none')) then 'invited'
    else p_else end
$$;
revoke all on function public.hiring_interview_stage(uuid, text) from public, anon, authenticated;

create or replace function public.hiring_interview_cancel(p_interview uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare i public.hiring_interviews; v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if i.state in ('cancelled', 'replaced') then return jsonb_build_object('ok', true, 'same', true); end if;
  if i.held_at is not null then return jsonb_build_object('error', 'held'); end if;
  update public.hiring_interviews set state = 'cancelled', updated_at = now() where id = i.id;
  -- The candidate stands where their interviews now leave them, never at
  -- Interview with none (INTERVIEW CANCELLED MOVES THE STAGE, 2026-11-26).
  update public.hiring_candidates c set stage = public.hiring_interview_stage(c.id, 'new'), last_step_at = now(), updated_at = now()
   where c.id = i.candidate_id and c.stage in ('invited', 'interview') and c.outcome is null;
  perform public.hiring_log(i.candidate_id, 'candidate.interview', 'Interview cancelled');
  return jsonb_build_object('ok', true, 'event', i.meeting_event_id, 'had_meet', i.meeting_event_id is not null);
end $$;
grant execute on function public.hiring_interview_cancel(uuid) to authenticated;

create or replace function public.hiring_invite(p_id uuid, p_slots timestamptz[], p_minutes int, p_mode text, p_note text, p_idem text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_days int := coalesce(public.app_setting('hiring_invite_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 3);
  v_slots timestamptz[];
  v_round int;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_idem, '') !~ '^[A-Za-z0-9-]{8,64}$' then return jsonb_build_object('error', 'bad-request'); end if;
  perform pg_advisory_xact_lock(hashtext('hiring_invite:' || p_idem));
  select * into i from public.hiring_interviews where idem = p_idem;
  if i.id is not null then return jsonb_build_object('ok', true, 'id', i.id, 'again', true); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage in ('hired', 'closed') then return jsonb_build_object('error', 'closed'); end if;
  select array_agg(distinct s order by s) into v_slots from unnest(coalesce(p_slots, '{}')) s where s is not null;
  if v_slots is null or cardinality(v_slots) < 1 or cardinality(v_slots) > 3 then return jsonb_build_object('error', 'bad-slots'); end if;
  if v_slots[1] < now() + interval '1 hour' then return jsonb_build_object('error', 'slot-past'); end if;
  if v_slots[cardinality(v_slots)] > now() + interval '60 days' then return jsonb_build_object('error', 'slot-far'); end if;
  if (v_slots[cardinality(v_slots)] at time zone 'Asia/Kuala_Lumpur')::date - (v_slots[1] at time zone 'Asia/Kuala_Lumpur')::date >= v_days then
    return jsonb_build_object('error', 'slot-window', 'days', v_days);
  end if;
  if coalesce(p_minutes, 0) not in (30, 45, 60, 90) then return jsonb_build_object('error', 'bad-minutes'); end if;
  if coalesce(p_mode, '') not in ('online', 'office') then return jsonb_build_object('error', 'bad-mode'); end if;
  if char_length(coalesce(p_note, '')) > 500 then return jsonb_build_object('error', 'too-long'); end if;
  update public.hiring_interviews set state = 'replaced', updated_at = now()
   where candidate_id = c.id and state in ('invited', 'picked', 'none');
  /* New times cancel a confirmed interview not yet held (the page takes its
     Meet off and tells the candidate first; 2026-11-20). */
  update public.hiring_interviews set state = 'cancelled', updated_at = now()
   where candidate_id = c.id and state = 'confirmed' and held_at is null;
  select coalesce(max(round), 0) + 1 into v_round from public.hiring_interviews where candidate_id = c.id and state <> 'replaced';
  insert into public.hiring_interviews (candidate_id, round, slots, minutes, mode, note, idem, invited_by)
  values (c.id, least(v_round, 20), v_slots, p_minutes, p_mode, nullif(btrim(coalesce(p_note, '')), ''), p_idem, me.id)
  returning * into i;
  -- Where its interviews now leave it: Invited, or Interview while one
  -- confirmed stands (a held round); a confirmed one just cancelled no
  -- longer holds it at Interview (2026-11-26).
  update public.hiring_candidates set stage = case when stage in ('new', 'pool', 'invited', 'interview') then public.hiring_interview_stage(id, 'invited') else stage end,
    last_step_at = now(), updated_at = now() where id = c.id;
  perform public.hiring_log(c.id, 'candidate.invited', cardinality(v_slots) || case when cardinality(v_slots) = 1 then ' time' else ' times' end
    || ' · ' || case p_mode when 'online' then 'Google Meet' else 'At the office' end || ' · ' || p_minutes || ' minutes');
  return jsonb_build_object('ok', true, 'id', i.id);
end $$;
grant execute on function public.hiring_invite(uuid, timestamptz[], int, text, text, text) to authenticated;

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
    v_back := public.hiring_interview_stage(c.id, 'new');
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

create or replace function public.careers_read(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_contact text := public.mail_sender('careers')->>'reply_to';
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_state text;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found', 'contact', v_contact); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null;
  if c.id is null then return jsonb_build_object('error', 'not_found', 'contact', v_contact); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() and not (c.stage = 'pool' and c.pool_consent = 'yes') then
    return jsonb_build_object('error', 'expired', 'contact', v_contact);
  end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state <> 'replaced'
   order by invited_at desc limit 1;
  v_state := case when i.id is null then null else public.hiring_interview_state(i) end;
  return jsonb_build_object('ok', true, 'contact', v_contact, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage = 'new' or (c.stage = 'pool' and c.outcome is null) then 'received' else c.stage end, 'received_at', c.created_at,
    'pool_declined', case when c.outcome = 'pool' and c.pool_consent = 'no' then true end,
    'pool', case when c.stage = 'pool' and c.outcome = 'pool' then jsonb_strip_nulls(jsonb_build_object('consent', c.pool_consent,
      'until', c.pool_until, 'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12))) end,
    'interview', case when i.id is null or c.stage in ('pool', 'closed') then null
      /* Cancelled: the state alone, never its time or link (2026-11-20). */
      when i.state = 'cancelled' then case when c.stage in ('new', 'invited', 'interview') and c.outcome is null
        then jsonb_build_object('state', 'cancelled') end
      /* A time chosen, not yet confirmed: the time, its length and online or
         at the office alone, never the note or a link (2026-11-22). */
      when v_state = 'picked' then jsonb_strip_nulls(jsonb_build_object('state', v_state, 'minutes', i.minutes, 'mode', i.mode,
        'at', i.slots[i.picked]))
      else jsonb_strip_nulls(jsonb_build_object(
      'state', v_state, 'slots', case when v_state = 'invited' then to_jsonb(i.slots) end, 'minutes', i.minutes,
      'mode', i.mode, 'note', i.note, 'at', case when i.picked is not null then i.slots[i.picked] end,
      'reply_by', case when v_state = 'invited' then i.reply_by end,
      'link', case when i.state = 'confirmed' and i.held_at is null then i.meeting_link end,
      /* Moved by the team (2026-11-22): the time it held before, while the
         interview is confirmed and not yet held. */
      'was', case when i.state = 'confirmed' and i.held_at is null then i.moved_from end,
      'held', case when i.held_at is not null then true end,
      'decide_by', case when i.held_at is not null and c.outcome is null then c.decide_by end,
      /* Past it with no decision: the careers mailbox to contact (2026-11-20). */
      'contact', case when i.held_at is not null and c.outcome is null and c.decide_by <= now() then v_contact end)) end,
    'docs', case when c.stage in ('offer', 'hired') then coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', d.id, 'kind', d.kind,
        'serial', d.serial, 'state', case when d.state = 'sent' and d.reply_by <= now() then 'expired' else d.state end,
        'sent_at', d.sent_at, 'reply_by', d.reply_by, 'signed_at', d.signed_at)) order by d.sent_at)
      from public.hiring_docs d where d.candidate_id = c.id and d.state in ('sent', 'signed', 'confirmed', 'declined')), '[]'::jsonb) end);
end $$;
revoke all on function public.careers_read(text) from public;
grant execute on function public.careers_read(text) to anon, authenticated;

-- END OF INTERVIEW CANCELLED MOVES THE STAGE -----------------------------------
