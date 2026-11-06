-- ===========================================================================
-- TAKE LEAD AS SALES BY (2026-11-06)
-- ===========================================================================
-- WHY (the user, 2026-11-06): "Take lead = i & mine account take sales for
-- this leads. Its equivalent to sales by." Person in charge is the key
-- account colleague, set later; the salesperson is Sales by.
--
-- WHAT IT CHANGES
--   `clients_sales_by_guard` lets a colleague at Clients: Leads Work set
--   Sales by to themselves on a lead nobody sells and nobody is in charge
--   of (Take lead); any other change of Sales by stays Clients Full Access.
--   `quote_website_read` names the Sales by colleague as the prospect's
--   representative while no Person in charge is set.
--
-- ORDER: this file, then the pages (a page served before still takes a lead
-- as Person in charge, which stays allowed). Safe to run twice.
--
-- ROLLBACK: restate both from 2026-10-23-sales-by.sql and the last
-- QUOTATION WEBSITE band before this one.
-- ===========================================================================

-- TAKE LEAD AS SALES BY -----------------------------------------------------

create or replace function public.clients_sales_by_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_me public.team_members;
begin
  if pg_trigger_depth() > 1 or auth.jwt() is null then return new; end if;
  if tg_op = 'UPDATE' and new.sales_by is not distinct from old.sales_by then return new; end if;
  v_me := public.ops_me();
  if v_me.id is null or public.allowed('clients', 'manage') then return new; end if;
  if tg_op = 'INSERT' and (new.sales_by is null or new.sales_by = v_me.id) then return new; end if;
  -- Take lead (2026-11-06): a lead nobody sells is taken by a colleague who
  -- works leads, as their own and nobody else's.
  if tg_op = 'UPDATE' and old.sales_by is null and new.sales_by = v_me.id
     and old.stage in ('lead', 'contacted', 'proposal')
     and nullif(btrim(coalesce(old.owner, '')), '') is null
     and public.allowed('clients.leads', 'work') then return new; end if;
  raise exception 'Sales by is set at Clients Full Access.' using errcode = '42501', hint = 'sales-by';
end $$;
revoke all on function public.clients_sales_by_guard() from public, anon, authenticated;

create or replace function public.quote_website_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w  public.quotations;
  q  public.quotations;
  c  public.clients;
  m  public.team_members;
  pm public.team_members;
  pc public.client_contacts;
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
  -- Any quotation with a link: a website quotation, or a team's once
  -- `quotation_link` made one (QUOTATION SIGNING).
  select * into w from public.quotations x
   where x.access_key = p_key and x.removed_at is null;
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
  -- No person in charge yet: the salesperson who took the lead (Sales by,
  -- 2026-11-06) is the prospect's representative.
  if m.id is null and c.sales_by is not null then
    select * into m from public.team_members x
     where x.id = c.sales_by and x.active and not coalesce(x.system, false) and x.removed_at is null;
  end if;
  -- Prepared by: the colleague who made the revision shown; a website
  -- quotation's, the person in charge.
  select * into pm from public.team_members x where x.id = public.quote_sign_member(q.made_by);
  if pm.id is null and q.source = 'website' then pm := m; end if;
  -- The letter that stands on the quotation's lines, the latest first.
  select dd.* into d from public.client_documents dd
   where dd.kind = 'offer' and dd.voided_at is null and dd.superseded_by is null
     and exists (select 1 from public.client_document_services ds
                   join public.client_services s on s.id = ds.service_id
                  where ds.document_id = dd.id and s.quotation_id = q.id)
   order by dd.created_at desc limit 1;
  -- The client's details form is offered only on the website quotation
  -- that made the lead: a later website quotation that matched an existing
  -- lead's email and number never opens that lead's form (2026-10-26, audit).
  v_own := w.source = 'website' and c.created_at >= w.issued_at - interval '1 minute'
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
  elsif q.signed_at is not null then
    -- Signed on the link or on paper: accepted, then welcome once reviewed
    -- and Active (QUOTATION SIGNING).
    if q.reviewed_at is not null and c.stage = 'active' then
      v_stage := 'welcome';
      select exists (select 1 from public.client_contacts k
                      where k.client_id = c.id and k.archived_at is null and k.portal_access
                        and lower(btrim(k.email)) = lower(btrim(coalesce(q.signed->'contact'->>'email', w.contact->>'email', '')))) into v_portal;
    else v_stage := 'accepted';
    end if;
  elsif q.valid_until < v_today then
    v_stage := 'expired';
  elsif not v_billed and v_own then
    select * into f from public.client_detail_forms x
     where x.client_id = c.id and x.voided_at is null
     order by x.created_at desc limit 1;
    if f.id is not null and f.submitted_at is not null and f.used_at is null then v_stage := 'billing_sent';
    elsif f.id is not null and f.submitted_at is null and f.expires_at > now() then v_stage := 'billing';
    end if;
  elsif v_billed and w.proceed_at is not null and w.source = 'website' then
    v_stage := 'billing_sent';
  end if;
  if v_stage is null then
    v_stage := case when w.proceed_at is not null then 'ready' else 'quote' end;
  end if;
  -- The record's details prefill only its own link: a website quotation
  -- that matched an existing lead never reads that lead's billing or
  -- primary contact, and a closed or expired link prefills nothing
  -- (audit 2026-11-04).
  if q.signed_at is null and (w.source <> 'website' or v_own) then
    select * into pc from public.client_contacts x
     where x.client_id = c.id and x.archived_at is null and x.is_primary
     order by x.created_at limit 1;
  end if;

  return jsonb_build_object(
    'ref', q.ref, 'first_ref', w.ref, 'revised', q.id <> w.id,
    'brand', coalesce(w.contact->>'brand', w.brand), 'version', case when q.source <> 'website' or q.released_at is not null then q.version end,
    'issued_at', q.issued_at,
    'valid_until', case when not v_unsent then q.valid_until end,
    'lines', case when not v_unsent then q.lines end,
    'totals', case when not v_unsent then q.totals end,
    'reply_due', case when v_stage = 'review' then q.reply_due end,
    'selection', w.selection, 'attention', coalesce(w.contact->>'name', pc.name),
    'stage', v_stage,
    'status', case when d.id is not null then 'offer' else q.status end,
    'details_key', case when v_stage = 'billing' then f.access_key end,
    'portal', v_portal,
    'proceed_at', w.proceed_at, 'proceed_due', w.proceed_due,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end,
    'market', case when c.market = 'SG' then 'SG' else 'MY' end,
    'today', v_today,
    'signed', case when q.signed_at is not null then jsonb_build_object('at', q.signed_at, 'via', q.signed->>'via',
                'signer', q.signed->'signer', 'signature', q.signed->'signature', 'company', q.signed->'company',
                'contact', q.signed->'contact', 'record', case when q.signed->>'via' = 'online' then q.signed->'record' end) end,
    'prepared', case when pm.id is not null then jsonb_build_object('name', pm.name, 'title', nullif(btrim(coalesce(pm.designation, '')), ''))
                     when nullif(btrim(coalesce(q.made_by, '')), '') is not null then jsonb_build_object('name', q.made_by, 'title', null) end,
    'reviewed', case when q.reviewed_at is not null then jsonb_build_object('name', q.reviewed_by, 'title', q.reviewed_role, 'at', q.reviewed_at) end,
    'prefill', case when q.signed_at is null and not v_unsent and v_stage not in ('closed', 'expired') then jsonb_build_object(
      'company', case when w.source <> 'website' or v_own then
                   jsonb_build_object('legal_name', coalesce(c.legal_name, ''), 'company_no', coalesce(c.company_no, ''),
                                      'billing_address', coalesce(c.billing_address, ''), 'sst_no', coalesce(c.sst_no, ''), 'tin', coalesce(c.tin, ''))
                 else jsonb_build_object('legal_name', '', 'company_no', '', 'billing_address', '', 'sst_no', '', 'tin', '') end,
      'contact', case when pc.id is not null then jsonb_build_object('salutation', coalesce(pc.salutation, ''), 'name', coalesce(pc.name, ''),
                                                                    'phone', coalesce(nullif(btrim(pc.phone), ''), case when btrim(coalesce(pc.whatsapp, '')) !~ '^@' then btrim(pc.whatsapp) end, ''),
                                                                     'email', coalesce(pc.email, ''))
                      else jsonb_build_object('salutation', coalesce(w.contact->>'salutation', ''), 'name', coalesce(w.contact->>'name', ''),
                                              'phone', coalesce(w.contact->>'whatsapp', ''), 'email', coalesce(w.contact->>'email', '')) end) end);
end $$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

-- END OF TAKE LEAD AS SALES BY ----------------------------------------------

select public.functions_tidy();
