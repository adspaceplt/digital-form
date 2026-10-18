-- ===========================================================================
-- WHATSAPP OUTAGE SPENDS NO TRY — a queued message that could not leave, or
-- that Meta held back for its throughput limit, keeps its three tries.
-- 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED
--   wa-send's drain stops at a request that never left (`not sent:`), so a
--   wake spends one try, but wa_done still counted it: an outage longer
--   than three wakes (about ten minutes) failed the oldest waiting message,
--   then the next. Meta's throughput limit (130429, read as wa-busy) counted
--   a try too, though it sent nothing.
--   * wa_done files a `not sent:` answer back to the queue and gives its
--     try back (tries less one, never below zero), so only Meta's own
--     refusal of the message spends one; an outage of any length fails
--     nothing, and the message goes once the way is clear.
--   * wa-send's drain files Meta's 130429 as `not sent:` and stops, as it
--     does a request that never left (supabase/functions/wa-send).
--
-- ROLLBACK
--   Run the wa_done definition of the WHATSAPP SENDS NEVER REPEATED section
--   of supabase/schema.sql again.
-- ===========================================================================

create or replace function public.wa_done(p_id uuid, p_ok boolean, p_wa_id text, p_error text)
returns void
language sql security definer set search_path = public as $$
  update public.wa_outbox o
     set state = case when p_ok then 'sent'
                      when coalesce(p_error, '') like 'unknown:%' then 'unknown'
                      when coalesce(p_error, '') like 'not sent:%' then 'queued'
                      when o.tries >= 3 then 'failed' else 'queued' end,
         tries = case when not p_ok and coalesce(p_error, '') like 'not sent:%' then greatest(0, o.tries - 1) else o.tries end,
         wa_id = left(p_wa_id, 200), error = left(p_error, 500), sent_at = case when p_ok then now() end
   where o.id = p_id
$$;
revoke all on function public.wa_done(uuid, boolean, text, text) from public, anon, authenticated;

-- END OF WHATSAPP OUTAGE SPENDS NO TRY --------------------------------------

select public.functions_tidy();
