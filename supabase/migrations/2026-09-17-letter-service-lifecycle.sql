-- ===========================================================================
-- 2026-09-17  A letter is issued for the services somebody chose, and only a
--             verified signature confirms them
--
-- WHAT WAS WRONG
--   One column, client_services.state, was doing two unrelated jobs: the
--   commercial lifecycle of the service, and the selection set for the next
--   letter. js/documents.js picked its lines with a single predicate,
--   `state = 'quoted'`, and nothing recorded which lines a letter had already
--   captured. Because issuing correctly confirms nothing, a line stays
--   `quoted` after its letter goes out — so the NEXT letter silently included
--   it again. Reproduced: a client with one line already on AQT/INT/2603001
--   and one new enquiry was issued a second letter carrying both, at
--   RM 26,136.01 instead of RM 5,400.00.
--
--   There was also no signature and no verification. client_documents carried
--   only voided_at, and a service was confirmed by a person setting a select
--   on its row, with nothing tying that act to any letter.
--
-- WHAT THIS CHANGES
--   Additive only. No existing column changes meaning, no row is rewritten,
--   no number is reissued.
--
--   clients.client_code        the business Client ID staff enter (AC180),
--                              unique, uppercase letters and digits only.
--   client_documents           signed_at, verified_at, verified_by,
--                              superseded_by, client_code (frozen at issue),
--                              idem_key (one letter per submission).
--   client_document_services   the mapping: which service lines a letter
--                              captured. Primary key (document_id, service_id)
--                              enforces one service once per document.
--   client_document_seq        the per client, per Malaysian calendar month
--                              counter, reserved atomically. Never reused.
--
--   client_documents.lines stays exactly as it is: the immutable, human
--   readable snapshot of names, descriptions, quantities, prices, tax and
--   terms as they stood at issuance. The mapping carries identity; the
--   snapshot carries the words.
--
--   Five functions, all security definer with a fixed search_path:
--     issue_letter         validate, reserve the serial, snapshot, map
--     letter_set_signed    Signed, awaiting verification. Confirms nothing.
--     verify_letter        confirms ONLY the services mapped to that letter
--     letter_set_void      refuses to void a verified letter
--     override_service_state  the admin-only escape hatch, reason required
--
--   New serial: AQL/{CLIENT_ID}/{YYMM}{SEQ}, e.g. AQL/AC180/260901.
--   Two digits is the minimum width, not a maximum: the hundredth letter of a
--   month reads AQL/AC180/2609100.
--
-- WHAT THIS DOES NOT DO
--   No backfill. Existing letters keep their AQT/INT/YYMMXXX numbers, their
--   Download and their Void, and are NOT eligible for verification: they have
--   no mappings, and verify_letter refuses a letter whose mapping count does
--   not match its line count. Existing confirmed services stay confirmed.
--   No existing client is given a code.
--
-- HOW TO RUN IT
--   Supabase dashboard > SQL editor > paste this file > Run. Safe to run more
--   than once. Nothing else in supabase/schema.sql needs re-running; the same
--   objects are mirrored there for a fresh database.
--
--   RUN THIS BEFORE DEPLOYING THE SITE. The columns and tables are ignored by
--   the code that is live today, so the window between the two is harmless.
--   The new code refuses to issue at all when the functions are absent, so a
--   half issued letter cannot exist either way.
--
-- PREFLIGHT (read only, run first, expected results beside each)
--   select count(*) from public.client_documents;            -- unchanged after
--   select count(*) from public.client_services
--     where state = 'confirmed';                             -- unchanged after
--   select to_regclass('public.client_document_services');   -- null before
--   select to_regclass('public.client_document_seq');        -- null before
--   select count(*) from information_schema.columns
--     where table_name = 'clients' and column_name = 'client_code';  -- 0 before
--
-- POST-MIGRATION VERIFICATION
--   select to_regclass('public.client_document_services');   -- not null
--   select to_regclass('public.client_document_seq');        -- not null
--   select count(*) from public.client_document_services;    -- 0
--   select count(*) from public.clients where client_code is not null;  -- 0
--   select count(*) from public.client_documents where signed_at is not null
--      or verified_at is not null;                           -- 0
--   -- and the two counts from the preflight, unchanged.
--
-- ROLLBACK
--   At the foot, commented out. It drops the two new tables and the five
--   functions and leaves every added column in place: the columns are nullable
--   and unread by the old code, and dropping client_code would throw away
--   something staff had typed.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The Client ID
--    A business code staff own, separate from the row's uuid. Uppercase
--    letters and digits only: it goes into a serial number, so a slash or a
--    space would break the format it is part of. Two to twelve characters,
--    which is loose enough for whatever operations already write down.
-- ---------------------------------------------------------------------------
alter table public.clients add column if not exists client_code text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clients_client_code_fmt') then
    alter table public.clients add constraint clients_client_code_fmt
      check (client_code is null or client_code ~ '^[A-Z0-9]{2,12}$');
  end if;
end $$;

-- Unique where set. A partial index, so any number of clients may have none.
create unique index if not exists clients_client_code_uidx
  on public.clients (client_code) where client_code is not null;

-- ---------------------------------------------------------------------------
-- 2. The letter's own lifecycle
--    Issued -> Signed, awaiting verification -> Verified. voided_at is reused
--    as it stands. superseded_by names the letter that replaced this one, for
--    the explicit replacement path.
-- ---------------------------------------------------------------------------
alter table public.client_documents add column if not exists signed_at     timestamptz;
alter table public.client_documents add column if not exists verified_at   timestamptz;
alter table public.client_documents add column if not exists verified_by   text;
alter table public.client_documents add column if not exists superseded_by uuid;
alter table public.client_documents add column if not exists client_code   text;
alter table public.client_documents add column if not exists idem_key      text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'client_documents_superseded_fk') then
    alter table public.client_documents add constraint client_documents_superseded_fk
      foreign key (superseded_by) references public.client_documents(id) on delete set null;
  end if;
end $$;

-- One submission, one letter. A double click carries the same key and the
-- second insert loses to this index, which issue_letter then reads back.
create unique index if not exists client_documents_idem_uidx
  on public.client_documents (client_id, idem_key) where idem_key is not null;

-- ---------------------------------------------------------------------------
-- 3. Which services a letter captured
--    The primary key is the "one service once per document" rule. The service
--    reference is `restrict`, not `cascade`: a line that has been quoted to a
--    client on paper is not a row anybody may delete out from under the
--    letter. Services are archived, never deleted, so nothing legitimate is
--    blocked by it.
-- ---------------------------------------------------------------------------
create table if not exists public.client_document_services (
  document_id uuid not null references public.client_documents(id) on delete cascade,
  service_id  uuid not null references public.client_services(id)  on delete restrict,
  created_at  timestamptz not null default now(),
  primary key (document_id, service_id)
);
create index if not exists cds_service_idx on public.client_document_services(service_id);

alter table public.client_document_services enable row level security;
-- Read only from the client side of the wire. Every write goes through the
-- security definer functions below, so nobody can attach a line to a letter by
-- calling PostgREST.
drop policy if exists cds_read on public.client_document_services;
create policy cds_read on public.client_document_services for select to authenticated
  using (public.allowed('clients'));

-- ---------------------------------------------------------------------------
-- 4. The serial, per client, per Malaysian calendar month
--    Reserved by an upsert, which takes a row lock, so two people pressing
--    Issue letter in the same second get consecutive numbers and neither
--    retries. A number handed out is spent: voiding, superseding or a later
--    failure never returns it to the pool.
-- ---------------------------------------------------------------------------
create table if not exists public.client_document_seq (
  client_id uuid not null references public.clients(id) on delete cascade,
  ym        text not null,                       -- 'YYMM' in Asia/Kuala_Lumpur
  next_val  int  not null default 1,
  primary key (client_id, ym)
);
alter table public.client_document_seq enable row level security;
drop policy if exists cdseq_read on public.client_document_seq;
create policy cdseq_read on public.client_document_seq for select to authenticated
  using (public.allowed('clients'));

-- ---------------------------------------------------------------------------
-- 5. Issuing
-- ---------------------------------------------------------------------------
create or replace function public.issue_letter(
  p_client    uuid,
  p_services  uuid[],
  p_idem      text,
  p_subtotal  numeric,
  p_tax       numeric,
  p_total     numeric,
  p_deal      jsonb   default '{}'::jsonb,
  p_replaces  uuid    default null,
  p_renewal   boolean default false
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
  if not public.allowed('clients') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if p_client is null or p_services is null or array_length(p_services, 1) is null then
    return jsonb_build_object('error', 'no-lines');
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;

  -- The Client ID is what the serial is built from, so there is no letter
  -- without one. Staff enter it on the record; nothing invents it.
  if coalesce(btrim(cl.client_code), '') = '' then
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
    return jsonb_build_object('error', 'clash');
end $$;

grant execute on function public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The client signed it. That is a fact about the letter and nothing else.
-- ---------------------------------------------------------------------------
create or replace function public.letter_set_signed(p_doc uuid, p_on boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.client_documents%rowtype;
  cl  public.clients%rowtype;
begin
  if not public.allowed('clients') then return jsonb_build_object('error', 'not-allowed'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('error', 'voided'); end if;
  if d.verified_at is not null then return jsonb_build_object('error', 'verified'); end if;
  -- Already where it is asked to be: say so and change nothing.
  if (d.signed_at is not null) = coalesce(p_on, true) then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  update public.client_documents
     set signed_at = case when coalesce(p_on, true) then now() else null end
   where id = p_doc;
  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, case when coalesce(p_on, true) then 'document.signed' else 'document.unsigned' end,
          cl.name, d.number);
  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.letter_set_signed(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Verification. The only thing in this portal that confirms a service.
--    It confirms the services mapped to THIS letter and reads no others.
-- ---------------------------------------------------------------------------
create or replace function public.verify_letter(p_doc uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.client_documents%rowtype;
  cl    public.clients%rowtype;
  me    public.team_members%rowtype;
  v_map int;
  v_n   int;
begin
  if not public.allowed('billing') then return jsonb_build_object('error', 'not-allowed'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('error', 'voided'); end if;
  if d.superseded_by is not null then return jsonb_build_object('error', 'superseded'); end if;
  if d.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;

  -- Verifying twice is verifying once.
  if d.verified_at is not null then
    return jsonb_build_object('ok', true, 'repeat', true, 'confirmed', 0);
  end if;

  -- A letter issued before this change has no mappings, so there is nothing
  -- to confirm and no guess is made. It stays history.
  select count(*) into v_map from public.client_document_services where document_id = p_doc;
  if v_map = 0 or v_map <> coalesce(jsonb_array_length(d.lines), -1) then
    return jsonb_build_object('error', 'no-mapping');
  end if;

  update public.client_services cs
     set state = 'confirmed'
    from public.client_document_services m
   where m.document_id = p_doc and cs.id = m.service_id
     and cs.archived_at is null and cs.state <> 'confirmed';
  get diagnostics v_n = row_count;

  select * into me from public.team_members where lower(email) = who and active limit 1;
  update public.client_documents
     set verified_at = now(), verified_by = coalesce(me.name, who)
   where id = p_doc;

  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.verified', cl.name,
          d.number || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end || ' confirmed');
  return jsonb_build_object('ok', true, 'confirmed', v_n);
end $$;

grant execute on function public.verify_letter(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Void. It never touches a service, and it refuses a verified letter:
--    that one is the record of something the client signed and we accepted.
-- ---------------------------------------------------------------------------
create or replace function public.letter_set_void(p_doc uuid, p_on boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.client_documents%rowtype;
  cl  public.clients%rowtype;
begin
  if not public.allowed('clients') then return jsonb_build_object('error', 'not-allowed'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.verified_at is not null then return jsonb_build_object('error', 'verified'); end if;
  if (d.voided_at is not null) = coalesce(p_on, true) then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  update public.client_documents
     set voided_at = case when coalesce(p_on, true) then now() else null end
   where id = p_doc;
  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, case when coalesce(p_on, true) then 'document.voided' else 'document.restored' end,
          cl.name, d.number);
  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.letter_set_void(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. The escape hatch. An admin may still set a service state by hand, for a
--    legacy line or an exception, and must say why. It is written to the
--    activity record with the reason, so it is never a silent edit.
-- ---------------------------------------------------------------------------
create or replace function public.override_service_state(p_service uuid, p_state text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  cs  public.client_services%rowtype;
  cl  public.clients%rowtype;
  adm boolean;
begin
  select coalesce(t.is_admin, t.role = 'admin', false) into adm
    from public.team_members t where lower(t.email) = who and t.active limit 1;
  if not coalesce(adm, false) then return jsonb_build_object('error', 'not-allowed'); end if;
  if p_state not in ('enquired', 'quoted', 'confirmed') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into cs from public.client_services where id = p_service and archived_at is null;
  if cs.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if cs.state = p_state then return jsonb_build_object('ok', true, 'repeat', true); end if;
  update public.client_services set state = p_state where id = p_service;
  select * into cl from public.clients where id = cs.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'service.override', cl.name,
          cs.label || ' · ' || cs.state || ' to ' || p_state || ' · ' || btrim(p_reason));
  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.override_service_state(uuid, text, text) to authenticated;

-- ===========================================================================
-- ROLLBACK (commented out on purpose)
--
-- drop function if exists public.override_service_state(uuid, text, text);
-- drop function if exists public.letter_set_void(uuid, boolean);
-- drop function if exists public.verify_letter(uuid);
-- drop function if exists public.letter_set_signed(uuid, boolean);
-- drop function if exists public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean);
-- drop table if exists public.client_document_services;
-- drop table if exists public.client_document_seq;
-- drop index if exists public.client_documents_idem_uidx;
--
-- The added columns stay. They are nullable and the old code never reads them,
-- and dropping clients.client_code would throw away something staff typed.
-- ===========================================================================
