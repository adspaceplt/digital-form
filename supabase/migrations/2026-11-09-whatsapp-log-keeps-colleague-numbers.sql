-- ===========================================================================
-- WHATSAPP LOG KEEPS COLLEAGUE NUMBERS (2026-11-09)
-- ===========================================================================
-- WHY (security audit run 2, 2026-11-09; the user's scheduled audit: "fix and
-- release confirmed ones"):
-- wa_messages returned colleagues' mobiles (withheld from the team table) to every
-- Messages View holder.
--
-- WHAT IT CHANGES
--   wa_messages shows a colleague recipient's number as its last four digits without Team View.
--
-- ORDER: this file, then the pages. Safe to run twice.
--
-- ROLLBACK: run the earlier wa_messages (WHATSAPP SECTION band) again.
-- ===========================================================================

-- WHATSAPP LOG KEEPS COLLEAGUE NUMBERS --------------------------------------

/* A colleague's mobile is Team's to read (security audit 2026-11-09): the
   team table withholds it from its column grants, and the namecard shows it
   only where the colleague chose Show. The reminders queued on WhatsApp to a
   colleague carry no client, so wa_messages returned their number whole to
   every Messages View holder. A colleague recipient's number now reads as
   its last four digits to a reader without Team View, as wa_recent read it. */
create or replace function public.wa_messages(p_month date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_from date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Kuala_Lumpur')::date))::date;
  v_a    timestamptz;
  v_b    timestamptz;
  v_team boolean := public.allowed('team', 'view');
begin
  if me.id is null or not public.allowed('whatsapp', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_a := v_from::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_b := (v_from + interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur';
  return jsonb_build_object(
    'month', v_from,
    'items', coalesce((select jsonb_agg(x order by x.created_at desc) from (
        select o.id, o.purpose, o.template, o.category, o.to_kind, o.to_name,
               case when o.to_kind = 'colleague' and not v_team and o.to_number <> ''
                    then '••••' || right(o.to_number, 4) else o.to_number end as to_number, o.client_id,
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

-- END OF WHATSAPP LOG KEEPS COLLEAGUE NUMBERS -------------------------------


select public.functions_tidy();
