-- ===========================================================================
-- WHITE LABEL BRAND LOGO — each brand says whose mark heads its reports: the
-- white-label client's wide logo, or ADspace's own wordmark.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after WHITE LABEL BRANDS.
--
-- WHAT CHANGED (the user, 2026-10-07)
--   Some of a partner's brands go out under the partner's logo, some under
--   ADspace's own mark; the brand is still named as the client either way.
--   1. `client_brands.logo`: 'partner' (the client's wide logo, the default)
--      or 'adspace'.
--   2. `client_brand_logo(p_id, p_logo)`: Reports: White label at Work;
--      `bad-logo`; filed `client.brand` from and to.
--   3. `client_brands_list` sends each brand's logo.
--   4. `sm_report_snapshot` sends the partner only where the report's brand
--      takes the partner's logo; a published version keeps what it went out
--      with.
--
-- ROLLBACK
--   Run sm_report_snapshot from WHITE LABEL ON THE CLIENT and
--   client_brands_list from WHITE LABEL BRANDS again; the column and the
--   function may stay unused.
-- ===========================================================================

alter table public.client_brands add column if not exists logo text not null default 'partner';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'client_brands_logo') then
    alter table public.client_brands add constraint client_brands_logo check (logo in ('partner', 'adspace'));
  end if;
end $$;

create or replace function public.client_brands_list(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if not (public.allowed('reports', 'view') or public.allowed('clients', 'view')) then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('brands', coalesce((
    select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'active', b.active, 'logo', b.logo)
                     order by b.active desc, lower(b.name))
      from public.client_brands b where b.client_id = p_client), '[]'::jsonb));
end $$;
revoke all on function public.client_brands_list(uuid) from public, anon;
grant execute on function public.client_brands_list(uuid) to authenticated;

create or replace function public.client_brand_logo(p_id uuid, p_logo text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  b public.client_brands;
  v_client text;
begin
  if me.id is null or not public.ops_granted('reports.whitelabel', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_logo, '') not in ('partner', 'adspace') then return jsonb_build_object('error', 'bad-logo'); end if;
  select * into b from public.client_brands where id = p_id for update;
  if b.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(b.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if b.logo = p_logo then return jsonb_build_object('ok', true); end if;
  select c.name into v_client from public.clients c where c.id = b.client_id;
  update public.client_brands set logo = p_logo, updated_at = now() where id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.brand', v_client, 'White label brand ' || b.name || ' logo: ' ||
    case b.logo when 'adspace' then 'ADspace' else v_client end || ' → ' ||
    case p_logo when 'adspace' then 'ADspace' else v_client end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_brand_logo(uuid, text) from public, anon;
grant execute on function public.client_brand_logo(uuid, text) to authenticated;

create or replace function public.sm_report_snapshot(p_id uuid, p_final boolean default false)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  c public.clients;
begin
  if not public.allowed('reports', 'view') and not public.allowed('clients', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  -- Somebody who reads Clients but not Reports reads the finished report
  -- only: once it is confirmed, never while it is being prepared.
  if not public.allowed('reports', 'view') and r.status not in ('confirmed', 'published') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into c from public.clients where id = r.client_id;
  return jsonb_build_object(
    'report', jsonb_build_object(
      -- A white-label report names the brand it covers, with no client logo.
      'id', r.id, 'kind', r.kind, 'title', r.title, 'client_name', coalesce(r.brand_name, c.name),
      'client_logo_url', case when r.brand_name is null then c.logo_url end,
      'market', to_jsonb(c) ->> 'market', 'lang', r.lang,
      'period_start', r.period_start, 'period_end', r.period_end,
      'headline', r.headline, 'intro', r.intro, 'insights', r.insights, 'rank_metric', r.rank_metric,
      'first_month', r.first_month, 'ads_totals', r.ads_totals,
      'status', case when p_final then 'final' else r.status end,
      'version_no', r.version_no, 'generated_at', now(),
      'prepared_by_name', (select name from public.team_members where id = r.submitted_by),
      -- The white-label client's wide logo while it is still ticked and the
      -- report's brand takes it (2026-10-07); else ADspace's own mark.
      'partner', (select jsonb_build_object('name', l.name, 'logo', l.report_logo)
                    from public.clients l where l.id = r.label_client and l.white_label
                     and coalesce((select b.logo from public.client_brands b where b.id = r.brand_id), 'partner') = 'partner')),
    'platforms', coalesce((select jsonb_agg(to_jsonb(p) - 'created_at' order by p.position, p.created_at)
                  from public.sm_report_platforms p where p.report_id = r.id), '[]'::jsonb),
    'posts', coalesce((select jsonb_agg((to_jsonb(q) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', q.thumb_data)
                  order by q.posted_on nulls last, q.position, q.created_at)
                  from public.sm_report_posts q where q.report_id = r.id), '[]'::jsonb),
    'ads', coalesce((select jsonb_agg((to_jsonb(a) - 'created_at' - 'thumb_data') || jsonb_build_object('thumb_url', a.thumb_data)
                  order by a.position, a.created_at)
                  from public.sm_report_ads a where a.report_id = r.id), '[]'::jsonb));
end $$;
grant execute on function public.sm_report_snapshot(uuid, boolean) to authenticated;

-- END OF WHITE LABEL BRAND LOGO -----------------------------------------------
