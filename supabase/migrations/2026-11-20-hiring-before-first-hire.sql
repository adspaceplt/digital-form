-- ===========================================================================
-- HIRING BEFORE THE FIRST HIRE (2026-11-20)
-- ===========================================================================
-- WHY: the user, 2026-11-20: "Check before the first real hire: these parts,
-- fix all" (the coordinator's thirteen points on the hiring flow).
--
-- WHAT IT CHANGES
--   * A reply-by ends at 6:00pm Malaysia time on its day
--     (`hiring_day_end`): an invitation's (`hiring_reply_by`, never past the
--     last time offered) and a document's (`hiring_doc_send`,
--     `hiring_doc_send_back`); `hiring_doc_mail_prepare` writes it with its
--     weekday and time, and answers the reason a document was sent back.
--   * `careers_read` answers the careers mailbox (`contact`) on every answer,
--     a refusal's too, for the candidate page's "Please contact ADspace at
--     {address}."; and `pool_declined` where the candidate declined the
--     talent pool.
--   * `hiring_invite` and `hiring_decide` (Keep in talent pool, Not proceed)
--     cancel a confirmed interview not yet held, as they cancel an open one;
--     the page takes its Google Meet off first and tells the candidate.
--   * An Employment Offer or Contract past its reply-by is told to the
--     Owners and the Hiring part once (`hiring_docs_expire`, pg_cron
--     `hiring-docs-expire`, every fifteen minutes; `expired_told_at`), and
--     the candidate is emailed (`hiring-mail` `drain`, woken by
--     `hiring_mail_kick` with the wake secret; `hiring_expire_mail_claim`,
--     `hiring_expire_mail_done`, the service role's; `expire_mail`). An offer
--     declined is told the same way, with the next step.
--   * `hiring_tell`: every candidate notice reaches the Hiring part's
--     holders as well as the Owners.
--   * Make colleague carries the confirmed contract's salary into Personnel
--     (trigger `hiring_candidates_pay_to_personnel`, never shown or filed as
--     a figure; a salary already set is left alone).
--   * The Welcome Kit's seed words, each line only where it still holds the
--     seed (`2026-11-20-hiring-before-first-hire-preview.sql` reports each).
--
-- ORDER: this file, then hiring-mail (the drain and the reason), then the
-- pages. An old page's Send new times leaves the confirmed interview to this
-- file, which cancels it without taking its Meet off. Safe to run twice.
--
-- ROLLBACK: unschedule `hiring-docs-expire`; drop `hiring_docs_expire`,
-- `hiring_mail_kick`, `hiring_expire_mail_claim`, `hiring_expire_mail_done`,
-- `hiring_day_end`, the trigger and its function; run `hiring_reply_by`
-- from INTERVIEW REPLY-BY, `hiring_doc_send`, `hiring_doc_send_back` and
-- `careers_doc_answer` from HIRING OFFERS AND CONTRACTS, `hiring_invite` and
-- `hiring_tell` from HIRING: INTERVIEWS, `hiring_doc_mail_prepare`,
-- `hiring_decide` and `careers_read` from HIRING: CONFIRMED AND CANCELLED
-- EMAILS again. The Welcome Kit's words are the team's to edit back. The
-- columns may stay.
-- ===========================================================================

/* The end of a working reply: 6:00pm Malaysia time, n days after a moment's day. */
create or replace function public.hiring_day_end(p_at timestamptz, p_days int)
returns timestamptz language sql stable security definer set search_path = public as $$
  select (((p_at at time zone 'Asia/Kuala_Lumpur')::date + coalesce(p_days, 0)) + time '18:00') at time zone 'Asia/Kuala_Lumpur';
$$;
revoke all on function public.hiring_day_end(timestamptz, int) from public, anon, authenticated;

alter table public.hiring_docs add column if not exists expired_told_at timestamptz;
alter table public.hiring_docs add column if not exists expire_mail text;
alter table public.hiring_docs add column if not exists expire_mail_at timestamptz;

do $$
begin
  if to_regclass('public.system_emails') is not null then
    alter table public.system_emails drop constraint if exists system_emails_kind_check;
    alter table public.system_emails add constraint system_emails_kind_check
      check (kind in ('hiring_invite', 'hiring_confirm', 'hiring_pool', 'hiring_not', 'hiring_doc',
                      'hiring_code', 'invite_team', 'invite_client', 'hiring_held', 'hiring_moved',
                      'hiring_confirmed', 'hiring_cancelled', 'hiring_expired'));
  end if;
end $$;

/* An invitation's reply-by: 6:00pm on the setting's days after it was made,
   or the last time offered where that comes first. */
create or replace function public.hiring_reply_by(p_invited timestamptz, p_slots timestamptz[])
returns timestamptz language sql stable security definer set search_path = public as $$
  select least(public.hiring_day_end(p_invited, coalesce(public.app_setting('hiring_reply_days',
           (p_invited at time zone 'Asia/Kuala_Lumpur')::date)::int, 3)),
         (select max(s) from unnest(p_slots) s));
$$;
revoke all on function public.hiring_reply_by(timestamptz, timestamptz[]) from public, anon, authenticated;

create or replace function public.hiring_doc_send(p_doc uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  d public.hiring_docs;
  o public.hiring_docs;
  c public.hiring_candidates;
  v_role text;
  v_serial text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  if not exists (select 1 from public.hiring_doc_pay p where p.doc_id = d.id) then return jsonb_build_object('error', 'no-pay'); end if;
  select * into c from public.hiring_candidates where id = d.candidate_id for update;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage <> 'offer' then return jsonb_build_object('error', 'not-offer'); end if;
  if d.replaces is not null then
    select * into o from public.hiring_docs where id = d.replaces for update;
    if o.id is null or o.state not in ('sent', 'withdrawn', 'declined', 'signed') then return jsonb_build_object('error', 'replaced'); end if;
    v_serial := o.serial;
    update public.hiring_docs set state = 'void', void_note = 'Replaced', voided_at = now(), voided_by = me.name, updated_at = now()
     where id = o.id;
  else
    v_serial := public.hiring_doc_serial(d.kind);
  end if;
  update public.hiring_docs set state = 'sent', serial = v_serial, sent_by = me.id, sent_at = now(),
    reply_by = public.hiring_day_end(now(), coalesce((d.terms->>'reply_days')::int, 3)), mail = null, mail_at = null, updated_at = now()
   where id = d.id returning * into d;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = c.id;
  perform public.hiring_log(c.id, 'candidate.document', (case d.kind when 'offer' then 'Employment Offer ' else 'Employment Contract ' end) || v_serial || ' sent');
  return jsonb_build_object('ok', true, 'row', public.hiring_doc_row(d));
end $$;
grant execute on function public.hiring_doc_send(uuid) to authenticated;

create or replace function public.hiring_doc_send_back(p_doc uuid, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc for update;
  if d.id is null then return jsonb_build_object('error', 'gone'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'signed' then return jsonb_build_object('error', 'not-signed'); end if;
  if char_length(btrim(coalesce(p_note, ''))) not between 2 and 500 then return jsonb_build_object('error', 'bad-note'); end if;
  update public.hiring_docs set state = 'sent', history = history || jsonb_build_array(jsonb_build_object('signed', signed, 'at', signed_at,
      'returned_at', now(), 'returned_by', me.name, 'note', btrim(p_note))),
    signed = null, signed_at = null, answered_at = null, returned_at = now(), returned_by = me.name, returned_note = btrim(p_note),
    reply_by = public.hiring_day_end(now(), coalesce((d.terms->>'reply_days')::int, 3)), updated_at = now()
   where id = d.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
  perform public.hiring_log(d.candidate_id, 'candidate.document', d.serial || ' sent back: ' || btrim(p_note));
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_send_back(uuid, text) to authenticated;

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
    'position', d.terms->>'position', 'key', c.link_key, 'reply_by', public.hiring_when(d.reply_by),
    'returned', d.returned_note is not null, 'returned_note', d.returned_note, 'sent_key', extract(epoch from coalesce(d.returned_at, d.sent_at))::bigint,
    'sender', me.name, 'system', coalesce(me.system, false));
end $$;
grant execute on function public.hiring_doc_mail_prepare(uuid) to authenticated;

/* The careers mailbox on every answer, a refusal's too (2026-11-20). */
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
  update public.hiring_candidates set stage = case when stage in ('new', 'pool', 'invited') then 'invited' else stage end,
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
      pool_consent = null, pool_until = null, outcome_mail = null, outcome_mail_at = null,
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
    pool_consent = case when p_outcome = 'pool' then 'asked' end, pool_until = null, outcome_mail = null, outcome_mail_at = null,
    decide_by = null, decide_note = null, decide_soon_at = null, decide_due_at = null, decide_moved_at = null,
    last_step_at = now(), updated_at = now()
   where id = c.id;
  update public.hiring_interviews set state = 'cancelled', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and (state in ('invited', 'picked', 'none') or (state = 'confirmed' and held_at is null));
  update public.hiring_docs set state = 'withdrawn', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and state = 'sent';
  perform public.hiring_log(c.id, 'candidate.decided',
    case p_outcome when 'proceed' then 'Proceed' when 'pool' then 'Keep in talent pool' else 'Not proceed' end);
  return jsonb_build_object('ok', true, 'was', c.outcome, 'email', p_outcome in ('pool', 'not'));
end $$;
grant execute on function public.hiring_decide(uuid, text, text) to authenticated;

create or replace function public.careers_doc_answer(p_key text, p_doc uuid, p_view text, p_answer text, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  d public.hiring_docs := public.careers_doc_of(p_key, p_doc);
  s public.hiring_doc_codes;
  p public.hiring_doc_pay;
  pl jsonb := coalesce(p_payload, '{}'::jsonb);
  v_name text := btrim(coalesce(pl->>'name', ''));
  v_id text := upper(btrim(coalesce(pl->>'id_no', '')));
  v_sig text := coalesce(pl->>'signature', '');
  v_at timestamptz := now();
  v_title text;
begin
  if d.id is null then return jsonb_build_object('error', 'not_found'); end if;
  s := public.careers_doc_view(d.id, p_view);
  if s.id is null then return jsonb_build_object('error', 'code-needed'); end if;
  select * into d from public.hiring_docs where id = d.id for update;
  if d.state <> 'sent' then return jsonb_build_object('error', 'answered'); end if;
  if d.reply_by <= now() then return jsonb_build_object('error', 'expired'); end if;
  v_title := case d.kind when 'offer' then 'Employment Offer' else 'Employment Contract' end;
  if p_answer = 'decline' then
    if d.kind <> 'offer' then return jsonb_build_object('error', 'bad-request'); end if;
    if char_length(coalesce(pl->>'note', '')) > 500 then return jsonb_build_object('error', 'too-long'); end if;
    update public.hiring_docs set state = 'declined', answered_at = v_at, decline_note = nullif(btrim(coalesce(pl->>'note', '')), ''),
      updated_at = now() where id = d.id;
    update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
    insert into public.hiring_events (candidate_id, actor, action, detail)
    values (d.candidate_id, 'Candidate page', 'candidate.document', d.serial || ' declined');
    perform public.hiring_tell(d.candidate_id, 'hiring.declined', 'A candidate declined an offer',
      d.serial || ' was declined. Choose Not proceed, or send a new offer.');
    return jsonb_build_object('ok', true);
  end if;
  if coalesce(p_answer, '') not in ('accept', 'sign') or (p_answer = 'accept') <> (d.kind = 'offer') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if char_length(v_name) not between 2 and 120 then return jsonb_build_object('error', 'bad-name'); end if;
  if coalesce(pl->>'agree', '') <> 'true' then return jsonb_build_object('error', 'bad-agree'); end if;
  if d.kind = 'contract' then
    if v_id !~ '^([0-9]{6}-[0-9]{2}-[0-9]{4}|[A-Z0-9]{6,20})$' then return jsonb_build_object('error', 'bad-id'); end if;
    if v_sig !~ '^[MLQCZmlqcz0-9 .,-]+$' or char_length(v_sig) not between 8 and 30000 then return jsonb_build_object('error', 'bad-signature'); end if;
  end if;
  select * into p from public.hiring_doc_pay where doc_id = d.id;
  update public.hiring_docs set state = 'signed', signed_at = v_at, answered_at = v_at,
    signed = jsonb_strip_nulls(jsonb_build_object('via', 'online', 'name', v_name,
      'id_no', case when d.kind = 'contract' then v_id end, 'signature', case when d.kind = 'contract' then v_sig end,
      'record', jsonb_build_object('at', v_at, 'email', s.email, 'ip', nullif(public.request_ip(), ''),
        'country', nullif(public.request_country(), ''), 'device', public.seal_device(pl->>'device'),
        'fingerprint', upper(left(encode(digest(d.serial || d.terms::text || coalesce(p.basic::text, '') || coalesce(p.probation::text, '') ||
          v_name || v_at::text, 'sha256'), 'hex'), 16))))),
    updated_at = now()
   where id = d.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (d.candidate_id, 'Candidate page', 'candidate.document', d.serial || case d.kind when 'offer' then ' accepted' else ' signed' end || ' on the candidate page');
  perform public.hiring_tell(d.candidate_id, 'hiring.signed', case d.kind when 'offer' then 'A candidate accepted an offer' else 'A candidate signed a contract' end,
    d.serial || '. Open the candidate to confirm it.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.careers_doc_answer(text, uuid, text, text, jsonb) from public;
grant execute on function public.careers_doc_answer(text, uuid, text, text, jsonb) to anon, authenticated;

create or replace function public.hiring_tell(p_candidate uuid, p_kind text, p_title text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  insert into public.ops_notifications (team_member_id, kind, title, body, link)
  select t.id, p_kind, p_title, p_body, 'https://digital.adspace.me/admin/?s=team&tab=hiring&candidate=' || p_candidate
    from public.team_members t
   where t.active and t.removed_at is null and not t.system and (me.id is null or t.id <> me.id)
     and (exists (select 1 from public.hiring_people p where p.candidate_id = p_candidate and p.team_member_id = t.id and p.role = 'owner')
          /* The Hiring part's holders too (2026-11-20): an admin, or a group granted it. */
          or t.is_admin or coalesce(t.access->>'team.hiring', '') in ('work', 'manage'));
end $$;
revoke all on function public.hiring_tell(uuid, text, text, text) from public, anon, authenticated;

/* Make colleague carries the confirmed contract's salary into Personnel,
   never shown or filed as a figure; a salary already set is left alone. */
create or replace function public.hiring_candidates_pay_to_personnel()
returns trigger language plpgsql security definer set search_path = public as $$
declare p public.hiring_doc_pay;
begin
  if new.member_id is null or old.member_id is not null then return new; end if;
  select pay.* into p from public.hiring_doc_pay pay join public.hiring_docs d on d.id = pay.doc_id
   where d.candidate_id = new.id and d.kind = 'contract' and d.state = 'confirmed'
   order by d.confirmed_at desc limit 1;
  if p.doc_id is null then return new; end if;
  insert into public.personnel_salaries (team_member_id) values (new.member_id) on conflict (team_member_id) do nothing;
  update public.personnel_salaries set probation = coalesce(probation, p.probation), confirmed = coalesce(confirmed, p.basic), updated_at = now()
   where team_member_id = new.member_id and probation is null and confirmed is null;
  if found then
    insert into public.hiring_events (candidate_id, actor, action, detail)
    values (new.id, 'Portal', 'candidate.hired', 'Salary carried into Personnel from the Employment Contract');
  end if;
  return new;
end $$;
revoke all on function public.hiring_candidates_pay_to_personnel() from public, anon, authenticated;
drop trigger if exists hiring_candidates_pay_to_personnel on public.hiring_candidates;
create trigger hiring_candidates_pay_to_personnel after update of member_id on public.hiring_candidates
  for each row execute function public.hiring_candidates_pay_to_personnel();

/* hiring-mail's drain, woken after a document expires (as creator-mail's). */
create or replace function public.hiring_mail_kick()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'net' and p.proname = 'http_post') then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/hiring-mail', '{"action":"drain"}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-adspace-wake',
            coalesce((select s.value from public.app_secrets s where s.key = 'wake_secret'), ''));
exception when others then
  return;
end $$;
revoke all on function public.hiring_mail_kick() from public, anon, authenticated;

/* Every fifteen minutes: an offer or contract past its reply-by with no
   answer is told once to the Owners and the part, and queued to email the
   candidate. */
create or replace function public.hiring_docs_expire()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; v_word text;
begin
  for r in
    select d.id, d.candidate_id, d.kind, d.serial, d.terms->>'position' as position from public.hiring_docs d
      join public.hiring_candidates c on c.id = d.candidate_id
     where d.state = 'sent' and d.reply_by <= now() and d.expired_told_at is null and c.removed_at is null
     for update of d
  loop
    v_word := case r.kind when 'offer' then 'Employment Offer' else 'Employment Contract' end;
    update public.hiring_docs set expired_told_at = now(), expire_mail = 'queued', expire_mail_at = null where id = r.id;
    insert into public.hiring_events (candidate_id, actor, action, detail)
    values (r.candidate_id, 'Portal', 'candidate.document', r.serial || ' expired with no reply');
    perform public.hiring_tell(r.candidate_id, 'hiring.doc_expired', 'An ' || v_word || ' expired',
      r.serial || ' for the ' || coalesce(r.position, 'position') || ' candidate expired with no reply. Choose Not proceed, or send a new one.');
    n := n + 1;
  end loop;
  if n > 0 then perform public.hiring_mail_kick(); end if;
  return n;
end $$;
revoke all on function public.hiring_docs_expire() from public, anon, authenticated;

/* hiring-mail's drain (the service role's): the expiry emails queued,
   claimed once each, and closed. */
create or replace function public.hiring_expire_mail_claim()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v jsonb;
begin
  /* Only the rows this call takes: a second wake meanwhile claims none of them. */
  with due as (
    select d.id from public.hiring_docs d join public.hiring_candidates c on c.id = d.candidate_id
     where d.expire_mail = 'queued' and c.removed_at is null and c.link_key is not null
     order by d.expired_told_at limit 20 for update of d skip locked),
  took as (
    update public.hiring_docs d set expire_mail = 'sending', expire_mail_at = now() from due where d.id = due.id
    returning d.id, d.kind, d.serial, d.terms, d.sent_at, d.reply_by, d.candidate_id)
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'kind', 'expired', 'doc', t.kind, 'ref', t.serial, 'to', c.email,
      'name', c.name, 'position', t.terms->>'position', 'key', c.link_key,
      'sent', public.register_day((t.sent_at at time zone 'Asia/Kuala_Lumpur')::date), 'reply_by', public.hiring_when(t.reply_by),
      'contact', public.mail_sender('careers')->>'reply_to', 'system', true)), '[]'::jsonb) into v
    from took t join public.hiring_candidates c on c.id = t.candidate_id;
  return v;
end $$;
revoke all on function public.hiring_expire_mail_claim() from public, anon, authenticated;
grant execute on function public.hiring_expire_mail_claim() to service_role;

create or replace function public.hiring_expire_mail_done(p_doc uuid, p_status text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.hiring_docs;
begin
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-request'); end if;
  update public.hiring_docs set expire_mail = p_status, expire_mail_at = now() where id = p_doc and expire_mail = 'sending' returning * into d;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (d.candidate_id, 'Portal', 'candidate.email', d.serial || ' expiry' || case p_status when 'sent' then ' emailed'
    when 'unknown' then ' emailed, not confirmed' else ' not emailed' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hiring_expire_mail_done(uuid, text) from public, anon, authenticated;
grant execute on function public.hiring_expire_mail_done(uuid, text) to service_role;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: documents expire as they are read until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'hiring-docs-expire';
  perform cron.schedule('hiring-docs-expire', '*/15 * * * *', 'select public.hiring_docs_expire()');
end $$;

/* The Welcome Kit's seed words (the coordinator's review of the first hire):
   each line changed only where its section still holds the seed's words,
   so a kit the team edited in Settings is left as it is. */
update public.welcome_kit k set sections = (
  select jsonb_agg(case
    when e->>'title' = 'Welcome' and e->>'body' like '%We would rather you start sharp than start fast.%'
      then jsonb_set(e, '{body}', to_jsonb(replace(e->>'body', 'We would rather you start sharp than start fast.', 'ADspace would rather you start well than start fast.')))
    when e->>'title' = 'How we work' and e->>'body' like '%Zoom: Video meetings and client calls%'
      then jsonb_set(jsonb_set(e, '{title}', '"Ways of working"'), '{body}', to_jsonb(replace(e->>'body', 'Zoom: Video meetings and client calls', 'Google Meet: Video meetings and client calls')))
    when e->>'title' = 'Your first weeks' and e->>'body' like '%Months 1 to 3: Your probation, with weekly check-ins and a confirmation review%'
      then jsonb_set(e, '{body}', to_jsonb(replace(e->>'body', 'Months 1 to 3: Your probation, with weekly check-ins and a confirmation review', 'Probation: As set in your contract, with weekly check-ins and a confirmation review')))
    when e->>'title' = 'Key policies' and e->>'body' like '%Work days: Monday to Friday; Saturday and Sunday on demand%'
      then jsonb_set(e, '{body}', to_jsonb(replace(e->>'body', 'Work days: Monday to Friday; Saturday and Sunday on demand', 'Work days: Monday to Friday')))
    else e end order by o)
    from jsonb_array_elements(k.sections) with ordinality as x(e, o))
 where k.id = 1;

-- END OF HIRING BEFORE THE FIRST HIRE ------------------------------------------

select public.functions_tidy();
