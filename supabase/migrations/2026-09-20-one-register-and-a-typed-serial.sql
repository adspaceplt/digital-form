-- ==========================================================================
-- ONE REGISTER, AND A SERIAL SOMEBODY CAN TYPE
-- 2026-09-20. Safe to run twice. Rollback at the foot.
--
-- Two changes, both asked for on 2026-09-20, and one consequence recorded.
--
-- 1. A DELETED SERIAL COMES BACK.
--    `serial_taken()` counted a row in `document_deletions` as spending the
--    reference for ever, so a document issued by mistake and then deleted
--    took its number out of circulation and the next real document skipped
--    to the following one. Testing a client's first two letters and deleting
--    both left that client starting at 03.
--
--    A deletion is now forgotten by this predicate: a reference is spent by
--    a document that STANDS — on the register, or as a Letter of Offer — and
--    by nothing else. The cost is stated rather than hidden: the deletion
--    row is still the only record that an earlier document ever carried that
--    reference, and after a reuse the two are told apart by their dates and
--    by the reason the first was deleted. That is the trade the team asked
--    for, and it only arises for a reference whose document no longer
--    exists, which nobody outside the office ever saw.
--
-- 2. A LETTER OF OFFER TAKES A TYPED REFERENCE.
--    `issue_letter` built `AQL/{client code}/{YYMM}{SEQ}` from a per-client,
--    per-month counter and the browser had no way to say otherwise, so a
--    number spent on a deleted letter could not be put back into use. It now
--    takes an optional reference: where one is typed it is checked against
--    every document that stands and refused if it is spent, and the counter
--    is NOT advanced, so typing a reference never costs the next letter its
--    place in the sequence. Where none is typed nothing changes at all.
-- ==========================================================================

-- 1. A reference is spent by a document that stands.
create or replace function public.serial_taken(p_serial text)
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.documents where upper(serial) = upper(btrim(p_serial)))
      or exists (select 1 from public.client_documents where upper(number) = upper(btrim(p_serial)))
$$;
grant execute on function public.serial_taken(text) to authenticated;

-- 2. issue_letter, with an optional reference. Everything else is unchanged.
create or replace function public.issue_letter(
  p_client    uuid,
  p_services  uuid[],
  p_idem      text,
  p_subtotal  numeric,
  p_tax       numeric,
  p_total     numeric,
  p_deal      jsonb   default '{}'::jsonb,
  p_replaces  uuid    default null,
  p_renewal   boolean default false,
  p_serial    text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  ct     public.client_contacts%rowtype;
  me     public.team_members%rowtype;
  v_ym   text;
  v_seq  int;
  v_no   text;
  v_id   uuid;
  v_lines jsonb;
  v_n    int;
  v_bad  int;
  v_old  public.client_documents%rowtype;
begin
  if not public.allowed('clients.documents') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if p_client is null or p_services is null or array_length(p_services, 1) is null then
    return jsonb_build_object('error', 'no-lines');
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;

  -- The Client ID is what the serial is built from, so there is no letter
  -- without one, unless the person has typed the reference themselves.
  v_no := nullif(btrim(coalesce(p_serial, '')), '');
  if v_no is null and coalesce(btrim(cl.client_code), '') = '' then
    return jsonb_build_object('error', 'no-client-code');
  end if;

  -- The same submission, pressed twice, is one letter. Answered before any
  -- number is reserved, so a double click cannot spend a serial either.
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.client_documents
      where client_id = p_client and idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
    end if;
  end if;

  -- A typed reference is checked before anything is written: the same shape
  -- the Register accepts, and refused where a document still holds it. A
  -- reference whose document was deleted is free again, which is the whole
  -- point of being able to type one.
  if v_no is not null then
    if v_no !~ '^[A-Za-z0-9/._-]{3,40}$' then
      return jsonb_build_object('error', 'serial-shape');
    end if;
    if public.serial_taken(v_no) then
      return jsonb_build_object('error', 'serial-taken');
    end if;
  end if;

  -- Every id must be this client's own live line, and in a state this letter
  -- may carry: To quote always, Confirmed only on a deliberate renewal.
  select count(*) into v_bad from unnest(p_services) s(id)
    left join public.client_services cs
      on cs.id = s.id and cs.client_id = p_client and cs.archived_at is null
    where cs.id is null
       or (cs.state = 'confirmed' and not p_renewal)
       or cs.state not in ('quoted', 'confirmed');
  if v_bad > 0 then return jsonb_build_object('error', 'bad-lines'); end if;

  -- A line already on a live letter is not offered again by accident. The way
  -- through is to void that letter, or to name it as the one being replaced.
  select count(*) into v_bad
    from public.client_document_services m
    join public.client_documents d on d.id = m.document_id
   where m.service_id = any(p_services)
     and d.voided_at is null
     and d.superseded_by is null
     and d.verified_at is null
     and (p_replaces is null or d.id <> p_replaces);
  if v_bad > 0 then return jsonb_build_object('error', 'already-quoted'); end if;

  if p_replaces is not null then
    select * into v_old from public.client_documents
      where id = p_replaces and client_id = p_client;
    if v_old.id is null then return jsonb_build_object('error', 'no-replaces'); end if;
    if v_old.verified_at is not null then return jsonb_build_object('error', 'replaces-verified'); end if;
  end if;

  select * into ct from public.client_contacts
    where client_id = p_client and archived_at is null
    order by (id = cl.bill_contact_id) desc, is_primary desc, name limit 1;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  -- A letter is signed by a person. issued_by is this row's name, so a team
  -- row named "Superadmin" printed that word under ADSPACE PLT on a client's
  -- letterhead. Refuse rather than draw a permission as a signatory.
  if not public.issuer_name_ok(me.name) then
    return jsonb_build_object('error', 'issuer-name', 'name', coalesce(me.name, ''));
  end if;

  -- The snapshot is built from the stored rows, never from what the browser
  -- sent: the words on a letter are the words the record held at that moment.
  select jsonb_agg(jsonb_build_object(
           'label', cs.label, 'unit', coalesce(cs.unit, ''), 'note', coalesce(cs.note, ''),
           'detail', coalesce(cs.detail, ''), 'state', cs.state,
           'qty', cs.qty, 'rate', cs.rate,
           'tenure', greatest(1, coalesce(cs.tenure, 1)),
           'start_on', coalesce(cs.start_on, ''),
           'tax', cl.sst_applies is not false,
           'service_id', cs.id)
           order by cs.created_at)
    into v_lines
    from public.client_services cs
   where cs.id = any(p_services);
  if v_lines is null then return jsonb_build_object('error', 'no-lines'); end if;

  -- A typed reference spends no sequence number: the counter is the office's
  -- record of how many letters it has issued this month, and a person filling
  -- a gap by hand has not issued one more.
  if v_no is null then
    -- The month is Malaysian, because the office that numbers the letter is.
    v_ym := to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM');

    -- Atomic: the upsert takes the row lock, so two issuers serialise here and
    -- come out with consecutive numbers. No read-then-insert, no retry.
    insert into public.client_document_seq (client_id, ym, next_val)
         values (p_client, v_ym, 2)
    on conflict (client_id, ym)
      do update set next_val = public.client_document_seq.next_val + 1
      returning next_val - 1 into v_seq;

    -- Two digits is the floor, not the ceiling: the hundredth letter of a month
    -- widens to three rather than wrapping. Not lpad(): Postgres pads AND
    -- truncates to the width it is given, so lpad('100', 2, '0') is '10' and the
    -- hundredth letter would collide with the tenth.
    v_no := 'AQL/' || cl.client_code || '/' || v_ym ||
            case when v_seq < 100 then lpad(v_seq::text, 2, '0') else v_seq::text end;
  end if;

  insert into public.client_documents
    (client_id, kind, number, issued_at, market, subtotal, tax, total,
     bill_to, lines, issued_by, client_code, idem_key)
  values
    (p_client, 'offer', v_no, (timezone('Asia/Kuala_Lumpur', now()))::date,
     coalesce(cl.market, 'MY'),
     round(coalesce(p_subtotal, 0), 2), round(coalesce(p_tax, 0), 2), round(coalesce(p_total, 0), 2),
     jsonb_build_object(
       'name', coalesce(cl.name, ''), 'legal_name', coalesce(cl.legal_name, ''),
       'address', coalesce(cl.billing_address, ''), 'regno', coalesce(cl.company_no, ''),
       'regno_old', coalesce(cl.company_no_old, ''), 'tin', coalesce(cl.tin, ''),
       'sst_no', coalesce(cl.sst_no, ''), 'sst_applies', cl.sst_applies is not false,
       'contact', coalesce(ct.name, ''), 'contact_role', coalesce(ct.role, ''),
       'phone', coalesce(ct.phone, ''), 'email', coalesce(ct.email, ''),
       'finance_email', coalesce(cl.finance_email, ''),
       'client_code', cl.client_code,
       'owner', coalesce(p_deal ->> 'owner', ''), 'source', coalesce(p_deal ->> 'source', ''),
       'industry', coalesce(p_deal ->> 'industry', ''), 'stage', coalesce(p_deal ->> 'stage', ''),
       'enquiry', coalesce(p_deal ->> 'enquiry', '')),
     v_lines, coalesce(me.name, who), cl.client_code, nullif(btrim(p_idem), ''))
  returning id into v_id;

  insert into public.client_document_services (document_id, service_id)
    select v_id, s.id from unnest(p_services) s(id)
    on conflict do nothing;

  if p_replaces is not null then
    update public.client_documents set superseded_by = v_id where id = p_replaces;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.superseded', cl.name, v_old.number || ' replaced by ' || v_no);
  end if;

  select count(*) into v_n from public.client_document_services where document_id = v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.issued', cl.name, v_no || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end);

  return jsonb_build_object('ok', true, 'id', v_id, 'number', v_no);
exception
  when unique_violation then
    -- Two presses that raced past the idempotency read: the loser reads the
    -- winner's letter back rather than making a second one.
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.client_documents
        where client_id = p_client and idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
      end if;
    end if;
    -- A typed reference that two people sent at once: the loser is told the
    -- reference is spent rather than that "two letters were issued at once",
    -- which names a cause they cannot act on.
    if nullif(btrim(coalesce(p_serial, '')), '') is not null then
      return jsonb_build_object('error', 'serial-taken');
    end if;
    return jsonb_build_object('error', 'clash');
end $$;

grant execute on function public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean, text) to authenticated;

-- The nine-argument form is gone: PostgREST resolves an RPC by the names it is
-- sent, so leaving both would give two candidates for a call that omits
-- p_serial and the request would be refused as ambiguous.
drop function if exists public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean);

-- Rollback:
--   1. Restore the deletions arm in serial_taken:
--        or exists (select 1 from public.document_deletions
--                    where upper(serial) = upper(btrim(p_serial)))
--   2. Re-create issue_letter without p_serial from supabase/schema.sql
--      section 5, and drop the ten-argument form.
