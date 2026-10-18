-- ===========================================================================
-- PASSCODE LOCKS LENGTHEN — a caller locked out again soon after is locked
-- out longer (15 minutes, then an hour, then a day), and a new access code
-- is six characters at least. 2026-10-18. Safe to run twice. Rollback at
-- the foot. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/confirmonce.js compares the two.
--
-- WHAT CHANGED (second audit, item 16)
--   1. `link_tries` keeps `strikes` and `struck_until` (the last lock's
--      end). A lock that begins within 24 hours of the last one ending is
--      the next step: 15 minutes, 1 hour, then 24 hours. The right access
--      code, and the team's Clear, start the steps again.
--      `link_passcode` and `link_lock_clear` are restated whole from
--      PASSCODE LOCKS PER CALLER with only that changed; `link_locked`
--      already says the minutes left.
--   2. Trigger `passcode_long_enough` on clients and campaigns refuses a
--      new or changed access code under six characters (`passcode-short`);
--      a shorter one already set keeps working until it is changed, and
--      clearing one is never refused. The console's Client settings says
--      so before it saves.
--
-- ROLLBACK
--   Run link_passcode and link_lock_clear from PASSCODE LOCKS PER CALLER
--   (2026-10-18-passcode-locks-per-caller.sql) again, then in the SQL
--   Editor:
--   drop trigger if exists clients_passcode_length on public.clients;
--   drop trigger if exists campaigns_passcode_length on public.campaigns;
--   drop function if exists public.passcode_long_enough();
--   alter table public.link_tries drop column if exists strikes,
--     drop column if exists struck_until;
-- ===========================================================================

alter table public.link_tries
  add column if not exists strikes integer not null default 0,
  add column if not exists struck_until timestamptz;

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
  select * into a from public.link_tries where kind = p_kind and token = p_token and ip = v_ip;
  select * into b from public.link_attempts where kind = p_kind and token = p_token;
  -- An address that opened the link in the last 30 days is never held by
  -- the link's backstop, only by its own count.
  v_known := a.ok_at is not null and a.ok_at > now() - interval '30 days';
  if a.locked_until > now() then return 'locked'; end if;
  if b.locked_until > now() and not v_known then return 'locked'; end if;
  -- Asked without one: the page learning that a passcode is needed.
  if coalesce(p_given, '') = '' then return 'wrong'; end if;
  if p_given = p_stored then
    if a.kind is null or a.fails > 0 or a.locked_until is not null or a.strikes > 0
       or coalesce(a.ok_at < now() - interval '1 day', true) then
      insert into public.link_tries as t (kind, token, ip, fails, last_at, ok_at)
      values (p_kind, p_token, v_ip, 0, now(), now())
      on conflict (kind, token, ip) do update
         set fails = 0, locked_until = null, ok_at = now(), strikes = 0, struck_until = null;
    end if;
    return 'ok';
  end if;

  insert into public.link_tries (kind, token, ip) values (p_kind, p_token, v_ip)
  on conflict (kind, token, ip) do nothing;
  select * into a from public.link_tries
   where kind = p_kind and token = p_token and ip = v_ip for update;
  if a.locked_until > now() then return 'locked'; end if;
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

  insert into public.link_attempts (kind, token) values (p_kind, p_token)
  on conflict (kind, token) do nothing;
  select * into b from public.link_attempts
   where kind = p_kind and token = p_token for update;
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

create or replace function public.link_lock_clear(p_kind text, p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me      public.team_members;
  v_token text;
  v_name  text;
  v_n     integer;
begin
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_kind = 'review' then
    if not public.allowed('review.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
    if not public.client_scope_ok('client', p_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
    select c.access_token, c.name into v_token, v_name from public.clients c where c.id = p_id;
  elsif p_kind = 'selection' then
    if not public.allowed('campaigns.campaigns', 'work') then return jsonb_build_object('error', 'denied'); end if;
    if not public.client_scope_ok('campaign', p_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
    select k.access_token, k.title into v_token, v_name from public.campaigns k where k.id = p_id;
  else
    return jsonb_build_object('error', 'bad-kind');
  end if;
  if v_token is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.link_tries set fails = 0, locked_until = null, strikes = 0, struck_until = null
   where kind = p_kind and token = v_token and (fails > 0 or locked_until is not null or strikes > 0);
  get diagnostics v_n = row_count;
  update public.link_attempts set fails = 0, locked_until = null
   where kind = p_kind and token = v_token;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, case when p_kind = 'review' then 'client.profile' else 'campaign.edited' end, v_name,
          case when p_kind = 'review' then 'Review link' else 'Selection link' end
          || ' unlocked · incorrect access codes cleared');
  return jsonb_build_object('ok', true, 'cleared', v_n);
end $$;
revoke all on function public.link_lock_clear(text, uuid) from public, anon;
grant execute on function public.link_lock_clear(text, uuid) to authenticated;

-- A new access code is six characters at least; one already set keeps
-- working until it is changed (second audit, item 16).
create or replace function public.passcode_long_enough()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.passcode is not null and btrim(new.passcode) <> ''
     and (tg_op = 'INSERT' or new.passcode is distinct from old.passcode)
     and char_length(new.passcode) < 6 then
    raise exception 'passcode-short' using errcode = 'check_violation',
      hint = 'An access code needs at least 6 characters.';
  end if;
  return new;
end $$;
revoke all on function public.passcode_long_enough() from public, anon, authenticated;
create or replace trigger clients_passcode_length before insert or update of passcode on public.clients
  for each row execute function public.passcode_long_enough();
create or replace trigger campaigns_passcode_length before insert or update of passcode on public.campaigns
  for each row execute function public.passcode_long_enough();

-- END OF PASSCODE LOCKS LENGTHEN ---------------------------------------------

select public.functions_tidy();
