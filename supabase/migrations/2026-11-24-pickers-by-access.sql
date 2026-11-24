-- ===========================================================================
-- PICKERS OFFER WHO MAY WORK THE SECTION (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24: a part-time contractor added to the portal only
-- for the namecard appeared in every sales and operations picker ("how do we
-- exclude him/her from these sales operations selections? (in the future
-- might also need to add her back)"). Person in charge, Sales by and a
-- campaign's owner offered every active colleague, whatever their access.
--
-- WHAT IT ADDS
--   * `team_pickable(p_section)`: the ids of the active colleagues who may
--     work `p_section` (its access at Work or above, or an admin), for any
--     colleague to ask; `[]` to anybody who is no colleague. Putting a
--     colleague in a group with no access to the section takes them out of
--     its pickers; moving them back returns them. Nothing else changes.
--
-- ORDER: this file, then the pages (a page from before never asks it; the
-- new page offers everyone while it is not run).
-- Safe to run twice.
-- ROLLBACK: drop `team_pickable(text)`; the pages then offer everyone.
-- ===========================================================================

create or replace function public.team_pickable(p_section text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when (public.ops_me()).id is null then '[]'::jsonb else coalesce((
    select jsonb_agg(t.id order by t.name)
      from public.team_members t
     where t.active and not coalesce(t.system, false)
       and (coalesce(t.is_admin, false) or coalesce(t.role, '') = 'admin'
            or public.level_rank(t.access ->> p_section) >= 2)), '[]'::jsonb) end
$$;
revoke all on function public.team_pickable(text) from public, anon;
grant execute on function public.team_pickable(text) to authenticated;

-- END OF PICKERS OFFER WHO MAY WORK THE SECTION -----------------------------

select public.functions_tidy();
