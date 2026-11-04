-- ===========================================================================
-- INDUSTRIES, THE SQL EDITOR PART — Delete an industry no client holds
-- (2026-11-04)
-- ===========================================================================
-- Run in the Supabase SQL Editor after 2026-11-04-industries.sql (the
-- connector holds a statement naming delete). Until it runs, Delete reads
-- "This feature is not available yet."; Set inactive works.
--
-- `industry_delete(p_name)` (Business settings): removes an industry no
-- client holds (`in-use` with the count), filed `team.changed` under
-- Industries. Safe to run twice. Rollback: drop the function.
-- ===========================================================================

create or replace function public.industry_delete(p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_n int;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  perform pg_advisory_xact_lock(hashtextextended('industries', 0));
  if not exists (select 1 from public.industries i where i.name = p_name) then return jsonb_build_object('error', 'not-found'); end if;
  select count(*)::int into v_n from public.clients c where c.industry = p_name;
  if v_n > 0 then return jsonb_build_object('error', 'in-use', 'clients', v_n); end if;
  delete from public.industries i where i.name = p_name;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Industries', 'Deleted: ' || p_name);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.industry_delete(text) from public, anon;
grant execute on function public.industry_delete(text) to authenticated;

-- END OF INDUSTRIES, THE SQL EDITOR PART --------------------------------------

select public.functions_tidy();
