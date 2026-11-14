-- ===========================================================================
-- PAID DAY READ FOR EVERY PAID BILL (2026-11-14)
-- ===========================================================================
-- WHY: a paid bill's day is its payment voucher's (2026-11-12), read when a
-- creator's bills are read. A creator whose bookings were all paid before
-- then was never read again, so three bills read the day the portal first
-- saw them paid (10 and 12 Nov) for Bukku's voucher of 30 Sept (the user,
-- 2026-11-14: "I didnt make any payments these few days").
--
-- WHAT CHANGED
--   * `creator_bills_due()` also names a linked creator holding a paid bill
--     with no voucher day, so the night reads its voucher (ten a run).
--   * `creator_bills_list` sends each paid bill's day (`paid_on`), which the
--     creator's Payment pane reads as Paid {day}.
--
-- ORDER: this file (connector). Safe to run twice; nothing else changes.
--
-- ROLLBACK: CREATOR LINKED BY EARLIER JOB's `creator_bills_due` and
-- CREATOR FEES' `creator_bills_list`.
-- ===========================================================================

-- PAID DAY READ FOR EVERY PAID BILL —

create or replace function public.creator_bills_due()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('creator', l.record_id, 'contact', l.contact_id)), '[]'::jsonb)
    from public.bukku_links l
   where l.kind = 'creator'
     and (exists (select 1 from public.campaign_options o
                  where o.creator_id = l.record_id and o.state in ('posted', 'completed')
                    and not exists (select 1 from public.creator_bills b where b.option_id = o.id and b.status = 'paid' and not b.gone))
       or exists (select 1 from public.creator_earlier_jobs e
                  where e.creator_id = l.record_id and e.removed_at is null and length(public.creator_ref_key(e.ref)) >= 4
                    and not exists (select 1 from public.creator_bills b
                                     where b.creator_id = l.record_id and b.status = 'paid' and not b.gone
                                       and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                                         or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0)))
       or exists (select 1 from public.creator_bills b
                  where b.creator_id = l.record_id and b.status = 'paid' and not b.gone and b.paid_on is null))
$$;
revoke all on function public.creator_bills_due() from public, anon, authenticated;
grant execute on function public.creator_bills_due() to service_role;

/* A paid bill names its day (its voucher's, else the day it was first read
   paid) on the creator's Payment pane. */
create or replace function public.creator_bills_list(p_creator uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pay boolean := public.ops_granted('campaigns.pay', 'view'); l public.bukku_links;
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.creators c where c.id = p_creator) then return jsonb_build_object('error', 'not-found'); end if;
  select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = p_creator;
  return jsonb_build_object('ok', true, 'pay', v_pay, 'linked', l.contact_id is not null,
    'read_at', (select max(b.read_at) from public.creator_bills b where b.creator_id = p_creator),
    -- The creator fees (2026-11-13): the standard fee, and whether the
    -- account a bill is posted to is set, at Creator payments View alone.
    'standard_fee', case when v_pay then (select jsonb_build_object('amount', s.amount, 'currency', s.currency)
        from public.creator_standard_fees s where s.creator_id = p_creator) end,
    'bill_account', case when v_pay then exists (select 1 from public.bukku_settings s where s.id = 1 and s.bill_account is not null) end,
    'jobs', coalesce((select jsonb_agg(jsonb_build_object(
        'option', o.id, 'job', public.creator_job_ref(o.id), 'earlier_job', o.earlier_job, 'state', o.state,
        'campaign', m.title, 'campaign_id', m.id, 'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'fee', case when v_pay then (select jsonb_build_object('amount', f.amount, 'currency', f.currency, 'source', f.source)
                 from public.creator_fees f where f.option_id = o.id) end,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'amount', case when v_pay then b.amount end, 'currency', b.currency, 'paid_on', case when b.status = 'paid' then coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date) end)
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = p_creator and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb),
    -- a creator's past job IDs from before the portal, each with the bill
    -- whose reference or number holds it
    'past', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'ref', e.ref,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'amount', case when v_pay then b.amount end, 'currency', b.currency, 'paid_on', case when b.status = 'paid' then coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date) end)
                   from public.creator_bills b
                  where b.creator_id = p_creator and b.option_id is null and not b.gone
                    and length(public.creator_ref_key(e.ref)) >= 4
                    and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                      or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0)
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by e.ref desc)
        from public.creator_earlier_jobs e where e.creator_id = p_creator and e.removed_at is null), '[]'::jsonb),
    'earlier', coalesce((select jsonb_agg(jsonb_build_object('number', b.number, 'ref', b.ref, 'status', b.status, 'date', b.bill_date,
        'amount', case when v_pay then b.amount end, 'currency', b.currency, 'paid_on', case when b.status = 'paid' then coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date) end) order by b.bill_date desc nulls last)
        from public.creator_bills b where b.creator_id = p_creator and b.option_id is null and not b.gone
         and not exists (select 1 from public.creator_earlier_jobs e
                          where e.creator_id = p_creator and e.removed_at is null and length(public.creator_ref_key(e.ref)) >= 4
                            and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                              or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0))), '[]'::jsonb));
end $$;
revoke all on function public.creator_bills_list(uuid) from public, anon;
grant execute on function public.creator_bills_list(uuid) to authenticated;

-- END OF PAID DAY READ FOR EVERY PAID BILL ----------------------------------

select public.functions_tidy();
