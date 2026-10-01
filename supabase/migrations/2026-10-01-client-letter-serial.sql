-- ===========================================================================
-- A CLIENT LETTER IS NUMBERED ACL/{CLIENT ID}/{YYMMDD}{NN}
-- 2026-10-01. Safe to run twice. Rollback at the foot. The function below is
-- supabase/schema.sql's own copy, byte for byte (tests/sql.js compares them).
--
-- WHAT CHANGED
--   A client letter issued without a typed reference was AD/[SA/]{client
--   code}/{type code}, with -2, -3 for a second of the same type. It is now
--   ACL/{client code}/{YYMMDD}{NN} (the user): ADspace Cover Letter, the
--   client, the letter's own date (today unless the sheet gives another),
--   and the lowest number that client has free that day, from 01. An
--   advisory lock on the base keeps two issuers from taking one number.
--
-- WHAT IS NOT CHANGED
--   A letter already issued keeps its reference; /verify/ answers both. A
--   typed reference, a quotation cover and an HR letter are as they were.
--   A reissue keeps its serial.
--
-- ROLLBACK
--   Run the issue_document of 2026-09-26 again from git history
--   (supabase/schema.sql before this date).
-- ===========================================================================

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
  p_salutation text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who     text := lower(auth.jwt() ->> 'email');
  t       public.doc_types%rowtype;
  cl      public.clients%rowtype;
  mb      public.team_members%rowtype;
  me      public.team_members%rowtype;
  v_old   public.documents%rowtype;
  v_serial text;
  v_base  text;
  v_n     int;
  v_id    uuid;
  v_langs text[];
begin
  select * into t from public.doc_types where id = p_type and active;
  if t.id is null then return jsonb_build_object('error', 'no-type'); end if;
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

  -- A signed kind is signed by a person, never by a permission.
  if t.signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;

  v_serial := nullif(btrim(coalesce(p_serial, '')), '');
  if v_serial is null then
    if t.family = 'quote_cover' then return jsonb_build_object('error', 'serial-required'); end if;
    if t.family = 'client' then
      if coalesce(btrim(cl.client_code), '') = '' then return jsonb_build_object('error', 'no-client-code'); end if;
      v_base := 'ACL/' || upper(btrim(cl.client_code)) || '/' ||
                to_char(coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date), 'YYMMDD');
      -- Two issuers on one client and day wait for each other here, so the
      -- second never reads the first one's number as free.
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
                to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM');
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
    (type_id, family, kind, serial, client_id, member_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key)
  values
    (t.id, t.family, t.name, v_serial,
     case when t.family = 'hr' then null else p_client end,
     case when t.family = 'hr' then p_member else null end,
     coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), t.title),
     coalesce(nullif(btrim(p_salutation), ''), t.salutation), t.closing,
     coalesce(p_recipient, '{}'::jsonb), coalesce(p_body, '{}'::jsonb), v_langs,
     case when t.signed then p_signatory else null end, t.signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''))
  returning id into v_id;

  -- The record is told an HR letter was issued and nothing about whom: the
  -- Activity record is read by more people than HR is.
  if t.family = 'hr' then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', 'HR', t.name);
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', cl.name, v_serial || ' · ' || t.name);
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
grant execute on function public.issue_document(text, uuid, uuid, text, date, text, jsonb, jsonb, jsonb, text[], text, text) to authenticated;
