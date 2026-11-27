-- ===========================================================================
-- QUOTE INTAKE (2026-11-27)
-- ===========================================================================
-- WHY: the user, 27 Nov 2026 (HANDOVER Queue 12, on the intake mockup):
-- /quote/'s Your details asks what the team needs to quote a business on
-- day one, and the request finds the record it belongs to on the server,
-- never on the page: Registering as (Company, or Sole / Partnership), the
-- Business Registration No. (BRN), 12 digits, required for both (a
-- company's entity code 01, 02 or 04, a sole proprietorship's or
-- partnership's 03), the registered name, the industry (required), a
-- website or No website and a social media account (one of the two),
-- Planned commencement as before, and Comments (the lead's Enquiry).
--
-- WHAT CHANGED
--   * `quote_brand_key(t)`: a brand name read for matching (case, spaces
--     and marks set aside).
--   * `quote_website_create` (restated): every intake field checked by
--     `quote_intake_check` (`bad-kind`, `bad-brn`, `brn-kind` with the
--     kind the number belongs to, `bad-legal`, `need-industry`,
--     `bad-industry`, `need-site`, `bad-site`, `need-handle`,
--     `bad-platform`, `bad-handle`, `bad-commence`, `bad-start-date`) and
--     Comments (`bad-comments` past 1,000). Matching: the BRN first, then
--     a contact holding both the email and the number (as before). The
--     same brand is that record; another brand makes a new lead whose
--     quotation keeps `match` (the client, its entity, how it matched),
--     told in the team's notice as Matches existing client {name}. The
--     registration typed for a record kept, or a number an entity holds,
--     is held for Use details (`quote_reg_hold`), never written over
--     Billing; a new lead's Billing takes it. A new lead takes the
--     website, the social media account and the Comments as its Enquiry.
--     The page's answer and the thank-you are the same whatever matched.
--
-- ORDER: after 2026-11-27-quote-details-asked.sql and after the pages
-- (the page sends the new fields; the old create ignores them meanwhile).
-- An old /quote/ tab still open after this file is refused at Submit
-- (its page names no BRN) and reads its general refusal; a refresh loads
-- the new page. Safe to run twice. Holds no drop or delete.
-- ROLLBACK: run `quote_website_create` from QUOTATION PREFLIGHT again.
-- ===========================================================================

create or replace function public.quote_brand_key(p text)
returns text
language sql immutable set search_path = public as $$
  select regexp_replace(lower(btrim(coalesce(p, ''))), '[[:space:][:punct:]]+', '', 'g')
$$;
revoke all on function public.quote_brand_key(text) from public, anon, authenticated;

create or replace function public.quote_website_create(p_sel jsonb, p_contact jsonb, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name  text := btrim(regexp_replace(coalesce(p_contact->>'name', ''), '\s+', ' ', 'g'));
  v_email text := lower(btrim(coalesce(p_contact->>'email', '')));
  v_wa    text := public.quote_website_number(p_contact->>'whatsapp');
  v_brand text := btrim(regexp_replace(coalesce(p_contact->>'brand', ''), '\s+', ' ', 'g'));
  v_ind   text;
  v_lang  text := case when p_contact->>'lang' = 'zh' then 'zh' else 'en' end;
  v_sal   text := nullif(btrim(coalesce(p_contact->>'salutation', '')), '');
  v_start text;
  v_on    date;
  v_reg   jsonb;
  v_cm    text := nullif(btrim(replace(coalesce(p_contact->>'comments', ''), E'\r', '')), '');
  v_key   text;
  v_match jsonb;
  v_hold  boolean := false;
  v_col   text;
  v_lead  public.clients;
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
  v_chk   jsonb;
begin
  if v_idem is null or length(v_idem) > 80 then return jsonb_build_object('error', 'bad-request'); end if;
  -- The quotation portal covered (Page availability) makes nothing.
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
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-salutation');
  end if;
  -- The intake (QUOTE INTAKE, 2026-11-27): Registering as, the Business
  -- Registration No. and registered name, the industry, a website or a
  -- social media account and Planned commencement, each required, checked
  -- as details sent later are (`quote_intake_check`).
  v_reg := public.quote_intake_check(p_contact, array['registration', 'industry', 'online', 'commence']);
  if v_reg ? 'error' then return v_reg; end if;
  v_ind := v_reg->>'industry';
  v_start := v_reg->>'commence';
  v_on := (v_reg->>'commence_on')::date;
  if v_cm is not null and length(v_cm) > 1000 then return jsonb_build_object('error', 'bad-comments'); end if;
  if coalesce((p_contact->>'consent')::boolean, false) is not true then return jsonb_build_object('error', 'consent'); end if;
  -- What changed since the page read the card, as the preflight asks it
  -- (QUOTATION PREFLIGHT, 2026-11-25): nothing is written while any stands.
  v_chk := public.quote_web_check(p_sel, case when jsonb_typeof(p_sel) = 'object' then p_sel->>'seen' end);
  if v_chk->'changes' @> '[{"kind": "off"}]'::jsonb then return jsonb_build_object('error', 'no-card'); end if;
  if jsonb_array_length(v_chk->'changes') > 0 then
    return jsonb_build_object('error', 'changed', 'changes', v_chk->'changes');
  end if;
  -- What the price reads, and nothing else (QUOTE WEBSITE CHOICES, 2026-11-24).
  v_sel := public.quote_website_sel(p_sel, coalesce(public.quote_card()->'snapshot', '{}'::jsonb));
  if v_sel ? 'error' then return v_sel; end if;

  -- Two posts at once are counted one after the other.
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || least(v_email, v_wa), 0));
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || greatest(v_email, v_wa), 0));
  if (select count(*) from public.quotations q
       where q.source = 'website' and q.issued_at > now() - interval '1 day'
         and (lower(q.contact->>'email') = v_email or q.contact->>'whatsapp' = '+' || v_wa)) >= 5 then
    return jsonb_build_object('error', 'limit');
  end if;

  -- Who this is (QUOTE INTAKE, 2026-11-27; never said on the page): the
  -- Business Registration No. first, then a contact holding both the email
  -- and the number. The same brand is that record (a lead while Lead,
  -- Contacted or Proposal sent, else the client served); another brand is
  -- a new lead the team sees as Matches existing client. The registration
  -- typed for a record kept is held for Use details, never written over
  -- Billing. Never the company or brand name alone, and never a guess.
  v_key := public.quote_brand_key(v_brand);
  select c.* into v_c from public.clients c
    join public.client_entities ce on ce.client_id = c.id
    join public.billing_entities e on e.id = ce.entity_id
   where regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = v_reg->>'brn'
     and public.quote_brand_key(c.name) = v_key
   order by (c.stage in ('lead', 'contacted', 'proposal')) desc, c.created_at desc limit 1;
  if v_c.id is null then
    select jsonb_build_object('client', c.id, 'name', c.name, 'entity', e.id, 'by', 'brn') into v_match
      from public.clients c
      join public.client_entities ce on ce.client_id = c.id
      join public.billing_entities e on e.id = ce.entity_id
     where regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = v_reg->>'brn'
     order by (c.stage = 'active') desc, ce.is_main desc, c.created_at desc limit 1;
  end if;
  -- A number some entity holds is never written to a new lead's Billing.
  v_hold := v_c.id is not null or v_match is not null
    or exists (select 1 from public.billing_entities e where regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = v_reg->>'brn');
  if v_c.id is null and v_match is null then
    -- A lead this person already is (the same contact holds both).
    select c.* into v_lead from public.clients c
      join public.client_contacts k on k.client_id = c.id
     where c.stage in ('lead', 'contacted', 'proposal')
       and k.archived_at is null
       and lower(k.email) = v_email
       and public.quote_website_number(k.whatsapp) = v_wa
     order by c.created_at desc limit 1;
    if v_lead.id is not null then
      if public.quote_brand_key(v_lead.name) = v_key then v_c := v_lead;
      else v_match := jsonb_build_object('client', v_lead.id, 'name', v_lead.name, 'by', 'contact');
      end if;
    end if;
  end if;
  -- Else a client the team already serves, at any other stage (Active,
  -- Paused, Past; WEBSITE QUOTATION FINDS ITS CLIENT, 2026-11-25): one of
  -- its contacts holds both; two such clients pick neither.
  if v_c.id is null and v_match is null then
    select count(distinct c.id) into v_hits from public.clients c
      join public.client_contacts k on k.client_id = c.id
     where c.stage not in ('lead', 'contacted', 'proposal')
       and k.archived_at is null
       and lower(k.email) = v_email
       and public.quote_website_number(k.whatsapp) = v_wa;
    if v_hits = 1 then
      select c.* into v_lead from public.clients c
        join public.client_contacts k on k.client_id = c.id
       where c.stage not in ('lead', 'contacted', 'proposal')
         and k.archived_at is null
         and lower(k.email) = v_email
         and public.quote_website_number(k.whatsapp) = v_wa
       limit 1;
      if public.quote_brand_key(v_lead.name) = v_key then v_c := v_lead;
      else v_match := jsonb_build_object('client', v_lead.id, 'name', v_lead.name, 'by', 'contact');
      end if;
    end if;
  end if;
  v_known := v_c.id is not null and v_c.stage not in ('lead', 'contacted', 'proposal');
  if v_c.id is null then
    v_base := btrim(regexp_replace(lower(v_brand), '[^a-z0-9]+', '-', 'g'), '-');
    if v_base = '' then v_base := 'client'; end if;
    v_slug := v_base;
    while exists (select 1 from public.clients c where lower(c.slug) = v_slug) loop
      v_n := v_n + 1; v_slug := v_base || '-' || v_n;
    end loop;
    v_col := case v_reg->>'platform' when 'instagram' then 'ig' when 'facebook' then 'fb'
               when 'tiktok' then 'tiktok' when 'xhs' then 'xhs' end;
    insert into public.clients (name, access_token, stage, industry, source, market, slug, deal_note, commence,
                                website, handle_ig, handle_fb, handle_tiktok, handle_xhs)
    values (v_brand, public.new_link_key(), 'lead', v_ind, 'website',
            case when v_wa like '65%' then 'SG' else 'MY' end, v_slug,
            coalesce(v_cm, 'Quotation requested on the website.'), v_start, v_reg->>'website',
            case when v_col = 'ig' then v_reg->>'handle' end, case when v_col = 'fb' then v_reg->>'handle' end,
            case when v_col = 'tiktok' then v_reg->>'handle' end, case when v_col = 'xhs' then v_reg->>'handle' end)
    returning * into v_c;
    -- A new lead's Billing takes the registration typed, unless some
    -- entity already holds the number (then held for Use details below).
    if not v_hold then
      update public.clients x set legal_name = v_reg->>'legal', company_no = v_reg->>'brn' where x.id = v_c.id;
    end if;
    insert into public.client_contacts (client_id, salutation, name, email, whatsapp, lang, is_primary)
    values (v_c.id, v_sal, v_name, v_email, '+' || v_wa, v_lang, true);
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation portal', 'client.added', v_c.name, 'Website · ' || coalesce(v_sal || ' ', '') || v_name);
    v_new := true;
  end if;

  v_r := public.quotation_make(v_c.id, v_sel, v_idem, 'website', null,
    jsonb_strip_nulls(jsonb_build_object('salutation', v_sal, 'name', v_name, 'email', v_email,
      'whatsapp', '+' || v_wa, 'lang', v_lang, 'brand', v_brand) || v_reg ||
      jsonb_strip_nulls(jsonb_build_object('comments', v_cm))));
  if v_r ? 'error' then
    if v_new then raise exception using message = 'quote:' || (v_r->>'error'); end if;
    return v_r;
  end if;
  select * into v_q from public.quotations where id = (v_r->>'id')::uuid;
  -- The version checked is the version priced: a card published between
  -- the two undoes the whole request.
  if v_q.version is distinct from v_chk->>'version' then raise exception using message = 'quote:changed'; end if;
  -- A lead asking again says when it plans to start now, once its
  -- quotation is made (a refused one changes nothing). A client already
  -- served keeps its record as the team keeps it.
  if not v_new and not v_known and v_start is not null and v_c.commence is distinct from v_start then
    update public.clients set commence = v_start where id = v_c.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation portal', 'client.edited', v_c.name, 'Planned commencement: ' ||
      coalesce(public.quote_commence_word(v_c.commence), 'not set') || ' → ' || public.quote_commence_word(v_start));
  end if;
  -- The price waits for the team (the user, 2026-10-29: "the price
  -- shouldnt send out straight"): the quotation is owed a reply by working
  -- days, the team is told to review it, and the prospect is sent nothing
  -- until a colleague sends it (`quotation_send`).
  update public.quotations set reply_due = public.quote_reply_by(now()), commence_on = v_on, match = v_match where id = v_q.id
   returning * into v_q;
  if v_hold then perform public.quote_reg_hold(v_c.id, v_q.id, v_reg); end if;
  if v_known then
    -- A client already served: its person in charge is told, else the
    -- managers who hold leads at Full Access (as `quote_proceed_remind`).
    select m.id into v_pic from public.team_members m
     where m.id = v_c.owner_id and m.active and not coalesce(m.system, false) and m.removed_at is null;
    insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
    select m.id, 'quote.website', 'Quotation to review · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', 'one-time') || ' · ' || v_name
      || coalesce(' · Preferred start date ' || public.register_day(v_on),
                  ' · Starts ' || lower(public.quote_commence_word(v_start)), '')
      || coalesce(' · Matches existing client ' || (v_match->>'name'), '')
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
        to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', 'one-time') || ' · ' || v_name
        || coalesce(' · Preferred start date ' || public.register_day(v_on),
                    ' · Starts ' || lower(public.quote_commence_word(v_start)), '')
        || coalesce(' · Matches existing client ' || (v_match->>'name'), '')
        || ' · Send by ' || public.register_day((v_q.reply_due at time zone 'Asia/Kuala_Lumpur')::date)
        || ' (' || trim(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMDay')) || '), ' ||
        lower(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
      v_q.id::text);
  end if;
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm = 'quote:changed' then
    return jsonb_build_object('error', 'changed', 'changes', jsonb_build_array(jsonb_build_object('kind', 'version')));
  end if;
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;


-- END OF QUOTE INTAKE ---------------------------------------------------------

select public.functions_tidy();
