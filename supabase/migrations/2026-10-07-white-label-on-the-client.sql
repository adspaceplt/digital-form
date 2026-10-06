-- ===========================================================================
-- WHITE LABEL ON THE CLIENT — a client ticked White label on its Brand pane
-- carries a wide logo for reports, and a report is set to one of those
-- clients and the brand it covers.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after REPORT WHITE LABEL and CLIENT BILLING COLUMNS.
--
-- WHAT CHANGED (the user, 2026-10-06)
--   The partner is a client, so the separate list of partners goes. A
--   client's Brand pane holds a White label tick and, while it is ticked,
--   the wide logo its reports carry; a report's White label offers only the
--   Active clients ticked so.
--   1. `clients.white_label` (off by default) and `clients.report_logo` (a
--      PNG data URL, 1200 by 400 at most); ticked needs the logo
--      (`clients_white_label_logo`). Both readable to the team, as every
--      other non-billing column.
--   2. `sm_reports.label_client`: the white-label client whose logo the
--      report carries.
--   3. `sm_report_label(p_id, p_client, p_brand)`: an admin's or Reports
--      Full Access, on any report not published (`published`), a client
--      ticked White label, holding its logo and Active (`bad-client`), a
--      brand of 120 characters at most (`bad-brand`); filed `report.saved`
--      from and to.
--   4. `sm_report_snapshot` sends that client as the partner (name, logo)
--      while it is still ticked, and, where a brand is set, the brand as the
--      client's name and no client logo. `report_partners` is no longer read.
--
-- ROLLBACK
--   Run sm_report_snapshot from REPORT WHITE LABEL again; the columns and
--   the function may stay unused.
-- ===========================================================================

alter table public.clients add column if not exists white_label boolean not null default false;
alter table public.clients add column if not exists report_logo text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clients_white_label_logo') then
    alter table public.clients add constraint clients_white_label_logo
      check (not white_label or report_logo is not null);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'clients_report_logo_png') then
    alter table public.clients add constraint clients_report_logo_png
      check (report_logo is null or (report_logo like 'data:image/png;base64,%' and char_length(report_logo) <= 1500000));
  end if;
end $$;
grant select (white_label, report_logo) on table public.clients to authenticated;

alter table public.sm_reports add column if not exists label_client uuid references public.clients(id) on delete set null;

create or replace function public.sm_report_label(p_id uuid, p_client uuid, p_brand text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  v_brand text := nullif(btrim(coalesce(p_brand, '')), '');
  v_c public.clients;
  v_was text;
  v_bits text[] := '{}';
begin
  if me.id is null or not (public.allowed('admin') or public.allowed('reports', 'manage')) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if r.status = 'published' then return jsonb_build_object('error', 'published'); end if;
  if v_brand is not null and char_length(v_brand) > 120 then return jsonb_build_object('error', 'bad-brand'); end if;
  if p_client is not null then
    select * into v_c from public.clients where id = p_client;
    if v_c.id is null or not v_c.white_label or v_c.report_logo is null or v_c.stage <> 'active' then
      return jsonb_build_object('error', 'bad-client');
    end if;
  end if;
  if r.label_client is not distinct from p_client and r.brand_name is not distinct from v_brand then
    return jsonb_build_object('ok', true);
  end if;
  if r.label_client is distinct from p_client then
    select c.name into v_was from public.clients c where c.id = r.label_client;
    v_bits := v_bits || ('White label: ' || coalesce(v_was, 'ADspace') || ' → ' || coalesce(v_c.name, 'ADspace'));
  end if;
  if r.brand_name is distinct from v_brand then
    v_bits := v_bits || ('Brand on the report: ' || coalesce(r.brand_name, 'not set') || ' → ' || coalesce(v_brand, 'not set'));
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set label_client = p_client, partner_id = null, brand_name = v_brand where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.saved', array_to_string(v_bits, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.sm_report_label(uuid, uuid, text) from public, anon;
grant execute on function public.sm_report_label(uuid, uuid, text) to authenticated;

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
      -- The white-label client whose logo the report carries (2026-10-07),
      -- while it is still ticked; else none.
      'partner', (select jsonb_build_object('name', l.name, 'logo', l.report_logo)
                    from public.clients l where l.id = r.label_client and l.white_label)),
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

-- END OF WHITE LABEL ON THE CLIENT --------------------------------------------
