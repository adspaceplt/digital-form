-- 2026-10-11. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. It holds a `delete` in a function body, so it runs in the SQL Editor.
--
-- ROLLBACK
--   Re-run the REPORTS section's sm_report_delete (refusing `has-versions`).
--
-- ===========================================================================
-- A SEEN REPORT DELETED — Reports Full Access deletes any report, a published
-- one included: the report, every version and its rows go, and the client's
-- portal no longer lists it (the user, 2026-10-11: "delete permanently =
-- totally gone"). The period is typed back as before.
-- ===========================================================================

/* A report goes with its period typed back, at Reports Full Access. One the
   client has read goes too, with every version (the user, 2026-10-11): it
   leaves the client portal, and the record says it had been published. The
   PDF kept in storage stays, as every stored file does. */
create or replace function public.sm_report_delete(p_id uuid, p_confirm text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  word text;
  cname text;
  seen integer;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  word := public.sm_period_word(r.period_start, r.period_end);
  if lower(btrim(coalesce(p_confirm, ''))) <> lower(word) then return jsonb_build_object('error', 'confirm-mismatch'); end if;
  select count(*) into seen from public.sm_report_versions where report_id = p_id;
  select name into cname from public.clients where id = r.client_id;
  perform set_config('adspace.sm_fn', 'on', true);
  delete from public.sm_reports where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'report.deleted', cname, word || ' · v' || r.version_no ||
          case when seen > 0 then ' · had been published, ' || seen || case when seen = 1 then ' version' else ' versions' end ||
                                  ' removed from the client portal' else '' end);
  return jsonb_build_object('ok', true, 'versions', seen);
end $$;
revoke all on function public.sm_report_delete(uuid, text) from public, anon;
grant execute on function public.sm_report_delete(uuid, text) to authenticated;

-- END OF A SEEN REPORT DELETED ----------------------------------------------

select public.functions_tidy();
