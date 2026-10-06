-- ===========================================================================
-- NAMECARD SHORT LINK SHOWN — the card names its short link, and a card's
-- short link is the name run together, numbered without a dash.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/levels.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-07: the card shows its short link in place of its long
--   address; Short Links lists every card's slug, so the team can see which
--   are taken; and a card's short link is the name run together, no dash.
--   1. `namecard_get` adds `slug`. The QR still holds the card's own address
--      (`/card/?k=`), which never changes, so a printed code survives an
--      edited slug.
--   2. `card_slug_from(name, email)`: the name's letters and digits run
--      together (Xue Yi reads `xueyi`); a name with none, written in Chinese,
--      takes the sign-in email's name (`qiaorou@…` reads `qiaorou`).
--      `team_card_slug` makes an empty slug from it.
--   3. `card_slug_free` numbers a taken slug without a dash (`xueyi2`, never
--      `xueyi-2`). Live on 2026-10-07 every card's slug was its name with no
--      dash, so no slug moves.
--   Short Links reads the cards' slugs from `team_members` (every colleague
--   reads it, `team_read`), so it needs no function.
--
-- ROLLBACK
--   Re-run namecard_get from NAMECARD MOBILE SWITCH, and card_slug_free and
--   team_card_slug from NAMECARD SHORT LINKS; then remove
--   card_slug_from(text, text).
-- ===========================================================================

/* A card's short link from its colleague: the name's letters and digits run
   together, else the sign-in email's name, else `card`. */
create or replace function public.card_slug_from(p_name text, p_email text)
returns text language sql immutable as $$
  select coalesce(
    nullif(left(regexp_replace(lower(coalesce(p_name, '')), '[^a-z0-9]+', '', 'g'), 70), ''),
    nullif(left(regexp_replace(lower(split_part(coalesce(p_email, ''), '@', 1)), '[^a-z0-9]+', '', 'g'), 70), ''),
    'card')
$$;
revoke all on function public.card_slug_from(text, text) from public, anon, authenticated;

/* The base, else the base numbered with no dash, free of every short link
   and every other colleague's card. */
create or replace function public.card_slug_free(p_base text, p_self uuid)
returns text language plpgsql security definer stable set search_path = public as $$
declare
  cand text := p_base;
  k int := 1;
begin
  loop
    exit when not exists (select 1 from public.links l where l.slug = cand)
          and not exists (select 1 from public.team_members t
                           where t.card_slug = cand and t.id is distinct from p_self);
    k := k + 1;
    cand := p_base || k;
  end loop;
  return cand;
end $$;
revoke all on function public.card_slug_free(text, uuid) from public, anon, authenticated;

create or replace function public.team_card_slug()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.card_slug is not distinct from old.card_slug then
    return new;
  end if;
  if new.card_slug is null or btrim(new.card_slug) = '' then
    new.card_slug := public.card_slug_free(public.card_slug_from(new.name, new.email), new.id);
    return new;
  end if;
  new.card_slug := lower(btrim(new.card_slug));
  if new.card_slug !~ '^[a-z0-9][a-z0-9._-]{0,79}$' then
    raise exception 'slug-shape' using hint = 'Lowercase letters, digits, dots, dashes or underscores.';
  end if;
  if exists (select 1 from public.links l where l.slug = new.card_slug)
     or exists (select 1 from public.team_members t where t.card_slug = new.card_slug and t.id <> new.id) then
    raise exception 'slug-taken' using errcode = '23505';
  end if;
  return new;
end $$;
revoke all on function public.team_card_slug() from public, anon, authenticated;

create or replace function public.namecard_get(p_key text)
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((
    select jsonb_build_object(
             'name', t.name,
             'designation', t.designation,
             'mobile', case when t.card_mobile then nullif(btrim(coalesce(t.mobile, '')), '') end,
             'email', lower(t.email),
             'slug', t.card_slug)
      from public.team_members t
     where t.card_key = lower(btrim(coalesce(p_key, ''))) and t.active and t.card_on
     limit 1), jsonb_build_object('error', 'not-found'))
$$;
grant execute on function public.namecard_get(text) to anon, authenticated;

-- END OF NAMECARD SHORT LINK SHOWN --------------------------------------------
