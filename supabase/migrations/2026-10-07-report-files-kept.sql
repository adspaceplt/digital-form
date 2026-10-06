-- ===========================================================================
-- REPORT FILES KEPT — each published version of a report keeps the PDF it
-- went out as, so a later change to how reports are drawn never changes a
-- report a client was sent, and every earlier version can be fetched again.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after SOCIAL MEDIA REPORTS and CLIENT SCOPE.
--
-- WHAT CHANGED (the user, 2026-10-06: "if our client received version at
-- (2026/10/06) but in the future maybe 2026/12/12 there is a new version, i
-- no longer can fetch back the 2026/10/06 version")
--   1. `sm_report_versions.file_key`, `file_at`, `file_by`: the PDF drawn
--      from the version once it is published, stored in the bucket under
--      `private/{client}/`, which is never served without a five-minute
--      signature. A file stands for the publish it was drawn after
--      (`file_at` not before `published_at`): a version taken off the portal
--      and published again keeps the next file drawn instead.
--   2. `sm_report_keep_file(p_version, p_key)`: Reports at Work, on a client
--      the colleague sees; the key must sit under the report's own client; a
--      version whose file stands answers `kept` with its own key and keeps
--      it.
--   3. `sm_report_file_key(p_version)`: what sign-download asks, as the
--      caller. A colleague at Reports View, or Clients View, on a client they
--      see: any version. A client's portal contact: only the version the
--      portal shows. Anybody else is answered `not-found`.
--   4. `portal_report` and `sm_report_file` say whether the version's file
--      stands (`kept`); `sm_report_file` also names the version.
--
-- ROLLBACK
--   Revoke execute on sm_report_keep_file(uuid, text) and
--   sm_report_file_key(uuid) from authenticated, then run portal_report from
--   SOCIAL MEDIA REPORTS and sm_report_file from CLIENT SCOPE again; the
--   columns may stay unused.
-- ===========================================================================

alter table public.sm_report_versions add column if not exists file_key text;
alter table public.sm_report_versions add column if not exists file_at timestamptz;
alter table public.sm_report_versions add column if not exists file_by text;

create or replace function public.sm_report_keep_file(p_version uuid, p_key text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v public.sm_report_versions;
  v_client uuid;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.sm_report_versions where id = p_version for update;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select r.client_id into v_client from public.sm_reports r where r.id = v.report_id;
  if v_client is null or not public.client_seen(v_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  if v.file_key is not null and v.file_at >= v.published_at then
    return jsonb_build_object('ok', true, 'kept', true, 'key', v.file_key);
  end if;
  if coalesce(p_key, '') !~ ('^private/' || v_client::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$') then
    return jsonb_build_object('error', 'bad-key');
  end if;
  update public.sm_report_versions set file_key = p_key, file_at = now(), file_by = me.name where id = v.id;
  return jsonb_build_object('ok', true, 'key', p_key);
end $$;
revoke all on function public.sm_report_keep_file(uuid, text) from public, anon;
grant execute on function public.sm_report_keep_file(uuid, text) to authenticated;

create or replace function public.sm_report_file_key(p_version uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  v public.sm_report_versions;
  v_client uuid;
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  select * into v from public.sm_report_versions where id = p_version;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select r.client_id into v_client from public.sm_reports r where r.id = v.report_id;
  if v_client is null then return jsonb_build_object('error', 'not-found'); end if;
  if public.is_team() then
    if not (public.allowed('reports', 'view') or public.allowed('clients', 'view'))
       or not public.client_seen(v_client, 'view') then
      return jsonb_build_object('error', 'not-found');
    end if;
  elsif v_client not in (select public.portal_clients())
     or v.withdrawn_at is not null
     or exists (select 1 from public.sm_report_versions x where x.report_id = v.report_id
                 and x.withdrawn_at is null and x.version_no > v.version_no) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v.file_key is null or v.file_at < v.published_at then return jsonb_build_object('error', 'not-kept'); end if;
  return jsonb_build_object('key', v.file_key);
end $$;
revoke all on function public.sm_report_file_key(uuid) from public, anon;
grant execute on function public.sm_report_file_key(uuid) to authenticated;

create or replace function public.portal_report(p_version uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  v public.sm_report_versions;
  cid uuid;
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  select * into v from public.sm_report_versions where id = p_version and withdrawn_at is null;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select client_id into cid from public.sm_reports where id = v.report_id;
  if cid is null or cid not in (select public.portal_clients()) then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.sm_report_versions x where x.report_id = v.report_id
              and x.withdrawn_at is null and x.version_no > v.version_no) then
    return jsonb_build_object('error', 'not-found');
  end if;
  return jsonb_build_object('snapshot', v.snapshot,
    'kept', v.file_key is not null and v.file_at >= v.published_at);
end $$;
revoke all on function public.portal_report(uuid) from public, anon;
grant execute on function public.portal_report(uuid) to authenticated;

create or replace function public.sm_report_file(p_id uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  r public.sm_reports;
  v public.sm_report_versions;
begin
  if not public.allowed('clients', 'view') and not public.allowed('reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.sm_report_versions x
   where x.report_id = p_id and x.withdrawn_at is null order by x.version_no desc limit 1;
  if v.id is not null then
    return jsonb_build_object('snapshot', v.snapshot, 'version_id', v.id,
      'kept', v.file_key is not null and v.file_at >= v.published_at);
  end if;
  if r.status <> 'confirmed' then return jsonb_build_object('error', 'not-finished'); end if;
  return jsonb_build_object('snapshot', public.sm_report_snapshot(p_id, false));
end $$;
grant execute on function public.sm_report_file(uuid) to authenticated;

-- END OF REPORT FILES KEPT ----------------------------------------------------
