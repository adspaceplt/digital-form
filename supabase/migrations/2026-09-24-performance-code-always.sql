-- ===========================================================================
-- MY PERFORMANCE ALWAYS ASKS FOR AN EMAIL CODE — the lock is no longer a
-- member's own switch.
-- 2026-09-24. Safe to run twice. Run after 2026-09-24-performance-email-code.sql.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/perf.js compares the two.
--
-- WHAT CHANGED. The user, on 2026-09-24: the page "mandatory requires otp
-- pin", so a tick to turn it on or off is useless. Every member's own
-- reviews now ask for a code emailed to them in the last 15 minutes, with
-- no switch: perf_guarded answers true for everybody and perf_guard_set
-- refuses to turn it off. The `email_code` column stays, unread, so the
-- rollback is two function bodies.
--
-- ROLLBACK
--   re-run perf_guarded and perf_guard_set from
--   2026-09-24-performance-email-code.sql.
-- ===========================================================================

/* Every member's reviews are behind the code. */
create or replace function public.perf_guarded(p_member uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select true
$$;

/* The switch is gone. Kept as a function so an open page from before this
   change is refused in words rather than by a missing function. */
create or replace function public.perf_guard_set(p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not coalesce(p_on, true) then return jsonb_build_object('error', 'always-on'); end if;
  return jsonb_build_object('ok', true, 'on', true);
end $$;

revoke all on function public.perf_guarded(uuid) from public, anon, authenticated;
revoke all on function public.perf_guard_set(boolean) from public, anon, authenticated;
grant execute on function public.perf_guard_set(boolean) to authenticated;

-- END OF MY PERFORMANCE ALWAYS ASKS FOR AN EMAIL CODE ------------------------
