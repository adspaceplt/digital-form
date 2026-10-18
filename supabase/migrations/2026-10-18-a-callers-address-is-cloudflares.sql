-- ===========================================================================
-- A CALLER'S ADDRESS IS CLOUDFLARE'S — the passcode locks count the address
-- Cloudflare saw, never one the caller wrote (2026-10-18)
-- ===========================================================================
-- WHY (audit 2026-10-18, item 1): `request_ip()` took the first entry of
-- X-Forwarded-For, which the caller writes. Read live (one request sent
-- with `X-Forwarded-For: 203.0.113.77, 198.51.100.9`): PostgREST passed
-- `203.0.113.77, 198.51.100.9,<the caller>` and `cf-connecting-ip:
-- <the caller>`; a request sending its own CF-Connecting-IP is refused by
-- Cloudflare (error 1000) and X-Real-IP never arrives. So a guesser wrote a
-- new address on every try and the five-try lock never held them.
--
-- WHAT IT CHANGES
--   * `request_ip()` reads `cf-connecting-ip`, else the last
--     X-Forwarded-For entry (the one the gateway appended), never the first.
--   * `media-pass` and `sign-download` ask for a link as the page did, and
--     Cloudflare stamps their own address on that call. They now pass the
--     caller's address in `x-adspace-ip` with `x-adspace-relay`, a secret
--     kept in `app_secrets` (`ip_relay_secret`, made here, read only with
--     the service role); `request_ip()` takes `x-adspace-ip` only beside the
--     right secret. It is security definer so it may read the secret, and
--     stays closed to every browser.
--   * The probe used to read the headers live (`zz_header_probe`, emptied
--     and closed the same hour) is dropped.
--
-- ORDER: this file, then `media-pass` and `sign-download`. Between the two
-- a function's passcode tries count against its own address, as before
-- 2026-10-18. Safe to run twice. The connector holds the last line (a drop):
-- run it in the SQL Editor.
-- Rollback: PASSCODE LOCKS PER CALLER's `request_ip()`, and the functions as
-- they were; the secret may stay.
-- ===========================================================================

insert into public.app_secrets (key, value)
select 'ip_relay_secret', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
 where not exists (select 1 from public.app_secrets s where s.key = 'ip_relay_secret');

create or replace function public.request_ip()
returns text
language sql stable security definer set search_path = public as $$
  select left(coalesce(
    case when nullif(h ->> 'x-adspace-relay', '') is not null
          and h ->> 'x-adspace-relay' = (select s.value from public.app_secrets s where s.key = 'ip_relay_secret')
         then nullif(btrim(h ->> 'x-adspace-ip'), '') end,
    nullif(btrim(h ->> 'cf-connecting-ip'), ''),
    nullif(btrim(reverse(split_part(reverse(coalesce(h ->> 'x-forwarded-for', '')), ',', 1))), ''),
    ''), 64)
  from (select coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json as h) r
$$;
revoke all on function public.request_ip() from public, anon, authenticated;

drop function if exists public.zz_header_probe();
-- END OF A CALLER'S ADDRESS IS CLOUDFLARE'S ---------------------------------

select public.functions_tidy();
