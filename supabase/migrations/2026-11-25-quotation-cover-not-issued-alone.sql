-- ===========================================================================
-- QUOTATION COVER NOT ISSUED ALONE (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25. Every quotation's PDF already opens with its
-- Quotation Cover (`js/quotepdf.js`, page 1, its words from the
-- `quote_cover` document type), so a Quotation Cover issued on its own from
-- Documents or a client's record repeats it.
--
-- WHAT CHANGES
--   * `issue_document`: a type of the `quote_cover` family is refused
--     (`not-issuable`), so an open tab served before cannot issue one.
--   * `document_reissue`: a Quotation Cover already issued is refused the
--     same way; it stays read only (Download, Verify, Void as before).
--   Each is restated from its last section with that line alone added.
--   * Unchanged: the `quote_cover` document type stays built in and
--     undeletable, and its words still write every quotation's cover.
--     Covers already issued stay in the register and on /verify/.
--
-- ORDER: the pages first (they stop offering it), then this file
-- (connector). Safe to run twice.
-- ROLLBACK: run `issue_document` from SAVED WHOLE AND TOLD and
-- `document_reissue` from DOCUMENTS ON THEIR OWN DATE again.
-- ===========================================================================

-- QUOTATION COVER NOT ISSUED ALONE --------------------------------------------

create or replace function public.issue_document(
  p_type      text,
  p_client    uuid,
  p_member    uuid,
  p_serial    text,
  p_issued_at date,
  p_title     text,
  p_recipient jsonb,
  p_body      jsonb,
  p_signatory jsonb,
  p_languages text[],
  p_idem      text,
  p_salutation text default null,
  p_signed    boolean default null,
  p_supplier  uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who     text := lower(auth.jwt() ->> 'email');
  t       public.doc_types%rowtype;
  cl      public.clients%rowtype;
  mb      public.team_members%rowtype;
  sp      public.suppliers%rowtype;
  me      public.team_members%rowtype;
  v_old   public.documents%rowtype;
  v_serial text;
  v_base  text;
  v_n     int;
  v_id    uuid;
  v_langs text[];
  v_signed boolean;
begin
  select * into t from public.doc_types where id = p_type and active;
  -- A letter's own date, backdated where chosen (2026-11-12): never before
  -- 14 Aug 2023 or after today; its reference follows it.
  if p_issued_at is not null and not public.doc_day_ok(p_issued_at) then return jsonb_build_object('error', 'bad-date'); end if;
  if t.id is null then return jsonb_build_object('error', 'no-type'); end if;
  -- A Quotation Cover opens every quotation's PDF; it is never issued on
  -- its own (QUOTATION COVER NOT ISSUED ALONE, 2026-11-25).
  if t.family = 'quote_cover' then return jsonb_build_object('error', 'not-issuable'); end if;
  if not public.register_may(t.family, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;

  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
    end if;
  end if;

  if t.family in ('quote_cover', 'client') then
    if p_client is null then return jsonb_build_object('error', 'no-client'); end if;
    select * into cl from public.clients where id = p_client;
    if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;
  end if;
  if t.family = 'hr' then
    if p_member is null then return jsonb_build_object('error', 'no-member'); end if;
    select * into mb from public.team_members where id = p_member;
    if mb.id is null then return jsonb_build_object('error', 'no-member'); end if;
    if coalesce(btrim(mb.staff_code), '') = '' then return jsonb_build_object('error', 'no-staff-code'); end if;
  end if;
  if t.family = 'supplier' then
    if p_supplier is null then return jsonb_build_object('error', 'no-supplier'); end if;
    select * into sp from public.suppliers where id = p_supplier;
    if sp.id is null then return jsonb_build_object('error', 'no-supplier'); end if;
    /* The agreement carries its schedules (2026-10-18): who the supplier is,
       when it starts, the fee and at least one account. */
    if t.id = 'supplier_sca' and not public.sca_complete(p_body) then
      return jsonb_build_object('error', 'agreement-incomplete');
    end if;
  end if;

  -- Whether the letter leaves space to be signed is the sheet's tick
  -- (2026-10-01), else the type's own setting. A signed letter is signed by
  -- a person, never by a permission; an unsigned one may still name who
  -- issued it, held to the same test.
  v_signed := coalesce(p_signed, t.signed);
  if coalesce(btrim(p_signatory ->> 'name'), '') <> '' and not public.issuer_name_ok(p_signatory ->> 'name') then
    return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
  end if;
  if v_signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;

  v_serial := nullif(btrim(coalesce(p_serial, '')), '');
  if v_serial is null then
    if t.family = 'quote_cover' then return jsonb_build_object('error', 'serial-required'); end if;
    if t.family in ('client', 'supplier') then
      if t.family = 'client' then
        if coalesce(btrim(cl.client_code), '') = '' then return jsonb_build_object('error', 'no-client-code'); end if;
        v_base := 'ACL/' || upper(btrim(cl.client_code));
      elsif t.id = 'supplier_sca' then
        v_base := 'AD/SCA/' || upper(btrim(sp.code));
      else
        v_base := 'ASL/' || upper(btrim(sp.code));
      end if;
      /* A Supplier Service Agreement is numbered by its month
         (AD/SCA/{Supplier ID}/{YYMM}{NN}, 2026-10-18); every other letter by
         its day. */
      v_base := v_base || '/' || to_char(coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
                                         case when t.id = 'supplier_sca' then 'YYMM' else 'YYMMDD' end);
      -- Two issuers on one client (or supplier) and day wait for each other
      -- here, so the second never reads the first one's number as free.
      perform pg_advisory_xact_lock(hashtext('acl:' || v_base));
      v_n := 1;
      loop
        v_serial := v_base || case when v_n < 10 then '0' else '' end || v_n;
        exit when not public.serial_taken(v_serial);
        v_n := v_n + 1;
        if v_n > 999 then return jsonb_build_object('error', 'no-serial'); end if;
      end loop;
    else
      v_base := 'ADHR/' || upper(mb.staff_code) || '/' || coalesce(t.code, 'GL') ||
                to_char(coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date), 'YYMM');
      -- Two issues for one colleague, kind and month wait for each other
      -- here, as a letter's do, so the second never takes the first's number
      -- (review 2026-11-24).
      perform pg_advisory_xact_lock(hashtext('adhr:' || v_base));
      v_serial := v_base; v_n := 1;
      while public.serial_taken(v_serial) loop
        v_n := v_n + 1; v_serial := v_base || '-' || v_n;
      end loop;
    end if;
  else
    if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
    if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  end if;

  v_langs := coalesce(p_languages, '{en}');
  if array_length(v_langs, 1) is null then v_langs := '{en}'; end if;

  select * into me from public.team_members where lower(email) = who and active limit 1;

  insert into public.documents
    (type_id, family, kind, serial, client_id, member_id, supplier_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key)
  values
    (t.id, t.family, t.name, v_serial,
     case when t.family in ('hr', 'supplier') then null else p_client end,
     case when t.family = 'hr' then p_member else null end,
     case when t.family = 'supplier' then p_supplier else null end,
     coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), t.title),
     coalesce(nullif(btrim(p_salutation), ''), t.salutation), t.closing,
     coalesce(p_recipient, '{}'::jsonb), coalesce(p_body, '{}'::jsonb), v_langs,
     case when coalesce(btrim(p_signatory ->> 'name'), '') <> '' then p_signatory else null end, v_signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''))
  returning id into v_id;

  -- The record is told an HR letter was issued and nothing about whom: the
  -- Activity record is read by more people than HR is.
  if t.family = 'hr' then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', 'HR', t.name);
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', case when t.family = 'supplier' then sp.name else cl.name end, v_serial || ' · ' || t.name);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
      end if;
    end if;
    return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.issue_document(text, uuid, uuid, text, date, text, jsonb, jsonb, jsonb, text[], text, text, boolean, uuid) to authenticated;

create or replace function public.document_reissue(
  p_doc       uuid,
  p_issued_at date,
  p_title     text,
  p_recipient jsonb,
  p_body      jsonb,
  p_signatory jsonb,
  p_languages text[],
  p_salutation text,
  p_idem      text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  d      public.documents%rowtype;
  v_old  public.documents%rowtype;
  me     public.team_members%rowtype;
  cl     public.clients%rowtype;
  v_id   uuid;
  v_langs text[];
begin
  select * into d from public.documents where id = p_doc;
  if p_issued_at is not null and not public.doc_day_ok(p_issued_at) then return jsonb_build_object('error', 'bad-date'); end if;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'portal' then return jsonb_build_object('error', 'not-portal'); end if;
  if d.family = 'quote_cover' then return jsonb_build_object('error', 'not-issuable'); end if;
  if not public.register_may(d.family, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
    end if;
  end if;
  if exists (select 1 from public.documents
              where upper(serial) = upper(d.serial) and voided_at is null and id <> d.id) then
    return jsonb_build_object('error', 'not-current');
  end if;
  if d.signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;
  v_langs := coalesce(p_languages, d.languages, '{en}');
  if array_length(v_langs, 1) is null then v_langs := '{en}'; end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  if d.voided_at is null then
    update public.documents set voided_at = now(), voided_by = who, void_reason = 'Reissued' where id = d.id;
  end if;
  insert into public.documents
    (type_id, family, kind, serial, client_id, member_id, supplier_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key, replaces)
  values
    (d.type_id, d.family, d.kind, d.serial, d.client_id, d.member_id, d.supplier_id,
     coalesce(p_issued_at, d.issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), d.title),
     coalesce(nullif(btrim(p_salutation), ''), d.salutation), d.closing,
     coalesce(p_recipient, d.recipient), coalesce(p_body, d.body), v_langs,
     case when d.signed then p_signatory else null end, d.signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''), d.id)
  returning id into v_id;

  if d.client_id is not null then select * into cl from public.clients where id = d.client_id; end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.reissued',
          case when d.family = 'hr' then 'HR' else coalesce(cl.name, (select s.name from public.suppliers s where s.id = d.supplier_id), d.recipient ->> 'name', '') end,
          case when d.family = 'hr' then d.kind else d.serial || ' · ' || d.kind end);
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', d.serial);
exception
  when unique_violation then
    return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.document_reissue(uuid, date, text, jsonb, jsonb, jsonb, text[], text, text) to authenticated;

-- END OF QUOTATION COVER NOT ISSUED ALONE -------------------------------------

select public.functions_tidy();
