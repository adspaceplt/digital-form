-- ===========================================================================
-- QUOTE WEBSITE LIVE PRICES (2026-11-24)
-- ===========================================================================
-- WHY: the user approved an interactive /quote/ (the canvas boards
-- QuotePhone and QuoteDesk, 2026-11-24): the prospect sees the price follow
-- every choice, each plan its monthly fee, each platform past the plan's
-- places what it adds, each item its rate, and a running summary. Before,
-- no rate was shown until the team sent the quotation (`quote_catalogue`
-- held none). The quotation itself still waits for the team.
--
-- WHAT CHANGED
--   * `quote_web_terms()` (internal): the commitments /quote/ offers, 6, 12
--     and 24 months; 3 and 18 stay Build quote's.
--   * `quote_website_sel(p_sel, p_snap)` (internal): what a website
--     selection may hold, one copy for the preview and the create: the keys
--     the price reads, no translation (Build quote's alone), a term from
--     `quote_web_terms()` (1 only where nothing monthly is held, which
--     `quote_price` refuses), and one-off items of the card's contents,
--     verifications, KOC and KOL lines and its File Release add-ons
--     (Working files, Raw footage); any other add-on (revisions, urgent,
--     adaptation, an outstation fee) is the team's, refused `bad-once`.
--   * `quote_catalogue()` (anon) now carries the live version's rates: each
--     plan's fee and inclusions, each platform's fee, each content's,
--     verification's (with the platform it verifies) and KOC package's rate,
--     what managing each advertising budget costs a month, the File Release add-ons, the website's terms
--     with their percentages and SST in force today.
--   * `quote_website_preview(p_sel)` (anon, writes nothing): the selection
--     priced as `quotation_make` prices a website quotation (`quote_compose`
--     on the live version, SST of today, in RM), answering its lines,
--     totals, extra content rates and version; `unavailable` while the page
--     is covered.
--   * `quote_website_create` normalises through `quote_website_sel`.
--
-- ORDER: the pages first (a page served before keeps its rate-free steps,
-- and its 3 or 18 months or translation are then refused `bad-term` /
-- dropped, read as "Not sent. Please try again."), then this file
-- (connector). Safe to run twice.
-- ROLLBACK: run `quote_catalogue` and `quote_website_create` from their
-- earlier sections again and `drop function public.quote_website_preview(jsonb)`;
-- the helpers may stay.
-- ===========================================================================

-- QUOTE WEBSITE LIVE PRICES ---------------------------------------------------

/* The commitments a prospect may choose on /quote/ (the user, 2026-11-24:
   6, 12 and 24 months, the minimum 6). */
create or replace function public.quote_web_terms()
returns int[]
language sql immutable set search_path = public as $$
  select array[6, 12, 24]
$$;
revoke all on function public.quote_web_terms() from public, anon, authenticated;

/* A one-off item a prospect may add on /quote/: a content, a verification,
   a creator package, and of the add-ons the card's File Release group
   alone; every other add-on is added by the team in Build quote. */
create or replace function public.quote_web_once_ok(p_svc jsonb)
returns boolean
language sql immutable set search_path = public as $$
  select coalesce(p_svc->'spec'->>'role', '') in ('content', 'verify', 'koc', 'kol')
      or (p_svc->'spec'->>'role' = 'addon' and lower(coalesce(p_svc->'spec'->>'group', '')) = 'file release')
$$;
revoke all on function public.quote_web_once_ok(jsonb) from public, anon, authenticated;

/* What a website selection may hold, and nothing else: one copy for the
   preview and the create. */
create or replace function public.quote_website_sel(p_sel jsonb, p_snap jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_sel jsonb;
  v_o jsonb;
begin
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if jsonb_typeof(p_sel->'once') = 'array' and jsonb_array_length(p_sel->'once') > 20
     or jsonb_typeof(p_sel->'extra') = 'object' and (select count(*) from jsonb_object_keys(p_sel->'extra')) > 10 then
    return jsonb_build_object('error', 'bad-selection');
  end if;
  v_sel := jsonb_strip_nulls(jsonb_build_object(
    'mix', case when jsonb_typeof(p_sel->'mix') = 'string' and length(p_sel->>'mix') <= 20 then p_sel->'mix' end,
    'plan', case when jsonb_typeof(p_sel->'plan') = 'string' and length(p_sel->>'plan') <= 80 then p_sel->'plan' end,
    'term', case when jsonb_typeof(p_sel->'term') in ('number', 'string') and length(p_sel->>'term') <= 4 then p_sel->'term' end,
    'budget', case when jsonb_typeof(p_sel->'budget') in ('number', 'string') and length(p_sel->>'budget') <= 12 then p_sel->'budget' end,
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
  -- The website's commitments; 1 is one-off items alone (quote_price refuses it beside a monthly line).
  if coalesce(v_sel->>'term', '') !~ '^[0-9]{1,2}$'
     or not ((v_sel->>'term')::int = 1 or (v_sel->>'term')::int = any (public.quote_web_terms())) then
    return jsonb_build_object('error', 'bad-term');
  end if;
  for v_o in select * from jsonb_array_elements(coalesce(v_sel->'once', '[]'::jsonb)) loop
    if not coalesce(public.quote_web_once_ok(public.quote_svc(p_snap, v_o->>'slug')), false) then
      return jsonb_build_object('error', 'bad-once');
    end if;
  end loop;
  return v_sel;
end $$;
revoke all on function public.quote_website_sel(jsonb, jsonb) from public, anon, authenticated;

create or replace function public.quote_catalogue()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_card jsonb := public.quote_card();
  v_svc jsonb;
  v_text jsonb;
  v_set jsonb;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_names constant jsonb := '{"meta":"Meta","tiktok":"TikTok","rednote":"rednote","linkedin":"LinkedIn"}';
begin
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_svc := coalesce(v_card->'snapshot'->'services', '[]'::jsonb);
  v_text := coalesce(v_card->'snapshot'->'text', '{}'::jsonb);
  -- SST and the term percentages in force today, as the preview prices them.
  v_set := coalesce(public.quote_tax_snap(v_card->'snapshot', null, v_today)->'settings', '{}'::jsonb);
  return jsonb_build_object(
    'version', v_card->>'version',
    'valid_days', coalesce(public.app_setting('quote_valid_days', v_today), 30)::int,
    'sst_pct', coalesce((v_set->>'sst_pct')::numeric, 0),
    'terms', (select jsonb_agg(jsonb_build_object('months', m, 'pct', public.quote_term_pct(v_set, m)) order by m)
                from unnest(public.quote_web_terms()) m),
    'plans', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', s->>'slug', 'plan', s->'spec'->>'plan', 'ads', coalesce((s->'spec'->>'ads')::boolean, false),
        'platforms', (s->'spec'->>'platforms')::int, 'contents', (s->'spec'->>'contents')::int,
        'mix', s->'spec'->'mix', 'ad_budget', (s->'spec'->>'ad_budget')::numeric, 'best_for', s->'spec'->>'best_for',
        'rate', (s->>'rate')::numeric,
        'included', coalesce((select jsonb_agg(btrim(d)) from unnest(string_to_array(coalesce(v_text->>
            case when coalesce((s->'spec'->>'ad_budget')::numeric, 0) > 0 then 'plans_ads_included' else 'plans_included' end, ''), E'\n')) d
           where btrim(d) <> ''), '[]'::jsonb))
        order by s->'spec'->>'plan')
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'plan' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'platforms', coalesce((select jsonb_agg(s->'spec'->>'platform'
        order by array_position(array['meta', 'tiktok', 'rednote', 'linkedin'], s->'spec'->>'platform'))
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'platform' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'platform_rates', coalesce((select jsonb_object_agg(s->'spec'->>'platform', (s->>'rate')::numeric)
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'platform' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '{}'::jsonb),
    'contents', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name', 'kind', s->'spec'->>'kind',
        'rate', (s->>'rate')::numeric) order by (s->>'rate')::numeric)
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'content' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'budgets', coalesce((select jsonb_agg(b order by b) from (
        select distinct (s->'spec'->>'budget')::numeric b from jsonb_array_elements(v_svc) s
         where s->'spec'->>'role' in ('ads', 'booster') and s->>'rate' is not null
           and coalesce((s->>'active')::boolean, true)) z), '[]'::jsonb),
    -- what managing each budget costs a month, as quote_price charges it
    -- (beside a plan, the cost of the budget less the cost of its cover)
    'ad_costs', coalesce((select jsonb_agg(jsonb_build_object('budget', b, 'cost', public.quote_ads_cost(v_card->'snapshot', b)) order by b)
      from (select distinct (s->'spec'->>'budget')::numeric b from jsonb_array_elements(v_svc) s
             where s->'spec'->>'role' in ('ads', 'booster') and s->>'rate' is not null
               and coalesce((s->>'active')::boolean, true)) z), '[]'::jsonb),
    'verify', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name', 'rate', (s->>'rate')::numeric,
        -- the platform it verifies: its own, else the platform its name names
        'platform', coalesce(s->'spec'->>'platform', (select k from jsonb_each_text(v_names) n(k, w)
                                                        where s->>'name' ~* ('\m' || w || '\M') limit 1))))
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'verify' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'koc', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name',
        'creators', (s->'spec'->>'creators')::int, 'rate', (s->>'rate')::numeric) order by (s->'spec'->>'creators')::int nulls last)
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'koc' and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'kol', (select s->>'slug' from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'kol' and coalesce((s->>'active')::boolean, true) limit 1),
    'files', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name', 'rate', (s->>'rate')::numeric)
        order by (s->>'rate')::numeric)
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'addon' and public.quote_web_once_ok(s) and s->>'rate' is not null
       and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'translation', false);
end $$;
revoke all on function public.quote_catalogue() from public;
grant execute on function public.quote_catalogue() to anon, authenticated;

/* The price as the prospect chooses (the user, 2026-11-24): the selection
   priced as quotation_make prices a website quotation, on the live
   version, SST of today, in RM. Nothing is kept. */
create or replace function public.quote_website_preview(p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_card jsonb := public.quote_card();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_snap jsonb;
  v_sel jsonb;
  v_p jsonb;
begin
  if public.page_covered('quote') then return jsonb_build_object('error', 'unavailable'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_snap := public.quote_tax_snap(v_card->'snapshot', null, v_today);
  v_sel := public.quote_website_sel(p_sel, v_snap);
  if v_sel ? 'error' then return v_sel; end if;
  v_p := public.quote_compose(v_snap, v_sel, false);
  if v_p ? 'error' then return jsonb_build_object('error', v_p->>'error'); end if;
  return jsonb_build_object(
    'lines', coalesce((select jsonb_agg(jsonb_build_object('slug', l->>'slug', 'kind', l->>'kind', 'basis', l->>'basis',
        'label', l->>'label', 'qty', (l->>'qty')::numeric, 'rate', (l->>'rate')::numeric,
        'amount', coalesce((l->>'amount')::numeric, round((l->>'qty')::numeric * (l->>'rate')::numeric, 2))) order by n)
      from jsonb_array_elements(v_p->'lines') with ordinality x(l, n)), '[]'::jsonb),
    'on_request', coalesce(v_p->'on_request', '[]'::jsonb),
    'extra_rates', coalesce(v_p->'extra_rates', '{}'::jsonb),
    'totals', jsonb_build_object('term', v_p->'totals'->'term', 'term_pct', v_p->'totals'->'term_pct',
      'sst_pct', v_p->'totals'->'sst_pct', 'budget', v_p->'totals'->'budget', 'month', v_p->'totals'->'month',
      'once', v_p->'totals'->'once', 'term_rows', v_p->'totals'->'term_rows'),
    'version', v_card->>'version');
end $$;
revoke all on function public.quote_website_preview(jsonb) from public;
grant execute on function public.quote_website_preview(jsonb) to anon, authenticated;

/* The website's create, its selection read through quote_website_sel. */
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
  -- What the price reads, and nothing else: one copy with the preview
  -- (QUOTE WEBSITE LIVE PRICES, 2026-11-24).
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
  -- quotation is made (a refused one changes nothing).
  if not v_new and v_start is not null and v_c.commence is distinct from v_start then
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
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation to review · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', 'one-off') || ' · ' || v_name
      || coalesce(' · Preferred start date ' || public.register_day(v_on),
                  ' · Starts ' || lower(public.quote_commence_word(v_start)), '')
      || ' · Send by ' || public.register_day((v_q.reply_due at time zone 'Asia/Kuala_Lumpur')::date)
      || ' (' || trim(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMDay')) || '), ' ||
      lower(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
    v_q.id::text);
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

-- END OF QUOTE WEBSITE LIVE PRICES ---------------------------------------------

select public.functions_tidy();
