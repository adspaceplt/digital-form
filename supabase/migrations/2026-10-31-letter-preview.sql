-- ===========================================================================
-- LETTER OF OFFER PREVIEWED BEFORE IT IS ISSUED — the letter the database
-- would make, drawn and not kept (2026-10-31)
-- ===========================================================================
-- WHY (the user, 2026-10-31, approving a review of a client's Services:
-- "need to allow preview pdf or page before sending"): Issue Letter of Offer
-- took the next reference and kept the letter at once, so a mistake in its
-- terms was first seen on the issued letter, put right only by Delete and
-- issuing again.
--
-- WHAT CHANGED
--   * `issue_letter_preview(...)`, issue_letter's arguments less the key:
--     runs `issue_letter` itself inside a subtransaction, reads the letter it
--     made, then rolls every write back (the letter, its lines, the counter,
--     the Activity record row), so the snapshot is exactly the one Issue would
--     keep, its refusals the same, and no reference is spent. Answers
--     `{ok, doc}` or issue_letter's own `{error}`. The team's (authenticated);
--     issue_letter asks the caller's access as it always does.
--
-- ORDER: this file (connector), then the pages. A page served before never
-- asks it; a page served after on a database without it reads "This needs a
-- database update" on Preview alone. Safe to run twice.
--
-- ROLLBACK: nothing else calls it; it may be left in place.
-- ===========================================================================

-- LETTER OF OFFER PREVIEWED BEFORE IT IS ISSUED -----------------------------

create or replace function public.issue_letter_preview(
  p_client    uuid,
  p_services  uuid[],
  p_subtotal  numeric,
  p_tax       numeric,
  p_total     numeric,
  p_deal      jsonb   default '{}'::jsonb,
  p_replaces  uuid    default null,
  p_renewal   boolean default false,
  p_serial    text    default null
) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_out jsonb;
  v_doc jsonb;
begin
  begin
    v_out := public.issue_letter(p_client, p_services, 'preview-' || gen_random_uuid()::text,
                                 p_subtotal, p_tax, p_total, p_deal, p_replaces, p_renewal, p_serial);
    if v_out ? 'id' and not (v_out ? 'error') then
      select to_jsonb(d) into v_doc from public.client_documents d where d.id = (v_out->>'id')::uuid;
    end if;
    -- Every write above is undone with this block: nothing is kept.
    raise exception using errcode = 'P0420', message = 'letter-preview';
  exception when sqlstate 'P0420' then
    null;
  end;
  if v_out is null or v_out ? 'error' then return coalesce(v_out, jsonb_build_object('error', 'not-found')); end if;
  return jsonb_build_object('ok', true, 'doc', v_doc);
end $$;
revoke all on function public.issue_letter_preview(uuid, uuid[], numeric, numeric, numeric, jsonb, uuid, boolean, text) from public, anon;
grant execute on function public.issue_letter_preview(uuid, uuid[], numeric, numeric, numeric, jsonb, uuid, boolean, text) to authenticated;

-- END OF LETTER OF OFFER PREVIEWED BEFORE IT IS ISSUED ----------------------

select public.functions_tidy();
