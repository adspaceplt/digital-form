-- ===========================================================================
-- QUOTATION WEBSITE ASKS WHEN TO START — Urgency to commence (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "its missing one thing which is the urgency to
-- commence. It will not affect the rates ... mainly for internal planning"):
-- a lead made on the website reached the team with no idea of when the
-- prospect plans to start, which the console's intake asks of every lead.
--
-- WHAT IT CHANGES
--   `quote_website_create` reads `p_contact->>'commence'` (1_3 Within 3
--   months, 3_6 3 to 6 months, 6_plus More than 6 months; `bad-commence`
--   for anything else, nothing where a page served before leaves it out),
--   keeps it on the new lead's `clients.commence`, moves it on a lead asking
--   again (filed `client.edited` from and to) and names it in the team's
--   notice. `quote_commence_word` (internal) writes the words. No price
--   reads it.
--
-- ORDER: the pages, then this file. Safe to run twice.
--
-- ROLLBACK: run the REVIEW FIXES OF 2026-10-29 section's
-- quote_website_create again (2026-10-29-review-fixes.sql), then
-- `drop function if exists public.quote_commence_word(text);`.
-- ===========================================================================

-- QUOTATION WEBSITE ASKS WHEN TO START --------------------------------------

create or replace function public.quote_commence_word(p text)
returns text
language sql immutable set search_path = public as $$
  select case p when '1_3' then 'Within 3 months' when '3_6' then '3 to 6 months'
                when '6_plus' then 'More than 6 months' end
$$;
revoke all on function public.quote_commence_word(text) from public, anon, authenticated;

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
  v_idem  text := nullif(btrim(coalesce(p_idem, '')), '');
  v_sel   jsonb;
  v_q     public.quotations;
  v_c     public.clients;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_r     jsonb;
  v_new   boolean := false;
  v_wa_ok boolean := false;
begin
  if v_idem is null or length(v_idem) > 80 then return jsonb_build_object('error', 'bad-request'); end if;
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
  if v_ind is not null and v_ind not in ('Property', 'F&B', 'Retail', 'Wellness', 'Lifestyle',
                                         'Automotive', 'Tech', 'Education', 'Other') then
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
    values ('Website', 'client.added', v_c.name, 'Website · ' || coalesce(v_sal || ' ', '') || v_name);
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
  -- quotation is made (a refused one changes nothing).
  if not v_new and v_start is not null and v_c.commence is distinct from v_start then
    update public.clients set commence = v_start where id = v_c.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('Website', 'client.edited', v_c.name, 'Urgency to commence: ' ||
      coalesce(public.quote_commence_word(v_c.commence), 'not set') || ' → ' || public.quote_commence_word(v_start));
  end if;
  -- Whether the prospect is told on WhatsApp is known before the team is,
  -- so a quotation past the day's cap says so in the team's notice (review
  -- 2026-10-29, 17: the 31st of the day read as the 1st).
  begin
    v_wa_ok := public.quote_wa_allowed(v_q.id);
  exception when others then v_wa_ok := false;
  end;
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation made on the website · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('Monthly incl. SST RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') || ' · ' || v_name
      || coalesce(' · Starts ' || lower(public.quote_commence_word(v_start)), '')
      || case when v_wa_ok then '' else ' · Not sent on WhatsApp (daily limit)' end,
    v_q.id::text);
  -- The prospect is told on WhatsApp that the quotation is ready, its link
  -- button the quotation's key; a queueing fault never fails the quotation.
  -- No more a day than the Business setting allows (audit 2026-10-29, 3):
  -- past it the quotation is made and the team told, the message not sent.
  begin
    if v_wa_ok then
      perform public.wa_enqueue('quote_ready', v_wa, v_name,
        jsonb_build_array(public.contact_greeting(v_sal, v_name), v_brand, v_q.ref),
        'quotation', v_q.id, v_c.id, v_q.access_key);
    end if;
  exception when others then null;
  end;
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

-- END OF QUOTATION WEBSITE ASKS WHEN TO START -------------------------------

select public.functions_tidy();
