-- ===========================================================================
-- GREETING BY WHOLE NAME — every WhatsApp greeting says the person's whole
-- name, never its first word (2026-11-11)
-- ===========================================================================
-- WHY (the user, 2026-11-11: "the name kept being cut short. Kai Sin but
-- Kai only"): a contact with no salutation, a creator and a colleague were
-- greeted by the first word of their name, which cuts a Chinese name.
--
-- WHAT CHANGED
--   * `contact_greeting(salutation, name)`: the whole name where no
--     salutation is set (a salutation still said once, a title kept whole).
--   * `wa_recipients`, `wa_compose_prepare` (a creator), `campaign_options_wa`
--     (a booking confirmed) and `ops_notifications_wa` (a colleague's
--     reminder) greet through it.
--
-- ORDER: this file (connector), then the pages. Safe to run twice.
--
-- ROLLBACK: each function from its section before this one in schema.sql
-- (SALUTATION SAID ONCE's contact_greeting; REPRESENTATIVE ON WHATSAPP's
-- wa_compose_prepare; WHATSAPP SECTION's wa_recipients; WHATSAPP CREATOR
-- LINK's campaign_options_wa; WHATSAPP's ops_notifications_wa).
-- ===========================================================================

-- GREETING BY WHOLE NAME -----------------------------------------------------

create or replace function public.contact_greeting(p_salutation text, p_name text)
returns text
language sql immutable set search_path = public as $$
  -- A salutation is said once, however the name was keyed (one set replaces
  -- the one the name opens on); with none, the whole name (Kai Sin, never Kai).
  select case when x.s <> '' then public.contact_named(x.s, x.n) else x.n end
    from (select btrim(coalesce(p_salutation, '')) as s,
                 btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')) as n) x
$$;
revoke all on function public.contact_greeting(text, text) from public, anon, authenticated;

create or replace function public.wa_recipients()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('whatsapp', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'contacts', case when not public.allowed('clients.contacts', 'view') then '[]'::jsonb else
      coalesce((select jsonb_agg(x order by x.client, x.is_primary desc, x.name) from (
        select k.id, k.name, k.role, coalesce(k.is_primary, false) as is_primary, c.id as client_id, c.name as client,
               c.stage, public.contact_greeting(k.salutation, k.name) as greeting,
               public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market) as number,
               coalesce(k.whatsapp ~ '^@', false) as username
          from public.client_contacts k
          join public.clients c on c.id = k.client_id
         where k.archived_at is null and public.client_seen(c.id, 'view')) x), '[]'::jsonb) end,
    'creators', case when not public.allowed('campaigns.creators', 'view') then '[]'::jsonb else
      coalesce((select jsonb_agg(x order by x.name) from (
        select k.id, k.name, public.contact_greeting(null, k.name) as greeting,
               public.wa_number(k.whatsapp, 'MY') as number, false as username, k.access_code as code
          from public.creators k
         where k.active) x), '[]'::jsonb) end);
end $$;
revoke all on function public.wa_recipients() from public, anon;
grant execute on function public.wa_recipients() to authenticated;

create or replace function public.ops_notifications_wa()
returns trigger
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  if new.kind not in ('tasks.empty', 'outstation', 'perf.remind', 'perf.reflect', 'health.remind') then return new; end if;
  select * into m from public.team_members x where x.id = new.team_member_id and x.active;
  if m.id is null then return new; end if;
  perform public.wa_queue('reminder', public.wa_number(m.mobile, 'MY'), m.name,
    jsonb_build_array(public.contact_greeting(null, m.name), coalesce(new.title, ''), coalesce(new.body, '')),
    'notice', new.id);
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.ops_notifications_wa() from public, anon, authenticated;
create or replace trigger ops_notifications_wa after insert on public.ops_notifications
  for each row execute function public.ops_notifications_wa();

create or replace function public.campaign_options_wa()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  k       public.creators;
  v_title text;
  v_cl    uuid;
begin
  if new.state is not distinct from old.state then return new; end if;
  if not (new.state = 'confirmed' and old.state in ('option', 'shortlisted', 'backup')) then return new; end if;
  select * into k from public.creators x where x.id = new.creator_id;
  if k.id is null then return new; end if;
  select coalesce(nullif(btrim(c.title), ''), 'Your campaign'), c.client_id into v_title, v_cl
    from public.campaigns c where c.id = new.campaign_id;
  perform public.wa_enqueue('creator', public.wa_number(k.whatsapp, 'MY'), k.name,
    jsonb_build_array(public.contact_greeting(null, k.name), v_title), 'option', new.id, v_cl, k.access_code);
  return new;
exception when others then
  return new;
end $$;

revoke all on function public.campaign_options_wa() from public, anon, authenticated;

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
  return jsonb_build_object('ok', true, 'number', v_n, 'name', cr.name, 'greeting', public.contact_greeting(null, cr.name),
    'client_id', cp.client_id,
    'campaign', case when cp.id is not null then coalesce(nullif(btrim(cp.title), ''), 'Your campaign') end,
    'code', cr.access_code, 'subject', coalesce(nullif(btrim(cp.title), ''), cr.name));
end $$;
revoke all on function public.wa_compose_prepare(text, uuid, text, uuid) from public, anon;
grant execute on function public.wa_compose_prepare(text, uuid, text, uuid) to authenticated;

-- END OF GREETING BY WHOLE NAME ----------------------------------------------

select public.functions_tidy();
