-- ===========================================================================
-- CONFIRMED PERIODS HOLD THEIR MONTHS — a month inside a confirmed quarter or
-- bonus and trip period is neither reopened nor deleted until that period is
-- reopened. 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored
-- byte for byte in supabase/schema.sql under the same banner; tests/perf.js
-- compares the two.
--
-- WHAT CHANGED (second audit, item 8)
--   Confirm keeps a quarter's or a half's rewards as a snapshot in
--   perf_rewards, and pays on it. perf_reopen and perf_delete read nothing
--   of it, so a final month in a paid quarter could be reopened, rescored
--   and finalised again (or deleted) while the snapshot, and the payout,
--   stayed as confirmed. Both now refuse `period-confirmed`, naming the
--   quarter or the period (`kind`, `word`), while either is confirmed;
--   Reopen under Quarters or Bonus and trip (Manage) is the way through, as
--   it is for the department scores and the company figures.
--
-- ROLLBACK
--   Run the perf_reopen definition of the PERFORMANCE REVIEWS section and
--   the perf_delete definition of A PERFORMANCE RECORD CAN BE DELETED in
--   supabase/schema.sql again.
-- ===========================================================================

create or replace function public.perf_reopen(p_token text, p_review uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare err text; m public.team_members; r public.perf_reviews; w public.perf_rewards;
begin
  err := public.perf_check(p_token, 'manage');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status <> 'final' then return jsonb_build_object('error', 'not-final'); end if;
  /* A month inside a confirmed quarter or half is paid on that snapshot:
     the period is reopened first. */
  select * into w from public.perf_rewards x
   where (x.kind = 'quarter' and x.period = date_trunc('quarter', r.period)::date)
      or (x.kind = 'period' and x.period = public.perf_half(r.period))
   order by x.kind limit 1;
  if w.kind is not null then
    return jsonb_build_object('error', 'period-confirmed', 'kind', w.kind,
      'word', case w.kind when 'quarter' then public.perf_quarter_word(w.period) else public.perf_period_word(w.period) end);
  end if;
  perform public.perf_log(r.id, r.team_member_id, 'reopened',
    jsonb_build_object('reason', btrim(p_reason), 'was', public.perf_json(r, false)));
  update public.perf_reviews set status = 'draft', result = null, released_at = null,
         dispute_until = null, acknowledged_at = null, finalised_at = null, finalised_by = null,
         version = version + 1, rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_delete(p_token text, p_review uuid, p_confirm text, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_err     text;
  v_me      public.team_members;
  v_rev     public.perf_reviews;
  v_name    text;
  v_month   text;
  v_printed boolean;
  v_rw      public.perf_rewards;
begin
  v_err := public.perf_check(p_token, 'manage');
  if v_err is not null then return jsonb_build_object('error', v_err); end if;
  if not public.perf_is_admin() then return jsonb_build_object('error', 'admin-only'); end if;
  v_me := public.ops_me();
  select * into v_rev from public.perf_reviews pr where pr.id = p_review for update;
  if v_rev.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_rev.team_member_id = v_me.id then return jsonb_build_object('error', 'own-review'); end if;
  /* A month inside a confirmed quarter or half is paid on that snapshot:
     the period is reopened first. */
  select * into v_rw from public.perf_rewards x
   where (x.kind = 'quarter' and x.period = date_trunc('quarter', v_rev.period)::date)
      or (x.kind = 'period' and x.period = public.perf_half(v_rev.period))
   order by x.kind limit 1;
  if v_rw.kind is not null then
    return jsonb_build_object('error', 'period-confirmed', 'kind', v_rw.kind,
      'word', case v_rw.kind when 'quarter' then public.perf_quarter_word(v_rw.period) else public.perf_period_word(v_rw.period) end);
  end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select tm.name into v_name from public.team_members tm where tm.id = v_rev.team_member_id;
  v_month := public.perf_month_word(v_rev.period);
  if lower(regexp_replace(btrim(coalesce(p_confirm, '')), '\s+', ' ', 'g'))
     <> lower(regexp_replace(btrim(coalesce(v_name, '') || ' ' || v_month), '\s+', ' ', 'g')) then
    return jsonb_build_object('error', 'confirm-mismatch');
  end if;
  v_printed := exists (select 1 from public.perf_events pe where pe.review_id = v_rev.id and pe.kind = 'printed');

  insert into public.perf_deleted (team_member_id, period, serial, status, printed, released_at, deleted_by, reason)
  values (v_rev.team_member_id, v_rev.period, v_rev.serial, v_rev.status, v_printed, v_rev.released_at,
          v_me.id, btrim(p_reason));
  perform public.perf_log(null, v_rev.team_member_id, 'deleted',
    jsonb_build_object('period', v_rev.period, 'month', v_month, 'serial', v_rev.serial,
                       'status', v_rev.status, 'printed', v_printed, 'reason', btrim(p_reason)));
  delete from public.perf_reviews pr where pr.id = v_rev.id;
  return jsonb_build_object('ok', true, 'month', v_month, 'status', v_rev.status, 'printed', v_printed);
end $$;

revoke all on function public.perf_reopen(text, uuid, text) from public, anon, authenticated;
revoke all on function public.perf_delete(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.perf_reopen(text, uuid, text) to authenticated;
grant execute on function public.perf_delete(text, uuid, text, text) to authenticated;

-- END OF CONFIRMED PERIODS HOLD THEIR MONTHS --------------------------------

select public.functions_tidy();
