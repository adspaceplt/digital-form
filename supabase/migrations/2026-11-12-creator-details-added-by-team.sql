-- ===========================================================================
-- CREATOR DETAILS ADDED BY THE TEAM — a colleague adds a creator's payment
-- details on the creator's Payment pane, approved as they are saved and
-- marked as added by the team (2026-11-12)
-- ===========================================================================
-- WHY (the user, 2026-11-12: "allow to add payment details inside the admin
-- portal, so our team member could add it. and straight approval (but mark
-- as internally added?)"): details came only from the creator's page or the
-- AP01 import, so a creator who sent theirs by WhatsApp waited on a link.
--
-- WHAT CHANGED
--   * `creator_pay_requests.entered_by` (the colleague who added the set;
--     null for a creator's own and an import).
--   * `creator_pay_add(p_creator, p_values)` (Creator payment details at
--     Work; `denied`, `not-found`, `bad` with `field`): checked as
--     `creator_pay_check` checks a creator's own, a number or detail left
--     blank keeping the one held as the creator's page does; a set waiting
--     is withdrawn, the one approved replaced, and the new set approved by
--     the colleague at once (inserted, then moved to approved, so the
--     creator payments sheet takes it as any approval). No email is sent:
--     the creator did not submit it. Filed `creator.updated`, Payment
--     details added by the team and approved.
--   * `creator_pay_list` answers `added_by` (the colleague's name).
--
-- ORDER: this file (connector), then the pages. A page served before reads
-- the list as before. Safe to run twice.
--
-- ROLLBACK: restate creator_pay_list from CREATOR PAYMENT DETAILS in
-- schema.sql; creator_pay_add and the column are left unused.
-- ===========================================================================

-- CREATOR DETAILS ADDED BY THE TEAM ------------------------------------------

alter table public.creator_pay_requests add column if not exists entered_by uuid references public.team_members(id);

create or replace function public.creator_pay_add(p_creator uuid, p_values jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  cr     public.creators;
  v_held public.creator_pay_requests;
  v_in   jsonb := coalesce(p_values, '{}'::jsonb) || jsonb_build_object('confirm', 'true');
  v_chk  jsonb;
  v      jsonb;
  v_seq  int;
  v_new  public.creator_pay_requests;
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into cr from public.creators x where x.id = p_creator for update;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  -- A number or detail left blank keeps the one held, as the creator's page does.
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
    if btrim(coalesce(v_in->>'address', '')) = '' and v_held.address is not null then v_in := v_in || jsonb_build_object('address', v_held.address); end if;
  end if;
  v_chk := public.creator_pay_check(v_in);
  if v_chk ? 'field' then return jsonb_build_object('error', 'bad', 'field', v_chk->>'field'); end if;
  v := v_chk->'values';
  update public.creator_pay_requests x set status = 'withdrawn' where x.creator_id = cr.id and x.status = 'pending';
  select coalesce(max(x.seq), 0) + 1 into v_seq from public.creator_pay_requests x where x.creator_id = cr.id;
  insert into public.creator_pay_requests (creator_id, seq, ref, bill_kind, id_no, legal_name, tin, address, currency,
    method, bank, account, payee, email, whatsapp, entered_by)
  values (cr.id, v_seq, public.creator_pay_ref(cr.creator_code, v_seq), v->>'bill_kind', v->>'id_no', v->>'legal_name',
    v->>'tin', v->>'address', v->>'currency', v->>'method', v->>'bank', v->>'account', v->>'payee', v->>'email', v->>'whatsapp', me.id)
  returning * into v_new;
  update public.creator_pay_requests x set status = 'replaced' where x.creator_id = cr.id and x.status = 'approved';
  update public.creator_pay_requests x set status = 'approved', decided_at = now(), decided_by = me.id where x.id = v_new.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', cr.name,
          coalesce(cr.creator_code || ' · ', '') || 'Payment details added by the team and approved · ' || v_new.ref || ' · ' ||
          public.creator_pay_method(v_new.method, v_new.bank) || ' ending ' || right(v_new.account, 4));
  return jsonb_build_object('ok', true, 'ref', v_new.ref);
end $$;
revoke all on function public.creator_pay_add(uuid, jsonb) from public, anon;
grant execute on function public.creator_pay_add(uuid, jsonb) to authenticated;

create or replace function public.creator_pay_list(p_creator uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_whole boolean := public.ops_granted('campaigns.pay', 'view');
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'whole', v_whole, 'decide', public.ops_granted('campaigns.pay', 'work'),
    'rows', coalesce((select jsonb_agg(public.creator_pay_json(r, v_whole)
                                       || jsonb_build_object('decided_by', m.name, 'added_by', a.name) order by r.seq desc)
                        from public.creator_pay_requests r
                        left join public.team_members m on m.id = r.decided_by
                        left join public.team_members a on a.id = r.entered_by
                       where r.creator_id = p_creator), '[]'::jsonb),
    'emails', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'purpose', e.purpose, 'to_email', e.to_email,
                          'status', e.status, 'created_at', e.created_at) order by e.created_at desc)
                         from public.creator_emails e where e.creator_id = p_creator), '[]'::jsonb));
end $$;
revoke all on function public.creator_pay_list(uuid) from public, anon;
grant execute on function public.creator_pay_list(uuid) to authenticated;

-- END OF CREATOR DETAILS ADDED BY THE TEAM -----------------------------------

select public.functions_tidy();
