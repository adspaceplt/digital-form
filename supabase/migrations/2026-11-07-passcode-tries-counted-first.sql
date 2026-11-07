-- ===========================================================================
-- PASSCODE TRIES COUNTED FIRST (2026-11-07)
-- ===========================================================================
-- WHY (security audit, 2026-11-07; the user: "fix all"):
-- Guesses sent at once got past the passcode lock: the passcode was compared
-- before the try was counted, so a burst was compared in full, and a right
-- guess beside the fifth wrong one was let in and cleared the lock.
--
-- WHAT IT CHANGES
--   `link_passcode` takes the caller's and the link's rows under a row lock
--   before it compares, so every guess reads the count the one before left.
--
-- ORDER: this file alone; no page changes. Safe to run twice.
--
-- ROLLBACK: restate `link_passcode` from the PASSCODE LOCKS LENGTHEN band.
-- ===========================================================================

-- PASSCODE TRIES COUNTED FIRST -----------------------------------------------

/* The guess is held until its try is counted (security audit 2026-11-07):
   the caller's row and the link's row are taken under a row lock before
   any passcode is compared, so guesses sent at once wait in turn, each
   reading the count the one before it left, and a right one sent beside the
   fifth wrong one meets the lock. Asked without a passcode, it still only
   reads. Everything else is as the PASSCODE LOCKS LENGTHEN band left it. */
create or replace function public.link_passcode(p_kind text, p_token text, p_stored text, p_given text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_ip text := public.request_ip();
  a public.link_tries%rowtype;
  b public.link_attempts%rowtype;
  v_known boolean;
begin
  if coalesce(p_stored, '') = '' then return 'ok'; end if;
  -- Asked without one: the page learning that a passcode is needed.
  if coalesce(p_given, '') = '' then
    select * into a from public.link_tries where kind = p_kind and token = p_token and ip = v_ip;
    select * into b from public.link_attempts where kind = p_kind and token = p_token;
    v_known := a.ok_at is not null and a.ok_at > now() - interval '30 days';
    if a.locked_until > now() then return 'locked'; end if;
    if b.locked_until > now() and not v_known then return 'locked'; end if;
    return 'wrong';
  end if;

  insert into public.link_tries (kind, token, ip) values (p_kind, p_token, v_ip)
  on conflict (kind, token, ip) do nothing;
  select * into a from public.link_tries
   where kind = p_kind and token = p_token and ip = v_ip for update;
  insert into public.link_attempts (kind, token) values (p_kind, p_token)
  on conflict (kind, token) do nothing;
  select * into b from public.link_attempts
   where kind = p_kind and token = p_token for update;
  -- An address that opened the link in the last 30 days is never held by
  -- the link's backstop, only by its own count.
  v_known := a.ok_at is not null and a.ok_at > now() - interval '30 days';
  if a.locked_until > now() then return 'locked'; end if;
  if b.locked_until > now() and not v_known then return 'locked'; end if;

  if p_given = p_stored then
    if a.fails > 0 or a.locked_until is not null or a.strikes > 0
       or coalesce(a.ok_at < now() - interval '1 day', true) then
      update public.link_tries
         set fails = 0, last_at = now(), locked_until = null, ok_at = now(), strikes = 0, struck_until = null
       where kind = p_kind and token = p_token and ip = v_ip;
    end if;
    return 'ok';
  end if;

  a.fails := case when a.locked_until is not null or a.last_at < now() - interval '15 minutes'
                  then 1 else a.fails + 1 end;
  if a.fails >= 5 then
    -- A lock again within a day of the last one ending is longer: 15
    -- minutes, then an hour, then a day (second audit, item 16).
    a.strikes := case when a.struck_until > now() - interval '24 hours' then a.strikes + 1 else 1 end;
    a.locked_until := now() + case a.strikes when 1 then interval '15 minutes'
                                             when 2 then interval '1 hour'
                                             else interval '24 hours' end;
    a.struck_until := a.locked_until;
  else
    a.locked_until := null;
  end if;
  update public.link_tries
     set fails = a.fails, last_at = now(), locked_until = a.locked_until,
         strikes = a.strikes, struck_until = a.struck_until
   where kind = p_kind and token = p_token and ip = v_ip;

  if b.locked_until is null or b.locked_until <= now() then
    b.fails := case when b.locked_until is not null or b.last_at < now() - interval '1 hour'
                    then 1 else b.fails + 1 end;
    b.locked_until := case when b.fails >= 100 then now() + interval '1 hour' end;
    update public.link_attempts set fails = b.fails, last_at = now(), locked_until = b.locked_until
     where kind = p_kind and token = p_token;
  end if;

  if a.locked_until is not null then return 'locked'; end if;
  if b.locked_until > now() and not v_known then return 'locked'; end if;
  return 'wrong';
end $$;
revoke all on function public.link_passcode(text, text, text, text) from public, anon, authenticated;

-- END OF PASSCODE TRIES COUNTED FIRST ----------------------------------------

select public.functions_tidy();
