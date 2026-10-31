-- ===========================================================================
-- CLIENT DETAILS LINK CLOSED — a client's details form link stops opening at
-- a press, with no new one made (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31, approving an audit of a client record's tabs):
-- Billing's Request from client offered Reset link alone, so a link sent in
-- error, or no longer wanted, stayed open until its day. A supplier's link
-- closes this way since 2026-10-18 (`supplier_link_close`).
--
-- WHAT IT CHANGES
--   * `client_details_close(p_client)`: at Clients: Billing Work, the client
--     in scope, every open form of the client ends now (`expires_at`), so
--     Billing reads Link expired and Create link makes a new one; the link
--     sent reads its expired page. Filed `client.edited` · Details form link
--     closed (`no-link` with none open).
--
-- ORDER: this file (connector), then the pages. A page served before never
-- asks it; a page served after on a database without it reads "This needs a
-- database update". Safe to run twice.
--
-- ROLLBACK: the pages from before; the function is then unused and harmless.
-- ===========================================================================

-- CLIENT DETAILS LINK CLOSED -------------------------------------------------

create or replace function public.client_details_close(p_client uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  v_cl public.clients;
  n    int;
begin
  if me.id is null or not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_cl from public.clients c where c.id = p_client;
  if v_cl.id is null or not public.client_seen(v_cl.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  update public.client_detail_forms f set expires_at = now()
   where f.client_id = p_client and f.voided_at is null and f.submitted_at is null and f.expires_at > now();
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error', 'no-link'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', v_cl.name, 'Details form link closed');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_close(uuid) from public, anon;
grant execute on function public.client_details_close(uuid) to authenticated;

-- END OF CLIENT DETAILS LINK CLOSED ------------------------------------------

select public.functions_tidy();
