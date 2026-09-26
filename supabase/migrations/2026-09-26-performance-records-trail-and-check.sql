-- ===========================================================================
-- PERFORMANCE RECORDS, THEIR TRAIL AND THEIR CHECK — a downloaded record is
-- stamped, listed in Documents and answered by the verify page, and the
-- Activity record reads its steps.
-- 2026-09-26. Safe to run twice. Run after
-- 2026-09-26-department-and-role-on-the-team.sql. Rollback at the foot.
-- Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/perf.js compares the two.
--
-- WHAT CHANGED, the user's decisions of 2026-09-26:
--  1. A download is filed before the file is drawn and the filing is what the
--     file prints (perf_printed answers the server's time, who, and the
--     record's released, acknowledged and finalised steps). The PDF carries
--     no signature lines; acknowledgement is the portal's.
--  2. A score save names what it changed (perf_save files each scorecard and
--     rate from and to, then the notes or the plan), and a save that changed
--     nothing is not filed.
--  3. The Activity record reads the steps of reviews (perf_activity): when,
--     the step, whose month, who. Never a score, a grade, a breach or a
--     dispute's words. For team.performance at View, without the master
--     code; the caller's own review is left out.
--  4. A record downloaded at least once is listed under HR Letters in
--     Documents (perf_register) for somebody holding both register.hr and
--     team.performance at View, the caller's own left out, with its
--     reference, colleague and month and nothing of its content.
--  5. The verify page answers a downloaded record's reference as an HR
--     Letter, Valid (Replaced while it is reopened as a draft), dated by its
--     release; never the name or the score. Every reference is also found
--     typed with dashes for slashes, the way a file name carries it.
--  6. My performance accepts a fresh passkey (Face ID, Touch ID) as well as a
--     fresh emailed code: perf_code_fresh reads either in the signed token.
--
-- ROLLBACK
--   drop function if exists public.perf_activity(integer), public.perf_register();
--   and re-run perf_save and perf_printed from
--   2026-09-24-performance-reviews.sql, perf_code_fresh from
--   2026-09-24-performance-email-code.sql, and verify_serial from
--   supabase/schema.sql's Documents Register section. A stamped event keeps
--   its detail; nothing is lost by the rollback.
-- ===========================================================================

/* 1. The download, filed first. */
/* A download is filed before the file is drawn, and the filing is what the
   file prints: the server's time, who took it, and the steps the record has
   been through (released, acknowledged, finalised), each by name, address
   and time. A refused filing is a refused file. */
create or replace function public.perf_printed(p_review uuid, p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews; ev_id uuid; ev_at timestamptz;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  select * into r from public.perf_reviews where id = p_review;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.team_member_id <> m.id and public.perf_check(p_token, 'view') is not null then
    return jsonb_build_object('error', 'denied');
  end if;
  if r.team_member_id = m.id and r.status = 'draft' then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.perf_events (review_id, team_member_id, actor_id, actor_email, kind, detail)
  values (r.id, r.team_member_id, m.id, m.email, 'printed', jsonb_build_object('version', r.version))
  returning id, created_at into ev_id, ev_at;
  return jsonb_build_object('ok', true, 'id', ev_id, 'at', ev_at, 'by', m.name, 'email', m.email,
    'trail', coalesce((
      select jsonb_agg(jsonb_build_object('kind', t.kind, 'at', t.created_at, 'by', t.who, 'email', t.actor_email)
                       order by t.created_at)
        from (select distinct on (pe.kind) pe.kind, pe.created_at, pe.actor_email,
                     coalesce(tm.name, pe.actor_email) as who
                from public.perf_events pe
                left join public.team_members tm on tm.id = pe.actor_id
               where pe.review_id = r.id
                 and ((pe.kind = 'released' and r.released_at is not null)
                   or (pe.kind = 'acknowledged' and r.acknowledged_at is not null)
                   or (pe.kind = 'finalised' and r.finalised_at is not null))
               order by pe.kind, pe.created_at desc) t), '[]'::jsonb));
end $$;

/* 2. A save names what it changed. */
create or replace function public.perf_save(p_token text, p_member uuid, p_period date,
                                            p_payload jsonb, p_rev integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; r public.perf_reviews; p date := date_trunc('month', p_period)::date;
  sc jsonb := coalesce(p_payload -> 'scores', '{}'::jsonb);
  rt jsonb := coalesce(p_payload -> 'rates', '{}'::jsonb);
  k text; v jsonb; mx numeric; rb date; was public.perf_reviews; changed jsonb;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if not exists (select 1 from public.team_members where id = p_member and active) then
    return jsonb_build_object('error', 'not-found');
  end if;
  if jsonb_typeof(sc) <> 'object' or jsonb_typeof(rt) <> 'object'
     or (p_payload ? 'notes' and jsonb_typeof(p_payload -> 'notes') <> 'object') then
    return jsonb_build_object('error', 'bad-payload');
  end if;
  for k, v in select key, value from jsonb_each(sc) loop
    mx := case k when 'output' then 25 when 'accuracy' then 15 when 'delivery' then 15
                 when 'client' then 20 when 'comms' then 15 when 'initiative' then 10 end;
    if mx is null then return jsonb_build_object('error', 'bad-score', 'key', k); end if;
    if jsonb_typeof(v) <> 'null' then
      if jsonb_typeof(v) <> 'number' then return jsonb_build_object('error', 'bad-score', 'key', k, 'max', mx); end if;
      if (v #>> '{}')::numeric not between 0 and mx or round((v #>> '{}')::numeric, 1) <> (v #>> '{}')::numeric then
        return jsonb_build_object('error', 'bad-score', 'key', k, 'max', mx);
      end if;
    end if;
  end loop;
  for k, v in select key, value from jsonb_each(rt) loop
    mx := case k when 'pacing' then 1000 when 'posting' then 100 when 'timeline' then 100
                 when 'satisfaction' then 100 when 'sla' then 100 end;
    if mx is null then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
    if jsonb_typeof(v) <> 'null' then
      if jsonb_typeof(v) <> 'number' then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
      if (v #>> '{}')::numeric not between 0 and mx then return jsonb_build_object('error', 'bad-rate', 'key', k); end if;
    end if;
  end loop;
  if coalesce(p_payload ->> 'review_by', '') <> '' then
    begin
      rb := (p_payload ->> 'review_by')::date;
    exception when others then
      return jsonb_build_object('error', 'bad-date');
    end;
  end if;

  select * into r from public.perf_reviews where team_member_id = p_member and period = p for update;
  if r.id is null then
    insert into public.perf_reviews (team_member_id, period) values (p_member, p)
    on conflict (team_member_id, period) do nothing;
    select * into r from public.perf_reviews where team_member_id = p_member and period = p for update;
    perform public.perf_log(r.id, p_member, 'started', '{}'::jsonb);
  elsif p_rev is not null and r.rev <> p_rev then
    return jsonb_build_object('error', 'stale', 'record', public.perf_json(r, true));
  end if;
  /* The scores are the draft's. What the month asks of the person next (the
     improvement, the date it is reviewed by, the step or reward) is written
     at the 1-1 and may be filled in until the record is final. */
  if r.status = 'final' or (r.status <> 'draft'
       and (p_payload - 'improvement' - 'review_by' - 'reward_step') <> '{}'::jsonb) then
    return jsonb_build_object('error', 'not-draft');
  end if;

  was := r;
  update public.perf_reviews set
    s_output     = case when sc ? 'output'     then (sc ->> 'output')::numeric     else s_output end,
    s_accuracy   = case when sc ? 'accuracy'   then (sc ->> 'accuracy')::numeric   else s_accuracy end,
    s_delivery   = case when sc ? 'delivery'   then (sc ->> 'delivery')::numeric   else s_delivery end,
    s_client     = case when sc ? 'client'     then (sc ->> 'client')::numeric     else s_client end,
    s_comms      = case when sc ? 'comms'      then (sc ->> 'comms')::numeric      else s_comms end,
    s_initiative = case when sc ? 'initiative' then (sc ->> 'initiative')::numeric else s_initiative end,
    r_posting      = case when rt ? 'posting'      then (rt ->> 'posting')::numeric      else r_posting end,
    r_timeline     = case when rt ? 'timeline'     then (rt ->> 'timeline')::numeric     else r_timeline end,
    r_satisfaction = case when rt ? 'satisfaction' then (rt ->> 'satisfaction')::numeric else r_satisfaction end,
    r_pacing       = case when rt ? 'pacing'       then (rt ->> 'pacing')::numeric       else r_pacing end,
    r_sla          = case when rt ? 'sla'          then (rt ->> 'sla')::numeric          else r_sla end,
    notes       = case when p_payload ? 'notes' then coalesce(p_payload -> 'notes', '{}'::jsonb) else notes end,
    improvement = case when p_payload ? 'improvement' then nullif(btrim(p_payload ->> 'improvement'), '') else improvement end,
    review_by   = case when p_payload ? 'review_by' then rb else review_by end,
    reward_step = case when p_payload ? 'reward_step' then nullif(btrim(p_payload ->> 'reward_step'), '') else reward_step end,
    updated_at = now(), rev = rev + 1
  where id = r.id
  returning * into r;
  /* What the save changed, named: each scorecard and rate whose value moved,
     from and to, then whether the notes or the plan moved. A save that moved
     nothing is not filed. */
  select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'from', c.a, 'to', c.b) order by c.n), '[]'::jsonb)
    into changed
    from (values (1, 'output', was.s_output, r.s_output), (2, 'accuracy', was.s_accuracy, r.s_accuracy),
                 (3, 'delivery', was.s_delivery, r.s_delivery), (4, 'client', was.s_client, r.s_client),
                 (5, 'comms', was.s_comms, r.s_comms), (6, 'initiative', was.s_initiative, r.s_initiative),
                 (7, 'posting', was.r_posting, r.r_posting), (8, 'timeline', was.r_timeline, r.r_timeline),
                 (9, 'satisfaction', was.r_satisfaction, r.r_satisfaction), (10, 'pacing', was.r_pacing, r.r_pacing),
                 (11, 'sla', was.r_sla, r.r_sla)) as c(n, key, a, b)
   where c.a is distinct from c.b;
  if coalesce(was.notes, '{}'::jsonb) is distinct from coalesce(r.notes, '{}'::jsonb) then
    changed := changed || jsonb_build_array(jsonb_build_object('key', 'notes'));
  end if;
  if was.improvement is distinct from r.improvement or was.review_by is distinct from r.review_by
     or was.reward_step is distinct from r.reward_step then
    changed := changed || jsonb_build_array(jsonb_build_object('key', 'plan'));
  end if;
  if jsonb_array_length(changed) > 0 then
    perform public.perf_log(r.id, p_member, 'scored', jsonb_build_object('changed', changed));
  end if;
  return public.perf_json(r, true);
end $$;

/* 3. The Activity record's Performance tab. */
create or replace function public.perf_activity(p_limit integer default 200)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me_row public.team_members;
begin
  me_row := public.ops_me();
  if me_row.id is null or not public.ops_granted('team.performance', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object(
             'at', e.created_at, 'kind', e.kind, 'member', tm.name, 'period', rv.period,
             'actor', e.actor_email, 'actor_name', ac.name) order by e.created_at desc)
      from (select pe.* from public.perf_events pe
             where pe.kind in ('released', 'disputed', 'decided', 'acknowledged',
                               'finalised', 'reopened', 'returned', 'printed')
               and pe.team_member_id is distinct from me_row.id
             order by pe.created_at desc
             limit greatest(1, least(coalesce(p_limit, 200), 500))) e
      left join public.team_members tm on tm.id = e.team_member_id
      left join public.perf_reviews rv on rv.id = e.review_id
      left join public.team_members ac on ac.id = e.actor_id), '[]'::jsonb));
end $$;

revoke all on function public.perf_activity(integer) from public, anon, authenticated;
grant execute on function public.perf_activity(integer) to authenticated;

/* 4. Documents. */
/* The records Documents lists: downloaded at least once, and read by
   somebody holding both HR Letters and Performance at View. */
create or replace function public.perf_register()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare me_row public.team_members;
begin
  me_row := public.ops_me();
  if me_row.id is null or not public.register_may('hr', 'view')
     or not public.ops_granted('team.performance', 'view') then
    return jsonb_build_object('rows', '[]'::jsonb);
  end if;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', rv.id, 'serial', rv.serial, 'member_id', rv.team_member_id,
             'name', tm.name, 'staff_code', tm.staff_code, 'period', rv.period,
             'month', public.perf_month_word(rv.period), 'status', rv.status,
             'released_at', rv.released_at,
             'downloaded_at', (select min(pe.created_at) from public.perf_events pe
                                where pe.review_id = rv.id and pe.kind = 'printed'))
           order by rv.period desc, tm.name)
      from public.perf_reviews rv
      join public.team_members tm on tm.id = rv.team_member_id
     where rv.serial is not null and rv.team_member_id is distinct from me_row.id
       and exists (select 1 from public.perf_events pe where pe.review_id = rv.id and pe.kind = 'printed')),
    '[]'::jsonb));
end $$;

/* 5. The verify page. */
/* One exact reference in, the kind, the date and whether it stands. A
   reference typed with dashes for slashes (the file name's form) is the same
   reference, but an exact match is always answered first. A performance
   record is answered once it has been downloaded, as an HR Letter. */
create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  sd text;
  d public.documents%rowtype;
  l public.client_documents%rowtype;
  rv public.perf_reviews%rowtype;
begin
  if length(s) < 3 or length(s) > 40 then return jsonb_build_object('found', false); end if;
  sd := replace(s, '/', '-');
  select * into d from public.documents
   where upper(serial) = s or replace(upper(serial), '/', '-') = sd
   order by (upper(serial) = s) desc, (voided_at is null) desc, created_at desc limit 1;
  if d.id is not null then
    return jsonb_build_object('found', true, 'serial', d.serial,
      'kind', case when d.family = 'hr' then 'HR Letter' else d.kind end,
      'issued_at', d.issued_at,
      'state', case when d.voided_at is null then 'valid' else 'voided' end);
  end if;
  select * into l from public.client_documents
   where upper(number) = s or replace(upper(number), '/', '-') = sd
   order by (upper(number) = s) desc limit 1;
  if l.id is not null then
    return jsonb_build_object('found', true, 'serial', l.number, 'kind', 'Letter of Offer',
      'issued_at', l.issued_at,
      'state', case when l.voided_at is not null then 'voided'
                    when l.superseded_by is not null then 'replaced'
                    else 'valid' end);
  end if;
  select * into rv from public.perf_reviews pr
   where (upper(pr.serial) = s or replace(upper(pr.serial), '/', '-') = sd)
     and exists (select 1 from public.perf_events pe where pe.review_id = pr.id and pe.kind = 'printed')
   limit 1;
  if rv.id is not null then
    return jsonb_build_object('found', true, 'serial', rv.serial, 'kind', 'HR Letter',
      'issued_at', rv.released_at,
      'state', case when rv.status = 'draft' then 'replaced' else 'valid' end);
  end if;
  return jsonb_build_object('found', false);
end $$;

/* 6. A passkey unlocks My performance too. */
/* The session was verified in the last 15 minutes by an email code or link,
   or by a passkey (Face ID, Touch ID, the device password). Read from the
   signed token, never from anything the page passes in. */
create or replace function public.perf_code_fresh()
returns boolean
language sql stable set search_path = public as $$
  select coalesce((
    select bool_or(a ->> 'method' in ('otp', 'magiclink', 'webauthn', 'passkey')
                   and (a ->> 'timestamp') ~ '^[0-9]+$'
                   and (a ->> 'timestamp')::bigint >= extract(epoch from now())::bigint - 900)
      from jsonb_array_elements(case when jsonb_typeof(auth.jwt() -> 'amr') = 'array'
                                     then auth.jwt() -> 'amr' else '[]'::jsonb end) a), false)
$$;
revoke all on function public.perf_code_fresh() from public, anon, authenticated;

revoke all on function public.perf_activity(integer) from public, anon, authenticated;
revoke all on function public.perf_register() from public, anon, authenticated;
grant execute on function public.perf_activity(integer) to authenticated;
grant execute on function public.perf_register() to authenticated;
grant execute on function public.verify_serial(text) to anon, authenticated;

-- END OF PERFORMANCE RECORDS, THEIR TRAIL AND THEIR CHECK --------------------
