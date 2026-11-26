-- ===========================================================================
-- QUOTATIONS ISSUED WHEN CREATED (2026-11-26)
-- ===========================================================================
-- WHY: /verify/ found nothing for ADP/QT2611-C02, a quotation with its
-- Document ID printed on its foot, and the Register left out four of nine
-- quotations (F3 and F5 of the handover of 2026-11-26): both read a
-- quotation only once sent out or signed. The user, 2026-11-26: "issued
-- means created, only when issued to client means someone viewed the
-- link". A quotation is issued the moment it is created; Sent
-- (`sent_out_at`) stays what it is.
--
-- WHAT IT CHANGES
--   * `quotation_issued(q)`: the one test of an issued quotation, true for
--     every quotation today; `verify_find` and its Document ID lookup ask
--     it (a row function the table's column grants refuse to a page, so the
--     Register, which lists every quotation, takes a column when the test
--     narrows).
--   * `verify_find`: every quotation is found by its reference, whether or
--     not it went out (a removed one Void, as before), and by its Document
--     ID (`doc_code`), answered as a report's is: the code as the serial,
--     `by_code`. Every other document and state stands.
--   * `quotation_delete`: a removed quotation that was sent out or signed
--     is refused `sent`; it stays on the Register and /verify/ as Void.
--     Every other refusal stands.
--
-- ORDER: this file, then the page (an old tab offers Delete on a sent
-- removed quotation and reads the refusal as its raw word). Safe to run
-- twice. `quotation_delete` holds a delete: an SQL Editor run of its own
-- where the connector holds it.
-- ROLLBACK: run DOCUMENT ID ON EVERY FOOT's `verify_find` (2026-11-24)
-- and QUOTATIONS DELETED AND REQUESTS RECORDED BY THE TEAM's
-- `quotation_delete` again.
-- ===========================================================================

-- QUOTATIONS ISSUED WHEN CREATED --------------------------------------------

/* Whether a quotation counts as issued: the one test verify_find and its
   Document ID lookup ask, so a later change (a quotation issued once
   confirmed) is made here. Today every quotation is issued as it is
   created. */
create or replace function public.quotation_issued(q public.quotations)
returns boolean language sql stable set search_path = public as $$
  select q.id is not null
$$;
revoke all on function public.quotation_issued(public.quotations) from public, anon;
grant execute on function public.quotation_issued(public.quotations) to authenticated;

/* Every quotation is issued as it is created: found by its reference
   and by its Document ID, whether or not it went out; a removed one
   reads Void. */
create or replace function public.verify_find(p_serial text)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  sd text;
  d public.documents%rowtype;
  l public.client_documents%rowtype;
  q public.quotations%rowtype;
  h public.hiring_docs%rowtype;
  rv public.perf_reviews%rowtype;
  dl public.perf_deleted%rowtype;
  rp public.sm_report_versions%rowtype;
  vs public.video_scripts%rowtype;
  v_code text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_state text;
  v_rep date;
  v_ref text;
begin
  if length(s) < 3 or length(s) > 40 then return null; end if;
  sd := replace(s, '/', '-');
  select * into d from public.documents x
   where upper(replace(x.serial, '/', '-')) = sd
   order by (upper(x.serial) = s) desc, (x.voided_at is null) desc, x.created_at desc limit 1;
  if d.id is not null then
    return jsonb_build_object('src', 'document', 'id', d.id, 'serial', d.serial,
      'kind', case when d.family = 'hr' then 'HR Letter' else d.kind end,
      'issued', d.issued_at, 'code', d.doc_code, 'sealed', false,
      'names', public.verify_names(array[d.recipient ->> 'name',
        (select c.legal_name from public.clients c where c.id = d.client_id),
        (select m.name from public.team_members m where m.id = d.member_id),
        (select coalesce(nullif(to_jsonb(u) ->> 'legal_name', ''), to_jsonb(u) ->> 'name') from public.suppliers u where u.id = d.supplier_id)]),
      'state', case when d.voided_at is null then 'valid' else 'voided' end,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', d.issued_at),
        jsonb_build_object('step', 'voided', 'day', (d.voided_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  select * into l from public.client_documents x
   where upper(replace(x.number, '/', '-')) = sd
   order by (upper(x.number) = s) desc limit 1;
  if l.id is not null then
    select x.issued_at into v_rep
      from public.client_documents x where x.id = l.superseded_by;
    return jsonb_build_object('src', 'letter', 'id', l.id, 'serial', l.number, 'kind', 'Letter of Offer',
      'issued', l.issued_at, 'code', l.doc_code, 'sealed', false,
      'names', public.verify_names(array[coalesce(nullif(l.bill_to ->> 'legal_name', ''), l.bill_to ->> 'name'), l.bill_to ->> 'contact',
        (select c.legal_name from public.clients c where c.id = l.client_id)]),
      'state', case when l.voided_at is not null then 'voided'
                    when l.superseded_by is not null then 'replaced'
                    else 'valid' end,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', l.issued_at),
        jsonb_build_object('step', 'signed', 'day', (l.signed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'confirmed', 'day', (l.verified_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'replaced', 'day', v_rep),
        jsonb_build_object('step', 'voided', 'day', (l.voided_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  select * into q from public.quotations x
   where (upper(replace(x.ref, '/', '-')) = sd)
     and public.quotation_issued(x)
   order by (upper(x.ref) = s) desc, x.issued_at desc limit 1;
  if q.id is not null then
    select (min(r.issued_at) at time zone 'Asia/Kuala_Lumpur')::date into v_rep
      from public.quotations r where r.replaces = q.id and r.removed_at is null;
    v_state := case when q.withdrawn_at is not null then 'withdrawn'
                    when q.status = 'not_proceeding' or q.removed_at is not null then 'voided'
                    when v_rep is not null then 'replaced'
                    when q.signed_at is null and q.valid_until is not null and q.valid_until < v_today then 'expired'
                    else 'valid' end;
    return jsonb_build_object('src', 'quotation', 'id', q.id, 'serial', q.ref, 'kind', 'Quotation',
      'issued', (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', q.doc_code, 'sealed', q.seal_key is not null,
      'names', public.verify_names(array[q.contact ->> 'name', to_jsonb(q) #>> '{bill_to,legal_name}',
        (select c.legal_name from public.clients c where c.id = q.client_id)]),
      'state', v_state,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'sent', 'day', (q.sent_out_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'signed', 'day', (q.signed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'confirmed', 'day', (q.reviewed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'sealed', 'day', (q.sealed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'declined', 'day', (q.declined_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'withdrawn', 'day', q.withdrawn_on),
        jsonb_build_object('step', 'voided', 'day', (q.removed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'replaced', 'day', v_rep),
        jsonb_build_object('step', 'expired', 'day', case when v_state = 'expired' then q.valid_until + 1 end))));
  end if;
  /* An offer or a contract once sent: the version standing first (a
     replacement keeps the reference, the one it replaced void). */
  select * into h from public.hiring_docs x
   where (upper(replace(x.serial, '/', '-')) = sd)
     and x.sent_at is not null and x.state <> 'draft'
   order by (upper(x.serial) = s) desc, (x.state <> 'void') desc, x.sent_at desc limit 1;
  if h.id is not null then
    v_state := case when h.state = 'void' then 'voided'
                    when h.state = 'withdrawn' then 'withdrawn'
                    when h.state = 'declined' then 'declined'
                    when h.state = 'sent' and h.reply_by is not null and h.reply_by < now() then 'expired'
                    else 'valid' end;
    return jsonb_build_object('src', 'hiring', 'id', h.id, 'serial', h.serial, 'kind', 'HR Letter',
      'issued', (h.sent_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', h.doc_code, 'sealed', h.seal_sha is not null,
      'names', public.verify_names(array[(select k.name from public.hiring_candidates k where k.id = h.candidate_id)]),
      'state', v_state,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (h.sent_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'signed', 'day', (h.signed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'confirmed', 'day', (h.confirmed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'sealed', 'day', (h.sealed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'declined', 'day', case when h.state = 'declined' then (coalesce(h.answered_at, h.updated_at) at time zone 'Asia/Kuala_Lumpur')::date end),
        jsonb_build_object('step', 'withdrawn', 'day', case when h.state = 'withdrawn' then (h.updated_at at time zone 'Asia/Kuala_Lumpur')::date end),
        jsonb_build_object('step', 'voided', 'day', (h.voided_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'expired', 'day', case when v_state = 'expired' then (h.reply_by at time zone 'Asia/Kuala_Lumpur')::date end))));
  end if;
  select * into rv from public.perf_reviews pr
   where (upper(replace(pr.serial, '/', '-')) = sd)
     and exists (select 1 from public.perf_events pe where pe.review_id = pr.id and pe.kind = 'printed')
   limit 1;
  if rv.id is not null then
    return jsonb_build_object('src', 'perf', 'id', rv.id, 'serial', rv.serial, 'kind', 'HR Letter',
      'issued', (rv.released_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', rv.doc_code, 'sealed', false,
      'names', public.verify_names(array[(select m.name from public.team_members m where m.id = rv.team_member_id)]),
      'state', case when rv.status = 'draft' then 'replaced' else 'valid' end,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (rv.released_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'acknowledged', 'day', (rv.acknowledged_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'finalised', 'day', (rv.finalised_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  select * into dl from public.perf_deleted pd
   where pd.printed and (upper(replace(pd.serial, '/', '-')) = sd)
   order by pd.deleted_at desc limit 1;
  if dl.id is not null then
    return jsonb_build_object('src', 'perf_deleted', 'id', dl.id, 'serial', dl.serial, 'kind', 'HR Letter',
      'issued', (dl.released_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', null, 'sealed', false, 'state', 'voided',
      'names', public.verify_names(array[(select m.name from public.team_members m where m.id = dl.team_member_id)]),
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (dl.released_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'voided', 'day', (dl.deleted_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  /* A report as published and a video script as shared hold no reference
     of their own: the Document ID their foot prints is what /verify/ is
     asked (DOCUMENT ID ON EVERY FOOT, 2026-11-24). */
  v_code := regexp_replace(s, '[^0-9A-Z]', '', 'g');
  if v_code ~ '^[2-9A-Z]{8}$' then
    select * into rp from public.sm_report_versions x where x.doc_code = v_code limit 1;
    if rp.id is not null then
      select (min(n.published_at) at time zone 'Asia/Kuala_Lumpur')::date into v_rep
        from public.sm_report_versions n where n.report_id = rp.report_id and n.version_no > rp.version_no;
      return jsonb_build_object('src', 'report', 'id', rp.id, 'serial', substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4), 'by_code', true,
        'kind', case when coalesce(rp.snapshot #>> '{report,kind}', (select r.kind from public.sm_reports r where r.id = rp.report_id)) = 'ads'
                     then 'Social Media Advertising Report' else 'Social Media Accounts Report' end,
        'issued', (rp.published_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', rp.doc_code, 'sealed', false,
        'state', case when rp.withdrawn_at is not null then 'withdrawn' when v_rep is not null then 'replaced' else 'valid' end,
        'steps', public.verify_steps(jsonb_build_array(
          jsonb_build_object('step', 'issued', 'day', (rp.published_at at time zone 'Asia/Kuala_Lumpur')::date),
          jsonb_build_object('step', 'replaced', 'day', v_rep),
          jsonb_build_object('step', 'withdrawn', 'day', (rp.withdrawn_at at time zone 'Asia/Kuala_Lumpur')::date))));
    end if;
    /* A quotation by the Document ID its foot prints (QUOTATIONS ISSUED
       WHEN CREATED, 2026-11-26): its reference is what is typed, the code
       found here stands for it, as a report's does. */
    select x.ref into v_ref from public.quotations x where x.doc_code = v_code and public.quotation_issued(x) limit 1;
    if v_ref is not null then
      return public.verify_find(v_ref) || jsonb_build_object('serial', substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4), 'by_code', true);
    end if;
    select * into vs from public.video_scripts x where x.doc_code = v_code and x.shared_at is not null limit 1;
    if vs.id is not null then
      return jsonb_build_object('src', 'script', 'id', vs.id, 'serial', substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4), 'by_code', true,
        'kind', 'Video Script',
        'issued', (vs.shared_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', vs.doc_code, 'sealed', false,
        'state', case when vs.status = 'shared' then 'valid' else 'withdrawn' end,
        'steps', public.verify_steps(jsonb_build_array(
          jsonb_build_object('step', 'issued', 'day', (vs.shared_at at time zone 'Asia/Kuala_Lumpur')::date),
          jsonb_build_object('step', 'withdrawn', 'day', case when vs.status <> 'shared' then (vs.updated_at at time zone 'Asia/Kuala_Lumpur')::date end))));
    end if;
  end if;
  return null;
end $$;
revoke all on function public.verify_find(text) from public, anon, authenticated;

create or replace function public.quotation_delete(p_id uuid, p_ref text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_n int;
  v_doc text;
  v_by text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'manage') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.removed_at is null then return jsonb_build_object('error', 'not-removed'); end if;
  if btrim(coalesce(p_ref, '')) <> v_q.ref then return jsonb_build_object('error', 'bad-ref'); end if;
  -- One that reached the client (its link opened, or sent) or was signed
  -- is kept, Void on the Register and /verify/, never deleted
  -- (QUOTATIONS ISSUED WHEN CREATED, 2026-11-26).
  if v_q.sent_out_at is not null or v_q.signed_at is not null then return jsonb_build_object('error', 'sent'); end if;
  select count(*) into v_n from public.client_services s where s.quotation_id = v_q.id;
  if v_n > 0 then return jsonb_build_object('error', 'lines', 'count', v_n); end if;
  select d.number into v_doc from public.client_documents d
   where d.lines @> jsonb_build_array(jsonb_build_object('quotation_id', v_q.id::text))
   order by d.created_at limit 1;
  if v_doc is not null then return jsonb_build_object('error', 'letter', 'number', v_doc); end if;
  select x.ref into v_by from public.quotations x where x.replaces = v_q.id order by x.issued_at limit 1;
  if v_by is not null then return jsonb_build_object('error', 'revised', 'ref', v_by); end if;
  insert into public.quotation_refs_kept (ref, deleted_by) values (v_q.ref, me.name)
  on conflict (ref) do nothing;
  delete from public.quotations where id = v_q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || ' deleted');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_delete(uuid, text) from public, anon;
grant execute on function public.quotation_delete(uuid, text) to authenticated;

-- END OF QUOTATIONS ISSUED WHEN CREATED -------------------------------------
