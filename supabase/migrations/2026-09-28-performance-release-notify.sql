-- ===========================================================================
-- RELEASE WITH OR WITHOUT TELLING — a month is released with a tick for
-- whether the member is notified.
-- 2026-09-28. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/perf.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-09-27: "when releasing the performance review
-- could you give an optional notification tick, to notify or not to notify,
-- to the team member. So we wont need to specifically notify them when i
-- issue for June July and August 2026 and also for future months if
-- applicable"):
--   `perf_release` takes `p_notify` (true unless the page says otherwise).
--   Unticked, the release writes no notification: nothing in the bell, and
--   so nothing on the member's phone. The release itself, its reference, its
--   dispute window and its history row are unchanged; the history row says
--   whether the member was told. The member still reads the released month
--   on My performance whenever they open it.
--   The three-argument version is dropped first: PostgREST cannot choose
--   between two versions a call fits.
--
-- ROLLBACK
--   drop function if exists public.perf_release(text, uuid, integer, boolean);
--   Re-run perf_release from THE PERFORMANCE SYSTEM.
-- ===========================================================================

drop function if exists public.perf_release(text, uuid, integer);

create or replace function public.perf_release(p_token text, p_review uuid, p_rev integer, p_notify boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; tm public.team_members;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if p_rev is not null and r.rev <> p_rev then
    return jsonb_build_object('error', 'stale', 'record', public.perf_json(r, true));
  end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft'); end if;
  if not (public.perf_calc(r) ->> 'complete')::boolean then
    return jsonb_build_object('error', 'incomplete');
  end if;
  select * into tm from public.team_members where id = r.team_member_id;
  if r.serial is null and coalesce(btrim(tm.staff_code), '') = '' then
    return jsonb_build_object('error', 'no-staff-code');
  end if;
  update public.perf_reviews set status = 'released', released_at = now(),
         dispute_until = now() + interval '3 days', reviewer_id = m.id,
         serial = coalesce(serial, 'ADHR/' || upper(btrim(tm.staff_code)) || '/PR' || to_char(period, 'YYMM')),
         rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'released',
    jsonb_build_object('version', r.version, 'notified', coalesce(p_notify, true)));
  if coalesce(p_notify, true) then
    perform public.perf_notify(r.team_member_id, 'perf.released',
      'Your ' || public.perf_month_word(r.period) || ' performance review is ready.',
      'perf.released.' || r.id || '.' || r.version);
  end if;
  return public.perf_json(r, true);
end $$;
revoke all on function public.perf_release(text, uuid, integer, boolean) from public, anon;
grant execute on function public.perf_release(text, uuid, integer, boolean) to authenticated;

-- END OF RELEASE WITH OR WITHOUT TELLING -------------------------------------
