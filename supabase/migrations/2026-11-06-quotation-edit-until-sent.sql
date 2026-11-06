-- ===========================================================================
-- QUOTATION EDITED UNTIL SENT (2026-11-06)
-- ===========================================================================
-- WHY (the user, 2026-11-06): "If i use adjust and send it should replace
-- the -F01 instead of creating F02 since F01 is not sent out yet", and
-- "once adjust and send but need to adjust edit again there is no option
-- for that. Quotation is a serious one so it must be accurate and correct
-- not always one shot". Chosen: a quotation is edited in place until the
-- portal sends it out; Download does not lock it.
--
-- WHAT IT CHANGES
--   `quotations.sent_out_at`: when the portal first sent the quotation out,
--   stamped by trigger, never by a page: a website quotation released
--   (Send quotation or Publish, `released_at`), a team's quotation given its
--   signing link (`access_key`), a WhatsApp queued for it (`wa_outbox`,
--   `ref_kind` quotation, not failed) or an email filed for it
--   (`client_emails`, kind quotation). Existing rows are stamped from the
--   same facts.
--   `quotation_edit(p_id, p_sel)` (Clients: Quotations at Work, the client
--   in scope): prices the selection again from the live rate card exactly as
--   `quotation_make` does and writes it into the same quotation, keeping its
--   reference and link; a team's quotation takes today's date and validity.
--   Refused `sent` once sent out, `signed`, `revised` (another revises it),
--   `not-proceeding`, `removed`, plus the pricing refusals. Filed
--   `client.quotation` with its figure (monthly, else one-off) from and to.
--
-- ORDER: this file, then the pages (a page served before never calls the
-- function; its Adjust and send still makes a revision). Safe to run twice.
--
-- ROLLBACK: drop function public.quotation_edit(uuid, jsonb); drop the three
-- triggers and their functions; alter table public.quotations drop column
-- sent_out_at.
-- ===========================================================================

-- QUOTATION EDITED UNTIL SENT -----------------------------------------------

alter table public.quotations add column if not exists sent_out_at timestamptz;
-- Read by the Services pane: the table is read through column grants.
grant select (sent_out_at) on table public.quotations to authenticated;

update public.quotations q set sent_out_at = coalesce(q.released_at,
         (select min(w.created_at) from public.wa_outbox w where w.ref_kind = 'quotation' and w.ref_id = q.id and coalesce(w.state, '') <> 'failed'),
         (select min(e.created_at) from public.client_emails e where e.kind = 'quotation' and e.ref_id = q.id),
         case when q.source = 'console' and q.access_key is not null then q.issued_at end)
 where q.sent_out_at is null
   and (q.released_at is not null
        or exists (select 1 from public.wa_outbox w where w.ref_kind = 'quotation' and w.ref_id = q.id and coalesce(w.state, '') <> 'failed')
        or exists (select 1 from public.client_emails e where e.kind = 'quotation' and e.ref_id = q.id)
        or (q.source = 'console' and q.access_key is not null));

-- The quotation itself: released, or a team's quotation given its link.
create or replace function public.quotations_sent_out()
returns trigger
language plpgsql set search_path = public as $$
begin
  if new.sent_out_at is null and (new.released_at is not null or (new.source = 'console' and new.access_key is not null)) then
    new.sent_out_at := now();
  end if;
  return new;
end $$;
revoke all on function public.quotations_sent_out() from public, anon, authenticated;
create or replace trigger quotations_sent_out before insert or update of released_at, access_key on public.quotations
  for each row execute function public.quotations_sent_out();

-- A WhatsApp or an email for it.
create or replace function public.quotation_sent_by_message()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if tg_table_name = 'wa_outbox' then
    if new.ref_kind is distinct from 'quotation' or coalesce(new.state, '') = 'failed' then return null; end if;
  elsif new.kind is distinct from 'quotation' then return null;
  end if;
  v_id := new.ref_id;
  update public.quotations set sent_out_at = now() where id = v_id and sent_out_at is null;
  return null;
exception when others then
  raise warning 'quotation_sent_by_message: %', sqlerrm;
  return null;
end $$;
revoke all on function public.quotation_sent_by_message() from public, anon, authenticated;
create or replace trigger wa_outbox_quotation_sent after insert on public.wa_outbox
  for each row execute function public.quotation_sent_by_message();
create or replace trigger client_emails_quotation_sent after insert on public.client_emails
  for each row execute function public.quotation_sent_by_message();

create or replace function public.quotation_edit(p_id uuid, p_sel jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_c public.clients;
  v_card jsonb := public.quote_card();
  v_p jsonb;
  v_fx numeric;
  v_now timestamptz := now();
  v_days int;
  v_sel jsonb;
  v_was numeric;
  v_is numeric;
  v_cur text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.removed_at is not null then return jsonb_build_object('error', 'removed'); end if;
  if v_q.signed_at is not null or v_q.reviewed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = v_q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if v_q.sent_out_at is not null or v_q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  select * into v_c from public.clients where id = v_q.client_id;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- As the team builds it: their edits kept (quotation_make's console path).
  v_sel := p_sel - 'client';
  v_p := public.quote_fx_out(public.quote_adjust(public.quote_price(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id), v_fx),
           v_sel), public.quote_tax_edits(v_sel->'edits')), v_fx);
  if v_p ? 'error' then return v_p; end if;
  if jsonb_typeof(v_p->'lines') is distinct from 'array' or jsonb_array_length(v_p->'lines') = 0 then
    return jsonb_build_object('error', 'nothing-priced');
  end if;
  v_was := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  update public.quotations
     set version = v_card->>'version', version_id = (v_card->>'id')::uuid, selection = v_sel,
         lines = v_p->'lines', totals = v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request'),
         -- A team's quotation is dated when it is made ready; a website one
         -- keeps the day it was asked for (its validity runs from its send).
         issued_at = case when v_q.source = 'console' then v_now else issued_at end,
         valid_until = case when v_q.source = 'console' then (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days else valid_until end
   where id = v_q.id
  returning * into v_q;
  v_is := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_cur := case when v_fx is null then 'RM ' else 'S$ ' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_c.name,
          v_q.ref || ' edited · ' ||
          coalesce(v_cur || to_char(v_was, 'FM999,999,990.00'), 'not set') || ' → ' ||
          coalesce(v_cur || to_char(v_is, 'FM999,999,990.00'), 'not set') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref);
end $$;
revoke all on function public.quotation_edit(uuid, jsonb) from public, anon;
grant execute on function public.quotation_edit(uuid, jsonb) to authenticated;

-- END OF QUOTATION EDITED UNTIL SENT ----------------------------------------

select public.functions_tidy();
