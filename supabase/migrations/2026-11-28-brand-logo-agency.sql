-- ===========================================================================
-- BRAND LOGO AGENCY KEY (2026-11-28)
-- ===========================================================================
-- WHY: release 8 decision 4 (HANDOVER item 20), carried by the restructure's
-- release 9. A white-label brand's reports go out under the partner's logo
-- or the agency's own wordmark, and the agency's choice was stored as the
-- agency's own name: an install's data named another agency.
-- WHAT IT CHANGES
--   * `client_brands.logo`: 'partner' or 'agency'. Every stored value that
--     is not 'partner' (the old check allowed one other, the agency's name)
--     is rewritten 'agency', and the check holds the new pair.
--   * `client_brand_logo(p_id, p_logo)`: takes 'agency' in place of the old
--     key; the activity line names the agency from the profile
--     (`agency('trading_name')`). Refusals, grants and the caller's lookup
--     (`ops_me()`) are unchanged.
--   * `sm_report_snapshot` and `client_brands_list` read `partner` alone or
--     pass the value on: unchanged.
-- ORDER: this file first, then the pages (js/crm.js, js/reports.js read
-- any value but 'partner' as the agency's mark, so they read the old key
-- and the new alike, and send 'agency'). Between the two, an open tab
-- reads every brand rightly, and its White label toggle to the agency's
-- logo is refused (Not saved.) until it is reloaded; the toggle back to
-- the partner's saves. The report is drawn from the database's snapshot
-- throughout (it reads 'partner' alone). Pages deployed first would be
-- refused on that toggle until this runs.
-- ROLLBACK: drop the check; set logo back to the old key where it is
-- 'agency'; add the check back as WHITE LABEL BRAND LOGO states it; run
-- client_brand_logo from that band again. Safe to run twice.

-- BRAND LOGO AGENCY KEY ------------------------------------------------------

alter table public.client_brands drop constraint if exists client_brands_logo;
update public.client_brands set logo = 'agency' where logo <> 'partner';
alter table public.client_brands add constraint client_brands_logo check (logo in ('partner', 'agency'));

create or replace function public.client_brand_logo(p_id uuid, p_logo text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  b public.client_brands;
  v_client text;
begin
  if me.id is null or not public.ops_granted('reports.whitelabel', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_logo, '') not in ('partner', 'agency') then return jsonb_build_object('error', 'bad-logo'); end if;
  select * into b from public.client_brands where id = p_id for update;
  if b.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(b.client_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if b.logo = p_logo then return jsonb_build_object('ok', true); end if;
  select c.name into v_client from public.clients c where c.id = b.client_id;
  update public.client_brands set logo = p_logo, updated_at = now() where id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.brand', v_client, 'White label brand ' || b.name || ' logo: ' ||
    case b.logo when 'agency' then public.agency('trading_name') else v_client end || ' → ' ||
    case p_logo when 'agency' then public.agency('trading_name') else v_client end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_brand_logo(uuid, text) from public, anon;
grant execute on function public.client_brand_logo(uuid, text) to authenticated;

-- END OF BRAND LOGO AGENCY KEY -----------------------------------------------

select public.functions_tidy();
