-- ===========================================================================
-- QUOTATION LINK ON WHATSAPP — a team's quotation sent to sign by the
-- approved quote_ready message (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31: "Go with A"): a new template asking the client
-- to sign was refused twice by Meta as Marketing. The approved `quote_ready`
-- message (your quotation is ready, a View quotation button on the
-- quotation's link) already reaches the link, which since QUOTATION SIGNING
-- shows Accept this quotation, so a team's quotation is sent by it too.
--
-- WHAT IT CHANGES
--   `quotation_resend(p_id, p_again)` takes a team's quotation as well: its
--   link made where it holds none, sent to the client's primary contact
--   (WhatsApp, else phone, as `wa_number` reads it), greeted with their
--   salutation, refused `signed` once the client has signed. A website
--   quotation is answered exactly as before. Filed "{ref} link sent on
--   WhatsApp" for a team's quotation.
--
-- ORDER: this file (connector), then the pages. Safe to run twice.
--
-- ROLLBACK: run QUOTATION RESENT ON WHATSAPP's `quotation_resend` again.
-- ===========================================================================

-- QUOTATION LINK ON WHATSAPP ------------------------------------------------

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

-- END OF QUOTATION LINK ON WHATSAPP -----------------------------------------

select public.functions_tidy();
