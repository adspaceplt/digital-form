-- ===========================================================================
-- GUIDES AND METHOD WORDING (2026-11-28)
-- ===========================================================================
-- WHY: restructure release 16 (docs/MAP.md §G; DESIGN.md §7, layer 3;
-- MAP-INVENTORY D.4 #40, #42, #43). The first-visit guides (js/admin.js
-- GUIDES), the performance review's categories, paths and print lines
-- (js/perf.js) and the ad report's reading notes (js/smreport.js) were
-- literals in code: a change of words needed a deploy, and an install
-- inherited this agency's. They move into the template store word for word;
-- nothing is rewritten. The pages keep what is mechanism: a guide's steps'
-- places on the screen, a category's key and its maximum, where each note
-- prints.
-- WHAT IT CHANGES
--   * `template_fields`: three kinds and their fields: `guide` (the verify
--     address), `performance` (none), `ad-report` (the link domain);
--     `template_fields_all` lists them. Agency values are placeholders,
--     filled on the page from the agency profile, never typed in the seed.
--   * Seed: 63 templates, version 1, live from 2026-01-01, each only where
--     its key and language hold no version, so a run again adds nothing and
--     a later version is never touched. A guide is one template, its name
--     the subject and a step a paragraph, in the order of its places on the
--     page; a category, a path and a print line one each; an ad report note
--     one each, in English and, where the PDF's Chinese table held it, 中文.
--     The words are those the three scripts printed, already in the public
--     repository.
--   * `wording_read(p_set, p_lang)`: every template of one set (`guide`,
--     `performance`, `ad-report`) in force on the Malaysian day, the
--     language asked for where one is live, else English: { key: { subject,
--     body, version, lang } }. A colleague reads the three; a client signed
--     in to its portal reads `ad-report` alone (the portal draws the
--     report's PDF); anyone else is refused.
-- ORDER: this file, then the pages (js/tpl.js `ADspaceTpl.set`, js/admin.js,
-- js/perf.js, js/smreport.js; admin/ and client/ loading js/tpl.js). An open
-- tab keeps its own words. A page loaded before this file offers no guide,
-- and its performance views and ad report PDF say they cannot be loaded,
-- never drawn short of a word.
-- ROLLBACK: the pages first (revert the four scripts and the two pages),
-- then run template_fields and template_fields_all from their last
-- definitions before this band; drop function public.wording_read(text,
-- text); the seeded rows are live and kept by templates_guard (a rollback
-- that must take them out disables the trigger for that statement). Safe to
-- run twice.

-- GUIDES AND METHOD WORDING ---------------------------------------------------

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
    when 'guide' then array['verify url']
    when 'performance' then array[]::text[]
    when 'ad-report' then array['link domain']
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
    'guide', to_jsonb(public.template_fields('guide')),
    'performance', to_jsonb(public.template_fields('performance')),
    'ad-report', to_jsonb(public.template_fields('ad-report'))) end $$;
revoke all on function public.template_fields_all() from public, anon;
grant execute on function public.template_fields_all() to authenticated;

/* The seed: the words main's scripts printed, a key and language at a time,
   only where that key and language hold no version yet. */
insert into public.templates (key, kind, language, version, subject, body, status, effective_from, sample)
select x.key, x.kind, x.language, 1, x.subject, x.body, 'live', date '2026-01-01', false
  from (values
    ('guide.analytics', 'guide', 'en', $w$Analytics$w$,
     $w$Each tab covers one subject, showing the charts your access allows.

Every figure covers the period chosen here and compares it with the period of the same length before it.

The largest changes against the previous period, calculated from the figures.$w$),
    ('guide.overview', 'guide', 'en', $w$Dashboard$w$,
     $w$Everything that needs your action today, late items first. Select an item to open it.

Ask the Assistant about your clients and work.

Me is your own work. Team holds the figures of the sections you manage.

Every figure covers the period chosen here.

The main figures, each compared with the previous period.

Everything that needs attention, late items first. Choose a tab above to show one section. Select an item to open it.$w$),
    ('guide.work', 'guide', 'en', $w$My Work$w$,
     $w$My Work shows the same tasks as a list, a board, a calendar or months.

Add a task here, or a client's posts for the month.

Move a task to its next stage here. The colleague who takes it next is notified.$w$),
    ('guide.clients', 'guide', 'en', $w$Clients$w$,
     $w$Add a lead on the day it comes in. Billing, brand and services are added as the deal progresses.

Open a client to see its contacts, services, documents, calls and visits.

Filter the list by stage or person in charge.$w$),
    ('guide.whatsapp', 'guide', 'en', $w$Messages$w$,
     $w$WhatsApp and Email each list what the portal has sent, month by month.

New message sends a Meta-approved template to a client contact or a creator.

Every message the portal has sent, with its status: Sent, Delivered, Read, or Failed with the reason.

Messages the portal sends automatically: those waiting or sending, and those not sent or not confirmed in the last seven days.$w$),
    ('guide.review', 'guide', 'en', $w$Content Review$w$,
     $w$Open a client to prepare a content set and send it for approval.

Find a client by name.$w$),
    ('guide.scripts', 'guide', 'en', $w$Video Scripts$w$,
     $w$New script adds a video to a client's content month, numbered by month (for example 2610VS01).

Open a script to write it, publish it to the client's link and record each clip number on the shoot day.$w$),
    ('guide.campaigns', 'guide', 'en', $w$Creators$w$,
     $w$New campaign creates a campaign for a client, with creators from the Creators List.

Campaigns, and the Creators List with every creator and their rates.

Open a campaign to book creators, check drafts and release them to the client.$w$),
    ('guide.register', 'guide', 'en', $w$Documents$w$,
     $w$Issue a letter on the letterhead. Its reference number is assigned automatically.

Press a reference to copy it. Anyone can check it at {verify url}.$w$),
    ('guide.suppliers', 'guide', 'en', $w$Suppliers$w$,
     $w$New supplier creates a Supplier ID and a link. The supplier fills in their own details.

Open a supplier to review the details they submitted, approve them and issue documents.$w$),
    ('guide.team.hiring', 'guide', 'en', $w$Hiring$w$,
     $w$Add candidate saves their details and CV, and creates their own page.

Open a candidate to add the colleagues who decide or interview, and to copy their page's link.$w$),
    ('guide.reports', 'guide', 'en', $w$Reports$w$,
     $w$New report creates an Accounts Report or an Advertising Report for an active client.

A report moves from Drafts to In review, Confirmed and Published. The client can read it once it is published.

Select reports to download several, or mark them as sent.$w$),
    ('guide.links', 'guide', 'en', $w$Short Links$w$,
     $w$Add link creates a short address and its QR code.

Live, Namecards and Paused, followed by the addresses the portal creates for clients and creators. Every address in use is listed, so none is used twice.$w$),
    ('guide.services', 'guide', 'en', $w$Services$w$,
     $w$Add a service or an add-on to the Rate Card.

Each Rate Card service is the starting point for a client's service line, which can then be edited.$w$),
    ('guide.team', 'guide', 'en', $w$Team$w$,
     $w$Members, Hiring, the user groups that control what each member can open, Performance and Health.

Add member gives a colleague their sign-in and digital namecard.$w$),
    ('guide.handbook', 'guide', 'en', $w$Handbook$w$,
     $w$Add a file or a link. A new version never replaces the old one.

Open a file. Earlier versions are in its ⋯ menu.$w$),
    ('guide.mine', 'guide', 'en', $w$My records$w$,
     $w$Your reviews, recognitions, letters and health check-ins. Only you can see them here.$w$),
    ('guide.settings', 'guide', 'en', $w$Settings$w$,
     $w$Settings are grouped by what they change. You see only the settings you have access to.

Edit and Open show the setting in full. A business figure applies from the date you enter.

A switch takes effect for everyone as soon as you press it. If the change is refused, it switches back.$w$),
    ('guide.whatsapp.templates', 'guide', 'en', $w$WhatsApp templates$w$,
     $w$Edit selects the Meta-approved template for this purpose from the list Meta provides.

The switch turns a purpose on or off. When it is off, nothing is sent and its button is removed from the records.$w$),
    ('guide.whatsapp.compose', 'guide', 'en', $w$New message$w$,
     $w$Choose a client contact or a creator. Their number is shown below. A contact with only a username cannot be messaged.

Choose a Meta-approved template. Its variables are filled in from the record and can be changed.

The preview shows the message as it will be sent. Send asks you to confirm the number and the category.$w$),
    ('guide.phone', 'guide', 'en', $w$Your sections$w$,
     $w$The bar holds the Dashboard and your sections. Press one to open it.

More opens the other sections, Settings, the Activity record and Arrange sections, where you choose the sections on this bar.

Your name opens My records and My namecard.$w$),
    ('guide.arrange', 'guide', 'en', $w$Arrange sections$w$,
     $w$Drag a section by its grip, or press the grip and move it with the arrow keys.

Turn on up to three sections for the tab bar at the bottom of your phone. Under Tab bar order, drag them and the Dashboard into any order.

Save applies the order on the web and on your phone, and the tab bar on your phone. Reset restores the standard order and tab bar.$w$),
    ('guide.mine.health', 'guide', 'en', $w$Health$w$,
     $w$A short check-in each month, or each week while your planned work is near your weekly capacity. Management reads your answers by name to support you. They are never used in a performance review.

I agree starts the check-ins. Withdraw stops them at any time.$w$),
    ('guide.mine.checkin', 'guide', 'en', $w$Health$w$,
     $w$Check in with your mood and workload. You can change your answers until the period ends.

Ask a colleague for a talk. They are told who asked, but never see your note.

Withdraw stops the check-ins and removes your answers from Team: Health.$w$),
    ('guide.team.health', 'guide', 'en', $w$Health$w$,
     $w$This period's average mood, check-ins, weekly check-ins and open talks.

Average mood by week, over 12 weeks.

Press a colleague to see their check-ins and this week's planned work. Answers are shown only while their agreement is in place.$w$),
    ('guide.reports.entry', 'guide', 'en', $w$Report$w$,
     $w$Four steps, each with a summary of what it contains. Press a step to open it.

Preview PDF shows the report as the client will read it, marked as a draft until it is confirmed.

Next opens the following step.$w$),
    ('guide.reports.text', 'guide', 'en', $w$Commentary$w$,
     $w$Write with AI drafts the commentary from the figures and your notes. Read it before submitting.

Notes for the draft: reasons, changes, the goal and next month's budget. They are kept in this browser only.

The language Write with AI drafts in.$w$),
    ('guide.reports.review', 'guide', 'en', $w$Review and publish$w$,
     $w$Confirm marks the report as reviewed. A manager then publishes it.

Publish shows the report on the client's link and saves its PDF as published.

Send back returns the report to its writer as a draft for corrections.$w$),
    ('guide.campaigns.record', 'guide', 'en', $w$Campaign$w$,
     $w$Each tab holds one part of the campaign: its creators, schedule, the client's selection and its finance.

Copy the client's link to send it. The client chooses their creators on it.

Publish shows the campaign's creators to the client on their link.$w$),
    ('guide.campaigns.roster', 'guide', 'en', $w$Creators List$w$,
     $w$Add creator saves a creator with their profiles, rate and contact details.

Creators are grouped by fee. Inactive creators are in a group of their own.

Open a creator to see their bookings, payments and payment details.$w$),
    ('guide.campaigns.payments', 'guide', 'en', $w$Payments$w$,
     $w$Payments are grouped by stage: Details to review, Ready to bill, Draft in Bukku, Awaiting payment and Paid.

The button on each row takes its next step: Review, Create bill, Link to Bukku or Open in Bukku.

Read from Bukku updates each bill's status once it is posted or paid in Bukku.$w$),
    ('guide.whatsapp.email', 'guide', 'en', $w$Email$w$,
     $w$Every email the portal has sent, with its status. Press one to read it in full.

Emails are listed by month. Type and Status narrow the list.

New email sends an email to a client, a supplier or a creator from a template.$w$),
    ('guide.overview.team', 'guide', 'en', $w$Team$w$,
     $w$Open work at each stage, with the colleagues assigned to it.

Each colleague's open, late and delivered work. Press a colleague to open their work.

Each client's posts, report and meeting this month. Press a client to open their month in My Work.$w$),
    ('guide.analytics.tab', 'guide', 'en', $w$Charts$w$,
     $w$Each tile shows a figure and its change from the previous period.

Better, Worse, Steady or Above alert states how the figure moved.

Monthly review and Reference hold the charts read less often. Press a heading to open it.

Write with AI analyses the figures on this tab: their health, risks, what is working and recommended actions.$w$),
    ('guide.reports.check', 'guide', 'en', $w$Check and submit$w$,
     $w$Report audit checks the figures against Meta and the commentary against the figures.

Submit asks who reviews the report, then sends it to them.$w$),
    ('performance.category.output', 'performance', 'en', $w$$w$,
     $w$Role output quality$w$),
    ('performance.category.accuracy', 'performance', 'en', $w$$w$,
     $w$Accuracy and compliance$w$),
    ('performance.category.delivery', 'performance', 'en', $w$$w$,
     $w$Delivery and reliability$w$),
    ('performance.category.client', 'performance', 'en', $w$$w$,
     $w$Client ownership$w$),
    ('performance.category.comms', 'performance', 'en', $w$$w$,
     $w$Communication and collaboration$w$),
    ('performance.category.initiative', 'performance', 'en', $w$$w$,
     $w$Initiative and improvement$w$),
    ('performance.path.development', 'performance', 'en', $w$Development path$w$,
     $w$A work or skills shortfall with no client harmed. Repeated months move through a documented, staged improvement process.$w$),
    ('performance.path.accountability', 'performance', 'en', $w$Recovery path$w$,
     $w$A serious issue this month, or the month fell well short. This month's bonus, commission eligibility, trip and reward-linked benefits do not apply.$w$),
    ('performance.print.issue-once', 'performance', 'en', $w$$w$,
     $w$Each issue is recorded once, under the area it affected most. Putting it right adds no points back, but can keep it from going further; the issue stays on the record.$w$),
    ('performance.print.no-path', 'performance', 'en', $w$$w$,
     $w$No development or recovery path applies this month.$w$),
    ('performance.print.path-limits', 'performance', 'en', $w$$w$,
     $w$A month with no issue resets the recovery path. Consequences are limited to privileges, training and discretionary rewards, and never affect salary.$w$),
    ('ad-report.performance.lead', 'ad-report', 'en', $w$$w$,
     $w$Each objective is ranked by cost per result, followed by each creative and its results across objectives.$w$),
    ('ad-report.performance.lead', 'ad-report', 'zh', $w$$w$,
     $w$各广告目标按单次成效费用排序，随后呈现每个创意在各目标下的成效。$w$),
    ('ad-report.read', 'ad-report', 'en', $w$How to read this$w$,
     $w$Cost per result is the cost of obtaining one lead, click or action; where the result is reach, it is the cost per 1,000 people reached, shown as / 1,000. It should be compared only between ads with the same objective, which is why each objective is ranked separately.

Each ad is assessed only against the result its objective was set to achieve. A leads ad that also started conversations is assessed by its cost per lead; those conversations are incidental, and the budget was not spent on them.

Reach is the number of people who saw an ad; impressions are the number of times it was shown. Frequency is impressions divided by reach.

A creative that ran under two objectives is shown on one line for each, so the lines can be compared to see which objective it served best.$w$),
    ('ad-report.read', 'ad-report', 'zh', $w$阅读说明$w$,
     $w$单次成效费用指获得一次潜在客户、点击或行动所需的费用。此数据只宜在同一广告目标的广告之间比较，因此每个目标均单独排名。

每则广告只按其投放目标所设定的成效计算费用。例如潜在客户广告即使同时带来少量对话，仍以单次潜在客户费用评估；这些对话属附带成效，预算并非为其投放。

覆盖人数指看过广告的人数；展示次数指广告获得展示的总次数。频次即展示次数除以覆盖人数。

同一创意若在两个广告目标下投放，将各列一行，便于比较该创意最能达成哪一个目标。$w$),
    ('ad-report.variations', 'ad-report', 'en', $w$$w$,
     $w$Each row combines every variation of one creative. Where a row shows a high cost per result or few results, its variations were tested together and did not perform as intended; the next round builds on the creatives that performed.$w$),
    ('ad-report.video', 'ad-report', 'en', $w$How to read the video figures$w$,
     $w$Hook rate is the proportion of viewers who continued watching after the ad appeared. The opening seconds determine whether a viewer stops or scrolls past: a high hook rate indicates an effective opening, and a low one shows where the next creative should be strengthened.

Hold rate is the proportion of viewers who continued watching after the opening, showing whether the message holds attention to the end. A high hold rate indicates engaging content; a low one shows where viewers stop watching.$w$),
    ('ad-report.video', 'ad-report', 'zh', $w$视频数据说明$w$,
     $w$吸睛率指广告出现后继续观看的人数比例。开场几秒决定观众停留还是滑过；吸睛率高代表开场奏效，偏低则说明下一则创意的开场可再加强。

持续观看率指被开场吸引后继续观看的人数比例，反映内容能否从头到尾留住观众。持续观看率高代表内容奏效；偏低则显示观众开始流失的位置。$w$),
    ('ad-report.glossary', 'ad-report', 'en', $w$$w$,
     $w$Every ad term is explained at {link domain}/fb-ad-terms.$w$),
    ('ad-report.glossary', 'ad-report', 'zh', $w$$w$,
     $w$各项广告术语的说明，请参阅 {link domain}/fb-ad-terms。$w$),
    ('ad-report.tax.sg', 'ad-report', 'en', $w$$w$,
     $w$Amount spent is the total spent on ads, excluding the 5% DCC and 9% GST, which are charged separately.$w$),
    ('ad-report.tax.sg', 'ad-report', 'zh', $w$$w$,
     $w$广告花费为投放于广告的全部金额，不包括另行收取的5%数字服务费（DCC）及9%消费税（GST）。$w$),
    ('ad-report.tax.my', 'ad-report', 'en', $w$$w$,
     $w$Amount spent is the total spent on ads, excluding the 10% WHT and 8% SST, which are charged separately.$w$),
    ('ad-report.tax.my', 'ad-report', 'zh', $w$$w$,
     $w$广告花费为投放于广告的全部金额，不包括另行收取的10%预扣税（WHT）及8%销售与服务税（SST）。$w$),
    ('ad-report.tax.both', 'ad-report', 'en', $w$$w$,
     $w$Amount spent is the total spent on ads, excluding the 10% WHT and 8% SST on a Malaysian ad account and the 5% DCC and 9% GST on a Singapore ad account, which are charged separately.$w$),
    ('ad-report.tax.both', 'ad-report', 'zh', $w$$w$,
     $w$广告花费为投放于广告的全部金额。马来西亚广告账户不包括另行收取的10%预扣税（WHT）及8%销售与服务税（SST）；新加坡广告账户不包括另行收取的5%数字服务费（DCC）及9%消费税（GST）。$w$),
    ('ad-report.roas', 'ad-report', 'en', $w$$w$,
     $w$Purchase value and ROAS are as reported by Meta, based on purchases its tracking attributes to these ads, and may differ from the sales your own records show.$w$),
    ('ad-report.not-ranked', 'ad-report', 'en', $w$$w$,
     $w$Not ranked: this ad recorded minimal delivery during the period, so its cost per result is not comparable.$w$)
  ) as x (key, kind, language, subject, body)
 where not exists (select 1 from public.templates t where t.key = x.key and t.language = x.language);

/* One set's words in force today (Malaysia), for the page that prints them:
   the guides and the performance words to a colleague, the ad report's
   notes to a colleague and to a client signed in to its portal. */
create or replace function public.wording_read(p_set text, p_lang text default 'en')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_at   date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_lang text := case when p_lang = 'zh' then 'zh' else 'en' end;
begin
  if p_set is null or p_set not in ('guide', 'performance', 'ad-report') then
    return jsonb_build_object('error', 'bad-set');
  end if;
  if not (public.is_team() or (p_set = 'ad-report' and exists (select 1 from public.portal_clients()))) then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'set', p_set, 'lang', v_lang, 'at', v_at, 'words', coalesce((
    select jsonb_object_agg(w.key, jsonb_build_object('subject', w.subject, 'body', w.body, 'version', w.version, 'lang', w.language))
      from (select distinct on (x.key) x.key, x.subject, x.body, x.version, x.language
              from public.templates x
             where x.kind = p_set and x.status = 'live' and x.effective_from <= v_at
               and x.language in ('en', v_lang)
             order by x.key, (x.language = v_lang) desc, x.effective_from desc, x.version desc) w), '{}'::jsonb));
end $$;
revoke all on function public.wording_read(text, text) from public, anon;
grant execute on function public.wording_read(text, text) to authenticated;

-- END OF GUIDES AND METHOD WORDING --------------------------------------------

select public.functions_tidy();
