-- ===========================================================================
-- REPRESENTATIVE ON WHATSAPP — a lead is told on WhatsApp which colleague
-- of the business development team took their enquiry (2026-11-11)
-- ===========================================================================
-- WHY (the user, 2026-11-11: a template telling a prospect that the
-- business development team reached out personally, with one variable for
-- the Sales by colleague, sent by hand from the lead and from Messages).
--
-- WHAT CHANGED
--   * `wa_templates.purpose` takes `representative` (the SQL Editor part,
--     REPRESENTATIVE ON WHATSAPP, THE SQL EDITOR PART, its row seeded off).
--   * `wa_may_send('representative', 'contact')`: Messages at Work and
--     Clients: Leads at View.
--   * `wa_compose_prepare` takes `representative` to a contact of a client
--     at Lead, Contacted or Proposal sent (`not-lead`) whose Sales by is an
--     active colleague (`no-sales-by`) with a namecard on and its short link
--     (`no-card`); it answers `rep` (the colleague's name) and `code` (the
--     namecard's short link, which `wa-send` puts in the link button).
--   * `wa_send_begin`, `wa_sent_recently`: filed and held as Sent recently
--     by its client, as a feedback request is.
--   * `wa_send_done`, `wa_template_set`: the purpose's words
--     (Representative introduction; Representative to lead, and
--     Quotation ready, which read Creator updates).
--
-- ORDER: the SQL Editor part, the pages, then this file (connector). Until
-- this file runs a press is refused `bad-request`, said as Not sent.
-- Safe to run twice.
--
-- ROLLBACK: each function from its section before this one in schema.sql
-- (FEEDBACK ASKED OF CLIENTS ALONE's wa_compose_prepare; WHATSAPP SEND
-- FILED FIRST's wa_send_begin and wa_send_done; the latest wa_may_send,
-- wa_sent_recently and wa_template_set); the SQL Editor part's rollback.
-- ===========================================================================

-- REPRESENTATIVE ON WHATSAPP -------------------------------------------------

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
                          and public.allowed('clients.quotes', 'view')
    when 'offer'    then p_to_kind = 'contact' and public.allowed('whatsapp.documents', 'work')
                         and public.allowed('clients.documents', 'view')
    when 'representative' then p_to_kind = 'contact' and public.allowed('clients.leads', 'view')
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
  t    public.team_members;
  v_n  text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose not in ('message', 'report', 'feedback', 'creator', 'approval', 'quotation', 'offer', 'representative')
     or p_to_kind not in ('contact', 'creator')
     or (p_purpose in ('report', 'feedback', 'approval', 'quotation', 'offer', 'representative') and p_to_kind <> 'contact')
     or (p_purpose = 'creator' and p_to_kind <> 'creator') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if not public.wa_may_send(p_purpose, p_to_kind) then return jsonb_build_object('error', 'denied'); end if;
  if p_to_kind = 'contact' then
    select * into k from public.client_contacts x where x.id = p_to and x.archived_at is null;
    if k.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = k.client_id;
    if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    /* A feedback request asks a client about work done for them: a lead,
       contacted or proposed, has none (MENU-1, 2026-10-22). */
    if p_purpose = 'feedback' and coalesce(c.stage, 'lead') in ('lead', 'contacted', 'proposal') then
      return jsonb_build_object('error', 'not-client');
    end if;
    /* A representative is named to a lead alone, and is its Sales by
       colleague: active, their namecard on, its short link the button's. */
    if p_purpose = 'representative' then
      if coalesce(c.stage, 'lead') not in ('lead', 'contacted', 'proposal') then
        return jsonb_build_object('error', 'not-lead');
      end if;
      select * into t from public.team_members x where x.id = c.sales_by and x.active and x.removed_at is null;
      if t.id is null then return jsonb_build_object('error', 'no-sales-by'); end if;
      if not coalesce(t.card_on, false) or nullif(btrim(coalesce(t.card_slug, '')), '') is null then
        return jsonb_build_object('error', 'no-card', 'rep', t.name);
      end if;
    end if;
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
      if q.status = 'not_proceeding' then return jsonb_build_object('error', 'void'); end if;
    end if;
    if p_purpose = 'offer' then
      select * into d from public.client_documents x where x.id = p_ref;
      if d.id is null or d.client_id <> c.id or d.kind not in ('offer', 'intent', 'cover') then
        return jsonb_build_object('error', 'not-found');
      end if;
      if (d.voided_at is not null or d.superseded_by is not null) then return jsonb_build_object('error', 'void'); end if;
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
    return jsonb_strip_nulls(jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'greeting', public.contact_greeting(k.salutation, k.name),
      'client_id', c.id, 'client', case when r.id is not null then coalesce(nullif(r.brand_name, ''), c.name) else c.name end,
      'subject', c.name, 'ref_kind', case when b.id is not null then 'set' when o.id is not null then 'option'
                       when q.id is not null then 'quotation' when d.id is not null then 'offer' end,
      -- an approval reminder's link button: the page that waits, past the
      -- site's root (the client's review page, the campaign's selection page)
      'link', case when b.id is not null then 'review/?k=' || c.access_token
                   when o.id is not null then 'creators/?k=' || cp.access_token end,
      -- the representative: their name, and their namecard's short link for
      -- the link button
      'rep', t.name, 'code', t.card_slug));
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

create or replace function public.wa_send_begin(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid, p_template text,
  p_lang text, p_category text, p_params jsonb, p_again boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  p      jsonb;
  v_rc   jsonb;
  v_ref  uuid;
  v_tpl  text := coalesce(nullif(btrim(p_template), ''), '');
  v_id   uuid;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  p := public.wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref);
  if p ? 'error' then return p; end if;
  if v_tpl = '' then return jsonb_build_object('error', 'bad-request'); end if;
  -- the same message as wa_sent_recently reads it: a feedback request or a
  -- representative by its client, a plain message by its template,
  -- anything else its record
  v_ref := case when p_purpose in ('feedback', 'representative') then (p ->> 'client_id')::uuid
                when p_purpose = 'message' then null else p_ref end;
  -- one send at a time of one message to one person: a second press waits
  -- here until the first is filed, then reads it
  perform pg_advisory_xact_lock(hashtextextended('wa_send:' || p_to_kind || ':' || p_to::text || ':' || p_purpose || ':' ||
    coalesce(v_ref::text, '') || ':' || case when p_purpose = 'message' then v_tpl else '' end, 0));
  if exists (select 1 from public.wa_outbox x
              where x.to_kind = p_to_kind and x.to_id = p_to and x.purpose = p_purpose and x.state = 'sending'
                and x.ref_id is not distinct from v_ref and (p_purpose <> 'message' or x.template = v_tpl)
                and x.claimed_at > now() - interval '5 minutes') then
    return jsonb_build_object('error', 'sending');
  end if;
  if not coalesce(p_again, false) then
    v_rc := public.wa_sent_recently(p_to_kind, p_to, p_purpose, p_ref, v_tpl);
    if coalesce((v_rc ->> 'recent')::boolean, false) then return jsonb_build_object('error', 'recent', 'recent', v_rc); end if;
  end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, state,
                                created_by, claimed_at, tries, to_kind, to_id, category)
  values (p_purpose, p ->> 'number', p ->> 'name', v_tpl, coalesce(nullif(btrim(p_lang), ''), 'en'),
          case when jsonb_typeof(p_params) = 'array' then p_params else '[]'::jsonb end,
          case p_purpose when 'report' then 'report' when 'creator' then 'option' when 'feedback' then 'client'
                         when 'representative' then 'client'
                         when 'approval' then p ->> 'ref_kind' when 'quotation' then 'quotation' when 'offer' then 'offer' end,
          case when p_purpose in ('report', 'creator', 'approval', 'quotation', 'offer') then p_ref
               when p_purpose in ('feedback', 'representative') then (p ->> 'client_id')::uuid end,
          (p ->> 'client_id')::uuid, 'sending', me.name, now(), 1, p_to_kind, p_to,
          nullif(lower(btrim(coalesce(p_category, ''))), ''))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.wa_send_begin(text, uuid, text, uuid, text, text, text, jsonb, boolean) from public, anon;
grant execute on function public.wa_send_begin(text, uuid, text, uuid, text, text, text, jsonb, boolean) to authenticated;

create or replace function public.wa_sent_recently(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid, p_template text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_prep  jsonb;
  v_hours numeric := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  v_ref   uuid;
  v_tpl   text := coalesce(nullif(btrim(p_template), ''), '');
  w       public.wa_outbox;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  v_prep := public.wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref);
  if v_prep ? 'error' then return v_prep; end if;
  if v_hours <= 0 then return jsonb_build_object('ok', true, 'recent', false, 'hours', 0); end if;
  v_ref := case when p_purpose in ('feedback', 'representative') then (v_prep ->> 'client_id')::uuid
                when p_purpose = 'message' then null else p_ref end;
  select * into w from public.wa_outbox x
   where x.to_kind = p_to_kind and x.to_id = p_to
     and x.state in ('queued', 'sending', 'sent', 'unknown')
     and x.created_at > now() - make_interval(hours => v_hours::int)
     and ((x.purpose = p_purpose
           and x.ref_id is not distinct from v_ref
           and (p_purpose <> 'message' or x.template = v_tpl))
       -- a feedback request, a representative or a plain message: the same
       -- template to the same person, whatever purpose it was filed under
       or (p_purpose in ('feedback', 'representative', 'message') and v_tpl <> '' and x.template = v_tpl))
   order by x.created_at desc limit 1;
  if w.id is null then return jsonb_build_object('ok', true, 'recent', false, 'hours', v_hours); end if;
  return jsonb_build_object('ok', true, 'recent', true, 'hours', v_hours, 'at', w.created_at,
    'by', case when w.created_by = 'system' then null else w.created_by end, 'to', w.to_name, 'state', w.state);
end $$;
revoke all on function public.wa_sent_recently(text, uuid, text, uuid, text) from public, anon;
grant execute on function public.wa_sent_recently(text, uuid, text, uuid, text) to authenticated;

create or replace function public.wa_send_done(p_id uuid, p_ok boolean, p_wa_id text, p_error text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  w      public.wa_outbox;
  p      jsonb;
  v_word text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into w from public.wa_outbox x
   where x.id = p_id and x.state = 'sending' and x.created_by = me.name and x.to_kind is not null for update;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.wa_outbox x
     set state = case when coalesce(p_ok, false) then 'sent'
                      when coalesce(p_error, '') like 'unknown:%' then 'unknown' else 'failed' end,
         wa_id = left(p_wa_id, 200), error = left(p_error, 500),
         sent_at = case when coalesce(p_ok, false) then now() end
   where x.id = w.id;
  if coalesce(p_ok, false) then
    p := public.wa_compose_prepare(w.to_kind, w.to_id, w.purpose,
           case when w.purpose in ('feedback', 'representative', 'message') then null else w.ref_id end);
    v_word := case w.purpose when 'report' then 'Report' when 'feedback' then 'Feedback request'
                             when 'creator' then 'Booking' when 'approval' then 'Approval reminder'
                             when 'quotation' then 'Quotation' when 'offer' then 'Letter of Offer'
                             when 'representative' then 'Representative introduction' else 'Message' end;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'wa.sent', coalesce(p ->> 'subject', w.to_name),
            case when w.purpose = 'creator' then w.to_name || ' · Booking sent on WhatsApp'
                 else v_word || ' sent on WhatsApp to ' || coalesce(nullif(btrim(w.to_name), ''), 'the contact') end);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_send_done(uuid, boolean, text, text) from public, anon;
grant execute on function public.wa_send_done(uuid, boolean, text, text) to authenticated;

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
                           when 'quote_ready' then 'Quotation ready' when 'representative' then 'Representative to lead'
                           else 'Creator updates' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'wa.template', 'WhatsApp',
          v_word || ': ' || coalesce(nullif(t.name, ''), 'not set') || ' (' || t.lang || ', ' || case when t.active then 'on' else 'off' end
          || ') → ' || coalesce(nullif(v_name, ''), 'not set') || ' (' || v_lang || ', ' || case when coalesce(p_active, false) then 'on' else 'off' end || ')');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_template_set(text, text, text, integer, text, boolean) from public, anon;
grant execute on function public.wa_template_set(text, text, text, integer, text, boolean) to authenticated;

-- END OF REPRESENTATIVE ON WHATSAPP ------------------------------------------

select public.functions_tidy();
