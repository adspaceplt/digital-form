-- ===========================================================================
-- THREE DATES A POST — every post line carries its draft due, its due date
-- and its post date, and a client's request for changes moves the due date
-- to the next day by itself.
-- 2026-10-06. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js (§42) compares
-- the two. Runs after APP SETTINGS and PIECE DATES AS TYPED.
--
-- WHAT CHANGED (the user, 2026-10-06)
--   1. `ops_create_pieces` takes each piece's draft due (ready for AQC
--      review), due date (to the client) and post date, on every piece:
--      several pieces once got the due date alone. Nothing is worked out.
--   2. `revision_due_days` (1) is a setting an admin changes in My Work's
--      Due dates, from a day on (`app_settings_set` restated with the key).
--   3. `ops_tasks_revision_due` (after update of stage_key): a task moved
--      into Revision (Client) takes as its due date the day that many days
--      after today (MYT), where that is later than the date it holds, filed
--      as a due change for a client request. The draft due is left alone.
--
-- ROLLBACK
--   Run ops_create_pieces from PIECE DATES AS TYPED and app_settings_set
--   from APP SETTINGS again; in the SQL Editor, remove the trigger
--   ops_tasks_revision_due. The setting's row may stay.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select 'revision_due_days', date '2023-08-14', 1
 where not exists (select 1 from public.app_settings s where s.key = 'revision_due_days');

/* The New sheet's one act: the pieces, each through ops_create_task, and the
   repeat on every one of them, all or none. */
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

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days'];
  v_moved text[] := '{}';
begin
  if not public.allowed('admin') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, 2) <> v_v
       or (v_k = 'lead_followup_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'proposal_followup_days' and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      insert into public.app_settings (key, from_date, value, set_by, set_at)
      values (v_k, p_from, v_v, v_me.id, now())
      on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      v_name := case v_k when 'lead_followup_hours' then 'A lead waits' when 'proposal_followup_days' then 'A proposal waits'
        when 'sst_pct' then 'SST' when 'term_1_3' then '1 to 3 months' when 'term_4_5' then '4 and 5 months'
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 23 months' when 'term_24' then '24 months and more'
        when 'revision_due_days' then 'Revision due' else 'Report due' end;
      v_unit := case when v_k = 'lead_followup_hours' then ' hours' when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days') then ' days'
        else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || trim(to_char(v_was, 'FM999999990.99'), '.') || v_unit || ' → ' ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || v_unit || ' · from ' || public.register_day(p_from));
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_read() to anon, authenticated;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;

/* A client's request for changes sends the work back with a new due date:
   the day `revision_due_days` after today in Malaysia, stored as a typed
   date is (that day at 00:00 UTC), and only where it is later than the due
   date the task holds. */
create or replace function public.ops_tasks_revision_due()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_day date; v_due timestamptz;
begin
  if new.stage_key <> 'revision_client' or old.stage_key is not distinct from new.stage_key then return null; end if;
  v_day := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_due := ((v_day + coalesce(public.app_setting('revision_due_days', v_day), 1)::integer)::timestamp) at time zone 'UTC';
  if new.current_final_due_at is not null and new.current_final_due_at >= v_due then return null; end if;
  update public.ops_tasks set current_final_due_at = v_due, updated_at = now() where id = new.id;
  perform public.ops_log(new.id, 'due_changed',
    jsonb_build_object('kind', 'final', 'value', new.current_final_due_at),
    jsonb_build_object('kind', 'final', 'value', v_due),
    jsonb_build_object('reason', 'client_request', 'note', 'The client asked for changes.', 'auto', true));
  return null;
end $$;
revoke all on function public.ops_tasks_revision_due() from public, anon, authenticated;
create or replace trigger ops_tasks_revision_due after update of stage_key on public.ops_tasks
  for each row when (new.stage_key = 'revision_client' and old.stage_key is distinct from new.stage_key)
  execute function public.ops_tasks_revision_due();

-- END OF THREE DATES A POST --------------------------------------------------
