-- ===========================================================================
-- QUOTATION WAYS OUT (2026-11-17)
-- ===========================================================================
-- WHY: the user, 2026-11-17 (digital-form-tests specs/SEAL-SPEC.md, decision
-- 8): a quotation has a way out at every step. Before signing the team
-- cancels it (Cancel, as before) and the client may decline it on its link;
-- once signed it is never deleted: it is marked withdrawn from a day, with a
-- reason, its sealed copy kept and its record and /verify/ reading
-- Withdrawn, and the service lines its approval confirmed put back where
-- the colleague asks, with Undo where it happened.
--
-- WHAT IT CHANGES
--   * `quotations` holds `declined_at` and `decline_reason` (the client's,
--     300 at most), and `withdrawn_at`, `withdrawn_on` (the day it stops),
--     `withdrawn_reason`, `withdrawn_by` and `withdrawn_lines` (each line's
--     state before, for Undo); each granted to the team as the table's other
--     columns are.
--   * `quote_decline(p_key, p_reason)` (anon): the client declines the
--     quotation its link shows while it is sent, unsigned and standing
--     (`signed`, `closed`, `unsent`, `expired`, `too-long`); it reads
--     Cancelled to the team (`not_proceeding`), the Declined step joins its
--     record, and who prepared it and the person in charge are told
--     (`quote.declined`). Filed under the Quotation website.
--   * `quotation_withdraw(p_id, p_on, p_reason, p_lines)` (Clients:
--     Quotations Full Access, the client in scope at Manage): a signed
--     quotation, not withdrawn (`not-signed`, `withdrawn`), from a day
--     between its signing and today (MYT; `bad-date`), with a reason of 3 to
--     300 (`bad-reason`); with `p_lines` its confirmed service lines go back
--     to To quote. `quotation_withdraw_undo(p_id)` puts it and the lines it
--     moved back (`not-withdrawn`). Each filed `client.quotation`.
--   * `quotation_record` adds the Withdrawn step; `verify_serial` answers
--     Withdrawn and its day; `quote_seal_state` says declined or withdrawn.
--
-- ORDER: 2026-10-07-function-hygiene.sql again (`quote_decline` joins
-- `open_to_anon`), this file (connector), then the pages. A page from
-- before offers neither act. Safe to run twice.
--
-- ROLLBACK: the pages from before; run the SIGNED DOCUMENT SEAL band's
-- `quotation_record` and `quote_seal_state` and the VERIFY SEALED FILES
-- band's `verify_serial` again. The columns may stay.
-- ===========================================================================


-- QUOTATION WAYS OUT — a quotation declined by the client, or withdrawn after signing.

alter table public.quotations add column if not exists declined_at      timestamptz;
alter table public.quotations add column if not exists decline_reason   text;
alter table public.quotations add column if not exists withdrawn_at     timestamptz;
alter table public.quotations add column if not exists withdrawn_on     date;
alter table public.quotations add column if not exists withdrawn_reason text;
alter table public.quotations add column if not exists withdrawn_by     text;
alter table public.quotations add column if not exists withdrawn_lines  jsonb;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'quotations_ways_out_check') then
    alter table public.quotations add constraint quotations_ways_out_check
      check (char_length(coalesce(decline_reason, '')) <= 300 and char_length(coalesce(withdrawn_reason, '')) <= 300);
  end if;
end $$;
grant select (declined_at, decline_reason, withdrawn_at, withdrawn_on, withdrawn_reason, withdrawn_by) on table public.quotations to authenticated;

/* The client declines on the link: the quotation the link shows, while it
   is sent and stands. */
create or replace function public.quote_decline(p_key text, p_reason text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
  c public.clients;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  if char_length(coalesce(v_reason, '')) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id) for update;
  if q.id is null or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if q.declined_at is not null then return jsonb_build_object('ok', true, 'again', true); end if;
  if q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
  if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'unsent'); end if;
  if q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  update public.quotations set status = 'not_proceeding', declined_at = now(), decline_reason = v_reason where id = q.id;
  insert into public.signing_steps (doc_kind, doc_id, step, ip, country)
  values ('quotation', q.id, 'declined', nullif(public.request_ip(), ''), nullif(public.request_country(), ''));
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation website', 'client.quotation', q.brand,
          q.ref || ' declined on the quotation link' || coalesce(' · ' || v_reason, ''));
  select * into c from public.clients where id = q.client_id;
  if public.quote_sign_member(q.made_by) is null and public.quote_sign_member(c.owner) is null then
    perform public.quote_tell(q.client_id, 'quote.declined', 'Quotation declined · ' || q.brand,
      q.ref || coalesce(' · ' || v_reason, ''), q.id::text || ':declined');
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by), public.quote_sign_member(c.owner)],
      'quote.declined', 'Quotation declined · ' || q.brand, q.ref || coalesce(' · ' || v_reason, ''),
      q.client_id, q.id::text || ':declined');
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quote_decline(text, text) from public;
grant execute on function public.quote_decline(text, text) to anon, authenticated;

/* A signed quotation withdrawn from a day: never deleted, its sealed copy
   kept; the service lines its approval confirmed go back to To quote where
   asked, each line's state kept for Undo. */
create or replace function public.quotation_withdraw(p_id uuid, p_on date, p_reason text, p_lines boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_lines jsonb := '[]'::jsonb;
  v_n integer := 0;
begin
  if me.id is null or not public.allowed('clients.quotes', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'manage') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.withdrawn_at is not null then return jsonb_build_object('error', 'withdrawn'); end if;
  if p_on is null or p_on < (q.signed_at at time zone 'Asia/Kuala_Lumpur')::date or p_on > v_today then
    return jsonb_build_object('error', 'bad-date');
  end if;
  if char_length(v_reason) < 3 or char_length(v_reason) > 300 then return jsonb_build_object('error', 'bad-reason'); end if;
  if coalesce(p_lines, false) then
    select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'state', s.state)), '[]'::jsonb), count(*)
      into v_lines, v_n
      from public.client_services s
     where s.quotation_id = q.id and s.archived_at is null and s.state = 'confirmed';
    update public.client_services set state = 'to_quote'
     where quotation_id = q.id and archived_at is null and state = 'confirmed';
  end if;
  update public.quotations
     set withdrawn_at = now(), withdrawn_on = p_on, withdrawn_reason = v_reason, withdrawn_by = me.name, withdrawn_lines = v_lines
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' withdrawn from ' || public.register_day(p_on) || ' · ' || v_reason ||
          case when v_n > 0 then ' · ' || v_n || case when v_n = 1 then ' service line' else ' service lines' end || ' back to To quote' else '' end);
  return jsonb_build_object('ok', true, 'lines', v_n);
end $$;
revoke all on function public.quotation_withdraw(uuid, date, text, boolean) from public, anon;
grant execute on function public.quotation_withdraw(uuid, date, text, boolean) to authenticated;

create or replace function public.quotation_withdraw_undo(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_l jsonb;
begin
  if me.id is null or not public.allowed('clients.quotes', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'manage') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.withdrawn_at is null then return jsonb_build_object('error', 'not-withdrawn'); end if;
  for v_l in select * from jsonb_array_elements(coalesce(q.withdrawn_lines, '[]'::jsonb)) loop
    update public.client_services set state = v_l->>'state'
     where id = (v_l->>'id')::uuid and quotation_id = q.id and archived_at is null and state = 'to_quote';
  end loop;
  update public.quotations
     set withdrawn_at = null, withdrawn_on = null, withdrawn_reason = null, withdrawn_by = null, withdrawn_lines = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand, q.ref || ' withdrawal undone');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_withdraw_undo(uuid) from public, anon;
grant execute on function public.quotation_withdraw_undo(uuid) to authenticated;

create or replace function public.quotation_record(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  s jsonb;
  v_steps jsonb := '[]'::jsonb;
begin
  if not public.is_team() or not public.allowed('clients.quotes', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  s := q.signed;
  v_steps := jsonb_build_array(jsonb_build_object('step', 'issued', 'at', q.issued_at,
    'by', case when q.source = 'website' then null else q.made_by end, 'team', q.source <> 'website',
    'note', 'Rate Card v.' || q.version));
  if q.source = 'website' and q.released_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'sent', 'at', q.released_at, 'by', q.released_by,
      'team', true, 'via', 'link'));
  end if;
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', 'sent', 'at', w.created_at, 'by', coalesce(w.created_by, 'ADspace'), 'team', true,
             'via', 'whatsapp', 'to', w.to_name,
             'state', case when w.read_at is not null then 'read' when w.delivered_at is not null then 'delivered' else w.state end))
      from public.wa_outbox w
     where w.ref_kind = 'quotation' and w.ref_id = q.id and coalesce(w.state, '') <> 'failed'), '[]'::jsonb);
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', 'sent', 'at', e.created_at,
             'by', coalesce((select m.name from public.team_members m where m.id = e.sent_by), 'ADspace'), 'team', true,
             'via', 'email', 'to', e.to_email, 'state', e.status))
      from public.client_emails e
     where e.kind = 'quotation' and e.ref_id = q.id and e.status <> 'failed'), '[]'::jsonb);
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', g.step, 'at', g.at, 'team', false, 'email', g.email,
             'in_contacts', g.in_contacts, 'ip', g.ip, 'country', g.country, 'device', g.device))
      from public.signing_steps g
     where g.doc_kind = 'quotation' and g.doc_id = q.id), '[]'::jsonb);
  if q.signed_at is not null and s is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'signed', 'at', q.signed_at, 'team', false,
      'by', s->'signer'->>'name', 'role', s->'signer'->>'designation', 'via', coalesce(s->>'via', 'online'),
      'company', s->'company'->>'legal_name',
      'email', s->'record'->>'email', 'in_contacts', (s->'record'->>'in_contacts')::boolean,
      'ip', s->'record'->>'ip', 'country', s->'record'->>'country',
      'device', coalesce(s->'record'->>'device', s->'record'->>'agent'),
      'entered_by', case when s->>'via' = 'paper' then s->'record'->>'by' end));
  end if;
  if q.submitted_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'submitted', 'at', q.submitted_at, 'team', true,
      'by', q.submitted_by, 'to', q.reviewer_name));
  end if;
  if q.returned_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'returned', 'at', q.returned_at, 'team', true,
      'by', q.returned_by, 'note', q.return_note));
  end if;
  if q.reviewed_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'confirmed', 'at', q.reviewed_at, 'team', true,
      'by', q.reviewed_by, 'role', q.reviewed_role));
  end if;
  if q.withdrawn_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'withdrawn', 'at', q.withdrawn_at, 'team', true,
      'by', q.withdrawn_by, 'note', 'From ' || public.register_day(q.withdrawn_on) || ' · ' || q.withdrawn_reason));
  end if;
  if q.sealed_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'sealed', 'at', q.sealed_at, 'team', true,
      'by', q.sealed_by, 'note', q.seal_sha));
  end if;
  return jsonb_build_object('id', q.id, 'ref', q.ref, 'brand', q.brand, 'company', s->'company'->>'legal_name',
    'signed', q.signed_at is not null, 'confirmed', q.reviewed_at is not null,
    'withdrawn', q.withdrawn_at is not null, 'declined', q.declined_at is not null,
    'seal', case when q.seal_key is null then null else jsonb_build_object('sha', q.seal_sha, 'pages_sha', q.seal_pages_sha,
                 'at', q.sealed_at, 'by', q.sealed_by) end,
    'steps', coalesce((select jsonb_agg(x order by (x->>'at')::timestamptz, x->>'step') from jsonb_array_elements(v_steps) x), '[]'::jsonb));
end $$;
revoke all on function public.quotation_record(uuid) from public, anon;
grant execute on function public.quotation_record(uuid) to authenticated;

create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  sd text;
  d public.documents%rowtype;
  l public.client_documents%rowtype;
  q public.quotations%rowtype;
  rv public.perf_reviews%rowtype;
  dl public.perf_deleted%rowtype;
  v_wait integer := public.verify_count();
begin
  if v_wait > 0 then
    return jsonb_build_object('found', false, 'locked', true, 'minutes', v_wait);
  end if;
  if length(s) < 3 or length(s) > 40 then return jsonb_build_object('found', false); end if;
  sd := replace(s, '/', '-');
  select * into d from public.documents
   where upper(serial) = s or replace(upper(serial), '/', '-') = sd
   order by (upper(serial) = s) desc, (voided_at is null) desc, created_at desc limit 1;
  if d.id is not null then
    return jsonb_build_object('found', true, 'serial', d.serial,
      'kind', case when d.family = 'hr' then 'HR Letter' else d.kind end,
      'issued_at', d.issued_at,
      'state', case when d.voided_at is null then 'valid' else 'voided' end);
  end if;
  select * into l from public.client_documents
   where upper(number) = s or replace(upper(number), '/', '-') = sd
   order by (upper(number) = s) desc limit 1;
  if l.id is not null then
    return jsonb_build_object('found', true, 'serial', l.number, 'kind', 'Letter of Offer',
      'issued_at', l.issued_at,
      'state', case when l.voided_at is not null then 'voided'
                    when l.superseded_by is not null then 'replaced'
                    else 'valid' end);
  end if;
  /* A quotation once it left ADspace (sent out, or signed): what its
     reference stands for and no more (SIGNED DOCUMENT SEAL, decision 6). */
  select * into q from public.quotations x
   where (upper(x.ref) = s or replace(upper(x.ref), '/', '-') = sd)
     and (x.sent_out_at is not null or x.signed_at is not null)
   order by (upper(x.ref) = s) desc, x.issued_at desc limit 1;
  if q.id is not null then
    return jsonb_build_object('found', true, 'serial', q.ref, 'kind', 'Quotation',
      'issued_at', q.issued_at,
      'signed_at', q.signed_at,
      'confirmed_at', q.reviewed_at,
      'document_id', case when q.seal_key is not null then q.id end,
      'sealed', q.seal_key is not null,
      'withdrawn_on', q.withdrawn_on,
      'state', case when q.withdrawn_at is not null then 'withdrawn'
                    when q.status = 'not_proceeding' or q.removed_at is not null then 'voided'
                    when exists (select 1 from public.quotations r where r.replaces = q.id and r.removed_at is null) then 'replaced'
                    when q.signed_at is null and q.valid_until is not null
                         and q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired'
                    else 'valid' end);
  end if;
  select * into rv from public.perf_reviews pr
   where (upper(pr.serial) = s or replace(upper(pr.serial), '/', '-') = sd)
     and exists (select 1 from public.perf_events pe where pe.review_id = pr.id and pe.kind = 'printed')
   limit 1;
  if rv.id is not null then
    return jsonb_build_object('found', true, 'serial', rv.serial, 'kind', 'HR Letter',
      'issued_at', rv.released_at,
      'state', case when rv.status = 'draft' then 'replaced' else 'valid' end);
  end if;
  select * into dl from public.perf_deleted pd
   where pd.printed and (upper(pd.serial) = s or replace(upper(pd.serial), '/', '-') = sd)
   order by pd.deleted_at desc limit 1;
  if dl.id is not null then
    return jsonb_build_object('found', true, 'serial', dl.serial, 'kind', 'HR Letter',
      'issued_at', dl.released_at, 'state', 'voided');
  end if;
  return jsonb_build_object('found', false);
end $$;
revoke all on function public.verify_serial(text) from public;
grant execute on function public.verify_serial(text) to anon, authenticated;

create or replace function public.quote_seal_state(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if q.id is null then return jsonb_build_object('confirmed', false); end if;
  /* Declined by the client, or withdrawn after signing (QUOTATION WAYS OUT). */
  if q.reviewed_at is null then
    return jsonb_build_object('confirmed', false, 'declined', q.declined_at is not null, 'declined_at', q.declined_at);
  end if;
  return jsonb_build_object('confirmed', true, 'id', q.id, 'confirmed_at', q.reviewed_at, 'sealed', q.seal_key is not null,
    'withdrawn', q.withdrawn_at is not null, 'withdrawn_on', q.withdrawn_on);
end $$;
revoke all on function public.quote_seal_state(text) from public;
grant execute on function public.quote_seal_state(text) to anon, authenticated;

-- END OF QUOTATION WAYS OUT ----------------------------------------------------

select public.functions_tidy();
