-- ===========================================================================
-- WHATSAPP QUEUE A FEW AT A TIME — the queue hands `wa-send` no more rows
-- than it can send before its time runs out. 2026-10-17. Safe to run twice.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the review of the audit's fix batches, finding 4)
--   `wa-send` claimed twenty rows a round with up to 25 seconds a send, past
--   the edge function's time limit. The rows it never reached were left at
--   Sending, and `wa_claim` marks a row left at Sending for five minutes Not
--   confirmed, never sent: messages that never went out were lost. The
--   function now claims one row at a time and starts no send after 90
--   seconds (and a request that never left is tried again, not marked Not
--   confirmed). `wa_claim` takes one row unless asked for more, and never
--   more than five, so no caller can claim more than it will send.
--
-- ROLLBACK
--   Run wa_claim again from WHATSAPP SENDS NEVER REPEATED (2026-10-17).
-- ===========================================================================

create or replace function public.wa_claim(p_limit integer default 1)
returns setof public.wa_outbox
language plpgsql security definer set search_path = public as $$
begin
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

-- END OF WHATSAPP QUEUE A FEW AT A TIME ---------------------------------------

select public.functions_tidy();
