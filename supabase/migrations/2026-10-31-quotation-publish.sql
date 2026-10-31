-- ===========================================================================
-- QUOTATION PUBLISHED WITHOUT WHATSAPP — a website quotation's rates shown
-- on its link with no message sent (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31: "Not everything needs a tick why not show button
-- like publish quotation / send quotation"): a quotation the team has
-- reviewed was shown to the prospect only by Send quotation, which also
-- queues the quotation-ready WhatsApp. The team at times tells the prospect
-- in its own chat, and wants the rates shown alone.
--
-- WHAT CHANGED
--   * `quotation_release(p_id, p_whatsapp)`: the one body of the two, no
--     page's to call (revoked from public, anon and authenticated). Its
--     checks are Send quotation's: Quotations at Work, the client in scope,
--     a website quotation, `again` once sent, `not-proceeding`, `revised`;
--     `no-contact` only where the WhatsApp is asked for (a prospect marked
--     Do not contact may still read the link they already hold).
--   * `quotation_send(p_id)` is `quotation_release(p_id, true)`: unchanged.
--   * `quotation_publish(p_id)` (authenticated) is `quotation_release(p_id,
--     false)`: valid from today, nothing queued, filed "{ref} published on
--     the quotation link · valid until …".
--
-- ORDER: this file (connector), then the pages. A page served before never
-- asks `quotation_publish`; a page served after on a database without it
-- reads "This needs a database update". Safe to run twice.
--
-- ROLLBACK: run QUOTATION REVIEW FIXES' quotation_send again; the two new
-- functions are then unused and harmless.
-- ===========================================================================

-- QUOTATION PUBLISHED WITHOUT WHATSAPP --------------------------------------

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
  -- Valid from the day it is shown, as the prospect first sees it.
  v_days := coalesce(public.app_setting('quote_valid_days', v_today), 30)::int;
  update public.quotations
     set released_at = now(), released_by = me.name, valid_until = v_today + v_days
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

create or replace function public.quotation_send(p_id uuid)
returns jsonb
language sql volatile security definer set search_path = public as $$
  select public.quotation_release(p_id, true);
$$;
revoke all on function public.quotation_send(uuid) from public, anon;
grant execute on function public.quotation_send(uuid) to authenticated;

create or replace function public.quotation_publish(p_id uuid)
returns jsonb
language sql volatile security definer set search_path = public as $$
  select public.quotation_release(p_id, false);
$$;
revoke all on function public.quotation_publish(uuid) from public, anon;
grant execute on function public.quotation_publish(uuid) to authenticated;

-- END OF QUOTATION PUBLISHED WITHOUT WHATSAPP -------------------------------

select public.functions_tidy();
