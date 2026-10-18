-- ===========================================================================
-- SUPPLIER SERVICE AGREEMENT — a supplier's one document, issued from the
-- portal with its schedules (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18): the Supplier Service Agreement (Ads Campaign
-- Management) is the document a supplier signs; Letter to Supplier is no
-- longer offered. Schedule A names the supplier, the services and the fee;
-- Schedule B lists the client accounts it runs, picked from Clients, and is
-- updated by issuing a new copy (Reissue: the same reference, "Latest update
-- as at" the new day).
--
-- WHAT IT CHANGES
--   * `doc_types.schedule`: a type's prefilled schedule wording (the
--     agreement's Part 2 and Schedule B's notes), copied into each document.
--   * A type `supplier_sca`, Supplier Service Agreement, signed, its clauses
--     as its wording (`# Heading`, `1.` a numbered clause, `a.` a lettered
--     item, the team's to edit in Document types). Made once; the first run
--     also stops offering Letter to Supplier (issued letters keep their type).
--   * `issue_document` numbers it AD/SCA/{Supplier ID}/{YYMM}{NN}, the
--     lowest free from 01, and refuses one without its schedules
--     (`agreement-incomplete`, `sca_complete`).
--
-- ORDER: this file, then the pages. A page served before offers no
-- agreement. Safe to run twice. Rollback: ISSUE from SUPPLIERS; the type set
-- inactive (`doc_type_set_active`), Letter to Supplier active again.
-- ===========================================================================

alter table public.doc_types add column if not exists schedule jsonb;

/* Made once: an agreement row the team edited is never written over, and
   Letter to Supplier is stood down only on the run that makes it. */
with made as (
  insert into public.doc_types (id, family, code, name, title, salutation, closing, body_en, signed, position, schedule)
  select 'supplier_sca', 'supplier', 'SCA', 'Supplier Service Agreement', 'Service Agreement', '', '',
         $sca$# Parties

This Advertising Management Services Agreement (the "Agreement") is made on the Agreement Date stated in Schedule A between ADSPACE PLT (Business Registration Number: 202304002162), with its registered address at 61-02, Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia (the "Company"); and the person or entity named as the Supplier in Part 1 of Schedule A (the "Supplier").

The Company provides marketing services to its clients. The Company wishes to engage the Supplier, as an independent contractor, to plan, run and optimise paid advertising campaigns for those clients on the terms below.

# Definitions

1. "Client" means any person or business for whom the Company provides services and to whose work the Supplier is assigned or exposed during the Term, including any prospective client introduced to the Supplier by the Company.

1. "Confidential Information" means all non-public information disclosed to or obtained by the Supplier in connection with this Agreement, including Client identities and contacts, pricing, budgets, ad spend, campaign strategies, audiences, creatives, performance data, login credentials, business plans, processes, templates and know-how of the Company or any Client.

1. "Ad Accounts" means any advertising, analytics, tracking or business manager accounts (for example Meta, Google, TikTok, LinkedIn) used for Company or Client work.

1. "Work Product" means all campaigns, ad copy, creatives, audiences, reports, structures, playbooks, data and other materials created by the Supplier under this Agreement.

1. "Term" means the period described in Clause 4.

# Services

1. The Supplier will provide the ads management services set out in Schedule A (the "Services") for the Clients the Company assigns from time to time.

1. The Supplier will perform the Services with reasonable skill and care, follow each platform's advertising policies, and comply with the Company's reasonable instructions, brand guidelines and approval process.

1. The Supplier must not launch, pause, or change budgets on any campaign beyond the spend approval limit in Schedule A without the Company's prior written approval.

1. The Supplier will deal with Clients only through the Company, unless the Company asks the Supplier to join a call or channel. In any such contact the Supplier acts on the Company's behalf and under the Company's name.

1. The Company will set a monthly ad spend budget for each Ad Account, as listed in Schedule B or later confirmed by the Company in writing (the "Approved Budget"). The Supplier will pace spend so that each account's actual monthly spend stays within the budget tolerance in Schedule A.

1. If an account's spend exceeds its Approved Budget by more than the budget tolerance because the Supplier set up, changed or monitored a campaign incorrectly, or did not follow the Company's instructions, the Supplier will reimburse the Company for the excess spend. The Company may deduct this amount from any fees due.

1. Underspending. If an account is likely to spend less than its Approved Budget by more than the budget tolerance, the Supplier will notify the Company in writing within 1 working day, with the reason and a recovery plan. If the underspend results from the Supplier's failure to launch, monitor or optimise campaigns, the Company may reduce that month's fee for the account in proportion to the shortfall.

1. Exclusions. The Supplier is not responsible for over- or underspending caused by platform errors, billing or payment issues, account suspensions not caused by the Supplier, or written instructions from the Company or Client, provided the Supplier reports the issue to the Company promptly.

# Term

This Agreement starts on the Start Date stated in Schedule A and continues until terminated under Clause 10. If Schedule A states a trial period, either party may end this Agreement during that period on 30 days' written notice.

# Fees and Payment

1. The Company will pay the Supplier the fees set out in Schedule A.

1. The Supplier will invoice the Company monthly. The Company will pay valid invoices within 14 working days of receipt.

1. Ad spend is paid by the Company or the Client directly to the platform. The Supplier must not use any payment method for ad spend unless the Company approves it in writing.

1. The Supplier is responsible for their own taxes, statutory contributions and business expenses. No other expenses are reimbursed unless approved in writing beforehand.

1. If the Supplier becomes SST-registered, it will notify the Company in writing before charging SST, and the parties will agree any change to the fees in writing.

# Confidentiality and Data Protection

1. The Supplier will keep all Confidential Information strictly confidential and use it only to perform the Services.

1. The Supplier will not disclose it to anyone without the Company's prior written consent.

1. The Supplier will not copy, download, screenshot, export or store Confidential Information or Client data except as needed for the Services, and only on secure, password-protected devices and accounts.

1. The Supplier will not share login credentials, add other users to Ad Accounts, or allow any third party (including assistants or subcontractors) to access Company or Client work without the Company's written approval.

1. The Supplier will not publicly disclose that they work for the Company's Clients, or use any Client's name, logo, results or creatives in a portfolio, case study, social media post or pitch, unless the Company gives written permission.

1. The Supplier will handle any personal data (such as customer lists, leads and pixel data) in line with the Personal Data Protection Act 2010 and the Company's instructions, and will tell the Company within 24 hours of any suspected data breach or unauthorised access.

1. These obligations do not apply to information that is or becomes public through no fault of the Supplier, or that the law or a court requires to be disclosed (after first notifying the Company where lawful).

1. On request, and in any case when this Agreement ends, the Supplier will return or permanently delete all Confidential Information and confirm this in writing.

1. This Clause 6 continues to apply indefinitely after this Agreement ends.

# Intellectual Property and Account Ownership

1. All Work Product belongs to the Company (or the relevant Client, as the Company directs) from the moment it is created. The Supplier assigns to the Company all rights, including copyright, in the Work Product and waives any moral rights to the extent the law allows.

1. All Ad Accounts, pixels, audiences, data and business manager assets belong to the Company or the Client. The Supplier gains no ownership of them and must not transfer, duplicate or claim them.

1. The Supplier will work only through access granted by the Company. The Supplier must not move Client assets into accounts the Supplier controls.

1. Tools, skills and general know-how the Supplier had before this Agreement remain the Supplier's, provided they contain no Confidential Information.

# No Use for Own Benefit

1. The Supplier must not use anything learned or created through this engagement to compete with the Company or to profit outside it. In particular, during the Term and for 12 months after it ends, the Supplier will not:

a. use Confidential Information, Client data, audiences, campaign structures, creatives or performance insights for the Supplier's own business or for any other client;

a. use the Company's proprietary templates, playbooks, reporting formats, pricing models or processes to set up or run a competing service;

a. copy or reuse any Client's audiences, lookalikes, pixel data or customer lists in any other account;

a. accept commissions, rebates, kickbacks or referral fees from platforms, vendors or Clients in connection with the Services without disclosing them to the Company in writing; or

a. run ads for a direct competitor of an assigned Client during the Term without the Company's prior written consent.

1. Nothing in this Clause stops the Supplier from using general advertising skills and experience that are publicly known or not specific to the Company or its Clients.

# Non-Solicitation and Non-Circumvention

1. During the Term and for 12 months after it ends, the Supplier will not, directly or through anyone else:

a. solicit, approach or accept work from any Client the Supplier worked on or learned about through the Company, for services the same as or similar to the Company's;

a. encourage any Client to reduce or end its business with the Company; or

a. solicit or hire any Company employee or contractor the Supplier worked with.

1. If a Client contacts the Supplier directly about work, the Supplier will refer the Client back to the Company and inform the Company promptly.

1. If the Supplier breaches Clause 9.1, the Supplier will pay the Company, as a genuine pre-estimate of its loss, a sum equal to 6 months of the fees that Client paid the Company, without limiting the Company's other remedies.

1. The parties agree these restrictions are reasonable to protect the Company's client relationships and Confidential Information.

# Termination

1. Either party may end this Agreement by giving 30 days' written notice.

1. The Company may end this Agreement immediately by written notice if the Supplier breaches Clauses 6, 7, 8 or 9, acts dishonestly, or causes an Ad Account to be suspended through negligence or a policy breach.

1. On termination the Supplier will, within 3 working days: hand over all Work Product, reports and campaign notes; remove their own access from all Ad Accounts; and return or delete Confidential Information under Clause 6.7.

1. The Company will pay fees properly earned up to the termination date. Clause 3.6 survives until any amount due under it has been paid in full. Clauses 6, 7, 8, 9, 11 and 13 also survive termination.

# Independent Contractor, Liability and Indemnity

1. The Supplier is an independent contractor, not an employee, partner or agent of the Company, and is not entitled to employee benefits. The Supplier decides its own working hours, methods and tools, and may take on other work, subject to Clauses 8 and 9.

1. The Supplier will indemnify the Company against losses, claims and costs caused by the Supplier's breach of this Agreement, breach of platform policies, negligence or misuse of Confidential Information.

1. The Company is not liable for any indirect or consequential loss. The Company's total liability under this Agreement is limited to the fees paid to the Supplier in the 3 months before the claim.

# General

1. The Supplier may not assign or subcontract this Agreement without the Company's written consent.

1. This Agreement is the entire agreement between the parties on its subject. Changes are valid only in writing signed by both parties.

1. If any clause is found unenforceable, it will be read down to the extent needed and the rest of the Agreement continues in force.

1. Notices must be in writing and sent to the addresses or emails stated in Clause 1 (for the Company) and Schedule A (for the Supplier).

1. This Agreement may be signed electronically and in counterparts, in line with the Electronic Commerce Act 2006. An electronic signature has the same effect as a handwritten one, and the counterparts together form one agreement.

# Governing Law

This Agreement is governed by the laws of Malaysia.
$sca$, true, 59, $sch${
  "platforms": "Meta",
  "tasks": "Campaign setup, audience building, ad copy, A/B testing, budget pacing, daily monitoring, optimisation",
  "reporting": "Weekly snapshots to the Company and monthly reporting to the Company's clients",
  "response": "Within 4 working hours on working days",
  "spend_limit": "Changes above 40% per day need written approval",
  "tolerance": "Actual monthly spend within ±10% of the approved budget",
  "notes": "The Company may add, remove or change an account or its Approved Budget by sharing a new copy of this Schedule B, stating the account and the date the change takes effect.\n\nA blank End date means the account is ongoing.\n\nAd spend per month is the amount spent shown in the ad account. It excludes all relevant taxes."
}$sch$::jsonb
   where not exists (select 1 from public.doc_types t where t.id = 'supplier_sca')
  returning id
)
update public.doc_types set active = false
 where id = 'supplier_letter' and exists (select 1 from made);

/* What an agreement must hold before it is issued. */
create or replace function public.sca_complete(p_body jsonb)
returns boolean
language sql immutable set search_path = public as $$
  select coalesce(btrim(p_body #>> '{agreement,part1,legal_name}'), '') <> ''
     and coalesce(p_body #>> '{agreement,part1,start}', '') ~ '^\d{4}-\d{2}-\d{2}$'
     and coalesce(btrim(p_body #>> '{agreement,part2,fee}'), '') <> ''
     and case when jsonb_typeof(p_body #> '{agreement,accounts}') = 'array'
              then jsonb_array_length(p_body #> '{agreement,accounts}') between 1 and 60 else false end
$$;
revoke all on function public.sca_complete(jsonb) from public, anon, authenticated;

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

-- END OF SUPPLIER SERVICE AGREEMENT ------------------------------------------
select public.functions_tidy();
