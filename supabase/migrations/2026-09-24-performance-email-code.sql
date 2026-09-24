-- ===========================================================================
-- MY PERFORMANCE BEHIND AN EMAIL CODE — a second lock a member may put on
-- their own reviews.
-- 2026-09-24. Safe to run twice. Run after 2026-09-24-performance-reviews.sql.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/perf.js compares the two.
--
-- WHAT THIS IS. Asked for by the user on 2026-09-24 ("a second guard layer
-- ... OTP / link to view the performance section"), with their decisions:
-- each person switches it on for themselves, and it is a 6-digit code sent
-- to their email. While it is on, the member's own functions answer
-- `code-needed` unless the session was verified by an email code in the
-- last 15 minutes. The proof is the session's own `amr` claim, which the
-- auth server writes when a code is verified (`verifyOtp`), so nothing the
-- browser sends can fake it. Turning the lock off needs a fresh code too,
-- so an unattended open laptop cannot switch it off.
--
-- The email is Supabase's own sign-in email, so its template must print the
-- code: Authentication, Emails, Magic Link, add {{ .Token }}. See
-- docs/PERFORMANCE-SETUP.md.
--
-- ROLLBACK
--   drop function if exists public.perf_guard_set(boolean), public.perf_guard_info(),
--     public.perf_guarded(uuid), public.perf_code_fresh();
--   alter table public.perf_people drop column if exists email_code;
--   and re-run perf_mine, perf_dispute and perf_acknowledge from
--   2026-09-24-performance-reviews.sql.
-- ===========================================================================

alter table public.perf_people add column if not exists email_code boolean not null default false;

/* The session was verified by an email code (or an email link, which the
   auth server records the same way) in the last 15 minutes. Read from the
   signed token, never from anything the page passes in. */
create or replace function public.perf_code_fresh()
returns boolean
language sql stable set search_path = public as $$
  select coalesce((
    select bool_or(a ->> 'method' in ('otp', 'magiclink')
                   and (a ->> 'timestamp') ~ '^[0-9]+$'
                   and (a ->> 'timestamp')::bigint >= extract(epoch from now())::bigint - 900)
      from jsonb_array_elements(case when jsonb_typeof(auth.jwt() -> 'amr') = 'array'
                                     then auth.jwt() -> 'amr' else '[]'::jsonb end) a), false)
$$;

/* Whether a member has put the lock on their own reviews. */
create or replace function public.perf_guarded(p_member uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select email_code from public.perf_people where team_member_id = p_member), false)
$$;

/* What the page needs to draw the lock: on or off, fresh or not, and the
   address the code goes to. */
create or replace function public.perf_guard_info()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  return jsonb_build_object('on', public.perf_guarded(m.id), 'fresh', public.perf_code_fresh(),
                            'email', m.email);
end $$;

/* The member's own switch. On at any time; off only with a fresh code. */
create or replace function public.perf_guard_set(p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not coalesce(p_on, false) and public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  insert into public.perf_people (team_member_id, email_code, updated_at)
  values (m.id, coalesce(p_on, false), now())
  on conflict (team_member_id) do update set email_code = excluded.email_code, updated_at = now();
  perform public.perf_log(null, m.id, 'email-code', jsonb_build_object('on', coalesce(p_on, false)));
  return jsonb_build_object('ok', true, 'on', coalesce(p_on, false));
end $$;

/* The member's own functions, each refusing while the lock is on and the
   code is not fresh. Otherwise identical to 2026-09-24-performance-reviews. */
create or replace function public.perf_mine()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  return jsonb_build_object('reviews', coalesce((
    select jsonb_agg(public.perf_json(r, false) order by r.period desc)
      from public.perf_reviews r
     where r.team_member_id = m.id and r.status <> 'draft'), '[]'::jsonb));
end $$;

create or replace function public.perf_dispute(p_review uuid, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews; it jsonb; n integer := 0; itm text; bid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status <> 'released' or exists (select 1 from public.perf_disputes d
                                        where d.review_id = r.id and d.version = r.version) then
    return jsonb_build_object('error', 'dispute-closed');
  end if;
  if r.dispute_until <= now() then return jsonb_build_object('error', 'window-closed'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('error', 'nothing-disputed');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    itm := it ->> 'item';
    if itm is null or itm not in ('output', 'accuracy', 'delivery', 'client', 'comms', 'initiative', 'breach') then
      return jsonb_build_object('error', 'bad-item');
    end if;
    if coalesce(btrim(it ->> 'reason'), '') = '' then return jsonb_build_object('error', 'reason-needed', 'item', itm); end if;
    bid := null;
    if itm = 'breach' then
      begin bid := (it ->> 'breach_id')::uuid; exception when others then bid := null; end;
      if bid is null or not exists (select 1 from public.perf_breaches b
                                     where b.id = bid and b.team_member_id = m.id
                                       and b.period = r.period and b.voided_at is null) then
        return jsonb_build_object('error', 'bad-item');
      end if;
    end if;
    insert into public.perf_disputes (review_id, version, item, breach_id, reason)
    values (r.id, r.version, itm, bid, btrim(it ->> 'reason'));
    n := n + 1;
  end loop;
  update public.perf_reviews set status = 'disputed', rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'disputed', jsonb_build_object('items', n));
  perform public.perf_notify(r.reviewer_id, 'perf.disputed',
    m.name || ' disputed ' || public.perf_month_word(r.period) || '.',
    'perf.disputed.' || r.id || '.' || r.version);
  return public.perf_json(r, false);
end $$;

create or replace function public.perf_acknowledge(p_review uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status = 'acknowledged' or r.status = 'final' then return public.perf_json(r, false); end if;
  if r.status = 'disputed' then return jsonb_build_object('error', 'open-dispute'); end if;
  update public.perf_reviews set status = 'acknowledged', acknowledged_at = now(),
         dispute_until = least(dispute_until, now()), rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'acknowledged', '{}'::jsonb);
  return public.perf_json(r, false);
end $$;

revoke all on function public.perf_code_fresh() from public, anon, authenticated;
revoke all on function public.perf_guarded(uuid) from public, anon, authenticated;
revoke all on function public.perf_guard_info() from public, anon, authenticated;
revoke all on function public.perf_guard_set(boolean) from public, anon, authenticated;
revoke all on function public.perf_mine() from public, anon, authenticated;
revoke all on function public.perf_dispute(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.perf_acknowledge(uuid) from public, anon, authenticated;
grant execute on function public.perf_guard_info() to authenticated;
grant execute on function public.perf_guard_set(boolean) to authenticated;
grant execute on function public.perf_mine() to authenticated;
grant execute on function public.perf_dispute(uuid, jsonb) to authenticated;
grant execute on function public.perf_acknowledge(uuid) to authenticated;

-- END OF MY PERFORMANCE BEHIND AN EMAIL CODE ---------------------------------
