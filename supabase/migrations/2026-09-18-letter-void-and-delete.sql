-- ===========================================================================
-- 2026-09-18  Voiding and deleting a letter are two different authorities
--
-- WHAT WAS WRONG
--   `letter_set_void` took one argument, asked for no reason, recorded nobody,
--   refused a verified letter outright, and reverted no service line. So the
--   only way to undo a verified letter was the admin override on each service
--   line one at a time, with no link back to the letter that caused it.
--   There was no way at all to remove a letter keyed in by mistake, and the
--   smoke-test letters issued against production had nowhere to go.
--
-- WHAT THIS CHANGES
--   Additive only. No existing column changes meaning, no row is rewritten,
--   no serial is reissued.
--
--   team_roles.can_doc_void     a new capability: void a verified letter.
--   team_members.can_doc_void   the member's copy, stamped by the same
--                               trigger that stamps every other switch.
--   client_documents            voided_by, void_reason.
--   client_document_deletions   the minimal audit event a permanent deletion
--                               leaves behind. It carries the former id, the
--                               serial, the actor, the time, the reason and
--                               the service ids, and NO client document
--                               content: no lines, no bill_to, no totals.
--
--   Two functions replaced, one added:
--     letter_set_void    now takes a reason, requires can_doc_void, applies
--                        to a VERIFIED letter, records who and why, and
--                        reverts only the service lines this letter alone
--                        confirmed.
--     letter_delete      permanent, gated on can_remove (the portal's
--                        existing hard-delete authority, an admin's by
--                        default), requires the exact serial typed back and
--                        a reason, same safe reversal, writes the audit row.
--     letter_undelete    is deliberately ABSENT. There is no stored PDF and
--                        no signed upload for a letter, so there is no
--                        object to quarantine and nothing a seven day window
--                        could restore: the row is the letter. The console
--                        says the deletion is immediate and irreversible.
--
-- WHY VOID IS VERIFIED-ONLY
--   A void is the reversal of a confirmation. An issued or signed letter has
--   confirmed nothing, so there is nothing to reverse and the row is either
--   still wanted or was never wanted at all, which is a deletion. This
--   narrows what `letter_set_void` used to accept; the console no longer
--   offers Void on an issued or signed letter, and offers Delete to an
--   admin instead.
--
-- SERIALS
--   A voided serial and a deleted serial are both spent for ever. The
--   counter in client_document_seq only ever increments, so neither can be
--   handed out again; the audit row records the deleted one so the gap in
--   the sequence has an explanation.
--
-- HOW TO RUN IT
--   Supabase dashboard > SQL editor > paste this file > Run. Safe to run more
--   than once. Nothing else in supabase/schema.sql needs re-running; the same
--   objects are mirrored there for a fresh database.
--
--   RUN THIS BEFORE DEPLOYING THE SITE. The column and the table are ignored
--   by the code that is live today. The new code calls letter_delete, which
--   simply does not exist until this has run, and the console names the
--   failure rather than appearing to succeed.
--
-- PREFLIGHT (read only, run first, expected results beside each)
--   select count(*) from public.client_documents;                  -- unchanged after
--   select count(*) from public.client_documents
--     where voided_at is not null;                                 -- unchanged after
--   select count(*) from public.client_services
--     where state = 'confirmed';                                   -- unchanged after
--   select to_regclass('public.client_document_deletions');         -- null before
--   select count(*) from information_schema.columns
--     where table_name = 'team_roles' and column_name = 'can_doc_void';  -- 0 before
--
-- POST-MIGRATION VERIFICATION
--   select to_regclass('public.client_document_deletions');         -- not null
--   select count(*) from public.client_document_deletions;          -- 0
--   select slug, can_doc_void from public.team_roles order by position;
--        -- admin true, every other group false
--   select count(*) from public.team_members where can_doc_void;    -- the admins
--   select count(*) from public.client_documents
--     where void_reason is not null;                                -- 0
--   -- and the three counts from the preflight, unchanged.
--
-- ROLLBACK
--   At the foot, commented out.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The capability. Voiding a verified letter reverses a commercial
--    confirmation, so it is its own switch rather than a corner of
--    can_clients. Permanent deletion is NOT a new switch: can_remove is
--    already this portal's hard-delete authority (a contact, a rate card
--    line) and is an admin's by default, so a letter joins what it governs.
-- ---------------------------------------------------------------------------
alter table public.team_roles   add column if not exists can_doc_void boolean not null default false;
alter table public.team_members add column if not exists can_doc_void boolean not null default false;

-- Seeded once onto the Admin group, and never re-applied: a group's switches
-- are edited on the Team page by the people who own them, and a seed that ran
-- on every pass would put back a switch somebody had deliberately turned off.
do $$ begin
  if not exists (select 1 from public.team_roles where can_doc_void) then
    update public.team_roles set can_doc_void = true where slug = 'admin';
  end if;
end $$;

-- The member carries the group's switches, so the stamp has to carry this one
-- too or a member's copy is false for ever however the group is set.
create or replace function public.team_role_defaults()
returns trigger language plpgsql as $$
declare r public.team_roles;
begin
  select * into r from public.team_roles where slug = new.role;
  if r.slug is null then
    select * into r from public.team_roles where slug = 'account';
    new.role := 'account';
  end if;
  new.is_admin      := r.is_admin;
  new.can_clients   := r.can_clients;   new.can_review   := r.can_review;
  new.can_campaigns := r.can_campaigns; new.can_links    := r.can_links;
  new.can_activity  := r.can_activity;  new.can_billing  := r.can_billing;
  new.can_remove    := r.can_remove;    new.can_doc_void := r.can_doc_void;
  new.updated_at    := now();
  return new;
end $$;

-- Re-stamp everyone so the new switch reaches the members who already exist.
update public.team_members set updated_at = updated_at;

-- allowed() answers for the new flag. Admin is still true for everything.
create or replace function public.allowed(flag text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
    where lower(email) = lower(auth.jwt() ->> 'email') and active limit 1;
  if t.id is null then return false; end if;
  if t.role = 'admin' then return true; end if;
  return coalesce(case flag
    when 'clients'   then t.can_clients
    when 'review'    then t.can_review
    when 'campaigns' then t.can_campaigns
    when 'links'     then t.can_links
    when 'activity'  then t.can_activity
    when 'billing'   then t.can_billing
    when 'remove'    then t.can_remove
    when 'doc_void'  then t.can_doc_void
    when 'admin'     then false
  end, false);
end $$;

grant execute on function public.allowed(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Who voided it and why. A void without a reason is a state change nobody
--    can account for six months later.
-- ---------------------------------------------------------------------------
alter table public.client_documents add column if not exists voided_by   text;
alter table public.client_documents add column if not exists void_reason text;

-- ---------------------------------------------------------------------------
-- 3. What a permanent deletion leaves behind. Enough to answer "what happened
--    to AQL/AC173/260902" and no more: the serial is kept so the gap in the
--    month's sequence has an explanation, and none of the client's document
--    content is kept, because the point of the deletion was to remove it.
-- ---------------------------------------------------------------------------
create table if not exists public.client_document_deletions (
  id          uuid primary key default gen_random_uuid(),
  document_id uuid not null,
  number      text not null,
  client_id   uuid,
  actor       text,
  reason      text not null,
  service_ids uuid[] not null default '{}',
  deleted_at  timestamptz not null default now()
);
create index if not exists client_document_deletions_client_idx
  on public.client_document_deletions (client_id);

alter table public.client_document_deletions enable row level security;
drop policy if exists client_document_deletions_read on public.client_document_deletions;
create policy client_document_deletions_read on public.client_document_deletions
  for select to authenticated using (public.allowed('clients'));
-- No insert, update or delete policy: the audit row is written by
-- letter_delete, which is security definer, and by nothing else.

-- ---------------------------------------------------------------------------
-- 4. Which service lines a letter alone is holding confirmed.
--    A line may be mapped to more than one verified letter (a renewal, a
--    replacement), and reverting it because one of them went away would undo
--    a confirmation the other one still carries. So: mapped to this letter,
--    currently confirmed, and mapped to no OTHER letter that is verified and
--    not voided.
-- ---------------------------------------------------------------------------
create or replace function public.letter_sole_services(p_doc uuid)
returns uuid[]
language sql security definer stable set search_path = public as $$
  select coalesce(array_agg(m.service_id), '{}')
    from public.client_document_services m
    join public.client_services s on s.id = m.service_id
   where m.document_id = p_doc
     and s.state = 'confirmed'
     and not exists (
       select 1
         from public.client_document_services m2
         join public.client_documents d2 on d2.id = m2.document_id
        where m2.service_id = m.service_id
          and m2.document_id <> p_doc
          and d2.verified_at is not null
          and d2.voided_at is null);
$$;

grant execute on function public.letter_sole_services(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Void. A verified letter, a reason, and only the lines this letter alone
--    confirmed. One transaction: a function body is one.
-- ---------------------------------------------------------------------------
create or replace function public.letter_set_void(p_doc uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who  text := lower(auth.jwt() ->> 'email');
  d    public.client_documents%rowtype;
  cl   public.clients%rowtype;
  ids  uuid[];
begin
  if not public.allowed('doc_void') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;

  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('ok', true, 'repeat', true); end if;
  -- A letter that has confirmed nothing has nothing to reverse: it is either
  -- still wanted, or it is a deletion.
  if d.verified_at is null then return jsonb_build_object('error', 'not-verified'); end if;

  ids := public.letter_sole_services(p_doc);

  update public.client_documents
     set voided_at   = now(),
         voided_by   = who,
         void_reason = btrim(p_reason)
   where id = p_doc;

  update public.client_services set state = 'quoted'
   where id = any(ids);

  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.voided', cl.name,
          d.number || ' · ' || btrim(p_reason) ||
          ' · ' || coalesce(array_length(ids, 1), 0) || ' service lines reverted');

  return jsonb_build_object('ok', true, 'reverted', coalesce(array_length(ids, 1), 0));
end $$;

grant execute on function public.letter_set_void(uuid, text) to authenticated;

-- The old two argument form is dropped, so a stale page cannot void without a
-- reason. It is dropped AFTER the new one is created, so there is never a
-- moment with no letter_set_void at all.
drop function if exists public.letter_set_void(uuid, boolean);

-- ---------------------------------------------------------------------------
-- 6. Permanent deletion. can_remove, the exact serial typed back, and a
--    reason. The mapping goes with the row (on delete cascade), the audit row
--    stays, and the serial is never handed out again.
-- ---------------------------------------------------------------------------
create or replace function public.letter_delete(p_doc uuid, p_confirm text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  d   public.client_documents%rowtype;
  cl  public.clients%rowtype;
  ids uuid[];
begin
  if not public.allowed('remove') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;

  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;

  -- Typed back exactly, because the serial is the one thing that identifies
  -- which letter is about to stop existing.
  if btrim(coalesce(p_confirm, '')) <> d.number then
    return jsonb_build_object('error', 'confirm-mismatch');
  end if;

  ids := public.letter_sole_services(p_doc);

  update public.client_services set state = 'quoted'
   where id = any(ids);

  -- A letter that replaced this one keeps pointing at nothing rather than at
  -- a row that is gone.
  update public.client_documents set superseded_by = null where superseded_by = p_doc;

  insert into public.client_document_deletions
    (document_id, number, client_id, actor, reason, service_ids)
  values (d.id, d.number, d.client_id, who, btrim(p_reason), coalesce(ids, '{}'));

  select * into cl from public.clients where id = d.client_id;

  -- client_document_services cascades on this delete.
  delete from public.client_documents where id = p_doc;

  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.deleted', cl.name,
          d.number || ' · ' || btrim(p_reason) ||
          ' · ' || coalesce(array_length(ids, 1), 0) || ' service lines reverted');

  return jsonb_build_object('ok', true, 'number', d.number,
                            'reverted', coalesce(array_length(ids, 1), 0));
end $$;

grant execute on function public.letter_delete(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. A letter is signed by a person, never by a permission. issue_letter
--    stamped issued_by from team_members.name, and a row named "Superadmin"
--    put that word on a client's letterhead. There is no designation field
--    and none is wanted: the name alone is what signs. So the name has to be
--    a name, and a letter is refused rather than drawn with a role on it.
-- ---------------------------------------------------------------------------
create or replace function public.issuer_name_ok(p_name text)
returns boolean
language sql immutable set search_path = public as $$
  select coalesce(btrim(p_name), '') <> ''
     and position('@' in p_name) = 0
     and lower(btrim(p_name)) not in (
       'superadmin', 'super admin', 'admin', 'administrator', 'team member',
       'team', 'marketing', 'sales', 'account', 'user', 'root', 'owner',
       'staff', 'system', 'support', 'test');
$$;

grant execute on function public.issuer_name_ok(text) to authenticated;

-- issue_letter is recreated whole, because Postgres replaces a function body
-- entire. The only change from the 2026-09-17 file is the issuer guard below;
-- every other line is that file's, unaltered.
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

  -- A letter is signed by a person. issued_by is this row's name, so a team
  -- row named "Superadmin" printed that word under ADSPACE PLT on a client's
  -- letterhead. Refuse rather than draw a permission as a signatory: the
  -- console says which name to fix and where.
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

-- ===========================================================================
-- ROLLBACK (commented out on purpose)
--
-- drop function if exists public.letter_delete(uuid, text, text);
-- drop function if exists public.letter_sole_services(uuid);
-- drop function if exists public.issuer_name_ok(text);
-- drop table if exists public.client_document_deletions;
--
-- -- and the previous letter_set_void, which took a boolean and no reason:
-- drop function if exists public.letter_set_void(uuid, text);
-- create or replace function public.letter_set_void(p_doc uuid, p_on boolean default true)
-- returns jsonb language plpgsql security definer set search_path = public as $$
-- declare who text := lower(auth.jwt() ->> 'email');
--         d public.client_documents%rowtype; cl public.clients%rowtype;
-- begin
--   if not public.allowed('clients') then return jsonb_build_object('error', 'not-allowed'); end if;
--   select * into d from public.client_documents where id = p_doc;
--   if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
--   if d.verified_at is not null then return jsonb_build_object('error', 'verified'); end if;
--   if (d.voided_at is not null) = coalesce(p_on, true) then
--     return jsonb_build_object('ok', true, 'repeat', true); end if;
--   update public.client_documents
--      set voided_at = case when coalesce(p_on, true) then now() else null end where id = p_doc;
--   select * into cl from public.clients where id = d.client_id;
--   insert into public.activity_log (actor, action, subject, detail)
--   values (who, case when coalesce(p_on, true) then 'document.voided' else 'document.restored' end,
--           cl.name, d.number);
--   return jsonb_build_object('ok', true);
-- end $$;
--
-- The added columns stay. They are nullable and the old code never reads them.
-- ===========================================================================
