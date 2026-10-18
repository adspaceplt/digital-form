-- ===========================================================================
-- WORKING DAYS SKIP HOLIDAYS — a count of working days passes over weekends
-- and public holidays, and a client's request for changes falls due in
-- working days. 2026-10-18. Safe to run twice. Rollback at the foot.
-- Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/ops.js compares the two.
--
-- WHAT CHANGED (review of 2026-10-18, item 20)
--   * ops_add_business_days skipped Saturday and Sunday (Malaysia time) but
--     counted a public holiday as a working day. It now passes over a day
--     on the Public holidays list too (public_holidays, Settings), so a
--     template's offsets land on working days. It reads a table, so it is
--     stable (no longer immutable) and security definer; it stays closed to
--     every browser.
--   * ops_tasks_revision_due put a task back to Revision (Client) due
--     today plus revision_due_days calendar days, so a Friday request fell
--     due on Saturday. It now counts revision_due_days working days from
--     today (Malaysia), through ops_add_business_days. The setting keeps its
--     key and its value; its words on the page read working days.
--
-- ROLLBACK
--   Run ops_add_business_days as THE OPERATIONS SYSTEM stated it, and
--   ops_tasks_revision_due as THREE DATES A POST stated it.
-- ===========================================================================

create or replace function public.ops_add_business_days(p_from timestamptz, p_days integer)
returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare
  d   timestamptz := p_from;
  n   integer := abs(coalesce(p_days, 0));
  dir integer := case when coalesce(p_days, 0) < 0 then -1 else 1 end;
begin
  if p_from is null then return null; end if;
  while n > 0 loop
    d := d + (dir || ' day')::interval;
    -- 0 is Sunday, 6 is Saturday in Postgres `dow`; a public holiday is no working day.
    if extract(dow from d at time zone 'Asia/Kuala_Lumpur') not in (0, 6)
       and not exists (select 1 from public.public_holidays h
                        where h.day = (d at time zone 'Asia/Kuala_Lumpur')::date) then
      n := n - 1;
    end if;
  end loop;
  return d;
end $$;
revoke all on function public.ops_add_business_days(timestamptz, integer) from public, anon, authenticated;

/* A client's request for changes sends the work back with a new due date:
   revision_due_days working days after today in Malaysia (weekends and
   public holidays passed over), stored as a typed date is (that day at
   00:00 UTC), and only where it is later than the due date the task holds. */
create or replace function public.ops_tasks_revision_due()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_day date; v_due timestamptz;
begin
  if new.stage_key <> 'revision_client' or old.stage_key is not distinct from new.stage_key then return null; end if;
  v_day := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_due := ((public.ops_add_business_days(v_day::timestamp at time zone 'Asia/Kuala_Lumpur',
              coalesce(public.app_setting('revision_due_days', v_day), 1)::integer)
             at time zone 'Asia/Kuala_Lumpur')::date::timestamp) at time zone 'UTC';
  if new.current_final_due_at is not null and new.current_final_due_at >= v_due then return null; end if;
  update public.ops_tasks set current_final_due_at = v_due, updated_at = now() where id = new.id;
  perform public.ops_log(new.id, 'due_changed',
    jsonb_build_object('kind', 'final', 'value', new.current_final_due_at),
    jsonb_build_object('kind', 'final', 'value', v_due),
    jsonb_build_object('reason', 'client_request', 'note', 'The client asked for changes.', 'auto', true));
  return null;
end $$;
revoke all on function public.ops_tasks_revision_due() from public, anon, authenticated;

-- END OF WORKING DAYS SKIP HOLIDAYS ------------------------------------------

select public.functions_tidy();
