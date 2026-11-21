-- ===========================================================================
-- HIRING AND RECORD LINES WORDED (2026-11-21)
-- ===========================================================================
-- WHY: the copy sweep of 20 and 21 Nov (DECISIONS 2026-11-21) left five
-- lines for a release that restates their functions. Each is drafted by
-- DESIGN.md §6: a complete sentence in the reader's words, a thing said once,
-- a figure in its own unit.
--
-- WHAT IT CHANGES (each function restated whole from its last band, every
-- refusal, grant and revoke kept, same signature; only the words move)
--   * The expired-document email's closing line, where the template still
--     reads as seeded (a template the team edited is left alone): Please
--     contact ADspace at {contact}. → Should you wish to discuss the
--     position, please contact ADspace at {contact}.
--   * The bell notices on an offer or contract declined, accepted, signed
--     or expired (`careers_doc_answer`, `hiring_docs_expire`) name the
--     document and the position before its reference: Employment Offer
--     ADHR/… for the position of {position}. Open the candidate to ….
--   * The candidate's record lines for an email (`hiring_mail_done`,
--     `hiring_outcome_mail_done`, `hiring_doc_mail_done`,
--     `hiring_confirmed_mail_done`, `hiring_expire_mail_done`): {What}
--     emailed to the candidate. / {What} sent to the candidate, but its
--     delivery could not be confirmed. / {What} could not be emailed to the
--     candidate. `hiring_interview_held`: Interview held. The decision is
--     due by {when}.
--   * Signed-in devices in the Activity record (`team_session_end`,
--     `team_sessions_end_all`, `team_sessions_idle_end`): {name} was signed
--     out on {device} ({code}). / {name} was signed out on n devices. /
--     n devices were signed out after 30 days unused. The action
--     (`team.changed`) and subject are unchanged, so ACTION_LABEL and
--     activity_section need nothing.
--   * The website quotation's bell line (`quote_website_create`) states the
--     start once: the preferred start date where one was given, else the
--     urgency.
--   * `app_settings_set` files Document IDs printed from as a date
--     (20 Nov 2026 → 1 Dec 2026 · from …), not as a percentage.
--
-- ORDER: this file alone (Management API). No page or edge function reads
-- these words, so an open page meets nothing new. Safe to run twice.
-- ROLLBACK: run each function from its band again (OFFER DECLINED OR EXPIRED
-- TOLD, HIRING: CONFIRMED AND CANCELLED EMAILS, the hiring bands, SIGN-IN
-- SESSIONS / SIGNED-IN DEVICES: IDLE AND ALL, START DATE ON THE QUOTATION,
-- WORKING HOURS) and put the template line back where it reads as worded
-- here.
-- ===========================================================================

update public.hiring_email_templates
   set body = replace(body, E'\n\nPlease contact ADspace at {contact}.\n\n',
                      E'\n\nShould you wish to discuss the position, please contact ADspace at {contact}.\n\n')
 where kind = 'expired' and updated_by is null
   and body = E'Dear {candidate name},\n\nThe {document} {reference} dated {document date} has expired, as no reply was received by {reply by} (Malaysia time).\n\nPlease contact ADspace at {contact}.\n\n{sign-off}';

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
    perform public.hiring_tell_once(d.candidate_id, 'hiring.declined', 'A candidate declined an offer',
      v_title || ' ' || d.serial || coalesce(' for the position of ' || nullif(btrim(d.terms->>'position'), ''), '') ||
      '. Open the candidate to decide the next step.', 'hiring.declined:' || d.id);
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
    v_title || ' ' || d.serial || coalesce(' for the position of ' || nullif(btrim(d.terms->>'position'), ''), '') ||
    '. Open the candidate to confirm it.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.careers_doc_answer(text, uuid, text, text, jsonb) from public;
grant execute on function public.careers_doc_answer(text, uuid, text, text, jsonb) to anon, authenticated;

create or replace function public.hiring_docs_expire()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select d.id, d.candidate_id, d.kind, d.serial, d.terms->>'position' as position from public.hiring_docs d
      join public.hiring_candidates c on c.id = d.candidate_id
     where d.state = 'sent' and d.reply_by <= now() and d.expired_told_at is null and c.removed_at is null
     for update of d
  loop
    update public.hiring_docs set expired_told_at = now(), expire_mail = 'queued', expire_mail_at = null where id = r.id;
    insert into public.hiring_events (candidate_id, actor, action, detail)
    values (r.candidate_id, 'Portal', 'candidate.document', r.serial || ' expired with no reply');
    perform public.hiring_tell_once(r.candidate_id, 'hiring.doc_expired',
      case r.kind when 'offer' then 'An offer expired with no reply' else 'A contract expired with no reply' end,
      case r.kind when 'offer' then 'Employment Offer ' else 'Employment Contract ' end || r.serial ||
      coalesce(' for the position of ' || nullif(btrim(r.position), ''), '') || '. Open the candidate to decide the next step.', 'hiring.doc_expired:' || r.id);
    n := n + 1;
  end loop;
  if n > 0 then perform public.hiring_mail_kick(); end if;
  return n;
end $$;
revoke all on function public.hiring_docs_expire() from public, anon, authenticated;

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
    case p_kind when 'invite' then 'Interview invitation' when 'confirm' then 'Interview confirmation'
      when 'cancelled' then 'Interview cancellation' when 'held' then 'Decision date' else 'New decision date' end ||
    case p_status when 'sent' then ' emailed to the candidate.'
    when 'unknown' then ' sent to the candidate, but its delivery could not be confirmed.'
    else ' could not be emailed to the candidate.' end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_mail_done(uuid, text, text, text) to authenticated;

create or replace function public.hiring_outcome_mail_done(p_id uuid, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_role text := public.hiring_role(p_id);
begin
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-request'); end if;
  update public.hiring_candidates set outcome_mail = p_status, outcome_mail_at = now(), updated_at = now() where id = p_id;
  perform public.hiring_log(p_id, 'candidate.email', 'Decision' || case p_status when 'sent' then ' emailed to the candidate.'
    when 'unknown' then ' sent to the candidate, but its delivery could not be confirmed.'
    else ' could not be emailed to the candidate.' end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_outcome_mail_done(uuid, text, text) to authenticated;

create or replace function public.hiring_doc_mail_done(p_doc uuid, p_status text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.hiring_docs; v_role text;
begin
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-request'); end if;
  update public.hiring_docs set mail = p_status, mail_at = now() where id = d.id;
  perform public.hiring_log(d.candidate_id, 'candidate.email', case d.kind when 'offer' then 'Employment Offer ' else 'Employment Contract ' end || d.serial || case p_status when 'sent' then ' emailed to the candidate.'
    when 'unknown' then ' sent to the candidate, but its delivery could not be confirmed.'
    else ' could not be emailed to the candidate.' end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.hiring_doc_mail_done(uuid, text, text) to authenticated;

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
  perform public.hiring_log(d.candidate_id, 'candidate.email', 'Confirmation of ' || case d.kind when 'offer' then 'Employment Offer ' else 'Employment Contract ' end || d.serial || case p_status when 'sent' then ' emailed to the candidate.'
    when 'unknown' then ' sent to the candidate, but its delivery could not be confirmed.'
    else ' could not be emailed to the candidate.' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hiring_confirmed_mail_done(uuid, text, text) from public, anon;
grant execute on function public.hiring_confirmed_mail_done(uuid, text, text) to authenticated;

create or replace function public.hiring_expire_mail_done(p_doc uuid, p_status text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.hiring_docs;
begin
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-request'); end if;
  update public.hiring_docs set expire_mail = p_status, expire_mail_at = now() where id = p_doc and expire_mail = 'sending' returning * into d;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (d.candidate_id, 'Portal', 'candidate.email', 'Expiry notice for ' || case d.kind when 'offer' then 'Employment Offer ' else 'Employment Contract ' end || d.serial || case p_status when 'sent' then ' emailed to the candidate.'
    when 'unknown' then ' sent to the candidate, but its delivery could not be confirmed.'
    else ' could not be emailed to the candidate.' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hiring_expire_mail_done(uuid, text) from public, anon, authenticated;
grant execute on function public.hiring_expire_mail_done(uuid, text) to service_role;

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
  perform public.hiring_log(c.id, 'candidate.interview', 'Interview held. The decision is due by ' || public.hiring_when(v_at) || '.');
  return jsonb_build_object('ok', true, 'decide_by', v_at);
end $$;
grant execute on function public.hiring_interview_held(uuid, timestamptz) to authenticated;

create or replace function public.team_session_end(p_id uuid, p_session uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  m      public.team_members;
  v_dev  text;
begin
  if me.id is null or not public.ops_granted('team.sessions', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.team_members t where t.id = p_id and t.erased_at is null;
  if m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(m.system, false) and m.id <> me.id then return jsonb_build_object('error', 'system-account'); end if;
  if p_session::text = coalesce(auth.jwt() ->> 'session_id', '') then return jsonb_build_object('error', 'own-session'); end if;
  select public.session_device(s.user_agent) into v_dev
    from auth.sessions s join auth.users u on u.id = s.user_id
   where s.id = p_session and lower(u.email) = lower(m.email);
  if v_dev is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from auth.sessions s where s.id = p_session;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Signed-in devices',
          m.name || ' was signed out on ' || v_dev || ' (' || left(p_session::text, 6) || ').');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_session_end(uuid, uuid) from public, anon, authenticated;
grant execute on function public.team_session_end(uuid, uuid) to authenticated;

create or replace function public.team_sessions_idle_end(p_now timestamptz default now())
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  v_days integer := coalesce(public.app_setting('session_idle_days', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::integer;
  v_n    integer := 0;
begin
  if v_days > 0 then
    delete from auth.sessions s
     using auth.users u
     where u.id = s.user_id
       and greatest(s.updated_at, s.refreshed_at at time zone 'UTC', s.created_at) < p_now - make_interval(days => v_days)
       and exists (select 1 from public.team_members t
                    where lower(t.email) = lower(u.email) and t.erased_at is null)
       and not exists (select 1 from public.team_members t
                        where lower(t.email) = lower(u.email) and coalesce(t.system, false));
    get diagnostics v_n = row_count;
    if v_n > 0 then
      insert into public.activity_log (actor, action, subject, detail)
      values ('system', 'team.changed', 'Signed-in devices',
              v_n || case when v_n = 1 then ' device was' else ' devices were' end || ' signed out after ' || v_days ||
              case when v_days = 1 then ' day' else ' days' end || ' unused.');
    end if;
  end if;
  perform public.job_beat('session-idle', true,
    case when v_days > 0 then v_n || ' signed out' else 'off' end);
  return v_n;
end $$;
revoke all on function public.team_sessions_idle_end(timestamptz) from public, anon, authenticated;

create or replace function public.team_sessions_end_all(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  m    public.team_members;
  v_n  integer := 0;
begin
  if me.id is null or not public.ops_granted('team.sessions', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.team_members t where t.id = p_id and t.erased_at is null;
  if m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if m.id = me.id or lower(m.email) = lower(me.email) then return jsonb_build_object('error', 'own-account'); end if;
  if coalesce(m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  delete from auth.sessions s
   using auth.users u
   where u.id = s.user_id and lower(u.email) = lower(m.email);
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('error', 'none'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Signed-in devices',
          m.name || ' was signed out on ' || v_n || case when v_n = 1 then ' device.' else ' devices.' end);
  return jsonb_build_object('ok', true, 'ended', v_n);
end $$;
revoke all on function public.team_sessions_end_all(uuid) from public, anon, authenticated;
grant execute on function public.team_sessions_end_all(uuid) to authenticated;

create or replace function public.quote_website_create(p_sel jsonb, p_contact jsonb, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name  text := btrim(regexp_replace(coalesce(p_contact->>'name', ''), '\s+', ' ', 'g'));
  v_email text := lower(btrim(coalesce(p_contact->>'email', '')));
  v_wa    text := public.quote_website_number(p_contact->>'whatsapp');
  v_brand text := btrim(regexp_replace(coalesce(p_contact->>'brand', ''), '\s+', ' ', 'g'));
  v_ind   text := nullif(btrim(coalesce(p_contact->>'industry', '')), '');
  v_lang  text := case when p_contact->>'lang' = 'zh' then 'zh' else 'en' end;
  v_sal   text := nullif(btrim(coalesce(p_contact->>'salutation', '')), '');
  v_start text := nullif(btrim(coalesce(p_contact->>'commence', '')), '');
  v_on_t  text := nullif(btrim(coalesce(p_contact->>'commence_on', '')), '');
  v_on    date;
  v_idem  text := nullif(btrim(coalesce(p_idem, '')), '');
  v_sel   jsonb;
  v_q     public.quotations;
  v_c     public.clients;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_r     jsonb;
  v_new   boolean := false;
begin
  if v_idem is null or length(v_idem) > 80 then return jsonb_build_object('error', 'bad-request'); end if;
  -- The quotation website covered (Page availability) makes nothing.
  if public.page_covered('quote') then return jsonb_build_object('error', 'unavailable'); end if;
  select * into v_q from public.quotations q
   where q.idem = v_idem and q.source = 'website' and lower(q.contact->>'email') = v_email;
  if v_q.id is not null then
    return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key, 'again', true);
  end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 160 then return jsonb_build_object('error', 'bad-email'); end if;
  if v_wa !~ '^(60(1[0-9]{8,9}|7[0-9]{7,8})|65[0-9]{8})$' then return jsonb_build_object('error', 'bad-whatsapp'); end if;
  if length(v_brand) < 2 or length(v_brand) > 120 then return jsonb_build_object('error', 'bad-brand'); end if;
  -- A name or brand is never a web address: both go into the WhatsApp the
  -- prospect is sent from ADspace's number (2026-10-26, audit).
  if v_name ~* public.quote_link_like() then return jsonb_build_object('error', 'bad-name'); end if;
  if v_brand ~* public.quote_link_like() then return jsonb_build_object('error', 'bad-brand'); end if;
  -- An industry on the list kept in Settings (INDUSTRIES, 2026-11-04).
  if v_ind is not null and not exists (select 1 from public.industries i where i.name = v_ind) then
    return jsonb_build_object('error', 'bad-industry');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-salutation');
  end if;
  -- When they plan to start: the console's Urgency to commence, for the
  -- team's planning; it changes no price. Left out by a page served before.
  if v_start is not null and v_start not in ('1_3', '3_6', '6_plus') then
    return jsonb_build_object('error', 'bad-commence');
  end if;
  -- A preferred start date, optional (PREFERRED START DATE, 2026-11-21):
  -- a day from today in Malaysia to the date ceiling, kept on the quotation
  -- it was asked on (START DATE ON THE QUOTATION, 2026-11-21).
  if v_on_t is not null then
    if v_on_t !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error', 'bad-start-date'); end if;
    begin
      v_on := v_on_t::date;
    exception when others then
      return jsonb_build_object('error', 'bad-start-date');
    end;
    if v_on < (now() at time zone 'Asia/Kuala_Lumpur')::date or v_on > date '2099-12-31' then
      return jsonb_build_object('error', 'bad-start-date');
    end if;
  end if;
  if coalesce((p_contact->>'consent')::boolean, false) is not true then return jsonb_build_object('error', 'consent'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if jsonb_typeof(p_sel->'once') = 'array' and jsonb_array_length(p_sel->'once') > 20
     or jsonb_typeof(p_sel->'extra') = 'object' and (select count(*) from jsonb_object_keys(p_sel->'extra')) > 10 then
    return jsonb_build_object('error', 'bad-selection');
  end if;

  -- What the price reads, and nothing else.
  v_sel := jsonb_strip_nulls(jsonb_build_object(
    'mix', case when jsonb_typeof(p_sel->'mix') = 'string' and length(p_sel->>'mix') <= 20 then p_sel->'mix' end,
    'plan', case when jsonb_typeof(p_sel->'plan') = 'string' and length(p_sel->>'plan') <= 80 then p_sel->'plan' end,
    'term', case when jsonb_typeof(p_sel->'term') in ('number', 'string') and length(p_sel->>'term') <= 4 then p_sel->'term' end,
    'budget', case when jsonb_typeof(p_sel->'budget') in ('number', 'string') and length(p_sel->>'budget') <= 12 then p_sel->'budget' end,
    'translate', case when jsonb_typeof(p_sel->'translate') = 'boolean' then p_sel->'translate' end,
    'platforms', (select jsonb_agg(distinct v) from jsonb_array_elements_text(
                    case when jsonb_typeof(p_sel->'platforms') = 'array' then p_sel->'platforms' else '[]'::jsonb end) v
                   where v in ('meta', 'tiktok', 'rednote', 'linkedin')),
    'langs', (select jsonb_agg(distinct l) from jsonb_array_elements_text(
                case when jsonb_typeof(p_sel->'langs') = 'array' then p_sel->'langs' else '[]'::jsonb end) l
               where l in ('en', 'zh', 'ms')),
    'extra', case when jsonb_typeof(p_sel->'extra') = 'object' then
               (select jsonb_object_agg(left(k, 80), p_sel->'extra'->k) from jsonb_object_keys(p_sel->'extra') k) end,
    'once', case when jsonb_typeof(p_sel->'once') = 'array' then
              (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('slug', left(o->>'slug', 80), 'qty', o->'qty')))
                 from jsonb_array_elements(p_sel->'once') o where jsonb_typeof(o) = 'object') end));

  -- Two posts at once are counted one after the other.
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || least(v_email, v_wa), 0));
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || greatest(v_email, v_wa), 0));
  if (select count(*) from public.quotations q
       where q.source = 'website' and q.issued_at > now() - interval '1 day'
         and (lower(q.contact->>'email') = v_email or q.contact->>'whatsapp' = '+' || v_wa)) >= 5 then
    return jsonb_build_object('error', 'limit');
  end if;

  -- A lead this person already is (the same contact holds both the email
  -- and the number), else a new one.
  select c.* into v_c from public.clients c
    join public.client_contacts k on k.client_id = c.id
   where c.stage in ('lead', 'contacted', 'proposal')
     and k.archived_at is null
     and lower(k.email) = v_email
     and public.quote_website_number(k.whatsapp) = v_wa
   order by c.created_at desc limit 1;
  if v_c.id is null then
    v_base := btrim(regexp_replace(lower(v_brand), '[^a-z0-9]+', '-', 'g'), '-');
    if v_base = '' then v_base := 'client'; end if;
    v_slug := v_base;
    while exists (select 1 from public.clients c where lower(c.slug) = v_slug) loop
      v_n := v_n + 1; v_slug := v_base || '-' || v_n;
    end loop;
    insert into public.clients (name, access_token, stage, industry, source, market, slug, deal_note, commence)
    values (v_brand, public.new_link_key(), 'lead', v_ind, 'website',
            case when v_wa like '65%' then 'SG' else 'MY' end, v_slug,
            'Quotation requested on the website.', v_start)
    returning * into v_c;
    insert into public.client_contacts (client_id, salutation, name, email, whatsapp, lang, is_primary)
    values (v_c.id, v_sal, v_name, v_email, '+' || v_wa, v_lang, true);
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.added', v_c.name, 'Website · ' || coalesce(v_sal || ' ', '') || v_name);
    v_new := true;
  end if;

  v_r := public.quotation_make(v_c.id, v_sel, v_idem, 'website', null,
    jsonb_strip_nulls(jsonb_build_object('salutation', v_sal, 'name', v_name, 'email', v_email,
      'whatsapp', '+' || v_wa, 'lang', v_lang, 'brand', v_brand)));
  if v_r ? 'error' then
    if v_new then raise exception using message = 'quote:' || (v_r->>'error'); end if;
    return v_r;
  end if;
  select * into v_q from public.quotations where id = (v_r->>'id')::uuid;
  -- A lead asking again says when it plans to start now, once its
  -- quotation is made (a refused one changes nothing).
  if not v_new and v_start is not null and v_c.commence is distinct from v_start then
    update public.clients set commence = v_start where id = v_c.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.edited', v_c.name, 'Urgency to commence: ' ||
      coalesce(public.quote_commence_word(v_c.commence), 'not set') || ' → ' || public.quote_commence_word(v_start));
  end if;
  -- The price waits for the team (the user, 2026-10-29: "the price
  -- shouldnt send out straight"): the quotation is owed a reply by working
  -- days, the team is told to review it, and the prospect is sent nothing
  -- until a colleague sends it (`quotation_send`).
  update public.quotations set reply_due = public.quote_reply_by(now()), commence_on = v_on where id = v_q.id
   returning * into v_q;
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation to review · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('Monthly incl. SST RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') || ' · ' || v_name
      || coalesce(' · Preferred start date ' || public.register_day(v_on),
                  ' · Starts ' || lower(public.quote_commence_word(v_start)), '')
      || ' · send by ' || public.register_day((v_q.reply_due at time zone 'Asia/Kuala_Lumpur')::date) || ', ' ||
      lower(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
    v_q.id::text);
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text; v_pre text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days', 'quote_valid_days', 'details_form_days', 'wa_repeat_hours',
    'bench_cpr_low', 'bench_cpr_mid', 'bench_cpr_high', 'bench_cpr_top', 'bench_msg_min', 'bench_msg_target', 'bench_msg_max',
    'bench_form_min', 'bench_form_target', 'bench_form_max', 'bench_cpm_min', 'bench_cpm_max', 'bench_cpl_rise',
    'bench_reels_share', 'bench_ad_spend_pct', 'bench_adset_daily', 'vic_lead_followup_hours', 'vic_proposal_followup_days', 'fx_sgd',
    'health_keep_months', 'health_leaver_months', 'abroad_days', 'abroad_remind_hours', 'analytics_from',
    'analytics_change_pct', 'analytics_churn_pct', 'quote_reply_days', 'quote_wa_day', 'client_email_on', 'ai_price_image', 'report_post_links',
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months', 'plan_db_mb', 'plan_db_alert_pct',
    'timely_pct', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'hiring_decision_days', 'verify_code_from',
    'work_start', 'work_end', 'work_lunch_min', 'work_weekend'];
  v_moved text[] := '{}';
  v_drop boolean; v_fw text; v_fv text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, case when v_k = 'fx_sgd' then 4 else 2 end) <> v_v
       or (v_k = 'fx_sgd' and (v_v < 0.5 or v_v > 10))
       or (v_k in ('lead_followup_hours', 'vic_lead_followup_hours') and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k in ('proposal_followup_days', 'vic_proposal_followup_days') and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k in ('meta_checks', 'client_email_on', 'report_post_links') and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'task_past_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_invite_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_link_days' and (v_v < 7 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_pool_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_keep_months' and (v_v < 1 or v_v > 36 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_mb' and (v_v < 100 or v_v > 1000000 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_alert_pct' and (v_v < 10 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_late_days' and (v_v < 0 or v_v > 30 or round(v_v, 1) <> v_v))
       or (v_k = 'stage_back_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_reply_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'session_idle_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_decision_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'quote_reply_days' and (v_v < 1 or v_v > 10 or v_v <> trunc(v_v)))
       or (v_k in ('creator_pay_days_myr', 'creator_pay_days_other') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k = 'quote_wa_day' and (v_v < 0 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'health_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'health_leaver_months' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_from' and (v_v < 202308 or v_v > 209912 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 12))
       or (v_k = 'verify_code_from' and (v_v < 20230814 or v_v > 20991231 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 31 or mod(trunc(v_v / 100), 100) not between 1 and 12))
       or (v_k in ('work_start', 'work_end') and (v_v < 0 or v_v > 2345 or v_v <> trunc(v_v) or mod(v_v, 100) not in (0, 15, 30, 45)))
       or (v_k = 'work_lunch_min' and (v_v < 0 or v_v > 180 or v_v <> trunc(v_v) or mod(v_v, 15) <> 0))
       or (v_k = 'work_weekend' and v_v not in (0, 1, 2))
       or (v_k = 'analytics_change_pct' and (v_v < 1 or v_v > 50 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_churn_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k in ('bench_reels_share') and (v_v < 0 or v_v > 100))
       or (v_k = 'bench_ad_spend_pct' and (v_v < 1 or v_v > 100))
       or (v_k = 'bench_cpl_rise' and (v_v < -100 or v_v > 100))
       or (v_k like 'bench_%' and v_k not in ('bench_reels_share', 'bench_ad_spend_pct', 'bench_cpl_rise') and (v_v < 0 or v_v > 10000)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  /* A working day ends after it starts, as the two stand on the From day. */
  if (p_values ? 'work_start' or p_values ? 'work_end')
     and coalesce((p_values ->> 'work_end')::numeric, public.app_setting('work_end', p_from))
      <= coalesce((p_values ->> 'work_start')::numeric, public.app_setting('work_start', p_from)) then
    return jsonb_build_object('error', 'bad-hours');
  end if;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      /* A planned change saved back to the value in force the day before is
         withdrawn: its row goes, rather than a second row restating it. */
      v_drop := p_from > v_today
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date = p_from)
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date < p_from)
        and public.app_setting(v_k, p_from - 1) = v_v;
      if v_drop then
        delete from public.app_settings s where s.key = v_k and s.from_date = p_from;
      else
        insert into public.app_settings (key, from_date, value, set_by, set_at)
        values (v_k, p_from, v_v, v_me.id, now())
        on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      end if;
      v_name := case v_k when 'lead_followup_hours' then 'Lead follow-up limit' when 'proposal_followup_days' then 'Proposal follow-up limit'
        when 'vic_lead_followup_hours' then 'VIC lead follow-up limit' when 'vic_proposal_followup_days' then 'VIC proposal follow-up limit'
        when 'sst_pct' then 'SST' when 'term_1_3' then 'Under 3 months' when 'term_4_5' then '3-month commitment'
        when 'term_6_11' then '6-month commitment' when 'term_12_23' then '12-month commitment' when 'term_18_23' then '18-month commitment' when 'term_24' then '24-month commitment'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input price per million tokens'
        when 'ai_price_out' then 'AI output price per million tokens' when 'ai_price_search' then 'AI web search price per thousand searches' when 'ai_price_image' then 'AI price per scene picture' when 'meta_checks' then 'Meta checks' when 'client_email_on' then 'Send by email' when 'report_post_links' then 'Posts linked to tasks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'hiring_pool_months' then 'Talent pool kept' when 'hiring_keep_months' then 'Closed candidates kept' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'quote_reply_days' then 'Contact within'
        when 'plan_db_mb' then 'Database plan' when 'plan_db_alert_pct' then 'Database alert'
        when 'timely_pct' then 'On time or early target' when 'timely_late_days' then 'Average lateness target'
        when 'stage_back_days' then 'Past dates on stage moves'
        when 'hiring_reply_days' then 'Interview reply time'
        when 'session_idle_days' then 'Signed-in devices'
        when 'hiring_decision_days' then 'Decision time'
        when 'creator_pay_days_myr' then 'Creator payment in MYR' when 'creator_pay_days_other' then 'Creator payment in other currencies'
        when 'wa_repeat_hours' then 'WhatsApp sent again'
        when 'quote_wa_day' then 'Website quotations on WhatsApp'
        when 'bench_cpr_low' then 'Property cost per result, tier 1 from' when 'bench_cpr_mid' then 'Property cost per result, tier 2 from'
        when 'bench_cpr_high' then 'Property cost per result, tier 3 from' when 'bench_cpr_top' then 'Property cost per result, tier 3 up to'
        when 'bench_msg_min' then 'Messaging cost per result, low' when 'bench_msg_target' then 'Messaging cost per result, target'
        when 'bench_msg_max' then 'Messaging cost per result, high' when 'bench_form_min' then 'Lead form cost per result, low'
        when 'bench_form_target' then 'Lead form cost per result, target' when 'bench_form_max' then 'Lead form cost per result, high'
        when 'bench_cpm_min' then 'Cost per 1,000 impressions, low' when 'bench_cpm_max' then 'Cost per 1,000 impressions, high'
        when 'bench_cpl_rise' then 'Yearly rise in cost per lead' when 'bench_reels_share' then 'Reels share of impressions'
        when 'bench_ad_spend_pct' then 'Ad spend share of the budget' when 'bench_adset_daily' then 'Minimum daily budget per ad set'
        when 'fx_sgd' then 'Singapore dollar rate'
        when 'health_keep_months' then 'Health check-ins kept' when 'health_leaver_months' then 'Leavers'' health data kept'
        when 'abroad_days' then 'Overseas approval' when 'abroad_remind_hours' then 'Overseas reminder'
        when 'analytics_from' then 'Analytics counts from'
        when 'verify_code_from' then 'Document IDs printed from'
        when 'work_start' then 'Working hours start' when 'work_end' then 'Working hours end'
        when 'work_lunch_min' then 'Lunch' when 'work_weekend' then 'Saturday and Sunday'
        when 'analytics_change_pct' then 'Analytics change threshold' when 'analytics_churn_pct' then 'Analytics quarterly churn alert'
        else 'Report due' end;
      v_pre := case when v_k = 'fx_sgd' then 'RM ' when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k = 'fx_sgd' then ' per S$1' when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours', 'abroad_remind_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days') then ' days'
        when v_k in ('quote_reply_days', 'creator_pay_days_myr', 'creator_pay_days_other', 'hiring_decision_days') then ' working days'
        when v_k = 'quote_wa_day' then ' per day'
        when v_k = 'plan_db_mb' then ' MB'
        when v_k = 'work_lunch_min' then ' minutes'
        when v_k in ('health_keep_months', 'hiring_pool_months', 'hiring_keep_months', 'health_leaver_months') then ' months'
        when v_pre <> '' then '' else '%' end;
      v_fw := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then case when v_was = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then coalesce(public.work_hours_word(v_k, v_was), 'not set')
              when v_k = 'analytics_from' then coalesce(substr(public.register_day(to_date(v_was::bigint::text, 'YYYYMM')), 3), 'not set')
              when v_k = 'verify_code_from' then coalesce(public.register_day(to_date(v_was::bigint::text, 'YYYYMMDD')), 'not set') else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit, 'not set') end;
      v_fv := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then case when v_v = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then public.work_hours_word(v_k, v_v)
              when v_k = 'analytics_from' then substr(public.register_day(to_date(v_v::bigint::text, 'YYYYMM')), 3)
              when v_k = 'verify_code_from' then public.register_day(to_date(v_v::bigint::text, 'YYYYMMDD')) else v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              case when v_drop then v_name || ': planned change withdrawn · ' || v_fw || ' from ' || public.register_day(p_from) ||
                ', stays ' || v_fv else
              case when v_k in ('analytics_from', 'verify_code_from') or (v_k like 'work\_%' and v_k <> 'work_lunch_min') then v_name || ': ' || v_fw || ' → ' || v_fv || ' · from ' || public.register_day(p_from) else
              v_name || ': ' || case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k in ('meta_checks', 'client_email_on', 'report_post_links') then '' else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit, 'not set') || ' → ' || v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' else 'FM999999990.99' end), '.') || v_unit ||
              ' · from ' || public.register_day(p_from) end end end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

-- END OF HIRING AND RECORD LINES WORDED ------------------------------------

select public.functions_tidy();
