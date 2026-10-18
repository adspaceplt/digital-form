-- ===========================================================================
-- PERSONAL DATA KEPT FOR A TIME — a WhatsApp message's number, name and
-- words are cleared after twelve months, and the Activity record keeps three
-- years. 2026-10-18. Safe to run twice. Rollback at the foot. Mirrored byte
-- for byte in supabase/schema.sql under the same banner; tests/sql.js
-- compares the two.
--
-- WHAT CHANGED (second audit, item 17; PDPA 2010 and 2012: keep personal
-- data no longer than its purpose needs)
--   Nothing ever left wa_outbox or activity_log. privacy_retention(p_now)
--   (pg_cron `privacy-retention`, 02:45 MYT on the 2nd of each month):
--   * clears a WhatsApp message's number (to_number, left empty, as the
--     column refuses none), name, variables and link code (to_name, params,
--     button) twelve months after it was queued, never one still queued or
--     sending; what was sent, when, to which record and how it went stay,
--     so the counts and the record of the send do not change (the WhatsApp
--     section lists the last twelve months alone);
--   * removes Activity record rows older than three years.
--   Not a page's to call. Performance's own trail (perf_events), HR letters
--   and the documents keep their own rules. The nightly database dump keeps
--   what it held on its day: its expiry is a lifecycle rule on
--   private/backups/db/ in S3, the user's to set (STANDARD.md).
--
-- ROLLBACK
--   select cron.unschedule(jobid) from cron.job where jobname = 'privacy-retention';
--   drop function if exists public.privacy_retention(timestamptz);
--   (what was cleared or removed is not brought back: it is in the dumps).
-- ===========================================================================

create or replace function public.privacy_retention(p_now timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_wa integer := 0; v_act integer := 0;
begin
  update public.wa_outbox o
     set to_number = '', to_name = null, params = '[]'::jsonb, button = null
   where o.created_at < p_now - interval '12 months'
     and o.state not in ('queued', 'sending')
     and (o.to_number <> '' or o.to_name is not null or o.params <> '[]'::jsonb or o.button is not null);
  get diagnostics v_wa = row_count;
  delete from public.activity_log a where a.created_at < p_now - interval '3 years';
  get diagnostics v_act = row_count;
  return jsonb_build_object('whatsapp_cleared', v_wa, 'activity_removed', v_act);
end $$;
revoke all on function public.privacy_retention(timestamptz) from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: personal data is not cleared until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'privacy-retention';
  perform cron.schedule('privacy-retention', '45 18 1 * *', 'select public.privacy_retention()');
end $$;

-- END OF PERSONAL DATA KEPT FOR A TIME --------------------------------------

select public.functions_tidy();
