-- ===========================================================================
-- DRAFT WITH AI LEFT — how many drafts a colleague has left on a report,
-- shown beside Draft with AI.
-- 2026-10-01. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   `ai_draft_left(p_report)`: Reports at Work. Reads `ai_drafts` as
--   `ai_draft_claim` counts it, writing nothing: what is left on the
--   report (one draft, else none for a colleague who is not an admin; five
--   in 24 hours for an admin), for the colleague (twenty in 24 hours) and
--   for the team (sixty in 24 hours), the least of the three as `left`, the
--   scope that sets it and its limit, and, where nothing is left, when the
--   next draft is free. A failed press is not counted.
--
-- ROLLBACK
--   drop function if exists public.ai_draft_left(uuid);
-- ===========================================================================

create or replace function public.ai_draft_left(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := now() - interval '24 hours';
  is_adm boolean;
  n_report integer; n_member integer; n_team integer;
  at_report timestamptz; at_member timestamptz; at_team timestamptz;
  l_report integer; l_member integer; l_team integer; l_min integer;
  v_scope text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  is_adm := coalesce(m.is_admin, false);
  select count(*), min(d.created_at) into n_report, at_report from public.ai_drafts d
   where d.report_id = p_report and d.created_at > since and d.outcome <> 'failed';
  if is_adm then
    l_report := greatest(0, 5 - n_report);
  elsif exists (select 1 from public.ai_drafts d where d.report_id = p_report and d.outcome <> 'failed') then
    l_report := 0;
  else
    l_report := 1;
  end if;
  select count(*), min(d.created_at) into n_member, at_member from public.ai_drafts d
   where d.team_member_id = m.id and d.created_at > since and d.outcome <> 'failed';
  l_member := greatest(0, 20 - n_member);
  select count(*), min(d.created_at) into n_team, at_team from public.ai_drafts d
   where d.created_at > since and d.outcome <> 'failed';
  l_team := greatest(0, 60 - n_team);
  l_min := least(l_report, l_member, l_team);
  v_scope := case when l_min = l_report then case when is_adm then 'report' else 'redraft' end
                  when l_min = l_member then 'person' else 'team' end;
  return jsonb_build_object(
    'left', l_min, 'scope', v_scope,
    'limit', case v_scope when 'redraft' then 1 when 'report' then 5 when 'person' then 20 else 60 end,
    'report', l_report, 'person', l_member, 'team', l_team, 'admin', is_adm,
    'next', case when l_min > 0 or v_scope = 'redraft' then null
                 when v_scope = 'report' then at_report + interval '24 hours'
                 when v_scope = 'person' then at_member + interval '24 hours'
                 else at_team + interval '24 hours' end);
end $$;

revoke all on function public.ai_draft_left(uuid) from public, anon, authenticated;
grant execute on function public.ai_draft_left(uuid) to authenticated;

-- END OF DRAFT WITH AI LEFT --------------------------------------------------
