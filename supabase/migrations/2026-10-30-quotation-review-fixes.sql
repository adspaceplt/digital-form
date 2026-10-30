-- ===========================================================================
-- QUOTATION REVIEW FIXES — the audit of 2026-10-30
-- ===========================================================================
-- WHY: the audit of the releases since 2026-10-29 found a website quotation
-- marked Not proceeding before the team sent it showing its price on the
-- prospect's link; Send quotation saying "sent on WhatsApp" with its template
-- off, and messaging a prospect marked Do not contact; the console's Chinese
-- cover note answered to anybody; and a Send racing a revision.
--
-- WHAT IT CHANGES
--   `quote_website_read` holds back the lines, totals and validity of a
--   website quotation not yet sent at every stage. `quotation_send` refuses
--   `no-contact`, and queues the WhatsApp (and says so) only while the
--   `quote_ready` template is on. `page_states` answers the console's 中文
--   note to the team alone, as its English one. `quotation_replace` holds
--   the quotation it revises while it does.
--
-- ORDER: this file, then the pages. Safe to run twice.
--
-- ROLLBACK: run the WEBSITE QUOTATION REVIEWED and PAGE AVAILABILITY
-- sections' definitions of these four again.
-- ===========================================================================

create or replace function public.quote_website_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w  public.quotations;
  q  public.quotations;
  c  public.clients;
  m  public.team_members;
  d  public.client_documents;
  f  public.client_detail_forms;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_stage text;
  v_portal boolean := false;
  v_billed boolean;
  v_own boolean;
  v_unsent boolean;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into w from public.quotations x
   where x.access_key = p_key and x.source = 'website' and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  -- A website quotation the team has not sent holds back its price at every
  -- stage, Not proceeding included (audit 2026-10-30).
  v_unsent := q.source = 'website' and q.released_at is null;
  select * into c from public.clients x where x.id = w.client_id;
  if nullif(btrim(coalesce(c.owner, '')), '') is not null then
    select * into m from public.team_members x
     where x.active and not coalesce(x.system, false) and x.removed_at is null and x.name = c.owner
     limit 1;
  end if;
  -- The letter that stands on the quotation's lines, the latest first.
  select dd.* into d from public.client_documents dd
   where dd.kind = 'offer' and dd.voided_at is null and dd.superseded_by is null
     and exists (select 1 from public.client_document_services ds
                   join public.client_services s on s.id = ds.service_id
                  where ds.document_id = dd.id and s.quotation_id = q.id)
   order by dd.created_at desc limit 1;
  -- The client's details form is offered only on the quotation that made
  -- the lead: a later website quotation that matched an existing lead's
  -- email and number never opens that lead's form (2026-10-26, audit).
  v_own := c.created_at >= w.issued_at - interval '1 minute'
           and not exists (select 1 from public.quotations o
                            where o.client_id = c.id and o.issued_at < w.issued_at and o.id <> w.id);
  v_billed := coalesce(btrim(c.legal_name), '') <> '' and coalesce(btrim(c.company_no), '') <> ''
              and coalesce(btrim(c.billing_address), '') <> '';

  if d.id is not null then
    if d.verified_at is not null and c.stage = 'active' then
      v_stage := 'welcome';
      select exists (select 1 from public.client_contacts k
                      where k.client_id = c.id and k.archived_at is null and k.portal_access
                        and lower(btrim(k.email)) = lower(btrim(coalesce(w.contact->>'email', '')))) into v_portal;
    elsif d.signed_at is not null then v_stage := 'signed';
    else v_stage := 'letter';
    end if;
  elsif w.status = 'not_proceeding' or q.status = 'not_proceeding' then
    v_stage := 'closed';
  elsif q.source = 'website' and q.released_at is null then
    -- Being reviewed: nothing priced leaves the database (2026-10-29).
    v_stage := 'review';
  elsif q.valid_until < v_today then
    v_stage := 'expired';
  elsif not v_billed and v_own then
    select * into f from public.client_detail_forms x
     where x.client_id = c.id and x.voided_at is null
     order by x.created_at desc limit 1;
    if f.id is not null and f.submitted_at is not null and f.used_at is null then v_stage := 'billing_sent';
    elsif f.id is not null and f.submitted_at is null and f.expires_at > now() then v_stage := 'billing';
    end if;
  elsif v_billed and w.proceed_at is not null then
    v_stage := 'billing_sent';
  end if;
  if v_stage is null then
    v_stage := case when w.proceed_at is not null then 'ready' else 'quote' end;
  end if;

  return jsonb_build_object(
    'ref', q.ref, 'first_ref', w.ref, 'revised', q.id <> w.id,
    'brand', coalesce(w.contact->>'brand', w.brand), 'version', case when q.source <> 'website' or q.released_at is not null then q.version end,
    'issued_at', q.issued_at,
    'valid_until', case when not v_unsent then q.valid_until end,
    'lines', case when not v_unsent then q.lines end,
    'totals', case when not v_unsent then q.totals end,
    'reply_due', case when v_stage = 'review' then q.reply_due end,
    'selection', w.selection, 'attention', w.contact->>'name',
    'stage', v_stage,
    'status', case when d.id is not null then 'offer' else q.status end,
    'details_key', case when v_stage = 'billing' then f.access_key end,
    'portal', v_portal,
    'proceed_at', w.proceed_at, 'proceed_due', w.proceed_due,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end,
    'market', case when c.market = 'SG' then 'SG' else 'MY' end,
    'today', v_today);
end $$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

create or replace function public.quotation_send(p_id uuid)
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
  -- A prospect marked Do not contact is not messaged (audit 2026-10-30).
  if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  -- Valid from the day it is sent, as the prospect first sees it.
  v_days := coalesce(public.app_setting('quote_valid_days', v_today), 30)::int;
  update public.quotations
     set released_at = now(), released_by = me.name, valid_until = v_today + v_days
   where id = q.id returning * into q;
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
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' sent to the prospect' || case when v_queued then ' on WhatsApp' else '' end ||
          ' · valid until ' || public.register_day(q.valid_until));
  return jsonb_build_object('ok', true, 'valid_until', q.valid_until, 'whatsapp', v_queued);
end $$;
revoke all on function public.quotation_send(uuid) from public, anon;
grant execute on function public.quotation_send(uuid) to authenticated;

create or replace function public.page_states()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(substr(f.key, 6), jsonb_build_object(
           'on', f.starts_at is null or f.starts_at <= now(),
           'set', true,
           'kind', coalesce(f.kind, 'upgrade'),
           'note', case when f.key <> 'page:admin' or public.is_team() then f.note end,
           'note_zh', case when f.key <> 'page:admin' or public.is_team() then f.note_zh end,
           'starts_at', f.starts_at,
           'ends_at', f.ends_at,
           'whatsapp', f.whatsapp)), '{}'::jsonb)
    from public.app_flags f
   where f.key like 'page:%' and f.on_now and (f.ends_at is null or f.ends_at > now())
$$;
revoke all on function public.page_states() from public;
grant execute on function public.page_states() to anon, authenticated;

create or replace function public.quotation_replace(p_new uuid, p_old uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  n public.quotations;
  o public.quotations;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into n from public.quotations where id = p_new for update;
  -- Held while it is revised, so a Send meanwhile waits and then reads it
  -- revised (audit 2026-10-30).
  select * into o from public.quotations where id = p_old for update;
  if n.id is null or o.id is null or n.client_id <> o.client_id or n.id = o.id
     or n.removed_at is not null or o.removed_at is not null
     or not public.client_scope_ok('client', n.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if n.source <> 'console' or n.replaces is not null then return jsonb_build_object('error', 'bad-quotation'); end if;
  update public.quotations set replaces = o.id where id = n.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', n.brand, n.ref || ' revises ' || o.ref);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_replace(uuid, uuid) from public, anon;
grant execute on function public.quotation_replace(uuid, uuid) to authenticated;

-- END OF QUOTATION REVIEW FIXES ----------------------------------------------

select public.functions_tidy();
