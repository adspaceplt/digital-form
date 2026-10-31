-- ===========================================================================
-- QUOTATION CANCELLED — a quotation the client will not take up is
-- cancelled, in words as on the pages (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31: "Not proceeding --> Cancel. I prefer these
-- kind of wordings"): the quotation's ⋯ reads Cancel and its state
-- Cancelled; the Activity record said marked Not proceeding.
--
-- WHAT CHANGED
--   * `quotation_set` files {ref} cancelled. Its checks, refusals and answer
--     are unchanged; the stored status `not_proceeding` and the refusal
--     `not-proceeding` stay.
--
-- ORDER: this file (connector), then the pages. Either order is safe: only
-- the words of a new Activity record row change. Safe to run twice.
--
-- ROLLBACK: run QUOTATION WEBSITE FOLLOW-UP's quotation_set again.
-- ===========================================================================

-- QUOTATION CANCELLED -------------------------------------------------------

create or replace function public.quotation_set(p_id uuid, p_what text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_word text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if p_what = 'not_proceeding' then
    update public.quotations set status = 'not_proceeding' where id = p_id; v_word := ' cancelled';
  elsif p_what = 'proceeding' then
    update public.quotations set status = case when requested_at is not null then 'requested' else 'sent' end
     where id = p_id;
    v_word := ' restored';
  elsif p_what in ('no_contact', 'contact') then
    if v_q.source <> 'website' then return jsonb_build_object('error', 'bad-what'); end if;
    update public.quotations
       set no_contact_at = case when p_what = 'no_contact' then coalesce(no_contact_at, now()) end,
           no_contact_by = case when p_what = 'no_contact' then coalesce(no_contact_by, me.name) end
     where id = p_id;
    v_word := case when p_what = 'no_contact' then ' · Do not contact: off → on' else ' · Do not contact: on → off' end;
  elsif p_what = 'remove' then
    update public.quotations set removed_at = now(), removed_by = me.name where id = p_id; v_word := ' removed';
  elsif p_what = 'restore' then
    update public.quotations set removed_at = null, removed_by = null where id = p_id; v_word := ' restored';
  else
    return jsonb_build_object('error', 'bad-what');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || v_word);
  return jsonb_build_object('ok', true);
end $$;

-- END OF QUOTATION CANCELLED ------------------------------------------------

select public.functions_tidy();
