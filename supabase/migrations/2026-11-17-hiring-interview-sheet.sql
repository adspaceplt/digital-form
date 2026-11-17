-- ===========================================================================
-- HIRING INTERVIEW SHEET — the team's Interviewer's Sheet, kept by each
-- interviewer on a candidate (2026-11-17)
-- ===========================================================================
-- WHY (the user, 2026-11-17, with NEW_Interview_Sheet.pdf: "add on on top of
-- the interview sheet, since the interview might take some time, it
-- shouldnt be shown like a card, it should at least a slide window"): each
-- colleague on a candidate fills the team's sheet during the interview in a
-- panel beside the record, saved as they go: a rating out of 10, internal
-- remarks, MBTI, and the sheet's questions. The scorecard's 1 to 5 scores
-- and the recommendation stay `hiring_scores`, saved from the same panel.
-- And "the invite interview, shouldnt be jusst time within a same day":
-- the times offered may now spread over 14 days (`hiring_invite_days`, its
-- seeded 3 moved to 14 where nobody changed it; Settings, Portal: Hiring).
--
-- WHAT IT CHANGES
--   * `hiring_sheets` (candidate, colleague, rating, answers): RLS on, no
--     policy, no grant; goes with its candidate (cascade), so the retention
--     run and Delete take it.
--   * `hiring_sheet_keys()` (the sheet's fields, the page's list held equal
--     by tests/hiringsql.js), `hiring_sheet_save(p_id, p_rating,
--     p_answers)`, `hiring_sheets_of(p_id)`: anyone on the candidate reads
--     every sheet; each colleague writes their own.
--   * Never to an AI service (HR-SPEC decision 10).
--
-- ORDER: this file (connector), then the pages. Safe to run twice.
-- ROLLBACK: remove the three functions and the table; set the setting back.
-- ===========================================================================

-- HIRING INTERVIEW SHEET -------------------------------------------------------

create table if not exists public.hiring_sheets (
  candidate_id   uuid not null references public.hiring_candidates(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id) on delete cascade,
  rating         int check (rating is null or rating between 1 and 10),
  answers        jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (candidate_id, team_member_id)
);
alter table public.hiring_sheets enable row level security;
revoke all on table public.hiring_sheets from public, anon, authenticated;

/* Times spread over 14 days: only the seeded figure moves, never one the
   team set. */
update public.app_settings set value = 14
 where key = 'hiring_invite_days' and from_date = date '2023-08-14' and value = 3
   and not exists (select 1 from public.app_settings s where s.key = 'hiring_invite_days' and s.from_date > date '2023-08-14');

/* The sheet's fields, in its order. */
create or replace function public.hiring_sheet_keys()
returns text[] language sql immutable set search_path = public as $$
  select array['remarks', 'mbti', 'why_role', 'about', 'academics', 'experience', 'hobbies', 'strengths',
               'future', 'ambition', 'company', 'found', 'why_us', 'why_hire', 'others', 'general']
$$;
revoke all on function public.hiring_sheet_keys() from public, anon, authenticated;

create or replace function public.hiring_sheet_save(p_id uuid, p_rating int, p_answers jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  v_clean jsonb := '{}'::jsonb;
  v_k text;
  v_v text;
  v_max int;
  v_was public.hiring_sheets;
  x public.hiring_sheets;
begin
  if me.id is null or v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage in ('hired', 'closed') then return jsonb_build_object('error', 'closed'); end if;
  if p_rating is not null and p_rating not between 1 and 10 then return jsonb_build_object('error', 'bad-rating'); end if;
  if jsonb_typeof(coalesce(p_answers, '{}'::jsonb)) <> 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  for v_k in select jsonb_object_keys(coalesce(p_answers, '{}'::jsonb)) loop
    if not (v_k = any (public.hiring_sheet_keys())) then return jsonb_build_object('error', 'bad-request'); end if;
    v_v := btrim(coalesce(p_answers ->> v_k, ''));
    v_max := 2000;
    if v_k = 'mbti' then v_max := 20; end if;
    if char_length(v_v) > v_max then return jsonb_build_object('error', 'too-long', 'field', v_k); end if;
    if v_v <> '' then v_clean := v_clean || jsonb_build_object(v_k, v_v); end if;
  end loop;
  select * into v_was from public.hiring_sheets where candidate_id = c.id and team_member_id = me.id;
  insert into public.hiring_sheets (candidate_id, team_member_id, rating, answers)
  values (c.id, me.id, p_rating, v_clean)
  on conflict (candidate_id, team_member_id) do update set rating = excluded.rating, answers = excluded.answers, updated_at = now()
  returning * into x;
  /* Saved as the interviewer types: filed once, when the sheet is started. */
  if v_was.candidate_id is null then perform public.hiring_log(c.id, 'candidate.scored', 'Interview sheet started'); end if;
  return jsonb_build_object('ok', true, 'updated_at', x.updated_at);
end $$;
revoke all on function public.hiring_sheet_save(uuid, int, jsonb) from public, anon;
grant execute on function public.hiring_sheet_save(uuid, int, jsonb) to authenticated;

create or replace function public.hiring_sheets_of(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null or public.hiring_role(p_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true, 'sheets', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', t.id, 'name', t.name, 'mine', t.id = me.id, 'rating', x.rating, 'answers', x.answers, 'updated_at', x.updated_at))
      order by (t.id <> me.id), x.updated_at)
    from public.hiring_sheets x join public.team_members t on t.id = x.team_member_id where x.candidate_id = p_id), '[]'::jsonb));
end $$;
revoke all on function public.hiring_sheets_of(uuid) from public, anon;
grant execute on function public.hiring_sheets_of(uuid) to authenticated;

-- END OF HIRING INTERVIEW SHEET ------------------------------------------------

select public.functions_tidy();
