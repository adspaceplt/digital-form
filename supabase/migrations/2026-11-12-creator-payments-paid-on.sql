-- ===========================================================================
-- CREATOR PAYMENTS PAID ON BUKKU'S DAY — a creator's bill reads Paid on the
-- day of Bukku's payment voucher, and the creator's page sends no amount
-- (2026-11-12)
-- ===========================================================================
-- WHY (the user, 2026-11-12: "the paid date is not even accurate, it should
-- follow Bukku's bill payment voucher not today's date"; "could you not show
-- the price … anyone who holds the link would be able to see"): a bill read
-- Paid took the day the portal first read it, and the creator's link sent
-- each bill's number and amount.
--
-- WHAT CHANGED
--   * `creator_bills.paid_on`: the latest date of the payments Bukku applied
--     to the bill (`bukku-sync` reads a paid bill's linked payments once).
--   * `creator_bills_take` keeps `paid_on` from the rows it is sent, an
--     earlier one kept where a row names none.
--   * `creator_pay_form`'s payments answer a bill's state and paid day
--     alone (`paid_on`, else the day the portal read it paid): never its
--     number, amount or currency.
--
-- ORDER: this file (connector), then `bukku-sync`, then the pages. A page
-- served before reads no amount and no paid day (it shows the state). Safe
-- to run twice.
--
-- ROLLBACK: restate creator_bills_take and creator_pay_form from CREATORS
-- FROM AP01 and CREATOR PAYMENTS in schema.sql; the column is left unused.
-- ===========================================================================

-- CREATOR PAYMENTS PAID ON BUKKU'S DAY --------------------------------------

alter table public.creator_bills add column if not exists paid_on date;

create or replace function public.creator_bills_take(p_creator uuid, p_contact bigint, p_rows jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  x jsonb; b public.creator_bills; v_id bigint; v_status text; v_opt uuid; v_n int := 0; v_paid int := 0;
  v_seen bigint[] := '{}'; v_post boolean;
begin
  if p_creator is null or jsonb_typeof(p_rows) is distinct from 'array' then return jsonb_build_object('error', 'bad-request'); end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    v_id := (x->>'id')::bigint;
    if v_id is null then continue; end if;
    v_seen := v_seen || v_id;
    v_opt := public.creator_bill_option(p_creator, x->>'ref', x->>'number');
    select * into b from public.creator_bills y where y.bill_id = v_id for update;
    -- A bill read with no balance keeps the state it had, never Paid by default.
    v_status := case when nullif(x->>'balance', '') is null then coalesce(b.status, 'processing')
                     when (x->>'balance')::numeric <= 0 then 'paid' else 'processing' end;
    v_post := v_opt is not null and exists (select 1 from public.campaign_options o where o.id = v_opt and o.posted_on is not null);
    if b.bill_id is null then
      insert into public.creator_bills (bill_id, creator_id, contact_id, number, ref, bill_date, amount, balance, currency, status,
                                        option_id, read_at, paid_seen_at, paid_told_at, paid_on)
      values (v_id, p_creator, p_contact, left(x->>'number', 60), left(x->>'ref', 200), nullif(x->>'date', '')::date,
              (x->>'amount')::numeric, nullif(x->>'balance', '')::numeric, left(coalesce(x->>'currency', 'MYR'), 3), v_status, v_opt, now(),
              case when v_status = 'paid' then now() end,
              case when v_status = 'paid' then now() end,
              case when v_status = 'paid' then nullif(x->>'paid_on', '')::date end);
      -- A bill first read already paid is told only for a booking posted in the
      -- portal; one from before the portal (no posted day) tells nobody.
      if v_status = 'paid' and v_post then
        perform public.creator_mail_job('paid', v_opt);
        v_paid := v_paid + 1;
      end if;
    else
      update public.creator_bills y set creator_id = p_creator, contact_id = p_contact, number = left(x->>'number', 60),
        ref = left(x->>'ref', 200), bill_date = nullif(x->>'date', '')::date, amount = (x->>'amount')::numeric,
        balance = coalesce(nullif(x->>'balance', '')::numeric, y.balance), currency = left(coalesce(x->>'currency', 'MYR'), 3), status = v_status,
        option_id = v_opt, gone = false, read_at = now(),
        paid_seen_at = case when v_status = 'paid' then coalesce(y.paid_seen_at, now()) end,
        paid_on = case when v_status = 'paid' then coalesce(nullif(x->>'paid_on', '')::date, y.paid_on) end
       where y.bill_id = v_id;
      if v_status = 'paid' and b.status = 'processing' and b.paid_told_at is null and v_opt is not null then
        update public.creator_bills y set paid_told_at = now() where y.bill_id = v_id;
        perform public.creator_mail_job('paid', v_opt);
        v_paid := v_paid + 1;
      end if;
    end if;
    v_n := v_n + 1;
  end loop;
  update public.creator_bills y set gone = true where y.creator_id = p_creator and not (y.bill_id = any(v_seen)) and not y.gone;
  return jsonb_build_object('ok', true, 'bills', v_n, 'told', v_paid);
end $$;
revoke all on function public.creator_bills_take(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.creator_bills_take(uuid, bigint, jsonb) to service_role;

create or replace function public.creator_pay_form(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr     public.creators;
  v_last public.creator_pay_requests;
  v_paid public.creator_pay_requests;
  v_day  date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from public.creators x where x.id = v_id;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not cr.active then return jsonb_build_object('error', 'inactive'); end if;
  select * into v_last from public.creator_pay_requests x where x.creator_id = cr.id and x.status <> 'withdrawn'
   order by x.seq desc limit 1;
  select * into v_paid from public.creator_pay_requests x where x.creator_id = cr.id and x.status = 'approved'
   order by x.decided_at desc limit 1;
  return jsonb_build_object('ok', true, 'due', public.creator_pay_due(cr.id), 'whatsapp', public.creator_mask_phone(cr.whatsapp),
    'address_needed', v_paid.id is not null and v_paid.address is null,
    'last', public.creator_pay_masked(public.creator_pay_json(v_last, false)),
    'paid', public.creator_pay_masked(public.creator_pay_json(v_paid, false)),
    'days', jsonb_build_object('myr', public.app_setting('creator_pay_days_myr', v_day),
                               'other', public.app_setting('creator_pay_days_other', v_day)),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'job', public.creator_job_ref(o.id), 'campaign', m.title, 'state', o.state,
        'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'bill', (select jsonb_build_object('status', b.status,
                   'paid_on', coalesce(b.paid_on, (b.paid_seen_at at time zone 'Asia/Kuala_Lumpur')::date))
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = cr.id and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb));
end $$;
grant execute on function public.creator_pay_form(text) to anon, authenticated;

-- END OF CREATOR PAYMENTS PAID ON BUKKU'S DAY -------------------------------

select public.functions_tidy();
