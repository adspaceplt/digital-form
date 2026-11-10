-- ===========================================================================
-- WEBSITE QUOTATIONS ON WHATSAPP LIMITED AGAIN — `quote_wa_day` holds the
-- day's Quotation ready messages to website prospects (2026-11-10)
-- ===========================================================================
-- WHY (the user, 2026-11-10: "limit work"): since a website quotation waits
-- for the team (2026-10-29), every Quotation ready message is a colleague's
-- Send quotation or Resend on WhatsApp, and `quote_wa_day` (Settings,
-- Messages: Website quotations) limited nothing.
--
-- WHAT CHANGED
--   * `quote_wa_allowed(p_id)` counts the day's (MYT) Quotation ready
--     messages to website quotations not failed, under one lock, against
--     `quote_wa_day`; 0 allows none.
--   * `quotation_release` (Send quotation) and `quotation_resend` (a website
--     quotation's Resend on WhatsApp) refuse `wa-limit` with the `cap` at the
--     limit, changing nothing. Publish and a team's quotation are not held.
--
-- ORDER: the pages, then this file (connector). A page served before reads
-- `wa-limit` as a generic refusal. Safe to run twice.
--
-- ROLLBACK: QUOTATION PUBLISHED WITHOUT WHATSAPP's quotation_release,
-- QUOTATION LINK ON WHATSAPP's quotation_resend and WEBSITE QUOTATION
-- WHATSAPP CAP's quote_wa_allowed.
-- ===========================================================================

-- WEBSITE QUOTATIONS ON WHATSAPP LIMITED AGAIN -------------------------------

create or replace function public.quote_wa_allowed(p_id uuid)
returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_cap numeric := coalesce(public.app_setting('quote_wa_day', v_today), 30);
  v_sent integer;
begin
  if v_cap <= 0 then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('quote-web-wa-day', 0));
  -- p_id is kept for the signature; every message counts, a resend included.
  select count(*) into v_sent from public.wa_outbox o
    join public.quotations q on q.id = o.ref_id and q.source = 'website'
   where o.purpose = 'quote_ready' and o.state <> 'failed'
     and o.created_at >= (v_today::timestamp at time zone 'Asia/Kuala_Lumpur');
  return v_sent < v_cap;
end $$;
revoke all on function public.quote_wa_allowed(uuid) from public, anon, authenticated;

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
  -- The day's WhatsApp messages for website quotations are held to
  -- `quote_wa_day` (counted under one lock); at the limit nothing changes and
  -- Publish still shows the rates.
  if coalesce(p_whatsapp, true) and not public.quote_wa_allowed(q.id) then
    return jsonb_build_object('error', 'wa-limit', 'cap', coalesce(public.app_setting('quote_wa_day', v_today), 30));
  end if;
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

create or replace function public.quotation_resend(p_id uuid, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  t  public.wa_templates;
  o  public.wa_outbox;
  k  public.client_contacts;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_hours numeric;
  v_wa text;
  v_name text;
  v_greet text;
  v_team boolean;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  v_team := q.source <> 'website';
  if not v_team and q.access_key is null then return jsonb_build_object('error', 'bad-quotation'); end if;
  if not v_team and q.released_at is null then return jsonb_build_object('error', 'not-sent'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if q.valid_until is not null and q.valid_until < v_today then return jsonb_build_object('error', 'expired'); end if;
  if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  if v_team and q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  select * into t from public.wa_templates x where x.purpose = 'quote_ready' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  if v_team then
    select * into k from public.client_contacts x
     where x.client_id = q.client_id and x.archived_at is null and x.is_primary
     order by x.created_at limit 1;
    v_wa := public.wa_number(case when btrim(coalesce(k.whatsapp, '')) <> '' and btrim(k.whatsapp) !~ '^@' then k.whatsapp else k.phone end);
    v_name := coalesce(nullif(btrim(coalesce(k.name, '')), ''), q.brand);
    v_greet := public.contact_greeting(k.salutation, v_name);
  else
    v_wa := public.quote_website_number(q.contact->>'whatsapp');
    v_name := coalesce(nullif(btrim(q.contact->>'name'), ''), q.brand);
    v_greet := public.contact_greeting(q.contact->>'salutation', v_name);
  end if;
  if v_wa is null or v_wa !~ '^(60|65)[0-9]{8,10}$' then return jsonb_build_object('error', 'no-number'); end if;
  v_hours := coalesce(public.app_setting('wa_repeat_hours', v_today), 24);
  if v_hours > 0 and not coalesce(p_again, false) then
    select * into o from public.wa_outbox x
     where x.purpose = 'quote_ready' and x.ref_id = q.id and x.state <> 'failed'
       and x.created_at > now() - make_interval(secs => v_hours * 3600)
     order by x.created_at desc limit 1;
    if o.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', o.created_at,
        'by', case when coalesce(o.created_by, 'system') = 'system' then null else o.created_by end));
    end if;
  end if;
  if not v_team and not public.quote_wa_allowed(q.id) then
    return jsonb_build_object('error', 'wa-limit', 'cap', coalesce(public.app_setting('quote_wa_day', v_today), 30));
  end if;
  -- A team's quotation takes its link the first time it is sent.
  if q.access_key is null then
    update public.quotations set access_key = public.new_link_key() where id = q.id returning * into q;
  end if;
  perform public.wa_enqueue('quote_ready', v_wa, v_name,
    jsonb_build_array(v_greet, coalesce(q.contact->>'brand', q.brand), q.ref),
    'quotation', q.id, q.client_id, q.access_key);
  update public.wa_outbox x set created_by = me.name
   where x.purpose = 'quote_ready' and x.ref_id = q.id and x.created_at = now() and x.created_by = 'system';
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || case when v_team then ' link sent on WhatsApp to ' || v_name else ' sent again to the prospect on WhatsApp' end);
  return jsonb_build_object('ok', true, 'key', q.access_key);
end $$;
revoke all on function public.quotation_resend(uuid, boolean) from public, anon;
grant execute on function public.quotation_resend(uuid, boolean) to authenticated;

-- END OF WEBSITE QUOTATIONS ON WHATSAPP LIMITED AGAIN ------------------------

select public.functions_tidy();
