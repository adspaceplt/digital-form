-- ===========================================================================
-- QUOTE FILES CAPPED (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25: the files a prospect asks for are held to what
-- their selection makes. Working files at most the graphics in it, Raw
-- footage at most the reels ("1 graphic and 3 reels": Working files 1,
-- Raw footage 3; Plan F, 4 graphics and 6 reels: 4 and 6).
--
-- WHAT CHANGED
--   * `quote_piece_class(kind)` (internal): a content piece's kind on the
--     card as a graphic (graphic, gif, carousel) or a reel (reel30, reel,
--     video120). The one reading; the catalogue hands it to /quote/.
--   * `quote_file_covers(service)` (internal): what a File Release line
--     covers, its spec's `covers` where the card states one, else Working
--     files the graphics and Raw footage the reels (by slug, for the cards
--     published before 2026-11-25). A line covering neither covers every
--     piece.
--   * `quote_files_cap(selection, snapshot)` (internal): the graphics and
--     reels a selection makes: the plan's content option (as quote_price
--     reads `mix`), its additional content pieces each month, and the
--     one-time content chosen.
--   * `quote_files_fit(selection, snapshot, base)` (internal): each File
--     Release line brought down to the pieces it covers, a line left at
--     none taken out; a count the quotation already held (`base`, what the
--     team agreed by hand) stays allowed.
--   * `quote_website_sel` (the create) and `quote_change_sel` (the sent
--     link's preview and change request) hold the files so. A page is never
--     trusted for it.
--   * `quote_catalogue()` (anon) answers each content's `piece` and each
--     file's `covers`, never a rate.
--   * `quote_preview(sel)` (the team's Build quote) answers `files_over`:
--     the File Release lines asked beyond the pieces they cover, a brand's
--     index with each. Build quote warns; it never refuses (the team may
--     agree more by hand).
--   The files' basis is unchanged: a File Release line is priced one-time
--   (quote_price `basis` once) with a plan or without; the cap is the
--   pieces the selection makes in a month with a plan, and the one-time
--   pieces without one.
--
-- ORDER: the pages first (Pages deploy), then this file (connector). An
-- old tab meanwhile: /quote/ before the pages deploy sends any count; the
-- create holds it to the cap once this file runs, until then as before.
-- The new pages before this file: the catalogue answers no `piece` or
-- `covers`, so /quote/ offers every file uncapped (as today) and Build
-- quote reads no `files_over` (no warning). Safe to run twice.
-- ROLLBACK: run `quote_website_sel` and `quote_catalogue` from the QUOTE
-- WEBSITE BILINGUAL section, `quote_change_sel` from QUOTATION CHANGES
-- REQUESTED and `quote_preview` from QUOTATION BRANDS again; the four new
-- helpers are then read by nothing.
-- ===========================================================================

-- QUOTE FILES CAPPED -----------------------------------------------------------


/* A content piece's kind as the files read it: a graphic or a reel. */
create or replace function public.quote_piece_class(p_kind text)
returns text
language sql immutable set search_path = public as $$
  select case when p_kind in ('graphic', 'gif', 'carousel') then 'graphic'
              when p_kind in ('reel30', 'reel', 'video120') then 'reel' end
$$;
revoke all on function public.quote_piece_class(text) from public, anon, authenticated;

/* What a File Release line covers: the card's own word, else Working files
   the graphics and Raw footage the reels; null covers every piece. */
create or replace function public.quote_file_covers(p_svc jsonb)
returns text
language sql immutable set search_path = public as $$
  select case when p_svc->'spec'->>'covers' in ('graphic', 'reel') then p_svc->'spec'->>'covers'
              when p_svc->>'slug' = 'working-files' then 'graphic'
              when p_svc->>'slug' = 'raw-footage' then 'reel' end
$$;
revoke all on function public.quote_file_covers(jsonb) from public, anon, authenticated;

/* The graphics and reels a selection makes: the plan's content option and
   additional content pieces each month, and the one-time content chosen. */
create or replace function public.quote_files_cap(p_sel jsonb, p_snap jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_g int := 0;
  v_r int := 0;
  v_plan jsonb;
  v_mix jsonb;
  v_i int := 0;
  v_k text;
  v_c text;
  v_n int;
  v_s jsonb;
  v_o jsonb;
begin
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('graphic', 0, 'reel', 0); end if;
  v_plan := public.quote_svc(p_snap, p_sel->>'plan');
  if v_plan->'spec'->>'role' = 'plan' and jsonb_typeof(v_plan->'spec'->'mix') = 'array'
     and jsonb_array_length(v_plan->'spec'->'mix') > 0 then
    if coalesce(p_sel->>'mix', '0') ~ '^[0-9]$' then v_i := coalesce((p_sel->>'mix')::int, 0); end if;
    if v_i >= jsonb_array_length(v_plan->'spec'->'mix') then v_i := 0; end if;
    v_mix := v_plan->'spec'->'mix'->v_i;
    if jsonb_typeof(v_mix) = 'object' then
      for v_k in select jsonb_object_keys(v_mix) loop
        v_c := public.quote_piece_class(v_k);
        v_n := case when coalesce(v_mix->>v_k, '') ~ '^[0-9]{1,3}$' then (v_mix->>v_k)::int else 0 end;
        if v_c = 'graphic' then v_g := v_g + v_n; elsif v_c = 'reel' then v_r := v_r + v_n; end if;
      end loop;
    end if;
    if jsonb_typeof(p_sel->'extra') = 'object' then
      for v_k in select jsonb_object_keys(p_sel->'extra') loop
        v_s := public.quote_svc(p_snap, v_k);
        if v_s->'spec'->>'role' = 'content' and coalesce(p_sel->'extra'->>v_k, '') ~ '^[0-9]{1,3}$' then
          v_c := public.quote_piece_class(v_s->'spec'->>'kind');
          v_n := (p_sel->'extra'->>v_k)::int;
          if v_c = 'graphic' then v_g := v_g + v_n; elsif v_c = 'reel' then v_r := v_r + v_n; end if;
        end if;
      end loop;
    end if;
  end if;
  if jsonb_typeof(p_sel->'once') = 'array' then
    for v_o in select * from jsonb_array_elements(p_sel->'once') loop
      v_s := public.quote_svc(p_snap, v_o->>'slug');
      if v_s->'spec'->>'role' = 'content' and coalesce(v_o->>'qty', '') ~ '^[0-9]{1,3}$' then
        v_c := public.quote_piece_class(v_s->'spec'->>'kind');
        v_n := (v_o->>'qty')::int;
        if v_c = 'graphic' then v_g := v_g + v_n; elsif v_c = 'reel' then v_r := v_r + v_n; end if;
      end if;
    end loop;
  end if;
  return jsonb_build_object('graphic', v_g, 'reel', v_r);
end $$;
revoke all on function public.quote_files_cap(jsonb, jsonb) from public, anon, authenticated;

/* Each File Release line held to the pieces it covers, a line left at
   none taken out; a count the quotation already held (`p_base`) stays. */
create or replace function public.quote_files_fit(p_sel jsonb, p_snap jsonb, p_base jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_cap jsonb;
  v_out jsonb := '[]'::jsonb;
  v_o jsonb;
  v_s jsonb;
  v_c text;
  v_lim int;
  v_held int;
begin
  if jsonb_typeof(p_sel) is distinct from 'object' or jsonb_typeof(p_sel->'once') is distinct from 'array' then return p_sel; end if;
  v_cap := public.quote_files_cap(p_sel, p_snap);
  for v_o in select * from jsonb_array_elements(p_sel->'once') loop
    v_s := public.quote_svc(p_snap, v_o->>'slug');
    if v_s->'spec'->>'role' = 'addon' and public.quote_web_once_ok(v_s) and jsonb_typeof(v_o->'qty') = 'number' then
      v_c := public.quote_file_covers(v_s);
      v_lim := case when v_c is null then (v_cap->>'graphic')::int + (v_cap->>'reel')::int else (v_cap->>v_c)::int end;
      select coalesce(max(case when coalesce(b->>'qty', '') ~ '^[0-9]{1,3}$' then (b->>'qty')::int end), 0) into v_held
        from jsonb_array_elements(case when jsonb_typeof(p_base->'once') = 'array' then p_base->'once' else '[]'::jsonb end) b
       where b->>'slug' = v_o->>'slug';
      v_lim := greatest(v_lim, v_held);
      if v_lim > 0 then
        v_out := v_out || jsonb_build_array(case when (v_o->>'qty')::numeric > v_lim then v_o || jsonb_build_object('qty', v_lim) else v_o end);
      end if;
    else
      v_out := v_out || jsonb_build_array(v_o);
    end if;
  end loop;
  return p_sel || jsonb_build_object('once', v_out);
end $$;
revoke all on function public.quote_files_fit(jsonb, jsonb, jsonb) from public, anon, authenticated;

/* What a website selection may hold, and nothing else: since 2026-11-25
   the prospect may ask for every content piece bilingual, kept only with
   two languages or more, and priced as Translation by the team; and the
   files are held to the pieces the selection makes. */
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
  -- The website's commitments; 1 is one-time items alone (quote_price refuses it beside a monthly line).
  if coalesce(v_sel->>'term', '') !~ '^[0-9]{1,2}$'
     or not ((v_sel->>'term')::int = 1 or (v_sel->>'term')::int = any (public.quote_web_terms())) then
    return jsonb_build_object('error', 'bad-term');
  end if;
  for v_o in select * from jsonb_array_elements(coalesce(v_sel->'once', '[]'::jsonb)) loop
    if not coalesce(public.quote_web_once_ok(public.quote_svc(p_snap, v_o->>'slug')), false) then
      return jsonb_build_object('error', 'bad-once');
    end if;
  end loop;
  -- The files held to the graphics and reels the selection makes.
  if v_sel ? 'once' then
    v_sel := public.quote_files_fit(v_sel, p_snap, null);
    if jsonb_array_length(v_sel->'once') = 0 then v_sel := v_sel - 'once'; end if;
  end if;
  return v_sel;
end $$;
revoke all on function public.quote_website_sel(jsonb, jsonb) from public, anon, authenticated;

/* The quotation's own selection with the prospect's changes in place, the
   files held to the pieces it makes (what the quotation held stays). */
create or replace function public.quote_change_sel(p_base jsonb, p_sel jsonb, p_snap jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v jsonb := coalesce(p_base, '{}'::jsonb);
  s jsonb;
  k text;
  n int;
  v_ex jsonb := '{}'::jsonb;
  v_once jsonb := '[]'::jsonb;
begin
  if p_sel is null then return v; end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if v ? 'brands' then return jsonb_build_object('error', 'brands'); end if;
  if p_sel ? 'plan' then
    s := public.quote_svc(p_snap, p_sel->>'plan');
    if jsonb_typeof(p_sel->'plan') <> 'string' or s is null or s->'spec'->>'role' is distinct from 'plan' or s->>'rate' is null then
      return jsonb_build_object('error', 'bad-plan');
    end if;
    if p_sel->>'plan' is distinct from v->>'plan' then v := v - 'mix' - 'extra'; end if;
    v := v || jsonb_build_object('plan', p_sel->>'plan');
  end if;
  if p_sel ? 'mix' then
    if jsonb_typeof(p_sel->'mix') <> 'string' or p_sel->>'mix' !~ '^[0-9]$' then return jsonb_build_object('error', 'bad-selection'); end if;
    v := v || jsonb_build_object('mix', p_sel->>'mix');
  end if;
  if p_sel ? 'platforms' then
    if jsonb_typeof(p_sel->'platforms') <> 'array' then return jsonb_build_object('error', 'bad-selection'); end if;
    v := v || jsonb_build_object('platforms', coalesce((select jsonb_agg(x order by array_position(array['meta', 'tiktok', 'rednote', 'linkedin'], x))
                                                          from (select distinct x from jsonb_array_elements_text(p_sel->'platforms') x
                                                                 where x in ('meta', 'tiktok', 'rednote', 'linkedin')) d), '[]'::jsonb));
  end if;
  if p_sel ? 'extra' then
    if jsonb_typeof(p_sel->'extra') <> 'object' or (select count(*) from jsonb_object_keys(p_sel->'extra')) > 10 then
      return jsonb_build_object('error', 'bad-extra');
    end if;
    for k in select jsonb_object_keys(p_sel->'extra') loop
      s := public.quote_svc(p_snap, k);
      if s is null or s->'spec'->>'role' is distinct from 'content' or coalesce(p_sel->'extra'->>k, '') !~ '^[0-9]{1,2}$' then
        return jsonb_build_object('error', 'bad-extra');
      end if;
      n := (p_sel->'extra'->>k)::int;
      if n > 0 then v_ex := v_ex || jsonb_build_object(k, n); end if;
    end loop;
    v := v || jsonb_build_object('extra', v_ex);
  end if;
  if p_sel ? 'files' then
    if jsonb_typeof(p_sel->'files') <> 'object' or (select count(*) from jsonb_object_keys(p_sel->'files')) > 5 then
      return jsonb_build_object('error', 'bad-once');
    end if;
    -- the files asked for replace the files held; every other one-time item stays
    select coalesce(jsonb_agg(o), '[]'::jsonb) into v_once from jsonb_array_elements(coalesce(v->'once', '[]'::jsonb)) o
     where not (coalesce(public.quote_svc(p_snap, o->>'slug')->'spec'->>'role', '') = 'addon'
                and public.quote_web_once_ok(public.quote_svc(p_snap, o->>'slug')));
    for k in select jsonb_object_keys(p_sel->'files') loop
      s := public.quote_svc(p_snap, k);
      if s is null or s->'spec'->>'role' is distinct from 'addon' or not public.quote_web_once_ok(s)
         or coalesce(p_sel->'files'->>k, '') !~ '^[0-9]{1,2}$' then
        return jsonb_build_object('error', 'bad-once');
      end if;
      n := (p_sel->'files'->>k)::int;
      if n > 0 then v_once := v_once || jsonb_build_array(jsonb_build_object('slug', k, 'qty', n)); end if;
    end loop;
    v := v || jsonb_build_object('once', v_once);
  end if;
  if p_sel ? 'term' then
    if coalesce(p_sel->>'term', '') !~ '^[0-9]{1,2}$'
       or not ((p_sel->>'term')::int = any (public.quote_web_terms()) or (p_sel->>'term')::int = (p_base->>'term')::int) then
      return jsonb_build_object('error', 'bad-term');
    end if;
    v := v || jsonb_build_object('term', (p_sel->>'term')::int);
  end if;
  -- The files held to the graphics and reels the changed selection makes.
  if v ? 'once' then v := public.quote_files_fit(v, p_snap, p_base); end if;
  return v;
end $$;
revoke all on function public.quote_change_sel(jsonb, jsonb, jsonb) from public, anon, authenticated;

/* What the website offers from the live card, never a rate (the user,
   2026-11-25: "Prices after we send"): each content's piece (a graphic or
   a reel) and what each file covers, so the files are held to them. */
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
    'contents', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name', 'kind', s->'spec'->>'kind',
        'piece', public.quote_piece_class(s->'spec'->>'kind'))
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
    'files', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name',
        'covers', public.quote_file_covers(s)) order by (s->>'rate')::numeric)
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'addon' and public.quote_web_once_ok(s) and s->>'rate' is not null
       and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    -- Whether the card prices a translation, never its rate.
    'translation', exists (select 1 from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'language' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)));
end $$;
revoke all on function public.quote_catalogue() from public;
grant execute on function public.quote_catalogue() to anon, authenticated;

/* Build quote's preview, with the File Release lines asked beyond the
   pieces they cover (`files_over`, a brand's index with each): the team
   is warned, never refused. */
create or replace function public.quote_preview(p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_on date := public.doc_day_of(p_sel->>'date');
  v_card jsonb;
  v_cl uuid;
  v_fx numeric;
  v_over jsonb := '[]'::jsonb;
  v_b jsonb;
  v_i int;
  v_s jsonb;
  v_cap jsonb;
  v_o jsonb;
  v_x jsonb;
  v_c text;
  v_lim int;
begin
  -- Priced on the quotation's own date (2026-11-12), today where none.
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  v_on := coalesce(v_on, (now() at time zone 'Asia/Kuala_Lumpur')::date);
  v_card := public.quote_card(v_on, nullif(btrim(coalesce(p_sel->>'card', '')), ''));
  if not public.is_team() or not public.allowed('clients.quotes', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_card is null then return jsonb_build_object('error', case when nullif(btrim(coalesce(p_sel->>'card', '')), '') is not null then 'bad-card' else 'no-card' end); end if;
  if coalesce(p_sel->>'client', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and public.client_scope_ok('client', (p_sel->>'client')::uuid, 'view') then
    v_cl := (p_sel->>'client')::uuid;
  end if;
  v_fx := public.quote_fx(v_cl, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- The files asked beyond the pieces they cover, each brand on its own.
  for v_b, v_i in
    select case when jsonb_typeof(p_sel->'brands') = 'array' then (p_sel - 'brands') || b else p_sel end,
           case when jsonb_typeof(p_sel->'brands') = 'array' then (n - 1)::int end
      from jsonb_array_elements(case when jsonb_typeof(p_sel->'brands') = 'array' then p_sel->'brands' else '[null]'::jsonb end)
           with ordinality x(b, n)
     where jsonb_typeof(p_sel->'brands') is distinct from 'array' or jsonb_typeof(b) = 'object'
  loop
    if jsonb_typeof(v_b->'once') = 'array' then
      v_cap := public.quote_files_cap(v_b, v_card->'snapshot');
      for v_o in select * from jsonb_array_elements(v_b->'once') loop
        v_s := public.quote_svc(v_card->'snapshot', v_o->>'slug');
        if v_s->'spec'->>'role' = 'addon' and public.quote_web_once_ok(v_s) and coalesce(v_o->>'qty', '') ~ '^[0-9]{1,3}$' then
          v_c := public.quote_file_covers(v_s);
          v_lim := case when v_c is null then (v_cap->>'graphic')::int + (v_cap->>'reel')::int else (v_cap->>v_c)::int end;
          if (v_o->>'qty')::int > v_lim then
            v_x := jsonb_build_object('slug', v_s->>'slug', 'name', v_s->>'name', 'qty', (v_o->>'qty')::int, 'cap', v_lim, 'covers', v_c, 'brand', v_i);
            v_over := v_over || jsonb_build_array(v_x);
          end if;
        end if;
      end loop;
    end if;
  end loop;
  -- Custom lines and starts (2026-11-12) priced with the rest, before S$.
  return public.quote_fx_out(public.quote_compose(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_cl, v_on), v_fx),
           p_sel - 'client' - 'date', true), v_fx)
         || jsonb_build_object('version', v_card->>'version', 'versions', public.quote_card_versions(), 'files_over', v_over);
end $$;
revoke all on function public.quote_preview(jsonb) from public, anon;
grant execute on function public.quote_preview(jsonb) to authenticated;

-- END OF QUOTE FILES CAPPED ----------------------------------------------------

select public.functions_tidy();
