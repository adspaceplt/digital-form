-- ===========================================================================
-- HR WORDING (2026-11-28)
-- ===========================================================================
-- WHY: restructure release 14 (docs/MAP.md §G; DESIGN.md §7, layer 3). The
-- Employment Offer's and the Employment Contract's words (its clauses, the
-- offer's paragraphs, the candidate's declaration) were literals in
-- js/hrdocs.js: a change of terms needed a deploy, and an install inherited
-- this agency's. They move into the template store word for word; nothing
-- is rewritten. The page keeps the order of the clauses and which apply
-- (probation, an end date, a named place, the salary set, no statutory
-- contributions for an internship or part-time); every sentence is a
-- template.
-- WHAT IT CHANGES
--   * `template_fields`: the kind `hr-document` and its fields (the agency's
--     name, the position, the duties, the dates, the place, the probation,
--     the salary in figures and words, the days to reply);
--     `template_fields_all` lists it.
--   * Seed: 35 templates of kind `hr-document`, English, version 1, live
--     from 2026-01-01 (before the first document was sent, so every
--     document already sent reads the words it was drawn with): a clause a
--     template, its heading the subject, its paragraphs the body. Each goes
--     in only where its key holds no English version, so a run again adds
--     nothing and a later version is never touched. The words are those
--     js/hrdocs.js printed, already in the public repository.
--   * `hr_wording(p_at)`: every `hr-document` template in force on a day,
--     { key: { subject, body, version } }; closed to a page.
--   * `hiring_doc_wording(p_doc)`: the words in force on the day a document
--     went out (today for a draft), for the hiring part and the candidate's
--     Owners (`hiring_role`, as `hiring_doc_record`); the caller found by
--     `auth.uid()` through `hiring_role`.
--   * `careers_doc_json`: the candidate's document carries the same words
--     (`wording`), behind the code and the view token as before
--     (`careers_doc_open`, `careers_doc_read`, which return it unchanged).
-- ORDER: this file, then the pages (js/hrdocs.js, js/hiring.js,
-- js/careers.js, careers/ and admin/ loading js/tpl.js). An open tab keeps
-- its own words and draws as before: `wording` is an extra key it ignores.
-- A page before this file refuses to draw (This feature is not available
-- yet.), never a document short of a clause.
-- ROLLBACK: the pages first (revert js/hrdocs.js, js/hiring.js,
-- js/careers.js, careers/index.html, admin/index.html), then: run
-- careers_doc_json from HIRING OFFERS AND CONTRACTS, and template_fields
-- and template_fields_all from their last definitions before this band;
-- drop function public.hiring_doc_wording(uuid), public.hr_wording(date);
-- the seeded rows are live and kept by templates_guard (a later rollback
-- that must take them out disables the trigger for that statement). Safe
-- to run twice.

-- HR WORDING ------------------------------------------------------------------

create or replace function public.template_fields(p_kind text) returns text[]
language sql immutable set search_path = public as $$
  select case p_kind
    when 'supplier' then array['contact name', 'supplier name', 'supplier id', 'payment term', 'currency',
      'document title', 'document reference', 'document date', 'sender name']
    when 'client' then array['contact name', 'client name', 'company name', 'document title', 'document reference',
      'document date', 'valid until', 'sender name']
    when 'free' then array['contact name', 'company name', 'client name', 'supplier name', 'sender name']
    when 'invoice' then array['contact name', 'client', 'invoice no', 'count', 'total', 'sign off', 'invoices']
    when 'creator-details' then array['creator name', 'creator id', 'reference', 'payee', 'method', 'account ending',
      'review link', 'date', 'chinese date', 'changes']
    when 'creator-booking' then array['creator name', 'creator id', 'job reference', 'campaign', 'posted date', 'pay by',
      'payee', 'method', 'account ending', 'amount', 'bill number', 'review link']
    when 'meeting' then array['meeting', 'date', 'time', 'month', 'channel', 'link']
    when 'code' then array['name', 'code', 'minutes', 'purpose']
    when 'candidate' then array['candidate name', 'position', 'interview length', 'where', 'times', 'reply by', 'note',
      'time', 'previous time', 'new time', 'place', 'google meet notice', 'decision date', 'months', 'document', 'reference',
      'requested action', 'purpose', 'reason', 'document date', 'contact', 'sign-off', 'button']
    when 'feedback' then array['contact name', 'client name', 'link']
    when 'quote' then array['contact name', 'brand', 'reference', 'details', 'reply by', 'link']
    when 'hr-document' then array['agency name', 'position', 'duties', 'start', 'end', 'place', 'probation', 'salary',
      'salary in words', 'probation salary', 'probation salary in words', 'reply days']
  end $$;
revoke all on function public.template_fields(text) from public, anon, authenticated;

create or replace function public.template_fields_all() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_team() then jsonb_build_object(
    'supplier', to_jsonb(public.template_fields('supplier')),
    'client', to_jsonb(public.template_fields('client')),
    'free', to_jsonb(public.template_fields('free')),
    'invoice', to_jsonb(public.template_fields('invoice')),
    'creator-details', to_jsonb(public.template_fields('creator-details')),
    'creator-booking', to_jsonb(public.template_fields('creator-booking')),
    'meeting', to_jsonb(public.template_fields('meeting')),
    'code', to_jsonb(public.template_fields('code')),
    'candidate', to_jsonb(public.template_fields('candidate')),
    'feedback', to_jsonb(public.template_fields('feedback')),
    'quote', to_jsonb(public.template_fields('quote')),
    'hr-document', to_jsonb(public.template_fields('hr-document'))) end $$;
revoke all on function public.template_fields_all() from public, anon;
grant execute on function public.template_fields_all() to authenticated;

insert into public.templates (key, kind, language, version, subject, body, status, effective_from)
select x.key, 'hr-document', 'en', 1, x.subject, x.body, 'live', date '2026-01-01'
  from (values
    ('hr.declare', '',
     $hr$I have read and fully understood the contents of this offer letter and contract, and I accept all the terms and conditions herein.$hr$),
    ('hr.offer.lead', '',
     $hr${agency name} is pleased to offer you employment, subject to the terms and conditions of the employment contract.$hr$),
    ('hr.offer.reply', '',
     $hr$Kindly indicate your acceptance of this offer on your application page within {reply days} from the date of this letter. Please note that this is not an employment contract. A formal employment contract will be issued upon confirmation of acceptance.

Thank you.$hr$),
    ('hr.offer.accepted', '',
     $hr$I accept this Employment Offer.$hr$),
    ('hr.offer.pending', '',
     $hr$Acceptance is given on the application page.$hr$),
    ('hr.contract.lead', '',
     $hr$With reference to your recent application and interviews, {agency name} is pleased to offer you employment as {position} on the following terms and conditions:$hr$),
    ('hr.contract.close', '',
     $hr$If the above terms and conditions are agreeable to you, please sign this contract on your application page as soon as possible.

This letter, when signed by the applicant, will constitute a binding contract.$hr$),
    ('hr.contract.nature', 'NATURE OF WORKS',
     $hr${duties} In addition to normal duties, you may from time to time be required to render such other duties and services as may be necessary to meet the needs of the company’s business.$hr$),
    ('hr.contract.commencement', 'DATE OF COMMENCEMENT',
     $hr$Your employment shall commence on {start}.$hr$),
    ('hr.contract.ends', '',
     $hr$This contract ends on {end}.$hr$),
    ('hr.contract.hours', 'WORKING HOURS',
     $hr$Normal hours of work are 8 hours per day for five days a week and one hour lunch break. The nature of the work may require you to extend your service beyond the normal working hours in fulfilment of your duties and responsibilities.

You will not receive overtime payments in respect of any such working time unless provided for in law or you are eligible for overtime pay under the Company’s policies or guidelines.

The Company additionally reserves its right to change or substitute your scheduled work hours or workdays/off days to meet business needs. The Company reserves the right to exclude office holiday(s) to staff depending on their workload / work schedule and/or programs.$hr$),
    ('hr.contract.place', 'PLACE OF EMPLOYMENT',
     $hr$During the term of your employment, the Management reserves the right to transfer you to other location/position within the {agency name} group of companies, departments, and associated companies.$hr$),
    ('hr.contract.place-named', '',
     $hr$Your place of employment will be at {place} but this location may change from time to time.$hr$),
    ('hr.contract.place-office', '',
     $hr$Your place of employment will be at the {agency name} registered office but this location may change from time to time.$hr$),
    ('hr.contract.probation', 'PROBATIONARY PERIOD',
     $hr$You are required to serve a probationary period of {probation} during which time your employment may be terminated by either party giving the other FOURTEEN (14) days' notice of termination or equivalent to FOURTEEN (14) days' salary in lieu of the notice.

This probationary period may be extended on reasonable grounds.

You are not entitled to paid annual leave during probationary period. If you have been absent from work for more than 3 consecutive working days without prior approval or leave from the company and without valid reason, your employment with the Company will be deemed terminated.$hr$),
    ('hr.contract.probation-intern', '',
     $hr$(For “Internship” position, this is equivalent to your Internship Programme)$hr$),
    ('hr.contract.salary', 'SALARY, BONUS AND ADVANCE WAGES',
     $hr$No advance wages will be payable.

Payment of bonus and annual increment (if any) is based on your performance, the Company’s profit and the overall market/economic condition and is solely at the absolute discretion of the Company.$hr$),
    ('hr.contract.salary-probation', '',
     $hr$The basic salary at the commencement of the employment will be {probation salary in words} ({probation salary}) per month during probationary period; {salary in words} ({salary}) after completion of probation, payable on or before the 7th day after each calendar month.$hr$),
    ('hr.contract.salary-basic', '',
     $hr$The basic salary at the commencement of the employment will be {salary in words} ({salary}) per month, payable on or before the 7th day after each calendar month.$hr$),
    ('hr.contract.salary-unset', '',
     $hr$The basic salary is stated in the copy sent to you.$hr$),
    ('hr.contract.deductions', 'DEDUCTIONS',
     $hr$The Company reserves the right in its absolute discretion to deduct from your pay the Employee’s contribution to Employees’ Provident Fund (EPF), Social Security Organisation (SOCSO), Employment Insurance System (EIS) and any sums which you may owe to the Company including, but without limitation, any overpayments or losses suffered by the Company as a result of your negligence or breach of the Company’s rules or terms.$hr$),
    ('hr.contract.deductions-no-statutory', 'DEDUCTIONS',
     $hr$The Company reserves the right in its absolute discretion to deduct from your pay any sums which you may owe to the Company including, but without limitation, any overpayments or losses suffered by the Company as a result of your negligence or breach of the Company’s rules or terms.

The Employee shall not be entitled to contributions under the Employees Provident Fund Act 1991, the Employees’ Social Security Act 1969 or the Employment Insurance System Act 2017.$hr$),
    ('hr.contract.rest-days', 'REST DAYS AND PUBLIC HOLIDAYS',
     $hr$You are entitled to ELEVEN (11) paid public holidays that are gazetted under the Public Holidays Ordinance and five of which, namely the National Day, Malaysia Day, the Birthday of the Yang Di-Pertuan Agong, the Birthday of Sultan of Johor and Labour Day are compulsory.

The remainder will be determined by the Company. You may refer to the Company’s internal list of public holidays for more information.$hr$),
    ('hr.contract.annual-leave', 'ANNUAL LEAVE',
     $hr$Upon confirmation as permanent employee, you are entitled to paid annual leave of:

[a] eight (8) days for every twelve (12) months of continuous service with the Company for the first two (2) years with the Company;

[b] twelve (12) days for every twelve (12) months of continuous service with the Company from the third year onwards; and

[c] sixteen (16) days for every twelve (12) months of continuous service with the Company from the sixth year onwards.

If your employment commences or terminates part way through the year, your entitlement to the annual leave during the year will be assessed on a pro-rata basis and deductions from final salary due to your termination of employment will be made in respect of the annual leaves taken in excess of entitlement.

Annual leave must be taken at times convenient to the Company and at least seven (7) days’ advance notice to take annual leave must be given to the Company. No more than seven (7) days’ annual leave may be taken at any one time unless permission is given by the Company through the Employee’s Direct Manager.

Emergency Leave is strictly for emergency and limited to unavoidable circumstances such as family member in serious illness or funeral. Disciplinary action will be taken against those who do not have a valid reason for their emergency leave. You are required to inform your Direct Manager personally at the earliest time of the day.$hr$),
    ('hr.contract.sick-leave', 'SICK LEAVE',
     $hr$You shall, after examination by a registered medical practitioner duly appointed by the Company; or a medical officer of the General Hospital or Government Clinic, be entitled to paid sick leave of a maximum of fourteen (14) days in the aggregate in each calendar year.

The Company does not provide medical expenses reimbursements in respect of the hospitalization, dental treatments, specialists, and/or Chinese Physician treatments.$hr$),
    ('hr.contract.absence', 'NOTIFICATION OF SICKNESS OR OTHER ABSENCE',
     $hr$If you are unable to attend work for any reason and the absence has not previously been authorized by the Company, you must inform the Company of the fact of your absence and the full reasons for it on each working day of absence until the Company is provided with a medical certificate, failing which you shall be deemed as absent without reason and may be subject to disciplinary action.

If you are absent from work without any reason, that shall be considered taking unpaid leave without prejudice to the Company’s right to impose disciplinary action against you.$hr$),
    ('hr.contract.parental-leave', 'PATERNITY / MATERNITY LEAVE',
     $hr$You are entitled to a paid maternity leave of 98 days or paternity leave of 7 days consecutively including the public holidays and weekends/rest days during the period of childbirth in accordance with Section 37 and Section 60FA of the Employment Act.$hr$),
    ('hr.contract.notice', 'NOTICE OF TERMINATION',
     $hr$If your employment continues after the end of the probationary period, your employment with the Company may be terminated by giving the Company at least TWO (2) months’ notice or equivalent of TWO (2) months’ salary in lieu of the notice.$hr$),
    ('hr.contract.breach', 'BREACH AND TERMINATION',
     $hr$This contract is breached and terminated when you are found guilty of misconduct, whether in the course of your duties or not, inconsistent with the fulfilment of the express or implied conditions of this contract, including but not limited to the following:

[a] For dishonesty particularly the misappropriation of the Company’s assets of any kind;

[b] For stealing and/or taking goods without authorization of the Company;

[c] Indecent and immoral acts during working hours;

[d] Guilty of any criminal offences;

[e] For wilful disobedience to lawful orders and instructions given by the Company and or insubordination;

[f] For lack of skill which you have expressly or impliedly warrant yourself to possess;

[g] For absence from work without leave from the Company or absence without any reasonable excuse.$hr$),
    ('hr.contract.conflict', 'CONFLICT OF INTEREST',
     $hr$You must devote the whole of your time, attention and abilities during the hours of work for the Company to your duties for the Company. You may not, under any circumstances, whether directly or indirectly undertake any other duties, of whatever kind during the hours of work for the Company.

You may not without the knowledge and prior written consent of the Company engage, whether directly or indirectly, in any business or employment which could or might reasonably be considered by others to impair your ability to act at all times in the best interests of the Company.

You must not own shares in a non-listed competitor.$hr$),
    ('hr.contract.confidentiality', 'CONFIDENTIALITY',
     $hr$You must not at any time during or after your employment, in any fashion, form, or manner, either directly or indirectly divulge, disclose, or communicate to any person, firm or corporation in any manner whatsoever any information of any kind, nature or description concerning any matters affecting or relating to the business of the Company or any information concerning the business of the Company, its manner of operation, or its plans, processes, or other facts of any kind, nature, or description without regard to whether any or all of the foregoing matters would be deemed confidential, material, or important.

The parties hereby stipulate that as between them, the foregoing matters are important, material, and confidential and gravely affect the effectiveness and successful conduct of the business of the Company, and its goodwill, and that any breach of the terms of this section is a material breach of this contract.$hr$),
    ('hr.contract.non-compete', 'NON-COMPETE CLAUSE',
     $hr$You agree that, during your employment with the Company and for a period of two (2) years following the termination of your employment, regardless of the reason for termination, you shall not, directly or indirectly, within Malaysia:

[a] Engage in or render services to any business in direct competition with the Company;

[b] Solicit, divert, or appropriate, or attempt to solicit, divert, or appropriate, any customer or client of the Company with whom you had material contact during your employment;

[c] Solicit, encourage, or induce any employee, consultant, or contractor of the Company to terminate or modify their relationship with the Company.

This restriction shall not prevent you from working for a non-competitive organization or engaging in activities not directly related to the business of the Company.$hr$),
    ('hr.contract.policies', 'COMPLIANCE WITH COMPANY POLICIES AND GUIDELINES',
     $hr$[a] Compliance with Company Policies

You agree to adhere and comply with all policies, guidelines, procedures, rules, and regulations established by the Company (collectively referred as the “Company Policies”), as may be updated or amended from time to time at the Company’s sole discretion.

[b] Duty to Stay Informed

It is your responsibility to familiarize yourself with the Company Policies and any subsequent updates or amendments. Failure to comply with the Company Policies may result in disciplinary action, up to and including termination of employment.

[c] Binding Nature

Compliance with the Company Policies is a condition of your continued employment. Any violation may constitute grounds for disciplinary measures, including but not limited to termination.$hr$),
    ('hr.contract.compensation', 'COMPENSATION',
     $hr$You shall be responsible to indemnify the Company for any loss or damages against the Company’s Property as a result of your wilful acts and/or negligence.$hr$),
    ('hr.contract.changes', 'CHANGES TO THE TERMS OF EMPLOYMENT',
     $hr$The Company reserves the right to make reasonable changes to any of the terms and conditions of employment and will notify you in writing of such changes at the earliest opportunity and, in any event, within one month after such changes have taken effect.

Such changes will be deemed to be accepted unless you notify the Company of any objection in writing before the expiry of the notice period.$hr$)
  ) as x (key, subject, body)
 where not exists (select 1 from public.templates t where t.key = x.key and t.language = 'en');

/* Every HR template in force on a day: { key: { subject, body, version } }. */
create or replace function public.hr_wording(p_at date)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(k.key, jsonb_build_object('subject', t.subject, 'body', t.body, 'version', t.version)), '{}'::jsonb)
    from (select distinct x.key from public.templates x
           where x.kind = 'hr-document' and x.language = 'en' and x.status = 'live') k
    cross join lateral public.template_in_force(k.key, 'en', coalesce(p_at, (now() at time zone 'Asia/Kuala_Lumpur')::date)) t
   where t.id is not null $$;
revoke all on function public.hr_wording(date) from public, anon, authenticated;

/* The words a document is drawn with: those in force on the day it went
   out, today's for a draft. The hiring part and the candidate's Owners. */
create or replace function public.hiring_doc_wording(p_doc uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.hiring_docs; v_role text; v_at date;
begin
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  v_at := (coalesce(d.sent_at, now()) at time zone 'Asia/Kuala_Lumpur')::date;
  return jsonb_build_object('ok', true, 'at', v_at, 'wording', public.hr_wording(v_at));
end $$;
revoke all on function public.hiring_doc_wording(uuid) from public, anon;
grant execute on function public.hiring_doc_wording(uuid) to authenticated;

create or replace function public.careers_doc_json(d public.hiring_docs)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object('ok', true, 'id', d.id, 'kind', d.kind, 'serial', d.serial,
    'state', case when d.state = 'sent' and d.reply_by <= now() then 'expired' else d.state end,
    'sent_at', d.sent_at, 'reply_by', d.reply_by, 'terms', d.terms, 'returned_note', case when d.state = 'sent' then d.returned_note end,
    'name', c.name, 'signed_at', d.signed_at, 'signed_name', d.signed->>'name',
    'signatory', jsonb_build_object('name', t.name, 'designation', t.designation),
    'pay', jsonb_build_object('basic', p.basic, 'probation', p.probation),
    'wording', public.hr_wording((coalesce(d.sent_at, now()) at time zone 'Asia/Kuala_Lumpur')::date)))
    from public.hiring_candidates c
    left join public.hiring_doc_pay p on p.doc_id = d.id
    left join public.team_members t on t.id = d.sent_by
   where c.id = d.candidate_id
$$;
revoke all on function public.careers_doc_json(public.hiring_docs) from public, anon, authenticated;

-- END OF HR WORDING -------------------------------------------------------------

select public.functions_tidy();
