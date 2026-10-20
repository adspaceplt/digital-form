-- ===========================================================================
-- WHATSAPP FEEDBACK SENT ONCE — a feedback request sent from New message is
-- Sent recently for the client's record too, and the other way round
-- (2026-10-20)
-- ===========================================================================
-- WHY (the wave 2 UX review, WA-1): a feedback request sent from the
-- WhatsApp section's New message is filed with purpose `message`, and one
-- sent from the client's ⋯ with purpose `feedback`. `wa_sent_recently`
-- matched the purpose first, so the same template to the same person went
-- twice within the hour without the question.
--
-- WHAT IT CHANGES
--   * `wa_sent_recently`: for a feedback request or a plain message, a
--     message of the same template to the same recipient within the hours
--     set is Sent recently whatever purpose it was filed under. Every other
--     match and every refusal is as before. `wa_send_begin` asks it, so the
--     send itself refuses `recent` the same way.
--
-- ORDER: the pages, then this file. An old page asks the same function with
-- the same arguments. Safe to run twice. Rollback: WHATSAPP SENDS NEVER
-- REPEATED's definition of `wa_sent_recently`.
-- ===========================================================================

create or replace function public.wa_sent_recently(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid, p_template text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_prep  jsonb;
  v_hours numeric := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  v_ref   uuid;
  v_tpl   text := coalesce(nullif(btrim(p_template), ''), '');
  w       public.wa_outbox;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  v_prep := public.wa_compose_prepare(p_to_kind, p_to, p_purpose, p_ref);
  if v_prep ? 'error' then return v_prep; end if;
  if v_hours <= 0 then return jsonb_build_object('ok', true, 'recent', false, 'hours', 0); end if;
  v_ref := case when p_purpose = 'feedback' then (v_prep ->> 'client_id')::uuid
                when p_purpose = 'message' then null else p_ref end;
  select * into w from public.wa_outbox x
   where x.to_kind = p_to_kind and x.to_id = p_to
     and x.state in ('queued', 'sending', 'sent', 'unknown')
     and x.created_at > now() - make_interval(hours => v_hours::int)
     and ((x.purpose = p_purpose
           and x.ref_id is not distinct from v_ref
           and (p_purpose <> 'message' or x.template = v_tpl))
       -- a feedback request or a plain message: the same template to the
       -- same person, whatever purpose it was filed under
       or (p_purpose in ('feedback', 'message') and v_tpl <> '' and x.template = v_tpl))
   order by x.created_at desc limit 1;
  if w.id is null then return jsonb_build_object('ok', true, 'recent', false, 'hours', v_hours); end if;
  return jsonb_build_object('ok', true, 'recent', true, 'hours', v_hours, 'at', w.created_at,
    'by', case when w.created_by = 'system' then null else w.created_by end, 'to', w.to_name, 'state', w.state);
end $$;
revoke all on function public.wa_sent_recently(text, uuid, text, uuid, text) from public, anon;
grant execute on function public.wa_sent_recently(text, uuid, text, uuid, text) to authenticated;

-- END OF WHATSAPP FEEDBACK SENT ONCE ----------------------------------------
select public.functions_tidy();
