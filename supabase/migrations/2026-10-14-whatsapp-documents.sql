-- ===========================================================================
-- WHATSAPP DOCUMENTS — a quotation or a Letter of Offer sent to a client
-- contact on WhatsApp, by hand, its PDF as the template's header document.
-- 2026-10-14. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Run after 2026-10-14-whatsapp-document-purposes.sql.
--
-- WHAT CHANGED (the user, 2026-10-14: "could be both but internal decides
-- which to send via whatsapp")
--   1. `wa_may_send('quotation' | 'offer', 'contact')`: WhatsApp and its
--      Quotations and letters part (`whatsapp.documents`) at Work, and
--      Clients: Services (a quotation) or Clients: Documents (a letter) at
--      View.
--   2. `wa_compose_prepare` and `wa_sent` take them to a client contact,
--      `p_ref` a quotation of the contact's client not removed, or a Letter
--      of Offer of that client not voided (`void`); else `not-found`. Each is
--      filed against its record (`quotation`, `offer`) and in the activity
--      record as "Quotation sent on WhatsApp to …" / "Letter of Offer sent on
--      WhatsApp to …".
--   3. `wa_template_set` names the purposes Quotation to client and Letter of
--      Offer to client.
--
-- ROLLBACK
--   Pages first, then restate wa_may_send, wa_compose_prepare, wa_sent and
--   wa_template_set from WHATSAPP APPROVAL REMINDER.
-- ===========================================================================

create or replace function public.wa_may_send(p_purpose text, p_to_kind text)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.allowed('whatsapp', 'work') and case p_purpose
    when 'report'   then public.allowed('whatsapp.report', 'work') and public.allowed('reports', 'view')
    when 'feedback' then public.allowed('whatsapp.feedback', 'work') and public.allowed('clients', 'view')
    when 'creator'  then public.allowed('whatsapp.booking', 'work') and public.allowed('campaigns', 'view')
    when 'approval' then p_to_kind = 'contact' and public.allowed('whatsapp.approval', 'work')
                         and (public.allowed('review.sets', 'view') or public.allowed('campaigns.campaigns', 'view'))
    when 'quotation' then p_to_kind = 'contact' and public.allowed('whatsapp.documents', 'work')
                          and public.allowed('clients.services', 'view')
    when 'offer'    then p_to_kind = 'contact' and public.allowed('whatsapp.documents', 'work')
                         and public.allowed('clients.documents', 'view')
    when 'message'  then case p_to_kind when 'contact' then public.allowed('clients.contacts', 'view')
                                        when 'creator' then public.allowed('campaigns.creators', 'view')
                                        else false end
    else false end
$$;
revoke all on function public.wa_may_send(text, text) from public, anon, authenticated;

create or replace function public.wa_compose_prepare(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  k    public.client_contacts;
  cr   public.creators;
  c    public.clients;
  r    public.sm_reports;
  o    public.campaign_options;
  cp   public.campaigns;
  b    public.batches;
  q    public.quotations;
  d    public.client_documents;
  v_n  text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose not in ('message', 'report', 'feedback', 'creator', 'approval', 'quotation', 'offer')
     or p_to_kind not in ('contact', 'creator')
     or (p_purpose in ('report', 'feedback', 'approval', 'quotation', 'offer') and p_to_kind <> 'contact')
     or (p_purpose = 'creator' and p_to_kind <> 'creator') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if not public.wa_may_send(p_purpose, p_to_kind) then return jsonb_build_object('error', 'denied'); end if;
  if p_to_kind = 'contact' then
    select * into k from public.client_contacts x where x.id = p_to and x.archived_at is null;
    if k.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = k.client_id;
    if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    if p_purpose = 'report' then
      select * into r from public.sm_reports x where x.id = p_ref;
      if r.id is null or r.client_id <> c.id then return jsonb_build_object('error', 'not-found'); end if;
      if r.status <> 'published' then return jsonb_build_object('error', 'not-published'); end if;
    end if;
    /* A quotation or a Letter of Offer is the contact's own client's: a
       quotation not removed, a letter not voided. */
    if p_purpose = 'quotation' then
      select * into q from public.quotations x where x.id = p_ref;
      if q.id is null or q.client_id <> c.id or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
    end if;
    if p_purpose = 'offer' then
      select * into d from public.client_documents x where x.id = p_ref;
      if d.id is null or d.client_id <> c.id or d.kind not in ('offer', 'intent', 'cover') then
        return jsonb_build_object('error', 'not-found');
      end if;
      if d.voided_at is not null then return jsonb_build_object('error', 'void'); end if;
    end if;
    /* An approval reminder names what waits on the client: a published
       content set of theirs, or a creator's draft at Reviewing on a
       campaign of theirs, each read at its own section. */
    if p_purpose = 'approval' then
      select * into b from public.batches x where x.id = p_ref;
      if b.id is not null then
        if b.client_id <> c.id or not public.allowed('review.sets', 'view') then return jsonb_build_object('error', 'not-found'); end if;
        if not coalesce(b.published, false) then return jsonb_build_object('error', 'not-waiting'); end if;
      else
        select * into o from public.campaign_options x where x.id = p_ref;
        if o.id is not null then select * into cp from public.campaigns x where x.id = o.campaign_id; end if;
        if o.id is null or cp.id is null or cp.client_id is distinct from c.id or not public.allowed('campaigns.campaigns', 'view') then
          return jsonb_build_object('error', 'not-found');
        end if;
        if o.state <> 'reviewing' then return jsonb_build_object('error', 'not-waiting'); end if;
      end if;
    end if;
    v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
    if v_n is null then
      return jsonb_build_object('error', case when k.whatsapp ~ '^@' then 'username' else 'no-number' end);
    end if;
    return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'greeting', public.contact_greeting(k.salutation, k.name),
      'client_id', c.id, 'client', case when r.id is not null then coalesce(nullif(r.brand_name, ''), c.name) else c.name end,
      'subject', c.name, 'ref_kind', case when b.id is not null then 'set' when o.id is not null then 'option'
                       when q.id is not null then 'quotation' when d.id is not null then 'offer' end);
  end if;
  select * into cr from public.creators x where x.id = p_to;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_purpose = 'creator' then
    select * into o from public.campaign_options x where x.id = p_ref;
    if o.id is null or o.creator_id <> cr.id then return jsonb_build_object('error', 'not-found'); end if;
    select * into cp from public.campaigns x where x.id = o.campaign_id;
    if cp.id is null or (cp.client_id is not null and not public.client_seen(cp.client_id, 'view')) then
      return jsonb_build_object('error', 'not-found');
    end if;
    if o.state in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced') then
      return jsonb_build_object('error', 'not-booked');
    end if;
  elsif not cr.active then
    return jsonb_build_object('error', 'not-found');
  end if;
  v_n := public.wa_number(cr.whatsapp, 'MY');
  if v_n is null then return jsonb_build_object('error', 'no-creator-number'); end if;
  return jsonb_build_object('ok', true, 'number', v_n, 'name', cr.name, 'greeting', split_part(btrim(cr.name), ' ', 1),
    'client_id', cp.client_id,
    'campaign', case when cp.id is not null then coalesce(nullif(btrim(cp.title), ''), 'Your campaign') end,
    'code', cr.access_code, 'subject', coalesce(nullif(btrim(cp.title), ''), cr.name));
end $$;
revoke all on function public.wa_compose_prepare(text, uuid, text, uuid) from public, anon;
grant execute on function public.wa_compose_prepare(text, uuid, text, uuid) to authenticated;

create or replace function public.wa_sent(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid, p_template text,
                                          p_lang text, p_category text, p_params jsonb, p_ok boolean,
                                          p_wa_id text, p_error text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  p    jsonb := public.wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref);
  v_word text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p ? 'error' then return p; end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, state,
                                wa_id, error, created_by, sent_at, tries, to_kind, to_id, category)
  values (p_purpose, p ->> 'number', p ->> 'name', coalesce(nullif(btrim(p_template), ''), ''), coalesce(nullif(btrim(p_lang), ''), 'en'),
          case when jsonb_typeof(p_params) = 'array' then p_params else '[]'::jsonb end,
          case p_purpose when 'report' then 'report' when 'creator' then 'option' when 'feedback' then 'client'
                         when 'approval' then p ->> 'ref_kind' when 'quotation' then 'quotation' when 'offer' then 'offer' end,
          case when p_purpose in ('report', 'creator', 'approval', 'quotation', 'offer') then p_ref when p_purpose = 'feedback' then (p ->> 'client_id')::uuid end,
          (p ->> 'client_id')::uuid,
          case when p_ok then 'sent' else 'failed' end, left(p_wa_id, 200), left(p_error, 500), me.name,
          case when p_ok then now() end, 1, p_to_kind, p_to,
          nullif(lower(btrim(coalesce(p_category, ''))), ''));
  if p_ok then
    v_word := case p_purpose when 'report' then 'Report' when 'feedback' then 'Feedback request'
                             when 'creator' then 'Booking' when 'approval' then 'Approval reminder'
                             when 'quotation' then 'Quotation' when 'offer' then 'Letter of Offer' else 'Message' end;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'wa.sent', p ->> 'subject',
            case when p_purpose = 'creator' then (p ->> 'name') || ' · Booking sent on WhatsApp'
                 else v_word || ' sent on WhatsApp to ' || coalesce(nullif(btrim(p ->> 'name'), ''), 'the contact') end);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_sent(text, uuid, text, uuid, text, text, text, jsonb, boolean, text, text) from public, anon;
grant execute on function public.wa_sent(text, uuid, text, uuid, text, text, text, jsonb, boolean, text, text) to authenticated;

create or replace function public.wa_template_set(p_purpose text, p_name text, p_lang text, p_params integer,
                                                  p_category text, p_active boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  t      public.wa_templates;
  v_name text := btrim(coalesce(p_name, ''));
  v_lang text := btrim(coalesce(p_lang, ''));
  v_cat  text := lower(btrim(coalesce(p_category, '')));
  v_word text;
begin
  if me.id is null or not public.allowed('whatsapp', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.wa_templates x where x.purpose = p_purpose;
  if t.purpose is null then return jsonb_build_object('error', 'not-found'); end if;
  if (v_name !~ '^[a-z0-9_]+$' or length(v_name) > 512) and not (v_name = '' and not coalesce(p_active, false)) then
    return jsonb_build_object('error', 'bad-name');
  end if;
  if v_lang !~ '^[a-z]{2,3}(_[A-Z]{2})?$' then return jsonb_build_object('error', 'bad-lang'); end if;
  if p_params is null or p_params not between 0 and 5 then return jsonb_build_object('error', 'bad-params'); end if;
  if v_cat not in ('', 'utility', 'marketing', 'authentication') then return jsonb_build_object('error', 'bad-category'); end if;
  if t.name = v_name and t.lang = v_lang and t.params = p_params and t.category = v_cat and t.active = coalesce(p_active, false) then
    return jsonb_build_object('ok', true, 'same', true);
  end if;
  update public.wa_templates x
     set name = v_name, lang = v_lang, params = p_params, category = v_cat, active = coalesce(p_active, false),
         set_by = me.name, set_at = now()
   where x.purpose = p_purpose;
  v_word := case p_purpose when 'report' then 'Report to client' when 'feedback' then 'Feedback request'
                           when 'reminder' then 'Team reminders' when 'approval' then 'Approval reminder'
                           when 'quotation' then 'Quotation to client' when 'offer' then 'Letter of Offer to client'
                           else 'Creator updates' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'wa.template', 'WhatsApp',
          v_word || ': ' || coalesce(nullif(t.name, ''), 'not set') || ' (' || t.lang || ', ' || case when t.active then 'on' else 'off' end
          || ') → ' || coalesce(nullif(v_name, ''), 'not set') || ' (' || v_lang || ', ' || case when coalesce(p_active, false) then 'on' else 'off' end || ')');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_template_set(text, text, text, integer, text, boolean) from public, anon;
grant execute on function public.wa_template_set(text, text, text, integer, text, boolean) to authenticated;

-- END OF WHATSAPP DOCUMENTS ---------------------------------------------------

select public.functions_tidy();
