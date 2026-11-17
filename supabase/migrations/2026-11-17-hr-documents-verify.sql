-- ===========================================================================
-- HR DOCUMENTS VERIFIED (2026-11-17)
-- ===========================================================================
-- WHY: HR-SPEC decisions 4 and 15 (tests/hr-templates/HR-SPEC.md): /verify/
-- checks an Employment Offer's and an Employment Contract's reference and
-- its sealed file, and the confirmed documents are listed in Documents
-- under HR Letters and on the colleague's Documents tab.
--
-- WHAT IT CHANGES
--   * `verify_serial` answers ADHR/OFR… and ADHR/EMP… once sent: HR Letter,
--     Valid, Void, Withdrawn, Declined or Expired, the days sent, signed and
--     confirmed, and the Document ID once sealed; never the candidate, a
--     term or a figure. Every other answer is unchanged.
--   * `verify_file` checks a file against a sealed offer or contract too.
--   * `hiring_register()` (HR Letters at View): the confirmed offers and
--     contracts, their reference, kind, person, colleague and days.
--   * `hiring_file_ok` lets HR Letters at View read a confirmed document's
--     sealed file, and nothing else in the bucket.
--
-- ORDER: this file (connector), then the pages. A page from before lists
-- none and reads a Declined answer as its state word. Safe to run twice.
--
-- ROLLBACK: run verify_serial from QUOTATION WAYS OUT, verify_file from
-- VERIFY SEALED FILES and hiring_file_ok from HIRING again; the pages from
-- before. `hiring_register` may stay.
-- ===========================================================================

-- HR DOCUMENTS VERIFIED ------------------------------------------------------

/* /verify/ answers an Employment Offer's and an Employment Contract's
   reference (ADHR/OFR…, ADHR/EMP…) as it answers every HR letter: HR
   Letter, its state and its days, and the Document ID once sealed; never
   the candidate, a term or a figure (HR-SPEC decision 15). Every other
   answer is as QUOTATION WAYS OUT left it. */
create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  sd text;
  d public.documents%rowtype;
  l public.client_documents%rowtype;
  q public.quotations%rowtype;
  h public.hiring_docs%rowtype;
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
  /* An offer or a contract once sent: the version standing first (a
     replacement keeps the reference, the one it replaced void). */
  select * into h from public.hiring_docs x
   where (upper(x.serial) = s or replace(upper(x.serial), '/', '-') = sd)
     and x.sent_at is not null and x.state <> 'draft'
   order by (upper(x.serial) = s) desc, (x.state <> 'void') desc, x.sent_at desc limit 1;
  if h.id is not null then
    return jsonb_build_object('found', true, 'serial', h.serial, 'kind', 'HR Letter',
      'issued_at', h.sent_at,
      'signed_at', h.signed_at,
      'confirmed_at', h.confirmed_at,
      'document_id', case when h.seal_sha is not null then h.id end,
      'sealed', h.seal_sha is not null,
      'state', case when h.state = 'void' then 'voided'
                    when h.state = 'withdrawn' then 'withdrawn'
                    when h.state = 'declined' then 'declined'
                    when h.state = 'sent' and h.reply_by is not null and h.reply_by < now() then 'expired'
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

/* A file checked against a sealed quotation, offer or contract. */
create or replace function public.verify_file(p_serial text, p_sha text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  h text := lower(btrim(coalesce(p_sha, '')));
  v_sha text;
  v_wait integer := public.verify_count();
begin
  if v_wait > 0 then return jsonb_build_object('locked', true, 'minutes', v_wait); end if;
  if length(s) < 3 or length(s) > 40 or h !~ '^[0-9a-f]{64}$' then return jsonb_build_object('error', 'bad-request'); end if;
  select x.seal_sha into v_sha from public.quotations x
   where (upper(x.ref) = s or replace(upper(x.ref), '/', '-') = replace(s, '/', '-'))
     and x.seal_key is not null
   order by (upper(x.ref) = s) desc, x.issued_at desc limit 1;
  if v_sha is null then
    select x.seal_sha into v_sha from public.hiring_docs x
     where (upper(x.serial) = s or replace(upper(x.serial), '/', '-') = replace(s, '/', '-'))
       and x.seal_sha is not null
     order by (upper(x.serial) = s) desc, (x.state <> 'void') desc, x.sealed_at desc limit 1;
  end if;
  if v_sha is null then return jsonb_build_object('none', true); end if;
  return jsonb_build_object('match', v_sha = h);
end $$;
revoke all on function public.verify_file(text, text) from public;
grant execute on function public.verify_file(text, text) to anon, authenticated;

/* Documents lists every offer and contract ADspace confirmed under HR
   Letters (HR-SPEC decision 4): the reference, the kind, the person and the
   day, never a term or a figure. HR Letters at View. */
create or replace function public.hiring_register()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.register_may('hr', 'view') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id, 'serial', x.serial, 'kind', x.kind, 'name', c.name, 'member_id', c.member_id,
      'sent_at', x.sent_at, 'confirmed_at', x.confirmed_at, 'sealed', x.seal_path is not null,
      'seal_path', x.seal_path, 'voided_at', x.voided_at) order by x.confirmed_at desc)
    from public.hiring_docs x join public.hiring_candidates c on c.id = x.candidate_id
    where x.confirmed_at is not null and x.serial is not null), '[]'::jsonb));
end $$;
revoke all on function public.hiring_register() from public, anon;
grant execute on function public.hiring_register() to authenticated;

/* The sealed copy is read by HR Letters at View too, the sealed file of a
   confirmed document alone; every other file keeps the candidate's people. */
create or replace function public.hiring_file_ok(p_name text, p_write boolean)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid;
  v_role text;
begin
  begin
    v_id := split_part(coalesce(p_name, ''), '/', 1)::uuid;
  exception when others then return false;
  end;
  v_role := public.hiring_role(v_id);
  if v_role is null then
    return not coalesce(p_write, false) and public.register_may('hr', 'view')
       and exists (select 1 from public.hiring_docs x
                    where x.candidate_id = v_id and x.seal_path = p_name and x.confirmed_at is not null);
  end if;
  return not coalesce(p_write, false) or v_role in ('admin', 'owner');
end $$;
revoke all on function public.hiring_file_ok(text, boolean) from public, anon;
grant execute on function public.hiring_file_ok(text, boolean) to authenticated;

-- END OF HR DOCUMENTS VERIFIED -----------------------------------------------

select public.functions_tidy();
