-- ===========================================================================
-- DETAILS FORM NAMES ITS ACCOUNT MANAGER (2026-11-25)
-- ===========================================================================
-- WHY: the details form's received page (the board ReceivedDetails, approved
-- 2026-11-25) names the client's account manager with Chat on WhatsApp.
--
-- WHAT IT CHANGES: `client_details_read` adds `rep` (name, title, whatsapp)
-- for the client's person in charge, as `quote_website_read` reads it.
--
-- ORDER: this file, then the pages. A page before it reads no `rep` and
-- draws no contact card; an old page ignores the key.
-- Safe to run twice.
-- ROLLBACK: run the earlier client_details_read in schema.sql again (the
-- same body without `m` and `rep`).
-- ===========================================================================

-- DETAILS FORM NAMES ITS ACCOUNT MANAGER -----------------------------------
-- The details form's received page names the client's account manager with
-- Chat on WhatsApp (the user approved the board, 2026-11-25): the read adds
-- the client's person in charge as /quote/ reads its representative (an
-- active colleague of that name, never a system account; the number only
-- where the colleague's namecard shows the mobile), and nothing else of
-- the record.
create or replace function public.client_details_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_f  public.client_detail_forms;
  v_cl public.clients;
  m    public.team_members;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_f from public.client_detail_forms f where f.access_key = p_key and f.voided_at is null;
  if v_f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if v_f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if v_f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  if v_cl.stage = 'past' then return jsonb_build_object('error', 'not_found'); end if;
  if nullif(btrim(coalesce(v_cl.owner, '')), '') is not null then
    select * into m from public.team_members x
     where x.active and not coalesce(x.system, false) and x.removed_at is null and x.name = v_cl.owner
     limit 1;
  end if;
  return jsonb_build_object('ok', true, 'brand', v_cl.name, 'expires_at', v_f.expires_at,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end);
end $$;
revoke all on function public.client_details_read(text) from public;
grant execute on function public.client_details_read(text) to anon, authenticated;

-- END OF DETAILS FORM NAMES ITS ACCOUNT MANAGER ----------------------------

select public.functions_tidy();
