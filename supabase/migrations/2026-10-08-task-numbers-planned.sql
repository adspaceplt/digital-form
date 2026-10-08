-- ===========================================================================
-- TASK NUMBERS FOLLOW THE PLAN — a client's month numbers its planned pieces
-- 01 to N, extras after them, and a number freed by a delete is used again.
-- 2026-10-08. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-08: "Make only deliverables based on pieces planned.
--   Extras or addons block the engagement selection … if delete then frees
--   up and can reuse serial … if its W1 then needs to be Week 1". The code's
--   NN was the client's highest for the month plus one, so a deleted piece
--   left a gap and the count stopped tallying with the plan. Now, under the
--   same advisory lock as `ops_next_seq`, trigger `ops_tasks_code_slot`
--   numbers a task as it is made:
--     - a Retainer piece (task_type `engagement`, not a report task) takes
--       the lowest number free from 01 to the month's `planned_count`; none
--       free is refused `plan-full` (with `planned`), so extras are Ad hoc,
--       Goodwill or Special;
--     - any other task takes the lowest free after `planned_count`;
--     - a month with nothing planned numbers from 01, lowest free first.
--   A task whose type moves between Retainer and the others is numbered
--   again the same way. A number typed by hand (`ops_set_code`) stays in its
--   range: a Retainer piece at or under the plan (`plan-range`), any other
--   task over it (`extra-range`). The code is always rebuilt from its month,
--   week and number (`ops_code_of`), so W1 is Week 1, and the title's code
--   follows it. Refusals are raised as the JSON the page reads.
--
-- ROLLBACK
--   drop trigger ops_tasks_code_slot on public.ops_tasks;
--   drop function public.ops_tasks_code_slot();
--   drop function public.ops_code_free(uuid, text, integer, integer, uuid);
--   drop function public.ops_code_retainer(text, text);
-- ===========================================================================

create or replace function public.ops_code_retainer(p_type text, p_source text)
returns boolean
language sql immutable set search_path = public as $$
  select coalesce(p_type, '') = 'engagement'
     and coalesce(p_source, '') not in ('report_social', 'report_ads')
$$;

create or replace function public.ops_code_free(
  p_client uuid, p_period text, p_from integer, p_to integer, p_except uuid)
returns integer
language sql stable set search_path = public as $$
  select min(n)::integer
    from generate_series(p_from, coalesce(p_to, p_from + (
           select count(*)::integer from public.ops_tasks o
            where coalesce(o.client_id, '00000000-0000-0000-0000-000000000000'::uuid)
                = coalesce(p_client, '00000000-0000-0000-0000-000000000000'::uuid)
              and o.code_period = p_period) + 1)) n
   where not exists (
     select 1 from public.ops_tasks o
      where coalesce(o.client_id, '00000000-0000-0000-0000-000000000000'::uuid)
          = coalesce(p_client, '00000000-0000-0000-0000-000000000000'::uuid)
        and o.code_period = p_period and o.code_seq = n
        and o.id is distinct from p_except)
$$;

create or replace function public.ops_tasks_code_slot()
returns trigger
language plpgsql set search_path = public as $$
declare
  v_planned integer;
  v_ret boolean;
  v_n integer;
  v_was text;
begin
  if new.code_seq is null or new.code_period is null or coalesce(new.code, '') = '' then
    return new;
  end if;
  v_was := case when tg_op = 'INSERT' then new.code else old.code end;
  select coalesce(e.planned_count, 0) into v_planned from public.ops_engagements e
   where e.client_id = new.client_id and e.period = new.code_period;
  v_planned := coalesce(v_planned, 0);
  v_ret := public.ops_code_retainer(new.task_type, new.source_type);
  if tg_op = 'INSERT'
     or (new.code_seq = old.code_seq and new.code_period = old.code_period
         and v_ret <> public.ops_code_retainer(old.task_type, old.source_type)) then
    perform pg_advisory_xact_lock(hashtext('ops_code:' || coalesce(new.client_id::text, 'internal') || ':' || new.code_period));
    if v_planned > 0 and v_ret then
      v_n := public.ops_code_free(new.client_id, new.code_period, 1, v_planned, new.id);
      if v_n is null then
        raise exception using message = jsonb_build_object('error', 'plan-full', 'planned', v_planned)::text;
      end if;
    else
      v_n := public.ops_code_free(new.client_id, new.code_period,
               case when v_planned > 0 then v_planned + 1 else 1 end, null, new.id);
    end if;
    new.code_seq := v_n;
  elsif (new.code_seq is distinct from old.code_seq or new.code_period is distinct from old.code_period)
        and v_planned > 0 then
    if v_ret and new.code_seq > v_planned then
      raise exception using message = jsonb_build_object('error', 'plan-range', 'planned', v_planned)::text;
    end if;
    if not v_ret and new.code_seq <= v_planned then
      raise exception using message = jsonb_build_object('error', 'extra-range', 'planned', v_planned)::text;
    end if;
  end if;
  new.code := public.ops_code_of(new.code_period, coalesce(new.code_week, 1), new.code_seq);
  if v_was is not null and new.code is distinct from v_was and left(coalesce(new.title, ''), length(v_was)) = v_was then
    new.title := new.code || substr(new.title, length(v_was) + 1);
  end if;
  return new;
end $$;
revoke all on function public.ops_tasks_code_slot() from public, anon, authenticated;
revoke all on function public.ops_code_free(uuid, text, integer, integer, uuid) from public, anon, authenticated;
revoke all on function public.ops_code_retainer(text, text) from public, anon, authenticated;

create or replace trigger ops_tasks_code_slot
  before insert or update of task_type, code_seq, code_week, code_period on public.ops_tasks
  for each row execute function public.ops_tasks_code_slot();

-- END OF TASK NUMBERS FOLLOW THE PLAN ---------------------------------------

select public.functions_tidy();
