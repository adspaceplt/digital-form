-- ===========================================================================
-- TEAM NAMECARDS — every active colleague has a digital namecard.
-- 2026-10-03. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/levels.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `team_members.mobile` (as typed; the card formats it), `card_email`
--      (the address the card shows; empty shows the sign-in email) and
--      `card_key`: eight characters from the link keys' alphabet, made by
--      trigger on every new row and never changed, so a printed QR keeps
--      working. The card's address is /card/?k={card_key}.
--   2. `namecard_get(p_key)`, granted to anon: an active colleague's name,
--      position, mobile and email for that key, and nothing else (never the
--      Employee ID, group, access or sign-in details where a card email is
--      set). A colleague stood down, or a key nobody holds, answers
--      `not-found`, so the card goes the day their access does.
--   3. `namecard_mine()`: the signed-in colleague's own card, key included.
--      `namecard_save_mine(p_mobile, p_email)`: they correct their own mobile
--      and card email (filed under Team); the Team sheet edits everybody's.
--
-- ROLLBACK
--   drop trigger if exists team_card_key on public.team_members;
--   drop function if exists public.team_card_key(), public.namecard_get(text),
--     public.namecard_mine(), public.namecard_save_mine(text, text);
--   The three columns may stay; nothing else reads them.
-- ===========================================================================

alter table public.team_members add column if not exists mobile text;
alter table public.team_members add column if not exists card_email text;
alter table public.team_members add column if not exists card_key text;
create unique index if not exists team_members_card_key_idx
  on public.team_members(card_key) where card_key is not null;

/* new_link_key() is closed to the browser, so a default calling it would
   refuse the Team sheet's insert; a definer trigger makes the key instead. */
create or replace function public.team_card_key()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  k text;
begin
  if new.card_key is null then
    loop
      k := public.new_link_key();
      exit when not exists (select 1 from public.team_members t where t.card_key = k);
    end loop;
    new.card_key := k;
  end if;
  if tg_op = 'UPDATE' and old.card_key is not null then
    new.card_key := old.card_key;
  end if;
  return new;
end $$;
revoke all on function public.team_card_key() from public, anon, authenticated;
drop trigger if exists team_card_key on public.team_members;
create trigger team_card_key before insert or update on public.team_members
  for each row execute function public.team_card_key();

update public.team_members set card_key = null where card_key is null;

create or replace function public.namecard_get(p_key text)
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((
    select jsonb_build_object(
             'name', t.name,
             'designation', t.designation,
             'mobile', nullif(btrim(coalesce(t.mobile, '')), ''),
             'email', coalesce(nullif(btrim(coalesce(t.card_email, '')), ''), t.email))
      from public.team_members t
     where t.card_key = lower(btrim(coalesce(p_key, ''))) and t.active
     limit 1), jsonb_build_object('error', 'not-found'))
$$;
grant execute on function public.namecard_get(text) to anon, authenticated;

create or replace function public.namecard_mine()
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((
    select jsonb_build_object(
             'key', t.card_key, 'name', t.name, 'designation', t.designation,
             'mobile', t.mobile, 'card_email', t.card_email, 'email', t.email)
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
  v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
  moved text[] := '{}';
begin
  select * into me_row from public.team_members t
   where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1;
  if me_row.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if v_mobile is not null and length(regexp_replace(v_mobile, '\D', '', 'g')) not between 8 and 15 then
    return jsonb_build_object('error', 'bad-mobile');
  end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('error', 'bad-email');
  end if;
  if v_mobile is distinct from me_row.mobile then
    moved := moved || ('Mobile: ' || coalesce(me_row.mobile, 'not set') || ' → ' || coalesce(v_mobile, 'not set'));
  end if;
  if v_email is distinct from me_row.card_email then
    moved := moved || ('Email on card: ' || coalesce(me_row.card_email, 'not set') || ' → ' || coalesce(v_email, 'not set'));
  end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.team_members set mobile = v_mobile, card_email = v_email where id = me_row.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (lower(me_row.email), 'team.edited', me_row.name, array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.namecard_save_mine(text, text) to authenticated;

-- END OF TEAM NAMECARDS -------------------------------------------------------
