-- ===========================================================================
-- NOTICE DELETE — a withdrawn notice can be deleted for good (the user,
-- 2026-10-10: "why notices cannot be deleted?").
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. It holds the word the connector stops on: run it in the SQL Editor.
--
-- WHAT CHANGED
--   `team_notice_delete(p_id)` (Team: Notices, as Withdraw) removes a
--   withdrawn notice and every colleague's copy of it from the bells, refused
--   `live` until it is withdrawn (Withdraw first, so nothing leaves a bell
--   without the team seeing it go), `not-found` once gone. A push already on
--   a phone stays there. Filed `team.changed` under subject Notices. There is
--   no restore.
--
-- ROLLBACK
--   Pages first (the ⋯ is drawn only on a withdrawn notice and names a
--   missing function "This needs a database update."), then remove the
--   function in the SQL Editor. A notice already deleted is gone.
-- ===========================================================================

create or replace function public.team_notice_delete(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v public.team_notices;
  n int;
begin
  if me.id is null or not public.ops_granted('team.notice', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.team_notices tn where tn.id = p_id for update;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v.withdrawn_at is null then return jsonb_build_object('error', 'live'); end if;
  delete from public.ops_notifications o where o.notice_id = v.id;
  get diagnostics n = row_count;
  delete from public.team_notices tn where tn.id = v.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Notices', 'Deleted: ' || v.title);
  return jsonb_build_object('ok', true, 'copies', n);
end $$;
revoke all on function public.team_notice_delete(uuid) from public, anon;
grant execute on function public.team_notice_delete(uuid) to authenticated;

-- END OF NOTICE DELETE ---------------------------------------------------------

select public.functions_tidy();
