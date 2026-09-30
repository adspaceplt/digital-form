-- ===========================================================================
-- SHORT LINKS FOR CLIENTS — a client's review link and a campaign's
-- selection link carry an eight-character key, and the long key each had
-- before still opens, by handing the page its new key.
-- 2026-10-01. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `clients.moved_token` / `campaigns.moved_token`: the long key a link
--      carried before its short one. It opens nothing by itself; it is
--      answered only by `link_moved`, with the key that replaced it.
--   2. `new_link_key()`: eight characters from the creator code's alphabet
--      in lower case (no 0, 1, i, l, o), from pgcrypto's random bytes, never
--      one already in use as a key or a moved key. The console makes the
--      same shape (`ADspaceAPI.accessToken`).
--   3. Once: every client and campaign whose key is longer than eight
--      characters keeps it as `moved_token` and takes a new short key. A
--      second run finds nothing left to move.
--   4. `link_moved(p_kind, p_token)`: `review` or `selection`, an exact moved
--      key in, the current key out, else null. Granted to anon, as the pages
--      that ask are signed out. It answers one key with one key: no listing,
--      no prefix.
--   5. A key changed afterwards (Reset access link) clears the moved key by
--      trigger, so a reset retires every earlier link, the long one
--      included.
--
-- ROLLBACK
--   Put each long key back first, while it is still known:
--     update public.clients set access_token = moved_token where moved_token is not null;
--     update public.campaigns set access_token = moved_token where moved_token is not null;
--   then:
--   drop trigger if exists clients_link_moved on public.clients;
--   drop trigger if exists campaigns_link_moved on public.campaigns;
--   drop function if exists public.link_key_changed();
--   drop function if exists public.link_moved(text, text);
--   drop function if exists public.new_link_key();
--   alter table public.clients drop column if exists moved_token;
--   alter table public.campaigns drop column if exists moved_token;
-- ===========================================================================

alter table public.clients   add column if not exists moved_token text;
alter table public.campaigns add column if not exists moved_token text;
create unique index if not exists clients_moved_token_idx
  on public.clients(moved_token) where moved_token is not null;
create unique index if not exists campaigns_moved_token_idx
  on public.campaigns(moved_token) where moved_token is not null;

create or replace function public.new_link_key()
returns text language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := '23456789abcdefghjkmnpqrstuvwxyz';
  v_out   text;
  v_bytes bytea;
  v_i     integer;
  v_b     integer;
begin
  loop
    v_out := '';
    while length(v_out) < 8 loop
      v_bytes := gen_random_bytes(16);
      for v_i in 0..15 loop
        v_b := get_byte(v_bytes, v_i);
        /* 248 is 31 × 8: below it every character is equally likely. */
        if v_b < 248 and length(v_out) < 8 then
          v_out := v_out || substr(alphabet, 1 + (v_b % 31), 1);
        end if;
      end loop;
    end loop;
    exit when not exists (select 1 from public.clients c
                           where c.access_token = v_out or c.moved_token = v_out)
          and not exists (select 1 from public.campaigns k
                           where k.access_token = v_out or k.moved_token = v_out);
  end loop;
  return v_out;
end $$;
revoke all on function public.new_link_key() from public, anon, authenticated;

/* A key changed by anything but this move retires the moved key with it. */
create or replace function public.link_key_changed() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.access_token is distinct from old.access_token
     and new.moved_token is not distinct from old.moved_token then
    new.moved_token := null;
  end if;
  return new;
end $$;
revoke all on function public.link_key_changed() from public, anon, authenticated;
drop trigger if exists clients_link_moved on public.clients;
create trigger clients_link_moved before update on public.clients
  for each row execute function public.link_key_changed();
drop trigger if exists campaigns_link_moved on public.campaigns;
create trigger campaigns_link_moved before update on public.campaigns
  for each row execute function public.link_key_changed();

/* The move, once: a long key becomes the moved key. */
do $$
declare r record;
begin
  for r in select id from public.clients
            where length(access_token) > 8 and moved_token is null loop
    update public.clients
       set moved_token = access_token, access_token = public.new_link_key()
     where id = r.id;
  end loop;
  for r in select id from public.campaigns
            where length(access_token) > 8 and moved_token is null loop
    update public.campaigns
       set moved_token = access_token, access_token = public.new_link_key()
     where id = r.id;
  end loop;
end $$;

create or replace function public.link_moved(p_kind text, p_token text)
returns text language sql stable security definer set search_path = public as $$
  select case p_kind
    when 'review' then
      (select c.access_token from public.clients c
        where p_token is not null and c.moved_token = p_token and c.active limit 1)
    when 'selection' then
      (select k.access_token from public.campaigns k
        where p_token is not null and k.moved_token = p_token limit 1)
  end
$$;
revoke all on function public.link_moved(text, text) from public;
grant execute on function public.link_moved(text, text) to anon, authenticated;

-- END OF SHORT LINKS FOR CLIENTS --------------------------------------------
