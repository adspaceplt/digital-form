-- ===========================================================================
-- SEND SWITCHES (2026-11-21)
-- ===========================================================================
-- WHY: the user, 2026-11-21, approving the send switches' model on a
-- mockup: "send by email ... is still required ... manually sending each
-- client, each supplier ... template based or non-template based". Send by
-- email governed a quotation, a Letter of Offer and a client letter alone;
-- every other email a colleague sends by hand ignored it, and WhatsApp sent
-- by hand had no switch of its own.
--
-- WHAT IT CHANGES
--   * `app_settings` key `client_wa_on` (1 On, 0 Off; seeded On from the
--     start, so nothing sent today stops): Send on WhatsApp, every WhatsApp
--     a colleague sends by hand.
--   * `manual_send_on(p_channel)` (no caller's): the portal's switch
--     (Email, WhatsApp) and the switch for sends by hand under it (Send by
--     email `client_email_on`, Send on WhatsApp `client_wa_on`).
--   * `send_ok(p_channel)` and `send_ok_of(p_member, p_channel)` (restated
--     from GROUP SWITCHES) ask `manual_send_on` and then the group's switch
--     (Send email, Send WhatsApp). Every email and WhatsApp sent by hand
--     already asks them: a quotation, a Letter of Offer, a client letter,
--     an overdue reminder, an invoice email, a supplier's emails, New email,
--     Send again, every WhatsApp composed and a quotation released on
--     WhatsApp; each refuses `send-off` as before. An automatic send keeps
--     `auto_send_on`; a sign-in code, an invitation and a verification code
--     ask no switch.
--   * `manual_send_set(p_channel, p_on)` (`team.settings`): Settings,
--     Messages: Send by email and Send on WhatsApp, filed `team.changed`
--     under Settings from and to. `client_email_set` stays for a page
--     served before.
--
-- ORDER: this file, then the pages. An old page meets the same refusals
-- (`send-off`, `email-off`); a new page on the old database reads no
-- `client_wa_on` (On) and its Send on WhatsApp switch is refused as not
-- available. Safe to run twice.
--
-- ROLLBACK: restore `send_ok` and `send_ok_of` from GROUP SWITCHES; drop
-- `manual_send_set(text, boolean)` and `manual_send_on(text)`; delete the
-- `client_wa_on` rows of `app_settings`.

insert into public.app_settings (key, from_date, value)
select 'client_wa_on', date '2023-08-14', 1
 where not exists (select 1 from public.app_settings s where s.key = 'client_wa_on');

create or replace function public.manual_send_on(p_channel text)
returns boolean language sql stable security definer set search_path = public as $$
  select p_channel in ('email', 'whatsapp') and public.portal_on(p_channel || '_on')
     and coalesce(public.app_setting(case p_channel when 'email' then 'client_email_on' else 'client_wa_on' end,
                                     (now() at time zone 'Asia/Kuala_Lumpur')::date), 1) = 1
$$;
revoke all on function public.manual_send_on(text) from public, anon, authenticated;

create or replace function public.send_ok(p_channel text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.manual_send_on(p_channel)
     and public.team_switch_of((public.ops_me()).id, p_channel || '_on')
$$;
revoke all on function public.send_ok(text) from public, anon, authenticated;

create or replace function public.send_ok_of(p_member uuid, p_channel text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.manual_send_on(p_channel)
     and public.team_switch_of(p_member, p_channel || '_on')
$$;
revoke all on function public.send_ok_of(uuid, text) from public, anon, authenticated;

create or replace function public.manual_send_set(p_channel text, p_on boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_key   text := case p_channel when 'email' then 'client_email_on' when 'whatsapp' then 'client_wa_on' end;
  v_was   numeric;
  v_to    numeric := case when coalesce(p_on, false) then 1 else 0 end;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_key is null then return jsonb_build_object('error', 'bad-kind'); end if;
  v_was := coalesce(public.app_setting(v_key, v_today), 1);
  if v_was is not distinct from v_to then return jsonb_build_object('ok', true); end if;
  insert into public.app_settings (key, from_date, value, set_by, set_at)
  values (v_key, v_today, v_to, me.id, now())
  on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Settings',
          case p_channel when 'email' then 'Send by email: ' else 'Send on WhatsApp: ' end ||
          case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_to = 1 then 'On' else 'Off' end ||
          ' · from ' || public.register_day(v_today));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.manual_send_set(text, boolean) from public, anon;
grant execute on function public.manual_send_set(text, boolean) to authenticated;

-- END OF SEND SWITCHES ------------------------------------------------------

select public.functions_tidy();
