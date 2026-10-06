-- ===========================================================================
-- REPORT PARTNERS — a partner's clients' reports carry the partner's logo at
-- the top of every page, in place of ADspace's wordmark.
-- 2026-10-06. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after CLIENT SCOPE (sm_report_snapshot, client_seen).
--
-- WHAT CHANGED (the user, 2026-10-06)
--   ADspace subcontracts white-label work: one partner hands over several of
--   its own clients, and their reports go out as a courtesy under the
--   partner's logo (landscape, never the client's round mark). Everything
--   else stays ADspace's: the clients know who does the work.
--   1. `report_partners` (name, a landscape logo kept as a PNG data address,
--      active) and `report_partner_clients` (one row a client, the partner
--      or none; no foreign key to the client, so removing a client never
--      waits on it, and a row left behind names nobody). RLS on, read at Reports View (the client's own row within
--      the client scope), written only through the functions below.
--   2. `report_partner_save(p_id, p_name, p_logo, p_clients)` adds or edits a
--      partner and sets its clients (a client moves from another partner;
--      one taken off reads ADspace again); `report_partner_set_active` stands
--      a partner down or back. Both an admin's or Reports Full Access, filed
--      `report.saved` under Partners.
--   3. `sm_report_snapshot` sends the client's active partner (name, logo),
--      so a published version keeps the brand it went out with.
--
-- ROLLBACK
--   Run sm_report_snapshot from CLIENT SCOPE again; the two tables and two
--   functions may stay unused.
-- ===========================================================================

create table if not exists public.report_partners (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  logo_data  text,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint report_partners_name check (char_length(btrim(name)) between 2 and 80),
  constraint report_partners_logo check (logo_data is null or (logo_data ~ '^data:image/png;base64,' and char_length(logo_data) <= 1500000))
);
create table if not exists public.report_partner_clients (
  client_id  uuid primary key,
  partner_id uuid references public.report_partners(id),
  updated_at timestamptz not null default now()
);
alter table public.report_partners enable row level security;
alter table public.report_partner_clients enable row level security;
grant select on public.report_partners, public.report_partner_clients to authenticated;
revoke insert, update on public.report_partners, public.report_partner_clients from anon, authenticated;
revoke select on public.report_partners, public.report_partner_clients from anon;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'report_partners' and policyname = 'report_partners_read') then
    create policy report_partners_read on public.report_partners for select to authenticated
      using (public.allowed('reports', 'view'));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'report_partner_clients' and policyname = 'report_partner_clients_read') then
    create policy report_partner_clients_read on public.report_partner_clients for select to authenticated
      using (public.allowed('reports', 'view'));
  end if;
  -- The scope rule asks the two helpers every other table's does: a login
  -- may not run client_seen itself, so a policy naming it fails every read.
  if not exists (select 1 from pg_policies where tablename = 'report_partner_clients' and policyname = 'client_scope') then
    create policy client_scope on public.report_partner_clients as restrictive for select to authenticated
      using ((select public.client_scope_free('view')) or public.client_scope_ok('client', client_id, 'view'));
  else
    alter policy client_scope on public.report_partner_clients
      using ((select public.client_scope_free('view')) or public.client_scope_ok('client', client_id, 'view'));
  end if;
end $$;

create or replace function public.report_partner_save(p_id uuid, p_name text, p_logo text, p_clients uuid[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_id uuid := p_id;
  v_name text := btrim(coalesce(p_name, ''));
  v_was public.report_partners;
  v_list text;
  c uuid;
begin
  if me.id is null or not (public.allowed('admin') or public.allowed('reports', 'manage')) then
    return jsonb_build_object('error', 'denied');
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if p_logo is not null and (p_logo !~ '^data:image/png;base64,' or char_length(p_logo) > 1500000) then
    return jsonb_build_object('error', 'bad-logo');
  end if;
  foreach c in array coalesce(p_clients, '{}') loop
    if not exists (select 1 from public.clients k where k.id = c) or not public.client_seen(c, 'view') then
      return jsonb_build_object('error', 'bad-client');
    end if;
  end loop;
  if v_id is null then
    insert into public.report_partners (name, logo_data) values (v_name, p_logo) returning id into v_id;
  else
    select * into v_was from public.report_partners where id = v_id for update;
    if v_was.id is null then return jsonb_build_object('error', 'not-found'); end if;
    update public.report_partners set name = v_name, logo_data = p_logo, updated_at = now() where id = v_id;
  end if;
  update public.report_partner_clients set partner_id = null, updated_at = now()
   where partner_id = v_id and not (client_id = any (coalesce(p_clients, '{}')));
  foreach c in array coalesce(p_clients, '{}') loop
    insert into public.report_partner_clients (client_id, partner_id) values (c, v_id)
    on conflict (client_id) do update set partner_id = excluded.partner_id, updated_at = now();
  end loop;
  select string_agg(k.name, ', ' order by k.name) into v_list
    from public.report_partner_clients pc join public.clients k on k.id = pc.client_id where pc.partner_id = v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'report.saved', 'Partners',
          case when v_was.id is null then 'Partner added: ' else 'Partner edited: ' end || v_name
          || case when v_was.id is not null and v_was.name is distinct from v_name then ' (was ' || v_was.name || ')' else '' end
          || case when v_was.id is not null and v_was.logo_data is distinct from p_logo then ' · logo changed' else '' end
          || ' · clients: ' || coalesce(v_list, 'none'));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.report_partner_save(uuid, text, text, uuid[]) from public, anon;
grant execute on function public.report_partner_save(uuid, text, text, uuid[]) to authenticated;

create or replace function public.report_partner_set_active(p_id uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v public.report_partners;
begin
  if me.id is null or not (public.allowed('admin') or public.allowed('reports', 'manage')) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into v from public.report_partners where id = p_id for update;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v.active is distinct from coalesce(p_on, false) then
    update public.report_partners set active = coalesce(p_on, false), updated_at = now() where id = p_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'report.saved', 'Partners',
            case when coalesce(p_on, false) then 'Partner set active: ' else 'Partner set inactive: ' end || v.name);
  end if;
  return jsonb_build_object('ok', true, 'active', coalesce(p_on, false));
end $$;
revoke all on function public.report_partner_set_active(uuid, boolean) from public, anon;
grant execute on function public.report_partner_set_active(uuid, boolean) to authenticated;

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
      'id', r.id, 'kind', r.kind, 'title', r.title, 'client_name', c.name, 'client_logo_url', c.logo_url,
      'market', to_jsonb(c) ->> 'market', 'lang', r.lang,
      'period_start', r.period_start, 'period_end', r.period_end,
      'headline', r.headline, 'intro', r.intro, 'insights', r.insights, 'rank_metric', r.rank_metric,
      'first_month', r.first_month, 'ads_totals', r.ads_totals,
      'status', case when p_final then 'final' else r.status end,
      'version_no', r.version_no, 'generated_at', now(),
      'prepared_by_name', (select name from public.team_members where id = r.submitted_by),
      -- The partner whose logo the report carries (2026-10-06), else none.
      'partner', (select jsonb_build_object('name', p.name, 'logo', p.logo_data)
                    from public.report_partner_clients pc join public.report_partners p on p.id = pc.partner_id
                   where pc.client_id = r.client_id and p.active)),
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

-- END OF REPORT PARTNERS ------------------------------------------------------
