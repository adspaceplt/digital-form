-- ===========================================================================
-- INTERVIEW TIME PENDING (2026-11-22, the user, with /careers/ after a time
-- was chosen: "Before confirmation … a candidate won't actually see any like
-- Google Meet details or office details. It's only when our internal has
-- already approved the schedule … then they would be able to see the next
-- steps"). 2026-11-22. Safe to run twice. Rollback at the foot. Mirrored
-- byte for byte in supabase/schema.sql under the same banner;
-- tests/hiringsql.js compares the two.
--
-- WHAT CHANGED
--   `careers_read(p_key)`: while the candidate has chosen a time and the
--   team has not confirmed it (`picked`), the interview answers its state,
--   the time chosen, its length and whether it is online or at the office
--   (the page words its notice by it), and nothing more: no note, no times
--   offered, no reply-by, no meeting link (the link was already withheld
--   until confirmed). The invitation (`invited`) and the confirmed interview
--   answer as before; a cancelled one still answers its state alone. Every
--   other answer is unchanged.
--   `hiring_interview_move(p_interview, p_at)` (Change interview time; the
--   user, 2026-11-22: "one clear act"): the part or an Owner moves a time
--   chosen or confirmed, not yet held, to one new time an hour ahead at
--   least and 60 days at most (`slot-past`, `slot-far`, `held`, `closed`,
--   `not-picked`), confirming it; the confirmation email is let go again
--   (`confirm_mail` cleared) and the change filed in the candidate's history.
--
-- ORDER: the pages, then this file, then hiring-mail. Until this file runs,
-- Change interview time is refused as not available (the function is not
-- there) and the pending state still answers its note, which the page never
-- draws; until hiring-mail is deployed, Resend may take a second
-- confirmation within a day of the first as the first (the same key).
--
-- ROLLBACK
--   Pages first; restate `careers_read(text)` from HIRING BEFORE THE FIRST
--   HIRE and run `drop function if exists public.hiring_interview_move(uuid,
--   timestamptz)`.
-- ===========================================================================

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
      when i.state = 'cancelled' then case when c.stage in ('invited', 'interview') and c.outcome is null
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

/* Change interview time (2026-11-22, the user: one clear act for the team):
   a time chosen or confirmed, not yet held, moved to one new time and
   confirmed, an hour ahead at least and 60 days at most. The candidate's
   page reads it at once; the page then moves the Google Meet's own event
   (meet-create, the same event) and emails the confirmation again. Filed in
   the candidate's history. */
create or replace function public.hiring_interview_move(p_interview uuid, p_at timestamptz)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
  v_was timestamptz;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id for update;
  if c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if i.held_at is not null then return jsonb_build_object('error', 'held'); end if;
  if c.outcome is not null or c.stage not in ('invited', 'interview') then return jsonb_build_object('error', 'closed'); end if;
  if i.state not in ('picked', 'confirmed') or i.picked is null then return jsonb_build_object('error', 'not-picked'); end if;
  if p_at is null or p_at < now() + interval '1 hour' then return jsonb_build_object('error', 'slot-past'); end if;
  if p_at > now() + interval '60 days' then return jsonb_build_object('error', 'slot-far'); end if;
  v_was := i.slots[i.picked];
  if v_was = p_at and i.state = 'confirmed' then return jsonb_build_object('ok', true, 'same', true, 'mode', i.mode); end if;
  update public.hiring_interviews set slots = array[p_at], picked = 1, state = 'confirmed',
    approved_by = case when i.state = 'confirmed' then i.approved_by else me.id end,
    approved_at = case when i.state = 'confirmed' then i.approved_at else now() end,
    confirm_mail = null, confirm_mail_at = null, updated_at = now()
   where id = i.id;
  update public.hiring_candidates set stage = 'interview', last_step_at = now(), updated_at = now() where id = c.id;
  perform public.hiring_log(c.id, 'candidate.interview', 'Interview time changed from ' || public.hiring_when(v_was) || ' to ' || public.hiring_when(p_at));
  return jsonb_build_object('ok', true, 'mode', i.mode, 'was', v_was, 'at', p_at, 'meet', i.meeting_event_id is not null);
end $$;
revoke all on function public.hiring_interview_move(uuid, timestamptz) from public;
grant execute on function public.hiring_interview_move(uuid, timestamptz) to authenticated;

-- END OF INTERVIEW TIME PENDING -----------------------------------------------

select public.functions_tidy();
