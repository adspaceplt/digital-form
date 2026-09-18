-- 2026-09-22  Voiding a letter is Clients: Manage, not a switch of its own.
--
-- `can_doc_void` was a separate capability beside the seven section levels:
-- voiding a verified letter reverses a commercial confirmation and was kept
-- apart from deleting one. In practice the person trusted to delete a
-- client's letter is the person trusted to void it, and two switches for one
-- level of trust left groups with Manage on Clients and no void, which reads
-- as a mistake. Decided with the user on 2026-09-22.
--
-- Two functions, redefined. No table, column, policy or trigger changes: the
-- `can_doc_void` columns stay in place, unread, so nothing has to be dropped
-- and the file is safe to run twice.
--
--   allowed(text)          `doc_void` leaves the case list; the one-argument
--                          form answers `billing` and `admin` only, and a bare
--                          section name still means work.
--   letter_set_void        asks allowed('clients', 'manage') instead of
--                          allowed('doc_void'). Everything else in it is as it
--                          was: a verified letter only, a reason required, the
--                          sole-held service lines reverted, the activity row.
--
-- Who gains and who loses, on the day this runs:
--   gains  any group at Manage on Clients that did not carry the tick
--   loses  any group carrying the tick without Manage on Clients
-- Admins are unaffected either way.
--
-- PREFLIGHT (read only, run first)
--   select slug, access ->> 'clients' as clients, can_doc_void
--     from public.team_roles order by position;
--        -- note any row where can_doc_void is true and clients is not 'manage'
--
-- POST-MIGRATION VERIFICATION
--   select pg_get_functiondef('public.letter_set_void(uuid, text)'::regprocedure)
--     like '%allowed(''clients'', ''manage'')%';                    -- true
--   select pg_get_functiondef('public.allowed(text)'::regprocedure)
--     like '%doc_void%';                                            -- false
--
-- ROLLBACK
--   Re-run this repository's `supabase/schema.sql` at the commit before this
--   migration; the columns were never dropped, so the earlier definitions read
--   them again as they stand.

create or replace function public.allowed(flag text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  if flag in ('billing', 'admin') then
    select * into t from public.team_members
      where lower(email) = lower(auth.jwt() ->> 'email') and active limit 1;
    if t.id is null then return false; end if;
    if t.is_admin or t.role = 'admin' then return true; end if;
    return coalesce(case flag
      when 'billing'  then t.can_billing
      else false
    end, false);
  end if;
  return public.allowed(flag, 'work');
end $$;
grant execute on function public.allowed(text) to authenticated;

create or replace function public.letter_set_void(p_doc uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.client_documents%rowtype;
  cl  public.clients%rowtype;
  ids uuid[];
begin
  -- Voiding is the Clients section's Manage level, the same authority that
  -- deletes a letter: one level of trust, one switch.
  if not public.allowed('clients', 'manage') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('ok', true, 'repeat', true); end if;
  if d.verified_at is null then return jsonb_build_object('error', 'not-verified'); end if;

  ids := public.letter_sole_services(p_doc);

  update public.client_documents
     set voided_at = now(), voided_by = who, void_reason = btrim(p_reason)
   where id = p_doc;
  update public.client_services set state = 'quoted' where id = any(ids);

  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.voided', cl.name,
          d.number || ' · ' || btrim(p_reason) || ' · ' ||
          coalesce(array_length(ids, 1), 0) || ' service lines reverted');
  return jsonb_build_object('ok', true, 'reverted', coalesce(array_length(ids, 1), 0));
end $$;
grant execute on function public.letter_set_void(uuid, text) to authenticated;
