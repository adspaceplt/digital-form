-- ===========================================================================
-- WAKE CALLS CARRY A SECRET — wa-send's drain and push-send answer only the
-- database's own wake, and a write wakes each of them once.
-- 2026-10-19. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED
--   wa-send's `drain` and push-send ran for any caller with no sign-in, so
--   anybody could make them work through the queues on demand; and each
--   queued row woke its sender again, so a notice to forty colleagues
--   started forty runs of push-send (the third audit, item 17).
--   * A wake secret is made once in `app_secrets` (`wake_secret`, 244
--     random bits from gen_random_uuid), never shown to a page or a person.
--   * wa_kick and push_kick send it as the `x-adspace-wake` header, and wake
--     once a transaction (a statement queueing forty messages wakes once;
--     pg_net sends after the commit, so the one wake finds them all).
--   * wake_secret_ok(p_given) answers whether a header is the secret, to
--     the service role alone; wa-send's `drain` and push-send ask it and
--     refuse anything else (401) before touching a queue
--     (supabase/functions/wa-send, supabase/functions/push-send).
--   The pg_cron job `outbox-drain` wakes them through the same two
--   functions, so it carries the secret too.
--
-- ROLLBACK
--   Redeploy the earlier wa-send and push-send first. Then run push_kick
--   of the PUSH NOTIFICATIONS section and wa_kick of the WHATSAPP section
--   of supabase/schema.sql again (they send no header).
-- ===========================================================================

insert into public.app_secrets (key, value)
values ('wake_secret', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (key) do nothing;

create or replace function public.wake_secret_ok(p_given text)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(length(p_given) >= 32, false) and exists (
    select 1 from public.app_secrets s where s.key = 'wake_secret' and s.value = p_given)
$$;
revoke all on function public.wake_secret_ok(text) from public, anon, authenticated;
grant execute on function public.wake_secret_ok(text) to service_role;

create or replace function public.wa_kick()
returns void
language plpgsql security definer set search_path = public as $$
begin
  -- once a transaction: the one wake, sent after the commit, finds every row
  if current_setting('adspace.wa_kicked', true) = '1' then return; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'net' and p.proname = 'http_post') then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/wa-send', '{"action":"drain"}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-adspace-wake',
            coalesce((select s.value from public.app_secrets s where s.key = 'wake_secret'), ''));
  perform set_config('adspace.wa_kicked', '1', true);
exception when others then
  return;
end $$;
revoke all on function public.wa_kick() from public, anon, authenticated;

create or replace function public.push_kick()
returns void
language plpgsql security definer set search_path = public as $$
begin
  -- once a transaction: the one wake, sent after the commit, finds every row
  if current_setting('adspace.push_kicked', true) = '1' then return; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'net' and p.proname = 'http_post') then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/push-send', '{}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-adspace-wake',
            coalesce((select s.value from public.app_secrets s where s.key = 'wake_secret'), ''));
  perform set_config('adspace.push_kicked', '1', true);
exception when others then
  return;
end $$;
revoke all on function public.push_kick() from public, anon, authenticated;

-- END OF WAKE CALLS CARRY A SECRET ------------------------------------------

select public.functions_tidy();
