-- ===========================================================================
-- META LINKS — which of Meta's ad accounts, Page and Instagram account a
-- client's reports are read from (Import from Meta).
-- 2026-10-08. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after WHITE LABEL BRANDS.
--
-- WHAT CHANGED (the user, 2026-10-08: "1 2 ok", "4 meta marketing api ok")
--   ADspace works in its own Meta business portfolio, and clients share
--   their ad accounts, Pages and Instagram accounts with it as a partner. A
--   client, and each of a white-label client's brands, links one or more ad
--   accounts, one Facebook Page and one Instagram account, picked from what
--   the system user can see (the `meta-import` edge function's `assets`),
--   never typed. Each pick keeps Meta's id and the name Meta gives it.
--   1. `meta_links` (RLS on, no policy, no grant): one row a client and brand
--      (the client's own has no brand); `ad_accounts` a list, `page` and
--      `instagram` one each, `{ id, name }`. Removed with its client or
--      brand; never removed by hand (an empty pick is kept as empty).
--   2. `meta_links_list(p_client)`: every row of the client (Reports or
--      Clients at View, the client in scope).
--   3. `meta_links_save(p_client, p_brand, p_ad_accounts, p_page,
--      p_instagram)`: Clients at Work with the client in scope at Work; the
--      brand the client's (`bad-brand`); ids digits only, at most 20 ad
--      accounts (`bad-asset`). Filed `client.brand` from and to; a save that
--      changed nothing files nothing.
--
-- ROLLBACK
--   drop function if exists public.meta_links_save(uuid, uuid, jsonb, jsonb, jsonb);
--   drop function if exists public.meta_links_list(uuid);
--   drop table if exists public.meta_links;
-- ===========================================================================

create table if not exists public.meta_links (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.clients(id) on delete cascade,
  brand_id    uuid references public.client_brands(id) on delete cascade,
  ad_accounts jsonb not null default '[]'::jsonb,
  page        jsonb,
  instagram   jsonb,
  updated_at  timestamptz not null default now(),
  updated_by  text
);
create unique index if not exists meta_links_client_brand_idx
  on public.meta_links (client_id, coalesce(brand_id, '00000000-0000-0000-0000-000000000000'::uuid));
alter table public.meta_links enable row level security;
revoke all on public.meta_links from public, anon, authenticated;

create or replace function public.meta_links_list(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if not (public.allowed('reports', 'view') or public.allowed('clients', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('links', coalesce((
    select jsonb_agg(jsonb_build_object('brand_id', l.brand_id, 'ad_accounts', l.ad_accounts,
             'page', l.page, 'instagram', l.instagram) order by l.brand_id nulls first)
      from public.meta_links l where l.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.meta_links_list(uuid) from public, anon;
grant execute on function public.meta_links_list(uuid) to authenticated;

-- One asset as kept: Meta's id (digits) and its name, else null.
create or replace function public.meta_asset_of(p jsonb)
returns jsonb
language sql immutable set search_path = public as $$
  select case
    when p is null or jsonb_typeof(p) <> 'object' or coalesce(p ->> 'id', '') = '' then null
    when (p ->> 'id') !~ '^[0-9]{3,30}$' then jsonb_build_object('bad', true)
    else jsonb_build_object('id', p ->> 'id',
           'name', left(coalesce(nullif(btrim(p ->> 'name'), ''), p ->> 'id'), 200))
  end
$$;
revoke all on function public.meta_asset_of(jsonb) from public, anon, authenticated;

-- How a pick reads in the record: the names, else "not set".
create or replace function public.meta_names(p jsonb)
returns text
language sql immutable set search_path = public as $$
  select coalesce(nullif(case jsonb_typeof(p)
    when 'array' then (select string_agg(e ->> 'name', ', ' order by o) from jsonb_array_elements(p) with ordinality as x(e, o))
    when 'object' then p ->> 'name' end, ''), 'not set')
$$;
revoke all on function public.meta_names(jsonb) from public, anon, authenticated;

create or replace function public.meta_links_save(p_client uuid, p_brand uuid, p_ad_accounts jsonb, p_page jsonb, p_instagram jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_client text;
  v_brand text;
  v_accs jsonb := '[]'::jsonb;
  v_page jsonb := public.meta_asset_of(p_page);
  v_ig jsonb := public.meta_asset_of(p_instagram);
  e jsonb;
  a jsonb;
  v_old public.meta_links;
  v_detail text;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select c.name into v_client from public.clients c where c.id = p_client;
  if v_client is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_brand is not null then
    select b.name into v_brand from public.client_brands b where b.id = p_brand and b.client_id = p_client;
    if v_brand is null then return jsonb_build_object('error', 'bad-brand'); end if;
  end if;
  if p_ad_accounts is not null and jsonb_typeof(p_ad_accounts) <> 'array' then return jsonb_build_object('error', 'bad-asset'); end if;
  for e in select x from jsonb_array_elements(coalesce(p_ad_accounts, '[]'::jsonb)) as t(x) loop
    a := public.meta_asset_of(e);
    if a is null or a ? 'bad' then return jsonb_build_object('error', 'bad-asset'); end if;
    if not exists (select 1 from jsonb_array_elements(v_accs) as y(z) where y.z ->> 'id' = a ->> 'id') then
      v_accs := v_accs || jsonb_build_array(a);
    end if;
  end loop;
  if jsonb_array_length(v_accs) > 20 or coalesce(v_page ? 'bad', false) or coalesce(v_ig ? 'bad', false) then
    return jsonb_build_object('error', 'bad-asset');
  end if;
  select * into v_old from public.meta_links l
   where l.client_id = p_client and l.brand_id is not distinct from p_brand for update;
  if v_old.id is not null and v_old.ad_accounts = v_accs and v_old.page is not distinct from v_page and v_old.instagram is not distinct from v_ig then
    return jsonb_build_object('ok', true);
  end if;
  if v_old.id is null and jsonb_array_length(v_accs) = 0 and v_page is null and v_ig is null then
    return jsonb_build_object('ok', true);
  end if;
  v_detail := concat_ws(' · ',
    case when coalesce(v_old.ad_accounts, '[]'::jsonb) <> v_accs
         then 'Meta ad accounts: ' || public.meta_names(v_old.ad_accounts) || ' → ' || public.meta_names(v_accs) end,
    case when v_old.page is distinct from v_page
         then 'Facebook Page: ' || public.meta_names(v_old.page) || ' → ' || public.meta_names(v_page) end,
    case when v_old.instagram is distinct from v_ig
         then 'Instagram: ' || public.meta_names(v_old.instagram) || ' → ' || public.meta_names(v_ig) end);
  if v_old.id is null then
    insert into public.meta_links (client_id, brand_id, ad_accounts, page, instagram, updated_by)
    values (p_client, p_brand, v_accs, v_page, v_ig, me.name);
  else
    update public.meta_links set ad_accounts = v_accs, page = v_page, instagram = v_ig,
           updated_at = now(), updated_by = me.name
     where id = v_old.id;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.brand', v_client, case when v_brand is not null then v_brand || ': ' else '' end || v_detail);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.meta_links_save(uuid, uuid, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.meta_links_save(uuid, uuid, jsonb, jsonb, jsonb) to authenticated;

-- END OF META LINKS ---------------------------------------------------------

select public.functions_tidy();
