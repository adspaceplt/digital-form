-- ===========================================================================
-- UNDO SEND — every email a colleague sends waits a minute (2026-11-28)
-- ===========================================================================
-- WHY: the user, 2026-11-28: "Can the 1 min delay apply not only to
-- candidates? Clients too… a nice gesture of could revert or cancel within a
-- minute." One mechanism for every email a colleague sends by hand or by a
-- step: a client's quotation, Letter of Offer or letter, an invoice email or
-- overdue reminder, a feedback request, Ask for details, a supplier's
-- emails, a New email, and a candidate's step emails, sent by hand and sent
-- again.
-- WHAT IT CHANGES
--   * `mail_queue` (RLS on, no policy, no grant): what Resend is sent, due
--     `send_undo_seconds` on (an app setting, 60), Queued, then Sending,
--     Sent, Failed or Not confirmed, or Cancelled; emptied once closed.
--   * The email's own row reads Queued and Cancelled (each log's status
--     check, a feedback request's mail_status; a candidate step's mail
--     state alike), so the Email log, a record's Emails and the Activity
--     record read them as they read Sent.
--   * `mail_queue_put` (the service role's, called by each sender once its
--     begin has filed the email as the caller), `mail_queue_claim` and
--     `mail_queue_close` (supplier-mail's drain), closing through each
--     sender's own close as the colleague who queued it; `mail_cancel`
--     (the sender, or Messages at Full Access; `sent` once the drain took
--     it); pg_cron `mail-queue` every minute wakes the drain only while an
--     email is due.
--   * Sent recently leaves a cancelled email out (supplier_email_prepare,
--     client_email_prepare, invoice_mail_begin; a feedback request's is
--     withdrawn); mail_sweep reads a queued email's time from its claim;
--     mail_log, team_emails_of and supplier_emails_of answer the sender's
--     id, so Cancel is drawn for the sender alone.
-- EXCLUDED, still immediate: codes, sign-in links and invitations, what a
--   client or visitor sends themselves, and what the portal sends by itself
--   (reminders, expiry emails, creator emails, alerts).
-- ORDER: this file, then supplier-mail, bukku-sync and hiring-mail, then
--   the pages. An open tab's send is queued and reads Sent as before, its
--   email going a minute later.
-- ROLLBACK: deploy the three functions before this release, then
--   select cron.unschedule('mail-queue'); update the queued rows' emails to
--   'sending' and run their drain once; drop table public.mail_queue; drop
--   function public.mail_queue_mark(public.mail_queue, text),
--   public.mail_queue_note(public.mail_queue, text, text),
--   public.mail_queue_put(jsonb), public.mail_queue_claim(int),
--   public.mail_queue_close(uuid, text, text, text),
--   public.mail_cancel(text, uuid), public.mail_queue_kick(),
--   public.mail_queue_due(); the status checks may stay wider. Safe to run
--   twice.

-- A queued email and a cancelled one are states of the email's own row, so
-- every list that reads the row (the Email log, a record's Emails, a
-- document's emailed line) reads them without a reader of its own.
alter table public.supplier_emails drop constraint if exists supplier_emails_status_check;
alter table public.supplier_emails add constraint supplier_emails_status_check
  check (status in ('queued', 'sending', 'sent', 'failed', 'unknown', 'delivered', 'opened', 'bounced', 'complained', 'cancelled'));
alter table public.client_emails drop constraint if exists client_emails_status_check;
alter table public.client_emails add constraint client_emails_status_check
  check (status in ('queued', 'sending', 'sent', 'failed', 'unknown', 'delivered', 'opened', 'bounced', 'complained', 'cancelled'));
alter table public.team_emails drop constraint if exists team_emails_status_check;
alter table public.team_emails add constraint team_emails_status_check
  check (status in ('queued', 'sending', 'sent', 'failed', 'unknown', 'delivered', 'opened', 'bounced', 'complained', 'cancelled'));
alter table public.invoice_emails drop constraint if exists invoice_emails_status_check;
alter table public.invoice_emails add constraint invoice_emails_status_check
  check (status in ('queued', 'sending', 'sent', 'failed', 'unknown', 'delivered', 'opened', 'bounced', 'complained', 'cancelled'));
alter table public.feedback_requests drop constraint if exists feedback_requests_mail_status_check;
alter table public.feedback_requests add constraint feedback_requests_mail_status_check
  check (mail_status in ('queued', 'sending', 'sent', 'failed', 'unknown', 'cancelled'));

/* The window, a Business setting (Settings, Business: Undo send), seeded
   once; read in force on the Malaysian day. */
insert into public.app_settings (key, from_date, value)
select 'send_undo_seconds', date '2023-08-14', 60
 where not exists (select 1 from public.app_settings s where s.key = 'send_undo_seconds');

/* The queue: one row an email, holding what Resend is sent (attachments
   included) until it goes, then emptied. RLS on, no policy, no grant: the
   functions below alone. */
create table if not exists public.mail_queue (
  id           uuid primary key default gen_random_uuid(),
  source       text not null check (source in ('supplier', 'client', 'invoice', 'manual', 'feedback', 'system')),
  log_id       uuid not null,
  close        jsonb not null default '{}'::jsonb,
  msg          jsonb not null default '{}'::jsonb,
  idem         text not null,
  to_name      text,
  what         text,
  status       text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'failed', 'unknown', 'cancelled')),
  send_at      timestamptz not null,
  queued_by    uuid references public.team_members (id) on delete set null,
  created_at   timestamptz not null default now(),
  claimed_at   timestamptz,
  closed_at    timestamptz,
  cancelled_by uuid references public.team_members (id) on delete set null,
  cancelled_at timestamptz,
  provider_id  text,
  error        text
);
alter table public.mail_queue enable row level security;
revoke all on public.mail_queue from public, anon, authenticated;
create unique index if not exists mail_queue_log_idx on public.mail_queue (source, log_id);
create index if not exists mail_queue_due_idx on public.mail_queue (send_at) where status = 'queued';

/* The email's own row set to a state of the queue: Queued as it is put,
   Sending as the drain claims it, Cancelled at Cancel. A hiring email's
   step reads the same word on the candidate's card. */
create or replace function public.mail_queue_mark(q public.mail_queue, p_state text)
returns void language plpgsql volatile security definer set search_path = public as $$
declare v_was text := case p_state when 'queued' then 'sending' when 'sending' then 'queued' else 'queued' end;
begin
  if q.source = 'supplier' then update public.supplier_emails x set status = p_state, error = case when p_state = 'cancelled' then 'cancelled' else x.error end where x.id = q.log_id and x.status = v_was;
  elsif q.source = 'client' then update public.client_emails x set status = p_state, error = case when p_state = 'cancelled' then 'cancelled' else x.error end where x.id = q.log_id and x.status = v_was;
  elsif q.source = 'manual' then update public.team_emails x set status = p_state, error = case when p_state = 'cancelled' then 'cancelled' else x.error end where x.id = q.log_id and x.status = v_was;
  elsif q.source = 'invoice' then update public.invoice_emails x set status = p_state, error = case when p_state = 'cancelled' then 'cancelled' else x.error end where x.id = q.log_id and x.status = v_was;
  elsif q.source = 'feedback' then
    -- A feedback request whose email is cancelled is withdrawn, as one that failed.
    update public.feedback_requests x set mail_status = p_state,
      closed_at = case when p_state = 'cancelled' and x.closed_at is null then now() else x.closed_at end,
      closed_reason = case when p_state = 'cancelled' and x.closed_at is null then 'withdrawn' else x.closed_reason end
     where x.id = q.log_id and x.mail_status = v_was;
  elsif q.source = 'system' then
    update public.system_emails x set status = p_state where x.id = q.log_id and x.status = v_was;
    if p_state <> 'sending' then
      if q.close->>'fn' = 'interview' then
        update public.hiring_interviews i set
          invite_mail = case when q.close->>'kind' = 'invite' then p_state else i.invite_mail end,
          confirm_mail = case when q.close->>'kind' = 'confirm' then p_state else i.confirm_mail end,
          reschedule_mail = case when q.close->>'kind' = 'rescheduled' then p_state else i.reschedule_mail end,
          cancel_mail = case when q.close->>'kind' = 'cancelled' then p_state else i.cancel_mail end,
          held_mail = case when q.close->>'kind' in ('held', 'moved') then p_state else i.held_mail end,
          updated_at = now()
         where i.id = (q.close->>'ref')::uuid;
      elsif q.close->>'fn' = 'doc' then update public.hiring_docs d set mail = p_state, mail_at = now() where d.id = (q.close->>'ref')::uuid;
      elsif q.close->>'fn' = 'confirmed' then update public.hiring_docs d set confirm_mail = p_state, confirm_mail_at = now() where d.id = (q.close->>'ref')::uuid;
      elsif q.close->>'fn' = 'outcome' then update public.hiring_candidates c set outcome_mail = p_state, outcome_mail_at = now(), updated_at = now() where c.id = (q.close->>'ref')::uuid;
      end if;
    end if;
  end if;
end $$;
revoke all on function public.mail_queue_mark(public.mail_queue, text) from public, anon, authenticated;

/* The Activity record's line for a queued or cancelled email, under the
   record its sender files the email under (a hiring email in the
   candidate's own history, never the Activity record). */
create or replace function public.mail_queue_note(q public.mail_queue, p_word text, p_actor text)
returns void language plpgsql volatile security definer set search_path = public as $$
declare v_action text; v_subject text; v_cand uuid;
begin
  if q.source = 'system' then
    select coalesce(i.candidate_id, d.candidate_id, c.id) into v_cand
      from (select 1) z
      left join public.hiring_interviews i on q.close->>'fn' = 'interview' and i.id = (q.close->>'ref')::uuid
      left join public.hiring_docs d on q.close->>'fn' in ('doc', 'confirmed') and d.id = (q.close->>'ref')::uuid
      left join public.hiring_candidates c on q.close->>'fn' = 'outcome' and c.id = (q.close->>'ref')::uuid;
    if v_cand is not null then
      insert into public.hiring_events (candidate_id, actor, action, detail)
      values (v_cand, coalesce(p_actor, 'ADspace'), 'candidate.email', coalesce(q.what, 'Email') || ' ' || p_word || '.');
    end if;
    return;
  end if;
  if q.source = 'supplier' then
    v_action := 'supplier.edited';
    select coalesce(s.name, s.code, 'Supplier') into v_subject from public.supplier_emails e join public.suppliers s on s.id = e.supplier_id where e.id = q.log_id;
  elsif q.source = 'manual' then
    v_action := 'email.sent';
    select coalesce(c.name, s.name, 'Other recipient') into v_subject from public.team_emails e
      left join public.clients c on c.id = e.client_id left join public.suppliers s on s.id = e.supplier_id where e.id = q.log_id;
  else
    v_action := 'client.edited';
    v_subject := case q.source
      when 'client' then (select c.name from public.client_emails e join public.clients c on c.id = e.client_id where e.id = q.log_id)
      when 'invoice' then (select coalesce(c.name, e.client_name) from public.invoice_emails e left join public.clients c on c.id = e.client_id where e.id = q.log_id)
      else (select c.name from public.feedback_requests e join public.clients c on c.id = e.client_id where e.id = q.log_id) end;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(p_actor, 'system'), v_action, coalesce(v_subject, 'Email'),
          coalesce(q.what, 'Email') || ' · email to ' || coalesce(nullif(q.to_name, ''), 'the recipient') || ' ' || p_word);
end $$;
revoke all on function public.mail_queue_note(public.mail_queue, text, text) from public, anon, authenticated;

/* An email built and checked by its sender, as the caller, then queued here
   by that function as the service role: due once the Undo window passes.
   The email's row reads Queued until it goes. */
create or replace function public.mail_queue_put(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  v_src  text := p->>'source';
  v_log  uuid := nullif(p->>'log_id', '')::uuid;
  v_by   uuid;
  v_secs int := greatest(0, least(600, coalesce(public.app_setting('send_undo_seconds', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 60)));
  q      public.mail_queue;
begin
  if v_src is null or v_log is null or jsonb_typeof(p->'msg') <> 'object' or coalesce(p->>'idem', '') = '' then
    return jsonb_build_object('error', 'bad-request');
  end if;
  v_by := case v_src
    when 'supplier' then (select e.sent_by from public.supplier_emails e where e.id = v_log)
    when 'client' then (select e.sent_by from public.client_emails e where e.id = v_log)
    when 'manual' then (select e.sent_by from public.team_emails e where e.id = v_log)
    when 'invoice' then (select e.sent_by from public.invoice_emails e where e.id = v_log)
    when 'feedback' then (select e.sent_by from public.feedback_requests e where e.id = v_log)
    else (select t.id from public.team_members t where t.auth_user_id = nullif(p->>'by', '')::uuid limit 1) end;
  insert into public.mail_queue (source, log_id, close, msg, idem, to_name, what, send_at, queued_by)
  values (v_src, v_log, coalesce(p->'close', '{}'::jsonb), p->'msg', p->>'idem', left(nullif(p->>'to_name', ''), 200),
          left(nullif(p->>'what', ''), 200), now() + make_interval(secs => v_secs), v_by)
  on conflict (source, log_id) do nothing
  returning * into q;
  if q.id is null then return jsonb_build_object('error', 'already'); end if;
  perform public.mail_queue_mark(q, 'queued');
  perform public.mail_queue_note(q, 'queued', (select t.name from public.team_members t where t.id = v_by));
  return jsonb_build_object('ok', true, 'queue', q.id, 'source', v_src, 'id', v_log, 'seconds', v_secs, 'send_at', q.send_at);
end $$;
revoke all on function public.mail_queue_put(jsonb) from public, anon, authenticated;
grant execute on function public.mail_queue_put(jsonb) to service_role;

/* The drain's (the service role's): each due email claimed once, its row
   read Sending. */
create or replace function public.mail_queue_claim(p_n int default 5)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare q public.mail_queue; v jsonb := '[]'::jsonb;
begin
  for q in
    select * from public.mail_queue x where x.status = 'queued' and x.send_at <= now()
     order by x.send_at limit greatest(1, least(coalesce(p_n, 5), 20)) for update skip locked
  loop
    -- A decision's email whose decision was reopened meanwhile (Undo,
    -- Reopen) is never sent: cancelled, as the decision is.
    if q.source = 'system' and q.close->>'fn' = 'outcome' and not exists (
         select 1 from public.hiring_candidates c where c.id = (q.close->>'ref')::uuid and c.removed_at is null
            and c.outcome in ('pool', 'not') and c.outcome_mail = 'queued') then
      update public.mail_queue x set status = 'cancelled', cancelled_at = now(), closed_at = now(), msg = '{}'::jsonb where x.id = q.id;
      update public.system_emails x set status = 'cancelled' where x.id = q.log_id and x.status = 'queued';
      continue;
    end if;
    update public.mail_queue x set status = 'sending', claimed_at = now() where x.id = q.id;
    perform public.mail_queue_mark(q, 'sending');
    v := v || jsonb_build_array(jsonb_build_object('id', q.id, 'msg', q.msg, 'idem', q.idem));
  end loop;
  return v;
end $$;
revoke all on function public.mail_queue_claim(int) from public, anon, authenticated;
grant execute on function public.mail_queue_claim(int) to service_role;

/* The drain's outcome: closed through the email's own sender's close, as
   the colleague who queued it (their access asked again), so the email's
   row, its record and the Activity record read as a send by hand always
   has. What Resend was sent is emptied once it is closed. */
create or replace function public.mail_queue_close(p_id uuid, p_status text, p_provider text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  q   public.mail_queue;
  m   public.team_members;
  r   jsonb;
  was text := current_setting('request.jwt.claims', true);
  hdr text := current_setting('request.headers', true);
begin
  if coalesce(p_status, '') not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into q from public.mail_queue x where x.id = p_id and x.status = 'sending' for update;
  if q.id is null then return jsonb_build_object('error', 'not-claimed'); end if;
  update public.mail_queue x set status = p_status, provider_id = nullif(p_provider, ''), error = left(nullif(p_error, ''), 480),
    closed_at = now(), msg = '{}'::jsonb where x.id = q.id;
  select * into m from public.team_members t where t.id = q.queued_by;
  if q.source = 'invoice' then
    r := public.invoice_email_done(q.log_id, p_status, p_provider, p_error);
  else
    -- Acting as the colleague who queued it: their own close, their access.
    perform set_config('request.jwt.claims', jsonb_build_object('email', m.email, 'sub', m.auth_user_id, 'role', 'authenticated')::text, true);
    perform set_config('request.headers', '{}', true);
    r := case q.source
      when 'supplier' then public.supplier_email_done(q.log_id, p_status, p_provider, p_error)
      when 'client' then public.client_email_done(q.log_id, p_status, p_provider, p_error)
      when 'manual' then public.email_new_done(q.log_id, p_status, p_provider, p_error)
      when 'feedback' then public.feedback_mail_done(q.log_id, p_status, p_provider, p_error)
      else null end;
    if q.source = 'system' then
      update public.system_emails x set status = p_status, provider_id = nullif(p_provider, ''), error = left(nullif(p_error, ''), 480),
        sent_at = case when p_status = 'sent' then now() end
       where x.id = q.log_id and x.status = 'sending';
      r := case q.close->>'fn'
        when 'interview' then public.hiring_mail_done((q.close->>'ref')::uuid, q.close->>'kind', p_status, p_error)
        when 'doc' then public.hiring_doc_mail_done((q.close->>'ref')::uuid, p_status, p_error)
        when 'confirmed' then public.hiring_confirmed_mail_done((q.close->>'ref')::uuid, p_status, p_error)
        when 'outcome' then public.hiring_outcome_mail_done((q.close->>'ref')::uuid, p_status, p_error)
        else jsonb_build_object('ok', true) end;
    end if;
    perform set_config('request.jwt.claims', coalesce(was, ''), true);
    perform set_config('request.headers', coalesce(hdr, ''), true);
  end if;
  return jsonb_build_object('ok', true, 'closed', r);
end $$;
revoke all on function public.mail_queue_close(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.mail_queue_close(uuid, text, text, text) to service_role;

/* Cancel, for the whole window: by the colleague who sent it, or at
   Messages Full Access. Refused once the drain has taken it (`sent`). */
create or replace function public.mail_cancel(p_source text, p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); q public.mail_queue;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.mail_queue x where x.source = p_source and x.log_id = p_id for update;
  if q.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if q.queued_by is distinct from me.id and not public.allowed('whatsapp', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if q.status = 'cancelled' then return jsonb_build_object('ok', true, 'same', true); end if;
  if q.status <> 'queued' then return jsonb_build_object('error', 'sent'); end if;
  update public.mail_queue x set status = 'cancelled', cancelled_by = me.id, cancelled_at = now(), closed_at = now(), msg = '{}'::jsonb
   where x.id = q.id returning * into q;
  perform public.mail_queue_mark(q, 'cancelled');
  perform public.mail_queue_note(q, 'cancelled before it was sent', me.name);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.mail_cancel(text, uuid) from public, anon;
grant execute on function public.mail_cancel(text, uuid) to authenticated;

/* The drain: supplier-mail's, woken with the wake secret. */
create or replace function public.mail_queue_kick()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'net' and p.proname = 'http_post') then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/supplier-mail', '{"action":"drain"}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-adspace-wake',
            coalesce((select s.value from public.app_secrets s where s.key = 'wake_secret'), ''));
exception when others then
  return;
end $$;
revoke all on function public.mail_queue_kick() from public, anon, authenticated;

/* Every minute, the drain is woken only while an email is due: the delay
   is the window to the window and a minute. */
create or replace function public.mail_queue_due()
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.mail_queue q where q.status = 'queued' and q.send_at <= now()) then
    perform public.mail_queue_kick();
  end if;
end $$;
revoke all on function public.mail_queue_due() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: a queued email waits for the next wake.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'mail-queue';
  perform cron.schedule('mail-queue', '* * * * *', 'select public.mail_queue_due()');
end $$;

create or replace function public.supplier_email_prepare(p_supplier uuid, p_purpose text, p_document uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.suppliers;
  d     public.documents;
  t     public.supplier_email_templates;
  v     jsonb;
  hours numeric;
  r     public.supplier_emails;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  select * into s from public.suppliers x where x.id = p_supplier;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.supplier_email_templates x where x.purpose = p_purpose;
  if t.purpose is null then return jsonb_build_object('error', 'bad-purpose'); end if;
  if coalesce(s.email, '') = '' then return jsonb_build_object('error', 'no-email'); end if;
  if p_purpose = 'approved' and s.status <> 'active' then return jsonb_build_object('error', 'not-active'); end if;
  if p_purpose = 'document' then
    select * into d from public.documents x where x.id = p_document and x.supplier_id = s.id;
    if d.id is null or d.voided_at is not null then return jsonb_build_object('error', 'bad-document'); end if;
  end if;
  v := jsonb_build_object(
    'supplier name', coalesce(s.name, s.code), 'supplier id', s.code,
    'contact name', coalesce(s.contact_name, ''), 'designation', coalesce(s.designation, ''),
    'payment term', coalesce(s.payment_term, ''),
    'currency', case s.currency when 'SGD' then 'SGD' else 'MYR' end,
    'document title', coalesce(d.kind, ''), 'document reference', coalesce(d.serial, ''),
    'document date', case when d.issued_at is null then ''
      else to_char(d.issued_at at time zone 'Asia/Kuala_Lumpur', 'FMDD FMMonth YYYY') end,
    'sender name', coalesce(me.name, ''));
  hours := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  if hours > 0 then
    select * into r from public.supplier_emails x
     where x.supplier_id = s.id and x.purpose = p_purpose and x.document_id is not distinct from d.id
       and x.status not in ('failed', 'cancelled') and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
  end if;
  return jsonb_build_object('ok', true,
    'to', jsonb_build_object('name', coalesce(s.contact_name, coalesce(s.name, s.code)), 'email', s.email),
    'cc', nullif(coalesce(s.finance_email, ''), s.email),
    'values', v,
    'subject', public.supplier_email_fill(t.subject, v),
    'body', public.supplier_email_fill(t.body, v),
    'document', case when d.id is null then null else jsonb_build_object('id', d.id, 'serial', d.serial, 'kind', d.kind) end,
    'recent', case when r.id is null then null else jsonb_build_object('at', r.created_at, 'to', r.to_email,
      'by', (select m.name from public.team_members m where m.id = r.sent_by)) end);
end $$;
revoke all on function public.supplier_email_prepare(uuid, text, uuid) from public, anon;
grant execute on function public.supplier_email_prepare(uuid, text, uuid) to authenticated;

create or replace function public.client_email_prepare(p_kind text, p_ref uuid, p_contact uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  c      public.clients;
  q      public.quotations;
  o      public.client_documents;
  d      public.documents;
  k      public.client_contacts;
  t      public.client_email_templates;
  v_cid  uuid;
  v_ref  text;
  v_tit  text;
  v_day  date;
  v_val  date;
  v      jsonb;
  ppl    jsonb;
  hours  numeric;
  r      public.client_emails;
  v_cc   text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if p_kind not in ('quotation', 'offer', 'letter') then return jsonb_build_object('error', 'bad-request'); end if;
  if not public.client_email_may(p_kind, 'work') or not public.allowed('clients.contacts', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if coalesce(public.app_setting('client_email_on', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) <> 1 then
    return jsonb_build_object('error', 'email-off');
  end if;
  if p_kind = 'quotation' then
    select * into q from public.quotations x where x.id = p_ref;
    if q.id is null or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
    if q.status = 'not_proceeding' then return jsonb_build_object('error', 'void'); end if;
    if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'unreleased'); end if;
    if q.confirmed_at is null then return jsonb_build_object('error', 'not-confirmed'); end if;
    if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
    v_cid := q.client_id; v_ref := q.ref; v_tit := 'Quotation';
    v_day := (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date; v_val := q.valid_until;
  elsif p_kind = 'offer' then
    select * into o from public.client_documents x where x.id = p_ref;
    if o.id is null or o.kind not in ('offer', 'intent', 'cover') then return jsonb_build_object('error', 'not-found'); end if;
    if o.voided_at is not null or o.superseded_by is not null then return jsonb_build_object('error', 'void'); end if;
    v_cid := o.client_id; v_ref := o.number; v_tit := 'Letter of Offer'; v_day := o.issued_at;
  else
    select * into d from public.documents x where x.id = p_ref and x.family = 'client';
    if d.id is null or d.client_id is null then return jsonb_build_object('error', 'not-found'); end if;
    if d.voided_at is not null then return jsonb_build_object('error', 'void'); end if;
    if d.source <> 'portal' then return jsonb_build_object('error', 'no-file'); end if;
    v_cid := d.client_id; v_ref := d.serial; v_tit := coalesce(nullif(d.kind, ''), 'Letter'); v_day := d.issued_at;
  end if;
  select * into c from public.clients x where x.id = v_cid;
  if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.client_email_templates x where x.kind = p_kind;
  if t.kind is null then return jsonb_build_object('error', 'needs-update'); end if;

  /* The client's contacts holding an email, the billing contact first, then
     the primary, then by name. */
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', public.contact_named(x.salutation, x.name),
           'email', btrim(x.email), 'role', x.role, 'billing', coalesce(x.id = c.bill_contact_id, false), 'primary', x.is_primary)
           order by (x.id = c.bill_contact_id) desc nulls last, x.is_primary desc, x.name), '[]'::jsonb)
    into ppl
    from public.client_contacts x
   where x.client_id = c.id and x.archived_at is null and coalesce(btrim(x.email), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
  if jsonb_array_length(ppl) = 0 then return jsonb_build_object('error', 'no-email'); end if;
  if p_contact is not null then
    select * into k from public.client_contacts x
     where x.id = p_contact and x.client_id = c.id and x.archived_at is null
       and coalesce(btrim(x.email), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
    if k.id is null then return jsonb_build_object('error', 'bad-contact'); end if;
  else
    select * into k from public.client_contacts x where x.id = (ppl->0->>'id')::uuid;
  end if;
  -- The finance email and registered name are Billing's (audit 2026-11-04).
  v_cc := case when public.allowed('clients.billing', 'view') then nullif(btrim(coalesce(c.finance_email, '')), '') end;
  if v_cc is not null and (lower(v_cc) = lower(btrim(k.email)) or v_cc !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then v_cc := null; end if;

  v := jsonb_build_object(
    'contact name', public.contact_named(k.salutation, k.name),
    'client name', c.name,
    'company name', coalesce(case when public.allowed('clients.billing', 'view') then nullif(c.legal_name, '') end, c.name),
    'document title', v_tit, 'document reference', v_ref,
    'document date', case when v_day is null then '' else to_char(v_day, 'FMDD FMMonth YYYY') end,
    'valid until', case when v_val is null then '' else to_char(v_val, 'FMDD FMMonth YYYY') end,
    'sender name', coalesce(me.name, ''));
  hours := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  if hours > 0 then
    select * into r from public.client_emails x
     where x.kind = p_kind and x.ref_id = p_ref and x.status not in ('failed', 'cancelled')
       and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
  end if;
  return jsonb_build_object('ok', true,
    'client_id', c.id, 'client', c.name,
    'contacts', ppl,
    'to', jsonb_build_object('id', k.id, 'name', public.contact_named(k.salutation, k.name), 'email', btrim(k.email)),
    'cc', v_cc,
    'reply_to', nullif(btrim(coalesce(me.email, '')), ''),
    'values', v,
    'subject', public.supplier_email_fill(t.subject, v),
    'body', public.supplier_email_fill(t.body, v),
    'document', jsonb_build_object('id', p_ref, 'kind', p_kind, 'serial', v_ref, 'title', v_tit),
    'recent', case when r.id is null then null else jsonb_build_object('at', r.created_at, 'to', r.to_email,
      'by', (select m.name from public.team_members m where m.id = r.sent_by)) end);
end $$;
revoke all on function public.client_email_prepare(text, uuid, uuid) from public, anon;
grant execute on function public.client_email_prepare(text, uuid, uuid) to authenticated;

create or replace function public.invoice_mail_begin(p_purpose text, p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean, p_to text, p_ccs text[])
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members;
  t      public.invoice_email_template;
  v_tpl  public.invoice_send_template;
  rcp    jsonb;
  opts   jsonb;
  pick   jsonb;
  inv    jsonb;
  hours  numeric;
  r      public.invoice_emails;
  v_n    int;
  v_k    int;
  v_m    int;
  v_d    int;
  v_to   text;
  v_cc   text;
  v_who  text;
  v_nm   boolean;
  v_co   text;
  v_tot  text;
  v_nos  text;
  v_list text[];
  v_vals jsonb;
  v_s    text;
  v_b    text;
  v_id   uuid;
begin
  select * into me from public.team_members x where x.id = p_actor and x.active;
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok_of(me.id, 'email') then return jsonb_build_object('error', 'send-off'); end if;
  if p_purpose is null or p_purpose not in ('reminder', 'invoice') then return jsonb_build_object('error', 'bad-request'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-request'); end if;
  if jsonb_typeof(p_invoices) <> 'array' or jsonb_array_length(p_invoices) < 1 or jsonb_array_length(p_invoices) > 50 then
    return jsonb_build_object('error', 'bad-invoices');
  end if;
  for inv in select value from jsonb_array_elements(p_invoices) loop
    if btrim(coalesce(inv->>'number', '')) = '' or coalesce(inv->>'number', '') !~ '^[^[:cntrl:]]{1,60}$' or coalesce(inv->>'currency', '') !~ '^[A-Z]{3}$'
       or (inv->>'amount') is null or (inv->>'amount')::numeric <= 0
       or (coalesce(inv->>'link', '') <> '' and inv->>'link' !~ '^https://[a-z0-9-]+\.bukku\.my/[A-Za-z0-9/_-]+$') then
      return jsonb_build_object('error', 'bad-invoices');
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended('invoice-mail:' || p_contact::text, 0));
  select * into r from public.invoice_emails x
   where x.bukku_contact = p_contact and x.status = 'sending' and x.created_at > now() - interval '10 minutes'
   order by x.created_at desc limit 1;
  if r.id is not null then return jsonb_build_object('error', 'sending'); end if;
  hours := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  if hours > 0 and not coalesce(p_again, false) then
    select * into r from public.invoice_emails x
     where x.bukku_contact = p_contact and x.purpose = p_purpose and x.status not in ('failed', 'cancelled') and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
    if r.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', r.created_at, 'to', r.to_email,
        'by', (select m.name from public.team_members m where m.id = r.sent_by)));
    end if;
  end if;
  rcp := case when p_client is null then null else public.invoice_recipient_for(p_client, p_contact) end;
  /* The addresses chosen on the sheet: the client's own, nothing typed. */
  if p_to is not null or p_ccs is not null then opts := public.invoice_recipient_options(p_client, p_contact); end if;
  if p_to is not null then
    select x into pick from jsonb_array_elements(opts) x where lower(x->>'email') = lower(btrim(p_to)) limit 1;
    if pick is null then return jsonb_build_object('error', 'bad-recipient'); end if;
    v_to := pick->>'email';
    v_who := coalesce(pick->>'name', 'Sir or Madam');
    v_nm := pick->>'name' is not null;
  else
    v_to := coalesce(rcp->>'email', nullif(btrim(coalesce(p_email, '')), ''));
    v_who := coalesce(rcp->>'name', 'Sir or Madam');
    v_nm := rcp->>'name' is not null;
  end if;
  if v_to is null or v_to !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then return jsonb_build_object('error', 'no-email'); end if;
  if p_ccs is not null then
    select count(*), count(o.e), count(distinct lower(o.e)), count(*) filter (where lower(o.e) = lower(v_to)),
           string_agg(o.e, ', ' order by o.i)
      into v_k, v_m, v_d, v_n, v_cc
      from (select a.i, (select x->>'email' from jsonb_array_elements(opts) x where lower(x->>'email') = lower(btrim(a.v)) limit 1) as e
              from unnest(p_ccs) with ordinality as a (v, i)
             where nullif(btrim(coalesce(a.v, '')), '') is not null) o;
    if v_k > 5 or v_m <> v_k or v_d <> v_m or v_n > 0 then return jsonb_build_object('error', 'bad-copy'); end if;
  else
    v_cc := case when coalesce(p_cc, false) and lower(coalesce(rcp->>'cc', '')) <> lower(v_to) then rcp->>'cc' end;
  end if;
  v_co := coalesce(rcp->>'company', nullif(btrim(coalesce(p_name, '')), ''), 'Client');
  v_n := jsonb_array_length(p_invoices);
  select string_agg(public.invoice_money(s.amt, s.cur), ' and ' order by s.cur) into v_tot
    from (select x->>'currency' as cur, sum((x->>'amount')::numeric) as amt
            from jsonb_array_elements(p_invoices) x group by x->>'currency') s;
  select array_agg(x->>'number' order by o) into v_list from jsonb_array_elements(p_invoices) with ordinality as a (x, o);
  v_nos := case when v_n = 1 then v_list[1]
                else array_to_string(v_list[1:v_n - 1], ', ') || ' and ' || v_list[v_n] end;
  v_vals := jsonb_build_object('contact name', v_who, 'client', v_co, 'invoice no', v_nos, 'count', v_n::text,
    'total', v_tot, 'sign off', case when v_nm then 'Yours sincerely' else 'Yours faithfully' end);
  if p_purpose = 'invoice' then
    select * into v_tpl from public.invoice_send_template x where x.id = 1;
    t.subject_one := v_tpl.subject_one; t.subject_many := v_tpl.subject_many; t.body := v_tpl.body;
    t.legal := v_tpl.legal; t.disclaimer := v_tpl.disclaimer;
  else
    select * into t from public.invoice_email_template x where x.id = 1;
  end if;
  v_s := btrim(regexp_replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_subject, '')), ''),
           case when v_n = 1 then t.subject_one else t.subject_many end), v_vals), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_body, '')), ''), t.body), v_vals), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  insert into public.invoice_emails (client_id, bukku_contact, client_name, invoices, to_email, cc_email, subject, body, sent_by, purpose)
  values (p_client, p_contact, v_co, p_invoices, v_to, nullif(v_cc, ''), v_s, v_b, me.id, p_purpose)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', v_to, 'cc', nullif(v_cc, ''),
    'cc_list', coalesce(to_jsonb(string_to_array(nullif(v_cc, ''), ', ')), '[]'::jsonb), 'subject', v_s, 'body', v_b,
    'legal', t.legal, 'disclaimer', t.disclaimer);
end $$;
revoke all on function public.invoice_mail_begin(text, uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean, text, text[]) from public, anon, authenticated;
grant execute on function public.invoice_mail_begin(text, uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean, text, text[]) to service_role;

create or replace function public.mail_sweep()
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  n integer := 0;
  k integer;
begin
  update public.invoice_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending'
     and coalesce((select q.claimed_at from public.mail_queue q where q.log_id = x.id), x.created_at) < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.supplier_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending'
     and coalesce((select q.claimed_at from public.mail_queue q where q.log_id = x.id), x.created_at) < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.client_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending'
     and coalesce((select q.claimed_at from public.mail_queue q where q.log_id = x.id), x.created_at) < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.team_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending'
     and coalesce((select q.claimed_at from public.mail_queue q where q.log_id = x.id), x.created_at) < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.creator_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.claimed_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  -- A row left at Sending may stand in the sheet: never tried again by itself
  -- (audit 2026-11-15), so the bank details are never added twice.
  update public.creator_sheet_rows x set status = 'failed', tries = 5,
         error = 'Not confirmed. Check the sheet before adding the row again.'
   where x.status = 'sending' and x.claimed_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  -- An email the shared queue claimed and never closed: not confirmed,
  -- never sent again by itself (UNDO SEND, 2026-11-28).
  update public.mail_queue x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed'), msg = '{}'::jsonb, closed_at = now()
   where x.status = 'sending' and x.claimed_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_sweep() from public, anon, authenticated;

/* Who sent each email, by id, so Cancel is drawn for its sender alone. */
create or replace function public.mail_log(p_month date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_from date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Kuala_Lumpur')::date))::date;
  v_a    timestamptz;
  v_b    timestamptz;
  v_sup  boolean;
  v_bill boolean;
  v_quo  boolean;
  v_all  boolean;
  v_cr   boolean;
  v_team boolean;
  v_con  boolean;
begin
  if me.id is null or not public.allowed('whatsapp', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_a := v_from::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_b := (v_from + interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_sup := public.allowed('suppliers', 'view');
  v_bill := public.allowed('clients.billing', 'view');
  v_quo := public.allowed('clients.quotes', 'view');
  v_all := public.client_scope_free('view');
  v_cr := public.allowed('campaigns.creators', 'view');
  v_team := public.allowed('team', 'view');
  v_con := public.allowed('clients.contacts', 'view');
  return jsonb_build_object(
    'month', v_from,
    'senders', (select jsonb_object_agg(m.key, m.name || ' <' || m.address || '>') from public.mail_senders m),
    'items', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
        select * from (
          select 'supplier'::text as source, e.id, e.purpose as kind, e.to_email, e.cc_email, e.subject, e.body,
                 t.name as sent_by, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 null::uuid as client_id, null::text as client, e.supplier_id, s.name as supplier, s.code as supplier_code,
                 d.serial as reference, null::text as to_name, null::uuid as ref_id, null::uuid as again_of, e.sent_by as sent_by_id
            from public.supplier_emails e
            left join public.suppliers s on s.id = e.supplier_id
            left join public.documents d on d.id = e.document_id
            left join public.team_members t on t.id = e.sent_by
           where v_sup and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'client', e.id, e.kind, e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, null, null, null,
                 e.reference, k.name, null, null, e.sent_by
            from public.client_emails e
            left join public.clients c on c.id = e.client_id
            left join public.client_contacts k on k.id = e.contact_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and public.client_email_may(e.kind, 'view')
             and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
          union all
          select 'invoice', e.id, e.purpose, e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, coalesce(c.name, e.client_name), null, null, null,
                 (select string_agg(i->>'number', ', ' order by o) from jsonb_array_elements(e.invoices) with ordinality as a (i, o)),
                 null, null, null, e.sent_by
            from public.invoice_emails e
            left join public.clients c on c.id = e.client_id
            left join public.team_members t on t.id = e.sent_by
           where v_bill and e.created_at >= v_a and e.created_at < v_b
             and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
          union all
          select 'manual', e.id, 'message', e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, e.supplier_id, s.name, s.code,
                 e.attachment, e.to_name, null, null, e.sent_by
            from public.team_emails e
            left join public.clients c on c.id = e.client_id
            left join public.suppliers s on s.id = e.supplier_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and (case when e.client_id is not null then public.allowed('clients.contacts', 'view') and public.client_seen(e.client_id, 'view')
                       when e.supplier_id is not null then v_sup else true end)
             and (not e.finance or v_bill)
          union all
          select 'creator', e.id, 'creator_' || e.purpose, e.to_email, null, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 null, null, null, null, null,
                 r.ref, k.name, null, e.again_of, e.sent_by
            from public.creator_emails e
            left join public.creators k on k.id = e.creator_id
            left join public.creator_pay_requests r on r.id = e.request_id
            left join public.team_members t on t.id = e.sent_by
           where v_cr and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'system', e.id, e.kind, e.to_email, null, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, null, null, null,
                 e.reference, e.to_name, e.ref_id, e.again_of, e.sent_by
            from public.system_emails e
            left join public.clients c on c.id = e.client_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and (case when e.kind like 'hiring%' then public.hiring_role(e.candidate_id) is not null
                       when e.kind = 'invite_team' then v_team
                       when e.kind = 'invite_client' then v_con and e.client_id is not null and public.client_seen(e.client_id, 'view')
                       else false end)
          union all
          select 'signing', g.id, 'signing', g.email, null, 'Your ADspace signing code for quotation ' || q.ref, null,
                 null, g.created_at,
                 case when g.used_at is not null then 'used' when g.expires_at < now() then 'expired' else 'requested' end,
                 null, g.created_at, null, null, null,
                 q.client_id, c.name, null, null, null,
                 q.ref, nullif(btrim(coalesce(g.payload->'contact'->>'salutation', '') || ' ' || coalesce(g.payload->'contact'->>'name', '')), ''),
                 null, null, null::uuid
            from public.quote_sign_codes g
            join public.quotations q on q.id = g.quotation_id
            left join public.clients c on c.id = q.client_id
           where v_quo and g.created_at >= v_a and g.created_at < v_b
             and (case when q.client_id is null then v_all else public.client_seen(q.client_id, 'view') end)
        ) u
        order by u.created_at desc
        limit 2000) x), '[]'::jsonb));
end $$;
revoke all on function public.mail_log(date) from public, anon;
grant execute on function public.mail_log(date) to authenticated;

create or replace function public.team_emails_of(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('clients.contacts', 'view') or not public.client_seen(p_client, 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    /* In the Email log's own shape, so its sheet opens one as it is. */
    select jsonb_agg(jsonb_build_object('source', 'manual', 'id', e.id, 'kind', 'message', 'to_email', e.to_email,
             'to_name', e.to_name, 'cc_email', e.cc_email, 'subject', e.subject, 'body', e.body, 'reference', e.attachment,
             'status', e.status, 'error', e.error, 'created_at', e.created_at, 'sent_at', e.sent_at,
             'delivered_at', e.delivered_at, 'opened_at', e.opened_at, 'bounced_at', e.bounced_at,
             'sent_by', m.name, 'sent_by_id', e.sent_by, 'client_id', e.client_id) order by e.created_at desc)
      from public.team_emails e
      left join public.team_members m on m.id = e.sent_by
     where e.client_id = p_client and (not e.finance or public.allowed('clients.billing', 'view'))), '[]'::jsonb));
end $$;
revoke all on function public.team_emails_of(uuid) from public, anon;
grant execute on function public.team_emails_of(uuid) to authenticated;

create or replace function public.supplier_emails_of(p_supplier uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(x.r order by x.at desc) from (
      select jsonb_build_object('id', e.id, 'purpose', e.purpose, 'to', e.to_email, 'cc', e.cc_email,
               'subject', e.subject, 'status', e.status, 'error', e.error, 'created_at', e.created_at,
               'delivered_at', e.delivered_at, 'opened_at', e.opened_at, 'bounced_at', e.bounced_at,
               'by', m.name, 'by_id', e.sent_by, 'source', 'supplier', 'document', d.serial) as r, e.created_at as at
        from public.supplier_emails e
        left join public.team_members m on m.id = e.sent_by
        left join public.documents d on d.id = e.document_id
       where e.supplier_id = p_supplier
      union all
      select jsonb_build_object('id', e.id, 'purpose', 'message', 'to', e.to_email, 'cc', e.cc_email,
               'subject', e.subject, 'status', e.status, 'error', e.error, 'created_at', e.created_at,
               'delivered_at', e.delivered_at, 'opened_at', e.opened_at, 'bounced_at', e.bounced_at,
               'by', m.name, 'by_id', e.sent_by, 'source', 'manual', 'document', e.attachment), e.created_at
        from public.team_emails e
        left join public.team_members m on m.id = e.sent_by
       where e.supplier_id = p_supplier) x), '[]'::jsonb));
end $$;
revoke all on function public.supplier_emails_of(uuid) from public, anon;
grant execute on function public.supplier_emails_of(uuid) to authenticated;

-- END OF UNDO SEND --------------------------------------------------------------

select public.functions_tidy();
