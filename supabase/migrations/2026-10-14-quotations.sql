-- ===========================================================================
-- QUOTATIONS — a client's quotation, priced by the database from the live
-- rate card, kept as it was sent (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-13: a quotation once sent "we should honor that";
-- "they can have multiple quotations, depends on which one they will
-- finally proceed")
--   A quotation is made from a selection (a plan, its platforms, extra
--   contents, languages, an advertising budget, a term, one-off items) and
--   priced by one calculation, `quote_price`, from the version of the rate
--   card that is live (`rate_card_current`). It is kept whole as sent: its
--   lines, its totals, the version it was priced from and the day it is
--   valid until (`quote_valid_days`, 30, a Business setting). It is never
--   edited: Make a copy prices the same selection again, and a client may
--   hold any number. Its lines are its own; a client's Services hold only
--   real lines, made from the chosen quotation by Issue Letter of Offer
--   (`quotation_offer`, To quote, each carrying `quotation_id`).
--
-- THE CALCULATION (Services, the approved pricing board)
--   * A plan's platforms: those it counts are in its fee, a dearer one in
--     place of a Meta-rate platform adds the difference; any more are
--     Additional platforms at their own fee.
--   * Extra contents on a plan: the plan's whole saving (its fee against
--     everything in it at Ala Carte, on its fuller option) on the content's
--     own rate, to the nearest RM 10.
--   * Languages: shared across the contents at no charge; Translate every
--     content charges the translation rate a content (the plan's and the
--     extras) for each language after the first.
--   * An advertising budget past what the plan covers: Meta advertising up
--     to its largest budget, then the coverage line to the budget asked;
--     past the largest coverage it is on request.
--   * The term's percentage (`term_*`, as the version holds them) on the
--     monthly subtotal; SST (`sst_pct`, the version's) on what remains.
--   * One-off items (content production, verification, KOC packages) are
--     their own subtotal, untouched by the term.
--
-- ORDER
--   This file, then the pages. A page from before reads nothing here.
--
-- ROLLBACK
--   The pages from before. The table, the column and the functions may
--   stay: nothing from before reads them.
-- ===========================================================================

create table if not exists public.quotations (
  id          uuid primary key default gen_random_uuid(),
  ref         text not null unique,
  client_id   uuid not null references public.clients(id) on delete cascade,
  brand       text not null,
  version     text not null,
  version_id  uuid,
  selection   jsonb not null,
  lines       jsonb not null,
  totals      jsonb not null,
  status      text not null default 'sent' check (status in ('sent', 'requested', 'not_proceeding')),
  source      text not null default 'console' check (source in ('console', 'website')),
  issued_at   timestamptz not null default now(),
  valid_until date not null,
  made_by     text,
  contact     jsonb,
  access_key  text unique,
  billing     jsonb,
  requested_at timestamptz,
  idem        text unique,
  removed_at  timestamptz,
  removed_by  text
);
create index if not exists quotations_client_idx on public.quotations (client_id, issued_at desc);
alter table public.quotations enable row level security;
revoke all on table public.quotations from public, anon;
-- Column by column, so a run of this file never hands back `billing`, which
-- the QUOTATION WEBSITE section withholds (audit I10, 2026-10-15).
revoke select on table public.quotations from authenticated;
grant select (id, ref, client_id, brand, version, version_id, selection, lines, totals, status, source,
              issued_at, valid_until, made_by, contact, access_key, requested_at, idem, removed_at, removed_by)
  on table public.quotations to authenticated;
do $p$
begin
  if not exists (select 1 from pg_policies where tablename = 'quotations' and policyname = 'quotations_read') then
    create policy quotations_read on public.quotations for select to authenticated
      using (public.allowed('clients.services', 'view'));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'quotations' and policyname = 'client_scope') then
    create policy client_scope on public.quotations as restrictive for select to authenticated
      using ((select public.client_scope_free('view')) or public.client_scope_ok('client', client_id, 'view'));
  end if;
end $p$;
create or replace trigger client_scope_guard before insert or update on public.quotations
  for each row execute function public.client_scope_guard('client', 'client_id');

alter table public.client_services add column if not exists quotation_id uuid references public.quotations(id);
create index if not exists client_services_quotation_idx on public.client_services (quotation_id);

insert into public.app_settings (key, from_date, value)
select 'quote_valid_days', date '2023-08-14', 30
 where not exists (select 1 from public.app_settings s where s.key = 'quote_valid_days');

-- One line of the version's price list, by slug (active lines only).
create or replace function public.quote_svc(p_snap jsonb, p_slug text)
returns jsonb
language sql immutable set search_path = public as $$
  select s from jsonb_array_elements(coalesce(p_snap->'services', '[]'::jsonb)) s
   where s->>'slug' = p_slug and coalesce((s->>'active')::boolean, true)
   limit 1
$$;
revoke all on function public.quote_svc(jsonb, text) from public, anon, authenticated;

-- What the version charges to manage advertising up to a budget from
-- nothing: Meta advertising up to its largest budget, then the coverage
-- line to the budget asked. Null past the largest coverage (on request).
create or replace function public.quote_ads_cost(p_snap jsonb, p_budget numeric)
returns numeric
language plpgsql immutable set search_path = public as $$
declare
  v_svc jsonb := coalesce(p_snap->'services', '[]'::jsonb);
  v_top numeric; v_top_rate numeric; v_rate numeric;
begin
  if coalesce(p_budget, 0) <= 0 then return 0; end if;
  select (s->>'rate')::numeric into v_rate from jsonb_array_elements(v_svc) s
   where s->'spec'->>'role' = 'ads' and coalesce((s->>'active')::boolean, true)
     and (s->'spec'->>'budget')::numeric >= p_budget
   order by (s->'spec'->>'budget')::numeric limit 1;
  if v_rate is not null then return v_rate; end if;
  select (s->'spec'->>'budget')::numeric, (s->>'rate')::numeric into v_top, v_top_rate
    from jsonb_array_elements(v_svc) s
   where s->'spec'->>'role' = 'ads' and coalesce((s->>'active')::boolean, true)
   order by (s->'spec'->>'budget')::numeric desc limit 1;
  select (s->>'rate')::numeric into v_rate from jsonb_array_elements(v_svc) s
   where s->'spec'->>'role' = 'booster' and coalesce((s->>'active')::boolean, true)
     and (s->'spec'->>'budget')::numeric >= p_budget
   order by (s->'spec'->>'budget')::numeric limit 1;
  if v_rate is null or v_top_rate is null then return null; end if;
  return v_top_rate + v_rate;
end $$;
revoke all on function public.quote_ads_cost(jsonb, numeric) from public, anon, authenticated;

create or replace function public.quote_rm(p numeric)
returns text
language sql immutable set search_path = public as $$
  select 'RM ' || to_char(p, 'FM999,999,990')
$$;
revoke all on function public.quote_rm(numeric) from public, anon, authenticated;

/* The one calculation. p_sel:
     plan       a plan's slug, or null
     mix        which of the plan's content options (0 by default)
     platforms  meta, tiktok, rednote, linkedin
     extra      { content slug: a month's count } on a plan
     langs      en, zh, ms; translate true charges every content each
                language after the first
     budget     the advertising budget a month asked for (0 for none)
     term       months (a plan needs 6 or more)
     once       [{ slug, qty }] one-off items
   Answers { lines, totals, on_request } or { error }. */
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

  -- One-off items.
  if jsonb_typeof(p_sel->'once') = 'array' then
    for v_x in select * from jsonb_array_elements(p_sel->'once') loop
      if coalesce(v_x->>'qty', '') !~ '^[0-9]{1,3}$' or (v_x->>'qty')::int < 1 then
        return jsonb_build_object('error', 'bad-once');
      end if;
      v_s := public.quote_svc(p_snap, v_x->>'slug');
      if v_s is null or coalesce(v_s->'spec'->>'role', '') not in ('content', 'verify', 'koc', 'addon') then
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

-- The reference: ADP/QT{YYMM}-{Z}{NN}, Z the brand's first letter (X where
-- it starts with none), NN counted a letter a month.
create or replace function public.quote_ref(p_brand text, p_at timestamptz)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  v_z text := upper(left(regexp_replace(coalesce(p_brand, ''), '[^A-Za-z]', '', 'g'), 1));
  v_head text;
  v_n int;
begin
  if v_z = '' then v_z := 'X'; end if;
  v_head := 'ADP/QT' || to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'YYMM') || '-' || v_z;
  perform pg_advisory_xact_lock(hashtext('quote_ref:' || v_head));
  select coalesce(max(substr(q.ref, length(v_head) + 1)::int), 0) + 1 into v_n
    from public.quotations q
   where q.ref like v_head || '%' and substr(q.ref, length(v_head) + 1) ~ '^[0-9]+$';
  return v_head || lpad(v_n::text, 2, '0');
end $$;
revoke all on function public.quote_ref(text, timestamptz) from public, anon, authenticated;

-- The live version, for whoever prices (the team, or the website's function).
create or replace function public.quote_card()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', v.id, 'version', v.version, 'snapshot', v.snapshot)
    from public.rate_card_versions v
   order by v.published_at desc
   limit 1
$$;
revoke all on function public.quote_card() from public, anon, authenticated;

-- Priced as it would be sent, read only (Build quote, as it is ticked).
create or replace function public.quote_preview(p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_card jsonb := public.quote_card();
begin
  if not public.is_team() or not public.allowed('clients.services', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  return public.quote_price(v_card->'snapshot', p_sel) ||
         jsonb_build_object('version', v_card->>'version');
end $$;
revoke all on function public.quote_preview(jsonb) from public, anon;
grant execute on function public.quote_preview(jsonb) to authenticated;

-- Makes and keeps one quotation for a client. The same key twice is the
-- same quotation.
create or replace function public.quotation_make(p_client uuid, p_sel jsonb, p_idem text, p_source text,
                                                 p_by text, p_contact jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_c public.clients;
  v_card jsonb := public.quote_card();
  v_p jsonb;
  v_q public.quotations;
  v_now timestamptz := now();
  v_days int;
begin
  if p_idem is not null then
    select * into v_q from public.quotations q where q.idem = p_idem;
    if v_q.id is not null then return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true); end if;
  end if;
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_p := public.quote_price(v_card->'snapshot', p_sel);
  if v_p ? 'error' then return v_p; end if;
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  insert into public.quotations (ref, client_id, brand, version, version_id, selection, lines, totals, source,
                                 issued_at, valid_until, made_by, contact, idem, access_key)
  values (public.quote_ref(v_c.name, v_now), v_c.id, v_c.name, v_card->>'version', (v_card->>'id')::uuid, p_sel,
          v_p->'lines', v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request'), p_source,
          v_now, (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days, p_by, p_contact, p_idem,
          case when p_source = 'website' then public.new_link_key() end)
  returning * into v_q;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(p_by, 'Website'), 'client.quotation', v_c.name,
          v_q.ref || ' sent · ' || coalesce('Monthly incl. SST RM ' ||
            to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') ||
          ' · rate card v.' || v_q.version);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'key', v_q.access_key);
end $$;
revoke all on function public.quotation_make(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

-- The console's Build quote and Make a copy.
create or replace function public.quotation_create(p_client uuid, p_sel jsonb, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('clients.services', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  return public.quotation_make(p_client, p_sel, nullif(btrim(coalesce(p_idem, '')), ''), 'console', me.name, null);
end $$;
revoke all on function public.quotation_create(uuid, jsonb, text) from public, anon;
grant execute on function public.quotation_create(uuid, jsonb, text) to authenticated;

-- Not proceeding, and back; Remove, and back (the way back never asks).
create or replace function public.quotation_set(p_id uuid, p_what text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_word text;
begin
  if me.id is null or not public.allowed('clients.services', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if p_what = 'not_proceeding' then
    update public.quotations set status = 'not_proceeding' where id = p_id; v_word := ' marked Not proceeding';
  elsif p_what = 'proceeding' then
    update public.quotations set status = case when requested_at is not null then 'requested' else 'sent' end
     where id = p_id;
    v_word := ' restored';
  elsif p_what = 'remove' then
    update public.quotations set removed_at = now(), removed_by = me.name where id = p_id; v_word := ' removed';
  elsif p_what = 'restore' then
    update public.quotations set removed_at = null, removed_by = null where id = p_id; v_word := ' restored';
  else
    return jsonb_build_object('error', 'bad-what');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || v_word);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_set(uuid, text) from public, anon;
grant execute on function public.quotation_set(uuid, text) to authenticated;

-- Issue Letter of Offer: the chosen quotation's lines become the client's
-- To quote lines, priced as quoted, once (a second press answers the same
-- lines).
create or replace function public.quotation_offer(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_l jsonb;
  v_ids uuid[] := '{}';
  v_id uuid;
begin
  if me.id is null or not public.allowed('clients.services', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or v_q.removed_at is not null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  select coalesce(array_agg(s.id order by s.created_at), '{}') into v_ids
    from public.client_services s where s.quotation_id = v_q.id and s.archived_at is null;
  if array_length(v_ids, 1) is not null then return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids), 'again', true); end if;
  for v_l in select * from jsonb_array_elements(v_q.lines) loop
    insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                        tenure, term_adjust, term_pct, detail, quotation_id)
    values (v_q.client_id,
            case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
            v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
            case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'quoted',
            'Quotation ' || v_q.ref,
            case when v_l->>'basis' = 'month' then (v_q.totals->>'term')::int else 1 end,
            v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (v_q.totals->>'term_pct')::numeric else 0 end,
            nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
            v_q.id)
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || ' · ' || array_length(v_ids, 1) || ' lines To quote for the Letter of Offer');
  return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids));
end $$;
revoke all on function public.quotation_offer(uuid) from public, anon;
grant execute on function public.quotation_offer(uuid) to authenticated;

-- The validity is a Business setting (Tax and terms).
create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days', 'quote_valid_days'];
  v_moved text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, 2) <> v_v
       or (v_k = 'lead_followup_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'proposal_followup_days' and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k = 'meta_checks' and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'quote_valid_days' and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v))) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      insert into public.app_settings (key, from_date, value, set_by, set_at)
      values (v_k, p_from, v_v, v_me.id, now())
      on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      v_name := case v_k when 'lead_followup_hours' then 'A lead waits' when 'proposal_followup_days' then 'A proposal waits'
        when 'sst_pct' then 'SST' when 'term_1_3' then '1 to 3 months' when 'term_4_5' then '4 and 5 months'
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 23 months' when 'term_24' then '24 months and more'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input, a million tokens'
        when 'ai_price_out' then 'AI output, a million tokens' when 'ai_price_search' then 'AI web searches, a thousand' when 'meta_checks' then 'Meta checks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'quote_valid_days' then 'Quotation validity' else 'Report due' end;
      v_unit := case when v_k in ('lead_followup_hours', 'task_remind_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'quote_valid_days') then ' days'
        else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || case when v_k = 'meta_checks' then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k = 'meta_checks' then '' else case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_was, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end || ' → ' ||
              case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end ||
              ' · from ' || public.register_day(p_from) end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

-- A quotation's steps are filed under Clients.
create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.file_deleted', 'campaign.file_hidden',
                    'campaign.file_shown', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.whatsapp', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.quotation', 'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_deleted', 'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('wa.sent', 'wa.template') then 'whatsapp'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished') then 'reports'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'review.unconfirmed',
                    'set.created', 'set.deleted', 'set.month', 'set.published', 'set.renamed',
                    'set.task_linked', 'set.task_unlinked',
                    'set.withdrawn') then 'review'
    when action in ('script.approved', 'script.changes', 'script.created', 'script.deleted',
                    'script.link', 'script.saved', 'script.shared', 'script.shot',
                    'script.unshared') then 'scripts'
    when action in ('handbook.added', 'handbook.archived', 'handbook.deleted',
                    'handbook.edited', 'handbook.restored', 'handbook.version') then 'handbook'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on', 'service.published') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

-- END OF QUOTATIONS ---------------------------------------------------------

select public.functions_tidy();
