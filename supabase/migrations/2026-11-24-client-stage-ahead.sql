-- ===========================================================================
-- A CLIENT'S STAGE SET AHEAD (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24: "regarding the client stages (eg. paused /
-- past, we could add future date), like if some client has told us to end
-- for the following month, so we could mark it first and analytics and
-- dashboard would catch it."
--
-- WHAT IT CHANGES
--   * `clients.stage_next` ('paused' or 'past'), `stage_next_on` (the
--     Malaysian day it takes effect), `stage_next_reason` and
--     `stage_next_note` (the reason and note the move will carry, the same
--     keys as `stage_reason`): one change set ahead a client, granted
--     select and update with the record's columns, all four set or none
--     (`clients_stage_next_shape`).
--   * `clients_stage_next` (before insert or update): a change set ahead is
--     after today in Malaysia (`stage-next-day`), to a stage the client is
--     not in (`stage-next-same`), and Completed only for a client once
--     Active (`stage-next-reason`); an insert carries none. Any real move
--     of the stage, by hand or by the job below, lets the change set ahead
--     go: a stage set by hand meanwhile replaces it.
--   * `clients_stage_due()`, every morning at 00:01 in Malaysia (16:01
--     UTC, `clients-stage-ahead`): each client whose day has come moves to
--     its stage with its reason and note, through the stage clock as a move
--     by hand does, filed `client.stage` under system. A day missed (the job
--     not run) is caught the next morning.
--   Why a stored move and not a stage derived on every read: the stage is
--   read by about three hundred lines of the schema (every policy through
--   `client_row_seen`, the client portal, Content Review, campaigns and
--   reports taking Active clients alone, the stage triggers), and each
--   would have to read the change set ahead to agree. Until its day the
--   client is in its stage as before; on the day it is in the new one,
--   everywhere at once.
--
-- ORDER: this file first, then the pages (they read the four columns, which
-- an old open tab never asks for; a page served before this file is applied
-- would have its client reads refused, so the file goes first).
--
-- ROLLBACK: unschedule `clients-stage-ahead`, drop the trigger
-- `clients_stage_next` and the functions `clients_stage_next()` and
-- `clients_stage_due()`, then the pages before this; the four columns may
-- stay (or be dropped after the pages are back).
-- Safe to run twice.
-- ===========================================================================

-- CLIENT STAGE AHEAD ------------------------------------------------------------

alter table public.clients add column if not exists stage_next text;
alter table public.clients add column if not exists stage_next_on date;
alter table public.clients add column if not exists stage_next_reason text;
alter table public.clients add column if not exists stage_next_note text;
grant select (stage_next, stage_next_on, stage_next_reason, stage_next_note) on table public.clients to authenticated;
grant update (stage_next, stage_next_on, stage_next_reason, stage_next_note) on table public.clients to authenticated;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clients_stage_next_shape') then
    alter table public.clients add constraint clients_stage_next_shape
      check ((stage_next is null and stage_next_on is null and stage_next_reason is null and stage_next_note is null)
          or (stage_next in ('paused', 'past') and stage_next_on is not null and stage_next_reason is not null
              and stage_next_reason in ('budget', 'results', 'in_house', 'closed', 'no_reply', 'other', 'completed')
              and (stage_next_reason <> 'completed' or stage_next = 'past')
              and length(coalesce(stage_next_note, '')) <= 2000));
  end if;
end $$;

create or replace function public.clients_stage_next()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.stage_next is not null then raise exception 'stage-next-day' using errcode = 'P0001'; end if;
    return new;
  end if;
  /* A real move, by hand or by clients_stage_due, ends the change set ahead. */
  if new.stage is distinct from old.stage then
    new.stage_next := null;
    new.stage_next_on := null;
    new.stage_next_reason := null;
    new.stage_next_note := null;
    return new;
  end if;
  if new.stage_next is null then
    new.stage_next_on := null;
    new.stage_next_reason := null;
    new.stage_next_note := null;
    return new;
  end if;
  if (new.stage_next, new.stage_next_on, new.stage_next_reason) is not distinct from
     (old.stage_next, old.stage_next_on, old.stage_next_reason) then
    return new;
  end if;
  if new.stage_next_on <= (now() at time zone 'Asia/Kuala_Lumpur')::date then
    raise exception 'stage-next-day' using errcode = 'P0001';
  end if;
  if new.stage_next = new.stage then
    raise exception 'stage-next-same' using errcode = 'P0001';
  end if;
  if new.stage_next_reason = 'completed' and new.stage <> 'active'
     and not exists (select 1 from jsonb_array_elements(coalesce(new.stage_log, '[]'::jsonb)) e
                      where e ->> 'stage' = 'active') then
    raise exception 'stage-next-reason' using errcode = 'P0001';
  end if;
  new.stage_next_note := nullif(btrim(coalesce(new.stage_next_note, '')), '');
  return new;
end $$;
revoke all on function public.clients_stage_next() from public, anon, authenticated;
create or replace trigger clients_stage_next before insert or update on public.clients
  for each row execute function public.clients_stage_next();

create or replace function public.clients_stage_due()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  c record;
  n integer := 0;
  v_day date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  for c in select x.id, x.name, x.stage_next, x.stage_next_on, x.stage_next_reason, x.stage_next_note
             from public.clients x
            where x.stage_next is not null and x.stage_next_on <= v_day
            order by x.stage_next_on, x.name loop
    begin
      update public.clients
         set stage = c.stage_next, stage_reason = c.stage_next_reason, stage_note = c.stage_next_note
       where id = c.id and stage_next = c.stage_next and stage_next_on = c.stage_next_on;
      if found then
        insert into public.activity_log (actor, action, subject, detail)
        values ('system', 'client.stage', c.name,
                case c.stage_next when 'paused' then 'Paused' else 'Past' end || ' from ' ||
                public.register_day(c.stage_next_on) || ', as scheduled · ' ||
                case c.stage_next_reason when 'budget' then 'Budget' when 'results' then 'Results'
                  when 'in_house' then 'Moved in-house' when 'closed' then 'Business closed'
                  when 'no_reply' then 'No reply' when 'completed' then 'Completed' else 'Other' end ||
                coalesce(': ' || c.stage_next_note, ''));
        n := n + 1;
      end if;
    exception when others then
      raise notice 'clients-stage-ahead: % was not moved (%).', c.id, sqlerrm;
    end;
  end loop;
  return n;
end $$;
revoke all on function public.clients_stage_due() from public, anon, authenticated;

/* Every morning at 00:01 in Malaysia (16:01 UTC). */
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'clients-stage-ahead: pg_cron is not installed, so no schedule was written.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'clients-stage-ahead';
  perform cron.schedule('clients-stage-ahead', '1 16 * * *', 'select public.clients_stage_due()');
end $$;

-- END OF CLIENT STAGE AHEAD ---------------------------------------------------

select public.functions_tidy();
