-- ===========================================================================
-- WHATSAPP NOT CONFIRMED COUNTED — the queue's tally counts the messages
-- marked Not confirmed beside those not sent. 2026-10-17. Safe to run twice.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the review of the audit's fix batches, finding 11)
--   WHATSAPP SENDS NEVER REPEATED marks a send whose answer never came
--   `unknown` (Not confirmed) and never sends it again, but `wa_messages`'
--   queue counted `failed` alone, so nothing on Templates warned of them.
--   It now counts `unknown` of the last seven days too, which the page
--   shows in the warning tally (js/whatsapp.js).
--
-- ROLLBACK
--   Run wa_messages again from WHATSAPP GREETING AND COUNTS (2026-10-15).
-- ===========================================================================

create or replace function public.wa_messages(p_month date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_from date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Kuala_Lumpur')::date))::date;
  v_a    timestamptz;
  v_b    timestamptz;
begin
  if me.id is null or not public.allowed('whatsapp', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_a := v_from::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_b := (v_from + interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur';
  return jsonb_build_object(
    'month', v_from,
    'items', coalesce((select jsonb_agg(x order by x.created_at desc) from (
        select o.id, o.purpose, o.template, o.category, o.to_kind, o.to_name, o.to_number, o.client_id,
               c.name as client, o.state, o.error, o.created_at, o.sent_at, o.created_by,
               o.delivered_at, o.read_at, o.failed_at, o.fail_code, o.fail_title, o.ref_kind, o.ref_id
          from public.wa_outbox o
          left join public.clients c on c.id = o.client_id
         where o.created_at >= v_a and o.created_at < v_b
           and (o.client_id is null or public.client_seen(o.client_id, 'view'))
         order by o.created_at desc
         limit 2000) x), '[]'::jsonb),
    'counts', (select jsonb_build_object(
        'utility',        count(*) filter (where o.category = 'utility'),
        'marketing',      count(*) filter (where o.category = 'marketing'),
        'authentication', count(*) filter (where o.category = 'authentication'))
      from public.wa_outbox o
     where o.state = 'sent' and o.failed_at is null and o.created_at >= v_a and o.created_at < v_b),
    'queue', (select jsonb_build_object(
        'queued',  count(*) filter (where o.state = 'queued'),
        'sending', count(*) filter (where o.state = 'sending'),
        'failed',  count(*) filter (where o.state = 'failed' and o.created_at > now() - interval '7 days'),
        -- Not confirmed: may have reached the person, so a colleague looks
        -- before sending again (2026-10-17).
        'unknown', count(*) filter (where o.state = 'unknown' and o.created_at > now() - interval '7 days'),
        'oldest',  min(o.created_at) filter (where o.state in ('queued', 'sending')))
      from public.wa_outbox o));
end $$;
revoke all on function public.wa_messages(date) from public, anon;
grant execute on function public.wa_messages(date) to authenticated;

-- END OF WHATSAPP NOT CONFIRMED COUNTED ------------------------------------

select public.functions_tidy();
