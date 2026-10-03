-- ===========================================================================
-- NAMECARD MOBILE SWITCH — each colleague shows or hides their mobile on
-- their card.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/levels.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-03: one card, one link and one QR; whether the mobile
--   is on it is the colleague's own choice ("mobile numbers is more of
--   personal preference"), turned on and off at will.
--   1. `team_members.card_mobile` (shown by default, as every card was).
--   2. `namecard_get` sends the mobile only while it is shown: hidden, the
--      number never leaves the database, so the card, its WhatsApp button
--      and Save contact all go without it.
--   3. `namecard_mine` adds `show_mobile`; `namecard_save(p_mobile, p_slug,
--      p_show)` saves the colleague's mobile, short link and the switch in
--      one write, filed `team.edited` from and to. `namecard_save_card`
--      stays for a page from before.
--
-- ROLLBACK
--   Re-run namecard_get from NAMECARDS FROM THE SIGN-IN and namecard_mine
--   from NAMECARD SHORT LINKS; then remove namecard_save(text, text,
--   boolean). The column may stay.
-- ===========================================================================

alter table public.team_members add column if not exists card_mobile boolean not null default true;

create or replace function public.namecard_get(p_key text)
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((
    select jsonb_build_object(
             'name', t.name,
             'designation', t.designation,
             'mobile', case when t.card_mobile then nullif(btrim(coalesce(t.mobile, '')), '') end,
             'email', lower(t.email))
      from public.team_members t
     where t.card_key = lower(btrim(coalesce(p_key, ''))) and t.active and t.card_on
     limit 1), jsonb_build_object('error', 'not-found'))
$$;
grant execute on function public.namecard_get(text) to anon, authenticated;

create or replace function public.namecard_mine()
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((
    select jsonb_build_object('key', t.card_key, 'slug', t.card_slug, 'name', t.name,
                              'designation', t.designation, 'mobile', t.mobile,
                              'email', lower(t.email), 'on', t.card_on,
                              'show_mobile', t.card_mobile)
      from public.team_members t
     where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active
     limit 1), jsonb_build_object('error', 'not-team'))
$$;
grant execute on function public.namecard_mine() to authenticated;

/* The colleague's own mobile, short link and whether the mobile is shown,
   from My namecard, in one write. An empty short link is made again from the
   name; the trigger refuses a taken or badly shaped one, answered here by
   name. A null p_show leaves the switch where it is. */
create or replace function public.namecard_save(p_mobile text, p_slug text, p_show boolean default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me_row public.team_members;
  v_mobile text := nullif(btrim(coalesce(p_mobile, '')), '');
  v_slug text := lower(btrim(coalesce(p_slug, '')));
  v_show boolean;
  now_slug text;
  said text := '';
begin
  select * into me_row from public.team_members t
   where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1;
  if me_row.id is null then return jsonb_build_object('error', 'not-team'); end if;
  v_show := coalesce(p_show, me_row.card_mobile);
  if v_mobile is not null and length(regexp_replace(v_mobile, '\D', '', 'g')) not between 8 and 15 then
    return jsonb_build_object('error', 'bad-mobile');
  end if;
  if v_slug <> '' and v_slug !~ '^[a-z0-9][a-z0-9._-]{0,79}$' then
    return jsonb_build_object('error', 'slug-shape');
  end if;
  if v_mobile is not distinct from me_row.mobile and v_slug = coalesce(me_row.card_slug, '')
     and v_show = me_row.card_mobile then
    return jsonb_build_object('ok', true, 'slug', me_row.card_slug, 'show_mobile', me_row.card_mobile);
  end if;
  begin
    update public.team_members set mobile = v_mobile, card_slug = nullif(v_slug, ''), card_mobile = v_show
     where id = me_row.id
     returning card_slug into now_slug;
  exception when others then
    if sqlerrm in ('slug-taken', 'slug-shape') then return jsonb_build_object('error', sqlerrm); end if;
    raise;
  end;
  if v_mobile is distinct from me_row.mobile then
    said := 'Mobile: ' || coalesce(me_row.mobile, 'not set') || ' → ' || coalesce(v_mobile, 'not set');
  end if;
  if v_show <> me_row.card_mobile then
    said := said || case when said = '' then '' else '; ' end || 'Mobile on card: '
         || case when me_row.card_mobile then 'Show' else 'Hide' end || ' → '
         || case when v_show then 'Show' else 'Hide' end;
  end if;
  if now_slug is distinct from me_row.card_slug then
    said := said || case when said = '' then '' else '; ' end
         || 'Short link: ' || coalesce(me_row.card_slug, 'not set') || ' → ' || coalesce(now_slug, 'not set');
  end if;
  if said <> '' then
    insert into public.activity_log (actor, action, subject, detail)
    values (lower(me_row.email), 'team.edited', me_row.name, said);
  end if;
  return jsonb_build_object('ok', true, 'slug', now_slug, 'show_mobile', v_show);
end $$;
grant execute on function public.namecard_save(text, text, boolean) to authenticated;

-- END OF NAMECARD MOBILE SWITCH ------------------------------------------------
