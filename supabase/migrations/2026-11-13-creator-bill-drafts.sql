-- ===========================================================================
-- CREATOR BILL DRAFTS (2026-11-13)
-- ===========================================================================
-- WHY: Create bill makes a draft in Bukku (the user, 2026-11-13: "Keep it
-- normal and draft at bukku"), and a booking read Not billed until the
-- draft was posted (the user: "Bill created but still showing Not billed").
--
-- WHAT CHANGED
--   * `creator_bills.status` takes `draft`: a bill Bukku holds as a draft,
--     read by bukku-sync with `draft: true`, the booking reading Draft in
--     Bukku until it is posted (then Processing, then Paid).
--   * `creator_bills_take`: a draft row is kept as `draft`; a bill read Paid
--     after a draft tells the creator as one read Processing does.
--
-- ORDER: this file (connector), then bukku-sync, then the pages. Safe to
-- run twice. An old bukku-sync sends no draft and nothing changes.
--
-- ROLLBACK: update public.creator_bills set gone = true where status =
-- 'draft'; the check back to ('processing', 'paid'); creator_bills_take
-- from CREATOR PAYMENTS PAID ON BUKKU'S DAY.
-- ===========================================================================

-- CREATOR BILL DRAFTS -------------------------------------------------------

alter table public.creator_bills drop constraint if exists creator_bills_status_check;
alter table public.creator_bills add constraint creator_bills_status_check check (status in ('draft', 'processing', 'paid'));

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
    v_status := case when coalesce(x->>'draft', '') = 'true' then 'draft'
                     when nullif(x->>'balance', '') is null then coalesce(nullif(b.status, 'draft'), 'processing')
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
      if v_status = 'paid' and b.status in ('processing', 'draft') and b.paid_told_at is null and v_opt is not null then
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

-- END OF CREATOR BILL DRAFTS ------------------------------------------------

select public.functions_tidy();
