-- ===========================================================================
-- REPORT WHITE LABEL — a report set as white-label carries a partner's logo
-- and the brand it covers, while it stays under the client who pays for it.
-- 2026-10-06. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after REPORT PARTNERS (report_partners, sm_report_snapshot).
--
-- WHAT CHANGED (the user, 2026-10-06)
--   The partner is the client: The Peakle Creative is billed and has its
--   portal, and ADspace services Peakle's own clients (SKS City Mall JBCC)
--   under Peakle's name. So the report is made under Peakle and set, report
--   by report, to the partner's logo and the brand it covers.
--   1. `sm_reports.partner_id` (the partner whose logo the PDF carries) and
--      `sm_reports.brand_name` (the brand the report covers), both empty
--      for an ordinary report.
--   2. `sm_report_white_label(p_id, p_partner, p_brand)`: an admin's or
--      Reports Full Access, on any report not published (`published`),
--      an active partner (`bad-partner`), a brand of 120 characters at
--      most (`bad-brand`); filed `report.saved` from and to.
--   3. `sm_report_snapshot` sends the report's partner (name, logo) and,
--      where a brand is set, the brand as the client's name and no client
--      logo; a published version keeps what it went out with. The clients a
--      partner held (`report_partner_clients`) are no longer read.
--
-- ROLLBACK
--   Run sm_report_snapshot from REPORT PARTNERS again; the two columns and
--   the function may stay unused.
-- ===========================================================================

alter table public.sm_reports add column if not exists partner_id uuid references public.report_partners(id);
alter table public.sm_reports add column if not exists brand_name text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'sm_reports_brand_name') then
    alter table public.sm_reports add constraint sm_reports_brand_name
      check (brand_name is null or char_length(btrim(brand_name)) between 1 and 120);
  end if;
end $$;

create or replace function public.sm_report_white_label(p_id uuid, p_partner uuid, p_brand text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  v_brand text := nullif(btrim(coalesce(p_brand, '')), '');
  v_p public.report_partners;
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
  if p_partner is not null then
    select * into v_p from public.report_partners where id = p_partner;
    if v_p.id is null or not v_p.active then return jsonb_build_object('error', 'bad-partner'); end if;
  end if;
  if r.partner_id is not distinct from p_partner and r.brand_name is not distinct from v_brand then
    return jsonb_build_object('ok', true);
  end if;
  if r.partner_id is distinct from p_partner then
    select p.name into v_was from public.report_partners p where p.id = r.partner_id;
    v_bits := v_bits || ('Partner logo: ' || coalesce(v_was, 'ADspace') || ' → ' || coalesce(v_p.name, 'ADspace'));
  end if;
  if r.brand_name is distinct from v_brand then
    v_bits := v_bits || ('Brand on the report: ' || coalesce(r.brand_name, 'not set') || ' → ' || coalesce(v_brand, 'not set'));
  end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set partner_id = p_partner, brand_name = v_brand where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.saved', array_to_string(v_bits, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.sm_report_white_label(uuid, uuid, text) from public, anon;
grant execute on function public.sm_report_white_label(uuid, uuid, text) to authenticated;

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
      -- The partner whose logo the report carries (2026-10-06), else none.
      'partner', (select jsonb_build_object('name', p.name, 'logo', p.logo_data)
                    from public.report_partners p where p.id = r.partner_id and p.active)),
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

-- END OF REPORT WHITE LABEL ---------------------------------------------------
