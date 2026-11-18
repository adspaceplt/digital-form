-- ===========================================================================
-- SEND AGAIN (2026-11-18)
-- ===========================================================================
-- WHY: the user, 2026-11-18, reading a creator email that was Not sent in
-- Messages' Email log: "maybe a resend button? so failed email could be
-- resent".
--
-- WHAT IT CHANGES
--   * `creator_emails.sent_by`, `again_of`; `system_emails.ref_id` (the
--     interview, candidate or document a hiring email was about),
--     `again_of`.
--   * `creator_email_again(p_id)`: a creator email Not sent, Bounced or Not
--     confirmed queued again in its first words, as the colleague's
--     (Messages and Creator Campaigns: Creators at Work, Send email on;
--     `denied`, `send-off`, `not-found`, `not-failed`, `gone`, `already`),
--     filed `email.sent`.
--   * `creator_mail_claim`: Automatic emails off holds back only what the
--     database queued itself, never an email sent again by hand.
--   * `system_email_file` keeps the record a hiring email was about
--     (`ref_id`) and the email it sends again (`again_of`); `mail_log`
--     answers both, and who sent a creator email again.
--
-- ORDER: this file (connector), then hiring-mail, then the pages. An old
-- page draws no Send again; hiring-mail before this file files as before.
-- Safe to run twice.
--
-- ROLLBACK: drop `creator_email_again`; restate `creator_mail_claim`,
-- `system_email_file` and `mail_log` as EVERY EMAIL IN MESSAGES and the
-- automatic switch's band state them; the columns may stay.
-- ===========================================================================

alter table public.creator_emails add column if not exists sent_by uuid;
alter table public.creator_emails add column if not exists again_of uuid;
alter table public.system_emails add column if not exists ref_id uuid;
alter table public.system_emails add column if not exists again_of uuid;

create or replace function public.creator_mail_claim(p_n int default 5)
returns setof public.creator_emails
language plpgsql volatile security definer set search_path = public as $$
begin
  /* Automatic emails off: an email queued before the switch moved is kept
     as Not sent, never sent later; one a colleague sent again by hand goes
     (SEND AGAIN, 2026-11-18). */
  if not public.auto_send_on('email') then
    update public.creator_emails x set status = 'failed', error = 'off: Automatic emails are off.'
     where x.status = 'queued' and x.sent_by is null;
  end if;
  return query
  update public.creator_emails x set status = 'sending', claimed_at = now()
   where x.id in (select y.id from public.creator_emails y where y.status = 'queued'
                   order by y.created_at limit least(greatest(coalesce(p_n, 5), 1), 10) for update skip locked)
  returning x.*;
end $$;
revoke all on function public.creator_mail_claim(int) from public, anon, authenticated;
grant execute on function public.creator_mail_claim(int) to service_role;

create or replace function public.system_email_file(p jsonb)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_ref  uuid := nullif(p ->> 'ref', '')::uuid;
  v_cand uuid;
  v_id   uuid;
begin
  if v_ref is not null and (p ->> 'kind') like 'hiring%' then
    v_cand := coalesce((select i.candidate_id from public.hiring_interviews i where i.id = v_ref),
                       (select d.candidate_id from public.hiring_docs d where d.id = v_ref),
                       (select c.id from public.hiring_candidates c where c.id = v_ref));
  end if;
  insert into public.system_emails (kind, candidate_id, client_id, to_email, to_name, subject, body, reference, sent_by,
                                    status, provider_id, error, sent_at, ref_id, again_of)
  values (p ->> 'kind', v_cand, nullif(p ->> 'client', '')::uuid, coalesce(p ->> 'to', ''), nullif(p ->> 'to_name', ''),
          coalesce(p ->> 'subject', ''), nullif(p ->> 'body', ''), nullif(p ->> 'reference', ''),
          (select t.id from public.team_members t where nullif(p ->> 'by', '') is not null
              and lower(t.email) = lower(p ->> 'by') order by t.active desc limit 1),
          coalesce(nullif(p ->> 'status', ''), 'sent'), nullif(p ->> 'provider', ''), nullif(p ->> 'error', ''),
          case when coalesce(p ->> 'status', 'sent') = 'sent' then now() end,
          v_ref, nullif(p ->> 'again_of', '')::uuid)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.system_email_file(jsonb) from public, anon, authenticated;
grant execute on function public.system_email_file(jsonb) to service_role;

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
                 d.serial as reference, null::text as to_name, null::uuid as ref_id, null::uuid as again_of
            from public.supplier_emails e
            left join public.suppliers s on s.id = e.supplier_id
            left join public.documents d on d.id = e.document_id
            left join public.team_members t on t.id = e.sent_by
           where v_sup and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'client', e.id, e.kind, e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, null, null, null,
                 e.reference, k.name, null, null
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
                 null, null, null
            from public.invoice_emails e
            left join public.clients c on c.id = e.client_id
            left join public.team_members t on t.id = e.sent_by
           where v_bill and e.created_at >= v_a and e.created_at < v_b
             and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
          union all
          select 'manual', e.id, 'message', e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, e.supplier_id, s.name, s.code,
                 e.attachment, e.to_name, null, null
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
                 r.ref, k.name, null, e.again_of
            from public.creator_emails e
            left join public.creators k on k.id = e.creator_id
            left join public.creator_pay_requests r on r.id = e.request_id
            left join public.team_members t on t.id = e.sent_by
           where v_cr and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'system', e.id, e.kind, e.to_email, null, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, null, null, null,
                 e.reference, e.to_name, e.ref_id, e.again_of
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
                 null, null
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

/* A creator email that did not arrive, sent again by hand from Messages'
   Email log: queued once more in the words it was first filled with, as
   the colleague's, and sent by creator-mail as the first was. */
create or replace function public.creator_email_again(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  e  public.creator_emails;
  v_id uuid;
begin
  if me.id is null or not public.allowed('whatsapp', 'work') or not public.allowed('campaigns.creators', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  select * into e from public.creator_emails x where x.id = p_id for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if e.status not in ('failed', 'bounced', 'unknown') then return jsonb_build_object('error', 'not-failed'); end if;
  if coalesce(btrim(e.to_email), '') = '' or e.body is null then return jsonb_build_object('error', 'gone'); end if;
  if exists (select 1 from public.creator_emails x where x.again_of = e.id and x.status not in ('failed', 'bounced')) then
    return jsonb_build_object('error', 'already');
  end if;
  insert into public.creator_emails (purpose, creator_id, request_id, option_id, to_email, subject, body, status, sent_by, again_of)
  values (e.purpose, e.creator_id, e.request_id, e.option_id, e.to_email, e.subject, e.body, 'queued', me.id, e.id)
  returning id into v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'email.sent', coalesce((select c.name from public.creators c where c.id = e.creator_id), 'Creator'),
          e.subject || ' · emailed again');
  perform public.creator_mail_kick();
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.creator_email_again(uuid) from public, anon;
grant execute on function public.creator_email_again(uuid) to authenticated;

-- END OF SEND AGAIN ----------------------------------------------------------

select public.functions_tidy();
