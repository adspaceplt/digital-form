-- ===========================================================================
-- PIECE DATES REQUIRED — every new content piece carries its draft due, its
-- due date and its post date; none may be left blank.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js (§43) compares
-- the two. Runs after THREE DATES A POST.
--
-- WHAT CHANGED (the user, 2026-10-09: "force to have required first draft
-- date, due date and the post date (as required) to curb delays")
--   1. `ops_create_pieces` refuses a piece missing any of the three dates
--      with `dates-required` and the piece's place (`piece`, from 1); the
--      pieces before it are undone, as any refusal part way is. Tasks made
--      before keep their dates as they are; Add task (an everyday task),
--      templates, copies, repeats and a month's report tasks are unchanged.
--
-- ROLLBACK
--   Run ops_create_pieces from THREE DATES A POST again.
-- ===========================================================================

/* The New sheet's one act: the pieces, each through ops_create_task, and the
   repeat on every one of them, all or none; each piece with its three
   dates. */
create or replace function public.ops_create_pieces(p_payload jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m      public.team_members;
  n      integer;
  pc     jsonb;
  i      integer := 0;
  w      integer;
  k      integer;
  inweek integer;
  per    text;
  first_day date;
  last_off integer;
  spread boolean;
  base   jsonb;
  one    jsonb;
  made   jsonb := '[]'::jsonb;
  rep    jsonb;
  rule   jsonb;
  ids    uuid[] := '{}';
  gen    jsonb := '[]'::jsonb;
  pp     text;
  said   text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_payload -> 'pieces') is distinct from 'array' then
    return jsonb_build_object('error', 'bad-count');
  end if;
  n := jsonb_array_length(p_payload -> 'pieces');
  if n < 1 or n > 60 then return jsonb_build_object('error', 'bad-count'); end if;
  rep := case when jsonb_typeof(p_payload -> 'repeat') = 'object' then p_payload -> 'repeat' end;
  if rep is not null then
    if coalesce(rep ->> 'frequency', '') not in ('weekly', 'monthly', 'custom') then
      return jsonb_build_object('error', 'bad-frequency');
    end if;
    if rep ->> 'frequency' = 'custom' and coalesce((rep ->> 'interval_days')::integer, 0) < 1 then
      return jsonb_build_object('error', 'interval-required');
    end if;
  end if;

  /* What every piece shares: whose it is, what kind, who does it. A piece
     names its own description, format, week and dates; only a sheet's one
     piece carries a brief. */
  base := jsonb_strip_nulls(jsonb_build_object(
    'scope', p_payload ->> 'scope', 'client_id', p_payload ->> 'client_id',
    'engagement_id', p_payload ->> 'engagement_id',
    'code_period', p_payload ->> 'code_period',
    'task_type', p_payload ->> 'task_type',
    'owner_id', p_payload ->> 'owner_id',
    'priority_level', p_payload -> 'priority_level',
    'complexity', p_payload ->> 'complexity',
    'description', case when n = 1 then p_payload ->> 'description' end));
  per := p_payload ->> 'code_period';
  if per ~ '^\d{4}-\d{2}$' and coalesce(p_payload ->> 'scope', 'client') <> 'internal' then
    first_day := (per || '-01')::date;
    last_off := ((first_day + interval '1 month')::date - first_day) - 1;
  end if;
  /* Only a repeat needs a day to count from; plain pieces take the dates
     typed on their rows and nothing else. */
  spread := first_day is not null and rep is not null;
  base := base || jsonb_build_object('dates_as_given', true);

  begin
    for pc in select x from jsonb_array_elements(p_payload -> 'pieces') x loop
      i := i + 1;
      w := least(5, greatest(1, coalesce((pc ->> 'code_week')::integer, 1)));
      one := base || jsonb_strip_nulls(jsonb_build_object(
        'content_desc', nullif(btrim(coalesce(pc ->> 'content_desc', '')), ''),
        'deliverable_type', nullif(pc ->> 'deliverable_type', ''),
        'code_week', case when first_day is not null then w end));
      /* Every piece carries the three dates typed on its row: the draft
         due (ready for AQC review), the due date (to the client) and the
         post date (2026-10-06). */
      one := one || jsonb_strip_nulls(jsonb_build_object(
        'first_draft_due_at', nullif(pc ->> 'first_draft_due_at', ''),
        'final_due_at', nullif(pc ->> 'final_due_at', ''),
        'publish_at', nullif(pc ->> 'publish_at', '')));
      /* None of the three may be left blank (2026-10-09): a piece without
         its dates is refused by its place, and nothing is made. */
      if not (one ? 'first_draft_due_at' and one ? 'final_due_at' and one ? 'publish_at') then
        raise exception using message = jsonb_build_object('error', 'dates-required', 'piece', i)::text;
      end if;
      /* A tentative day inside the piece's week, the week's pieces spread
         across its seven days, so the calendar has somewhere to put each one
         and a repeat a day to count from; the content meeting fixes the real
         date. Never past the month's last day, which only week 5 reaches. */
      if spread and not (one ? 'publish_at') then
        select count(*) filter (where least(5, greatest(1, coalesce((y ->> 'code_week')::integer, 1))) = w),
               count(*) filter (where least(5, greatest(1, coalesce((y ->> 'code_week')::integer, 1))) = w and o < i)
          into inweek, k
          from jsonb_array_elements(p_payload -> 'pieces') with ordinality as a(y, o);
        one := one || jsonb_build_object('publish_at',
          (first_day + least((w - 1) * 7 + (k * 7) / greatest(inweek, 1), last_off))::timestamptz);
      end if;
      one := public.ops_create_task(one, case when p_idem is null then null else p_idem || ':' || i end);
      if one ? 'error' then raise exception using message = one::text; end if;
      made := made || jsonb_build_object('id', one ->> 'id', 'code', one ->> 'code', 'title', one ->> 'title');
      ids := ids || (one ->> 'id')::uuid;
      if rep is not null then
        rule := public.ops_set_recurring((one ->> 'id')::uuid, jsonb_strip_nulls(jsonb_build_object(
          'frequency', rep ->> 'frequency',
          'interval_days', case when rep ->> 'frequency' = 'custom' then rep -> 'interval_days' end,
          'ends_on', nullif(rep ->> 'ends_on', ''),
          'max_count', rep -> 'max_count')));
        if rule ? 'error' then raise exception using message = rule::text; end if;
      end if;
    end loop;
  exception when raise_exception then
    /* A refusal part way leaves nothing behind: the block's writes are
       undone and the refusal is answered as it was given. */
    said := sqlerrm;
    begin
      return said::jsonb;
    exception when others then
      return jsonb_build_object('error', said);
    end;
  end;

  /* What the new rules already owe is made now rather than tomorrow morning. */
  if rep is not null then
    foreach pp in array public.ops_recurring_periods() loop
      gen := gen || public.ops_generate_recurring(pp,
        array(select r.id from public.ops_recurring_rules r where r.active and r.source_task_id = any (ids)));
    end loop;
  end if;
  return jsonb_build_object('count', n, 'tasks', made, 'repeats', gen);
end $$;
grant execute on function public.ops_create_pieces(jsonb, text) to authenticated;

-- END OF PIECE DATES REQUIRED ------------------------------------------------

select public.functions_tidy();
