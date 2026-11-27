-- ===========================================================================
-- QUOTATION MADE BY ITS COLLEAGUE'S ID (2026-11-27)
-- ===========================================================================
-- WHY: a quotation held who made it by name alone (`made_by`), and the
-- PDF read that colleague's designation by `team_members.name`; a renamed
-- colleague drew no role under their name. A record is traced by its id,
-- never by its name.
-- WHAT IT CHANGES
--   * `quotations.made_by_id` (uuid, nullable, on delete set null), read
--     by a signed-in colleague as the list's other columns are. The
--     name stays as written, a snapshot never rewritten.
--   * `quotations_made_by_id()` (before insert): a quotation made with a
--     name takes the caller's own id where the caller is that colleague,
--     else a revision's the id of the quotation it revises or replaces
--     under the same name. Never resolved from a name.
--   * Backfill: a quotation's `made_by` held by exactly one colleague
--     takes that colleague's id; a name two hold is left unfilled.
-- ORDER: this file first, then the pages (which read `made_by_id`). An
-- open tab served before reads the role by name as it did.
-- ROLLBACK: drop trigger quotations_made_by_id on public.quotations; drop
-- function public.quotations_made_by_id(); the pages read the column, so
-- it stays. Safe to run twice.

-- QUOTATION MADE BY ID ------------------------------------------------------

alter table public.quotations add column if not exists made_by_id uuid
  references public.team_members(id) on delete set null;
grant select (made_by_id) on table public.quotations to authenticated;

create or replace function public.quotations_made_by_id()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members;
  v uuid;
begin
  if new.made_by_id is not null or nullif(btrim(coalesce(new.made_by, '')), '') is null then return new; end if;
  me := public.ops_me();
  if me.id is not null and me.name = btrim(new.made_by) then
    new.made_by_id := me.id;
    return new;
  end if;
  select x.made_by_id into v from public.quotations x
   where x.id = coalesce(new.revises, new.replaces) and x.made_by = new.made_by;
  new.made_by_id := v;
  return new;
end $$;
revoke all on function public.quotations_made_by_id() from public, anon, authenticated;

drop trigger if exists quotations_made_by_id on public.quotations;
create trigger quotations_made_by_id before insert on public.quotations
  for each row execute function public.quotations_made_by_id();

with one as (
  select m.name, min(m.id::text)::uuid id from public.team_members m
   where nullif(btrim(m.name), '') is not null group by m.name having count(*) = 1
)
update public.quotations q set made_by_id = o.id
  from one o
 where q.made_by_id is null and btrim(q.made_by) = o.name;

-- END OF QUOTATION MADE BY ID -------------------------------------------------

select public.functions_tidy();
