-- ===========================================================================
-- CANDIDATE EMAILS (2026-11-21)
-- ===========================================================================
-- WHY: the user, 2026-11-21, approving the send switches' model on a
-- mockup: "the interviews emails ... should all be automatic emails", and
-- an automatic step "should be continued, just to show an alert". The nine
-- hiring emails to a candidate asked the group's Send email and Send by
-- email as if a colleague wrote them; their words were typed in hiring-mail.
--
-- WHAT IT CHANGES
--   * `hiring_email_templates` (kind, on_send, subject, body; RLS on, no
--     policy, no grant): each candidate email's words and whether it is sent,
--     seeded with the words hiring-mail sends today, unchanged: Interview
--     invitation (`invite`), Interview confirmed (`confirm`), Thank you for
--     your interview (`held`), Decision date updated (`moved`), Interview
--     cancelled (`cancelled`), Keep in talent pool (`pool`) and Not proceed
--     (`not`), the two outcomes; Employment document (`doc`) and Employment
--     document sent again (`doc_again`); Document confirmed (`confirmed`);
--     Document expired (`expired`).
--   * `template_fields('candidate')` (and `template_fields_all`, restated):
--     the fields hiring-mail fills.
--   * `hiring_mail_gate(p_kinds)` (the team's and the service role's): the
--     automatic rule, `auto` (`auto_send_on('email')`: the portal's Email and
--     Automatic emails), `hand` (`send_ok('email')`: the portal's Email, Send
--     by email and the group's Send email, for an email sent again by hand),
--     and each kind's switch and words. hiring-mail sends a step's email only
--     where `auto` and its kind are on, else files it Not sent (`off: ...`),
--     the step itself never held; Send again and Email candidate ask `hand`.
--   * `hiring_mail_prepare`, `hiring_outcome_mail_prepare`,
--     `hiring_doc_mail_prepare` and `hiring_confirmed_mail_prepare`
--     (restated) no longer refuse `send-off`: the gate decides.
--   * `hiring_email_templates_get()` and `hiring_email_templates_save(p_rows)`
--     (`team.settings`): Settings, Messages: Email templates, Candidates;
--     each save checked against `template_fields('candidate')`, filed
--     `team.changed` under Candidate emails.
--
-- ORDER: this file, then hiring-mail, then the pages. Between this file and
-- hiring-mail, hiring-mail v(old) sends with its own words and no switch
-- (as an automatic send would with every switch on, the live state). An
-- old page meets the same answers. Safe to run twice.
--
-- ROLLBACK: restore the four prepares and `template_fields`,
-- `template_fields_all` from their bands; drop `hiring_email_templates_save`,
-- `hiring_email_templates_get`, `hiring_mail_gate` and
-- `hiring_email_templates`; deploy hiring-mail's previous version.

create table if not exists public.hiring_email_templates (
  kind        text primary key check (kind in ('invite', 'confirm', 'held', 'moved', 'cancelled', 'pool', 'not',
                                                'doc', 'doc_again', 'confirmed', 'expired')),
  on_send     boolean not null default true,
  subject     text not null,
  body        text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
alter table public.hiring_email_templates enable row level security;
revoke all on table public.hiring_email_templates from public, anon, authenticated;
insert into public.hiring_email_templates (kind, subject, body) values
  ('invite', 'Interview invitation: {position}',
   E'Dear {candidate name},\n\nThank you for your application for the position of {position}. ADspace would like to invite you to an interview of {interview length} minutes {where} at one of the following times:\n\n{times}\n\n{note}\n\nPlease choose a time on your application page by {reply by} (Malaysia time). If none of these times is suitable, please indicate this on the same page.\n\n{button}\n\n{sign-off}'),
  ('confirm', 'Interview confirmed: {position}',
   E'Dear {candidate name},\n\nYour interview for the position of {position} is confirmed for {time} (Malaysia time), for {interview length} minutes.\n\n{place}\n\n{note}\n\nThe details are also on your application page.\n\n{button}\n\n{sign-off}'),
  ('held', 'Thank you for your interview: {position}',
   E'Dear {candidate name},\n\nThank you for attending the interview for the position of {position}.\n\nADspace will inform you of the outcome by {decision date} (Malaysia time).\n\nThe details are also on your application page.\n\n{button}\n\n{sign-off}'),
  ('moved', 'Decision date updated: {position}',
   E'Dear {candidate name},\n\nThank you for your patience following the interview for the position of {position}. ADspace requires additional time to consider your application.\n\nADspace will now inform you of the outcome by {decision date} (Malaysia time).\n\n{note}\n\nThe details are also on your application page.\n\n{button}\n\n{sign-off}'),
  ('cancelled', 'Interview cancelled: {position}',
   E'Dear {candidate name},\n\nYour interview for the position of {position} on {time} (Malaysia time) has been cancelled. {google meet line}\n\nADspace will contact you to arrange another time.\n\n{sign-off}'),
  ('pool', 'Your application: {position}',
   E'Dear {candidate name},\n\nThank you for your interest in the position of {position} and for the time you have given ADspace. There is no suitable opening for you at this time. ADspace would like to keep your application for {months} months and may contact you about future positions.\n\nPlease indicate on your application page whether you agree. If you do not agree, your details will be deleted.\n\n{button}\n\n{sign-off}'),
  ('not', 'Your application: {position}',
   E'Dear {candidate name},\n\nThank you for your interest in the position of {position} and for the time you have given ADspace. After careful consideration, ADspace will not be proceeding with your application.\n\nADspace wishes you every success in your search.\n\n{sign-off}'),
  ('doc', '{document}: {reference}',
   E'Dear {candidate name},\n\nADspace is pleased to send you an {document} for the position of {position}, reference {reference}.\n\nPlease read it on your application page and {what to do} by {reply by}. For your privacy, the page will ask for a code sent to this email address before it shows the document.\n\n{button}\n\n{sign-off}'),
  ('doc_again', '{document}: {reference}',
   E'Dear {candidate name},\n\nYour {document} {reference} has been sent to you again {for what}.\n\n{reason}\n\nPlease read it on your application page and {what to do} by {reply by}. For your privacy, the page will ask for a code sent to this email address before it shows the document.\n\n{button}\n\n{sign-off}'),
  ('confirmed', '{document} confirmed: {reference}',
   E'Dear {candidate name},\n\nYour {document} {reference} for the position of {position} has been confirmed and countersigned by ADSPACE PLT.\n\nThe confirmed copy may be read on your application page. For your privacy, the page will ask for a code sent to this email address before it shows the document.\n\n{button}\n\n{sign-off}'),
  ('expired', '{document} expired: {reference}',
   E'Dear {candidate name},\n\nThe {document} {reference} dated {document date} has expired, as no reply was received by {reply by} (Malaysia time).\n\nPlease contact ADspace at {contact}.\n\n{sign-off}')
on conflict (kind) do nothing;

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
      'time', 'place', 'google meet line', 'decision date', 'months', 'document', 'reference', 'what to do', 'for what',
      'reason', 'document date', 'contact', 'sign-off', 'button']
  end $$;
revoke all on function public.template_fields(text) from public, anon, authenticated;

create or replace function public.template_fields_all() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_team() then jsonb_build_object(
    'supplier', to_jsonb(public.template_fields('supplier')),
    'client', to_jsonb(public.template_fields('client')),
    'free', to_jsonb(public.template_fields('free')),
    'invoice', to_jsonb(public.template_fields('invoice')),
    'creator-details', to_jsonb(public.template_fields('creator-details')),
    'creator-booking', to_jsonb(public.template_fields('creator-booking')),
    'meeting', to_jsonb(public.template_fields('meeting')),
    'code', to_jsonb(public.template_fields('code')),
    'candidate', to_jsonb(public.template_fields('candidate'))) end $$;
revoke all on function public.template_fields_all() from public, anon;
grant execute on function public.template_fields_all() to authenticated;

/* The automatic rule for a candidate email, asked by hiring-mail as the
   caller (a step's email) or as the service role (the expiry drain), and by
   the console to warn before a step: `auto` the portal's Email and Automatic
   emails, `hand` an email sent again by hand (the portal's Email, Send by
   email and the group's Send email), and each kind's switch and words. */
create or replace function public.hiring_mail_gate(p_kinds text[])
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not (public.is_team() or coalesce(auth.jwt() ->> 'role', '') = 'service_role') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'auto', public.auto_send_on('email'),
      'hand', case when public.is_team() then public.send_ok('email') else false end,
      'tpl', coalesce((select jsonb_object_agg(t.kind, jsonb_build_object('on', t.on_send, 'subject', t.subject, 'body', t.body))
        from public.hiring_email_templates t where t.kind = any (coalesce(p_kinds, '{}'::text[]))), '{}'::jsonb)) end
$$;
revoke all on function public.hiring_mail_gate(text[]) from public, anon;
grant execute on function public.hiring_mail_gate(text[]) to authenticated, service_role;

create or replace function public.hiring_email_templates_get()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'on', t.on_send, 'subject', t.subject, 'body', t.body, 'updated_at', t.updated_at, 'updated_by', m.name)
      order by array_position(array['invite', 'confirm', 'cancelled', 'held', 'moved', 'pool', 'not', 'doc', 'doc_again', 'confirmed', 'expired'], t.kind))
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
        when 'cancelled' then 'Interview cancelled' when 'held' then 'Thank you for your interview'
        when 'moved' then 'Decision date updated' when 'pool' then 'Keep in talent pool' when 'not' then 'Not proceed'
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

/* The four prepares, each restated with its `send-off` refusal taken out:
   the gate decides (hiring-mail). Nothing else in them changes. */
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
       and j.id <> i.id and j.invited_at > i.invited_at and j.state not in ('cancelled', 'replaced')) then
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
revoke all on function public.hiring_mail_prepare(uuid, text) from public, anon;
grant execute on function public.hiring_mail_prepare(uuid, text) to authenticated;

create or replace function public.hiring_outcome_mail_prepare(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
begin
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.outcome not in ('pool', 'not') then return jsonb_build_object('error', 'no-email'); end if;
  return jsonb_build_object('id', c.id, 'kind', c.outcome, 'to', c.email, 'name', c.name, 'position', c.position, 'key', c.link_key,
    'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12),
    'sender', me.name, 'system', coalesce(me.system, false));
end $$;
revoke all on function public.hiring_outcome_mail_prepare(uuid) from public, anon;
grant execute on function public.hiring_outcome_mail_prepare(uuid) to authenticated;

create or replace function public.hiring_doc_mail_prepare(p_doc uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; c public.hiring_candidates; v_role text;
begin
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
revoke all on function public.hiring_doc_mail_prepare(uuid) from public, anon;
grant execute on function public.hiring_doc_mail_prepare(uuid) to authenticated;

create or replace function public.hiring_confirmed_mail_prepare(p_doc uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; c public.hiring_candidates; v_role text;
begin
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

-- END OF CANDIDATE EMAILS -------------------------------------------------

select public.functions_tidy();
