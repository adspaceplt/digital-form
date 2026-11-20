-- ===========================================================================
-- HIRING: CONFIRMED AND CANCELLED EMAILS (2026-11-20)
-- ===========================================================================
-- WHY: the user, 2026-11-20: "yes fix the 3 hiring issues too". A candidate
-- whose offer or contract ADspace confirmed was told by their page that
-- they would hear by email, and was never emailed; a confirmed interview
-- cancelled left the candidate's page reading Interview confirmed and the
-- candidate holding the Google Meet link, unemailed. Hiring dates read in
-- the portal's form for a date the reader waits on: 21 Nov 2026
-- (Saturday), 10:00am (`ADspaceClock.due`).
--
-- WHAT IT CHANGES
--   * `hiring_when(p_at)`: 21 Nov 2026 (Saturday), 10:00am, in place of
--     Saturday, 21 November 2026, 10:00am. Read by every hiring email, the
--     bell's lines and the history.
--   * `hiring_docs.confirm_mail`, `confirm_mail_at`; `hiring_doc_row`
--     answers them.
--   * `hiring_confirmed_mail_prepare(p_doc)` / `hiring_confirmed_mail_done
--     (p_doc, p_status, p_error)`: the email that a confirmed Employment
--     Offer or Contract was confirmed (`hiring-mail` `confirmed`), the part
--     or the Owner, `not-confirmed` before Confirm; never the terms.
--   * `hiring_interviews.cancel_mail`, `cancel_mail_at`;
--     `hiring_interview_row` answers them; `hiring_mail_prepare` and
--     `hiring_mail_done` take `cancelled` (`hiring-mail` `cancelled`): a
--     confirmed interview cancelled (`not-cancelled`), the latest one
--     (`replaced` once new times are sent).
--   * `careers_read` answers a cancelled interview as `{state: cancelled}`
--     while the candidate is Invited or at Interview and undecided, so
--     the page reads Interview cancelled, never its time or link.
--   * `system_emails` files `hiring_confirmed` and `hiring_cancelled`.
--   * The coordinator's review of the day's merges: a decision date on a
--     working day alone (`is_working_day`, the front door's rule; `hiring_interview_held` and
--     `hiring_decide_by_change` refuse `not-workday`); `hiring_decide_remind
--     (p_today)` counts the working days left (tomorrow, on the next working
--     day, in 2 working days) and, past the date with no decision, tells the
--     Owners each working morning (`hiring.decide_over`,
--     `hiring_candidates.decide_over_on`); `careers_read` answers, past the
--     decision date with no decision, the careers mailbox to contact; every hiring email's prepare
--     answers `system` (the sender a system account: the email closes as
--     the ADspace Hiring Team), never the colleague's own address.
--   * An email that did not go is filed in the candidate's history as not
--     emailed, never with the mail provider's own words.
--   * Left on their own reading of a working day, unchanged here: My Work's
--     `ops_add_business_days` (weekends alone: a due date is never moved
--     for a holiday), `ops_tasks_remind` and `ops_tasks_nudge` (weekends,
--     their cron asking `public_holiday_on`, which is the same rule).
--
-- ORDER: this file, then hiring-mail (the two new kinds), then the pages.
-- An old page never asks for the new emails; an old hiring-mail refuses
-- them (`bad-request`), so the page says the email was not sent and offers
-- Email candidate. Safe to run twice.
--
-- ROLLBACK: drop `hiring_confirmed_mail_prepare`,
-- `hiring_confirmed_mail_done`, `hiring_decide_remind(date)` and
-- `is_working_day`; run `hiring_workday_add` from INTERVIEW HELD, `hiring_decide_remind`,
-- `hiring_interview_held` and `hiring_decide_by_change` from INTERVIEW
-- HELD, `hiring_outcome_mail_prepare` and `hiring_doc_mail_prepare` from
-- ACCESS CLEAN-UP again; run `hiring_when` from INTERVIEW TIMES IN
-- FULL, `hiring_doc_row` from HIRING OFFERS AND CONTRACTS, and
-- `hiring_interview_row`, `hiring_mail_prepare`, `hiring_mail_done` and
-- `careers_read` from INTERVIEW HELD again; restore the `system_emails`
-- kind check without the two kinds. The columns may stay.
-- ===========================================================================

/* A time the candidate waits on, Malaysia's: 21 Nov 2026 (Saturday), 10:00am. */
create or replace function public.hiring_when(p_at timestamptz)
returns text language sql stable set search_path = public as $$
  select case when p_at is null then null else
    public.register_day((p_at at time zone 'Asia/Kuala_Lumpur')::date) || ' ('
    || to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'FMDay') || '), '
    || ltrim(lower(to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'HH12:MIam')), '0') end;
$$;
revoke all on function public.hiring_when(timestamptz) from public, anon, authenticated;

alter table public.hiring_docs add column if not exists confirm_mail text;
alter table public.hiring_docs add column if not exists confirm_mail_at timestamptz;
alter table public.hiring_interviews add column if not exists cancel_mail text;
alter table public.hiring_interviews add column if not exists cancel_mail_at timestamptz;

/* The two new emails are filed for Messages' Email log as the others. */
do $$
begin
  if to_regclass('public.system_emails') is not null then
    alter table public.system_emails drop constraint if exists system_emails_kind_check;
    alter table public.system_emails add constraint system_emails_kind_check
      check (kind in ('hiring_invite', 'hiring_confirm', 'hiring_pool', 'hiring_not', 'hiring_doc',
                      'hiring_code', 'invite_team', 'invite_client', 'hiring_held', 'hiring_moved',
                      'hiring_confirmed', 'hiring_cancelled'));
  end if;
end $$;

create or replace function public.hiring_doc_row(d public.hiring_docs)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', d.id, 'kind', d.kind, 'state', d.state, 'serial', d.serial, 'terms', d.terms, 'replaces', d.replaces,
    'made_by', (select t.name from public.team_members t where t.id = d.made_by), 'made_at', d.made_at,
    'sent_by', (select t.name from public.team_members t where t.id = d.sent_by),
    'sent_role', (select t.designation from public.team_members t where t.id = d.sent_by), 'sent_at', d.sent_at,
    'reply_by', d.reply_by, 'expired', d.state = 'sent' and d.reply_by <= now(),
    'answered_at', d.answered_at, 'decline_note', d.decline_note,
    'signed', case when d.signed is not null then jsonb_strip_nulls(jsonb_build_object('via', d.signed->>'via',
      'name', d.signed->>'name', 'on', d.signed->>'on', 'has_scan', d.signed ? 'path', 'path', d.signed->>'path',
      'email', d.signed->'record'->>'email')) end,
    'signed_at', d.signed_at, 'returned_at', d.returned_at, 'returned_by', d.returned_by, 'returned_note', d.returned_note,
    'confirmed_by', (select t.name from public.team_members t where t.id = d.confirmed_by), 'confirmed_at', d.confirmed_at,
    'stamp_no', d.stamp_no, 'stamp_path', d.stamp_path, 'seal_path', d.seal_path, 'seal_sha', d.seal_sha,
    'sealed_at', d.sealed_at, 'void_note', d.void_note, 'voided_at', d.voided_at, 'mail', d.mail, 'mail_at', d.mail_at,
    'confirm_mail', d.confirm_mail, 'confirm_mail_at', d.confirm_mail_at,
    'pay_set', exists (select 1 from public.hiring_doc_pay p where p.doc_id = d.id), 'updated_at', d.updated_at))
$$;
revoke all on function public.hiring_doc_row(public.hiring_docs) from public, anon, authenticated;

/* The candidate told that their document was confirmed: its name, its
   reference and their page; never the terms or the salary. */
create or replace function public.hiring_confirmed_mail_prepare(p_doc uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; c public.hiring_candidates; v_role text;
begin
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed'); end if;
  select * into c from public.hiring_candidates where id = d.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('id', d.id, 'kind', 'confirmed', 'doc', d.kind, 'ref', d.serial, 'to', c.email, 'name', c.name,
    'position', d.terms->>'position', 'key', c.link_key, 'sender', me.name, 'system', coalesce(me.system, false));
end $$;
revoke all on function public.hiring_confirmed_mail_prepare(uuid) from public, anon;
grant execute on function public.hiring_confirmed_mail_prepare(uuid) to authenticated;

create or replace function public.hiring_confirmed_mail_done(p_doc uuid, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.hiring_docs; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-request'); end if;
  update public.hiring_docs set confirm_mail = p_status, confirm_mail_at = now() where id = d.id;
  perform public.hiring_log(d.candidate_id, 'candidate.email', d.serial || ' confirmation' || case p_status when 'sent' then ' emailed'
    when 'unknown' then ' emailed, not confirmed' else ' not emailed' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hiring_confirmed_mail_done(uuid, text, text) from public, anon;
grant execute on function public.hiring_confirmed_mail_done(uuid, text, text) to authenticated;

create or replace function public.hiring_interview_row(i public.hiring_interviews)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object('id', i.id, 'round', i.round, 'slots', to_jsonb(i.slots), 'minutes', i.minutes,
    'mode', i.mode, 'note', i.note, 'state', public.hiring_interview_state(i), 'picked', i.picked, 'picked_at', i.picked_at,
    'candidate_note', i.candidate_note, 'invited_at', i.invited_at, 'reply_by', i.reply_by,
    'invited_by', (select t.name from public.team_members t where t.id = i.invited_by),
    'approved_at', i.approved_at, 'approved_by', (select t.name from public.team_members t where t.id = i.approved_by),
    'meeting_link', i.meeting_link, 'invite_mail', i.invite_mail, 'invite_mail_at', i.invite_mail_at,
    'confirm_mail', i.confirm_mail, 'confirm_mail_at', i.confirm_mail_at,
    'cancel_mail', i.cancel_mail, 'cancel_mail_at', i.cancel_mail_at,
    'held_at', i.held_at, 'held_by', (select t.name from public.team_members t where t.id = i.held_by),
    'held_mail', i.held_mail, 'held_mail_at', i.held_mail_at,
    'decide_by', (select c.decide_by from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null),
    'decide_note', (select c.decide_note from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null),
    'decide_moved', (select true from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null and c.decide_moved_at is not null)));
$$;
revoke all on function public.hiring_interview_row(public.hiring_interviews) from public, anon, authenticated;

create or replace function public.hiring_mail_done(p_interview uuid, p_kind text, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare i public.hiring_interviews; v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') or coalesce(p_kind, '') not in ('invite', 'confirm', 'held', 'moved', 'cancelled') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if p_kind = 'invite' then update public.hiring_interviews set invite_mail = p_status, invite_mail_at = now(), updated_at = now() where id = i.id;
  elsif p_kind = 'confirm' then update public.hiring_interviews set confirm_mail = p_status, confirm_mail_at = now(), updated_at = now() where id = i.id;
  elsif p_kind = 'cancelled' then update public.hiring_interviews set cancel_mail = p_status, cancel_mail_at = now(), updated_at = now() where id = i.id;
  else update public.hiring_interviews set held_mail = p_status, held_mail_at = now(), updated_at = now() where id = i.id; end if;
  perform public.hiring_log(i.candidate_id, 'candidate.email',
    case p_kind when 'invite' then 'Invitation' when 'confirm' then 'Confirmation' when 'cancelled' then 'Cancellation'
      when 'held' then 'Decision date' else 'New decision date' end || case p_status when 'sent' then ' emailed'
      when 'unknown' then ' emailed, not confirmed' else ' not emailed' end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_mail_done(uuid, text, text, text) to authenticated;

create or replace function public.hiring_mail_prepare(p_interview uuid, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
begin
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  select * into i from public.hiring_interviews where id = p_interview;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_kind = 'invite' and public.hiring_interview_state(i) not in ('invited', 'none') then return jsonb_build_object('error', 'not-open'); end if;
  if p_kind = 'confirm' and i.state <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed'); end if;
  if p_kind = 'confirm' and i.mode = 'online' and i.meeting_link is null then return jsonb_build_object('error', 'no-meet'); end if;
  if p_kind in ('held', 'moved') and (i.held_at is null or c.decide_by is null or c.outcome is not null) then
    return jsonb_build_object('error', 'not-held');
  end if;
  /* A cancellation is told only of a confirmed interview, and only while no
     newer interview has been sent. */
  if p_kind = 'cancelled' and (i.state <> 'cancelled' or i.approved_at is null or i.picked is null) then
    return jsonb_build_object('error', 'not-cancelled');
  end if;
  if p_kind = 'cancelled' and exists (select 1 from public.hiring_interviews j where j.candidate_id = i.candidate_id
       and j.id <> i.id and j.invited_at > i.invited_at and j.state <> 'cancelled') then
    return jsonb_build_object('error', 'replaced');
  end if;
  if p_kind not in ('invite', 'confirm', 'held', 'moved', 'cancelled') then return jsonb_build_object('error', 'bad-kind'); end if;
  return jsonb_build_object('id', i.id, 'kind', p_kind, 'to', c.email, 'name', c.name, 'position', c.position,
    'key', c.link_key, 'mode', i.mode, 'minutes', i.minutes, 'note', i.note, 'link', case when p_kind <> 'cancelled' then i.meeting_link end,
    'times', (select jsonb_agg(public.hiring_when(s) order by s) from unnest(i.slots) s),
    'when', case when i.picked is not null then public.hiring_when(i.slots[i.picked]) end,
    'reply_by', case when p_kind = 'invite' and i.state = 'invited' then public.hiring_when(i.reply_by) end,
    'decide_by', case when p_kind in ('held', 'moved') then public.hiring_when(c.decide_by) end,
    'decide_note', case when p_kind = 'moved' then c.decide_note end,
    'sender', me.name, 'system', coalesce(me.system, false));
end $$;

create or replace function public.careers_read(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_state text;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null;
  if c.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() and not (c.stage = 'pool' and c.pool_consent = 'yes') then
    return jsonb_build_object('error', 'expired');
  end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state <> 'replaced'
   order by invited_at desc limit 1;
  v_state := case when i.id is null then null else public.hiring_interview_state(i) end;
  return jsonb_build_object('ok', true, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage = 'new' or (c.stage = 'pool' and c.outcome is null) then 'received' else c.stage end, 'received_at', c.created_at,
    'pool', case when c.stage = 'pool' and c.outcome = 'pool' then jsonb_strip_nulls(jsonb_build_object('consent', c.pool_consent,
      'until', c.pool_until, 'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12))) end,
    'interview', case when i.id is null or c.stage in ('pool', 'closed') then null
      /* Cancelled: the state alone, never its time or link (2026-11-20). */
      when i.state = 'cancelled' then case when c.stage in ('invited', 'interview') and c.outcome is null
        then jsonb_build_object('state', 'cancelled') end
      else jsonb_strip_nulls(jsonb_build_object(
      'state', v_state, 'slots', case when v_state = 'invited' then to_jsonb(i.slots) end, 'minutes', i.minutes,
      'mode', i.mode, 'note', i.note, 'at', case when i.picked is not null then i.slots[i.picked] end,
      'reply_by', case when v_state = 'invited' then i.reply_by end,
      'link', case when i.state = 'confirmed' and i.held_at is null then i.meeting_link end,
      'held', case when i.held_at is not null then true end,
      'decide_by', case when i.held_at is not null and c.outcome is null then c.decide_by end,
      /* Past it with no decision: the careers mailbox to contact (2026-11-20). */
      'contact', case when i.held_at is not null and c.outcome is null and c.decide_by <= now() then public.mail_sender('careers')->>'reply_to' end)) end,
    'docs', case when c.stage in ('offer', 'hired') then coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', d.id, 'kind', d.kind,
        'serial', d.serial, 'state', case when d.state = 'sent' and d.reply_by <= now() then 'expired' else d.state end,
        'sent_at', d.sent_at, 'reply_by', d.reply_by, 'signed_at', d.signed_at)) order by d.sent_at)
      from public.hiring_docs d where d.candidate_id = c.id and d.state in ('sent', 'signed', 'confirmed', 'declined')), '[]'::jsonb) end);
end $$;
revoke all on function public.careers_read(text) from public;
grant execute on function public.careers_read(text) to anon, authenticated;

/* A working day, the one rule (the user, 2026-11-20: the decision date
   follows the front door's Service hours): Monday to Friday, never a day on
   the public holidays list. The front door reads the same table. */
create or replace function public.is_working_day(p_day date)
returns boolean language sql stable security definer set search_path = public as $$
  select p_day is not null and extract(isodow from p_day) < 6
     and not exists (select 1 from public.public_holidays h where h.day = p_day);
$$;
revoke all on function public.is_working_day(date) from public, anon, authenticated;

/* n working days after p_day (before it, n below nought), by that rule. */
create or replace function public.hiring_workday_add(p_day date, p_n int)
returns date language plpgsql stable security definer set search_path = public as $$
declare
  v_cur  date := p_day;
  v_left int := abs(coalesce(p_n, 0));
  v_step int := case when coalesce(p_n, 0) < 0 then -1 else 1 end;
begin
  while v_left > 0 loop
    v_cur := v_cur + v_step;
    if public.is_working_day(v_cur) then
      v_left := v_left - 1;
    end if;
  end loop;
  return v_cur;
end $$;
revoke all on function public.hiring_workday_add(date, int) from public, anon, authenticated;

alter table public.hiring_candidates add column if not exists decide_over_on date;

create or replace function public.hiring_interview_held(p_interview uuid, p_decide_by timestamptz)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
  v_at timestamptz;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id for update;
  if i.held_at is not null then return jsonb_build_object('ok', true, 'same', true, 'decide_by', c.decide_by); end if;
  if i.state <> 'confirmed' or i.picked is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  if c.outcome is not null or c.stage <> 'interview' then return jsonb_build_object('error', 'decided'); end if;
  if i.slots[i.picked] > now() then return jsonb_build_object('error', 'not-yet'); end if;
  v_at := coalesce(p_decide_by, public.hiring_decide_by_at(now(), null));
  if v_at <= now() then return jsonb_build_object('error', 'past'); end if;
  if v_at > public.hiring_decide_by_at(now(), 30) then return jsonb_build_object('error', 'too-far'); end if;
  if not public.is_working_day((v_at at time zone 'Asia/Kuala_Lumpur')::date) then return jsonb_build_object('error', 'not-workday'); end if;
  update public.hiring_interviews set held_at = now(), held_by = me.id, held_mail = null, held_mail_at = null, updated_at = now() where id = i.id;
  update public.hiring_candidates set decide_by = v_at, decide_note = null, decide_soon_at = null, decide_due_at = null, decide_moved_at = null,
    last_step_at = now(), updated_at = now() where id = c.id;
  perform public.hiring_log(c.id, 'candidate.interview', 'Interview held. Decision due ' || public.hiring_when(v_at));
  return jsonb_build_object('ok', true, 'decide_by', v_at);
end $$;
grant execute on function public.hiring_interview_held(uuid, timestamptz) to authenticated;

create or replace function public.hiring_decide_by_change(p_interview uuid, p_decide_by timestamptz, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id for update;
  if i.held_at is null or c.decide_by is null then return jsonb_build_object('error', 'not-held'); end if;
  if c.outcome is not null then return jsonb_build_object('error', 'decided'); end if;
  if p_decide_by is null or p_decide_by <= now() then return jsonb_build_object('error', 'past'); end if;
  if p_decide_by > public.hiring_decide_by_at(now(), 30) then return jsonb_build_object('error', 'too-far'); end if;
  if not public.is_working_day((p_decide_by at time zone 'Asia/Kuala_Lumpur')::date) then return jsonb_build_object('error', 'not-workday'); end if;
  if char_length(coalesce(p_note, '')) > 500 then return jsonb_build_object('error', 'too-long'); end if;
  if p_decide_by = c.decide_by and nullif(btrim(coalesce(p_note, '')), '') is not distinct from c.decide_note then
    return jsonb_build_object('ok', true, 'same', true, 'decide_by', c.decide_by);
  end if;
  update public.hiring_candidates set decide_by = p_decide_by, decide_note = nullif(btrim(coalesce(p_note, '')), ''),
    decide_soon_at = null, decide_due_at = null, decide_moved_at = now(), last_step_at = now(), updated_at = now() where id = c.id;
  update public.hiring_interviews set held_mail = null, held_mail_at = null, updated_at = now() where id = i.id;
  perform public.hiring_log(c.id, 'candidate.interview', 'Decision date changed from ' || public.hiring_when(c.decide_by) ||
    ' to ' || public.hiring_when(p_decide_by));
  return jsonb_build_object('ok', true, 'was', c.decide_by, 'decide_by', p_decide_by);
end $$;
grant execute on function public.hiring_decide_by_change(uuid, timestamptz, text) to authenticated;

/* Each morning at 8:30 (MYT; p_today stands in for today in a test): two
   working days before a decision-by, the working days left counted
   (tomorrow, on the next working day, in 2 working days), and on its day,
   its Owners told once each; past it with no decision, each working
   morning, once a day (Decision overdue); a decision clears all of it. */
drop function if exists public.hiring_decide_remind();
create or replace function public.hiring_decide_remind(p_today date default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  n int := 0;
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Kuala_Lumpur')::date);
  v_day date;
  v_left int;
  v_when text;
begin
  for r in
    select c.id, c.position, c.decide_by, c.decide_soon_at, c.decide_due_at, c.decide_over_on from public.hiring_candidates c
     where c.decide_by is not null and c.outcome is null and c.removed_at is null and c.stage = 'interview'
     for update
  loop
    v_day := (r.decide_by at time zone 'Asia/Kuala_Lumpur')::date;
    if v_today = v_day and r.decide_due_at is null then
      update public.hiring_candidates set decide_due_at = now() where id = r.id;
      perform public.hiring_tell(r.id, 'hiring.decide_due', 'A hiring decision is due today',
        'Decide on the ' || r.position || ' candidate by ' || public.hiring_when(r.decide_by) || ' on the Scores tab.');
      n := n + 1;
    elsif v_today < v_day and v_today >= public.hiring_workday_add(v_day, -2) and r.decide_soon_at is null then
      select count(*) into v_left from generate_series(v_today + 1, v_day, interval '1 day') g(d)
       where public.is_working_day(g.d::date);
      v_when := case when v_day = v_today + 1 then 'tomorrow' when v_left <= 1 then 'on the next working day'
        else 'in ' || v_left || ' working days' end;
      update public.hiring_candidates set decide_soon_at = now() where id = r.id;
      perform public.hiring_tell(r.id, 'hiring.decide_soon', 'A hiring decision is due ' || v_when,
        'Decide on the ' || r.position || ' candidate by ' || public.hiring_when(r.decide_by) || ' on the Scores tab.');
      n := n + 1;
    elsif v_today > v_day and public.is_working_day(v_today) and r.decide_over_on is distinct from v_today then
      update public.hiring_candidates set decide_over_on = v_today where id = r.id;
      perform public.hiring_tell(r.id, 'hiring.decide_over', 'A hiring decision is overdue',
        'The decision on the ' || r.position || ' candidate was due ' || public.hiring_when(r.decide_by) || '. Decide on the Scores tab, or change the decision date.');
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.hiring_decide_remind(date) from public, anon, authenticated;

create or replace function public.hiring_outcome_mail_prepare(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
begin
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.outcome not in ('pool', 'not') then return jsonb_build_object('error', 'no-email'); end if;
  return jsonb_build_object('id', c.id, 'kind', c.outcome, 'to', c.email, 'name', c.name, 'position', c.position, 'key', c.link_key,
    'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12),
    'sender', me.name, 'system', coalesce(me.system, false));
end $$;
grant execute on function public.hiring_outcome_mail_prepare(uuid) to authenticated;

create or replace function public.hiring_doc_mail_prepare(p_doc uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; c public.hiring_candidates; v_role text;
begin
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'sent' then return jsonb_build_object('error', 'not-sent'); end if;
  select * into c from public.hiring_candidates where id = d.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('id', d.id, 'kind', 'doc', 'doc', d.kind, 'ref', d.serial, 'to', c.email, 'name', c.name,
    'position', d.terms->>'position', 'key', c.link_key, 'reply_by', public.register_day((d.reply_by at time zone 'Asia/Kuala_Lumpur')::date),
    'returned', d.returned_note is not null, 'sent_key', extract(epoch from coalesce(d.returned_at, d.sent_at))::bigint,
    'sender', me.name, 'system', coalesce(me.system, false));
end $$;
grant execute on function public.hiring_doc_mail_prepare(uuid) to authenticated;

-- END OF HIRING: CONFIRMED AND CANCELLED EMAILS --------------------------------

select public.functions_tidy();
