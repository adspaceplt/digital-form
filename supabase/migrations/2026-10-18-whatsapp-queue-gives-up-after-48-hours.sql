-- ===========================================================================
-- WHATSAPP QUEUE GIVES UP AFTER 48 HOURS — a queued message that has not
-- left in 48 hours is marked Failed, saying why, so the team can send it
-- again. 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored byte
-- for byte in supabase/schema.sql under the same banner; tests/sql.js
-- compares the two.
--
-- WHAT CHANGED (review item 8)
--   WHATSAPP OUTAGE SPENDS NO TRY gives a request that never left its try
--   back, so a message caught by a long outage stayed Queued for ever: the
--   drain woke for it every five minutes, Sent recently counted it as sent
--   (so nobody was asked before sending it again), and privacy_retention,
--   which never clears a queued row, kept its number and words.
--   * wa_expire(p_now) marks every row still Queued 48 hours after it was
--     queued as Failed, with the error `expired: not sent within 48 hours`
--     (the WhatsApp section reads it in the team's words). A message Meta
--     accepted, or one at Sending or Not confirmed, is never touched.
--   * wa_claim runs it before it claims, and pg_cron `wa-expire` every
--     hour, so it holds whether or not the drain wakes. A failed row is
--     cleared by privacy_retention on the same twelve months as any other.
--     Not a page's to call.
--
-- ROLLBACK
--   select cron.unschedule(jobid) from cron.job where jobname = 'wa-expire';
--   then run wa_claim again from WHATSAPP QUEUE A FEW AT A TIME. wa_expire
--   is left in place, unused (a failed row is sent again by hand).
-- ===========================================================================

create or replace function public.wa_expire(p_now timestamptz default now())
returns integer
language plpgsql security definer set search_path = public as $$
declare v_n integer := 0;
begin
  update public.wa_outbox o
     set state = 'failed', error = 'expired: not sent within 48 hours'
   where o.state = 'queued' and o.created_at < p_now - interval '48 hours';
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.wa_expire(timestamptz) from public, anon, authenticated;

create or replace function public.wa_claim(p_limit integer default 1)
returns setof public.wa_outbox
language plpgsql security definer set search_path = public as $$
begin
  /* A message that has not left in 48 hours is failed, so it can be sent again. */
  perform public.wa_expire();
  /* A send cut off mid-way may have reached Meta: it is never sent again. */
  update public.wa_outbox o
     set state = 'unknown', error = 'unknown: the send was cut off before WhatsApp answered'
   where o.state = 'sending' and o.claimed_at < now() - interval '5 minutes';
  return query
  update public.wa_outbox o set state = 'sending', claimed_at = now(), tries = o.tries + 1
   where o.id in (select x.id from public.wa_outbox x
                   where x.state = 'queued' and x.tries < 3
                   order by x.created_at limit greatest(1, least(coalesce(p_limit, 1), 5))
                   for update skip locked)
  returning o.*;
end $$;
revoke all on function public.wa_claim(integer) from public, anon, authenticated;

/* Every hour, whether or not the drain wakes: the queue's own clock. */
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: a queued message waits for the next drain to be failed.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'wa-expire';
  perform cron.schedule('wa-expire', '23 * * * *', 'select public.wa_expire()');
end $$;

-- END OF WHATSAPP QUEUE GIVES UP AFTER 48 HOURS -----------------------------

select public.functions_tidy();
