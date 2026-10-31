-- ===========================================================================
-- BRAND ANALYSIS VERSION DELETED — a version of a client's Brand analysis is
-- deleted for good, never the one Write with AI reads (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31, approving an audit of a client record's tabs):
-- every run of Run analysis is kept as the next version, and none could be
-- taken away; a report's versions and an Analytics read delete this way.
--
-- WHAT IT CHANGES
--   * `brand_analysis_delete(p_id)` (Clients: Brand Full Access, the client
--     in scope): removes one version. The latest confirmed version, which
--     Write with AI reads (`brand_analysis_brief`), is refused (`in-use`):
--     confirm another or withdraw its confirmation first. Filed
--     `client.brand` · Brand analysis: version n deleted. No restore.
--
-- ORDER: the pages, then this file in the SQL Editor (its body removes a
-- row, which the connector holds). Until it runs, Delete reads "This needs
-- a database update". Safe to run twice. Mirrored byte for byte in
-- supabase/schema.sql under the same banner.
--
-- ROLLBACK (SQL Editor): drop function public.brand_analysis_delete(uuid).
-- ===========================================================================

-- BRAND ANALYSIS VERSION DELETED ---------------------------------------------

create or replace function public.brand_analysis_delete(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  m      public.team_members := public.ops_me();
  a      public.brand_analyses;
  v_name text;
  v_last uuid;
begin
  if m.id is null or not public.allowed('clients.brand', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into a from public.brand_analyses x where x.id = p_id;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(a.client_id, 'manage') then return jsonb_build_object('error', 'client-scope'); end if;
  -- One client's versions at a time, so a confirmation made meanwhile is seen.
  select x.name into v_name from public.clients x where x.id = a.client_id for update;
  select x.id into v_last from public.brand_analyses x
   where x.client_id = a.client_id and x.confirmed_at is not null
   order by x.version desc limit 1;
  if v_last = a.id then return jsonb_build_object('error', 'in-use'); end if;
  delete from public.brand_analyses x where x.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'client.brand', v_name, 'Brand analysis: version ' || a.version || ' deleted');
  return jsonb_build_object('ok', true, 'version', a.version);
end $$;
revoke all on function public.brand_analysis_delete(uuid) from public, anon;
grant execute on function public.brand_analysis_delete(uuid) to authenticated;

-- END OF BRAND ANALYSIS VERSION DELETED --------------------------------------

select public.functions_tidy();
