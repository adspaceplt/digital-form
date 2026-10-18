-- ===========================================================================
-- BREACH POINTS ADDED AS NUMBERS — an issue's points are kept to the decimal
-- the settings give, and the month's total is rounded once. 2026-10-18.
-- Safe to run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/perf.js compares the two.
--
-- WHAT CHANGED (second audit, item 11)
--   Breach points are settings to two decimals (perf_settings_set), but
--   perf_deduction_at returned an integer and perf_deduction_vic_at rounded
--   again after the VIC multiplier, so each issue was rounded on its own:
--   Level 1 at 2.5 taken twice cost 6, not 5, and a 75 month fell to 69,
--   below C at 70. perf_calc also cast the cap to a whole number.
--   * `perf_points_at(severity, repeated, late, vic, at)` (new, no page's to
--     call): an issue's points as a number, the multiplier on the exact sum.
--   * perf_calc adds them exactly, rounds the month's total once to the 0.1
--     step the scores take (so the final score is always one the page
--     shows), then applies the cap as a number. `deduction` and
--     `deduction_raw` may now carry one decimal; the page, the printed
--     record and the stand-in already read them as numbers. A final month
--     keeps the result it was finalised with.
--   * perf_breaches_json and perf_breach_log answer each issue's points to
--     the cent of a point (two decimals).
--   No live setting holds a decimal (checked 2026-10-18), so no month open
--   today reads differently.
--   perf_deduction_at and perf_deduction_vic_at stay as they were; nothing
--   in the last definitions calls them now.
--
-- ROLLBACK
--   Run the perf_calc and perf_breaches_json definitions of the VIC
--   PERFORMANCE section and the perf_breach_log definition of AN ISSUE
--   PRICED BY ITS MONTH in supabase/schema.sql again; perf_points_at may
--   stay (nothing else calls it).
-- ===========================================================================

/* An issue's points as a number, never rounded: the settings take two
   decimals and the VIC multiplier is applied to the exact sum. */
create or replace function public.perf_points_at(p_severity integer, p_repeated boolean, p_late boolean,
                                                 p_vic boolean, p_at date)
returns numeric
language sql stable security definer set search_path = public as $$
  select (- coalesce(case p_severity when 1 then public.perf_setting('ded_l1', p_at) when 2 then public.perf_setting('ded_l2', p_at)
                                    when 3 then public.perf_setting('ded_l3', p_at) when 4 then public.perf_setting('ded_l4', p_at) end, 0)
          - case when p_repeated then public.perf_setting('ded_repeat', p_at) else 0 end
          - case when p_late then public.perf_setting('ded_late', p_at) else 0 end)
         * case when p_vic then coalesce(public.perf_setting('ded_vic', p_at), 1) else 1 end
$$;
revoke all on function public.perf_points_at(integer, boolean, boolean, boolean, date) from public, anon, authenticated;

create or replace function public.perf_breaches_json(p_member uuid, p_period date, p_with_void boolean)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'occurred_on', b.occurred_on, 'category', b.category,
           'severity', b.severity, 'repeated', b.repeated, 'late', b.late,
           'what', b.what, 'evidence', b.evidence,
           'deduction', round(public.perf_points_at(b.severity, b.repeated, b.late, b.vic, p_period), 2),
           'client_id', b.client_id, 'client_name', (select c.name from public.clients c where c.id = b.client_id),
           'vic', b.vic, 'vic_x', case when b.vic then public.perf_setting('ded_vic', p_period) end,
           'logged_by', (select name from public.team_members where id = b.logged_by),
           'logged_at', b.logged_at, 'voided_at', b.voided_at, 'void_reason', b.void_reason)
         order by b.occurred_on, b.logged_at), '[]'::jsonb)
    from public.perf_breaches b
   where b.team_member_id = p_member and b.period = p_period
     and (p_with_void or b.voided_at is null)
$$;

create or replace function public.perf_calc(r public.perf_reviews)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  base numeric; raw_ded numeric; ded numeric; fin numeric; l3 boolean; l4 boolean;
  g text; cap integer; rk integer; prev public.perf_reviews; prev_g text; ok boolean;
  complete boolean; path text; ads boolean; bd text; bc text; bm text;
  rank_of constant text := 'ABCDE';
  v_cap numeric;
begin
  if r.status = 'final' and r.result is not null then return r.result; end if;
  complete := r.s_output is not null and r.s_accuracy is not null and r.s_delivery is not null
          and r.s_client is not null and r.s_comms is not null and r.s_initiative is not null;
  base := coalesce(r.s_output, 0) + coalesce(r.s_accuracy, 0) + coalesce(r.s_delivery, 0)
        + coalesce(r.s_client, 0) + coalesce(r.s_comms, 0) + coalesce(r.s_initiative, 0);
  /* Each issue's points exactly as the settings give them (two decimals,
     times the VIC multiplier), the month's total rounded once, to the 0.1
     step the scores take, before the cap. */
  select round(coalesce(sum(public.perf_points_at(severity, repeated, late, vic, r.period)), 0), 1),
         coalesce(bool_or(severity = 3), false), coalesce(bool_or(severity = 4), false)
    into raw_ded, l3, l4
    from public.perf_breaches
   where team_member_id = r.team_member_id and period = r.period and voided_at is null;
  v_cap := public.perf_setting('ded_cap', r.period);
  ded := greatest(raw_ded, -v_cap);
  fin := greatest(0, least(100, base + ded));
  g := public.perf_grade_at(fin, r.period);
  cap := case when l4 then 4 when l3 then 2 else 0 end;
  rk := greatest(position(g in rank_of), cap);
  g := substr(rank_of, rk, 1);

  select * into prev from public.perf_reviews
   where team_member_id = r.team_member_id and period = (r.period - interval '1 month')::date
     and status <> 'draft';
  if prev.id is not null then
    prev_g := (public.perf_calc(prev)) ->> 'grade';
  end if;
  ok := (g in ('A', 'B') or (g = 'C' and prev_g is distinct from 'C')) and not l3 and not l4;
  path := case when g = 'E' or l3 or l4 then 'accountability' when g = 'D' then 'development' end;

  ads := coalesce((select runs_ads from public.perf_people where team_member_id = r.team_member_id), false);
  bd := (select b from unnest(array[public.perf_band(r.r_posting, 95), public.perf_band(r.r_timeline, 90)]) b
          where b is not null order by position(b in 'green amber red') desc limit 1);
  bc := (select b from unnest(array[public.perf_band(r.r_satisfaction, 90),
                                    case when ads then public.perf_pacing_band(r.r_pacing) end]) b
          where b is not null order by position(b in 'green amber red') desc limit 1);
  bm := public.perf_band(r.r_sla, 90);

  return jsonb_build_object(
    'complete', complete, 'base', base, 'deduction', ded, 'deduction_raw', raw_ded,
    'final', fin, 'cap', v_cap,
    'points', jsonb_build_object('1', public.perf_setting('ded_l1', r.period), '2', public.perf_setting('ded_l2', r.period),
                                 '3', public.perf_setting('ded_l3', r.period), '4', public.perf_setting('ded_l4', r.period),
                                 'repeat', public.perf_setting('ded_repeat', r.period), 'late', public.perf_setting('ded_late', r.period),
                                 'vic', public.perf_setting('ded_vic', r.period)),
    'raw_grade', public.perf_grade_at(fin, r.period), 'grade', g,
    'grade_word', public.perf_grade_word(g),
    'capped', case when rk > position(public.perf_grade_at(fin, r.period) in rank_of) then (case when l4 then 'D' else 'B' end) end,
    'l3', l3, 'l4', l4, 'review', l4,
    'eligible', ok, 'previous_grade', prev_g,
    'path', path,
    'suggested', jsonb_build_object(
      'delivery', case bd when 'green' then 15 when 'amber' then 12 when 'red' then 7.5 end,
      'delivery_band', bd,
      'client', case bc when 'green' then 20 when 'amber' then 16 when 'red' then 10 end,
      'client_band', bc,
      'comms', case bm when 'green' then 15 when 'amber' then 12 when 'red' then 7.5 end,
      'comms_band', bm));
end $$;

create or replace function public.perf_breach_log(p_token text, p_member uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; on_ date; p date; cat text; sev integer; rep boolean;
  st text; nb public.perf_breaches; cl uuid;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if not exists (select 1 from public.team_members where id = p_member and active) then
    return jsonb_build_object('error', 'not-found');
  end if;
  begin on_ := (p_payload ->> 'occurred_on')::date; exception when others then on_ := null; end;
  if on_ is null or on_ > (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'bad-date'); end if;
  cat := p_payload ->> 'category';
  if cat is null or cat not in ('client', 'delivery', 'compliance', 'asset') then
    return jsonb_build_object('error', 'bad-category');
  end if;
  sev := case when (p_payload ->> 'severity') ~ '^[1-4]$' then (p_payload ->> 'severity')::integer end;
  if sev is null then return jsonb_build_object('error', 'bad-severity'); end if;
  if coalesce(btrim(p_payload ->> 'what'), '') = '' then return jsonb_build_object('error', 'what-needed'); end if;
  /* The client it concerns, optional (2026-10-15): a VIC client's issue
     counts double, stamped at logging. */
  if nullif(p_payload ->> 'client_id', '') is not null then
    begin cl := (p_payload ->> 'client_id')::uuid; exception when others then cl := null; end;
    if cl is null or not exists (select 1 from public.clients c where c.id = cl) then
      return jsonb_build_object('error', 'bad-client');
    end if;
  end if;
  p := date_trunc('month', on_)::date;
  select status into st from public.perf_reviews where team_member_id = p_member and period = p;
  if st is not null and st <> 'draft' then
    return jsonb_build_object('error', 'month-released', 'month', public.perf_month_word(p));
  end if;
  /* The same kind of breach earlier in the same quarter is a repeat, unless
     the reviewer says otherwise. */
  rep := case when p_payload ? 'repeated' and jsonb_typeof(p_payload -> 'repeated') = 'boolean'
              then (p_payload ->> 'repeated')::boolean
              else exists (select 1 from public.perf_breaches b
                            where b.team_member_id = p_member and b.category = cat
                              and b.voided_at is null
                              and date_trunc('quarter', b.occurred_on) = date_trunc('quarter', on_)
                              and b.occurred_on <= on_) end;
  insert into public.perf_breaches (team_member_id, occurred_on, period, category, severity,
                                    repeated, late, what, evidence, logged_by, client_id)
  values (p_member, on_, p, cat, sev, rep, coalesce((p_payload ->> 'late')::boolean, false),
          btrim(p_payload ->> 'what'), nullif(btrim(p_payload ->> 'evidence'), ''), m.id, cl)
  returning * into nb;
  perform public.perf_log((select id from public.perf_reviews where team_member_id = p_member and period = p),
    p_member, 'breach_logged', jsonb_build_object('breach', nb.id, 'category', cat, 'severity', sev,
      'repeated', rep, 'late', nb.late, 'vic', nb.vic,
      'deduction', round(public.perf_points_at(sev, rep, nb.late, nb.vic, p), 2)));
  return jsonb_build_object('ok', true, 'id', nb.id, 'repeated', rep, 'vic', nb.vic,
    'deduction', round(public.perf_points_at(sev, rep, nb.late, nb.vic, p), 2), 'period', p);
end $$;

revoke all on function public.perf_breaches_json(uuid, date, boolean) from public, anon, authenticated;
revoke all on function public.perf_calc(public.perf_reviews) from public, anon, authenticated;
revoke all on function public.perf_breach_log(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.perf_breach_log(text, uuid, jsonb) to authenticated;

-- END OF BREACH POINTS ADDED AS NUMBERS -------------------------------------

select public.functions_tidy();
