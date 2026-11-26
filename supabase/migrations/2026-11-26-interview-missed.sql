-- ===========================================================================
-- INTERVIEW MISSED (2026-11-26)
-- ===========================================================================
-- WHY: the user, 2026-11-26 ("interview flow ok"): a confirmed interview
-- whose time has begun offers two acts, Interview completed (Interview held
-- renamed where a person reads it) and Did not attend. Did not attend asks
-- What next?: Offer a new time (the candidate keeps their place and is sent
-- new times) or Close application (Not proceed, the candidate emailed "We
-- missed you at your interview for {position}"). A missed interview is
-- recorded, counted in the history and never later completed or cancelled.
--
-- WHAT IT CHANGES
--   * `hiring_interviews.missed_at`, `missed_by`; the state `missed`.
--   * `hiring_interview_missed(p_interview, p_next)`: the part or the Owner,
--     a confirmed interview not completed whose time has begun, undecided;
--     `times` moves the candidate where their interviews now leave them
--     (`hiring_interview_stage`, else New), `close` decides Not proceed
--     (`hiring_decide`) at the same moment. Refusals: `not-found`,
--     `denied`, `held`, `not-confirmed`, `decided`, `not-yet`, `bad-next`.
--   * `hiring_interview_missed_undo(p_interview)`: Undo where it happened,
--     two minutes at most, while no newer interview was sent and no email
--     went (`too-late`, `moved-on`, `decided`, `mail-sent`).
--   * `hiring_closed_missed(candidate)`: the missed interview that closed
--     the application (its `missed_at` the decision's own moment). Internal.
--   * `hiring_interview_cancel` refuses a missed interview (`missed`);
--     `hiring_interview_held` files Interview completed.
--   * `hiring_interview_row` answers `missed_at` and `missed_by`.
--   * `careers_read` answers `missed` (the time, and `closed` where it
--     closed the application) and no interview for the missed one.
--   * `hiring_outcome_mail_prepare` and `hiring_outcome_mail_claim` answer
--     kind `missed`, with the time and the careers mailbox, where the miss
--     closed the application; the template `missed` (Interview missed,
--     Settings, Messages: Candidate email templates) is seeded; Email log
--     files `hiring_missed`.
--
-- ORDER: this file, then hiring-mail (the template `missed` in its drain),
-- then the pages. An old page never asks the new functions; an old
-- hiring-mail claims a missed close's email as `missed`, finds no template
-- in its gate and files it Not sent, so hiring-mail follows at once.
-- Safe to run twice. Holds no delete; its drops are a check's, restated.
--
-- ROLLBACK: drop `hiring_interview_missed`, `hiring_interview_missed_undo`
-- and `hiring_closed_missed`; run each restated function's last definition
-- before this band again; restore the three checks without `missed` and
-- `hiring_missed` once no row holds them. The columns may stay.
-- ===========================================================================

-- INTERVIEW MISSED -------------------------------------------------------------

alter table public.hiring_interviews add column if not exists missed_at timestamptz;
alter table public.hiring_interviews add column if not exists missed_by uuid references public.team_members(id) on delete set null;
alter table public.hiring_interviews drop constraint if exists hiring_interviews_state_check;
alter table public.hiring_interviews add constraint hiring_interviews_state_check
  check (state in ('invited', 'picked', 'none', 'confirmed', 'cancelled', 'replaced', 'expired', 'missed'));

alter table public.hiring_email_templates drop constraint if exists hiring_email_templates_kind_check;
alter table public.hiring_email_templates add constraint hiring_email_templates_kind_check
  check (kind in ('invite', 'confirm', 'rescheduled', 'held', 'moved', 'cancelled', 'pool', 'not', 'missed',
                  'doc', 'doc_again', 'confirmed', 'expired'));
insert into public.hiring_email_templates (kind, subject, body) values
  ('missed', 'We missed you at your interview for {position}',
   E'Dear {candidate name},\n\nAs you did not attend your interview for the position of {position}, arranged for {time} (Malaysia time), your application has been closed.\n\nThank you for your interest in joining ADspace. Should you wish to apply again in the future, please contact ADspace at {contact}.\n\n{sign-off}')
on conflict (kind) do nothing;

do $$
begin
  if to_regclass('public.system_emails') is not null then
    alter table public.system_emails drop constraint if exists system_emails_kind_check;
    alter table public.system_emails add constraint system_emails_kind_check
      check (kind in ('hiring_invite', 'hiring_confirm', 'hiring_pool', 'hiring_not', 'hiring_doc',
                      'hiring_code', 'invite_team', 'invite_client', 'hiring_held', 'hiring_moved',
                      'hiring_confirmed', 'hiring_cancelled', 'hiring_expired', 'hiring_rescheduled', 'hiring_missed'));
  end if;
end $$;

create or replace function public.hiring_email_templates_get()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'on', t.on_send, 'subject', t.subject, 'body', t.body, 'updated_at', t.updated_at, 'updated_by', m.name)
      order by array_position(array['invite', 'confirm', 'rescheduled', 'cancelled', 'held', 'moved', 'pool', 'not', 'missed', 'doc', 'doc_again', 'confirmed', 'expired'], t.kind))
      from public.hiring_email_templates t left join public.team_members m on m.id = t.updated_by), '[]'::jsonb)) end
$$;
revoke all on function public.hiring_email_templates_get() from public, anon;
grant execute on function public.hiring_email_templates_get() to authenticated;

create or replace function public.hiring_email_templates_save(p_rows jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  x       jsonb;
  t       public.hiring_email_templates;
  v_bad   jsonb;
  v_moved text[] := '{}';
  v_word  text;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  -- Every row is checked before any is written: a refusal saves none
  -- (review 2026-11-24: rows before it stood saved and unrecorded).
  for x in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    select * into t from public.hiring_email_templates y where y.kind = x->>'kind' for update;
    if t.kind is null then return jsonb_build_object('error', 'bad-request'); end if;
    if length(btrim(coalesce(x->>'subject', ''))) < 3 or length(x->>'subject') > 200 then
      return jsonb_build_object('error', 'bad-subject', 'kind', t.kind);
    end if;
    if length(btrim(coalesce(x->>'body', ''))) < 10 or length(x->>'body') > 5000 then
      return jsonb_build_object('error', 'bad-body', 'kind', t.kind);
    end if;
    v_bad := public.template_check(coalesce(x->>'subject', '') || ' ' || coalesce(x->>'body', ''), 'candidate');
    if v_bad is not null then return v_bad || jsonb_build_object('kind', t.kind); end if;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    select * into t from public.hiring_email_templates y where y.kind = x->>'kind';
    if (t.on_send, t.subject, t.body) is distinct from
       (coalesce((x->>'on')::boolean, true), btrim(x->>'subject'), btrim(x->>'body')) then
      v_word := case t.kind when 'invite' then 'Interview invitation' when 'confirm' then 'Interview confirmed'
        when 'rescheduled' then 'Interview time changed'
        when 'cancelled' then 'Interview cancelled' when 'held' then 'Thank you for your interview'
        when 'moved' then 'Decision date changed' when 'pool' then 'Talent pool' when 'not' then 'Application unsuccessful'
        when 'missed' then 'Interview missed'
        when 'doc' then 'Employment document' when 'doc_again' then 'Employment document sent again'
        when 'confirmed' then 'Document confirmed' else 'Document expired' end;
      v_moved := v_moved || (v_word ||
        case when t.on_send is distinct from coalesce((x->>'on')::boolean, true)
             then ': ' || case when t.on_send then 'Sent → Not sent' else 'Not sent → Sent' end
             else ': wording changed' end);
      update public.hiring_email_templates y set on_send = coalesce((x->>'on')::boolean, true), subject = btrim(x->>'subject'),
        body = btrim(x->>'body'), updated_at = now(), updated_by = me.id where y.kind = t.kind;
    end if;
  end loop;
  if cardinality(v_moved) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Candidate emails', array_to_string(v_moved, ' · '));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hiring_email_templates_save(jsonb) from public, anon;
grant execute on function public.hiring_email_templates_save(jsonb) to authenticated;

/* The missed interview that closed the application: Close application
   decides Not proceed in the same transaction as the miss, so the miss's
   moment is the decision's own; a later decision, or Reopen, has another. */
create or replace function public.hiring_closed_missed(p_candidate uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select m.id from public.hiring_interviews m join public.hiring_candidates c on c.id = m.candidate_id
   where c.id = p_candidate and c.outcome = 'not' and m.state = 'missed' and m.missed_at = c.outcome_at
   limit 1
$$;
revoke all on function public.hiring_closed_missed(uuid) from public, anon, authenticated;

/* Did not attend: the part's or the Owner's, once the confirmed interview's
   time has begun, before it is completed and before a decision. `times`
   leaves the candidate where their interviews now leave them, ready for new
   times; `close` decides Not proceed at the same moment. */
create or replace function public.hiring_interview_missed(p_interview uuid, p_next text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
  v_n int;
  v_close jsonb;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id for update;
  if c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if i.state = 'missed' then return jsonb_build_object('ok', true, 'same', true); end if;
  if i.held_at is not null then return jsonb_build_object('error', 'held'); end if;
  if i.state <> 'confirmed' or i.picked is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  if c.outcome is not null or c.stage <> 'interview' then return jsonb_build_object('error', 'decided'); end if;
  if i.slots[i.picked] > now() then return jsonb_build_object('error', 'not-yet'); end if;
  if coalesce(p_next, '') not in ('times', 'close') then return jsonb_build_object('error', 'bad-next'); end if;
  update public.hiring_interviews set state = 'missed', missed_at = now(), missed_by = me.id, updated_at = now() where id = i.id;
  select count(*) into v_n from public.hiring_interviews m where m.candidate_id = c.id and m.state = 'missed';
  perform public.hiring_log(c.id, 'candidate.interview', 'Did not attend the interview on ' || public.hiring_when(i.slots[i.picked]) || '.' ||
    case when v_n > 1 then ' Interviews missed: ' || v_n || '.' else '' end);
  if p_next = 'close' then
    v_close := public.hiring_decide(c.id, 'not', null);
    if v_close ? 'error' then raise exception 'hiring_interview_missed: %', v_close->>'error'; end if;
    return jsonb_build_object('ok', true, 'next', 'close', 'missed', v_n, 'meets', coalesce(v_close->'meets', '[]'::jsonb));
  end if;
  update public.hiring_candidates set stage = public.hiring_interview_stage(id, 'new'), last_step_at = now(), updated_at = now()
   where id = c.id and outcome is null;
  return jsonb_build_object('ok', true, 'next', 'times', 'missed', v_n);
end $$;
grant execute on function public.hiring_interview_missed(uuid, text) to authenticated;

/* Undo where it happened: two minutes at most, while no newer interview was
   sent and no email went; a close is reopened first. Never later. */
create or replace function public.hiring_interview_missed_undo(p_interview uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
  v_back jsonb;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if i.state <> 'missed' then return jsonb_build_object('ok', true, 'same', true); end if;
  if i.missed_at < now() - interval '2 minutes' then return jsonb_build_object('error', 'too-late'); end if;
  if exists (select 1 from public.hiring_interviews j where j.candidate_id = i.candidate_id and j.id <> i.id
               and j.invited_at > i.invited_at and j.state <> 'replaced') then
    return jsonb_build_object('error', 'moved-on');
  end if;
  select * into c from public.hiring_candidates where id = i.candidate_id for update;
  if c.outcome is not null then
    if public.hiring_closed_missed(c.id) is distinct from i.id then return jsonb_build_object('error', 'decided'); end if;
    if c.outcome_mail in ('sent', 'sending', 'unknown', 'failed') then return jsonb_build_object('error', 'mail-sent'); end if;
    v_back := public.hiring_decide(c.id, 'reopen', null);
    if v_back ? 'error' then raise exception 'hiring_interview_missed_undo: %', v_back->>'error'; end if;
  end if;
  update public.hiring_interviews set state = 'confirmed', missed_at = null, missed_by = null, updated_at = now() where id = i.id;
  update public.hiring_candidates set stage = public.hiring_interview_stage(id, 'new'), last_step_at = now(), updated_at = now()
   where id = c.id and outcome is null;
  perform public.hiring_log(c.id, 'candidate.interview', 'Did not attend undone.');
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_interview_missed_undo(uuid) to authenticated;

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
  -- A missed interview stays missed (INTERVIEW MISSED, 2026-11-26).
  if i.state = 'missed' then return jsonb_build_object('error', 'missed'); end if;
  update public.hiring_interviews set state = 'cancelled', updated_at = now() where id = i.id;
  -- The candidate stands where their interviews now leave them, never at
  -- Interview with none (INTERVIEW CANCELLED MOVES THE STAGE, 2026-11-26).
  update public.hiring_candidates c set stage = public.hiring_interview_stage(c.id, 'new'), last_step_at = now(), updated_at = now()
   where c.id = i.candidate_id and c.stage in ('invited', 'interview') and c.outcome is null;
  perform public.hiring_log(i.candidate_id, 'candidate.interview', 'Interview cancelled');
  return jsonb_build_object('ok', true, 'event', i.meeting_event_id, 'had_meet', i.meeting_event_id is not null);
end $$;
grant execute on function public.hiring_interview_cancel(uuid) to authenticated;

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
  -- A missed interview is never later completed (INTERVIEW MISSED, 2026-11-26).
  if i.state = 'missed' then return jsonb_build_object('error', 'missed'); end if;
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
  perform public.hiring_log(c.id, 'candidate.interview', 'Interview completed. The decision is due by ' || public.hiring_when(v_at) || '.');
  return jsonb_build_object('ok', true, 'decide_by', v_at);
end $$;
grant execute on function public.hiring_interview_held(uuid, timestamptz) to authenticated;

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
    'moved_from', i.moved_from, 'reschedule_mail', i.reschedule_mail, 'reschedule_mail_at', i.reschedule_mail_at,
    'held_at', i.held_at, 'held_by', (select t.name from public.team_members t where t.id = i.held_by),
    'held_mail', i.held_mail, 'held_mail_at', i.held_mail_at,
    'missed_at', i.missed_at, 'missed_by', (select t.name from public.team_members t where t.id = i.missed_by),
    'decide_by', (select c.decide_by from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null),
    'decide_note', (select c.decide_note from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null),
    'decide_moved', (select true from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null and c.decide_moved_at is not null)));
$$;
revoke all on function public.hiring_interview_row(public.hiring_interviews) from public, anon, authenticated;

create or replace function public.hiring_outcome_mail_prepare(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  v_missed uuid;
begin
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.outcome not in ('pool', 'not') then return jsonb_build_object('error', 'no-email'); end if;
  -- Closed at Did not attend: the missed interview's own email (2026-11-26).
  v_missed := public.hiring_closed_missed(c.id);
  return jsonb_build_object('id', c.id, 'kind', case when v_missed is not null then 'missed' else c.outcome end,
    'to', c.email, 'name', c.name, 'position', c.position, 'key', c.link_key,
    'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12),
    'when', (select public.hiring_when(m.slots[m.picked]) from public.hiring_interviews m where m.id = v_missed),
    'contact', case when v_missed is not null then public.mail_sender('careers')->>'reply_to' end,
    'sender', me.name, 'system', coalesce(me.system, false));
end $$;
revoke all on function public.hiring_outcome_mail_prepare(uuid) from public, anon;
grant execute on function public.hiring_outcome_mail_prepare(uuid) to authenticated;

create or replace function public.hiring_outcome_mail_claim()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v jsonb; v_stuck uuid[];
begin
  -- A send still marked going out after 10 minutes never answered: it is
  -- marked not confirmed, filed, and told by the morning check
  -- (RETENTION AND JOBS HELD).
  with stuck as (
    update public.hiring_candidates c set outcome_mail = 'unknown', outcome_mail_at = now()
     where c.outcome_mail = 'sending' and coalesce(c.outcome_mail_at, c.updated_at) < now() - interval '10 minutes'
    returning c.id)
  select coalesce(array_agg(x.id), '{}') into v_stuck from stuck x;
  perform public.hiring_log(x, 'candidate.email', 'Decision sent to the candidate, but its delivery could not be verified.')
    from unnest(v_stuck) x;
  with due as (
    select c.id from public.hiring_candidates c
     where c.outcome_mail = 'queued' and c.outcome_mail_due <= now() and c.outcome in ('pool', 'not')
       and c.removed_at is null and c.link_key is not null
     order by c.outcome_mail_due limit 20 for update skip locked),
  took as (
    update public.hiring_candidates c set outcome_mail = 'sending', outcome_mail_due = null, outcome_mail_at = now() from due where c.id = due.id
    returning c.id, c.outcome, c.email, c.name, c.position, c.link_key)
  -- Closed at Did not attend: the missed interview's own email (2026-11-26).
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'kind', case when x.mid is not null then 'missed' else t.outcome end,
      'to', t.email, 'name', t.name, 'position', t.position, 'key', t.link_key,
      'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12),
      'when', (select public.hiring_when(m.slots[m.picked]) from public.hiring_interviews m where m.id = x.mid),
      'contact', case when x.mid is not null then public.mail_sender('careers')->>'reply_to' end,
      'system', true)), '[]'::jsonb) into v
    from took t cross join lateral (select public.hiring_closed_missed(t.id) as mid) x;
  return v;
end $$;
revoke all on function public.hiring_outcome_mail_claim() from public, anon, authenticated;
grant execute on function public.hiring_outcome_mail_claim() to service_role;

create or replace function public.careers_read(p_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_contact text := public.mail_sender('careers')->>'reply_to';
  c public.hiring_candidates;
  i public.hiring_interviews;
  m public.hiring_interviews;
  v_state text;
  v_missed jsonb;
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
  /* Interview missed (2026-11-26): its time, while no later interview has
     been confirmed and the candidate is still in the running, or where it
     closed the application. */
  select * into m from public.hiring_interviews where candidate_id = c.id and state = 'missed'
   order by invited_at desc limit 1;
  v_missed := case when m.id is not null
      and not exists (select 1 from public.hiring_interviews j where j.candidate_id = c.id and j.invited_at > m.invited_at and j.state = 'confirmed')
      and ((c.stage in ('new', 'invited', 'interview') and c.outcome is null) or public.hiring_closed_missed(c.id) = m.id)
    then jsonb_strip_nulls(jsonb_build_object('at', m.slots[m.picked], 'closed', case when c.outcome = 'not' then true end)) end;
  return jsonb_strip_nulls(jsonb_build_object('missed', v_missed)) || jsonb_build_object('ok', true, 'contact', v_contact, 'name', c.name, 'position', c.position, 'stage',
    case when c.stage = 'new' or (c.stage = 'pool' and c.outcome is null) then 'received' else c.stage end, 'received_at', c.created_at,
    'pool_declined', case when c.outcome = 'pool' and c.pool_consent = 'no' then true end,
    'pool', case when c.stage = 'pool' and c.outcome = 'pool' then jsonb_strip_nulls(jsonb_build_object('consent', c.pool_consent,
      'until', c.pool_until, 'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12))) end,
    'interview', case when i.id is null or c.stage in ('pool', 'closed') or i.state = 'missed' then null
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

-- END OF INTERVIEW MISSED ------------------------------------------------------

select public.functions_tidy();
