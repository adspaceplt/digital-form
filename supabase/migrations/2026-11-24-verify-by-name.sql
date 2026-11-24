-- ===========================================================================
-- VERIFY BY THE NAME ADDRESSED TO (2026-11-24)
-- ===========================================================================
-- WHY: the review of everything merged since 2026-11-09, release B2 (the
-- user, 2026-11-24: "Fix all together"). /verify/ let the day of issue stand
-- for the Document ID on a copy issued before every copy carried one
-- (`verify_code_from`, 20 Nov 2026), and the first answer gave its month;
-- a client's or supplier's reference (ACL/, ASL/ `{YYMMDD}NN`) carries the
-- day itself, so anybody holding a reference read the details. The user
-- chose the name the document is addressed to in its place.
-- `doc_code_of` answered any document's code to anon for any id, and
-- `verify_find` scanned five tables on a form no index held.
--
-- WHAT IT CHANGES
--   * `verify_find`: one form of a reference (upper case, a slash as a
--     dash), held by an index on each table it reads; each document's
--     names (`names`, never answered): a Document's recipient, client,
--     colleague and supplier; a Letter of Offer's billed company, name and
--     contact and its client; a quotation's brand, contact, billed company
--     and client; an offer or contract's candidate; a performance record's
--     colleague.
--   * `verify_serial` answers `by_name` (where the name may stand for the
--     Document ID) and the month only where it may not.
--   * `verify_details` answers a Document ID alone; a day a page from before
--     sends is read no more.
--   * `verify_details_name(p_serial, p_name)` (anon): the name compared
--     with case and spaces set aside; the ten checks an hour a connection,
--     and five wrong names a reference lock it for 24 hours
--     (`verify_name_tries`, closed to every page; `locked`, `reference`).
--   * `verify_answer`: one shape for both; `checks` (how many times it was
--     checked) to a colleague alone, never the public answer.
--   * `doc_code_of` answers a colleague, and a client's portal login for
--     its own Letter of Offer; `doc_code_of_key(p_kind, p_id, p_key)`
--     (anon) a quotation for its link's key and an offer or contract sent
--     for its candidate's.
--
-- ORDER: 2026-10-07-function-hygiene.sql again (its `open_to_anon` now
-- names `verify_details_name` and `doc_code_of_key`), then this file, then
-- the pages. An old open page meets `by_name` it does not read and offers
-- the Document ID alone; a day it sends is refused as no match; /quote/ and
-- /careers/ from before draw their PDF without its Document ID until
-- reloaded. Safe to run twice.
-- ROLLBACK: run `verify_find`, `verify_serial`, `verify_details` and
-- `doc_code_of` from VERIFY CHECKS COUNTED and VERIFY DETAILS again; the
-- indexes, the table and the new functions may stay.
-- ===========================================================================

-- VERIFY BY THE NAME ADDRESSED TO --------------------------------------------

/* One form of a reference, the one every lookup compares and every index
   holds: upper case, a slash read as a dash. */
create index if not exists documents_serial_verify_idx on public.documents (upper(replace(serial, '/', '-')));
create index if not exists client_documents_number_verify_idx on public.client_documents (upper(replace(number, '/', '-')));
create index if not exists quotations_ref_verify_idx on public.quotations (upper(replace(ref, '/', '-')));
create index if not exists hiring_docs_serial_verify_idx on public.hiring_docs (upper(replace(serial, '/', '-')));
create index if not exists perf_reviews_serial_verify_idx on public.perf_reviews (upper(replace(serial, '/', '-')));
create index if not exists perf_deleted_serial_verify_idx on public.perf_deleted (upper(replace(serial, '/', '-')));

/* A name as compared: case and spaces set aside. */
create or replace function public.verify_name_key(p text)
returns text
language sql immutable set search_path = public as $$
  select lower(regexp_replace(coalesce(p, ''), '[[:space:]]+', '', 'g'))
$$;
revoke all on function public.verify_name_key(text) from public, anon, authenticated;

/* The names a document is addressed to, as compared; never answered. */
create or replace function public.verify_names(p text[])
returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(distinct y.k), '[]'::jsonb)
    from (select public.verify_name_key(x) as k from unnest(p) x) y
   where length(y.k) >= 2
$$;
revoke all on function public.verify_names(text[]) from public, anon, authenticated;

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
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_state text;
  v_rep date;
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
        (select c.name from public.clients c where c.id = d.client_id),
        (select m.name from public.team_members m where m.id = d.member_id),
        (select to_jsonb(u) ->> 'legal_name' from public.suppliers u where u.id = d.supplier_id),
        (select to_jsonb(u) ->> 'name' from public.suppliers u where u.id = d.supplier_id)]),
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
      'names', public.verify_names(array[l.bill_to ->> 'legal_name', l.bill_to ->> 'name', l.bill_to ->> 'contact',
        (select c.legal_name from public.clients c where c.id = l.client_id),
        (select c.name from public.clients c where c.id = l.client_id)]),
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
     and (x.sent_out_at is not null or x.signed_at is not null)
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
      'names', public.verify_names(array[q.brand, q.contact ->> 'name', to_jsonb(q) #>> '{bill_to,legal_name}',
        (select c.legal_name from public.clients c where c.id = q.client_id),
        (select c.name from public.clients c where c.id = q.client_id)]),
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
  return null;
end $$;
revoke all on function public.verify_find(text) from public, anon, authenticated;

/* Wrong names a reference, wherever they come from: five in a day lock
   the name for that reference for 24 hours (a name can be guessed, a
   Document ID cannot). */
create table if not exists public.verify_name_tries (
  serial       text primary key,
  n            integer not null default 0,
  since        timestamptz not null default now(),
  locked_until timestamptz
);
alter table public.verify_name_tries enable row level security;
revoke all on public.verify_name_tries from public, anon, authenticated;

/* The minutes a reference's name stays locked, 0 where it is open. */
create or replace function public.verify_name_wait(p_key text)
returns integer
language sql stable set search_path = public as $$
  select coalesce((select greatest(1, ceil(extract(epoch from (t.locked_until - now())) / 60)::integer)
                     from public.verify_name_tries t where t.serial = p_key and t.locked_until > now()), 0)
$$;
revoke all on function public.verify_name_wait(text) from public, anon, authenticated;

create or replace function public.verify_name_wrong(p_key text)
returns void
language plpgsql volatile set search_path = public as $$
begin
  insert into public.verify_name_tries as t (serial, n, since) values (p_key, 1, now())
  on conflict (serial) do update
    set n = case when t.since < now() - interval '24 hours' then 1 else t.n + 1 end,
        since = case when t.since < now() - interval '24 hours' then now() else t.since end;
  update public.verify_name_tries t set locked_until = now() + interval '24 hours'
   where t.serial = p_key and t.n >= 5 and (t.locked_until is null or t.locked_until <= now());
end $$;
revoke all on function public.verify_name_wrong(text) from public, anon, authenticated;

/* The details, one shape for a Document ID and a name: never a name, a
   term or a figure; the check count to a colleague alone. */
create or replace function public.verify_answer(f jsonb, p_contact text)
returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('ok', true, 'serial', f ->> 'serial', 'kind', f ->> 'kind', 'state', f ->> 'state',
    'issued_on', f ->> 'issued',
    'document_id', case when f ->> 'code' is not null then substr(f ->> 'code', 1, 4) || '-' || substr(f ->> 'code', 5, 4) end,
    'sealed', coalesce((f ->> 'sealed')::boolean, false),
    'history', f -> 'steps', 'contact', p_contact) ||
    -- how many times it was checked: a colleague's to read, never the
    -- public answer's (the user, 2026-11-24)
    case when public.is_team() then jsonb_build_object('checks', greatest(1, public.verify_check_count(f ->> 'src', (f ->> 'id')::uuid)))
         else '{}'::jsonb end
$$;
revoke all on function public.verify_answer(jsonb, text) from public, anon, authenticated;

/* The first answer: that ADSPACE PLT issued a document with this reference,
   its kind and its standing; its month only where its name cannot stand
   for the Document ID (a reference may carry its day). A lookup that finds
   one is counted. */
create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  f jsonb;
  v_wait integer := public.verify_count();
  v_name boolean;
begin
  if v_wait > 0 then
    return jsonb_build_object('found', false, 'locked', true, 'minutes', v_wait);
  end if;
  f := public.verify_find(p_serial);
  if f is null then return jsonb_build_object('found', false); end if;
  perform public.verify_check_note(f);
  v_name := public.verify_by_day(f);
  return jsonb_build_object('found', true, 'serial', f ->> 'serial', 'kind', f ->> 'kind', 'state', f ->> 'state',
    'sealed', coalesce((f ->> 'sealed')::boolean, false), 'more', true, 'by_name', v_name) ||
    case when v_name then '{}'::jsonb else jsonb_build_object('issued_month', to_char((f ->> 'issued')::date, 'YYYY-MM')) end;
end $$;
revoke all on function public.verify_serial(text) from public;
grant execute on function public.verify_serial(text) to anon, authenticated;

/* The details for the Document ID printed on the copy (a sealed one's
   earlier ID too). `p_day`, which a page from before sends, is read no
   more: the name the document is addressed to stands for a missing ID
   (`verify_details_name`). One answer for a wrong code and an unknown
   reference. */
create or replace function public.verify_details(p_serial text, p_code text, p_day date)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f jsonb;
  c text := upper(regexp_replace(left(coalesce(p_code, ''), 80), '[^0-9A-Za-z]', '', 'g'));
  v_contact text := (select b.address from public.mail_boxes b where b.key = 'legal');
  v_wait integer := public.verify_detail_count();
  v_ok boolean := false;
begin
  if v_wait > 0 then
    return jsonb_build_object('locked', true, 'minutes', v_wait, 'contact', v_contact);
  end if;
  f := public.verify_find(p_serial);
  if f is not null and c <> '' then
    if f ->> 'code' is not null and c = f ->> 'code' then
      v_ok := true;
    elsif c ~ '^[0-9A-F]{32}$' and (f ->> 'sealed')::boolean and f ->> 'src' in ('quotation', 'hiring')
          and c = upper(replace(f ->> 'id', '-', '')) then
      v_ok := true;
    end if;
  end if;
  if not v_ok then return jsonb_build_object('no_match', true, 'contact', v_contact); end if;
  return public.verify_answer(f, v_contact);
end $$;
revoke all on function public.verify_details(text, text, date) from public;
grant execute on function public.verify_details(text, text, date) to anon, authenticated;

/* The details for a document issued before every copy carried its
   Document ID: the name it is addressed to (the registered company name
   or the person's), case and spaces set aside. Ten checks an hour a
   connection, as a Document ID's, and five wrong names a reference lock
   it for 24 hours. One answer for a wrong name and an unknown reference. */
create or replace function public.verify_details_name(p_serial text, p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f jsonb;
  k text := public.verify_name_key(left(coalesce(p_name, ''), 200));
  v_contact text := (select b.address from public.mail_boxes b where b.key = 'legal');
  v_wait integer := public.verify_detail_count();
  v_team boolean := public.is_team();
  v_key text;
  v_lock integer;
begin
  if v_wait > 0 then
    return jsonb_build_object('locked', true, 'minutes', v_wait, 'contact', v_contact);
  end if;
  f := public.verify_find(p_serial);
  if f is null or not public.verify_by_day(f) or length(k) < 2 then
    return jsonb_build_object('no_match', true, 'contact', v_contact);
  end if;
  v_key := upper(replace(f ->> 'serial', '/', '-'));
  v_lock := case when v_team then 0 else public.verify_name_wait(v_key) end;
  if v_lock > 0 then
    return jsonb_build_object('locked', true, 'reference', true, 'minutes', v_lock, 'contact', v_contact);
  end if;
  if not coalesce((f -> 'names') ? k, false) then
    if not v_team then perform public.verify_name_wrong(v_key); end if;
    return jsonb_build_object('no_match', true, 'contact', v_contact);
  end if;
  return public.verify_answer(f, v_contact);
end $$;
revoke all on function public.verify_details_name(text, text) from public;
grant execute on function public.verify_details_name(text, text) to anon, authenticated;

/* The code of a document, as printed: any for a colleague, a client's own
   Letter of Offer for its portal login, else none. A page outside the
   team asks `doc_code_of_key` with its own key. */
create or replace function public.doc_code_of(p_kind text, p_id uuid)
returns text
language plpgsql stable security definer set search_path = public as $$
declare v text;
begin
  if p_id is null then return null; end if;
  if public.is_team() then
    v := case p_kind
      when 'document'  then (select x.doc_code from public.documents x where x.id = p_id)
      when 'letter'    then (select x.doc_code from public.client_documents x where x.id = p_id)
      when 'quotation' then (select x.doc_code from public.quotations x where x.id = p_id)
      when 'hiring'    then (select x.doc_code from public.hiring_docs x where x.id = p_id)
      when 'perf'      then (select x.doc_code from public.perf_reviews x where x.id = p_id)
    end;
  elsif p_kind = 'letter' then
    v := (select x.doc_code from public.client_documents x
           where x.id = p_id and x.client_id in (select public.portal_clients()));
  end if;
  if v is null then return null; end if;
  return substr(v, 1, 4) || '-' || substr(v, 5, 4);
end $$;
revoke all on function public.doc_code_of(text, uuid) from public;
grant execute on function public.doc_code_of(text, uuid) to anon, authenticated;

/* The code for the page holding the document's own key: a quotation's
   link (/quote/), a candidate's (/careers/, an offer or contract sent). */
create or replace function public.doc_code_of_key(p_kind text, p_id uuid, p_key text)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v text;
  k text := btrim(coalesce(p_key, ''));
begin
  if p_id is null then return null; end if;
  if k = '' or public.is_team() then return public.doc_code_of(p_kind, p_id); end if;
  v := case p_kind
    when 'quotation' then (select x.doc_code from public.quotations x
                            where x.id = p_id and x.access_key = k and x.removed_at is null)
    when 'hiring'    then (select x.doc_code from public.hiring_docs x join public.hiring_candidates c on c.id = x.candidate_id
                            where x.id = p_id and c.link_key = lower(k) and x.sent_at is not null and x.state <> 'draft')
  end;
  if v is null then return null; end if;
  return substr(v, 1, 4) || '-' || substr(v, 5, 4);
end $$;
revoke all on function public.doc_code_of_key(text, uuid, text) from public;
grant execute on function public.doc_code_of_key(text, uuid, text) to anon, authenticated;

-- END OF VERIFY BY THE NAME ADDRESSED TO -------------------------------------

select public.functions_tidy();
