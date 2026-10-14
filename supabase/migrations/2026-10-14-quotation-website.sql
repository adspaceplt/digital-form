-- ===========================================================================
-- QUOTATION WEBSITE — a quotation a prospect makes for themselves at
-- /quote/, the lead it creates, and the Letter of Offer they request
-- (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-13: the quotation website on the approved canvas,
-- Website 1 to 6 and the desk view)
--   A prospect picks what they need, a plan, its platforms and what it is
--   customised with, gives their name, work email, WhatsApp number and
--   brand, and is shown their quotation at once, priced by the same
--   calculation as Build quote (`quote_price`, the live version only).
--   Proceed asks the billing details and requests the Letter of Offer; the
--   team is told at each step and issues the letter from the console.
--
-- WHAT IT ADDS
--   * `quote_catalogue()` (anon): what the website offers from the live
--     version, without a rate: plans, platforms, contents, the advertising
--     budgets, verifications, KOC packages. "The rates will be shown on the
--     final page."
--   * `quote_website_create(p_sel, p_contact, p_idem)` (the server's alone;
--     the `quote-request` function calls it after Cloudflare's check): the
--     contact is checked (a name, an email, a Malaysia or Singapore
--     WhatsApp number, a brand, consent); a lead whose contact holds the
--     same email or number is used again while it is a Lead, Contacted or
--     Proposal sent, else a new lead is made (Source Website, nobody holds
--     it, so the team takes it as any other); the quotation is kept with
--     `source` website and its own key; five a contact a day (`limit`).
--     The same key twice is the same quotation.
--   * `quote_website_read(p_key)` (anon): the quotation the key opens, as
--     it was kept; never its contact details or billing.
--   * `quote_website_request(p_key, p_billing)` (anon): Proceed. The
--     registered company name, its 12-digit registration number and the
--     billing address are kept on the quotation, which moves to Letter of
--     Offer requested (`expired`, `not-proceeding`, `bad-billing`; a second
--     press answers `again`).
--   * Each step is filed `client.quotation` and told to every colleague who
--     works leads (Clients: Leads at Work, or an admin), never a system
--     account: `ops_notifications.client_id` opens the lead's Services.
--   * `quote_price` takes a KOL campaign as an item quoted on request.
--   * The billing a prospect gave is withheld from the table and read
--     through `quotation_billing` (Clients: Billing at View), as a client's
--     billing columns are; the console's Use billing details fills the
--     client's Billing sheet with it.
--
-- ORDER
--   2026-10-07-function-hygiene.sql again (three functions join
--   `open_to_anon`), this file, the `quote-request` function, then the
--   pages. A page from before reads nothing here.
--
-- ROLLBACK
--   The pages from before; the functions may stay (nothing else calls them):
--     drop function if exists public.quote_catalogue();
--     drop function if exists public.quote_website_create(jsonb, jsonb, text);
--     drop function if exists public.quote_website_read(text);
--     drop function if exists public.quote_website_request(text, jsonb);
--     drop function if exists public.quotation_billing(uuid);
--     grant select on table public.quotations to authenticated;
--   then 2026-10-07-function-hygiene.sql from before this date.
-- ===========================================================================

alter table public.ops_notifications add column if not exists client_id uuid
  references public.clients(id) on delete cascade;

/* The one calculation, as 2026-10-14-quotations.sql made it, taking a KOL
   campaign (role kol, no single rate) as an item quoted on request. */
create or replace function public.quote_price(p_snap jsonb, p_sel jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_svc jsonb := coalesce(p_snap->'services', '[]'::jsonb);
  v_set jsonb := coalesce(p_snap->'settings', '{}'::jsonb);
  v_text jsonb := coalesce(p_snap->'text', '{}'::jsonb);
  v_lines jsonb := '[]'::jsonb;
  v_req text[] := '{}';
  v_plan jsonb; v_spec jsonb; v_mix jsonb; v_opt jsonb;
  v_term int; v_mixi int := 0; v_slots int := 0; v_contents int := 0;
  v_meta numeric; v_fee numeric; v_val numeric; v_best numeric := 0; v_factor numeric;
  v_cover numeric := 0; v_budget numeric := 0; v_cost numeric; v_from numeric;
  v_plats text[] := '{}'; v_in text[] := '{}'; v_p text; v_k text; v_n int; v_q int;
  v_s jsonb; v_rate numeric; v_langs text[] := '{}'; v_l text; v_base text;
  v_sub numeric := 0; v_once numeric := 0; v_pct numeric := 0; v_off numeric; v_excl numeric;
  v_sst_pct numeric := coalesce((v_set->>'sst_pct')::numeric, 0); v_sst numeric; v_osst numeric;
  v_detail text[]; v_words text[]; v_tot int := 0; v_x jsonb; v_month boolean := false;
  v_hint jsonb := '{}'::jsonb;
  v_names constant jsonb := '{"meta":"Meta","tiktok":"TikTok","rednote":"rednote","linkedin":"LinkedIn"}';
  v_lname constant jsonb := '{"en":"English","zh":"Chinese","ms":"Malay"}';
begin
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if coalesce(p_sel->>'term', '') !~ '^[0-9]{1,2}$' then return jsonb_build_object('error', 'bad-term'); end if;
  v_term := (p_sel->>'term')::int;
  if v_term < 1 or v_term > 36 then return jsonb_build_object('error', 'bad-term'); end if;
  select (s->>'rate')::numeric into v_meta from jsonb_array_elements(v_svc) s
   where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = 'meta' limit 1;
  v_meta := coalesce(v_meta, 0);

  -- Platforms asked for, known and once each, cheapest first.
  select coalesce(array_agg(p order by f, o), '{}') into v_plats
    from (select x.p, x.o, (select (s->>'rate')::numeric from jsonb_array_elements(v_svc) s
                             where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = x.p
                               and coalesce((s->>'active')::boolean, true) limit 1) f
            from (select distinct on (v) v as p, array_position(array['meta', 'tiktok', 'rednote', 'linkedin'], v) o
                    from jsonb_array_elements_text(coalesce(p_sel->'platforms', '[]'::jsonb)) v
                   where v in ('meta', 'tiktok', 'rednote', 'linkedin')) x) y
   where f is not null;

  if nullif(p_sel->>'plan', '') is not null then
    v_plan := public.quote_svc(p_snap, p_sel->>'plan');
    v_spec := v_plan->'spec';
    if v_plan is null or v_spec->>'role' is distinct from 'plan' or v_plan->>'rate' is null then
      return jsonb_build_object('error', 'bad-plan');
    end if;
    if v_term < 6 then return jsonb_build_object('error', 'plan-term'); end if;
    if coalesce(p_sel->>'mix', '0') ~ '^[0-9]$' then v_mixi := coalesce((p_sel->>'mix')::int, 0); end if;
    if v_mixi >= jsonb_array_length(v_spec->'mix') then v_mixi := 0; end if;
    v_mix := v_spec->'mix'->v_mixi;
    v_slots := (v_spec->>'platforms')::int;
    v_contents := (v_spec->>'contents')::int;
    v_cover := coalesce((v_spec->>'ad_budget')::numeric, 0);
    if array_length(v_plats, 1) is null then return jsonb_build_object('error', 'no-platform'); end if;
    v_in := v_plats[1:v_slots];

    -- The plan's whole saving: its fee against everything in it at Ala Carte,
    -- on the option worth more.
    for v_opt in select * from jsonb_array_elements(v_spec->'mix') loop
      v_val := v_slots * v_meta + coalesce(public.quote_ads_cost(p_snap, v_cover), 0);
      for v_k in select jsonb_object_keys(v_opt) loop
        select (s->>'rate')::numeric into v_rate from jsonb_array_elements(v_svc) s
         where s->'spec'->>'role' = 'content' and s->'spec'->>'kind' = v_k limit 1;
        v_val := v_val + coalesce(v_rate, 0) * (v_opt->>v_k)::int;
      end loop;
      v_best := greatest(v_best, v_val);
    end loop;
    v_factor := case when v_best > 0 then (v_plan->>'rate')::numeric / v_best else 1 end;
    -- What one more of each content costs on this plan, for the builder.
    select coalesce(jsonb_object_agg(s->>'slug', round((s->>'rate')::numeric * v_factor / 10) * 10), '{}'::jsonb) into v_hint
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'content' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true);

    v_words := '{}';
    for v_k in select k from jsonb_object_keys(v_mix) k
                order by array_position(array['graphic', 'reel'], k) nulls last, k loop
      v_n := (v_mix->>v_k)::int;
      v_words := v_words || (v_n || ' ' || case v_k when 'graphic' then case when v_n = 1 then 'graphic' else 'graphics' end
        when 'reel' then case when v_n = 1 then 'reel' else 'reels' end else v_k end);
    end loop;
    v_detail := array[v_contents || ' contents per month: ' || array_to_string(v_words, ' and ') ||
      case when v_mix ? 'reel' then ', up to 60 seconds each' else '' end];
    if v_cover > 0 then
      v_detail := v_detail || ('Advertising budget coverage up to ' || public.quote_rm(v_cover) || ' per month');
    end if;
    v_detail := v_detail || string_to_array(coalesce(v_text->>case when v_cover > 0 then 'plans_ads_included' else 'plans_included' end, ''), E'\n');
    v_lines := v_lines || jsonb_build_object('slug', v_plan->>'slug', 'kind', 'plan', 'basis', 'month',
      'label', 'Social Media Services · Plan ' || (v_spec->>'plan') || ' (' ||
        regexp_replace((select string_agg(v_names->>x, ', ' order by o) from unnest(v_in) with ordinality u(x, o)),
                       ', ([^,]*)$', ' and \1') || ')',
      'detail', (select jsonb_agg(d) from unnest(v_detail) d where btrim(d) <> ''),
      'qty', 1, 'rate', (v_plan->>'rate')::numeric);

    -- A dearer platform in a Meta-rate place adds the difference.
    foreach v_p in array v_in loop
      select (s->>'rate')::numeric, s->>'slug' into v_fee, v_k from jsonb_array_elements(v_svc) s
       where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = v_p limit 1;
      if v_fee > v_meta then
        v_lines := v_lines || jsonb_build_object('slug', v_k, 'kind', 'platform_in', 'basis', 'month',
          'label', (v_names->>v_p) || ' within the plan', 'detail', '[]'::jsonb, 'qty', 1, 'rate', v_fee - v_meta);
      end if;
    end loop;
    foreach v_p in array coalesce(v_plats[v_slots + 1:], '{}') loop
      select (s->>'rate')::numeric, s->>'slug' into v_fee, v_k from jsonb_array_elements(v_svc) s
       where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = v_p limit 1;
      v_lines := v_lines || jsonb_build_object('slug', v_k, 'kind', 'platform', 'basis', 'month',
        'label', 'Additional platform · ' || (v_names->>v_p), 'detail', '[]'::jsonb, 'qty', 1, 'rate', v_fee);
    end loop;

    -- Extra contents, at the plan's whole saving, to the nearest RM 10.
    if jsonb_typeof(p_sel->'extra') = 'object' then
      for v_k in select k from jsonb_object_keys(p_sel->'extra') k order by k loop
        if coalesce(p_sel->'extra'->>v_k, '') !~ '^[0-9]{1,2}$' then return jsonb_build_object('error', 'bad-extra'); end if;
        v_q := (p_sel->'extra'->>v_k)::int;
        continue when v_q = 0;
        v_s := public.quote_svc(p_snap, v_k);
        if v_s is null or v_s->'spec'->>'role' is distinct from 'content' or v_s->>'rate' is null then
          return jsonb_build_object('error', 'bad-extra');
        end if;
        v_lines := v_lines || jsonb_build_object('slug', v_k, 'kind', 'extra', 'basis', 'month',
          'label', 'Additional ' || lower(left(v_s->>'name', 1)) || substr(v_s->>'name', 2),
          'detail', '[]'::jsonb, 'qty', v_q,
          'rate', round((v_s->>'rate')::numeric * v_factor / 10) * 10);
        v_tot := v_tot + v_q;
      end loop;
    end if;
    v_tot := v_tot + v_contents;

    -- Translation, a content for each language after the first.
    select coalesce(array_agg(l order by array_position(array['en', 'zh', 'ms'], l)), '{}') into v_langs
      from (select distinct l from jsonb_array_elements_text(coalesce(p_sel->'langs', '[]'::jsonb)) l
             where l in ('en', 'zh', 'ms')) z;
    if coalesce((p_sel->>'translate')::boolean, false) and array_length(v_langs, 1) > 1 then
      v_s := (select s from jsonb_array_elements(v_svc) s where s->'spec'->>'role' = 'language'
               and coalesce((s->>'active')::boolean, true) limit 1);
      if v_s is null then return jsonb_build_object('error', 'no-translation'); end if;
      foreach v_l in array v_langs[2:] loop
        v_lines := v_lines || jsonb_build_object('slug', v_s->>'slug', 'kind', 'translation', 'basis', 'month',
          'label', 'Translation into ' || (v_lname->>v_l) || ', per content', 'detail', '[]'::jsonb,
          'qty', v_tot, 'rate', (v_s->>'rate')::numeric);
      end loop;
    end if;
  else
    -- No plan: each platform managed at its own fee.
    foreach v_p in array v_plats loop
      select (s->>'rate')::numeric, s->>'slug' into v_fee, v_k from jsonb_array_elements(v_svc) s
       where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = v_p limit 1;
      v_lines := v_lines || jsonb_build_object('slug', v_k, 'kind', 'platform', 'basis', 'month',
        'label', 'Account management · ' || (v_names->>v_p), 'detail', '[]'::jsonb, 'qty', 1, 'rate', v_fee);
    end loop;
  end if;

  -- The advertising budget past what the plan covers.
  if coalesce(p_sel->>'budget', '0') !~ '^-?[0-9]{1,7}$' then return jsonb_build_object('error', 'bad-budget'); end if;
  v_budget := (coalesce(p_sel->>'budget', '0'))::numeric;
  if v_budget < 0 then
    v_req := v_req || 'budget'::text;
  elsif v_budget > v_cover then
    v_cost := public.quote_ads_cost(p_snap, v_budget);
    if v_cost is null then
      v_req := v_req || 'budget'::text;
    elsif v_cover > 0 then
      v_lines := v_lines || jsonb_build_object('slug', null, 'kind', 'ads', 'basis', 'month',
        'label', 'Advertising budget coverage, up to ' || public.quote_rm(v_budget), 'detail', '[]'::jsonb,
        'qty', 1, 'rate', v_cost - public.quote_ads_cost(p_snap, v_cover));
    else
      select s into v_s from jsonb_array_elements(v_svc) s
       where s->'spec'->>'role' = 'ads' and coalesce((s->>'active')::boolean, true)
       order by ((s->'spec'->>'budget')::numeric >= v_budget) desc,
                case when (s->'spec'->>'budget')::numeric >= v_budget then (s->'spec'->>'budget')::numeric
                     else -(s->'spec'->>'budget')::numeric end
       limit 1;
      v_from := least(v_budget, (v_s->'spec'->>'budget')::numeric);
      v_lines := v_lines || jsonb_build_object('slug', v_s->>'slug', 'kind', 'ads', 'basis', 'month',
        'label', 'Meta advertising · advertising budget up to ' || public.quote_rm((v_s->'spec'->>'budget')::numeric),
        'detail', coalesce((select jsonb_agg(d) from unnest(string_to_array(coalesce(v_text->>'ads_included', ''), E'\n')) d
                             where btrim(d) <> ''), '[]'::jsonb),
        'qty', 1, 'rate', (v_s->>'rate')::numeric);
      if v_budget > (v_s->'spec'->>'budget')::numeric then
        v_lines := v_lines || jsonb_build_object('slug', null, 'kind', 'ads', 'basis', 'month',
          'label', 'Advertising budget coverage, up to ' || public.quote_rm(v_budget), 'detail', '[]'::jsonb,
          'qty', 1, 'rate', v_cost - (v_s->>'rate')::numeric);
      end if;
    end if;
  end if;

  -- One-off items; a KOL campaign and a custom KOC list are quoted on request.
  if jsonb_typeof(p_sel->'once') = 'array' then
    for v_x in select * from jsonb_array_elements(p_sel->'once') loop
      if coalesce(v_x->>'qty', '') !~ '^[0-9]{1,3}$' or (v_x->>'qty')::int < 1 then
        return jsonb_build_object('error', 'bad-once');
      end if;
      v_s := public.quote_svc(p_snap, v_x->>'slug');
      if v_s is null or coalesce(v_s->'spec'->>'role', '') not in ('content', 'verify', 'koc', 'kol', 'addon') then
        return jsonb_build_object('error', 'bad-once');
      end if;
      if v_s->>'rate' is null then v_req := v_req || (v_s->>'name')::text; continue; end if;
      v_lines := v_lines || jsonb_build_object('slug', v_s->>'slug', 'kind', v_s->'spec'->>'role', 'basis', 'once',
        'label', v_s->>'name', 'detail', '[]'::jsonb, 'qty', (v_x->>'qty')::int, 'rate', (v_s->>'rate')::numeric);
    end loop;
  end if;

  if jsonb_array_length(v_lines) = 0 and array_length(v_req, 1) is null then
    return jsonb_build_object('error', 'empty');
  end if;

  select coalesce(sum((l->>'qty')::numeric * (l->>'rate')::numeric) filter (where l->>'basis' = 'month'), 0),
         coalesce(sum((l->>'qty')::numeric * (l->>'rate')::numeric) filter (where l->>'basis' = 'once'), 0),
         bool_or(l->>'basis' = 'month')
    into v_sub, v_once, v_month
    from jsonb_array_elements(v_lines) l;
  v_month := coalesce(v_month, false);
  v_pct := case when not v_month then 0
                when v_term <= 3 then coalesce((v_set->>'term_1_3')::numeric, 0)
                when v_term <= 5 then coalesce((v_set->>'term_4_5')::numeric, 0)
                when v_term <= 11 then coalesce((v_set->>'term_6_11')::numeric, 0)
                when v_term <= 23 then coalesce((v_set->>'term_12_23')::numeric, 0)
                else coalesce((v_set->>'term_24')::numeric, 0) end;
  v_off := round(v_sub * v_pct / 100, 2);
  v_excl := v_sub + v_off;
  v_sst := round(v_excl * v_sst_pct / 100, 2);
  v_osst := round(v_once * v_sst_pct / 100, 2);

  return jsonb_build_object(
    'lines', (select jsonb_agg(l || jsonb_build_object('amount', round((l->>'qty')::numeric * (l->>'rate')::numeric, 2)))
                from jsonb_array_elements(v_lines) l),
    'on_request', to_jsonb(v_req),
    'extra_rates', v_hint,
    'totals', jsonb_build_object(
      'term', v_term, 'term_pct', v_pct, 'sst_pct', v_sst_pct, 'budget', greatest(v_budget, 0),
      'month', case when v_month then jsonb_build_object('subtotal', v_sub, 'term', v_off, 'excl', v_excl,
                 'sst', v_sst, 'incl', v_excl + v_sst) end,
      'once', case when v_once > 0 then jsonb_build_object('subtotal', v_once, 'sst', v_osst, 'incl', v_once + v_osst) end,
      'commitment', case when v_month then (v_excl + v_sst) * v_term else 0 end + v_once + v_osst));
end $$;
revoke all on function public.quote_price(jsonb, jsonb) from public, anon, authenticated;

/* What the website offers, from the live version, with no rate. */
create or replace function public.quote_catalogue()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_card jsonb := public.quote_card();
  v_svc jsonb;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_svc := coalesce(v_card->'snapshot'->'services', '[]'::jsonb);
  return jsonb_build_object(
    'version', v_card->>'version',
    'valid_days', coalesce(public.app_setting('quote_valid_days', v_today), 30)::int,
    'plans', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', s->>'slug', 'plan', s->'spec'->>'plan', 'ads', coalesce((s->'spec'->>'ads')::boolean, false),
        'platforms', (s->'spec'->>'platforms')::int, 'contents', (s->'spec'->>'contents')::int,
        'mix', s->'spec'->'mix', 'ad_budget', (s->'spec'->>'ad_budget')::numeric, 'best_for', s->'spec'->>'best_for')
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
    'verify', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name'))
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'verify' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'koc', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name',
        'creators', (s->'spec'->>'creators')::int) order by (s->'spec'->>'creators')::int nulls last)
      from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'koc' and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
    'kol', (select s->>'slug' from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'kol' and coalesce((s->>'active')::boolean, true) limit 1),
    'translation', exists (select 1 from jsonb_array_elements(v_svc) s
     where s->'spec'->>'role' = 'language' and coalesce((s->>'active')::boolean, true)));
end $$;
revoke all on function public.quote_catalogue() from public;
grant execute on function public.quote_catalogue() to anon, authenticated;

/* The colleagues told about a website quotation: whoever works leads (or an
   admin), active, never a system account. */
create or replace function public.quote_tell(p_client uuid, p_kind text, p_title text, p_body text, p_key text)
returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, p_kind, p_title, p_body, p_client, p_kind || ':' || p_key || ':' || m.id
    from public.team_members m
   where m.active and not coalesce(m.system, false)
     and (m.is_admin or m.role = 'admin'
          or public.level_rank(coalesce(m.access ->> 'clients.leads', m.access ->> 'clients')) >= 2)
  on conflict (dedupe_key) do nothing;
end $$;
revoke all on function public.quote_tell(uuid, text, text, text, text) from public, anon, authenticated;

/* A quotation made on the website, for the lead it belongs to. Called by
   the quote-request function with the service role, after Cloudflare's
   check. */
create or replace function public.quote_website_create(p_sel jsonb, p_contact jsonb, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name  text := btrim(regexp_replace(coalesce(p_contact->>'name', ''), '\s+', ' ', 'g'));
  v_email text := lower(btrim(coalesce(p_contact->>'email', '')));
  v_wa    text := regexp_replace(coalesce(p_contact->>'whatsapp', ''), '[^0-9]', '', 'g');
  v_brand text := btrim(regexp_replace(coalesce(p_contact->>'brand', ''), '\s+', ' ', 'g'));
  v_ind   text := nullif(btrim(coalesce(p_contact->>'industry', '')), '');
  v_lang  text := case when p_contact->>'lang' = 'zh' then 'zh' else 'en' end;
  v_idem  text := nullif(btrim(coalesce(p_idem, '')), '');
  v_q     public.quotations;
  v_c     public.clients;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_r     jsonb;
  v_new   boolean := false;
begin
  if v_idem is null or length(v_idem) > 80 then return jsonb_build_object('error', 'bad-request'); end if;
  if v_wa ~ '^0[1-9]' then v_wa := '6' || v_wa; end if;   -- 012… is Malaysia's 6012…
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
  if coalesce((p_contact->>'consent')::boolean, false) is not true then return jsonb_build_object('error', 'consent'); end if;
  if (select count(*) from public.quotations q
       where q.source = 'website' and q.issued_at > now() - interval '1 day'
         and (lower(q.contact->>'email') = v_email or q.contact->>'whatsapp' = '+' || v_wa)) >= 5 then
    return jsonb_build_object('error', 'limit');
  end if;

  -- A lead this person already is, else a new one.
  select c.* into v_c from public.clients c
    join public.client_contacts k on k.client_id = c.id
   where c.stage in ('lead', 'contacted', 'proposal')
     and k.archived_at is null
     and (lower(k.email) = v_email or regexp_replace(coalesce(k.whatsapp, ''), '[^0-9]', '', 'g') = v_wa)
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
    insert into public.client_contacts (client_id, name, email, whatsapp, lang, is_primary)
    values (v_c.id, v_name, v_email, '+' || v_wa, v_lang, true);
    insert into public.activity_log (actor, action, subject, detail)
    values ('Website', 'client.added', v_c.name, 'Website · ' || v_name);
    v_new := true;
  end if;

  v_r := public.quotation_make(v_c.id, p_sel, v_idem, 'website', null,
    jsonb_build_object('name', v_name, 'email', v_email, 'whatsapp', '+' || v_wa, 'lang', v_lang));
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

/* The quotation a website key opens, as it was kept; never its contact or
   billing. */
create or replace function public.quote_website_read(p_key text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object('ref', q.ref, 'brand', q.brand, 'version', q.version,
      'issued_at', q.issued_at, 'valid_until', q.valid_until, 'lines', q.lines, 'totals', q.totals,
      'selection', q.selection, 'attention', q.contact->>'name',
      'status', q.status, 'requested', q.requested_at is not null,
      'today', (now() at time zone 'Asia/Kuala_Lumpur')::date)
      from public.quotations q
     where p_key ~ '^[a-z0-9]{8}$' and q.access_key = p_key and q.source = 'website' and q.removed_at is null),
    jsonb_build_object('error', 'not-found'))
$$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

/* Proceed: the billing details and the request for the Letter of Offer. */
create or replace function public.quote_website_request(p_key text, p_billing jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_q    public.quotations;
  v_reg  text := upper(btrim(regexp_replace(coalesce(p_billing->>'registered_name', ''), '\s+', ' ', 'g')));
  v_brn  text := regexp_replace(coalesce(p_billing->>'brn', ''), '[^0-9]', '', 'g');
  v_addr text := btrim(coalesce(p_billing->>'address', ''));
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into v_q from public.quotations q
   where q.access_key = p_key and q.source = 'website' and q.removed_at is null for update;
  if v_q.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_q.requested_at is not null then return jsonb_build_object('ok', true, 'again', true); end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if v_q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  if length(v_reg) < 3 or length(v_reg) > 160 or v_brn !~ '^[0-9]{12}$' or length(v_addr) < 10 or length(v_addr) > 400 then
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

/* The billing details a prospect gave are Clients: Billing's, as a client's
   own are: the column is withheld from the table and read through
   `quotation_billing` (Clients: Billing at View, client scope). */
revoke select on table public.quotations from anon, authenticated;
grant select (id, ref, client_id, brand, version, version_id, selection, lines, totals, status, source,
              issued_at, valid_until, made_by, contact, access_key, requested_at, idem, removed_at, removed_by)
  on table public.quotations to authenticated;

create or replace function public.quotation_billing(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_q public.quotations;
begin
  if not public.is_team() or not public.allowed('clients.billing', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  return coalesce(v_q.billing, '{}'::jsonb);
end $$;
revoke all on function public.quotation_billing(uuid) from public, anon;
grant execute on function public.quotation_billing(uuid) to authenticated;

-- A website quotation's notice opens the lead's Services.
create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.link is not null then new.link
         when new.task_id is not null then '/admin/?s=work&open=' || new.task_id::text
         when new.report_id is not null then '/admin/?s=reports&report=' || new.report_id::text
         when new.script_id is not null then '/admin/?s=scripts&script=' || new.script_id::text
         when new.client_id is not null then '/admin/?s=clients&client=' || new.client_id::text || '&tab=services'
         when new.kind in ('client_left', 'tasks.empty', 'tasks.nudge') then '/admin/?s=work'
         when new.kind = 'hr.letter' then '/admin/?s=mine&view=letters'
         when new.kind = 'perf.disputed' then '/admin/?s=team&tab=performance'
         when new.kind = 'perf.reflect' then '/admin/?s=mine&view=reflection'
         when new.kind = 'perf.initiative' then '/admin/?s=mine&view=initiatives'
         when new.kind like 'health.%' then '/admin/?s=mine&view=health'
         when new.kind like 'perf.%' then '/admin/?s=mine'
         else '/admin/' end,
    case when new.task_id is not null then 'task-' || new.task_id::text
         when new.report_id is not null then 'report-' || new.report_id::text
         when new.script_id is not null then 'script-' || new.script_id::text
         when new.client_id is not null then 'client-' || new.client_id::text
         when new.kind = 'hr.letter' then 'hr-letter'
         when new.kind in ('perf.remind', 'perf.reflect', 'health.remind') then 'my-hr'
         when new.kind = 'tasks.empty' then 'tasks-empty'
         when new.kind = 'tasks.nudge' then 'tasks-nudge'
         when new.kind = 'outstation' then 'outstation'
         else null end);
  return new;
exception when others then
  return new;
end $$;

-- END OF QUOTATION WEBSITE --------------------------------------------------

select public.functions_tidy();
