-- ===========================================================================
-- A CHECK-IN KEEPS ITS HALF MONTH — a health check-in is saved into the half
-- month its sheet showed, or refused in words (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 18): `health_checkin_save` filed the answers under
-- the half month of the moment they reached the database, so a sheet opened
-- for 1 to 15 October and saved after midnight on the 16th filed them, unseen,
-- under 16 to 31 October.
--
-- WHAT IT CHANGES
--   * `health_checkin_save(p_scores, p_note, p_half)`: the page names the
--     half month its sheet showed; one that is no longer the current half is
--     refused `stale-half` with the current one, and nothing is kept. Every
--     other refusal is as before.
--   * The old `health_checkin_save(p_scores, p_note)` stays for a page loaded
--     before this one and saves into the current half, as before (no drop:
--     the connector holds a drop).
--
-- ORDER: this file, then the pages. Safe to run twice.
-- Rollback: `revoke` and `drop function public.health_checkin_save(jsonb,
-- text, date)` in the SQL Editor; the page then reads "This needs a database
-- update" on Save until it is rolled back too.
-- ===========================================================================

create or replace function public.health_checkin_save(p_scores jsonb, p_note text, p_half date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; g jsonb; k text; v numeric; h date;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  m := public.ops_me();
  if not public.health_agreed(m.id) then return jsonb_build_object('error', 'no-consent'); end if;
  h := public.health_half(public.health_today());
  if p_half is distinct from h then
    return jsonb_build_object('error', 'stale-half', 'half', h, 'half_end', public.health_half_end(h));
  end if;
  if jsonb_typeof(p_scores) is distinct from 'object' then return jsonb_build_object('error', 'incomplete'); end if;
  foreach k in array array['body', 'mind', 'sleep', 'energy', 'workload'] loop
    if jsonb_typeof(p_scores -> k) is distinct from 'number' then
      return jsonb_build_object('error', 'incomplete', 'item', k);
    end if;
    v := (p_scores ->> k)::numeric;
    if v < 1 or v > 5 or v <> trunc(v) then return jsonb_build_object('error', 'bad-score', 'item', k); end if;
  end loop;
  if char_length(coalesce(p_note, '')) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  insert into public.health_checkins (team_member_id, half, body, mind, sleep, energy, workload, note)
  values (m.id, h, (p_scores ->> 'body')::smallint, (p_scores ->> 'mind')::smallint,
          (p_scores ->> 'sleep')::smallint, (p_scores ->> 'energy')::smallint,
          (p_scores ->> 'workload')::smallint, nullif(btrim(coalesce(p_note, '')), ''))
  on conflict (team_member_id, half) do update
     set body = excluded.body, mind = excluded.mind, sleep = excluded.sleep, energy = excluded.energy,
         workload = excluded.workload, note = excluded.note, updated_at = now();
  return public.health_mine();
end $$;
revoke all on function public.health_checkin_save(jsonb, text, date) from public, anon, authenticated;
grant execute on function public.health_checkin_save(jsonb, text, date) to authenticated;

-- END OF A CHECK-IN KEEPS ITS HALF MONTH ------------------------------------

select public.functions_tidy();
