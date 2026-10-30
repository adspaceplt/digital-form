-- ===========================================================================
-- QUOTATION RESENT ON WHATSAPP — the prospect's link sent again (2026-10-30)
-- ===========================================================================
-- WHY (the user, 2026-10-30: "if prospects missed the link how do we send
-- them to proceed", then "build the resend on WhatsApp too"): the
-- quotation-ready WhatsApp, whose button opens the prospect's own link, went
-- once, at Send quotation, and nothing sent it again.
--
-- WHAT IT CHANGES
--   `quotation_resend(p_id, p_again)` (Clients: Quotations at Work, the
--   client in scope) queues the `quote_ready` WhatsApp again for a website
--   quotation the team has sent, still valid, not revised, not Not
--   proceeding and not marked Do not contact (`not-sent`, `expired`,
--   `revised`, `not-proceeding`, `no-contact`, `bad-quotation`,
--   `not-found`), its template on (`wa-off`) and a number to send to
--   (`no-number`). One already queued or sent within `wa_repeat_hours` is
--   answered `recent` with when and by whom unless asked again (`p_again`),
--   under a lock on the quotation. The message is filed under the colleague
--   who sent it, and the quotation under Clients.
--
-- ORDER: this file, then the pages (an old console offers no Resend).
-- Safe to run twice.
--
-- ROLLBACK: drop function public.quotation_resend(uuid, boolean); (SQL
-- Editor; nothing else changes).
-- ===========================================================================

create or replace function public.quotation_resend(p_id uuid, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  t  public.wa_templates;
  o  public.wa_outbox;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_hours numeric;
  v_wa text;
  v_name text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.source <> 'website' or q.access_key is null then return jsonb_build_object('error', 'bad-quotation'); end if;
  if q.released_at is null then return jsonb_build_object('error', 'not-sent'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if q.valid_until is not null and q.valid_until < v_today then return jsonb_build_object('error', 'expired'); end if;
  if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  select * into t from public.wa_templates x where x.purpose = 'quote_ready' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  v_wa := public.quote_website_number(q.contact->>'whatsapp');
  if v_wa is null or v_wa !~ '^(60|65)[0-9]{8,10}$' then return jsonb_build_object('error', 'no-number'); end if;
  v_hours := coalesce(public.app_setting('wa_repeat_hours', v_today), 24);
  if v_hours > 0 and not coalesce(p_again, false) then
    select * into o from public.wa_outbox x
     where x.purpose = 'quote_ready' and x.ref_id = q.id and x.state <> 'failed'
       and x.created_at > now() - make_interval(secs => v_hours * 3600)
     order by x.created_at desc limit 1;
    if o.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', o.created_at,
        'by', case when coalesce(o.created_by, 'system') = 'system' then null else o.created_by end));
    end if;
  end if;
  v_name := coalesce(nullif(btrim(q.contact->>'name'), ''), q.brand);
  perform public.wa_enqueue('quote_ready', v_wa, v_name,
    jsonb_build_array(public.contact_greeting(q.contact->>'salutation', v_name),
                      coalesce(q.contact->>'brand', q.brand), q.ref),
    'quotation', q.id, q.client_id, q.access_key);
  update public.wa_outbox x set created_by = me.name
   where x.purpose = 'quote_ready' and x.ref_id = q.id and x.created_at = now() and x.created_by = 'system';
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand, q.ref || ' sent again to the prospect on WhatsApp');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_resend(uuid, boolean) from public, anon;
grant execute on function public.quotation_resend(uuid, boolean) to authenticated;

-- END OF QUOTATION RESENT ON WHATSAPP -----------------------------------------

select public.functions_tidy();
