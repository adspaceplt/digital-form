-- ===========================================================================
-- CREATOR TOTALS — a creator's page reads what clients were billed for them
-- and what was paid to them (2026-11-12)
-- ===========================================================================
-- WHY (the user, 2026-11-12: "calculate the amount that we paid to this
-- creator (a total), and how much this creator being reported amount to our
-- clients … both are different"; "you may go ahead and build the totals").
--
-- WHAT CHANGED
--   * `creator_totals(p_creator)`: Billed to clients (each booking's client
--     rate from Confirmed on, by the client's billing currency, campaigns the
--     caller reads) and Paid to creator (bills Bukku reads paid, at Creator
--     payments View alone), each a line a currency, never added across.
--
-- ORDER: this file (connector), then the pages. A page served before never
-- asks it. Safe to run twice.
--
-- ROLLBACK: drop function public.creator_totals(uuid);
-- ===========================================================================

-- CREATOR TOTALS -------------------------------------------------------------

create or replace function public.creator_totals(p_creator uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pay boolean := public.ops_granted('campaigns.pay', 'view');
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.creators c where c.id = p_creator) then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true, 'pay', v_pay,
    -- What clients were billed for this creator: each booking's client rate
    -- from Confirmed on, in the currency its client is billed in, only on
    -- campaigns the caller may read.
    'billed', case when not public.allowed('campaigns.campaigns', 'view') then null else
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

-- END OF CREATOR TOTALS ------------------------------------------------------

select public.functions_tidy();
