-- ===========================================================================
-- CREATOR PAGE PAYMENTS — the creator's own page reads its bookings'
-- payments beside its payment details (2026-11-10, Creator R5). Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user's approved mockup, 2026-11-08: the creator page's
-- Payments tab, "status from Bukku", amounts shown, "No one marks Paid by
-- hand")
-- * `creator_pay_form(p_code)` (anon, the creator's code counted as before)
--   also answers `payments`: each booking from Confirmed on with its Job
--   reference, campaign, state, posted and pay-by days and the bill read for
--   it (number, Processing or Paid, amount, currency, date), never another
--   creator's; and `days`, the working days payment takes in MYR and in
--   other currencies (Settings, Clients: Creator payments).
-- ===========================================================================

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
  return jsonb_build_object('ok', true, 'due', public.creator_pay_due(cr.id), 'whatsapp', cr.whatsapp,
    'last', public.creator_pay_json(v_last, false), 'paid', public.creator_pay_json(v_paid, false),
    'days', jsonb_build_object('myr', public.app_setting('creator_pay_days_myr', v_day),
                               'other', public.app_setting('creator_pay_days_other', v_day)),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'job', public.creator_job_ref(o.id), 'campaign', m.title, 'state', o.state,
        'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'amount', b.amount, 'currency', b.currency)
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = cr.id and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb));
end $$;
grant execute on function public.creator_pay_form(text) to anon, authenticated;

-- Rollback: run CREATOR PAYMENT DETAILS' creator_pay_form again.

-- END OF CREATOR PAGE PAYMENTS ------------------------------------------------

select public.functions_tidy();
