-- ===========================================================================
-- CREATOR PAYMENTS QUEUE (2026-11-13)
-- ===========================================================================
-- WHY: paying creators meant opening each creator's page in turn (the user,
-- 2026-11-13: it will not scale to hundreds). The approved mockup puts every
-- creator's payment work in one queue on Creator Campaigns' Payments tab.
--
-- WHAT CHANGED
--   * `creator_payments_queue(p_paid_from)`: at Creators List View, the
--     payment details waiting for review (newest last) and every booking
--     posted in the portal or holding a live bill, with its creator, Job
--     reference, campaign, client (named only where the caller sees the
--     client), Pay by, currency and bill; a paid bill only where paid on or
--     after `p_paid_from` (else the first of last month, MYT). The fee and
--     every amount at Creator payments View alone, as `creator_bills_list`.
--   * The payment request notice (`campaign_options_posted_mail`) and the
--     details to review notice (`creator_pay_requests_notice`) open their
--     row in the queue (`tab=payments&row=`).
--
-- ORDER: this file (connector), then the pages. Safe to run twice; a page
-- served before never asks it.
--
-- ROLLBACK: the two notices from CREATOR PAYMENTS and CREATOR DETAILS
-- NOTICE; revoke the queue function in the SQL Editor.
-- ===========================================================================

-- CREATOR PAYMENTS QUEUE —

create or replace function public.creator_payments_queue(p_paid_from date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_pay  boolean := public.ops_granted('campaigns.pay', 'view');
  v_from date := coalesce(p_paid_from,
    (date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') - interval '1 month')::date);
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'pay', v_pay, 'work', public.ops_granted('campaigns.pay', 'work'),
    'paid_from', v_from,
    'bill_account', case when v_pay then exists (select 1 from public.bukku_settings s where s.id = 1 and s.bill_account is not null) end,
    'read_at', (select max(b.read_at) from public.creator_bills b),
    -- Payment details waiting for review, oldest first.
    'review', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'creator', cr.id, 'name', cr.name, 'code', cr.creator_code, 'ref', r.ref,
        'currency', r.currency, 'method_word', public.creator_pay_method(r.method, r.bank),
        'account_end', right(r.account, 4), 'created_at', r.created_at,
        'replaces', exists (select 1 from public.creator_pay_requests y where y.creator_id = r.creator_id and y.status = 'approved'))
        order by r.created_at)
        from public.creator_pay_requests r join public.creators cr on cr.id = r.creator_id
       where r.status = 'pending'), '[]'::jsonb),
    -- Every booking posted in the portal, or holding a live bill.
    'jobs', coalesce((select jsonb_agg(x.j order by x.k) from (
      select jsonb_build_object(
          'option', o.id, 'creator', cr.id, 'name', cr.name, 'code', cr.creator_code,
          'linked', exists (select 1 from public.bukku_links l where l.kind = 'creator' and l.record_id = cr.id and l.contact_id is not null),
          'job', public.creator_job_ref(o.id), 'state', o.state, 'campaign', m.title, 'campaign_id', m.id,
          'client', case when public.client_seen(c.id, 'view') then c.name end,
          'client_code', case when public.client_seen(c.id, 'view') then c.client_code end,
          'posted_on', o.posted_on, 'pay_by', o.pay_by,
          'currency', coalesce(f.currency, (select p.currency from public.creator_pay_requests p
                                             where p.creator_id = cr.id and p.status = 'approved' order by p.seq desc limit 1), 'MYR'),
          'fee', case when v_pay and f.option_id is not null then jsonb_build_object('amount', f.amount, 'currency', f.currency) end,
          'bill', case when b.bill_id is not null then jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                    'paid_on', coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date),
                    'amount', case when v_pay then b.amount end, 'currency', b.currency) end) as j,
          coalesce(o.pay_by, o.posted_on) as k
        from public.campaign_options o
        join public.creators cr on cr.id = o.creator_id
        join public.campaigns m on m.id = o.campaign_id
        join public.clients c on c.id = m.client_id
        left join public.creator_fees f on f.option_id = o.id
        left join lateral (select y.* from public.creator_bills y where y.option_id = o.id and not y.gone
                            order by (y.status = 'processing') desc, (y.status = 'draft') desc, y.bill_date desc nulls last limit 1) b on true
       where o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
         and ((b.bill_id is null and o.posted_on is not null and o.state in ('posted', 'completed'))
           or b.status in ('draft', 'processing')
           or (b.status = 'paid' and coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date, b.bill_date) >= v_from))
      ) x), '[]'::jsonb));
end $$;
revoke all on function public.creator_payments_queue(date) from public, anon;
grant execute on function public.creator_payments_queue(date) to authenticated;


-- The payment request and the details to review open their row in the
-- queue (`row=`), no longer the creator's own page.
create or replace function public.campaign_options_posted_mail()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.creators; m public.campaigns; v_ref text;
begin
  if new.state is distinct from 'posted' or old.state in ('posted', 'completed') then return null; end if;
  -- Told once a booking: a revert and a second move into Posted tell nobody again.
  if exists (select 1 from public.creator_emails e where e.option_id = new.id and e.purpose in ('request', 'posted')) then return null; end if;
  begin
    perform public.creator_mail_job('request', new.id);
    perform public.creator_mail_job('posted', new.id);
    select * into c from public.creators x where x.id = new.creator_id;
    select * into m from public.campaigns x where x.id = new.campaign_id;
    v_ref := public.creator_job_ref(new.id);
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    select tm.id, 'creator.payment', 'Creator payment request · ' || coalesce(v_ref, c.name),
           c.name || ' · ' || coalesce(m.title, '') || coalesce(' · Pay by ' || public.register_day(new.pay_by), ''),
           'https://digital.adspace.me/admin/?s=campaigns&tab=payments&row=' || new.id,
           'creator.payment:' || new.id || ':' || tm.id
      from public.team_members tm
     where tm.active and not coalesce(tm.system, false)
       and (tm.is_admin or tm.role = 'admin' or public.level_rank(tm.access ->> 'campaigns.pay') >= 2)
    on conflict (dedupe_key) do nothing;
  exception when others then
    return null;
  end;
  return null;
end $$;
revoke all on function public.campaign_options_posted_mail() from public, anon, authenticated;
create or replace trigger campaign_options_posted_mail after update of state on public.campaign_options
  for each row execute function public.campaign_options_posted_mail();

create or replace function public.creator_pay_requests_notice()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.creators;
begin
  if new.status is distinct from 'pending' then return null; end if;
  begin
    select * into c from public.creators x where x.id = new.creator_id;
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    select tm.id, 'creator.details', 'Payment details to review · ' || coalesce(c.name, new.ref),
           new.ref || ' · Sent on the creator page',
           'https://digital.adspace.me/admin/?s=campaigns&tab=payments&row=' || new.id,
           'creator.details:' || new.id || ':' || tm.id
      from public.team_members tm
     where tm.active and tm.removed_at is null and not coalesce(tm.system, false)
       and tm.department = 'marketing'
       and (tm.is_admin or tm.role = 'admin'
            or public.level_rank(coalesce(tm.access ->> 'campaigns.creators', tm.access ->> 'campaigns')) >= 1)
    on conflict (dedupe_key) do nothing;
  exception when others then
    return null;
  end;
  return null;
end $$;
revoke all on function public.creator_pay_requests_notice() from public, anon, authenticated;
create or replace trigger creator_pay_requests_notice after insert on public.creator_pay_requests
  for each row execute function public.creator_pay_requests_notice();

-- END OF CREATOR PAYMENTS QUEUE ----------------------------------------------

select public.functions_tidy();
