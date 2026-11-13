-- ===========================================================================
-- CREATOR MARGIN FOR ADMINS (2026-11-13)
-- ===========================================================================
-- WHY: a creator's Totals read Margin (the client rate less the creator's
-- fee) to anyone holding Creator payments at View; the user, 2026-11-13:
-- "I don't think this could be reviewed by anyone else, maybe just admins".
--
-- WHAT CHANGED
--   * `creator_totals`: `margin` is answered only where `perf_is_admin()`
--     (team.perfadmin, the admin's part for revenue and profit) holds,
--     beside Creator payments View and Creator Campaigns: Campaigns View.
--     Billed, Agreed, Outstanding and Paid are unchanged.
--
-- ORDER: this file (connector), then the pages (none change). Safe to run
-- twice.
--
-- ROLLBACK: creator_totals from CREATOR FEES.
-- ===========================================================================

-- CREATOR MARGIN FOR ADMINS —

create or replace function public.creator_totals(p_creator uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pay boolean := public.ops_granted('campaigns.pay', 'view'); v_camp boolean := public.allowed('campaigns.campaigns', 'view');
        v_admin boolean := public.perf_is_admin();
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.creators c where c.id = p_creator) then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true, 'pay', v_pay,
    -- What clients were billed for this creator: each booking's client rate
    -- from Confirmed on, in the currency its client is billed in, only on
    -- campaigns the caller may read.
    'billed', case when not v_camp then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bookings', x.n) order by x.cur)
        from (select case when public.client_bill_market(c.market, c.bill_sgd) = 'SG' then 'SGD' else 'MYR' end as cur,
                     sum(o.rate) as amt, count(*) as n
                from public.campaign_options o
                join public.campaigns m on m.id = o.campaign_id
                join public.clients c on c.id = m.client_id
               where o.creator_id = p_creator
                 and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
                 and public.client_seen(c.id, 'view')
               group by 1) x), '[]'::jsonb) end,
    -- The fees agreed with the creator, from Confirmed on, in the currency
    -- they are paid in (2026-11-13), at Creator payments View alone.
    'agreed', case when not v_pay then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bookings', x.n) order by x.cur)
        from (select f.currency as cur, sum(f.amount) as amt, count(*) as n
                from public.campaign_options o join public.creator_fees f on f.option_id = o.id
               where o.creator_id = p_creator
                 and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
               group by 1) x), '[]'::jsonb) end,
    -- Outstanding: the fees of those bookings no paid bill holds.
    'owed', case when not v_pay then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bookings', x.n) order by x.cur)
        from (select f.currency as cur, sum(f.amount) as amt, count(*) as n
                from public.campaign_options o join public.creator_fees f on f.option_id = o.id
               where o.creator_id = p_creator
                 and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
                 and not exists (select 1 from public.creator_bills b where b.option_id = o.id and b.status = 'paid' and not b.gone)
               group by 1) x), '[]'::jsonb) end,
    -- Margin: the client rate less the fee, each booking whose client is
    -- billed in the fee's own currency, never across currencies; an admin's
    -- alone (team.perfadmin, revenue and profit; 2026-11-13).
    'margin', case when not (v_pay and v_camp and v_admin) then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bookings', x.n) order by x.cur)
        from (select f.currency as cur, sum(o.rate - f.amount) as amt, count(*) as n
                from public.campaign_options o
                join public.creator_fees f on f.option_id = o.id
                join public.campaigns m on m.id = o.campaign_id
                join public.clients c on c.id = m.client_id
               where o.creator_id = p_creator
                 and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
                 and public.client_seen(c.id, 'view')
                 and f.currency = case when public.client_bill_market(c.market, c.bill_sgd) = 'SG' then 'SGD' else 'MYR' end
               group by 1) x), '[]'::jsonb) end,
    -- What was paid to the creator: every bill Bukku reads paid, earlier
    -- jobs included, at Creator payments View alone.
    'paid', case when not v_pay then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bills', x.n) order by x.cur)
        from (select coalesce(b.currency, 'MYR') as cur, sum(b.amount) as amt, count(*) as n
                from public.creator_bills b
               where b.creator_id = p_creator and b.status = 'paid' and not b.gone
               group by 1) x), '[]'::jsonb) end);
end $$;
revoke all on function public.creator_totals(uuid) from public, anon;
grant execute on function public.creator_totals(uuid) to authenticated;

-- END OF CREATOR MARGIN FOR ADMINS ----------------------------------------

select public.functions_tidy();
