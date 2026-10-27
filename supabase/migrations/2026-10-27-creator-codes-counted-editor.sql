-- ===========================================================================
-- CREATOR CODES COUNTED, THE SQL EDITOR PART — turning notifications on with
-- a creator's code counts a wrong code as the creator's page does
-- (2026-10-27)
-- ===========================================================================
-- WHY: 2026-10-27-creator-codes-counted.sql counts wrong creator codes in
-- `get_creator`, `creator_set_profiles` and `share_link_preview`.
-- `push_subscribe` answered a creator's code too (`not-found` or not), and
-- it holds a delete the connector holds, so it runs here, after that file.
--
-- WHAT IT CHANGES
--   `push_subscribe` takes a creator's code through `creator_code_try`
--   before anything else: a caller locked out is answered `locked` with
--   `minutes`, and a wrong code is counted. Everything else is as BACKEND
--   REVIEW REST left it.
--
-- ORDER: after 2026-10-27-creator-codes-counted.sql. Safe to run twice.
-- Rollback: push_subscribe as BACKEND REVIEW REST defines it.
-- ===========================================================================

create or replace function public.push_subscribe(
  p_audience text, p_ref text, p_endpoint text, p_p256dh text, p_auth text, p_lang text default 'en')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_target uuid;
  v_lang   text := case when p_lang = 'zh' then 'zh' else 'en' end;
  v_lock   integer;
begin
  if not public.push_endpoint_ok(p_endpoint)
     or coalesce(length(p_p256dh), 0) not between 80 and 100
     or coalesce(length(p_auth), 0) not between 16 and 32 then
    return jsonb_build_object('error', 'bad-subscription');
  end if;
  if p_audience not in ('team', 'client', 'creator') then
    return jsonb_build_object('error', 'bad-audience');
  end if;
  if p_audience = 'creator' then
    select t.o_creator, t.o_locked into v_target, v_lock from public.creator_code_try(p_ref) t;
    if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  end if;
  v_target := public.push_target(p_audience, p_ref);
  if v_target is null then
    return jsonb_build_object('error', case when p_audience = 'team' then 'not-team' else 'not-found' end);
  end if;

  if not exists (select 1 from public.push_subscriptions s where s.endpoint = p_endpoint and s.target = v_target) then
    perform pg_advisory_xact_lock(hashtext('push_subscribe:' || v_target::text));
    if (select count(*) from public.push_subscriptions s
         where s.target = v_target and s.created_at > now() - interval '1 hour') >= 5
       or (select count(*) from public.push_subscriptions s where s.target = v_target) >= 20 then
      return jsonb_build_object('error', 'too-many');
    end if;
  end if;

  if p_audience in ('team', 'creator') then
    delete from public.push_subscriptions s
     where s.endpoint = p_endpoint and s.audience = p_audience and s.target <> v_target;
  end if;
  insert into public.push_subscriptions
    (endpoint, p256dh, auth, audience, team_member_id, campaign_id, creator_id, lang)
  values (p_endpoint, p_p256dh, p_auth, p_audience,
          case when p_audience = 'team' then v_target end,
          case when p_audience = 'client' then v_target end,
          case when p_audience = 'creator' then v_target end, v_lang)
  on conflict (endpoint, target) do update
     set lang = excluded.lang, seen_at = now();
  update public.push_subscriptions s set p256dh = p_p256dh, auth = p_auth
   where s.endpoint = p_endpoint and (s.p256dh <> p_p256dh or s.auth <> p_auth);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.push_subscribe(text, text, text, text, text, text) from public;
grant execute on function public.push_subscribe(text, text, text, text, text, text) to anon, authenticated;

-- END OF CREATOR CODES COUNTED, THE SQL EDITOR PART ------------------------

select public.functions_tidy();
