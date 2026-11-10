-- ===========================================================================
-- CREATOR PAGE DETAILS MASKED — the creator's link shows their payment
-- details partly hidden (2026-11-10)
-- ===========================================================================
-- WHY (the user, 2026-11-10: "the link could accidentally fall to others and
-- it looks dangerous to have full details"): `creator_pay_form` (anon, the
-- creator's code) answered the legal name, account holder, billing address,
-- TIN, email and WhatsApp in full; only the ID and account numbers were cut
-- to their last four.
--
-- WHAT CHANGED
--   * `creator_mask_words`, `creator_mask_email`, `creator_mask_phone`,
--     `creator_mask_text` and `creator_pay_masked(jsonb)` (internal): a name
--     a letter a word (T** S*** Y***), an email its first two letters and
--     last before the @ (ha*******3@gmail.com), a number its first two and
--     last four digits (60*****1234), an address its last part after a
--     comma, a TIN its last four.
--   * `creator_pay_form` answers `last` and `paid` masked (`masked` true) and
--     the creator's WhatsApp masked. The console (`creator_pay_list`), the
--     emails and the payments sheet read the values whole, as before.
--   * `creator_pay_submit`: a legal name, TIN, address, account holder,
--     email or WhatsApp left blank keeps the one held (as the ID and account
--     numbers already did), so Change details never needs the full value
--     on the page.
--
-- ORDER: this file (connector), then the pages. A page served before reads
-- the masked values in its form; sent back unchanged they fail the checks
-- (an email with stars is refused), so nothing masked is ever stored.
-- Safe to run twice.
--
-- ROLLBACK: CREATOR PAGE PAYMENTS's creator_pay_form and CREATOR PAYMENT
-- DETAILS's creator_pay_submit again; drop the five mask functions.
-- ===========================================================================

create or replace function public.creator_mask_words(p text)
returns text language sql immutable set search_path = public as $$
  select case when nullif(btrim(coalesce(p, '')), '') is null then null else
    (select string_agg(left(w, 1) || repeat('*', greatest(char_length(w) - 1, 1)), ' ' order by n)
       from regexp_split_to_table(btrim(p), '\s+') with ordinality as t(w, n)) end
$$;
revoke all on function public.creator_mask_words(text) from public, anon, authenticated;

create or replace function public.creator_mask_email(p text)
returns text language sql immutable set search_path = public as $$
  select case when coalesce(p, '') !~ '@' then public.creator_mask_words(p) else
    (select case when char_length(l) <= 2 then left(l, 1) || '*'
                 else left(l, 2) || repeat('*', greatest(char_length(l) - 3, 1)) || right(l, 1) end
            || '@' || split_part(p, '@', 2)
       from (select split_part(p, '@', 1) as l) x) end
$$;
revoke all on function public.creator_mask_email(text) from public, anon, authenticated;

create or replace function public.creator_mask_phone(p text)
returns text language sql immutable set search_path = public as $$
  select case when char_length(d) < 6 then nullif(repeat('*', char_length(d)), '')
              else left(d, 2) || repeat('*', char_length(d) - 6) || right(d, 4) end
    from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x
$$;
revoke all on function public.creator_mask_phone(text) from public, anon, authenticated;

/* An address its last part (the postcode and city) after the first, the
   rest starred; a TIN its last four. */
create or replace function public.creator_mask_text(p text, p_kind text)
returns text language sql immutable set search_path = public as $$
  select case when nullif(btrim(coalesce(p, '')), '') is null then null
    when p_kind = 'address' and p ~ ',' then '****, ' || btrim(regexp_replace(p, '^.*,', ''))
    when p_kind = 'address' then public.creator_mask_words(p)
    else repeat('*', greatest(char_length(p) - 4, 1)) || right(p, 4) end
$$;
revoke all on function public.creator_mask_text(text, text) from public, anon, authenticated;

create or replace function public.creator_pay_masked(j jsonb)
returns jsonb language sql immutable set search_path = public as $$
  select case when j is null or jsonb_typeof(j) <> 'object' then j else j || jsonb_build_object(
    'legal_name', public.creator_mask_words(j->>'legal_name'),
    'payee', public.creator_mask_words(j->>'payee'),
    'address', public.creator_mask_text(j->>'address', 'address'),
    'tin', public.creator_mask_text(j->>'tin', 'tin'),
    'email', public.creator_mask_email(j->>'email'),
    'whatsapp', public.creator_mask_phone(j->>'whatsapp'),
    'masked', true) end
$$;
revoke all on function public.creator_pay_masked(jsonb) from public, anon, authenticated;

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
    'last', public.creator_pay_masked(public.creator_pay_json(v_last, false)),
    'paid', public.creator_pay_masked(public.creator_pay_json(v_paid, false)),
    'days', jsonb_build_object('myr', public.app_setting('creator_pay_days_myr', v_day),
                               'other', public.app_setting('creator_pay_days_other', v_day)),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'job', public.creator_job_ref(o.id), 'campaign', m.title, 'state', o.state,
        'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'paid_at', b.paid_seen_at, 'amount', b.amount, 'currency', b.currency)
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = cr.id and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb));
end $$;
grant execute on function public.creator_pay_form(text) to anon, authenticated;

create or replace function public.creator_pay_submit(p_code text, p_values jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr     public.creators;
  v_held public.creator_pay_requests;
  v_in   jsonb := coalesce(p_values, '{}'::jsonb);
  v_chk  jsonb;
  v      jsonb;
  v_seq  int;
  v_new  public.creator_pay_requests;
begin
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from public.creators x where x.id = v_id for update;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not cr.active then return jsonb_build_object('error', 'inactive'); end if;
  if not public.creator_pay_due(cr.id) then return jsonb_build_object('error', 'not-due'); end if;
  if (select count(*) from public.creator_pay_requests x where x.creator_id = cr.id
       and x.created_at > now() - interval '1 day') >= 5 then
    return jsonb_build_object('error', 'too-many');
  end if;
  -- A number left blank keeps the one held, where nothing it belongs to moved;
  -- a detail the page shows masked, left blank, keeps the one held.
  select * into v_held from public.creator_pay_requests x where x.creator_id = cr.id and x.status in ('approved', 'pending')
   order by x.seq desc limit 1;
  if v_held.id is not null then
    if btrim(coalesce(v_in->>'id_no', '')) = '' and v_in->>'bill_kind' = v_held.bill_kind then
      v_in := v_in || jsonb_build_object('id_no', v_held.id_no);
    end if;
    if btrim(coalesce(v_in->>'account', '')) = '' and v_in->>'method' = v_held.method
       and upper(coalesce(v_in->>'currency', '')) = v_held.currency and coalesce(v_in->>'bank', '') = coalesce(v_held.bank, '') then
      v_in := v_in || jsonb_build_object('account', v_held.account);
    end if;
    if btrim(coalesce(v_in->>'legal_name', '')) = '' then v_in := v_in || jsonb_build_object('legal_name', v_held.legal_name); end if;
    if btrim(coalesce(v_in->>'tin', '')) = '' and v_held.tin is not null then v_in := v_in || jsonb_build_object('tin', v_held.tin); end if;
    if btrim(coalesce(v_in->>'address', '')) = '' then v_in := v_in || jsonb_build_object('address', v_held.address); end if;
    if btrim(coalesce(v_in->>'payee', '')) = '' then v_in := v_in || jsonb_build_object('payee', v_held.payee); end if;
    if btrim(coalesce(v_in->>'email', '')) = '' then v_in := v_in || jsonb_build_object('email', v_held.email); end if;
    if btrim(coalesce(v_in->>'whatsapp', '')) = '' then v_in := v_in || jsonb_build_object('whatsapp', v_held.whatsapp); end if;
  end if;
  v_chk := public.creator_pay_check(v_in);
  if v_chk ? 'field' then return jsonb_build_object('error', 'bad', 'field', v_chk->>'field'); end if;
  v := v_chk->'values';
  update public.creator_pay_requests x set status = 'withdrawn' where x.creator_id = cr.id and x.status = 'pending';
  select coalesce(max(x.seq), 0) + 1 into v_seq from public.creator_pay_requests x where x.creator_id = cr.id;
  insert into public.creator_pay_requests (creator_id, seq, ref, bill_kind, id_no, legal_name, tin, address, currency,
    method, bank, account, payee, email, whatsapp)
  values (cr.id, v_seq, public.creator_pay_ref(cr.creator_code, v_seq), v->>'bill_kind', v->>'id_no', v->>'legal_name',
    v->>'tin', v->>'address', v->>'currency', v->>'method', v->>'bank', v->>'account', v->>'payee', v->>'email', v->>'whatsapp')
  returning * into v_new;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Creator page', 'creator.updated', cr.name,
          coalesce(cr.creator_code || ' · ', '') || 'Payment details submitted · ' || v_new.ref || ' · ' ||
          public.creator_pay_method(v_new.method, v_new.bank) || ' ending ' || right(v_new.account, 4));
  perform public.creator_mail_queue('received', v_new.id);
  perform public.creator_mail_queue('review', v_new.id);
  return jsonb_build_object('ok', true, 'ref', v_new.ref);
end $$;
grant execute on function public.creator_pay_submit(text, jsonb) to anon, authenticated;

select public.functions_tidy();

-- END OF CREATOR PAGE DETAILS MASKED -----------------------------------------
