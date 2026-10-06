-- ===========================================================================
-- FIRST-VISIT GUIDES — which section guides a colleague has met, on any
-- device. 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte
-- for byte in supabase/schema.sql under the same banner; tests/levels.js
-- compares the two.
--
-- WHAT CHANGED
--   The user, 2026-10-07: first-time users do not know what each section is
--   for; a one-time guide across the portal. A section's guide (js/guide.js)
--   opens by itself on a colleague's first visit and again from its ⓘ. What a
--   colleague has met is kept here, so a guide met at a desk is not met again
--   on a phone. The client pages keep theirs in the browser.
--   `guide_seen` (RLS on, no policy, no grant): one row a colleague a guide.
--   `guides_seen()` answers the caller's keys, and nothing to anybody who is
--   not an active colleague; `guide_seen_mark(p_guide)` records one, refusing
--   a key of the wrong shape (`bad-guide`).
--
-- ROLLBACK
--   Remove guide_seen_mark(text) and guides_seen(), then the table guide_seen.
-- ===========================================================================

create table if not exists public.guide_seen (
  team_member_id uuid not null references public.team_members(id),
  guide          text not null,
  seen_at        timestamptz not null default now(),
  primary key (team_member_id, guide)
);
alter table public.guide_seen enable row level security;
revoke all on public.guide_seen from public, anon, authenticated;

/* The guides the signed-in colleague has met. */
create or replace function public.guides_seen()
returns text[] language sql security definer stable set search_path = public as $$
  select coalesce(array_agg(g.guide order by g.guide), '{}'::text[])
    from public.guide_seen g
   where g.team_member_id = (select m.id from public.ops_me() m)
$$;
revoke all on function public.guides_seen() from public, anon;
grant execute on function public.guides_seen() to authenticated;

/* One guide met. A key is a section's name: lower case, a few characters. */
create or replace function public.guide_seen_mark(p_guide text)
returns jsonb language plpgsql security definer volatile set search_path = public as $$
declare
  v_me  uuid := (select m.id from public.ops_me() m);
  v_key text := lower(btrim(coalesce(p_guide, '')));
begin
  if v_me is null then return jsonb_build_object('error', 'not-team'); end if;
  if v_key !~ '^[a-z][a-z0-9.-]{0,39}$' then return jsonb_build_object('error', 'bad-guide'); end if;
  insert into public.guide_seen (team_member_id, guide) values (v_me, v_key)
  on conflict (team_member_id, guide) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.guide_seen_mark(text) from public, anon;
grant execute on function public.guide_seen_mark(text) to authenticated;

-- END OF FIRST-VISIT GUIDES ---------------------------------------------------
