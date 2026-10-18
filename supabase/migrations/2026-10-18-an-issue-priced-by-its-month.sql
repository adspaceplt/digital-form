-- ===========================================================================
-- AN ISSUE PRICED BY ITS MONTH — each issue's points are read with the
-- settings of the month it belongs to, as the month's total is. 2026-10-18.
-- Safe to run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/perf.js compares the two.
--
-- WHAT CHANGED (second audit, item 12)
--   perf_calc adds up a month's issues with that month's breach points
--   (perf_setting at r.period), but perf_breaches_json, the list of issues
--   the review sheet, the member's page and the printed record show, priced
--   each line, and named the VIC multiplier, with today's settings; so did
--   the figure perf_breach_log answers and files. Once the points changed
--   from a later quarter, an earlier month's lines no longer added up to
--   its total. All three now read the issue's own month (`p_period`, the
--   month the issue is logged into).
--
-- ROLLBACK
--   Run the perf_breaches_json definition of the VIC PERFORMANCE section and
--   the perf_breach_log definition of the MALAYSIA TIME IN THE DATABASE
--   section of supabase/schema.sql again.
-- ===========================================================================

create or replace function public.perf_breaches_json(p_member uuid, p_period date, p_with_void boolean)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'occurred_on', b.occurred_on, 'category', b.category,
           'severity', b.severity, 'repeated', b.repeated, 'late', b.late,
           'what', b.what, 'evidence', b.evidence,
           'deduction', public.perf_deduction_vic_at(b.severity, b.repeated, b.late, b.vic, p_period),
           'client_id', b.client_id, 'client_name', (select c.name from public.clients c where c.id = b.client_id),
           'vic', b.vic, 'vic_x', case when b.vic then public.perf_setting('ded_vic', p_period) end,
           'logged_by', (select name from public.team_members where id = b.logged_by),
           'logged_at', b.logged_at, 'voided_at', b.voided_at, 'void_reason', b.void_reason)
         order by b.occurred_on, b.logged_at), '[]'::jsonb)
    from public.perf_breaches b
   where b.team_member_id = p_member and b.period = p_period
     and (p_with_void or b.voided_at is null)
$$;

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
      'deduction', public.perf_deduction_vic_at(sev, rep, nb.late, nb.vic, p)));
  return jsonb_build_object('ok', true, 'id', nb.id, 'repeated', rep, 'vic', nb.vic,
    'deduction', public.perf_deduction_vic_at(sev, rep, nb.late, nb.vic, p), 'period', p);
end $$;

revoke all on function public.perf_breaches_json(uuid, date, boolean) from public, anon, authenticated;
revoke all on function public.perf_breach_log(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.perf_breach_log(text, uuid, jsonb) to authenticated;

-- END OF AN ISSUE PRICED BY ITS MONTH ---------------------------------------

select public.functions_tidy();
