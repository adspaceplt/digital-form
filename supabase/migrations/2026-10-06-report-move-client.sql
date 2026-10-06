-- ===========================================================================
-- REPORT MOVED TO ANOTHER CLIENT — an admin moves a draft report started
-- under a temporary client to the client it belongs to.
-- 2026-10-06. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after the REPORTS sections (sm_report_log, the guard's
-- adspace.sm_fn switch) and AI DRAFT SUBJECT (ai_drafts.client_id).
--
-- WHAT CHANGED (the user, 2026-10-06)
--   The team starts a report under a temporary client while a client's
--   record is pending. `sm_report_move(p_id, p_client)` (an admin's alone)
--   moves a draft to an Active client; its accounts, posts, ads and text
--   go with it, since they hang off the report. A report past draft keeps
--   its client (`not-draft`); the target must be Active (`not-active`) and
--   hold no report of the same kind whose period shares a day (`exists`).
--   The report's AI uses follow it (`ai_drafts.client_id`). The move is
--   filed under both clients as a save, from and to.
--
-- ROLLBACK
--   In the SQL Editor, remove the function sm_report_move(uuid, uuid).
-- ===========================================================================

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
  select * into c from public.clients where id = p_client;
  if c.id is null or c.stage <> 'active' then return jsonb_build_object('error', 'not-active'); end if;
  if c.id = r.client_id then return jsonb_build_object('ok', true, 'client_id', c.id); end if;
  if exists (select 1 from public.sm_reports x
              where x.client_id = c.id and x.kind = r.kind and x.id <> r.id
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

-- END OF REPORT MOVED TO ANOTHER CLIENT -------------------------------------
