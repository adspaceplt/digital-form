-- ===========================================================================
-- QUOTE WEBSITE GUARDS — the quotation website keeps a visitor to their own
-- lead, reads a number as the team types it, and stores only what it prices
-- (2026-10-15)
-- ===========================================================================
-- WHY (the audit of 2026-10-15, S1, S2, I1, I2)
--   * S2: a lead was reused when the email OR the number matched, so anybody
--     who knew one of them filed a quotation (and, through Proceed, billing
--     details) under a real lead, and read that lead's name back.
--   * I2: `8123 4567` (Singapore without 65) and `12-345 6789` (a Malaysian
--     mobile without its 0) were refused, though `wa_number` reads both; a
--     lead keyed by the team as `012…` never matched the incoming `6012…`.
--   * S1: the selection was stored as sent (any key, arrays of any length),
--     and two posts at once could each pass the five-a-day count.
--   * I1: Proceed asked a 12-digit registration number of everyone, so a
--     Singapore prospect (a UEN) could never press it.
--
-- WHAT CHANGED
--   * `quote_website_number(p_raw)` (internal): the digits in international
--     form, as `wa_number` reads them: a leading 0 is Malaysia, eight digits
--     Singapore, nine or ten starting 1 a Malaysian mobile without its 0.
--   * `quote_website_create`:
--     - reuses a lead only where one of its live contacts holds both the
--       email and the number (the stored number read the same way); any
--       other visitor gets a lead of their own, for the team to merge;
--     - keeps the brand the visitor typed in the quotation's contact
--       (`contact.brand`), which is what the visitor reads back;
--     - stores only the keys `quote_price` reads, each bounded (platforms
--       and languages from their lists, at most 20 one-off items and 10
--       extra formats, no `edits`);
--     - takes a transaction lock on the email and on the number before the
--       five-a-day count, so parallel posts are counted one after another.
--   * `quote_website_read` answers `brand` from the quotation's contact
--     (else the quotation's own) and `market` (MY or SG, from the client).
--   * `quote_website_request` accepts a Singapore UEN (nine or ten
--     characters, its letters in capitals) where the client's market is SG,
--     and 12 digits otherwise.
--
-- ORDER
--   This file, then the pages (`js/quote.js` reads `market` and sends the
--   UEN), then `quote-request` (it refuses while `TURNSTILE_SECRET` is
--   unset). A page from before sends the 12 digits it always did and reads
--   the brand it typed.
--
-- Safe to run twice. Rollback: run QUOTE WEBSITE SALUTATION's
-- quote_website_create and QUOTATION WEBSITE's quote_website_read and
-- quote_website_request again; drop function quote_website_number(text).
-- ===========================================================================

create or replace function public.quote_website_number(p_raw text)
returns text
language sql immutable set search_path = public as $$
  select case
           when d ~ '^0[1-9]' then '6' || d
           when d ~ '^[3689][0-9]{7}$' then '65' || d
           when d ~ '^1[0-9]{8,9}$' then '60' || d
           else d end
    from (select regexp_replace(coalesce(p_raw, ''), '[^0-9]', '', 'g') as d) x
$$;
revoke all on function public.quote_website_number(text) from public, anon, authenticated;

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
  v_idem  text := nullif(btrim(coalesce(p_idem, '')), '');
  v_sel   jsonb;
  v_q     public.quotations;
  v_c     public.clients;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_r     jsonb;
  v_new   boolean := false;
begin
  if v_idem is null or length(v_idem) > 80 then return jsonb_build_object('error', 'bad-request'); end if;
  select * into v_q from public.quotations q where q.idem = v_idem;
  if v_q.id is not null then
    return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key, 'again', true);
  end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 160 then return jsonb_build_object('error', 'bad-email'); end if;
  if v_wa !~ '^(60(1[0-9]{8,9}|7[0-9]{7,8})|65[0-9]{8})$' then return jsonb_build_object('error', 'bad-whatsapp'); end if;
  if length(v_brand) < 2 or length(v_brand) > 120 then return jsonb_build_object('error', 'bad-brand'); end if;
  if v_ind is not null and v_ind not in ('Property', 'F&B', 'Retail', 'Wellness', 'Lifestyle',
                                         'Automotive', 'Tech', 'Education', 'Other') then
    return jsonb_build_object('error', 'bad-industry');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-salutation');
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
    insert into public.clients (name, access_token, stage, industry, source, market, slug, deal_note)
    values (v_brand, public.new_link_key(), 'lead', v_ind, 'website',
            case when v_wa like '65%' then 'SG' else 'MY' end, v_slug,
            'Quotation requested on the website.')
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
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation made on the website · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('Monthly incl. SST RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') || ' · ' || v_name,
    v_q.id::text);
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

create or replace function public.quote_website_read(p_key text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object('ref', q.ref, 'brand', coalesce(q.contact->>'brand', q.brand), 'version', q.version,
      'issued_at', q.issued_at, 'valid_until', q.valid_until, 'lines', q.lines, 'totals', q.totals,
      'selection', q.selection, 'attention', q.contact->>'name',
      'status', q.status, 'requested', q.requested_at is not null,
      'market', case when c.market = 'SG' then 'SG' else 'MY' end,
      'today', (now() at time zone 'Asia/Kuala_Lumpur')::date)
      from public.quotations q
      left join public.clients c on c.id = q.client_id
     where p_key ~ '^[a-z0-9]{8}$' and q.access_key = p_key and q.source = 'website' and q.removed_at is null),
    jsonb_build_object('error', 'not-found'))
$$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

create or replace function public.quote_website_request(p_key text, p_billing jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_q    public.quotations;
  v_sg   boolean;
  v_reg  text := upper(btrim(regexp_replace(coalesce(p_billing->>'registered_name', ''), '\s+', ' ', 'g')));
  v_brn  text := upper(regexp_replace(coalesce(p_billing->>'brn', ''), '[^0-9A-Za-z]', '', 'g'));
  v_addr text := btrim(coalesce(p_billing->>'address', ''));
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into v_q from public.quotations q
   where q.access_key = p_key and q.source = 'website' and q.removed_at is null for update;
  if v_q.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_q.requested_at is not null then return jsonb_build_object('ok', true, 'again', true); end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if v_q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  select c.market = 'SG' into v_sg from public.clients c where c.id = v_q.client_id;
  if length(v_reg) < 3 or length(v_reg) > 160 or length(v_addr) < 10 or length(v_addr) > 400
     or (coalesce(v_sg, false) and v_brn !~ '^([0-9]{8,9}[A-Z]|[TSR][0-9]{2}[A-Z]{2}[0-9]{4}[A-Z])$')
     or (not coalesce(v_sg, false) and v_brn !~ '^[0-9]{12}$') then
    return jsonb_build_object('error', 'bad-billing');
  end if;
  update public.quotations
     set billing = jsonb_build_object('registered_name', v_reg, 'brn', v_brn, 'address', v_addr),
         requested_at = now(), status = 'requested'
   where id = v_q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_q.contact->>'name', 'Website'), 'client.quotation', v_q.brand,
          v_q.ref || ' · Letter of Offer requested on the website');
  perform public.quote_tell(v_q.client_id, 'quote.requested', 'Letter of Offer requested · ' || v_q.brand,
    v_q.ref || ' · ' || v_reg, v_q.id::text);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quote_website_request(text, jsonb) from public;
grant execute on function public.quote_website_request(text, jsonb) to anon, authenticated;

-- END OF QUOTE WEBSITE GUARDS -----------------------------------------------
select public.functions_tidy();
