-- ===========================================================================
-- INDUSTRIES — a client's industry is chosen from a list kept in Settings
-- (2026-11-04)
-- ===========================================================================
-- WHY (the user, 2026-11-04: "can do a setting for industry? currently its
-- hardcoded?", then "A": a rename carries onto every client): the nine
-- industries stood typed in three places, the console's pickers, the
-- quotation website and `quote_website_create`'s check.
--
-- WHAT IT ADDS
--   * `industries` (name, name_zh, active, on_website, position): RLS on, no
--     policy, no grant. Seeded once, into an empty table, with the nine the
--     portal offered, F&B and Tech by the names the website gave them
--     (their clients moving with them), their Chinese words the website's,
--     then any other
--     industry a client already holds, set inactive.
--   * `industries_list()`: to the team every industry in its order, with
--     how many clients hold it; to anyone else (the quotation website) the
--     active ones the website offers, their names alone.
--   * `industry_save(p_was, p_name, p_name_zh, p_website)` (Business
--     settings): adds an industry (p_was null, at the list's end) or changes
--     one. A name of 2 to 40 characters, unique in any case (`bad-name`,
--     `taken`), a Chinese name of 40 at most (`bad-name-zh`). A rename
--     carries onto every client holding the old name. Filed `team.changed`
--     under Industries, from and to.
--   * `industry_set_active(p_name, p_on)` (Business settings): an inactive
--     industry is offered to nobody; its clients keep it. Never asks; filed.
--   * `industry_move(p_name, p_up)` (Business settings): one place up or
--     down; the list's order is every picker's.
--   * `quote_website_create` takes an industry the website offers.
--   * Removing one no client holds is the SQL Editor part
--     (2026-11-04-industries-editor.sql).
--
-- ORDER: 2026-10-07-function-hygiene.sql again (its `open_to_anon` now
-- names `industries_list`), this file (connector), the pages, then the SQL
-- Editor part. A page served before reads its own nine and writes one the
-- list holds. Safe to run twice.
--
-- ROLLBACK: run QUOTATION WEBSITE COMMENCE's quote_website_create again;
-- the table and its functions are then unused.
-- ===========================================================================

create table if not exists public.industries (
  name text primary key check (length(btrim(name)) between 2 and 40),
  name_zh text check (name_zh is null or length(name_zh) <= 40),
  active boolean not null default true,
  on_website boolean not null default true,
  position int not null default 100,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.industries enable row level security;
revoke all on table public.industries from public, anon, authenticated;
create unique index if not exists industries_name_idx on public.industries (lower(name));

do $$
begin
  if exists (select 1 from public.industries) then return; end if;
  insert into public.industries (name, name_zh, position) values
    ('Property', '房地产', 1), ('Food and beverage', '餐饮', 2), ('Retail', '零售', 3), ('Wellness', '健康养生', 4),
    ('Lifestyle', '生活方式', 5), ('Automotive', '汽车', 6), ('Technology', '科技', 7), ('Education', '教育', 8),
    ('Other', '其他', 9);
  -- The website read F&B and Tech in full; the list takes those names, and
  -- the clients holding the short ones move with them, as a rename does.
  update public.clients c set industry = case c.industry when 'F&B' then 'Food and beverage' else 'Technology' end
   where c.industry in ('F&B', 'Tech');
  insert into public.industries (name, active, on_website, position)
  select distinct btrim(c.industry), false, false, 50
    from public.clients c
   where length(btrim(coalesce(c.industry, ''))) between 2 and 40
     and not exists (select 1 from public.industries i where lower(i.name) = lower(btrim(c.industry)))
  on conflict do nothing;
end $$;

/* Every industry for the team; the website's for anyone else. */
create or replace function public.industries_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.is_team() then
    return coalesce((select jsonb_agg(jsonb_build_object('name', i.name, 'name_zh', i.name_zh, 'active', i.active,
        'website', i.on_website, 'clients', (select count(*)::int from public.clients c where c.industry = i.name))
        order by i.position, lower(i.name))
      from public.industries i), '[]'::jsonb);
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('name', i.name, 'name_zh', i.name_zh) order by i.position, lower(i.name))
    from public.industries i where i.active and i.on_website), '[]'::jsonb);
end $$;
revoke all on function public.industries_list() from public;
grant execute on function public.industries_list() to anon, authenticated;

create or replace function public.industry_save(p_was text, p_name text, p_name_zh text, p_website boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_zh   text := nullif(btrim(regexp_replace(coalesce(p_name_zh, ''), '\s+', ' ', 'g')), '');
  v_was  public.industries;
  v_n    int := 0;
  v_moved text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_name) < 2 or length(v_name) > 40 then return jsonb_build_object('error', 'bad-name'); end if;
  if v_zh is not null and length(v_zh) > 40 then return jsonb_build_object('error', 'bad-name-zh'); end if;
  perform pg_advisory_xact_lock(hashtextextended('industries', 0));
  if p_was is not null then
    select * into v_was from public.industries i where i.name = p_was for update;
    if v_was.name is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if exists (select 1 from public.industries i where lower(i.name) = lower(v_name) and i.name is distinct from p_was) then
    return jsonb_build_object('error', 'taken');
  end if;
  if v_was.name is null then
    insert into public.industries (name, name_zh, on_website, position, updated_by)
    values (v_name, v_zh, coalesce(p_website, true),
            coalesce((select max(i.position) from public.industries i), 0) + 1, me.id);
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Industries', 'Added: ' || v_name);
    return jsonb_build_object('ok', true, 'name', v_name);
  end if;
  v_moved := array_remove(array[
    case when v_was.name <> v_name then 'Name: ' || v_was.name || ' → ' || v_name end,
    case when v_was.name_zh is distinct from v_zh then 'Chinese name: ' || coalesce(v_was.name_zh, 'not set') || ' → ' || coalesce(v_zh, 'not set') end,
    case when v_was.on_website is distinct from coalesce(p_website, v_was.on_website)
         then 'On the quotation website: ' || case when v_was.on_website then 'on → off' else 'off → on' end end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true, 'name', v_name, 'clients', 0); end if;
  update public.industries i set name = v_name, name_zh = v_zh, on_website = coalesce(p_website, i.on_website),
         updated_at = now(), updated_by = me.id
   where i.name = v_was.name;
  -- A rename carries onto every client holding the old name (the user,
  -- 2026-11-04: "A").
  if v_was.name <> v_name then
    update public.clients c set industry = v_name where c.industry = v_was.name;
    get diagnostics v_n = row_count;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Industries', v_name || ' · ' || array_to_string(v_moved, ' · ') ||
          case when v_n = 1 then ' · 1 client updated' when v_n > 1 then ' · ' || v_n || ' clients updated' else '' end);
  return jsonb_build_object('ok', true, 'name', v_name, 'clients', v_n);
end $$;
revoke all on function public.industry_save(text, text, text, boolean) from public, anon;
grant execute on function public.industry_save(text, text, text, boolean) to authenticated;

create or replace function public.industry_set_active(p_name text, p_on boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v  public.industries;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.industries i where i.name = p_name for update;
  if v.name is null then return jsonb_build_object('error', 'not-found'); end if;
  if v.active = coalesce(p_on, false) then return jsonb_build_object('ok', true); end if;
  update public.industries i set active = coalesce(p_on, false), updated_at = now(), updated_by = me.id where i.name = v.name;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Industries', v.name || ' · ' || case when p_on then 'Inactive → Active' else 'Active → Inactive' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.industry_set_active(text, boolean) from public, anon;
grant execute on function public.industry_set_active(text, boolean) to authenticated;

/* One place up or down, the neighbour taking its place. */
create or replace function public.industry_move(p_name text, p_up boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_names text[];
  v_at int;
  v_to int;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  perform pg_advisory_xact_lock(hashtextextended('industries', 0));
  select array_agg(i.name order by i.position, lower(i.name)) into v_names from public.industries i;
  v_at := array_position(v_names, p_name);
  if v_at is null then return jsonb_build_object('error', 'not-found'); end if;
  v_to := v_at + case when coalesce(p_up, false) then -1 else 1 end;
  if v_to < 1 or v_to > cardinality(v_names) then return jsonb_build_object('ok', true); end if;
  v_names[v_at] := v_names[v_to]; v_names[v_to] := p_name;
  update public.industries i set position = array_position(v_names, i.name) where i.position is distinct from array_position(v_names, i.name);
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Industries', p_name || ' · moved ' || case when p_up then 'up' else 'down' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.industry_move(text, boolean) from public, anon;
grant execute on function public.industry_move(text, boolean) to authenticated;

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
  -- An industry the website offers, from the list kept in Settings
  -- (INDUSTRIES, 2026-11-04).
  if v_ind is not null and not exists (select 1 from public.industries i
                                        where i.name = v_ind and i.active and i.on_website) then
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
  -- The price waits for the team (the user, 2026-10-29: "the price
  -- shouldnt send out straight"): the quotation is owed a reply by working
  -- days, the team is told to review it, and the prospect is sent nothing
  -- until a colleague sends it (`quotation_send`).
  update public.quotations set reply_due = public.quote_reply_by(now()) where id = v_q.id
   returning * into v_q;
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation to review · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('Monthly incl. SST RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') || ' · ' || v_name
      || coalesce(' · Starts ' || lower(public.quote_commence_word(v_start)), '')
      || ' · send by ' || public.register_day((v_q.reply_due at time zone 'Asia/Kuala_Lumpur')::date) || ', ' ||
      lower(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
    v_q.id::text);
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

-- END OF INDUSTRIES ----------------------------------------------------------

select public.functions_tidy();
