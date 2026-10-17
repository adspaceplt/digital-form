-- ===========================================================================
-- LETTERS PRICED AS QUOTED WHILE VALID — a Letter of Offer takes its
-- quotation's term percentage and SST only while the quotation stands.
-- 2026-10-17. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/lettersql.js
-- compares the two.
--
-- WHAT CHANGED (the review of the audit's fix batches, finding 2)
--   LETTERS PRICED AS QUOTED priced a letter at its quotation's term
--   percentage and SST whenever every line carried one `quotation_id`. The
--   link is never cleared, and the quotation's validity was never read, so
--   a renewal on the same confirmed lines months later, or a letter
--   replacing one after the quotation lapsed, still charged the SST of the
--   day it was quoted. `issue_letter` now takes the quotation's figures
--   only where it is not a renewal, the quotation is not removed and its
--   `valid_until` is today or later (Malaysia's day); otherwise the letter
--   is priced on today's rates, as every other letter. The page holds the
--   same rule (js/documents.js `quoteOf`).
--
-- ROLLBACK
--   Run issue_letter again from LETTERS PRICED AS QUOTED (2026-10-17).
--   Letters issued meanwhile keep their figures.
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
  v_once numeric;
  v_otax numeric;
  v_sub  numeric;
  v_tax  numeric;
  v_tot  numeric;
  v_pct  numeric;
  v_qid  uuid;
  v_q    public.quotations%rowtype;
  v_tp   numeric;
  v_tpn  int;
  v_tadj boolean;
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
     line's rate with its term on it, rounded to the cent. Where every line
     of more than a month shares one term, those lines are priced by the
     month and times the term, and a line of one month is a one-off item
     with its own SST (2026-10-15: a one-off item beside them no longer
     turns the letter into one whole total); otherwise every line is its
     whole amount. SST at the rate in force today unless the client is
     exempt. The page's figures are kept only where they agree to the sen,
     so a line changed since the sheet opened, or a figure typed in a
     browser, is refused (`stale`) and the sheet reads the lines again. */
  select case when count(distinct greatest(1, coalesce(cs.tenure, 1)))
                     filter (where greatest(1, coalesce(cs.tenure, 1)) > 1) = 1
              then max(greatest(1, coalesce(cs.tenure, 1))) else 0 end
    into v_term
    from public.client_services cs where cs.id = any(p_services);
  /* A letter whose every line came from one quotation is priced as that
     quotation was (audit F, 2026-10-17): its term percentage taken once on
     each subtotal, never rounded line by line, and SST at the rate the
     quotation was made with, never today's. The page's figures are held to
     the same price (js/documents.js priceOf). */
  select case when count(*) filter (where cs.quotation_id is null) = 0
                   and count(distinct cs.quotation_id) = 1 then min(cs.quotation_id::text)::uuid end,
         count(distinct coalesce(cs.term_pct, 0)) filter (where greatest(1, coalesce(cs.tenure, 1)) > 1),
         coalesce(bool_and(cs.term_adjust is not false) filter (where greatest(1, coalesce(cs.tenure, 1)) > 1), true),
         coalesce(max(cs.term_pct) filter (where greatest(1, coalesce(cs.tenure, 1)) > 1), 0)
    into v_qid, v_tpn, v_tadj, v_tp
    from public.client_services cs where cs.id = any(p_services);
  /* Only while the quotation still stands (2026-10-17, the review's
     finding 2): unexpired by Malaysia's day and not removed. A renewal, or a
     letter replacing one after the quotation lapsed, is priced on today's
     rates, as any other letter. */
  if v_qid is not null and coalesce(v_tpn, 0) <= 1 and v_tadj and not coalesce(p_renewal, false) then
    select * into v_q from public.quotations q
     where q.id = v_qid and q.removed_at is null
       and q.valid_until >= (timezone('Asia/Kuala_Lumpur', now()))::date;
  end if;
  if v_q.id is not null then
    if v_term > 0 then
      select coalesce(sum(coalesce(cs.qty, 0) * coalesce(cs.rate, 0))
               filter (where greatest(1, coalesce(cs.tenure, 1)) = v_term), 0),
             coalesce(sum(coalesce(cs.qty, 0) * coalesce(cs.rate, 0) * greatest(1, coalesce(cs.tenure, 1)))
               filter (where greatest(1, coalesce(cs.tenure, 1)) <> v_term), 0)
        into v_each, v_once
        from public.client_services cs where cs.id = any(p_services);
      v_each := v_each + round(v_each * v_tp / 100, 2);
    else
      select coalesce(sum(coalesce(cs.qty, 0) * coalesce(cs.rate, 0) * greatest(1, coalesce(cs.tenure, 1)))
               filter (where greatest(1, coalesce(cs.tenure, 1)) > 1), 0),
             coalesce(sum(coalesce(cs.qty, 0) * coalesce(cs.rate, 0))
               filter (where greatest(1, coalesce(cs.tenure, 1)) = 1), 0)
        into v_each, v_once
        from public.client_services cs where cs.id = any(p_services);
      v_once := v_each + round(v_each * v_tp / 100, 2) + v_once;
      v_each := 0;
    end if;
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce((v_q.totals->>'sst_pct')::numeric, 0) end;
    /* The letter keeps what it was priced on, so a redraw prints the same. */
    select jsonb_agg(l.e || jsonb_build_object('quotation_id', v_qid, 'quote_sst', v_pct) order by l.n)
      into v_lines from jsonb_array_elements(v_lines) with ordinality l(e, n);
  else
    select coalesce(sum(coalesce(cs.qty, 0) *
             round(coalesce(cs.rate, 0) *
               case when cs.term_adjust is false then 1
                    when cs.term_pct is not null then 1 + cs.term_pct / 100
                    else case greatest(1, coalesce(cs.tenure, 1))
                           when 3 then 1 / 0.9 when 12 then 0.95 when 24 then 0.9 else 1 end
               end, 2) *
             case when v_term > 0 then 1 else greatest(1, coalesce(cs.tenure, 1)) end)
             filter (where v_term > 0 and greatest(1, coalesce(cs.tenure, 1)) = v_term), 0),
           coalesce(sum(coalesce(cs.qty, 0) *
             round(coalesce(cs.rate, 0) *
               case when cs.term_adjust is false then 1
                    when cs.term_pct is not null then 1 + cs.term_pct / 100
                    else case greatest(1, coalesce(cs.tenure, 1))
                           when 3 then 1 / 0.9 when 12 then 0.95 when 24 then 0.9 else 1 end
               end, 2) *
             greatest(1, coalesce(cs.tenure, 1)))
             filter (where v_term = 0 or greatest(1, coalesce(cs.tenure, 1)) <> v_term), 0)
      into v_each, v_once
      from public.client_services cs where cs.id = any(p_services);
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce(public.app_setting('sst_pct', (timezone('Asia/Kuala_Lumpur', now()))::date), 0) end;
  end if;
  v_etax := round(v_each * v_pct) / 100;
  v_otax := round(v_once * v_pct) / 100;
  v_sub := round(v_each * greatest(v_term, 1), 2) + round(v_once, 2);
  v_tax := round(v_etax * greatest(v_term, 1), 2) + v_otax;
  v_tot := round(round(v_each + v_etax, 2) * greatest(v_term, 1), 2) + round(v_once + v_otax, 2);
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
       'contact_salutation', coalesce(ct.salutation, ''),
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

-- END OF LETTERS PRICED AS QUOTED WHILE VALID ------------------------------

select public.functions_tidy();
