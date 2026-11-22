-- ===========================================================================
-- CAMPAIGN CREATOR PAYMENTS — who has been paid for a campaign, read on its
-- record (2026-11-22)
-- ===========================================================================
-- WHY: the user approved screen (f) of the Bukku structure mockup
-- (mockups/bukku-structure, v3) on 2026-11-22: a campaign's Creators tab
-- names each booking's payment beside its step (Not billed, Processing,
-- Paid {day}), and the record's rail counts the creators paid, so who is
-- still owed for one campaign is read without opening Payments.
--
-- WHAT IT CHANGES
--   * `campaign_creator_bills(p_campaign)` (security definer, stable):
--     Creator Campaigns at View and Creator payments (`campaigns.pay`) at
--     View, else `denied`; a campaign the caller's client scope does not
--     reach, or none, `not-found`. Answers each booking from Confirmed on
--     (`option`, `creator`, its step, `posted_on`, whether the creator is
--     linked to Bukku) with the bill `creator_bills` holds for it (its Job
--     reference matched: `option_id`), a bill in hand before a paid one, as
--     the Payments queue chooses: number, status, bill date, paid day,
--     amount and currency. One read for the whole campaign; Bukku is not
--     asked. Never on a client page or the creator's page.
--
-- ORDER: this file, then the pages. A page served before it never asks; a
-- page meeting a database without it reads nothing and draws no payment
-- (the record stands as before). Safe to run twice.
--
-- ROLLBACK: drop function public.campaign_creator_bills(uuid);
-- ===========================================================================

create or replace function public.campaign_creator_bills(p_campaign uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_client uuid;
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns', 'view')
     or not public.ops_granted('campaigns.pay', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select m.client_id into v_client from public.campaigns m where m.id = p_campaign;
  if v_client is null or not public.client_seen(v_client, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  return jsonb_build_object('ok', true,
    'bookings', coalesce((select jsonb_agg(jsonb_build_object(
        'option', o.id, 'creator', o.creator_id, 'state', o.state, 'posted_on', o.posted_on,
        'linked', exists (select 1 from public.bukku_links l
                           where l.kind = 'creator' and l.record_id = o.creator_id and l.contact_id is not null),
        'bill', case when b.bill_id is not null then jsonb_build_object(
                  'number', b.number, 'status', b.status, 'date', b.bill_date,
                  'paid_on', case when b.status = 'paid' then coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date) end,
                  'amount', b.amount, 'currency', b.currency) end)
        order by o.position)
        from public.campaign_options o
        left join lateral (select y.* from public.creator_bills y where y.option_id = o.id and not y.gone
                            order by (y.status = 'processing') desc, (y.status = 'draft') desc, y.bill_date desc nulls last
                            limit 1) b on true
       where o.campaign_id = p_campaign
         and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb));
end $$;
revoke all on function public.campaign_creator_bills(uuid) from public, anon;
grant execute on function public.campaign_creator_bills(uuid) to authenticated;

-- END OF CAMPAIGN CREATOR PAYMENTS ------------------------------------------
select public.functions_tidy();
