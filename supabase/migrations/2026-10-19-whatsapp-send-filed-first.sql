-- ===========================================================================
-- WHATSAPP SEND FILED FIRST — a message sent by hand is filed as Sending
-- before it goes, under a lock, so two quick presses send it once.
-- 2026-10-19. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED
--   wa-send asked Sent recently, then sent, and filed the message only once
--   Meta answered (`wa_sent`), so two presses close together both passed
--   the check and both sent; a send WhatsApp never confirmed was filed
--   Failed, so it did not count as sent; and the sends from before the
--   composer (`report`, `feedback`, `wa_creator_send`) asked nothing at all
--   (the third audit, item 9).
--   * wa_send_begin(p_to_kind, p_to, p_purpose, p_ref, p_template, p_lang,
--     p_category, p_params, p_again) asks wa_compose_prepare as the caller,
--     takes a lock on the recipient, the purpose and the record, refuses
--     `sending` while the same message is on its way, refuses `recent`
--     (as wa_sent_recently answers) unless `p_again`, and files the message
--     as Sending before anything is sent.
--   * wa_send_done(p_id, p_ok, p_wa_id, p_error) closes it, the caller's
--     own row alone: Sent, Not confirmed (an `unknown:` answer, which counts
--     as Sent recently and is never sent again by itself) or Failed, and
--     files `wa.sent` as wa_sent did.
--   * The sends from before the composer are closed to every browser:
--     wa_report_prepare, wa_feedback_prepare, wa_record and wa_creator_send
--     (no page has called them since the composer, 2026-10-10); wa-send no
--     longer answers `report` or `feedback`.
--   wa_sent stays for wa-send as deployed before this file.
--
-- ROLLBACK
--   Redeploy the earlier wa-send first. Then
--     revoke all on function public.wa_send_begin(text, uuid, text, uuid, text, text, text, jsonb, boolean) from public, anon, authenticated;
--     revoke all on function public.wa_send_done(uuid, boolean, text, text) from public, anon, authenticated;
--   and, for a page still calling them, grant execute on the four retired
--   functions to authenticated again.
-- ===========================================================================

create or replace function public.wa_send_begin(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid, p_template text,
                                                p_lang text, p_category text, p_params jsonb, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  p      jsonb;
  v_rc   jsonb;
  v_ref  uuid;
  v_tpl  text := coalesce(nullif(btrim(p_template), ''), '');
  v_id   uuid;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  p := public.wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref);
  if p ? 'error' then return p; end if;
  if v_tpl = '' then return jsonb_build_object('error', 'bad-request'); end if;
  -- the same message as wa_sent_recently reads it: a feedback request by
  -- its client, a plain message by its template, anything else its record
  v_ref := case when p_purpose = 'feedback' then (p ->> 'client_id')::uuid
                when p_purpose = 'message' then null else p_ref end;
  -- one send at a time of one message to one person: a second press waits
  -- here until the first is filed, then reads it
  perform pg_advisory_xact_lock(hashtextextended('wa_send:' || p_to_kind || ':' || p_to::text || ':' || p_purpose || ':' ||
    coalesce(v_ref::text, '') || ':' || case when p_purpose = 'message' then v_tpl else '' end, 0));
  if exists (select 1 from public.wa_outbox x
              where x.to_kind = p_to_kind and x.to_id = p_to and x.purpose = p_purpose and x.state = 'sending'
                and x.ref_id is not distinct from v_ref and (p_purpose <> 'message' or x.template = v_tpl)
                and x.claimed_at > now() - interval '5 minutes') then
    return jsonb_build_object('error', 'sending');
  end if;
  if not coalesce(p_again, false) then
    v_rc := public.wa_sent_recently(p_to_kind, p_to, p_purpose, p_ref, v_tpl);
    if coalesce((v_rc ->> 'recent')::boolean, false) then return jsonb_build_object('error', 'recent', 'recent', v_rc); end if;
  end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, state,
                                created_by, claimed_at, tries, to_kind, to_id, category)
  values (p_purpose, p ->> 'number', p ->> 'name', v_tpl, coalesce(nullif(btrim(p_lang), ''), 'en'),
          case when jsonb_typeof(p_params) = 'array' then p_params else '[]'::jsonb end,
          case p_purpose when 'report' then 'report' when 'creator' then 'option' when 'feedback' then 'client'
                         when 'approval' then p ->> 'ref_kind' when 'quotation' then 'quotation' when 'offer' then 'offer' end,
          case when p_purpose in ('report', 'creator', 'approval', 'quotation', 'offer') then p_ref when p_purpose = 'feedback' then (p ->> 'client_id')::uuid end,
          (p ->> 'client_id')::uuid, 'sending', me.name, now(), 1, p_to_kind, p_to,
          nullif(lower(btrim(coalesce(p_category, ''))), ''))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.wa_send_begin(text, uuid, text, uuid, text, text, text, jsonb, boolean) from public, anon;
grant execute on function public.wa_send_begin(text, uuid, text, uuid, text, text, text, jsonb, boolean) to authenticated;

create or replace function public.wa_send_done(p_id uuid, p_ok boolean, p_wa_id text, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  w      public.wa_outbox;
  p      jsonb;
  v_word text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into w from public.wa_outbox x
   where x.id = p_id and x.state = 'sending' and x.created_by = me.name and x.to_kind is not null for update;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.wa_outbox x
     set state = case when coalesce(p_ok, false) then 'sent'
                      when coalesce(p_error, '') like 'unknown:%' then 'unknown' else 'failed' end,
         wa_id = left(p_wa_id, 200), error = left(p_error, 500),
         sent_at = case when coalesce(p_ok, false) then now() end
   where x.id = w.id;
  if coalesce(p_ok, false) then
    p := public.wa_compose_prepare(w.to_kind, w.to_id, w.purpose,
           case when w.purpose in ('feedback', 'message') then null else w.ref_id end);
    v_word := case w.purpose when 'report' then 'Report' when 'feedback' then 'Feedback request'
                             when 'creator' then 'Booking' when 'approval' then 'Approval reminder'
                             when 'quotation' then 'Quotation' when 'offer' then 'Letter of Offer' else 'Message' end;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'wa.sent', coalesce(p ->> 'subject', w.to_name),
            case when w.purpose = 'creator' then w.to_name || ' · Booking sent on WhatsApp'
                 else v_word || ' sent on WhatsApp to ' || coalesce(nullif(btrim(w.to_name), ''), 'the contact') end);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.wa_send_done(uuid, boolean, text, text) from public, anon;
grant execute on function public.wa_send_done(uuid, boolean, text, text) to authenticated;

-- The sends from before the composer, closed to every browser (a function
-- already removed is passed over).
do $$
declare f text;
begin
  foreach f in array array['public.wa_report_prepare(uuid)', 'public.wa_feedback_prepare(uuid)',
    'public.wa_record(text, uuid, uuid, text, text, text, jsonb, boolean, text, text)', 'public.wa_creator_send(uuid)'] loop
    if to_regprocedure(f) is not null then
      execute 'revoke all on function ' || f || ' from public, anon, authenticated';
    end if;
  end loop;
end $$;

-- END OF WHATSAPP SEND FILED FIRST ------------------------------------------

select public.functions_tidy();
