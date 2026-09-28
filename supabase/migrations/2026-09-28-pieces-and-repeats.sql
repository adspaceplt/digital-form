-- ===========================================================================
-- PIECES AND REPEATS — one sheet makes a month's pieces and their repeat, and
-- repeats are made without anybody pressing Run.
-- 2026-09-28. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/ops.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-09-28: "why bulk add still necessary? Why not
-- just at the create / new task or content deliverable Optional repeat", then
-- "1 and 2 proceed"):
--   1. `ops_create_pieces(p_payload, p_idem)`: the New sheet's one act. Its
--      pieces (each a description, a format and a week; a sheet's only piece
--      may carry its own dates) are made through `ops_create_task` in one
--      transaction, all or none. Where there is more than one piece, or a
--      repeat, a piece with no publish date takes a tentative one inside its
--      week, as Bulk add did. An optional `repeat` sets the same rule on every
--      piece (`ops_set_recurring`) and makes at once what already falls due.
--      The same press twice is the same act.
--   2. `ops_generate_recurring` makes nothing on or before the day of the task
--      a rule copies: that task is the first occurrence. Before this, a rule
--      run for its own month copied its task onto its task's own day.
--   3. `ops_set_recurring` keeps a task's week only on a monthly rule; a weekly
--      or every-N-days copy takes the week of its own date.
--   4. Repeats run themselves. When a client's month is confirmed (its meeting
--      set or marked not applicable), that client's repeats for the month are
--      made at once, as the person confirming (`ops_engagements_confirmed`).
--      Every morning at 00:10 Malaysia time `ops_recurring_daily()` makes what
--      falls due this month, and next month in the last seven days
--      (`ops_recurring_periods()`), each rule as the colleague who set it (else
--      its task's owner) with that colleague's own access. Run repeating tasks
--      and Bulk add leave the page; `ops_generate_month` stays for the record.
--
-- ROLLBACK
--   select cron.unschedule('ops-repeats-daily');
--   drop trigger if exists ops_engagements_confirmed on public.ops_engagements;
--   drop function if exists public.ops_engagements_confirmed();
--   drop function if exists public.ops_recurring_daily();
--   drop function if exists public.ops_create_pieces(jsonb, text);
--   drop function if exists public.ops_recurring_periods();
--   Re-run ops_set_recurring from THE OPERATIONS SYSTEM, PHASE 4 and
--   ops_generate_recurring from EVERY TASK IN A CONFIRMED MONTH.
-- ===========================================================================

create or replace function public.ops_set_recurring(p_task uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  t public.ops_tasks;
  r public.ops_recurring_rules;
  freq text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_tasks where id = p_task;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;

  select * into r from public.ops_recurring_rules where source_task_id = p_task and active;
  if coalesce((p_payload ->> 'active')::boolean, true) = false then
    if r.id is not null then
      update public.ops_recurring_rules set active = false, updated_at = now() where id = r.id;
      perform public.ops_log(p_task, 'recurrence_off', null, null, '{}'::jsonb);
    end if;
    return jsonb_build_object('ok', true, 'active', false);
  end if;

  freq := coalesce(p_payload ->> 'frequency', 'monthly');
  if freq not in ('weekly', 'monthly', 'custom') then return jsonb_build_object('error', 'bad-frequency'); end if;
  if freq = 'custom' and coalesce((p_payload ->> 'interval_days')::integer, 0) < 1 then
    return jsonb_build_object('error', 'interval-required');
  end if;

  if r.id is null then
    insert into public.ops_recurring_rules
      (name, client_id, template_id, owner_id, frequency, day_of_month, source_task_id,
       interval_days, ends_on, max_count, code_week, created_by)
    values (public.ops_title(t), t.client_id, t.template_id,
            (select team_member_id from public.ops_task_assignees
              where task_id = p_task and responsibility = 'owner' and ended_at is null),
            freq, (p_payload ->> 'day_of_month')::integer, p_task,
            (p_payload ->> 'interval_days')::integer, (p_payload ->> 'ends_on')::date,
            (p_payload ->> 'max_count')::integer,
            coalesce((p_payload ->> 'code_week')::integer, case when freq = 'monthly' then t.code_week end),
            m.id)
    returning * into r;
    perform public.ops_log(p_task, 'recurrence_set', null, to_jsonb(r) - 'id', '{}'::jsonb);
  else
    update public.ops_recurring_rules set
      frequency = freq, day_of_month = (p_payload ->> 'day_of_month')::integer,
      interval_days = (p_payload ->> 'interval_days')::integer,
      ends_on = (p_payload ->> 'ends_on')::date, max_count = (p_payload ->> 'max_count')::integer,
      code_week = coalesce((p_payload ->> 'code_week')::integer, case when freq = 'monthly' then r.code_week end),
      updated_at = now()
    where id = r.id returning * into r;
    perform public.ops_log(p_task, 'recurrence_set', null, to_jsonb(r) - 'id', '{}'::jsonb);
  end if;
  return to_jsonb(r);
end $$;
grant execute on function public.ops_set_recurring(uuid, jsonb) to authenticated;

create or replace function public.ops_generate_recurring(
  p_period text, p_rules uuid[] default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  r     public.ops_recurring_rules;
  src   public.ops_tasks;
  made  integer := 0;
  skip  integer := 0;
  key   text;
  first_day date;
  last_day date;
  anchor date;
  d     date;
  stepd integer;
  one   jsonb;
  wk    integer;
  held  integer := 0;
  ccl   uuid;
  mon   public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
  first_day := (p_period || '-01')::date;
  last_day := (first_day + interval '1 month' - interval '1 day')::date;

  for r in select * from public.ops_recurring_rules
            where active and (p_rules is null or id = any (p_rules))
              and (source_task_id is null or public.ops_may_see_task(source_task_id)) loop
    if r.source_task_id is not null then
      select * into src from public.ops_tasks where id = r.source_task_id;
    else
      src := null;
    end if;

    /* A client's repeats wait for the client's month: one that exists, is
       open and has its content meeting set or marked not applicable. Until
       then the rule is held and counted, and a later run makes them. */
    ccl := case when src.id is not null then case when src.scope = 'client' then src.client_id end
                else r.client_id end;
    mon := null;
    if ccl is not null then
      select * into mon from public.ops_engagements x where x.client_id = ccl and x.period = p_period;
      if mon.id is null or mon.status in ('completed', 'cancelled')
         or (mon.meeting_at is null and not mon.meeting_na) then
        held := held + 1;
        continue;
      end if;
    end if;

    /* The dates this rule falls on inside the month. */
    if r.frequency = 'monthly' then
      d := first_day + (least(coalesce(r.day_of_month,
              case when src.publish_at is not null then extract(day from src.publish_at)::integer else 1 end),
              extract(day from last_day)::integer) - 1);
      stepd := null;
    else
      stepd := case when r.frequency = 'weekly' then 7 else greatest(1, coalesce(r.interval_days, 7)) end;
      anchor := coalesce(src.publish_at::date, r.created_at::date, first_day);
      if anchor > first_day then d := anchor;
      else d := anchor + ((((first_day - anchor) + stepd - 1) / stepd) * stepd); end if;
    end if;

    while d is not null and d <= last_day loop
      if d >= first_day
         /* The task a rule copies is its first occurrence: nothing on or
            before its day is made again. */
         and (src.id is null or d > coalesce(src.publish_at, r.created_at)::date)
         and (r.ends_on is null or d <= r.ends_on)
         and (r.max_count is null or r.generated_count < r.max_count) then
        key := 'recur:' || r.id::text || ':' || to_char(d, 'YYYY-MM-DD');
        if exists (select 1 from public.ops_tasks where idem_key = key) then
          skip := skip + 1;
        else
          wk := coalesce(r.code_week, least(5, ((extract(day from d)::integer - 1) / 7) + 1));
          if src.id is not null then
            one := public.ops_duplicate_task(src.id, jsonb_build_object(
              'keep_desc', true, 'copy_dates', false, 'copy_assignees', true,
              'publish_at', d::timestamptz, 'code_period', p_period, 'code_week', wk,
              'engagement_id', mon.id), key);
          else
            one := public.ops_create_task(jsonb_build_object(
              'scope', case when r.client_id is null then 'internal' else 'client' end,
              'client_id', r.client_id, 'template_id', r.template_id,
              'title', r.name || ' — ' || p_period, 'content_desc', r.name,
              'owner_id', r.owner_id, 'publish_at', d::timestamptz,
              'code_period', p_period, 'code_week', wk, 'engagement_id', mon.id), key);
          end if;
          if one ? 'error' then return one || jsonb_build_object('rule', r.id); end if;
          made := made + 1;
          update public.ops_recurring_rules
             set generated_count = generated_count + 1, last_generated_period = p_period, updated_at = now()
           where id = r.id;
          r.generated_count := r.generated_count + 1;
        end if;
      end if;
      exit when stepd is null;
      d := d + stepd;
    end loop;
  end loop;
  return jsonb_build_object('created', made, 'skipped', skip, 'held', held, 'period', p_period);
end $$;
grant execute on function public.ops_generate_recurring(text, uuid[], text) to authenticated;

/* The months a repeat is made for today: this one in Malaysia, and the next
   one once this one is in its last seven days. */
create or replace function public.ops_recurring_periods()
returns text[]
language sql stable set search_path = public as $$
  select case
    when (now() at time zone 'Asia/Kuala_Lumpur')::date
         > (date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') + interval '1 month' - interval '8 days')::date
    then array[to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYY-MM'),
               to_char(date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') + interval '1 month', 'YYYY-MM')]
    else array[to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYY-MM')]
  end
$$;
revoke all on function public.ops_recurring_periods() from public, anon, authenticated;

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
     names its own description, format and week; only a sheet's one piece
     carries its own dates and brief. */
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
  spread := first_day is not null and (n > 1 or rep is not null);

  begin
    for pc in select x from jsonb_array_elements(p_payload -> 'pieces') x loop
      i := i + 1;
      w := least(5, greatest(1, coalesce((pc ->> 'code_week')::integer, 1)));
      one := base || jsonb_strip_nulls(jsonb_build_object(
        'content_desc', nullif(btrim(coalesce(pc ->> 'content_desc', '')), ''),
        'deliverable_type', nullif(pc ->> 'deliverable_type', ''),
        'code_week', case when first_day is not null then w end));
      if n = 1 then
        one := one || jsonb_strip_nulls(jsonb_build_object(
          'publish_at', nullif(pc ->> 'publish_at', ''),
          'first_draft_due_at', nullif(pc ->> 'first_draft_due_at', ''),
          'final_due_at', nullif(pc ->> 'final_due_at', '')));
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

/* A client's month confirmed makes that client's repeats for it at once, as
   the person confirming and with their access. A refusal or a fault here
   never fails the confirmation; the morning run makes what it missed. */
create or replace function public.ops_engagements_confirmed()
returns trigger language plpgsql security definer set search_path = public as $$
declare rules uuid[];
begin
  if new.status in ('completed', 'cancelled') then return null; end if;
  if old.meeting_at is not null or coalesce(old.meeting_na, false) then return null; end if;
  if new.meeting_at is null and not coalesce(new.meeting_na, false) then return null; end if;
  select array_agg(r.id) into rules
    from public.ops_recurring_rules r
    left join public.ops_tasks s on s.id = r.source_task_id
   where r.active
     and case when s.id is not null then case when s.scope = 'client' then s.client_id end
              else r.client_id end = new.client_id;
  if rules is null then return null; end if;
  begin
    perform public.ops_generate_recurring(new.period, rules);
  exception when others then
    null;
  end;
  return null;
end $$;
revoke all on function public.ops_engagements_confirmed() from public, anon, authenticated;
drop trigger if exists ops_engagements_confirmed on public.ops_engagements;
create trigger ops_engagements_confirmed after update of meeting_at, meeting_na on public.ops_engagements
  for each row execute function public.ops_engagements_confirmed();

/* The morning run. Each rule is made as the colleague who set it, else its
   task's owner, with that colleague's own access; a rule neither of them can
   make waits. Nobody calls this but the schedule below. */
create or replace function public.ops_recurring_daily()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a   record;
  pp  text;
  out jsonb := '[]'::jsonb;
  was text := current_setting('request.jwt.claims', true);
begin
  for a in
    select actor.email, array_agg(r.id order by r.id) as rules
      from public.ops_recurring_rules r
      left join public.ops_tasks s on s.id = r.source_task_id
      cross join lateral (
        select tm.email from public.team_members tm
         where tm.active and tm.email is not null
           and tm.id in (r.created_by,
                         (select x.team_member_id from public.ops_task_assignees x
                           where x.task_id = s.id and x.responsibility = 'owner' and x.ended_at is null
                           limit 1))
         order by (tm.id = r.created_by) desc nulls last
         limit 1) actor
     where r.active
     group by actor.email
  loop
    perform set_config('request.jwt.claims',
      jsonb_build_object('email', a.email, 'role', 'authenticated')::text, true);
    foreach pp in array public.ops_recurring_periods() loop
      out := out || jsonb_build_object('period', pp, 'rules', to_jsonb(a.rules),
                                       'result', public.ops_generate_recurring(pp, a.rules));
    end loop;
  end loop;
  perform set_config('request.jwt.claims', coalesce(was, ''), true);
  return out;
end $$;
revoke all on function public.ops_recurring_daily() from public, anon, authenticated;

/* Every morning at 00:10 in Malaysia (16:10 UTC). */
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'ops-repeats-daily: pg_cron is not installed, so no schedule was written.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'ops-repeats-daily';
  perform cron.schedule('ops-repeats-daily', '10 16 * * *', 'select public.ops_recurring_daily()');
end $$;

-- END OF PIECES AND REPEATS ---------------------------------------------------
