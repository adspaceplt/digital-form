-- ===========================================================================
-- NAMECARDS FROM THE SIGN-IN — a card shows the email its colleague signs
-- in with.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/levels.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-03: "why not just use the login email". Every active
--   colleague keeps a card, interns signing in with a personal address
--   included (the user: "cannot restrict @adspacestudios.com").
--   1. `namecard_get` and `namecard_mine` give the sign-in address as the
--      card's email; `card_email` is no longer read (the column stays,
--      unread).
--   2. `namecard_save_mine` keeps the mobile alone (its email argument is
--      ignored, so the page's call is unchanged).
--   3. `team_members.card_on` (on by default): Team turns a card off and on
--      again from the colleague's row; while off its address answers
--      `not-found`, and the same address works again once it is back on.
--
-- ROLLBACK
--   Re-run the three functions from 2026-10-03-team-namecards.sql. The
--   column may stay; nothing else reads it.
-- ===========================================================================

alter table public.team_members add column if not exists card_on boolean not null default true;

create or replace function public.namecard_get(p_key text)
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((
    select jsonb_build_object(
             'name', t.name,
             'designation', t.designation,
             'mobile', nullif(btrim(coalesce(t.mobile, '')), ''),
             'email', lower(t.email))
      from public.team_members t
     where t.card_key = lower(btrim(coalesce(p_key, ''))) and t.active and t.card_on
     limit 1), jsonb_build_object('error', 'not-found'))
$$;
grant execute on function public.namecard_get(text) to anon, authenticated;

create or replace function public.namecard_mine()
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((
    select jsonb_build_object('key', t.card_key, 'name', t.name, 'designation', t.designation,
                              'mobile', t.mobile, 'email', lower(t.email), 'on', t.card_on)
      from public.team_members t
     where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active
     limit 1), jsonb_build_object('error', 'not-team'))
$$;
grant execute on function public.namecard_mine() to authenticated;

create or replace function public.namecard_save_mine(p_mobile text, p_email text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me_row public.team_members;
  v_mobile text := nullif(btrim(coalesce(p_mobile, '')), '');
begin
  select * into me_row from public.team_members t
   where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1;
  if me_row.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if v_mobile is not null and length(regexp_replace(v_mobile, '\D', '', 'g')) not between 8 and 15 then
    return jsonb_build_object('error', 'bad-mobile');
  end if;
  if v_mobile is not distinct from me_row.mobile then return jsonb_build_object('ok', true); end if;
  update public.team_members set mobile = v_mobile where id = me_row.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (lower(me_row.email), 'team.edited', me_row.name,
          'Mobile: ' || coalesce(me_row.mobile, 'not set') || ' → ' || coalesce(v_mobile, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.namecard_save_mine(text, text) to authenticated;

-- END OF NAMECARDS FROM THE SIGN-IN -------------------------------------------
