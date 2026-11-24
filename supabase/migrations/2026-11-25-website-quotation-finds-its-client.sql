-- ===========================================================================
-- WEBSITE QUOTATION FINDS ITS CLIENT (2026-11-25)
-- ===========================================================================
-- WHY: a client the team already serves (Active, Paused or Past) asking for
-- a quotation on the website was made a second record, a new lead, because
-- only Lead, Contacted and Proposal sent were matched (the user,
-- 2026-11-25). The request now reaches the client's own record.
--
-- WHAT IT CHANGES
--   * `quote_website_create`: where no lead matches as before, a client at
--     any other stage one of whose contacts holds both the email and the
--     number takes the quotation (Services, needing the team; source
--     website); no lead is made and the client's record is left as the team
--     keeps it (no Planned commencement written). Its person in charge
--     (`owner_id`, an active colleague) is told, kind `quote.website`,
--     else the managers who hold leads at Full Access, or an admin. Two
--     clients holding the same contact pick none: a lead is made as before.
--     Never matched on a company or brand name. The page's answer is
--     unchanged (ok, ref, key).
--   * `quote_website_read`: while such a quotation is unsent it names no
--     representative and no preparer, and reads the market from the number
--     typed, so the page learns nothing of the client; the details form
--     and the prefill stay withheld as for a matched lead (`v_own`).
--     Lead, Contacted and Proposal sent read as before.
--
-- ORDER: this file alone (no page or edge function changes). An open
-- /quote/ tab reads Request received as before at every step.
-- Safe to run twice. Holds no drop or delete.
-- ROLLBACK: run `quote_website_create` from TONE SWEEP 6 and
-- `quote_website_read` from TAKE LEAD AS SALES BY again; a quotation
-- already kept on a client stays there.
-- ===========================================================================

-- WEBSITE QUOTATION FINDS ITS CLIENT ----------------------------------------

create or replace function public.quote_website_create(p_sel jsonb, p_contact jsonb, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name  text := btrim(regexp_replace(coalesce(p_contact->>'name', ''), '\s+', ' ', 'g'));
  v_email text := lower(btrim(coalesce(p_contact->>'email', '')));
  v_wa    text := public.quote_website_number(p_contact->>'whatsapp');
  v_brand text := btrim(regexp_replace(coalesce(p_contact->>'brand', ''), '\s+', ' ', 'g'));
  v_ind   text := nullif(btrim(coalesce(p_contact->>'industry', '')), '');
  v_lang  text := case when p_contact->>'lang' = 'zh' then 'zh' else 'en' end;
  v_sal   text := nullif(btrim(coalesce(p_contact->>'salutation', '')), '');
  v_start text := nullif(btrim(coalesce(p_contact->>'commence', '')), '');
  v_on_t  text := nullif(btrim(coalesce(p_contact->>'commence_on', '')), '');
  v_on    date;
  v_idem  text := nullif(btrim(coalesce(p_idem, '')), '');
  v_sel   jsonb;
  v_q     public.quotations;
  v_c     public.clients;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_r     jsonb;
  v_new   boolean := false;
  v_known boolean := false;
  v_hits  int;
  v_pic   uuid;
begin
  if v_idem is null or length(v_idem) > 80 then return jsonb_build_object('error', 'bad-request'); end if;
  -- The quotation website covered (Page availability) makes nothing.
  if public.page_covered('quote') then return jsonb_build_object('error', 'unavailable'); end if;
  select * into v_q from public.quotations q
   where q.idem = v_idem and q.source = 'website' and lower(q.contact->>'email') = v_email;
  if v_q.id is not null then
    return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key, 'again', true);
  end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 160 then return jsonb_build_object('error', 'bad-email'); end if;
  if v_wa !~ '^(60(1[0-9]{8,9}|7[0-9]{7,8})|65[0-9]{8})$' then return jsonb_build_object('error', 'bad-whatsapp'); end if;
  if length(v_brand) < 2 or length(v_brand) > 120 then return jsonb_build_object('error', 'bad-brand'); end if;
  -- A name or brand is never a web address: both go into the WhatsApp the
  -- prospect is sent from ADspace's number (2026-10-26, audit).
  if v_name ~* public.quote_link_like() then return jsonb_build_object('error', 'bad-name'); end if;
  if v_brand ~* public.quote_link_like() then return jsonb_build_object('error', 'bad-brand'); end if;
  -- An industry on the list kept in Settings (INDUSTRIES, 2026-11-04).
  if v_ind is not null and not exists (select 1 from public.industries i where i.name = v_ind) then
    return jsonb_build_object('error', 'bad-industry');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-salutation');
  end if;
  -- When they plan to start: the console's Urgency to commence, for the
  -- team's planning; it changes no price. Left out by a page served before.
  if v_start is not null and v_start not in ('1_3', '3_6', '6_plus') then
    return jsonb_build_object('error', 'bad-commence');
  end if;
  -- A preferred start date, optional (PREFERRED START DATE, 2026-11-21):
  -- a day from today in Malaysia to the date ceiling, kept on the quotation
  -- it was asked on (START DATE ON THE QUOTATION, 2026-11-21).
  if v_on_t is not null then
    if v_on_t !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error', 'bad-start-date'); end if;
    begin
      v_on := v_on_t::date;
    exception when others then
      return jsonb_build_object('error', 'bad-start-date');
    end;
    if v_on < (now() at time zone 'Asia/Kuala_Lumpur')::date or v_on > date '2099-12-31' then
      return jsonb_build_object('error', 'bad-start-date');
    end if;
  end if;
  if coalesce((p_contact->>'consent')::boolean, false) is not true then return jsonb_build_object('error', 'consent'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if jsonb_typeof(p_sel->'once') = 'array' and jsonb_array_length(p_sel->'once') > 20
     or jsonb_typeof(p_sel->'extra') = 'object' and (select count(*) from jsonb_object_keys(p_sel->'extra')) > 10 then
    return jsonb_build_object('error', 'bad-selection');
  end if;

  -- What the price reads, and nothing else.
  v_sel := jsonb_strip_nulls(jsonb_build_object(
    'mix', case when jsonb_typeof(p_sel->'mix') = 'string' and length(p_sel->>'mix') <= 20 then p_sel->'mix' end,
    'plan', case when jsonb_typeof(p_sel->'plan') = 'string' and length(p_sel->>'plan') <= 80 then p_sel->'plan' end,
    'term', case when jsonb_typeof(p_sel->'term') in ('number', 'string') and length(p_sel->>'term') <= 4 then p_sel->'term' end,
    'budget', case when jsonb_typeof(p_sel->'budget') in ('number', 'string') and length(p_sel->>'budget') <= 12 then p_sel->'budget' end,
    'translate', case when jsonb_typeof(p_sel->'translate') = 'boolean' then p_sel->'translate' end,
    'platforms', (select jsonb_agg(distinct v) from jsonb_array_elements_text(
                    case when jsonb_typeof(p_sel->'platforms') = 'array' then p_sel->'platforms' else '[]'::jsonb end) v
                   where v in ('meta', 'tiktok', 'rednote', 'linkedin')),
    'langs', (select jsonb_agg(distinct l) from jsonb_array_elements_text(
                case when jsonb_typeof(p_sel->'langs') = 'array' then p_sel->'langs' else '[]'::jsonb end) l
               where l in ('en', 'zh', 'ms')),
    'extra', case when jsonb_typeof(p_sel->'extra') = 'object' then
               (select jsonb_object_agg(left(k, 80), p_sel->'extra'->k) from jsonb_object_keys(p_sel->'extra') k) end,
    'once', case when jsonb_typeof(p_sel->'once') = 'array' then
              (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('slug', left(o->>'slug', 80), 'qty', o->'qty')))
                 from jsonb_array_elements(p_sel->'once') o where jsonb_typeof(o) = 'object') end));

  -- Two posts at once are counted one after the other.
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || least(v_email, v_wa), 0));
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || greatest(v_email, v_wa), 0));
  if (select count(*) from public.quotations q
       where q.source = 'website' and q.issued_at > now() - interval '1 day'
         and (lower(q.contact->>'email') = v_email or q.contact->>'whatsapp' = '+' || v_wa)) >= 5 then
    return jsonb_build_object('error', 'limit');
  end if;

  -- A lead this person already is (the same contact holds both the email
  -- and the number), else a new one.
  select c.* into v_c from public.clients c
    join public.client_contacts k on k.client_id = c.id
   where c.stage in ('lead', 'contacted', 'proposal')
     and k.archived_at is null
     and lower(k.email) = v_email
     and public.quote_website_number(k.whatsapp) = v_wa
   order by c.created_at desc limit 1;
  -- Else a client the team already serves, at any other stage (Active,
  -- Paused, Past; WEBSITE QUOTATION FINDS ITS CLIENT, 2026-11-25): one of its
  -- contacts holds both the email and the number. Never the company or
  -- brand name alone, and never a guess: two clients holding the same
  -- contact make a lead as before.
  if v_c.id is null then
    select count(distinct c.id) into v_hits from public.clients c
      join public.client_contacts k on k.client_id = c.id
     where c.stage not in ('lead', 'contacted', 'proposal')
       and k.archived_at is null
       and lower(k.email) = v_email
       and public.quote_website_number(k.whatsapp) = v_wa;
    if v_hits = 1 then
      select c.* into v_c from public.clients c
        join public.client_contacts k on k.client_id = c.id
       where c.stage not in ('lead', 'contacted', 'proposal')
         and k.archived_at is null
         and lower(k.email) = v_email
         and public.quote_website_number(k.whatsapp) = v_wa
       limit 1;
      v_known := true;
    end if;
  end if;
  if v_c.id is null then
    v_base := btrim(regexp_replace(lower(v_brand), '[^a-z0-9]+', '-', 'g'), '-');
    if v_base = '' then v_base := 'client'; end if;
    v_slug := v_base;
    while exists (select 1 from public.clients c where lower(c.slug) = v_slug) loop
      v_n := v_n + 1; v_slug := v_base || '-' || v_n;
    end loop;
    insert into public.clients (name, access_token, stage, industry, source, market, slug, deal_note, commence)
    values (v_brand, public.new_link_key(), 'lead', v_ind, 'website',
            case when v_wa like '65%' then 'SG' else 'MY' end, v_slug,
            'Quotation requested on the website.', v_start)
    returning * into v_c;
    insert into public.client_contacts (client_id, salutation, name, email, whatsapp, lang, is_primary)
    values (v_c.id, v_sal, v_name, v_email, '+' || v_wa, v_lang, true);
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.added', v_c.name, 'Website · ' || coalesce(v_sal || ' ', '') || v_name);
    v_new := true;
  end if;

  v_r := public.quotation_make(v_c.id, v_sel, v_idem, 'website', null,
    jsonb_strip_nulls(jsonb_build_object('salutation', v_sal, 'name', v_name, 'email', v_email,
      'whatsapp', '+' || v_wa, 'lang', v_lang, 'brand', v_brand)));
  if v_r ? 'error' then
    if v_new then raise exception using message = 'quote:' || (v_r->>'error'); end if;
    return v_r;
  end if;
  select * into v_q from public.quotations where id = (v_r->>'id')::uuid;
  -- A lead asking again says when it plans to start now, once its
  -- quotation is made (a refused one changes nothing). A client already
  -- served keeps its record as the team keeps it.
  if not v_new and not v_known and v_start is not null and v_c.commence is distinct from v_start then
    update public.clients set commence = v_start where id = v_c.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.edited', v_c.name, 'Planned commencement: ' ||
      coalesce(public.quote_commence_word(v_c.commence), 'not set') || ' → ' || public.quote_commence_word(v_start));
  end if;
  -- The price waits for the team (the user, 2026-10-29: "the price
  -- shouldnt send out straight"): the quotation is owed a reply by working
  -- days, the team is told to review it, and the prospect is sent nothing
  -- until a colleague sends it (`quotation_send`).
  update public.quotations set reply_due = public.quote_reply_by(now()), commence_on = v_on where id = v_q.id
   returning * into v_q;
  if v_known then
    -- A client already served: its person in charge is told, else the
    -- managers who hold leads at Full Access (as `quote_proceed_remind`).
    select m.id into v_pic from public.team_members m
     where m.id = v_c.owner_id and m.active and not coalesce(m.system, false) and m.removed_at is null;
    insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
    select m.id, 'quote.website', 'Quotation to review · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', 'one-off') || ' · ' || v_name
      || coalesce(' · Preferred start date ' || public.register_day(v_on),
                  ' · Starts ' || lower(public.quote_commence_word(v_start)), '')
      || ' · Send by ' || public.register_day((v_q.reply_due at time zone 'Asia/Kuala_Lumpur')::date)
      || ' (' || trim(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMDay')) || '), ' ||
      lower(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
           v_c.id, 'quote.website:' || v_q.id || ':' || m.id
      from public.team_members m
     where m.active and not coalesce(m.system, false)
       and (m.id = v_pic
            or (v_pic is null and (m.is_admin or m.role = 'admin'
                or public.level_rank(coalesce(m.access ->> 'clients.leads', m.access ->> 'clients')) >= 3)))
    on conflict (dedupe_key) do nothing;
  else
    perform public.quote_tell(v_c.id, 'quote.website', 'Quotation to review · ' || v_c.name,
      v_q.ref || ' · ' || coalesce('RM ' ||
        to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', 'one-off') || ' · ' || v_name
        || coalesce(' · Preferred start date ' || public.register_day(v_on),
                    ' · Starts ' || lower(public.quote_commence_word(v_start)), '')
        || ' · Send by ' || public.register_day((v_q.reply_due at time zone 'Asia/Kuala_Lumpur')::date)
        || ' (' || trim(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMDay')) || '), ' ||
        lower(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
      v_q.id::text);
  end if;
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

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
  v_held boolean;
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
  -- A website quotation that found a client the team already serves
  -- (WEBSITE QUOTATION FINDS ITS CLIENT, 2026-11-25) says nothing of that
  -- client while the team has not sent it: no representative, no
  -- preparer, the market read from the number typed.
  v_held := v_unsent and not v_own and coalesce(c.stage, '') not in ('lead', 'contacted', 'proposal');
  if v_held then m := null; pm := null; end if;
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
    'market', case when v_held then case when w.contact->>'whatsapp' like '+65%' then 'SG' else 'MY' end
                   when c.market = 'SG' then 'SG' else 'MY' end,
    'today', v_today,
    'signed', case when q.signed_at is not null then jsonb_build_object('at', q.signed_at, 'via', q.signed->>'via',
                'signer', q.signed->'signer', 'signature', q.signed->'signature', 'company', q.signed->'company',
                'contact', q.signed->'contact', 'record', case when q.signed->>'via' = 'online' then q.signed->'record' end) end,
    'prepared', case when pm.id is not null then jsonb_build_object('name', pm.name, 'title', nullif(btrim(coalesce(pm.designation, '')), ''))
                     when not v_held and nullif(btrim(coalesce(q.made_by, '')), '') is not null then jsonb_build_object('name', q.made_by, 'title', null) end,
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

-- END OF WEBSITE QUOTATION FINDS ITS CLIENT ---------------------------------

select public.functions_tidy();
