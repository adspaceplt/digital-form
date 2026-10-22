-- ===========================================================================
-- FEEDBACK ASKED OF CLIENTS ALONE — a feedback request on WhatsApp goes to a
-- client's contact, never a lead's.
-- 2026-10-22. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED (the menu review, MENU-1; the user, 2026-10-22: "Fix all")
--   The client record's ⋯ offered Request feedback on WhatsApp on a lead,
--   a contacted lead and a proposal, and wa_compose_prepare sent it.
--   * wa_compose_prepare refuses `feedback` to a contact whose client is at
--     Lead, Contacted or Proposal sent (`not-client`); every other purpose
--     and stage answers as before. The record's ⋯ no longer offers it there.
--
-- ROLLBACK
--   Run the wa_compose_prepare definition of the WHATSAPP LINK FROM THE
--   RECORD section of supabase/schema.sql again.
-- ===========================================================================

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
    /* A feedback request asks a client about work done for them: a lead,
       contacted or proposed, has none (MENU-1, 2026-10-22). */
    if p_purpose = 'feedback' and coalesce(c.stage, 'lead') in ('lead', 'contacted', 'proposal') then
      return jsonb_build_object('error', 'not-client');
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
    return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'greeting', public.contact_greeting(k.salutation, k.name),
      'client_id', c.id, 'client', case when r.id is not null then coalesce(nullif(r.brand_name, ''), c.name) else c.name end,
      'subject', c.name, 'ref_kind', case when b.id is not null then 'set' when o.id is not null then 'option'
                       when q.id is not null then 'quotation' when d.id is not null then 'offer' end,
      -- an approval reminder's link button: the page that waits, past the
      -- site's root (the client's review page, the campaign's selection page)
      'link', case when b.id is not null then 'review/?k=' || c.access_token
                   when o.id is not null then 'creators/?k=' || cp.access_token end);
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

-- END OF FEEDBACK ASKED OF CLIENTS ALONE -------------------------------------

select public.functions_tidy();
