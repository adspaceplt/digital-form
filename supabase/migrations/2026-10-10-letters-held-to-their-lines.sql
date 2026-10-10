-- ===========================================================================
-- LETTERS HELD TO THEIR LINES — a letter is priced by the database and
-- verified only over the lines it printed; a client's deletion files itself;
-- the documents table takes no direct write; a group seeing only its own
-- clients holds no Activity record (audit S2, S4, R1, 2026-10-10).
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/lettersql.js compares
-- the two. It drops policies, so it runs in the SQL Editor.
--
-- WHAT CHANGED
--   1. `issue_letter` works the price itself (the letter's own rule:
--      js/documents.js priceOf, js/money.js rateFor, SST at the rate in
--      force today) and refuses page figures that differ by more than a sen
--      (`stale`, with the figures now). Same signature.
--   2. `verify_letter` refuses a letter one of whose lines was removed since
--      (`archived-line`) or whose quantity, rate, term or adjustment moved
--      since it was issued (`changed-terms`).
--   3. `delete_client` files `client.deleted` itself, in the transaction that
--      deletes; the page no longer files it.
--   4. `client_documents` keeps its read policy; insert, update and delete
--      go only through the letter functions (no page writes the table).
--   5. Trigger `team_roles_scope_guard`: a group is not given Own clients
--      only together with any Activity record access (`scope-activity`),
--      since the record is not scoped. An admin group is left alone.
--
-- ROLLBACK
--   Re-run the CLIENT LETTERS section's issue_letter and verify_letter, the
--   ONE SET OF HANDLES section's delete_client (the page filing again), and
--   the DELETE AT ITS LEVEL section's three client_documents policies, and
--   remove the trigger and its function.
-- ===========================================================================

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
  /* A reference somebody typed. Blank is the ordinary case and the counter
     below makes the number; where one is typed it is checked against every
     document that stands and the counter is not advanced, so filling a gap
     by hand never costs the next letter its place in the sequence. */
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
  v_try  int;
  v_no   text;
  v_id   uuid;
  v_lines jsonb;
  v_n    int;
  v_bad  int;
  v_old  public.client_documents%rowtype;
  v_term int;
  v_each numeric;
  v_etax numeric;
  v_sub  numeric;
  v_tax  numeric;
  v_tot  numeric;
  v_pct  numeric;
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
  -- without one. Staff enter it on the record; nothing invents it. A typed
  -- reference needs no code, because nothing is being built.
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
  -- the Register accepts, and refused where a document still holds it.
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
           -- The line's own answer to whether its term prices it. Written into
           -- the snapshot because the letter is redrawn from it, and a letter
           -- must print the same figure every time it is drawn. A snapshot
           -- taken before this key existed carries none, which money.js reads
           -- as on, so those letters redraw as they were issued.
           'term_adjust', coalesce(cs.term_adjust, false),
           -- And the percentage that tick applies, so a later rate card can
           -- never move a figure this letter printed. Null on a line quoted
           -- before the column existed, which money.js reads as that card.
           'term_pct', cs.term_pct,
           'tax', cl.sst_applies is not false,
           'service_id', cs.id)
           order by cs.created_at)
    into v_lines
    from public.client_services cs
   where cs.id = any(p_services);
  if v_lines is null then return jsonb_build_object('error', 'no-lines'); end if;

  /* The price is the database's (audit S4, 2026-10-10), worked as the
     letter draws it (js/documents.js priceOf, js/money.js rateFor): each
     line's rate with its term on it, rounded to the cent; a letter whose
     lines share a term of more than a month priced by the month and times
     the term; SST at the rate in force today unless the client is exempt.
     The page's figures are kept only where they agree to the sen, so a line
     changed since the sheet opened, or a figure typed in a browser, is
     refused (`stale`) and the sheet reads the lines again. */
  select case when count(distinct greatest(1, coalesce(cs.tenure, 1))) = 1
               and min(greatest(1, coalesce(cs.tenure, 1))) > 1
              then min(greatest(1, coalesce(cs.tenure, 1))) else 0 end
    into v_term
    from public.client_services cs where cs.id = any(p_services);
  select coalesce(sum(coalesce(cs.qty, 0) *
           round(coalesce(cs.rate, 0) *
             case when cs.term_adjust is false then 1
                  when cs.term_pct is not null then 1 + cs.term_pct / 100
                  else case greatest(1, coalesce(cs.tenure, 1))
                         when 3 then 1 / 0.9 when 12 then 0.95 when 24 then 0.9 else 1 end
             end, 2) *
           case when v_term > 0 then 1 else greatest(1, coalesce(cs.tenure, 1)) end), 0)
    into v_each
    from public.client_services cs where cs.id = any(p_services);
  v_pct := case when cl.sst_applies is false then 0
                else coalesce(public.app_setting('sst_pct', (timezone('Asia/Kuala_Lumpur', now()))::date), 0) end;
  v_etax := round(v_each * v_pct) / 100;
  v_sub := round(v_each * greatest(v_term, 1), 2);
  v_tax := round(v_etax * greatest(v_term, 1), 2);
  v_tot := round(round(v_each + v_etax, 2) * greatest(v_term, 1), 2);
  if abs(coalesce(p_subtotal, -1) - v_sub) > 0.01 or abs(coalesce(p_tax, -1) - v_tax) > 0.01
     or abs(coalesce(p_total, -1) - v_tot) > 0.01 then
    return jsonb_build_object('error', 'stale', 'subtotal', v_sub, 'tax', v_tax, 'total', v_tot);
  end if;

  -- A typed reference spends no sequence number: the counter is the office's
  -- record of how many letters it has issued this month, and a person filling
  -- a gap by hand has not issued one more.
  if v_no is null then
    -- The month is Malaysian, because the office that numbers the letter is.
    v_ym := to_char(timezone('Asia/Kuala_Lumpur', now()), 'YYMM');

    -- The counter still advances on every automatic issue, and the upsert's
    -- row lock is what makes the scan below safe: a second issuer blocks here
    -- until the first has committed its letter, so the two never read the same
    -- gap as free. What the counter gives is a bound to scan within, not the
    -- number itself.
    insert into public.client_document_seq (client_id, ym, next_val)
         values (p_client, v_ym, 2)
    on conflict (client_id, ym)
      do update set next_val = public.client_document_seq.next_val + 1
      returning next_val - 1 into v_seq;

    -- The lowest free slot, not the counter's own value. A deleted letter
    -- releases its reference (serial_taken stopped counting deletions on
    -- 2026-09-20), and without this the automatic path still counted upward
    -- past the gap: a client whose first two letters were issued in testing
    -- and deleted started at 03 for ever. The counter is at least the number
    -- of letters issued this month, so a free slot exists at or below it
    -- unless somebody has typed references over the same range by hand; the
    -- cap covers that and refuses rather than looping.
    --
    -- Two digits is the floor, not the ceiling: the hundredth letter of a month
    -- widens to three rather than wrapping. Not lpad(): Postgres pads AND
    -- truncates to the width it is given, so lpad('100', 2, '0') is '10' and the
    -- hundredth letter would collide with the tenth.
    v_try := 1;
    loop
      v_no := 'AQL/' || cl.client_code || '/' || v_ym ||
              case when v_try < 100 then lpad(v_try::text, 2, '0') else v_try::text end;
      exit when not public.serial_taken(v_no);
      v_try := v_try + 1;
      if v_try > greatest(v_seq, 1) + 200 then
        return jsonb_build_object('error', 'no-serial');
      end if;
    end loop;
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
    -- A typed reference two people sent at once: the loser is told the
    -- reference is spent rather than that "two letters were issued at once",
    -- which names a cause they cannot act on.
    if nullif(btrim(coalesce(p_serial, '')), '') is not null then
      return jsonb_build_object('error', 'serial-taken');
    end if;
    return jsonb_build_object('error', 'clash');
end $$;

grant execute on function public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean, text) to authenticated;

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
  if not public.allowed('clients.documents') then return jsonb_build_object('error', 'not-allowed'); end if;
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

  /* What the client signed is the letter's snapshot. A line removed since,
     or one whose quantity, rate, term or adjustment moved since, is not
     what was signed, so nothing is confirmed (audit S4, 2026-10-10): the
     letter is reissued, or the line put back as it was. */
  if exists (select 1 from public.client_document_services m
               join public.client_services cs on cs.id = m.service_id
              where m.document_id = p_doc and cs.archived_at is not null) then
    return jsonb_build_object('error', 'archived-line');
  end if;
  if exists (select 1 from jsonb_array_elements(d.lines) l
               join public.client_services cs on cs.id = (l ->> 'service_id')::uuid
              where l ? 'service_id'
                and ((l ->> 'qty')::numeric is distinct from cs.qty
                  or (l ->> 'rate')::numeric is distinct from cs.rate
                  or (l ->> 'tenure')::int is distinct from greatest(1, coalesce(cs.tenure, 1))
                  or (l ? 'term_adjust' and (l ->> 'term_adjust')::boolean is distinct from coalesce(cs.term_adjust, false))
                  or (l ? 'term_pct' and (l ->> 'term_pct')::numeric is distinct from cs.term_pct))) then
    return jsonb_build_object('error', 'changed-terms');
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

create or replace function public.delete_client(p_client uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  want text;
  who  text := auth.jwt() ->> 'email';
  cl   public.clients%rowtype;
  me   public.team_members%rowtype;
begin
  if who is null then
    raise exception 'Not signed in';
  end if;

  select value into want from public.app_secrets where key = 'delete_code';

  -- No code set: the interface asks for the client's name instead, and has
  -- already checked it. Nothing more to enforce here.
  if want is not null and want <> '' then
    if p_code is null or p_code <> want then
      return 'wrong-code';
    end if;
  end if;

  select * into cl from public.clients where id = p_client;
  delete from public.clients where id = p_client;
  if not found then
    return 'not-found';
  end if;
  /* Filed here, in the same transaction, never by the page after the answer
     (audit R1, 2026-10-10): a reply lost on the way left no record. */
  select * into me from public.team_members where lower(email) = lower(who) and active limit 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, who), 'client.deleted', cl.name, coalesce(cl.client_code, ''));
  return 'deleted';
end $$;

revoke all on function public.delete_client(uuid, text) from anon;
grant execute on function public.delete_client(uuid, text) to authenticated;

drop policy if exists client_documents_write on public.client_documents;
drop policy if exists client_documents_edit on public.client_documents;
drop policy if exists client_documents_del on public.client_documents;

/* Own clients only narrows Clients and every table under a client, but the
   Activity record is not scoped: it names every client's events. A group
   holds one or the other until the record is scoped (the user, 2026-10-10). */
create or replace function public.team_roles_scope_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(new.client_scope, 'all') = 'own' and not coalesce(new.is_admin, false)
     and (coalesce(new.access ->> 'activity', 'none') <> 'none'
          or exists (select 1 from jsonb_each_text(coalesce(new.access, '{}'::jsonb)) e
                      where e.key like 'activity.%' and e.value <> 'none')) then
    raise exception 'scope-activity'
      using hint = 'Own clients only cannot be given with the Activity record, which is not limited to a colleague''s clients.';
  end if;
  return new;
end $$;
revoke all on function public.team_roles_scope_guard() from public, anon, authenticated;
create or replace trigger team_roles_scope_guard
  before insert or update of access, client_scope, is_admin on public.team_roles
  for each row execute function public.team_roles_scope_guard();

-- END OF LETTERS HELD TO THEIR LINES -------------------------------------------

select public.functions_tidy();
