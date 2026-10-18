-- ===========================================================================
-- HR LETTERS FIND THEIR COLLEAGUE — an HR letter whose reference carries a
-- colleague's Employee ID is filed under them (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18: "when its linked to a team member, shouldnt all
-- letters or documents go into their respective accounts"): the HR letters
-- added by hand from the old list carry the colleague's Employee ID in their
-- reference (ADHR/AD013/E2501, AD013-P2405001) but name nobody, so the
-- register's Team column found them and the colleague's record did not.
--
-- WHAT IT CHANGES
--   * `hr_member_of(serial)`: the one colleague whose Employee ID is a part
--     of the reference (split on / and -), else null (none, or two).
--   * Trigger `documents_hr_member` (before insert or update of serial,
--     family, member_id): an HR letter naming nobody takes that colleague.
--   * The HR letters already filed naming nobody are filed so once.
--
-- ORDER: this file, then the pages (the colleague's record also matches by
-- the reference, so either order reads the same). Safe to run twice.
-- Rollback: drop the trigger and the function; the rows keep their colleague.
-- ===========================================================================

create or replace function public.hr_member_of(p_serial text)
returns uuid
language sql stable security definer set search_path = public as $$
  select case when count(*) = 1 then (array_agg(m.id))[1] end
    from public.team_members m
   where coalesce(btrim(m.staff_code), '') <> ''
     and string_to_array(regexp_replace(upper(coalesce(p_serial, '')), '-', '/', 'g'), '/') @> array[upper(btrim(m.staff_code))]
$$;
revoke all on function public.hr_member_of(text) from public, anon, authenticated;

create or replace function public.documents_hr_member()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.family = 'hr' and new.member_id is null then
    new.member_id := public.hr_member_of(new.serial);
  end if;
  return new;
end $$;
revoke all on function public.documents_hr_member() from public, anon, authenticated;

create or replace trigger documents_hr_member
  before insert or update of serial, family, member_id on public.documents
  for each row execute function public.documents_hr_member();

update public.documents d
   set member_id = public.hr_member_of(d.serial)
 where d.family = 'hr' and d.member_id is null and public.hr_member_of(d.serial) is not null;

-- END OF HR LETTERS FIND THEIR COLLEAGUE ------------------------------------
select public.functions_tidy();
