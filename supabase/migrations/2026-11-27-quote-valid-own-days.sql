-- ===========================================================================
-- QUOTATION VALID FOR ITS OWN DAYS (2026-11-27)
-- ===========================================================================
-- WHY: ADP/REQ2611-SBD (a website request) was set Valid for: 14 days in
-- Build quote, yet `quotation_release` read only `quote_valid_days` (30)
-- and `quotation_edit` left a website request's valid_until as it was.
-- WHAT IT CHANGES: one rule. A quotation is valid for its own
-- selection.valid days (14, 30, 45, 60 or 90), else `quote_valid_days`,
-- counted from the day it is published: `quotation_release` (Send and
-- Publish) reads it; `quotation_edit` reads it for every source (a bad
-- value is `bad-valid`) and dates a website quotation already sent from
-- its send, one not yet sent from today (Send dates it again).
-- ROLLBACK: re-run `quotation_release` from 2026-11-26-quotations-confirmed.sql
-- and `quotation_edit` from 2026-11-27-colleague-save-website-request.sql.
-- Safe to run twice.

create or replace function public.quotation_edit(p_id uuid, p_sel jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_c public.clients;
  v_on date := public.doc_day_of(p_sel->>'date');
  v_card jsonb;
  v_ref text;
  v_was_ref text;
  v_p jsonb;
  v_fx numeric;
  v_now timestamptz := now();
  v_days int;
  v_v jsonb;
  v_sel jsonb;
  v_was numeric;
  v_is numeric;
  v_cur text;
  v_n int;
  v_doc text;
  v_x jsonb;
  v_b jsonb;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  if v_on is not null and v_on <> (v_now at time zone 'Asia/Kuala_Lumpur')::date then
    v_now := (v_on::timestamp + (v_now at time zone 'Asia/Kuala_Lumpur')::time) at time zone 'Asia/Kuala_Lumpur';
  end if;
  v_on := (v_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_card := public.quote_card(v_on, nullif(btrim(coalesce(p_sel->>'card', '')), ''));
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.removed_at is not null then return jsonb_build_object('error', 'removed'); end if;
  if v_q.signed_at is not null or v_q.reviewed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = v_q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if v_q.sent_out_at is not null or v_q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  -- A quotation a letter or service lines came from keeps its figures
  -- (2026-11-07), as its removal is refused then: Edit makes its revision.
  select count(*) into v_n from public.client_services s where s.quotation_id = v_q.id;
  if v_n > 0 then return jsonb_build_object('error', 'lines', 'count', v_n); end if;
  select d.number into v_doc from public.client_documents d
   where d.lines @> jsonb_build_array(jsonb_build_object('quotation_id', v_q.id::text))
   order by d.created_at limit 1;
  if v_doc is not null then return jsonb_build_object('error', 'letter', 'number', v_doc); end if;
  select * into v_c from public.clients where id = v_q.client_id;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- As the team builds it: a colleague is saving, so their edits, names,
  -- descriptions and its one brand are kept on a website request too
  -- (COLLEAGUE'S SAVE ON A WEBSITE REQUEST, 2026-11-27); the public page
  -- itself never adjusts nor sends brands (quotation_make).
  v_sel := p_sel - 'client' - 'date';
  v_p := public.quote_fx_out(public.quote_compose(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id, v_on), v_fx),
           v_sel, true), v_fx);
  if v_p ? 'error' then return v_p; end if;
  v_x := public.quote_extras(case when v_q.source = 'console' then v_sel else '{}'::jsonb end);
  if v_x ? 'error' then return v_x; end if;
  if v_q.source = 'console' then
    v_b := public.quote_client_extras(v_c.id, v_p->'lines', v_sel);
    if v_b ? 'error' then return v_b; end if;
    v_x := v_x || v_b;
  end if;
  if jsonb_typeof(v_p->'lines') is distinct from 'array' or jsonb_array_length(v_p->'lines') = 0 then
    return jsonb_build_object('error', 'nothing-priced');
  end if;
  v_was := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  -- Valid for its own days (Build quote's Valid for), website requests
  -- too, else the Business setting (QUOTATION VALID FOR ITS OWN DAYS).
  v_v := public.quote_extras(jsonb_build_object('valid', v_sel->'valid'));
  if v_v ? 'error' then return v_v; end if;
  v_days := coalesce((v_v->>'valid_days')::int, public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  /* A team's quotation dated into another month takes that month's
     reference (it has not been sent); the one it held is kept, never
     issued again. */
  v_ref := v_q.ref; v_was_ref := v_q.ref;
  if v_q.source = 'console' and v_q.ref !~ ('^ADP/QT' || to_char(v_on, 'YYMM') || '-') then
    -- A draft moved to another month takes that month's draft reference and
    -- spends no number (QUOTATIONS CONFIRMED, 2026-11-26).
    if v_q.confirmed_at is null then
      v_ref := public.quote_draft_ref(v_now);
    else
      v_ref := public.quote_ref(v_q.brand, v_now);
      insert into public.quotation_refs_kept (ref) values (v_q.ref) on conflict do nothing;
    end if;
  end if;
  update public.quotations
     set ref = v_ref, version = v_card->>'version', version_id = (v_card->>'id')::uuid, selection = v_sel,
         lines = v_p->'lines', totals = v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request') || v_x,
         -- A team's quotation is dated when it is made ready; a website one
         -- keeps the day it was asked for (its validity runs from its send).
         issued_at = case when v_q.source = 'console' then v_now else issued_at end,
         -- A website quotation already sent runs from the day it was sent.
         valid_until = case when v_q.source <> 'console' and v_q.released_at is not null
                            then (v_q.released_at at time zone 'Asia/Kuala_Lumpur')::date + v_days
                            else (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days end
   where id = v_q.id
  returning * into v_q;
  v_is := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_cur := case when v_fx is null then 'RM ' else 'S$ ' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_c.name,
          case when v_ref <> v_was_ref then v_was_ref || ' → ' else '' end || v_q.ref || ' edited · ' ||
          coalesce(v_cur || to_char(v_was, 'FM999,999,990.00'), 'not set') || ' → ' ||
          coalesce(v_cur || to_char(v_is, 'FM999,999,990.00'), 'not set') ||
          ' · Rate Card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref);
end $$;
revoke all on function public.quotation_edit(uuid, jsonb) from public, anon;
grant execute on function public.quotation_edit(uuid, jsonb) to authenticated;

create or replace function public.quotation_release(p_id uuid, p_whatsapp boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days int;
  v_wa text;
  v_name text;
  v_queued boolean := false;
  v_on boolean;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_whatsapp and not public.send_ok('whatsapp') then return jsonb_build_object('error', 'send-off'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.source <> 'website' then return jsonb_build_object('error', 'bad-quotation'); end if;
  if q.released_at is not null then return jsonb_build_object('ok', true, 'again', true, 'valid_until', q.valid_until); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  -- A prospect marked Do not contact is not messaged (audit 2026-10-30);
  -- publishing sends them nothing.
  if coalesce(p_whatsapp, true) and q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  -- The day's WhatsApp messages for website quotations are held to
  -- `quote_wa_day` (counted under one lock); at the limit nothing changes and
  -- Publish still shows the rates.
  if coalesce(p_whatsapp, true) and not public.quote_wa_allowed(q.id) then
    return jsonb_build_object('error', 'wa-limit', 'cap', coalesce(public.app_setting('quote_wa_day', v_today), 30));
  end if;
  -- Valid for its own days (Build quote's Valid for), else the Business
  -- setting, from the day it is shown, as the prospect first sees it.
  v_days := coalesce((public.quote_extras(jsonb_build_object('valid', q.selection->'valid'))->>'valid_days')::int,
                     public.app_setting('quote_valid_days', v_today), 30)::int;
  -- Send quotation is a request's confirmation: it takes its reference
  -- now (QUOTATIONS CONFIRMED, 2026-11-26); one confirmed before keeps its.
  update public.quotations
     set released_at = now(), released_by = me.name, valid_until = v_today + v_days,
         ref = case when confirmed_at is null then public.quote_ref(brand, now()) else ref end,
         confirmed_at = coalesce(confirmed_at, now()), confirmed_by = coalesce(confirmed_by, me.name)
   where id = q.id returning * into q;
  if coalesce(p_whatsapp, true) then
    v_wa := public.quote_website_number(q.contact->>'whatsapp');
    v_name := coalesce(nullif(btrim(q.contact->>'name'), ''), q.brand);
    -- Sent on WhatsApp only where its template is on: wa_enqueue says nothing
    -- when it is off (audit 2026-10-30).
    select exists (select 1 from public.wa_templates x where x.purpose = 'quote_ready' and x.active and x.name <> '') into v_on;
    begin
      if v_on and v_wa ~ '^(60|65)[0-9]{8,10}$' then
        perform public.wa_enqueue('quote_ready', v_wa, v_name,
          jsonb_build_array(public.contact_greeting(q.contact->>'salutation', v_name),
                            coalesce(q.contact->>'brand', q.brand), q.ref),
          'quotation', q.id, q.client_id, q.access_key);
        v_queued := true;
      end if;
    exception when others then v_queued := false;
    end;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || case when coalesce(p_whatsapp, true)
                        then ' sent to the prospect' || case when v_queued then ' on WhatsApp' else '' end
                        else ' published on the quotation link' end ||
          ' · valid until ' || public.register_day(q.valid_until));
  return jsonb_build_object('ok', true, 'valid_until', q.valid_until, 'whatsapp', v_queued);
end $$;
revoke all on function public.quotation_release(uuid, boolean) from public, anon, authenticated;

-- END OF QUOTATION VALID FOR ITS OWN DAYS -----------------------------------
