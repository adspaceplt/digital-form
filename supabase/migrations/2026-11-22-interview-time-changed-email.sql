-- ===========================================================================
-- INTERVIEW TIME CHANGED EMAIL (2026-11-22, the user: "Yes, I as candidate
-- would have thought the date is the same and maybe missed it if it's
-- brought forward, or moved beyond. This is corporate governance of good
-- image shown to our candidates."). 2026-11-22. Safe to run twice. Rollback
-- at the foot. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/hiringsql.js compares the two.
--
-- WHAT CHANGED
--   Change interview time (`hiring_interview_move`) moved the interview and
--   confirmed it, and a colleague then pressed Email {name}, which sent the
--   Interview confirmed email again: nothing said the time had changed. Now:
--   * `hiring_interviews.moved_from` (the time the interview held before its
--     last move), `moved_from_before` (the one before that, so a move the
--     shared calendar refused is put back whole), `moved_at` (the move's own
--     moment, carried in the email's Resend key) and `reschedule_mail`,
--     `reschedule_mail_at` (the email's outcome); `hiring_interview_row`
--     answers `moved_from` and the outcome.
--   * A twelfth candidate email, Interview time changed (`rescheduled`,
--     `hiring_email_templates`, its own switch, on): the previous time and
--     the new one, each with its weekday, the new one standing; where the
--     interview is held at the new time; and that the candidate may say on
--     WhatsApp from their page if it does not suit. Its fields `previous
--     time` and `new time` join `template_fields('candidate')`.
--   * `hiring_mail_prepare` and `hiring_mail_done` take `rescheduled`: a
--     confirmed interview not held, moved at least once (`not-moved`),
--     online with its Google Meet (`no-meet`); sent, it also stands as the
--     confirmation of the new time (`confirm_mail`), and it is filed in the
--     candidate's history.
--   * `hiring_interview_move` stamps the previous time and the move, and lets
--     the earlier email go; moved back to the time it was moved from before
--     any email told the candidate (the calendar refused the move), the
--     earlier record is put back.
--   * `careers_read` answers a confirmed interview not held its previous
--     time (`was`), so the page reads Rescheduled with it.
--   * `system_emails` files `hiring_rescheduled`.
--
-- ORDER: the pages, then this file, then hiring-mail. Until this file runs,
-- the console reads no `rescheduled` template, so Change interview time
-- offers Email {name} as before (the confirmation). Between this file and
-- hiring-mail, a move's automatic email is refused by hiring-mail v(old) as
-- a bad request and the card offers Email candidate; nothing is sent twice.
--
-- ROLLBACK
--   hiring-mail's previous version; then restate `careers_read`,
--   `hiring_interview_move` from INTERVIEW TIME PENDING, `hiring_mail_done`
--   from HIRING AND RECORD LINES WORDED, `hiring_mail_prepare`,
--   `template_fields`, `hiring_email_templates_get` and
--   `hiring_email_templates_save` from CANDIDATE EMAILS, and
--   `hiring_interview_row` from HIRING: CONFIRMED AND CANCELLED EMAILS; the
--   `rescheduled` row and the columns may stay.
-- ===========================================================================

alter table public.hiring_interviews add column if not exists moved_from timestamptz;
alter table public.hiring_interviews add column if not exists moved_from_before timestamptz;
alter table public.hiring_interviews add column if not exists moved_at timestamptz;
alter table public.hiring_interviews add column if not exists reschedule_mail text;
alter table public.hiring_interviews add column if not exists reschedule_mail_at timestamptz;

alter table public.hiring_email_templates drop constraint if exists hiring_email_templates_kind_check;
alter table public.hiring_email_templates add constraint hiring_email_templates_kind_check
  check (kind in ('invite', 'confirm', 'rescheduled', 'held', 'moved', 'cancelled', 'pool', 'not',
                  'doc', 'doc_again', 'confirmed', 'expired'));
insert into public.hiring_email_templates (kind, subject, body) values
  ('rescheduled', 'Interview time changed: {position}',
   E'Dear {candidate name},\n\nYour interview for the position of {position} has been rescheduled. Please note the new date and time below.\n\nPrevious time: {previous time} (no longer applies)\nNew time: {new time} (Malaysia time), for {interview length} minutes\n\n{place}\n\nIf the new time is not suitable, please contact ADspace on WhatsApp through your application page.\n\n{button}\n\n{sign-off}')
on conflict (kind) do nothing;

do $$
begin
  if to_regclass('public.system_emails') is not null then
    alter table public.system_emails drop constraint if exists system_emails_kind_check;
    alter table public.system_emails add constraint system_emails_kind_check
      check (kind in ('hiring_invite', 'hiring_confirm', 'hiring_pool', 'hiring_not', 'hiring_doc',
                      'hiring_code', 'invite_team', 'invite_client', 'hiring_held', 'hiring_moved',
                      'hiring_confirmed', 'hiring_cancelled', 'hiring_expired', 'hiring_rescheduled'));
  end if;
end $$;

/* The fields hiring-mail fills in a candidate email. */
create or replace function public.template_fields(p_kind text) returns text[]
language sql immutable set search_path = public as $$
  select case p_kind
    when 'supplier' then array['contact name', 'supplier name', 'supplier id', 'payment term', 'currency',
      'document title', 'document reference', 'document date', 'sender name']
    when 'client' then array['contact name', 'client name', 'company name', 'document title', 'document reference',
      'document date', 'valid until', 'sender name']
    when 'free' then array['contact name', 'company name', 'client name', 'supplier name', 'sender name']
    when 'invoice' then array['contact name', 'client', 'invoice no', 'count', 'total', 'sign off', 'invoices']
    when 'creator-details' then array['creator name', 'creator id', 'reference', 'payee', 'method', 'account ending',
      'review link']
    when 'creator-booking' then array['creator name', 'creator id', 'job reference', 'campaign', 'posted date', 'pay by',
      'payee', 'method', 'account ending', 'amount', 'bill number', 'review link']
    when 'meeting' then array['meeting', 'date', 'time', 'month', 'channel', 'link']
    when 'code' then array['name', 'code', 'minutes', 'purpose']
    when 'candidate' then array['candidate name', 'position', 'interview length', 'where', 'times', 'reply by', 'note',
      'time', 'previous time', 'new time', 'place', 'google meet notice', 'decision date', 'months', 'document', 'reference',
      'requested action', 'purpose', 'reason', 'document date', 'contact', 'sign-off', 'button']
  end $$;
revoke all on function public.template_fields(text) from public, anon, authenticated;

create or replace function public.hiring_email_templates_get()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'on', t.on_send, 'subject', t.subject, 'body', t.body, 'updated_at', t.updated_at, 'updated_by', m.name)
      order by array_position(array['invite', 'confirm', 'rescheduled', 'cancelled', 'held', 'moved', 'pool', 'not', 'doc', 'doc_again', 'confirmed', 'expired'], t.kind))
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
    if (t.on_send, t.subject, t.body) is distinct from
       (coalesce((x->>'on')::boolean, true), btrim(x->>'subject'), btrim(x->>'body')) then
      v_word := case t.kind when 'invite' then 'Interview invitation' when 'confirm' then 'Interview confirmed'
        when 'rescheduled' then 'Interview time changed'
        when 'cancelled' then 'Interview cancelled' when 'held' then 'Thank you for your interview'
        when 'moved' then 'Decision date updated' when 'pool' then 'Talent pool' when 'not' then 'Not proceed'
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
    'decide_by', (select c.decide_by from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null),
    'decide_note', (select c.decide_note from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null),
    'decide_moved', (select true from public.hiring_candidates c where c.id = i.candidate_id and i.held_at is not null and c.decide_moved_at is not null)));
$$;
revoke all on function public.hiring_interview_row(public.hiring_interviews) from public, anon, authenticated;

create or replace function public.hiring_mail_prepare(p_interview uuid, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_kind = 'invite' and public.hiring_interview_state(i) not in ('invited', 'none') then return jsonb_build_object('error', 'not-open'); end if;
  if p_kind in ('confirm', 'rescheduled') and i.state <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed'); end if;
  if p_kind in ('confirm', 'rescheduled') and i.mode = 'online' and i.meeting_link is null then return jsonb_build_object('error', 'no-meet'); end if;
  /* The time changed (2026-11-22): a confirmed interview not yet held that
     was moved, its previous time and its new one. */
  if p_kind = 'rescheduled' and (i.moved_from is null or i.held_at is not null) then return jsonb_build_object('error', 'not-moved'); end if;
  if p_kind in ('held', 'moved') and (i.held_at is null or c.decide_by is null or c.outcome is not null) then
    return jsonb_build_object('error', 'not-held');
  end if;
  /* A cancellation is told only of a confirmed interview, and only while no
     newer interview has been sent. */
  if p_kind = 'cancelled' and (i.state <> 'cancelled' or i.approved_at is null or i.picked is null) then
    return jsonb_build_object('error', 'not-cancelled');
  end if;
  if p_kind = 'cancelled' and exists (select 1 from public.hiring_interviews j where j.candidate_id = i.candidate_id
       and j.id <> i.id and j.invited_at > i.invited_at and j.state not in ('cancelled', 'replaced')) then
    return jsonb_build_object('error', 'replaced');
  end if;
  if p_kind not in ('invite', 'confirm', 'rescheduled', 'held', 'moved', 'cancelled') then return jsonb_build_object('error', 'bad-kind'); end if;
  return jsonb_build_object('id', i.id, 'kind', p_kind, 'to', c.email, 'name', c.name, 'position', c.position,
    'key', c.link_key, 'mode', i.mode, 'minutes', i.minutes, 'note', i.note, 'link', case when p_kind <> 'cancelled' then i.meeting_link end,
    'times', (select jsonb_agg(public.hiring_when(s) order by s) from unnest(i.slots) s),
    'when', case when i.picked is not null then public.hiring_when(i.slots[i.picked]) end,
    'was', case when p_kind = 'rescheduled' then public.hiring_when(i.moved_from) end,
    'moved_key', case when p_kind = 'rescheduled' then (extract(epoch from i.moved_at) * 1000)::bigint end,
    'reply_by', case when p_kind = 'invite' and i.state = 'invited' then public.hiring_when(i.reply_by) end,
    'decide_by', case when p_kind in ('held', 'moved') then public.hiring_when(c.decide_by) end,
    'decide_note', case when p_kind = 'moved' then c.decide_note end,
    'sender', me.name, 'system', coalesce(me.system, false));
end $$;
revoke all on function public.hiring_mail_prepare(uuid, text) from public, anon;
grant execute on function public.hiring_mail_prepare(uuid, text) to authenticated;

create or replace function public.hiring_mail_done(p_interview uuid, p_kind text, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare i public.hiring_interviews; v_role text;
begin
  select * into i from public.hiring_interviews where id = p_interview for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') or coalesce(p_kind, '') not in ('invite', 'confirm', 'rescheduled', 'held', 'moved', 'cancelled') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if p_kind = 'invite' then update public.hiring_interviews set invite_mail = p_status, invite_mail_at = now(), updated_at = now() where id = i.id;
  elsif p_kind = 'confirm' then update public.hiring_interviews set confirm_mail = p_status, confirm_mail_at = now(), updated_at = now() where id = i.id;
  /* The time changed, once sent, confirms the new time too (2026-11-22). */
  elsif p_kind = 'rescheduled' then update public.hiring_interviews set reschedule_mail = p_status, reschedule_mail_at = now(),
    confirm_mail = case when p_status = 'sent' then 'sent' else confirm_mail end,
    confirm_mail_at = case when p_status = 'sent' then now() else confirm_mail_at end, updated_at = now() where id = i.id;
  elsif p_kind = 'cancelled' then update public.hiring_interviews set cancel_mail = p_status, cancel_mail_at = now(), updated_at = now() where id = i.id;
  else update public.hiring_interviews set held_mail = p_status, held_mail_at = now(), updated_at = now() where id = i.id; end if;
  perform public.hiring_log(i.candidate_id, 'candidate.email',
    case p_kind when 'invite' then 'Interview invitation' when 'confirm' then 'Interview confirmation'
      when 'rescheduled' then 'New interview time'
      when 'cancelled' then 'Interview cancellation' when 'held' then 'Decision date' else 'New decision date' end ||
    case p_status when 'sent' then ' emailed to the candidate.'
    when 'unknown' then ' sent to the candidate, but its delivery could not be verified.'
    else ' could not be emailed to the candidate.' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hiring_mail_done(uuid, text, text, text) from public, anon;
grant execute on function public.hiring_mail_done(uuid, text, text, text) to authenticated;

/* Change interview time (2026-11-22): as INTERVIEW TIME PENDING moved it,
   now stamping the previous time and the move for the Interview time
   changed email and the candidate's page. Moved back to the time it was
   moved from while no email has told the candidate of the move (the shared
   calendar refused it), the earlier record is put back. */
create or replace function public.hiring_interview_move(p_interview uuid, p_at timestamptz)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
  v_was timestamptz;
  v_undo boolean;
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
  v_undo := i.moved_from is not null and p_at = i.moved_from and i.reschedule_mail is null;
  update public.hiring_interviews set slots = array[p_at], picked = 1, state = 'confirmed',
    approved_by = case when i.state = 'confirmed' then i.approved_by else me.id end,
    approved_at = case when i.state = 'confirmed' then i.approved_at else now() end,
    moved_from = case when v_undo then i.moved_from_before else v_was end,
    moved_from_before = case when v_undo then null else i.moved_from end,
    moved_at = now(), reschedule_mail = null, reschedule_mail_at = null,
    confirm_mail = null, confirm_mail_at = null, updated_at = now()
   where id = i.id;
  update public.hiring_candidates set stage = 'interview', last_step_at = now(), updated_at = now() where id = c.id;
  perform public.hiring_log(c.id, 'candidate.interview', 'Interview time changed from ' || public.hiring_when(v_was) || ' to ' || public.hiring_when(p_at));
  return jsonb_build_object('ok', true, 'mode', i.mode, 'was', v_was, 'at', p_at, 'meet', i.meeting_event_id is not null);
end $$;
revoke all on function public.hiring_interview_move(uuid, timestamptz) from public;
grant execute on function public.hiring_interview_move(uuid, timestamptz) to authenticated;

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

-- END OF INTERVIEW TIME CHANGED EMAIL -----------------------------------------

select public.functions_tidy();
