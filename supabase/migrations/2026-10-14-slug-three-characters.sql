-- ===========================================================================
-- SLUG THREE CHARACTERS — a short link or a namecard's slug is at least three
-- characters, so every one and two character address on the links host is
-- the portal's own (2026-10-14)
-- ===========================================================================
-- WHY (the user, 2026-10-14: "when creating short links, the slug requires
-- to have minimum 3 letters; 1 and 2 letters eg. hi.adspace.me/q,
-- hi.adspace.me/qr are all blocked")
--   The links host already answers /r/, /s/, /c/ and /p/ itself. Keeping
--   every address under three characters out of the team's hands leaves room
--   for the next without a clash. Live on 2026-10-14 no short link and no
--   card held a slug under three characters, so nothing moves.
--
-- WHAT IT ADDS
--   * `links_slug_min`: a short link's slug of at least three characters,
--     held on every new or changed link (an older one keeps working).
--   * `team_card_slug_min`: the same for a card, any card's slug under three
--     characters made again from the name first.
--   * `team_card_slug` refuses a typed slug under three characters
--     (`slug-shape`), which `namecard_save` already names.
--   * `card_slug_from` makes a card's slug of three or more: the name run
--     together, else the sign-in email's name, else the name with `card`
--     after it (Al reads `alcard` where the email gives nothing longer).
--
-- Safe to run twice. Rollback: drop the two constraints, then run
-- `card_slug_from` and `team_card_slug` from NAMECARD SHORT LINK SHOWN.
-- ===========================================================================

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'links_slug_min') then
    /* A short link already under three characters keeps working; every new
       or changed one is held to three. */
    alter table public.links add constraint links_slug_min check (char_length(slug) >= 3) not valid;
  end if;
end $$;

/* A card's short link from its colleague: the name's letters and digits run
   together, else the sign-in email's name, else the name with `card` after
   it; three characters at least. */
create or replace function public.card_slug_from(p_name text, p_email text)
returns text language sql immutable as $$
  select case when char_length(p.n) >= 3 then p.n
              when char_length(p.e) >= 3 then p.e
              else p.n || 'card' end
    from (select left(regexp_replace(lower(coalesce(p_name, '')), '[^a-z0-9]+', '', 'g'), 70) as n,
                 left(regexp_replace(lower(split_part(coalesce(p_email, ''), '@', 1)), '[^a-z0-9]+', '', 'g'), 70) as e) p
$$;
revoke all on function public.card_slug_from(text, text) from public, anon, authenticated;

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
  if new.card_slug !~ '^[a-z0-9][a-z0-9._-]{2,79}$' then
    raise exception 'slug-shape' using hint = 'At least three lowercase letters, digits, dots, dashes or underscores.';
  end if;
  if exists (select 1 from public.links l where l.slug = new.card_slug)
     or exists (select 1 from public.team_members t where t.card_slug = new.card_slug and t.id <> new.id) then
    raise exception 'slug-taken' using errcode = '23505';
  end if;
  return new;
end $$;
revoke all on function public.team_card_slug() from public, anon, authenticated;

/* A card's slug under three characters is made again from the name, then
   held to three. */
do $$
declare
  r record;
begin
  if exists (select 1 from pg_constraint where conname = 'team_card_slug_min') then return; end if;
  for r in select t.id from public.team_members t where char_length(t.card_slug) < 3 order by t.name, t.id loop
    update public.team_members set card_slug = '' where id = r.id;
  end loop;
  alter table public.team_members add constraint team_card_slug_min check (char_length(card_slug) >= 3);
end $$;

-- END OF SLUG THREE CHARACTERS ----------------------------------------------
select public.functions_tidy();
