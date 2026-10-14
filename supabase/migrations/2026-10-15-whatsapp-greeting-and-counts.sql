-- ===========================================================================
-- WHATSAPP GREETING AND COUNTS — a name led by its salutation, and a message
-- Meta failed left out of the month's sent (2026-10-15)
-- ===========================================================================
-- WHY (ux-audit WA-4 and WA-5, 2026-10-14)
--   * A contact with no salutation is greeted by the first word of the name,
--     so a name typed as "Ms Tan" greeted "Dear Ms,". No live contact was so
--     named on 2026-10-14; one keyed so later would be.
--   * The month's templates sent by category counted a message Meta later
--     reported as failed (`state` sent, `failed_at` set), which Meta does
--     not charge.
--
-- WHAT IT CHANGES
--   * `contact_greeting(salutation, name)`: with no salutation, a name whose
--     first word is a salutation (Mr, Ms, Mrs, Mdm, Dr, Prof, Dato', Datin,
--     Datuk, Puan Sri, Tun, Tuan, Puan, Encik, Cik, Madam or Miss; never Tan,
--     a surname too), with or without a full stop, is greeted whole.
--   * `wa_messages(p_month)`: `counts` leaves out a message with `failed_at`.
--
-- Safe to run twice. Rollback: restate both functions from
-- 2026-10-09-contact-salutation.sql and 2026-10-10-whatsapp-section.sql.
-- ===========================================================================

create or replace function public.contact_greeting(p_salutation text, p_name text)
returns text
language sql immutable set search_path = public as $$
  select case when nullif(btrim(coalesce(p_salutation, '')), '') is not null
              then btrim(p_salutation) || ' ' || btrim(coalesce(p_name, ''))
              when lower(split_part(btrim(coalesce(p_name, '')), ' ', 1)) ~ '^(mr|ms|mrs|mdm|dr|prof|dato''?|datin|datuk|puan|tun|tuan|encik|cik|madam|miss)\.?$'
               and position(' ' in btrim(coalesce(p_name, ''))) > 0
              then btrim(p_name)
              else split_part(btrim(coalesce(p_name, '')), ' ', 1) end
$$;

revoke all on function public.contact_greeting(text, text) from public, anon, authenticated;

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
        'oldest',  min(o.created_at) filter (where o.state in ('queued', 'sending')))
      from public.wa_outbox o));
end $$;
revoke all on function public.wa_messages(date) from public, anon;
grant execute on function public.wa_messages(date) to authenticated;

-- END OF WHATSAPP GREETING AND COUNTS ----------------------------------------
select public.functions_tidy();
