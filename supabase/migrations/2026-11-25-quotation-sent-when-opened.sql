-- ===========================================================================
-- QUOTATION SENT WHEN IT REACHES THE CLIENT (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25. On 25 Nov at 07:48 MYT Copy link on a console
-- quotation (ADP/QT2611-C01) made its link, and `quotations_sent_out`
-- stamped it sent out because a team's quotation given its link counted as
-- sent. The client moved from Lead to Proposal sent, the move was filed
-- "Proposal sent · ADP/QT2611-C01 sent out", and the quotation's edits
-- were locked. Nothing had reached the client: copying a link is not
-- sending it.
--
-- WHAT CHANGES
--   * `quotations_sent_out`: a released quotation alone is stamped sent out
--     by the row itself. Giving a team's quotation its link no longer is;
--     the trigger now watches `released_at` alone.
--   * `quote_opened`: a team's quotation (`source` console) not yet sent out
--     is stamped the first time its own link is opened by anyone but a
--     signed-in colleague (a colleague's reading and the console's Preview
--     return before it), in the function that files the opening, so the
--     lead moves to Proposal sent then (`quotations_sent_moves_lead`).
--     Restated from QUOTATION LINK ACTIVITY with that step alone added.
--   * Unchanged: a WhatsApp queued or sent, or an email sent, for it still
--     stamps it (`quotation_sent_by_message`); a website quotation is sent
--     when released. A quotation whose link exists but was never opened
--     stays editable and unsent.
--   * Existing rows are not changed.
--
-- ORDER: the pages (no page changes its calls), then this file (connector).
-- An old tab meanwhile reads the same functions. Safe to run twice.
-- ROLLBACK: run `quotations_sent_out` and its trigger from QUOTATION EDITED
-- UNTIL SENT, and `quote_opened` from QUOTATION LINK ACTIVITY, again.
-- ===========================================================================

-- QUOTATION SENT WHEN IT REACHES THE CLIENT ----------------------------------

-- The quotation itself: a released one. A team's quotation is sent when its
-- link is first opened by the client (quote_opened) or its message goes
-- (quotation_sent_by_message).
create or replace function public.quotations_sent_out()
returns trigger
language plpgsql set search_path = public as $$
begin
  if new.sent_out_at is null and new.released_at is not null then
    new.sent_out_at := now();
  end if;
  return new;
end $$;
revoke all on function public.quotations_sent_out() from public, anon, authenticated;
create or replace trigger quotations_sent_out before insert or update of released_at on public.quotations
  for each row execute function public.quotations_sent_out();

create or replace function public.quote_opened(p_key text, p_device text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
  v_ip  text := nullif(public.request_ip(), '');
  v_dev text := public.seal_device(p_device);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  if public.is_team() then return jsonb_build_object('ok', true, 'kept', false); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if q.id is null or (q.source = 'website' and q.released_at is null) then
    return jsonb_build_object('ok', true, 'kept', false);
  end if;
  -- A team's quotation reaches the client the first time its link is
  -- opened by anyone but a colleague: it is sent out then, once.
  if q.source = 'console' and q.sent_out_at is null then
    update public.quotations set sent_out_at = now() where id = q.id and sent_out_at is null;
  end if;
  if exists (select 1 from public.signing_steps s
              where s.doc_kind = 'quotation' and s.doc_id = q.id and s.step = 'opened'
                and s.at > now() - interval '6 hours'
                and s.ip is not distinct from v_ip and s.device is not distinct from v_dev)
     or (select count(*) from public.signing_steps s
          where s.doc_kind = 'quotation' and s.doc_id = q.id and s.step = 'opened') >= 100 then
    return jsonb_build_object('ok', true, 'kept', false);
  end if;
  insert into public.signing_steps (doc_kind, doc_id, step, ip, country, device)
  values ('quotation', q.id, 'opened', v_ip, nullif(public.request_country(), ''), v_dev);
  -- The same opening, kept once, is the Activity record's line.
  perform public.quote_activity(q, 'quotation.opened', q.ref, q.contact);
  return jsonb_build_object('ok', true, 'kept', true);
end $$;
revoke all on function public.quote_opened(text, text) from public;
grant execute on function public.quote_opened(text, text) to anon, authenticated;

-- END OF QUOTATION SENT WHEN IT REACHES THE CLIENT ---------------------------

select public.functions_tidy();
