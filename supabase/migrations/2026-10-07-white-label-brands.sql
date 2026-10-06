-- ===========================================================================
-- WHITE LABEL BRANDS — a white-label client keeps a list of the brands it is
-- serviced for, and a report belongs to its client and its brand, so each
-- brand has its own report a month, its own AI quota and its own history.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after WHITE LABEL ON THE CLIENT.
--
-- WHAT CHANGED (the user, 2026-10-07)
--   The partner is the client (Peakle), and Peakle's own clients (A, B, C)
--   are its brands. A report for Client A must not take Peakle's own month,
--   nor share its AI quota with Client B.
--   1. `client_brands` (RLS on, no policy, no grant): a client's saved
--      brands, a name each (unique within the client, any case), stood down
--      with `active`, never removed. Read through `client_brands_list`
--      (Reports or Clients at View, the client in scope); written through
--      `client_brand_save` (Reports: White label at Work), filed
--      `client.brand`. A rename carries onto the client's reports not yet
--      published.
--   2. `sm_reports.brand_id`: the brand a report covers. One report a client,
--      kind, period and brand (`sm_reports_client_brand_period_idx`; the
--      client's own report is the one with no brand).
--   3. `sm_report_create_for(p_client, p_start, p_end, p_kind, p_brand)`
--      starts a report for a brand (Reports: White label at Work; the client
--      ticked White label with its logo; the brand the client's, active,
--      `bad-brand`), carrying accounts forward from that brand's own last
--      report; `sm_report_create` is the same with no brand.
--   4. `sm_report_brand(p_id, p_brand)` sets or clears the brand of a report
--      not published (`exists` where the brand already has one for the
--      period), the report's own client's logo going with it; filed from and
--      to. `sm_report_label` is no longer called.
--   5. `ai_drafts.brand_id`, filled from the report on every insert, and
--      `ai_draft_same` counting by brand, so a brand's drafts are its own.
--   6. `sm_report_move` refuses a white-label report (`white-label`) and
--      checks the destination's own reports only.
--   7. A report set before this (a typed brand name) is given a saved brand
--      of that name.
--   8. Mark as sent (the user, 2026-10-07): `sm_reports.sent_on` /
--      `sent_by`, set on a published report only through
--      `sm_report_sent(p_id, p_on)` (Reports at Work; `not-published`; a day
--      not after today in Malaysia nor before the period starts,
--      `bad-date`; null marks it not sent), filed from and to.
--
-- BY HAND, ONCE, IN THE SQL EDITOR (the connector holds the statement):
--   drop index if exists public.sm_reports_client_period_idx;
--   Until then a second report for a period (a brand's beside the client's
--   own) is refused (`index-pending`).
--
-- ROLLBACK
--   Run sm_report_create, sm_report_move and ai_draft_same from their earlier
--   sections again; the table, the columns and the new functions may stay.
-- ===========================================================================

create table if not exists public.client_brands (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null,
  name        text not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint client_brands_name check (char_length(btrim(name)) between 1 and 120)
);
create unique index if not exists client_brands_name_idx on public.client_brands (client_id, lower(btrim(name)));
alter table public.client_brands enable row level security;
revoke all on public.client_brands from public, anon, authenticated;

alter table public.sm_reports add column if not exists brand_id uuid;
create unique index if not exists sm_reports_client_brand_period_idx
  on public.sm_reports (client_id, kind, period_start, period_end, coalesce(brand_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- A report given a typed brand before the list existed takes a saved brand.
insert into public.client_brands (client_id, name)
select distinct r.client_id, btrim(r.brand_name) from public.sm_reports r
 where r.brand_name is not null and r.brand_id is null
on conflict do nothing;
update public.sm_reports r set brand_id = b.id
  from public.client_brands b
 where r.brand_id is null and r.brand_name is not null
   and b.client_id = r.client_id and lower(btrim(b.name)) = lower(btrim(r.brand_name));

alter table public.ai_drafts add column if not exists brand_id uuid;
create or replace function public.ai_drafts_brand()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.report_id is not null and new.brand_id is null then
    select r.brand_id into new.brand_id from public.sm_reports r where r.id = new.report_id;
  end if;
  return new;
end $$;
revoke all on function public.ai_drafts_brand() from public, anon, authenticated;
create or replace trigger ai_drafts_brand before insert on public.ai_drafts
  for each row execute function public.ai_drafts_brand();
update public.ai_drafts d set brand_id = r.brand_id
  from public.sm_reports r where d.report_id = r.id and d.brand_id is null and r.brand_id is not null;

create or replace function public.ai_draft_same(p_report uuid)
returns setof public.ai_drafts
language sql stable security definer set search_path = public as $$
  select d.* from public.ai_drafts d
   where d.outcome <> 'failed' and d.purpose = 'draft'
     and (d.report_id = p_report
          or exists (select 1 from public.sm_reports r
                      where r.id = p_report and d.client_id = r.client_id and d.kind = r.kind
                        and d.brand_id is not distinct from r.brand_id
                        and d.period_start <= r.period_end and d.period_end >= r.period_start))
$$;
revoke all on function public.ai_draft_same(uuid) from public, anon, authenticated;

create or replace function public.client_brands_list(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if not (public.allowed('reports', 'view') or public.allowed('clients', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('brands', coalesce((
    select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'active', b.active) order by b.active desc, lower(b.name))
      from public.client_brands b where b.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.client_brands_list(uuid) from public, anon;
grant execute on function public.client_brands_list(uuid) to authenticated;

create or replace function public.client_brand_save(p_id uuid, p_client uuid, p_name text, p_active boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  b public.client_brands;
  v_client text;
  v_id uuid;
begin
  if me.id is null or not public.ops_granted('reports.whitelabel', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'denied'); end if;
  select c.name into v_client from public.clients c where c.id = p_client;
  if v_client is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_name is null or char_length(v_name) > 120 then return jsonb_build_object('error', 'bad-name'); end if;
  if exists (select 1 from public.client_brands x where x.client_id = p_client and lower(btrim(x.name)) = lower(v_name)
              and x.id is distinct from p_id) then
    return jsonb_build_object('error', 'taken');
  end if;
  if p_id is null then
    insert into public.client_brands (client_id, name, active) values (p_client, v_name, coalesce(p_active, true))
    returning id into v_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.brand', v_client, 'White label brand added: ' || v_name);
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;
  select * into b from public.client_brands where id = p_id and client_id = p_client for update;
  if b.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if b.name = v_name and b.active = coalesce(p_active, b.active) then return jsonb_build_object('ok', true, 'id', b.id); end if;
  update public.client_brands set name = v_name, active = coalesce(p_active, b.active), updated_at = now() where id = p_id;
  if b.name <> v_name then
    perform set_config('adspace.sm_fn', 'on', true);
    update public.sm_reports set brand_name = v_name where brand_id = p_id and status <> 'published';
    perform set_config('adspace.sm_fn', 'off', true);
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.brand', v_client, concat_ws(' · ',
    case when b.name <> v_name then 'White label brand: ' || b.name || ' → ' || v_name end,
    case when b.active <> coalesce(p_active, b.active)
         then 'White label brand ' || v_name || (case when p_active then ': inactive → active' else ': active → inactive' end) end));
  return jsonb_build_object('ok', true, 'id', b.id);
end $$;
revoke all on function public.client_brand_save(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.client_brand_save(uuid, uuid, text, boolean) to authenticated;

create or replace function public.sm_report_create_for(p_client uuid, p_start date, p_end date, p_kind text, p_brand uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  rid uuid;
  prev uuid;
  pr public.sm_reports;
  totals jsonb := '{}'::jsonb;
  pgroups jsonb;
  ptk jsonb;
  c public.clients;
  b public.client_brands;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.clients where id = p_client;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_start is null or p_end is null or p_end < p_start then return jsonb_build_object('error', 'bad-period'); end if;
  if coalesce(p_kind, '') not in ('social', 'ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_brand is not null then
    if not public.ops_granted('reports.whitelabel', 'work') then return jsonb_build_object('error', 'denied'); end if;
    select * into b from public.client_brands where id = p_brand;
    if b.id is null or b.client_id <> p_client or not b.active or not c.white_label or c.report_logo is null then
      return jsonb_build_object('error', 'bad-brand');
    end if;
  end if;
  select id into rid from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start = p_start and period_end = p_end
     and brand_id is not distinct from p_brand;
  if rid is not null then return jsonb_build_object('error', 'exists', 'id', rid); end if;
  select id into prev from public.sm_reports
   where client_id = p_client and kind = p_kind and period_start < p_start and brand_id is not distinct from p_brand
   order by period_start desc limit 1;
  perform set_config('adspace.sm_fn', 'on', true);
  begin
    if p_kind = 'ads' then
      if prev is not null then
        select * into pr from public.sm_reports where id = prev;
        select coalesce(jsonb_object_agg(g.objective, jsonb_build_object('results',
                 coalesce(nullif(pr.ads_totals #>> array['groups', g.objective, 'results'], '')::numeric, g.results),
                 'spend', g.spend)), '{}'::jsonb)
          into pgroups
          from (select a.objective, sum(a.results) as results, sum(a.spend) as spend
                  from public.sm_report_ads a where a.report_id = prev and a.platform = 'meta' group by a.objective) g;
        if exists (select 1 from public.sm_report_ads where report_id = prev and platform = 'tiktok')
           or coalesce(pr.ads_totals #>> '{tiktok,reach}', pr.ads_totals #>> '{tiktok,impressions}',
                       pr.ads_totals #>> '{tiktok,spend}') is not null then
          ptk := jsonb_strip_nulls(jsonb_build_object(
            'prev_reach', nullif(pr.ads_totals #>> '{tiktok,reach}', '')::numeric,
            'prev_impressions', coalesce(nullif(pr.ads_totals #>> '{tiktok,impressions}', '')::numeric,
                                         (select sum(impressions) from public.sm_report_ads where report_id = prev and platform = 'tiktok')),
            'prev_spend', coalesce(nullif(pr.ads_totals #>> '{tiktok,spend}', '')::numeric,
                                   (select sum(spend) from public.sm_report_ads where report_id = prev and platform = 'tiktok'))));
        end if;
        totals := jsonb_strip_nulls(jsonb_build_object(
          'prev_start', pr.period_start, 'prev_end', pr.period_end,
          'prev_reach', nullif(pr.ads_totals ->> 'reach', '')::numeric,
          'prev_impressions', coalesce(nullif(pr.ads_totals ->> 'impressions', '')::numeric,
                                       (select sum(impressions) from public.sm_report_ads where report_id = prev and platform = 'meta')),
          'prev_spend', coalesce(nullif(pr.ads_totals ->> 'spend', '')::numeric,
                                 (select sum(spend) from public.sm_report_ads where report_id = prev and platform = 'meta')),
          'prev_groups', pgroups,
          'tiktok', ptk));
      else
        if date_trunc('month', p_start)::date = p_start and (p_start + interval '1 month' - interval '1 day')::date = p_end then
          totals := jsonb_build_object('prev_start', (p_start - interval '1 month')::date, 'prev_end', p_start - 1);
        else
          totals := jsonb_build_object('prev_start', p_start - (p_end - p_start + 1), 'prev_end', p_start - 1);
        end if;
      end if;
      insert into public.sm_reports (client_id, kind, title, period_start, period_end, created_by, first_month, ads_totals,
                                     brand_id, brand_name, label_client)
      values (p_client, p_kind, 'Social Media Advertising Report', p_start, p_end, me.id, false, totals,
              b.id, b.name, case when b.id is not null then p_client end)
      returning id into rid;
    else
      insert into public.sm_reports (client_id, kind, period_start, period_end, created_by, brand_id, brand_name, label_client)
      values (p_client, p_kind, p_start, p_end, me.id, b.id, b.name, case when b.id is not null then p_client end)
      returning id into rid;
      if prev is not null then
        insert into public.sm_report_platforms (report_id, platform, platform_name, account_name, handle, group_key, group_label,
          position, metrics, followers_start, er_basis, metric_notes)
        select rid, p.platform, p.platform_name, p.account_name, p.handle, p.group_key, p.group_label, p.position, p.metrics,
               coalesce(p.followers_end, case when p.followers_start is not null and p.growth_override is not null
                                              then p.followers_start + p.growth_override end),
               p.er_basis, p.metric_notes
          from public.sm_report_platforms p where p.report_id = prev;
      end if;
    end if;
  exception when unique_violation then
    perform set_config('adspace.sm_fn', 'off', true);
    return jsonb_build_object('error', 'index-pending');
  end;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(rid, 'report.created', case when b.id is not null then 'White label: ' || b.name end);
  return jsonb_build_object('ok', true, 'id', rid, 'carried', prev is not null);
end $$;
revoke all on function public.sm_report_create_for(uuid, date, date, text, uuid) from public, anon;
grant execute on function public.sm_report_create_for(uuid, date, date, text, uuid) to authenticated;

create or replace function public.sm_report_create(p_client uuid, p_start date, p_end date, p_kind text default 'social')
returns jsonb
language sql security definer set search_path = public as $$
  select public.sm_report_create_for(p_client, p_start, p_end, p_kind, null)
$$;
grant execute on function public.sm_report_create(uuid, date, date, text) to authenticated;

create or replace function public.sm_report_brand(p_id uuid, p_brand uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  b public.client_brands;
begin
  if me.id is null or not public.ops_granted('reports.whitelabel', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.status = 'published' then return jsonb_build_object('error', 'published'); end if;
  select * into c from public.clients where id = r.client_id;
  if p_brand is not null then
    select * into b from public.client_brands where id = p_brand;
    if b.id is null or b.client_id <> r.client_id or not b.active or not c.white_label or c.report_logo is null then
      return jsonb_build_object('error', 'bad-brand');
    end if;
  end if;
  if r.brand_id is not distinct from p_brand then return jsonb_build_object('ok', true); end if;
  if exists (select 1 from public.sm_reports x
              where x.client_id = r.client_id and x.kind = r.kind and x.id <> r.id
                and x.period_start = r.period_start and x.period_end = r.period_end
                and x.brand_id is not distinct from p_brand) then
    return jsonb_build_object('error', 'exists');
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  begin
    update public.sm_reports
       set brand_id = b.id, brand_name = b.name, partner_id = null,
           label_client = case when b.id is not null then r.client_id end
     where id = p_id;
  exception when unique_violation then
    perform set_config('adspace.sm_fn', 'off', true);
    return jsonb_build_object('error', 'index-pending');
  end;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.saved',
    'White label: ' || coalesce(r.brand_name, 'not set') || ' → ' || coalesce(b.name, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.sm_report_brand(uuid, uuid) from public, anon;
grant execute on function public.sm_report_brand(uuid, uuid) to authenticated;

create or replace function public.sm_report_move(p_id uuid, p_client uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  was text;
begin
  if me.id is null or not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft', 'status', r.status); end if;
  if r.brand_id is not null then return jsonb_build_object('error', 'white-label'); end if;
  select * into c from public.clients where id = p_client;
  if c.id is null or c.stage <> 'active' then return jsonb_build_object('error', 'not-active'); end if;
  if c.id = r.client_id then return jsonb_build_object('ok', true, 'client_id', c.id); end if;
  if exists (select 1 from public.sm_reports x
              where x.client_id = c.id and x.kind = r.kind and x.id <> r.id and x.brand_id is null
                and x.period_start <= r.period_end and x.period_end >= r.period_start) then
    return jsonb_build_object('error', 'exists');
  end if;
  select k.name into was from public.clients k where k.id = r.client_id;
  perform public.sm_report_log(p_id, 'report.saved', 'Client: ' || coalesce(was, 'not set') || ' → ' || c.name);
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set client_id = c.id where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  update public.ai_drafts set client_id = c.id where report_id = p_id;
  perform public.sm_report_log(p_id, 'report.saved', 'Client: ' || coalesce(was, 'not set') || ' → ' || c.name);
  return jsonb_build_object('ok', true, 'client_id', c.id);
end $$;
revoke all on function public.sm_report_move(uuid, uuid) from public, anon, authenticated;
grant execute on function public.sm_report_move(uuid, uuid) to authenticated;

alter table public.sm_reports add column if not exists sent_on date;
alter table public.sm_reports add column if not exists sent_by text;

create or replace function public.sm_report_sent(p_id uuid, p_on date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.status <> 'published' then return jsonb_build_object('error', 'not-published'); end if;
  if p_on is not null and (p_on > v_today or p_on < r.period_start) then return jsonb_build_object('error', 'bad-date'); end if;
  if r.sent_on is not distinct from p_on then return jsonb_build_object('ok', true); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set sent_on = p_on, sent_by = case when p_on is null then null else me.name end where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.saved', 'Sent to client: ' ||
    coalesce(public.register_day(r.sent_on), 'not set') || ' → ' || coalesce(public.register_day(p_on), 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.sm_report_sent(uuid, date) from public, anon;
grant execute on function public.sm_report_sent(uuid, date) to authenticated;

-- END OF WHITE LABEL BRANDS ---------------------------------------------------
