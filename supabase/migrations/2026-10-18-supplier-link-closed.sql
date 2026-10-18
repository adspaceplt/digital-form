-- ===========================================================================
-- A SUPPLIER'S LINK IS CLOSED — the details form's link stops opening at a
-- press, with no new one made (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18: "how to delete the link?"): Reset link made a
-- new link in place of the old; a supplier approved by hand still held a
-- link open for two weeks.
--
-- WHAT IT CHANGES
--   * `supplier_link_close(p_id)`: at Suppliers Work, every open form of the
--     supplier ends now (`expires_at`), so it reads Link expired and Create
--     link makes a new one; filed `supplier.edited` · Details form link
--     closed (`no-link` with none open).
--
-- ORDER: this file, then the pages. Safe to run twice.
-- Rollback: drop the function; the pages from before.
-- ===========================================================================

create or replace function public.supplier_link_close(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  s   public.suppliers;
  n   int;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.supplier_forms x set expires_at = now()
   where x.supplier_id = p_id and x.voided_at is null and x.submitted_at is null and x.expires_at > now();
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error', 'no-link'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'supplier.edited', coalesce(s.name, s.code), s.code || ' · Details form link closed');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_link_close(uuid) from public, anon;
grant execute on function public.supplier_link_close(uuid) to authenticated;

-- END OF A SUPPLIER'S LINK IS CLOSED ----------------------------------------
select public.functions_tidy();
