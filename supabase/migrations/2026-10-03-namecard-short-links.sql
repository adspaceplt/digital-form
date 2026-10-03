-- ===========================================================================
-- NAMECARD SHORT LINKS — every colleague's card has a short link on the
-- links host.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/levels.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-03: a short link for every namecard, made from the
--   name and edited per person in Team.
--   1. `team_members.card_slug`: made from the name as the colleague is
--      added (Xue Yi reads `xue-yi`), numbered where taken (`-2`), and never
--      following a rename. Team edits it; an empty value is made again from
--      the name. One slug is never both a card's and a short link's, whichever
--      came first (`slug-taken`).
--   2. `link_resolve` answers a card's slug with the card's own address
--      (`/card/?k=`) while the colleague is active and the card is on, and
--      as missing otherwise, so the Worker needs no change. A short link
--      still wins where both could answer.
--   3. `namecard_mine` adds `slug`, for My namecard to show and copy.
--   The QR on the card keeps the card's own address, which never changes,
--   so a printed code survives an edited slug.
--
-- ROLLBACK
--   Re-run link_resolve from the SHORT LINKS section of schema.sql and
--   namecard_mine from NAMECARDS FROM THE SIGN-IN; then remove the triggers
--   links_card_clash and team_card_slug and their functions, and
--   card_slug_base(text) and card_slug_free(text, uuid). The column may stay.
-- ===========================================================================

alter table public.team_members add column if not exists card_slug text;
create unique index if not exists team_members_card_slug_idx
  on public.team_members(card_slug) where card_slug is not null;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'team_card_slug_shape') then
    alter table public.team_members add constraint team_card_slug_shape
      check (card_slug ~ '^[a-z0-9][a-z0-9._-]{0,79}$');
  end if;
end $$;

/* A name as a slug: lower case, a dash between words, nothing else. */
create or replace function public.card_slug_base(p_name text)
returns text language sql immutable as $$
  select coalesce(nullif(trim(both '-' from left(
           trim(both '-' from regexp_replace(lower(coalesce(p_name, '')), '[^a-z0-9]+', '-', 'g')), 70)), ''),
         'card')
$$;
revoke all on function public.card_slug_base(text) from public, anon, authenticated;

/* The base, else the base numbered, free of every short link and every
   other colleague's card. */
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
    cand := p_base || '-' || k;
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
    new.card_slug := public.card_slug_free(public.card_slug_base(new.name), new.id);
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
create or replace trigger team_card_slug before insert or update on public.team_members
  for each row execute function public.team_card_slug();

create or replace function public.links_card_clash()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.team_members t where t.card_slug = new.slug) then
    raise exception 'slug-taken' using errcode = '23505';
  end if;
  return new;
end $$;
revoke all on function public.links_card_clash() from public, anon, authenticated;
create or replace trigger links_card_clash before insert or update of slug on public.links
  for each row execute function public.links_card_clash();

/* Everybody already on the list, one at a time so two of one name number
   apart. */
do $$
declare
  r record;
begin
  for r in select t.id from public.team_members t where t.card_slug is null order by t.name, t.id loop
    update public.team_members set card_slug = '' where id = r.id;
  end loop;
end $$;

create or replace function public.link_resolve(p_slug text, p_qr text default null)
returns table (url text, state text)
language plpgsql security definer stable set search_path = public as $$
declare
  v_slug   text := lower(btrim(coalesce(p_slug, '')));
  v_code   text := lower(btrim(coalesce(p_qr, '')));
  v_target text;
  v_live   boolean;
begin
  if v_slug = '' then
    return query select null::text, 'missing'::text;
    return;
  end if;

  select l.target_url, l.active into v_target, v_live
    from public.links l
   where l.slug = v_slug;

  if v_target is null then
    -- A colleague's namecard, while they are active and the card is on.
    select 'https://digital.adspace.me/card/?k=' || t.card_key into v_target
      from public.team_members t
     where t.card_slug = v_slug and t.active and t.card_on and t.card_key is not null;
    if v_target is null then
      return query select null::text, 'missing'::text;
      return;
    end if;
    return query select v_target, 'ok'::text;
    return;
  end if;
  if not v_live then
    return query select null::text, 'paused'::text;
    return;
  end if;

  -- A scan carries its code; a typed link does not, and is never turned away
  -- by one. A code that belongs to another slug is as revoked as a dead one.
  if v_code <> '' and not exists (
       select 1 from public.link_qrs q
        where q.code = v_code and q.slug = v_slug and q.active) then
    return query select null::text, 'revoked'::text;
    return;
  end if;

  return query select v_target, 'ok'::text;
end $$;
revoke all on function public.link_resolve(text, text) from public;
grant execute on function public.link_resolve(text, text) to anon, authenticated;

create or replace function public.namecard_mine()
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((
    select jsonb_build_object('key', t.card_key, 'slug', t.card_slug, 'name', t.name,
                              'designation', t.designation, 'mobile', t.mobile,
                              'email', lower(t.email), 'on', t.card_on)
      from public.team_members t
     where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active
     limit 1), jsonb_build_object('error', 'not-team'))
$$;
grant execute on function public.namecard_mine() to authenticated;

-- END OF NAMECARD SHORT LINKS --------------------------------------------------
