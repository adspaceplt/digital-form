-- ===========================================================================
-- QUOTATION TERMS IN THE TEMPLATE STORE (2026-11-28)
-- ===========================================================================
-- WHY: restructure release 13 (docs/MAP.md §G; DESIGN.md §7, layer 3). The
-- quotation's terms were typed in js/quotepdf.js (the cover's fallback,
-- TERMS in both layouts, the lead and the acceptance line) and in
-- js/quote.js (how ad spend is paid, the notes under the quotation, the
-- signing consent, English and 中文): a change of terms needed a deploy
-- and an install inherited the agency's (MAP-INVENTORY §D.1 #3, #4, #6).
-- They move into the store word for word; nothing is rewritten.
-- WHAT IT CHANGES
--   * `template_fields('quotation-terms')`: the fields a quotation's terms
--     are filled with (agency, document reference, document date, prepared
--     for, days, days in words, valid until, amount, items, prepay percent,
--     credit fee percent, service terms link, rate card version, minimum
--     term, minimum term in words, currency, ad budget, credit fee, company
--     name). Every other kind as it stood.
--   * `template_texts(keys, lang, at)`: the live versions in force on a
--     Malaysian day (a quotation's own issue day, so a copy redrawn later
--     reads as issued), 中文 falling back to English, of the public kinds
--     alone (`quotation-terms`: printed on every quotation). Refused
--     `not-found` naming the first key with none, never answered short.
--     The quotation page is signed out: granted to anon and joins
--     `open_to_anon` (FUNCTION HYGIENE, run that file first).
--   * Seed: 57 versions (31 keys of the PDF in English, 13 of the page in
--     English and 中文), version 1, live from 1970-01-01 (every quotation already issued reads
--     them as it printed them), each only where
--     its key and language hold no version. The wording is the code's as it
--     stood in the public repository.
-- ORDER: the hygiene file (2026-10-07-function-hygiene.sql), this file,
-- then the pages. An open tab keeps its typed words until it reloads; a
-- page that meets no `template_texts` (this file not yet run) refuses the
-- PDF and the quotation page reads Unable to load, never terms left out.
-- ROLLBACK: deploy the pages before this release first; then
-- `drop function public.template_texts(text[], text, date);` restate
-- `template_fields` from 2026-11-22-interview-time-changed-email.sql; the
-- seeded versions are live and kept by `templates_guard` (harmless: no
-- page before this release reads them). Safe to run twice.

-- QUOTATION TERMS IN THE TEMPLATE STORE ---------------------------------------

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
    when 'quotation-terms' then array['agency', 'document reference', 'document date', 'prepared for', 'days', 'days in words',
      'valid until', 'amount', 'items', 'prepay percent', 'credit fee percent', 'service terms link', 'rate card version',
      'minimum term', 'minimum term in words', 'currency', 'ad budget', 'credit fee', 'company name']
  end $$;
revoke all on function public.template_fields(text) from public, anon, authenticated;

/* The wording of the public kinds in force on a day, by key: what a
   signed-out page prints (a quotation's terms). Every key answered or
   none. */
create or replace function public.template_texts(p_keys text[], p_lang text default 'en', p_at date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_at date := coalesce(p_at, (now() at time zone 'Asia/Kuala_Lumpur')::date);
  v_key text;
  v_t public.templates;
  v_fb boolean;
  v_out jsonb := '{}'::jsonb;
begin
  if p_lang is null or p_lang not in ('en', 'zh') then return jsonb_build_object('error', 'bad-lang'); end if;
  if p_keys is null or cardinality(p_keys) = 0 or cardinality(p_keys) > 80 then return jsonb_build_object('error', 'bad-keys'); end if;
  foreach v_key in array p_keys loop
    v_t := public.template_in_force(v_key, p_lang, v_at);
    v_fb := false;
    if v_t.id is null and p_lang <> 'en' then
      v_t := public.template_in_force(v_key, 'en', v_at);
      v_fb := v_t.id is not null;
    end if;
    if v_t.id is null or v_t.kind <> 'quotation-terms' then
      return jsonb_build_object('error', 'not-found', 'key', v_key);
    end if;
    v_out := v_out || jsonb_build_object(v_key, jsonb_build_object('subject', v_t.subject, 'body', v_t.body,
      'version', v_t.version, 'lang', v_t.language, 'fallback', v_fb, 'effective_from', v_t.effective_from));
  end loop;
  return jsonb_build_object('ok', true, 'at', v_at, 'texts', v_out);
end $$;
revoke all on function public.template_texts(text[], text, date) from public;
grant execute on function public.template_texts(text[], text, date) to anon, authenticated;

/* The quotation's terms as js/quotepdf.js and js/quote.js typed them, into
   a key and language holding no version alone: a first run, never a
   running list. */
insert into public.templates (key, kind, language, version, subject, body, status, effective_from)
select x.key, 'quotation-terms', x.language, 1, x.subject, x.body, 'live', date '1970-01-01'
  from (values
    ('quotation.cover', 'en', 'QUOTATION FOR DIGITAL MARKETING SERVICES',
     'We are pleased to submit our quotation for your consideration. It has been prepared based on the scope and requirements discussed, with full details set out in the following pages.' || chr(10) || '' || chr(10) || 'Should you need any clarification or additional information, please do not hesitate to contact us. We would be pleased to provide further materials to support your evaluation.'),
    ('quotation.lead', 'en', '',
     'Quotation {document reference}, dated {document date}, sets out the services and fees proposed for {prepared for}.'),
    ('quotation.terms.validity', 'en', '',
     'This Quotation is valid for {days in words} ({days}) days from its date of issue and shall lapse on {valid until} unless accepted before that date.'),
    ('quotation.terms.fees', 'en', '',
     'The total Monthly Service Fee payable over the minimum term is {amount}.'),
    ('quotation.terms.fees-sst', 'en', '',
     'The total Monthly Service Fee payable over the minimum term is {amount}, inclusive of SST.'),
    ('quotation.terms.fees-own', 'en', '',
     'The total Monthly Service Fee payable over the period stated for each service is {amount}.'),
    ('quotation.terms.fees-own-sst', 'en', '',
     'The total Monthly Service Fee payable over the period stated for each service is {amount}, inclusive of SST.'),
    ('quotation.terms.ads', 'en', '',
     'The Advertising Budget shall be paid to the advertising platforms on the Client''s behalf before the services commence. It includes any SST and withholding tax applicable to the advertising platforms'' charges.'),
    ('quotation.terms.ads-excluded', 'en', '',
     'The Advertising Budget is not included in this Quotation.'),
    ('quotation.terms.ad-ways', 'en', '',
     'The Advertising Budget is paid either by the Client''s own credit card through the Client''s own ad account, or in advance to {agency} each month before the ads run. Each following month is requested when about {prepay percent}% of the current budget is spent. Where it is instead invoiced on the payment terms of this Quotation, an Agency Credit Term Fee of {credit fee percent}% of the Advertising Budget applies.'),
    ('quotation.terms.exclusions', 'en', '',
     'Additional footage, working files and raw footage are not included and shall be charged separately upon request.'),
    ('quotation.terms.on-request', 'en', '',
     '{items} shall be quoted separately upon request.'),
    ('quotation.terms.budget-above', 'en', '',
     'An advertising budget above the highest tier of the {agency} Rate Card'),
    ('quotation.terms.agreement', 'en', '',
     'This Quotation shall become binding upon its acceptance and signature by the Client on the Acceptance of Quotation page. This Quotation shall constitute the contract between the parties.'),
    ('quotation.terms.agreement-terms', 'en', '',
     'This Quotation shall become binding upon its acceptance and signature by the Client on the Acceptance of Quotation page. This Quotation, together with the {agency} Service Terms at {service terms link}, shall constitute the contract between the parties.'),
    ('quotation.terms.basis', 'en', '',
     'All rates are based on the {agency} Rate Card Version {rate card version}. E&OE.'),
    ('quotation.notes.validity', 'en', '',
     'This quotation is valid for {days in words} ({days}) days from its date of issue, until {valid until}.'),
    ('quotation.notes.includes', 'en', '',
     'The amount per month includes {items}.'),
    ('quotation.notes.includes-own', 'en', '',
     'The first month''s amount includes {items}.'),
    ('quotation.notes.once-items', 'en', '',
     'the one-time items'),
    ('quotation.notes.ad-ways', 'en', '',
     'It is paid by the client''s own credit card through the client''s own ad account, or prepaid to {agency} each month before the ads run. Each following month is requested when about {prepay percent}% of the current budget is spent. Where the advertising budget is invoiced on this quotation''s payment terms instead, an Agency Credit Term Fee of {credit fee percent}% of the advertising budget applies.'),
    ('quotation.notes.on-request', 'en', '',
     'The following are quoted on request: {items}.'),
    ('quotation.notes.budget-above', 'en', '',
     'an advertising budget above the highest tier of the {agency} Rate Card'),
    ('quotation.notes.commitment', 'en', '',
     'The total commitment for {minimum term in words} ({minimum term}) months is {amount}.'),
    ('quotation.notes.commitment-once', 'en', '',
     'The total commitment for {minimum term in words} ({minimum term}) months is {amount}, one-time items included.'),
    ('quotation.notes.commitment-own', 'en', '',
     'The total commitment over the months stated for each service is {amount}.'),
    ('quotation.notes.commitment-own-once', 'en', '',
     'The total commitment over the months stated for each service is {amount}, one-time items included.'),
    ('quotation.notes.binding', 'en', '',
     'This quotation becomes binding once accepted and signed on its acceptance page.'),
    ('quotation.notes.binding-terms', 'en', '',
     'This quotation becomes binding once accepted and signed on its acceptance page. Together with the {agency} Service Terms at {service terms link}, it forms the contract between the parties.'),
    ('quotation.notes.basis', 'en', '',
     'Rates are based on the {agency} Rate Card Version {rate card version}. E&OE.'),
    ('quotation.acceptance', 'en', '',
     'By signing below, the Client accepts Quotation {document reference}, dated {document date}, and agrees to be bound by the terms set out in this document.'),
    ('quote.ads.own.1', 'en', '',
     'Meta charges the ads directly to your own credit card.'),
    ('quote.ads.own.1', 'zh', '',
     'Meta 直接从您自己的信用卡扣除广告费用。'),
    ('quote.ads.own.2', 'en', '',
     'The account is linked to the {agency} Meta business portfolio, so {agency} runs and manages the campaigns.'),
    ('quote.ads.own.2', 'zh', '',
     '该账户将关联至 {agency} 的 Meta 商务资产组合，由 {agency} 投放并管理广告活动。'),
    ('quote.ads.pre.1', 'en', '',
     'The first month''s advertising budget is paid to {agency} before the ads start.'),
    ('quote.ads.pre.1', 'zh', '',
     '首月广告预算须于广告开始投放前支付予 {agency}。'),
    ('quote.ads.pre.2', 'en', '',
     'Each following month is requested when about {prepay percent}% of the current budget is spent.'),
    ('quote.ads.pre.2', 'zh', '',
     '当月预算消耗约{prepay percent}%时，{agency} 将请款下月预算。'),
    ('quote.ads.pre.3', 'en', '',
     'If payment is not received, the ads will be paused until payment is received.'),
    ('quote.ads.pre.3', 'zh', '',
     '如未收到款项，广告将暂停投放，直至收款为止。'),
    ('quote.ads.term', 'en', '',
     'Where the advertising budget is billed with the invoice on the quotation''s payment terms instead of prepaid, an Agency Credit Term Fee of {credit fee percent}% will be added to the advertising budget.'),
    ('quote.ads.term', 'zh', '',
     '如广告预算按报价单的付款期限随发票结算而非预付，将按广告预算另加收{credit fee percent}%的账期服务费（Agency Credit Term Fee）。'),
    ('quote.ads.example', 'en', '',
     'For example, a budget of {currency}' || chr(160) || '{ad budget} carries a fee of {currency}' || chr(160) || '{credit fee}.'),
    ('quote.ads.example', 'zh', '',
     '例如：广告预算 {currency}' || chr(160) || '{ad budget}，账期服务费为 {currency}' || chr(160) || '{credit fee}。'),
    ('quote.notes.ads', 'en', '',
     'The advertising budget is paid to the advertising platforms on the Client''s behalf and is payable before the service commences.'),
    ('quote.notes.ads', 'zh', '',
     '广告预算由 {agency} 代客户支付予广告平台，须于服务开始前支付。'),
    ('quote.notes.pay', 'en', '',
     'Payment is due within {days} days of the invoice date.'),
    ('quote.notes.pay', 'zh', '',
     '付款期限为发票日期起{days}天内。'),
    ('quote.notes.pay-approve', 'en', '',
     'Payment is due within {days} days of the invoice date, subject to {agency}''s approval.'),
    ('quote.notes.pay-approve', 'zh', '',
     '付款期限为发票日期起{days}天内，须经 {agency} 批准。'),
    ('quote.notes.managed', 'en', '',
     'The fees include the management of an advertising budget of up to {currency}' || chr(160) || '{ad budget} per month.'),
    ('quote.notes.managed', 'zh', '',
     '费用包括代为管理每月最高 {currency}' || chr(160) || '{ad budget} 的广告预算。'),
    ('quote.notes.basis', 'en', '',
     'Rates are based on the {agency} Rate Card v.{rate card version}.'),
    ('quote.notes.basis', 'zh', '',
     '价格依据 {agency} 价目表 v.{rate card version}。'),
    ('quote.sign.agree', 'en', '',
     'I am authorised to sign on behalf of {company name} and accept this quotation and the {agency} Service Terms.'),
    ('quote.sign.agree', 'zh', '',
     '本人获授权代表 {company name} 签署，并接受本报价及 {agency} 服务条款。')
  ) as x (key, language, subject, body)
 where not exists (select 1 from public.templates t where t.key = x.key and t.language = x.language);

-- END OF QUOTATION TERMS IN THE TEMPLATE STORE ---------------------------------

select public.functions_tidy();
