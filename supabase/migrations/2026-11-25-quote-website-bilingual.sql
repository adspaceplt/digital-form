-- ===========================================================================
-- QUOTE WEBSITE BILINGUAL (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25: the prospect may ask on /quote/ for every
-- content piece to be bilingual ("Make every content piece bilingual"),
-- which quotation release 1 (2026-11-24) had left to Build quote alone.
-- No price is shown on /quote/; the team prices it as Translation in
-- Build quote before the quotation is sent.
--
-- WHAT CHANGED
--   * `quote_website_sel(p_sel, p_snap)` (internal) keeps `translate`
--     (true alone) where the selection holds two languages or more, and
--     drops it otherwise. The key is Build quote's own.
--   * `quote_catalogue()` (anon) answers `translation` true where the live
--     card holds an active, priced language service; never its rate.
--
-- ORDER: the pages first, then this file (connector). Until this file
-- runs, a page that sends the tick has it dropped by the create (the
-- request is made without it) and the catalogue answers `translation`
-- false, so the tick is not drawn. Safe to run twice.
-- ROLLBACK: run `quote_website_sel` and `quote_catalogue` from the QUOTE
-- WEBSITE CHOICES section again.
-- ===========================================================================

-- QUOTE WEBSITE BILINGUAL ------------------------------------------------------


/* What a website selection may hold, and nothing else: since 2026-11-25
   the prospect may ask for every content piece bilingual, kept only with
   two languages or more, and priced as Translation by the team. */
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
    'translate', case when p_sel->'translate' = 'true'::jsonb then true end,
    'extra', case when jsonb_typeof(p_sel->'extra') = 'object' then
               (select jsonb_object_agg(left(k, 80), p_sel->'extra'->k) from jsonb_object_keys(p_sel->'extra') k) end,
    'once', case when jsonb_typeof(p_sel->'once') = 'array' then
              (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('slug', left(o->>'slug', 80), 'qty', o->'qty')))
                 from jsonb_array_elements(p_sel->'once') o where jsonb_typeof(o) = 'object') end));
  -- Bilingual with two languages or more alone.
  if v_sel ? 'translate' and coalesce(jsonb_array_length(v_sel->'langs'), 0) < 2 then v_sel := v_sel - 'translate'; end if;
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

/* What the website offers from the live card, never a rate (the user,
   2026-11-25: "Prices after we send"). */
create or replace function public.quote_catalogue()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_card jsonb := public.quote_card();
  v_svc jsonb;
  v_text jsonb;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_names constant jsonb := '{"meta":"Meta","tiktok":"TikTok","rednote":"rednote","linkedin":"LinkedIn"}';
begin
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_svc := coalesce(v_card->'snapshot'->'services', '[]'::jsonb);
  v_text := coalesce(v_card->'snapshot'->'text', '{}'::jsonb);
  return jsonb_build_object(
    'version', v_card->>'version',
    'valid_days', coalesce(public.app_setting('quote_valid_days', v_today), 30)::int,
    'terms', to_jsonb(public.quote_web_terms()),
    'plans', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', s->>'slug', 'plan', s->'spec'->>'plan', 'ads', coalesce((s->'spec'->>'ads')::boolean, false),
        'platforms', (s->'spec'->>'platforms')::int, 'contents', (s->'spec'->>'contents')::int,
        'mix', s->'spec'->'mix', 'ad_budget', (s->'spec'->>'ad_budget')::numeric, 'best_for', s->'spec'->>'best_for',
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
    'contents', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name', 'kind', s->'spec'->>'kind')
        order by (s->>'rate')::numeric)
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'content' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'budgets', coalesce((select jsonb_agg(b order by b) from (
        select distinct (s->'spec'->>'budget')::numeric b from jsonb_array_elements(v_svc) s
         where s->'spec'->>'role' in ('ads', 'booster') and s->>'rate' is not null
           and coalesce((s->>'active')::boolean, true)) z), '[]'::jsonb),
    'verify', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name',
        -- the platform it verifies: its own, else the platform its name names
        'platform', coalesce(s->'spec'->>'platform', (select k from jsonb_each_text(v_names) n(k, w)
                                                        where s->>'name' ~* ('\m' || w || '\M') limit 1))))
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'verify' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'koc', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name',
        'creators', (s->'spec'->>'creators')::int) order by (s->'spec'->>'creators')::int nulls last)
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'koc' and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'kol', (select s->>'slug' from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'kol' and coalesce((s->>'active')::boolean, true) limit 1),
    'files', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name') order by (s->>'rate')::numeric)
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'addon' and public.quote_web_once_ok(s) and s->>'rate' is not null
       and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    -- Whether the card prices a translation, never its rate.
    'translation', exists (select 1 from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'language' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)));
end $$;
revoke all on function public.quote_catalogue() from public;
grant execute on function public.quote_catalogue() to anon, authenticated;

-- END OF QUOTE WEBSITE BILINGUAL -----------------------------------------------

select public.functions_tidy();
