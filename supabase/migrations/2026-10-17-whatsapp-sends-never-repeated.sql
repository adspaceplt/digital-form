-- ===========================================================================
-- WHATSAPP SENDS NEVER REPEATED — a message whose send may have gone out is
-- marked Not confirmed and never sent again by itself, and the queues are
-- drained every five minutes. 2026-10-17. Safe to run twice. Rollback at the
-- foot. Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/sql.js compares the two.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding C)
--   `wa-send` put a message back in the queue whenever its request to Meta
--   failed, a connection that dropped or timed out after Meta had taken the
--   message included, and `wa_claim` took a row left at Sending for five
--   minutes (the function cut off mid-send) and sent it again: a client or
--   creator could be messaged twice or three times. And the queues were
--   woken only by the write that filled them (`wa_kick`, `push_kick`), so a
--   wake that failed left a message waiting until the next one.
--   1. `wa_outbox.state` takes `unknown` (Not confirmed): Meta may have it,
--      nobody knows. Trigger `wa_outbox_unknown` turns a failure whose
--      reason starts `unknown:` into it, as `wa-send` files one (a dropped
--      connection, a timeout, Meta answering 5xx), through `wa_done`,
--      `wa_sent` or `wa_record` alike. `wa_done` never queues it again.
--   2. `wa_claim` takes queued rows alone; a row left at Sending past five
--      minutes is marked Not confirmed, never sent again.
--   3. `wa_sent_recently` counts a Not confirmed message as sent, so sending
--      it again by hand asks first (Sent recently).
--   4. pg_cron `outbox-drain`, every five minutes, wakes `wa-send` and
--      `push-send` only while their queue holds something to send.
--
-- ROLLBACK
--   select cron.unschedule('outbox-drain');
--   drop trigger if exists wa_outbox_unknown on public.wa_outbox;
--   Run wa_claim, wa_done and wa_sent_recently again from their sections;
--   update public.wa_outbox set state = 'failed' where state = 'unknown';
--   and put the state check back to its four states.
-- ===========================================================================

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.wa_outbox'::regclass and contype = 'c'
                    and pg_get_constraintdef(oid) like '%unknown%') then
    alter table public.wa_outbox drop constraint if exists wa_outbox_state_check;
    alter table public.wa_outbox add constraint wa_outbox_state_check
      check (state in ('queued', 'sending', 'sent', 'unknown', 'failed'));
  end if;
end $$;

create or replace function public.wa_outbox_unknown()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.state in ('failed', 'queued') and coalesce(new.error, '') like 'unknown:%' then
    new.state := 'unknown';
  end if;
  return new;
end $$;
revoke all on function public.wa_outbox_unknown() from public, anon, authenticated;

create or replace trigger wa_outbox_unknown before insert or update on public.wa_outbox
  for each row execute function public.wa_outbox_unknown();

create or replace function public.wa_claim(p_limit integer default 20)
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
                   order by x.created_at limit greatest(1, least(coalesce(p_limit, 20), 50))
                   for update skip locked)
  returning o.*;
end $$;
revoke all on function public.wa_claim(integer) from public, anon, authenticated;

create or replace function public.wa_done(p_id uuid, p_ok boolean, p_wa_id text, p_error text)
returns void
language sql security definer set search_path = public as $$
  update public.wa_outbox o
     set state = case when p_ok then 'sent'
                      when coalesce(p_error, '') like 'unknown:%' then 'unknown'
                      when o.tries >= 3 then 'failed' else 'queued' end,
         wa_id = left(p_wa_id, 200), error = left(p_error, 500), sent_at = case when p_ok then now() end
   where o.id = p_id
$$;
revoke all on function public.wa_done(uuid, boolean, text, text) from public, anon, authenticated;

create or replace function public.wa_sent_recently(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid, p_template text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_prep  jsonb;
  v_hours numeric := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  v_ref   uuid;
  w       public.wa_outbox;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  v_prep := public.wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref);
  if v_prep ? 'error' then return v_prep; end if;
  if v_hours <= 0 then return jsonb_build_object('ok', true, 'recent', false, 'hours', 0); end if;
  v_ref := case when p_purpose = 'feedback' then (v_prep ->> 'client_id')::uuid
                when p_purpose = 'message' then null else p_ref end;
  select * into w from public.wa_outbox x
   where x.to_kind = p_to_kind and x.to_id = p_to and x.purpose = p_purpose
     and x.state in ('queued', 'sending', 'sent', 'unknown')
     and x.created_at > now() - make_interval(hours => v_hours::int)
     and x.ref_id is not distinct from v_ref
     and (p_purpose <> 'message' or x.template = coalesce(p_template, ''))
   order by x.created_at desc limit 1;
  if w.id is null then return jsonb_build_object('ok', true, 'recent', false, 'hours', v_hours); end if;
  return jsonb_build_object('ok', true, 'recent', true, 'hours', v_hours, 'at', w.created_at,
    'by', case when w.created_by = 'system' then null else w.created_by end, 'to', w.to_name, 'state', w.state);
end $$;
revoke all on function public.wa_sent_recently(text, uuid, text, uuid, text) from public, anon;
grant execute on function public.wa_sent_recently(text, uuid, text, uuid, text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: the queues are woken by their writes alone until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'outbox-drain';
  perform cron.schedule('outbox-drain', '*/5 * * * *',
    'select public.wa_kick() where exists (select 1 from public.wa_outbox o where o.state = ''queued'' or (o.state = ''sending'' and o.claimed_at < now() - interval ''5 minutes'')); '
    || 'select public.push_kick() where exists (select 1 from public.push_outbox o where o.sent_at is null and (o.claimed_at is null or o.claimed_at < now() - interval ''5 minutes'') and o.created_at > now() - interval ''2 days'')');
end $$;

-- END OF WHATSAPP SENDS NEVER REPEATED ---------------------------------------

select public.functions_tidy();
