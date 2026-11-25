-- ===========================================================================
-- QUOTATION PREFLIGHT (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25, for /quote/ and a sent quotation's link, "like
-- a concert ticket checkout": before the prospect submits, the page checks
-- what they chose against the live Rate Card and shows anything that
-- changed, so what is submitted is accurate and still offered.
--
-- WHAT CHANGED
--   * `quote_web_changes(p_sel, p_snap)` (internal): the one list of what a
--     website selection holds that the card no longer offers, each as
--     `{kind, slug}`: `plan`, `mix` (the plan's content option), `platform`,
--     `extra` (an additional content piece), `translate`, `term`, `once` (a
--     one-time item, a verification, a creator list or a file).
--   * `quote_website_sel` (restated) asks it for the term and the one-time
--     items (`bad-term`, `bad-once` as before), never a second copy.
--   * `quote_web_check(p_sel, p_seen)` (internal): the page switched off
--     (`off`), the live Rate Card moved on from the version the page read
--     (`version`, only where the page names one), then the list above.
--   * `quote_preflight(p_sel, p_seen, p_key)` (anon): answers `ok` and the
--     `changes`, never a price. Without a key, /quote/'s selection against
--     the live card (`p_seen.version`, the catalogue's). With a key, a sent
--     quotation's changed selection against its own Rate Card, as
--     `quote_change_request` reads it: a refusal of the link as its code
--     (`not-found`, `closed`, `signed`, `expired`, `unsent`, `brands`), a
--     change refused by `quote_change_sel` as its kind, and `price` where
--     the totals the page showed (`p_seen.month`, `p_seen.once`) are no
--     longer the totals. 240 calls an address an hour (`quote_throttle`,
--     `quote_hits`, one row an address), then `limit`.
--   * `quote_website_create` (restated) runs `quote_web_check` before
--     anything is written (`changed` with the list, nothing made) and holds
--     the version it checked: a card published between the check and the
--     quotation undoes the whole request (`changed`). A page served before
--     names no version and is checked on what it chose alone. Its Activity
--     lines read Quotation portal.
--   * `quotations_website_activity` (restated) names the Rate Card version
--     the quotation holds on its Quotation requested line.
--   * `page_name('quote')` reads Quotation portal; `quote_activity` and
--     `quote_proceed` (restated, their actor alone changed) file their
--     lines as Quotation portal, and the Activity record's lines filed as
--     Quotation website are named Quotation portal.
--
-- ORDER: this file (connector), then the pages; then
-- 2026-10-07-function-hygiene.sql again (`quote_preflight` joins
-- `open_to_anon`). Until the pages land, an open tab never calls the
-- preflight and its Submit is checked by the create as above. Until the
-- hygiene file runs again, the grant below stands (functions_tidy, run at
-- the foot, would take anon's away), so it runs straight after. Safe to
-- run twice. Holds no drop or delete.
-- ROLLBACK: run `quote_website_sel` from QUOTE WEBSITE BILINGUAL,
-- `quote_website_create` from ONE-TIME, NEVER ONE-OFF and `page_name` from
-- FEEDBACK PAGE AVAILABLE, `quote_activity` and `quotations_website_activity`
-- from QUOTATION LINK ACTIVITY
-- and `quote_proceed` from its last section again; in the SQL Editor, drop
-- `quote_preflight(jsonb, jsonb, text)`, `quote_web_check(jsonb, text)`,
-- `quote_web_changes(jsonb, jsonb)`, `quote_throttle()` and the table
-- `quote_hits`. The Activity lines renamed keep their new name.
-- ===========================================================================

-- QUOTATION PREFLIGHT ----------------------------------------------------------

create table if not exists public.quote_hits (
  ip   text primary key,
  hour timestamp not null,
  n    int not null default 0
);
alter table public.quote_hits enable row level security;
revoke all on public.quote_hits from public, anon, authenticated;

/* A caller's preflights in the hour, one row an address, started again
   each hour, so nothing grows. */
create or replace function public.quote_throttle()
returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare
  v_ip   text := coalesce(nullif(public.request_ip(), ''), 'none');
  v_hour timestamp := date_trunc('hour', now() at time zone 'Asia/Kuala_Lumpur');
  v_n    int;
begin
  insert into public.quote_hits as h (ip, hour, n) values (v_ip, v_hour, 1)
  on conflict (ip) do update
     set n = case when h.hour < v_hour then 1 else h.n + 1 end, hour = v_hour
  returning n into v_n;
  return v_n <= 240;
end $$;
revoke all on function public.quote_throttle() from public, anon, authenticated;

/* What a website selection holds that the card no longer offers: the one
   list the preflight, the create and quote_website_sel read. */
create or replace function public.quote_web_changes(p_sel jsonb, p_snap jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_out jsonb := '[]'::jsonb;
  v_s   jsonb;
  v_k   text;
  v_o   jsonb;
begin
  if jsonb_typeof(p_sel) is distinct from 'object' then return v_out; end if;
  if nullif(p_sel->>'plan', '') is not null then
    v_s := public.quote_svc(p_snap, p_sel->>'plan');
    if v_s is null or v_s->'spec'->>'role' is distinct from 'plan' or v_s->>'rate' is null then
      v_out := v_out || jsonb_build_object('kind', 'plan', 'slug', p_sel->>'plan');
    elsif coalesce(p_sel->>'mix', '') ~ '^[0-9]{1,2}$'
          and (p_sel->>'mix')::int >= coalesce(jsonb_array_length(case when jsonb_typeof(v_s->'spec'->'mix') = 'array' then v_s->'spec'->'mix' end), 1) then
      v_out := v_out || jsonb_build_object('kind', 'mix', 'slug', p_sel->>'plan');
    end if;
  end if;
  for v_k in select distinct x from jsonb_array_elements_text(
               case when jsonb_typeof(p_sel->'platforms') = 'array' then p_sel->'platforms' else '[]'::jsonb end) x
              where x in ('meta', 'tiktok', 'rednote', 'linkedin') loop
    if not exists (select 1 from jsonb_array_elements(coalesce(p_snap->'services', '[]'::jsonb)) s
                    where s->'spec'->>'role' = 'platform' and s->'spec'->>'platform' = v_k
                      and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)) then
      v_out := v_out || jsonb_build_object('kind', 'platform', 'slug', v_k);
    end if;
  end loop;
  if jsonb_typeof(p_sel->'extra') = 'object' then
    for v_k in select k from jsonb_object_keys(p_sel->'extra') k order by k loop
      continue when coalesce(p_sel->'extra'->>v_k, '0') in ('0', '');
      v_s := public.quote_svc(p_snap, v_k);
      if v_s is null or v_s->'spec'->>'role' is distinct from 'content' or v_s->>'rate' is null then
        v_out := v_out || jsonb_build_object('kind', 'extra', 'slug', v_k);
      end if;
    end loop;
  end if;
  if p_sel->'translate' = 'true'::jsonb
     and not exists (select 1 from jsonb_array_elements(coalesce(p_snap->'services', '[]'::jsonb)) s
                      where s->'spec'->>'role' = 'language' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)) then
    v_out := v_out || jsonb_build_object('kind', 'translate');
  end if;
  -- The website's commitments; 1 is one-time items alone.
  if coalesce(p_sel->>'term', '') !~ '^[0-9]{1,2}$'
     or not ((p_sel->>'term')::int = 1 or (p_sel->>'term')::int = any (public.quote_web_terms())) then
    v_out := v_out || jsonb_build_object('kind', 'term', 'slug', left(coalesce(p_sel->>'term', ''), 4));
  end if;
  for v_o in select * from jsonb_array_elements(case when jsonb_typeof(p_sel->'once') = 'array' then p_sel->'once' else '[]'::jsonb end) loop
    if not coalesce(public.quote_web_once_ok(public.quote_svc(p_snap, v_o->>'slug')), false) then
      v_out := v_out || jsonb_build_object('kind', 'once', 'slug', left(coalesce(v_o->>'slug', ''), 80));
    end if;
  end loop;
  return v_out;
end $$;
revoke all on function public.quote_web_changes(jsonb, jsonb) from public, anon, authenticated;

/* What a website selection may hold, and nothing else: since 2026-11-25
   the prospect may ask for every content piece bilingual, kept only with
   two languages or more, and priced as Translation by the team. Its term
   and one-time items are judged by quote_web_changes (QUOTATION
   PREFLIGHT, 2026-11-25). */
create or replace function public.quote_website_sel(p_sel jsonb, p_snap jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_sel jsonb;
  v_ch  jsonb;
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
  v_ch := public.quote_web_changes(v_sel, p_snap);
  if exists (select 1 from jsonb_array_elements(v_ch) c where c->>'kind' = 'term') then
    return jsonb_build_object('error', 'bad-term');
  end if;
  if exists (select 1 from jsonb_array_elements(v_ch) c where c->>'kind' = 'once') then
    return jsonb_build_object('error', 'bad-once');
  end if;
  return v_sel;
end $$;
revoke all on function public.quote_website_sel(jsonb, jsonb) from public, anon, authenticated;

/* The checks the preflight and the create share: the page switched off,
   the live card moved on from the version the page read, then what the
   selection holds that the card no longer offers. */
create or replace function public.quote_web_check(p_sel jsonb, p_seen text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_card jsonb;
  v_out  jsonb := '[]'::jsonb;
begin
  if public.page_covered('quote') then
    return jsonb_build_object('changes', jsonb_build_array(jsonb_build_object('kind', 'off')));
  end if;
  v_card := public.quote_card();
  if v_card is null then
    return jsonb_build_object('changes', jsonb_build_array(jsonb_build_object('kind', 'off')));
  end if;
  if nullif(btrim(coalesce(p_seen, '')), '') is not null and p_seen is distinct from v_card->>'version' then
    v_out := v_out || jsonb_build_object('kind', 'version');
  end if;
  return jsonb_build_object('changes', v_out || public.quote_web_changes(p_sel, coalesce(v_card->'snapshot', '{}'::jsonb)),
                            'version', v_card->>'version');
end $$;
revoke all on function public.quote_web_check(jsonb, text) from public, anon, authenticated;

/* Before Submit, and before Request these changes: what changed since the
   page read it, never a price. */
create or replace function public.quote_preflight(p_sel jsonb, p_seen jsonb default null, p_key text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_chk jsonb;
  o     jsonb;
  q     public.quotations;
  c     jsonb;
  v_fx  numeric;
  v_sel jsonb;
  v_p   jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not public.quote_throttle() then return jsonb_build_object('error', 'limit'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if p_key is null then
    v_chk := public.quote_web_check(p_sel, case when jsonb_typeof(p_seen) = 'object' then p_seen->>'version' end);
    return jsonb_build_object('ok', jsonb_array_length(v_chk->'changes') = 0, 'changes', v_chk->'changes', 'version', v_chk->'version');
  end if;
  -- A sent quotation's changed selection, as quote_change_request reads it.
  o := public.quote_change_open(p_key);
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid;
  if q.selection ? 'brands' then return jsonb_build_object('error', 'brands'); end if;
  c := public.quote_change_snap(q);
  v_fx := (c->>'fx')::numeric;
  if c is null or v_fx = 0 then return jsonb_build_object('error', 'no-card'); end if;
  v_sel := public.quote_change_sel(q.selection, p_sel, c->'snap');
  if v_sel ? 'error' then
    v_out := v_out || jsonb_build_object('kind', case v_sel->>'error' when 'bad-plan' then 'plan' when 'bad-extra' then 'extra'
                                                   when 'bad-once' then 'once' when 'bad-term' then 'term' else 'selection' end);
  else
    v_p := public.quote_fx_out(public.quote_compose(c->'snap', v_sel, q.source <> 'website'), v_fx);
    if v_p ? 'error' then
      v_out := v_out || jsonb_build_object('kind', 'selection');
    elsif jsonb_typeof(p_seen) = 'object'
          and (coalesce((p_seen->>'month')::numeric, -1) is distinct from coalesce((v_p->'totals'->'month'->>'incl')::numeric, -1)
               or coalesce((p_seen->>'once')::numeric, -1) is distinct from coalesce((v_p->'totals'->'once'->>'incl')::numeric, -1)) then
      v_out := v_out || jsonb_build_object('kind', 'price');
    end if;
  end if;
  return jsonb_build_object('ok', jsonb_array_length(v_out) = 0, 'changes', v_out);
exception when invalid_text_representation then
  return jsonb_build_object('error', 'bad-selection');
end $$;
revoke all on function public.quote_preflight(jsonb, jsonb, text) from public;
grant execute on function public.quote_preflight(jsonb, jsonb, text) to anon, authenticated;

create or replace function public.page_name(p text)
returns text
language sql immutable set search_path = public as $$
  select case p when 'admin' then 'Console' when 'client' then 'Client portal' when 'review' then 'Content Review'
    when 'script' then 'Video Scripts' when 'details' then 'Details form' when 'creators' then 'Creator selection'
    when 'creator' then 'Creator page' when 'quote' then 'Quotation portal' when 'supplier' then 'Supplier form'
    when 'verify' then 'Verify a document' when 'careers' then 'Candidate page' when 'feedback' then 'Feedback form'
    when 'home' then 'Front page' when 'notfound' then 'Page not found' when 'card' then 'Namecards' end
$$;
revoke all on function public.page_name(text) from public, anon, authenticated;

/* A quotation requested on the quotation portal names the Rate Card
   version it was checked and priced on (QUOTATION PREFLIGHT, 2026-11-25). */
create or replace function public.quotations_website_activity()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  c public.clients;
begin
  select * into c from public.clients x where x.id = new.client_id;
  perform public.quote_activity(new, 'quotation.requested',
    new.ref || ' · ' || case when c.created_at >= now() then 'New lead'
                             when c.stage in ('lead', 'contacted', 'proposal') then 'Existing lead'
                             else 'Existing client' end
      || coalesce(' · Rate Card v.' || new.version, ''),
    new.contact);
  return null;
end $$;
revoke all on function public.quotations_website_activity() from public, anon, authenticated;

/* The Activity record's lines by the page read Quotation portal (the user,
   2026-11-25), its own functions' and the ones filed before. */
/* One step on a quotation link, filed under Clients: the client's name its
   subject, the one-line detail, and the line's facts (the reference, who,
   and the visit). */
create or replace function public.quote_activity(p_q public.quotations, p_action text, p_detail text, p_who jsonb)
returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name text;
begin
  select c.name into v_name from public.clients c where c.id = p_q.client_id;
  insert into public.activity_log (actor, action, subject, detail, meta)
  values ('Quotation portal', p_action, coalesce(v_name, p_q.brand), p_detail,
          jsonb_strip_nulls(jsonb_build_object('ref', p_q.ref,
            'name', nullif(btrim(coalesce(p_who->>'salutation', '') || ' ' || coalesce(p_who->>'name', '')), ''),
            'email', nullif(lower(btrim(coalesce(p_who->>'email', ''))), ''))) || public.request_visit());
end $$;
revoke all on function public.quote_activity(public.quotations, text, text, jsonb) from public, anon, authenticated;

create or replace function public.quote_proceed(p_key text, p_start text, p_decider text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w  public.quotations;
  q  public.quotations;
  v_due timestamptz;
  v_words text;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into w from public.quotations x
   where x.access_key = p_key and x.source = 'website' and x.removed_at is null for update;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if w.proceed_at is not null then
    return jsonb_build_object('ok', true, 'again', true, 'at', w.proceed_at, 'due', w.proceed_due);
  end if;
  -- What the prospect sees is the latest revision: its validity and its
  -- state decide (2026-10-26, audit).
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if w.status = 'not_proceeding' or q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'not-sent'); end if;
  if coalesce(p_start, '') not in ('month', 'quarter') or coalesce(p_decider, '') not in ('yes', 'others') then
    return jsonb_build_object('error', 'bad-answer');
  end if;
  if q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  v_due := public.quote_reply_by(now());
  v_words := public.quote_proceed_words(p_start, p_decider);
  update public.quotations
     set proceed_at = now(), proceed_due = v_due, proceed_start = p_start, proceed_decider = p_decider
   where id = w.id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation portal', 'client.quotation', w.brand,
          w.ref || ' · Ready to proceed on the website' ||
          coalesce(' by ' || nullif(btrim(w.contact->>'name'), ''), '') || ' · ' || v_words);
  perform public.quote_tell(w.client_id, 'quote.proceed', 'Ready to proceed · ' || w.brand,
    w.ref || coalesce(' · ' || nullif(btrim(w.contact->>'name'), ''), '') || ' · ' || v_words || ' · contact by ' ||
      public.register_day((v_due at time zone 'Asia/Kuala_Lumpur')::date) || ', ' ||
      lower(to_char(v_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
    w.id::text);
  return jsonb_build_object('ok', true, 'at', now(), 'due', v_due);
end $$;
revoke all on function public.quote_proceed(text, text, text) from public;
grant execute on function public.quote_proceed(text, text, text) to anon, authenticated;

update public.activity_log set actor = 'Quotation portal' where actor = 'Quotation website';

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
    values ('Quotation portal', 'client.added', v_c.name, 'Website · ' || coalesce(v_sal || ' ', '') || v_name);
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
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', 'one-time') || ' · ' || v_name
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
        to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', 'one-time') || ' · ' || v_name
        || coalesce(' · Preferred start date ' || public.register_day(v_on),
                    ' · Starts ' || lower(public.quote_commence_word(v_start)), '')
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

-- END OF QUOTATION PREFLIGHT ---------------------------------------------------

select public.functions_tidy();
