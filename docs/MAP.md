# Portal map

What the portal holds, how its records link, where the agency's identity and wording live, and the order of the restructure. Read-only survey at `ca7f5d0` (2026-11-27). Detail tables for A, C and D are in `docs/MAP-INVENTORY.md`.

## The five layers

| Layer | One job | Today |
|---|---|---|
| 1. Identity | Every record linked by its uuid; names, codes and numbers are display only | 289 uuid FKs; **117 non-uuid links** and **89 uuid columns with no FK** (A.2) |
| 2. Agency | One profile read through one path | Split across `ADSPACE_ORG` / `ADSPACE_CONFIG` (`js/config.js`), `mail_senders`, `mail_boxes`, `id_formats`; **1,180 visible values typed in code**, 491 of them bypassing a store that exists (C) |
| 3. Content | Agency wording as versioned templates with placeholders | **54 agency-IP blocks**: 11 editable in Settings, 4 versioned, 8 AI prompt sets in code only (D) |
| 4. Business chain | Lead → … → Performance, each link a uuid | Of 14 arrows: 4 held by an FK, 1 by uuid with no FK, 4 soft (a month string, dates, a computed offer), 5 not linked (B) |
| 5. Presentation | Tokens and components | Stabilised; exceptions are the brand files and fonts (C, logo/font rows) |

End state: one codebase, one agency per install, never multi-tenant.

## Headline counts

| Measure | Count | Where |
|---|---|---|
| Tables | 211 (206 live; 5 created then dropped) | A |
| Tables keyed on something other than a uuid | 65 (`bukku_links_gone` has no key) | A.3 |
| Non-uuid links | 117: 20 matched by name/email/code in SQL, 15 Bukku ids, 65 copied colleague names, 17 other copied values | A.2 |
| uuid columns with no FK | 89 (16 polymorphic) | A.2.3, A.2.4 |
| FKs with no stated `on delete` | 47 (36 to `team_members`) | A.3 |
| Visible agency values typed in code | 1,180 (2,082 with comments and notes) | C.4 |
| …by area (code) | schema and migrations 400, js 333, pages 186, demo 107, edge functions 73, css 29, PDFs 17, workers 17, manifest/site 11, CI 6 | C.4 |
| Bypasses of a central store | 491 (471 client side, 20 server mailboxes) plus 24 `|| 'ADspace'` fallbacks | C.2 |
| Values with no central store at all (server side) | 437 | C.2 |
| Internal identifiers (`ADspaceX`, `adspace.x` keys; not visible, left as they are) | 5,410 | C.5 |
| Agency-IP content blocks | 54 (letters/terms 11, email/WhatsApp 16, HR/consent/privacy 12, method/criteria 7, AI 8) | D.7 |
| Country-specific code spots | 20 grouped (about 1,316 Malaysia-time literals, 1,298 of them in SQL) | E |


## B. Business chain

Schema lines are `supabase/schema.sql` (last definition cited). Checked at HEAD `ca7f5d0` (2026-11-27).

**Lead and client are one row.** `clients.stage` defaults to `'lead'` (schema.sql:39; comment :37 "Leads live on the same list as billing clients"). Stages lead/contacted/proposal map to `clients.leads` access (js/crm.js:75-76). No `leads` table. A website `/quote/` request still lands on a `clients` row (`quotations.client_id not null`, :45603).

| Arrow | State | Mechanism | Evidence (file:line) | Note / on hold |
|---|---|---|---|---|
| Lead → Client | LINKED (same row) | `clients.stage` moves | schema.sql:39; js/crm.js:75 | No conversion step. The record just changes stage |
| Client → Quotation | LINKED | `quotations.client_id` FK | schema.sql:45600-45603, :45623; js/quotes.js:253 | — |
| Quotation → Service line | LINKED | `client_services.quotation_id` FK, written by `quotation_offer` / `quotation_review` | schema.sql:45646; :160225 (offer, insert :160249); :166575 (review, insert :166664); js/quotes.js:258; js/documents.js:75 | Lines can also be added by hand with `quotation_id` null |
| Service line → Month | SOFT | No key. New month lists the months a confirmed line covers (`start_on` + `tenure`) and labels the rest "No service line". It refuses nothing | js/ops.js:8256-8299; `ops_engagements` has no service-line column (schema.sql:6948-6970) | The closed loop is on hold (STANDARD §24; docs/rules/services.md) |
| Client → Month | LINKED | `ops_engagements.client_id` FK; `period` text `YYYY-MM`, unique (client_id, period) | schema.sql:6948-6966, :6971 | — |
| Month → Content Review | SOFT (set) / LINKED (task) | Set: `batches.period` YYYY-MM matches the month by string + `client_id`. Task: `ops_tasks.batch_id` FK, `ops_task_links.post_id` (`ops_link_post`), trigger `ops_post_follow`; the task carries `engagement_id` | schema.sql:41884 (batches.period); :4437 (batch_id); :106780; :106871; :109528; :6974; js/ops.js:4215; js/review.js:226 | — |
| Month → Video Scripts | LINKED | `video_scripts.engagement_id` FK (+ `period` text) | schema.sql:38459, :38461; js/scripts.js:682 | — |
| Month → Creator campaigns | NOT LINKED (record) | `campaigns` has no engagement or period column. Only a task can carry both `campaign_id` and `engagement_id` | schema.sql:823-845, :4436 | — |
| Month → Report | LINKED (task) / SOFT (report row) | `ops_engagement_sync_reports` makes report tasks (`source_type 'report_social'/'report_ads'`, `engagement_id`). The `sm_reports` row matches by `client_id` + `period_start/end` dates, with no engagement key | schema.sql:30136-30210, :25643; :12108-12139 (unique client/kind/period); js/ops.js:3776, :3802 | — |
| Content Review → Report | LINKED (no FK constraint) | `sm_report_post_links` (post_id, report_id, task_id), set by `sm_report_post_link` | schema.sql:97099-97116; :123665 | The uuid columns declare no `references` |
| Video Scripts → Report | NOT LINKED | — | — | — |
| Creator campaigns → Report | NOT LINKED | — | — | — |
| Report → Invoice (Bukku) | NOT LINKED | — | — | Covered by the closed loop, which is on hold |
| Quotation → Invoice (Bukku) | LINKED | `quotation_invoices` (quotation_id FK, cycle, kind, `bukku_id`); create or `quotation_invoice_link` | schema.sql:124112-124126; :166355; js/quotes.js:1655-1660; supabase/functions/bukku-sync/index.ts:1906 | **STANDARD §24 still calls this "on hold". The code says it is built (2026-11-27-quotation-invoice-link.sql)** |
| Campaign → Invoice (Bukku) | LINKED | `campaigns.bukku_invoice_id` | schema.sql:159167 | — |
| Client → Bukku contact/docs | LINKED (polymorphic) | `bukku_links (kind, record_id)` → `contact_id`; `bukku_docs.contact_id` | schema.sql:68365-68374; :132191-132206 | `record_id` has no FK |
| Invoice → Client feedback | NOT LINKED | Feedback is keyed on client only (`feedback_requests.client_id`, `manager_id`) | schema.sql:147075-147094 | — |
| Client feedback → Performance | SOFT (computed, offered) | `perf_ops_rate` averages `feedback_responses` by `manager_id` + MYT month. The rate is offered and never written (`perf_reviews.r_satisfaction` is still typed) | schema.sql:167101; js/perf.js:1102-1104 | Queued item, **now built** (af8b7b5, #1578) |
| Client feedback → Dashboard / client record | LINKED (read) | The newest score shows on Overview; the Team tab already counted clients not asked | js/crm.js (af8b7b5); docs/DECISIONS.md:12238 | Queued item, **now built** |
| Content Review → My Work | LINKED | Same post link as above. The client's note is read under the task at Revision (Client) | js/ops.js:3631; docs/rules/my-work.md:460-484 | Queued item, **now built** (8feedbc, #1566) |
| Creator booking → Bukku bill | LINKED | `creator_bills.option_id` FK; on Completed, `createbill` with `auto` runs after `creator_bill_auto_ok` (setting `creator_bill_on_completed`) | schema.sql:103411-103423; :166838; js/campaigns.js:6300 | Queued item, **now built** (3994242, #1575) |
| Short Links → client record | LINKED | `links.client_id`, `links.campaign_id` FK; `link_hit` counts visits | schema.sql:167742-167743; :167777; workers/links/worker.js:337 | Queued item, **now built** (e1d07b9, #1581); the Worker is deployed (ca7f5d0) |
| Outstation → My Work | NOT LINKED | `outstation_stops.client_id`, `touch_id` only; no task key | schema.sql:142630-142648 | On hold |
| Meta reports → Analytics | NOT LINKED | js/analytics.js has 0 `sm_report` references | — | On hold |

**Gaps**
- Service line → Month is the weakest link: the month only reads the line's dates, and no key ties a month to a line.
- Report → Invoice is not linked, and neither is Invoice → feedback. Neither is planned before the closed loop.
- The month owns its report task, but the `sm_reports` row has no `engagement_id`. It matches by client and dates only.
- Creator campaigns and Content Review sets reach the month only through tasks. Neither record carries a month key; the set carries only a `period` string.
- Polymorphic keys without an FK: `bukku_links.record_id` and the three ids on `sm_report_post_links`.
- STANDARD.md §24 is stale. All four "approved and queued" links are built (DECISIONS.md:12230-12243), and quotation → Bukku invoices is built too, although the file still lists it as on hold.

## E. Country-specific logic

| Topic | Location | Kind | Setting or code | Note |
|---|---|---|---|---|
| SST rate | `app_setting('sst_pct', day)` schema.sql:101929, :110121, :110648, :143851, :146344 (261 `'sst_pct'` hits); js/money.js:23-31, :151 | Tax % by date | SETTING (`app_settings`) | money.js `FIRST.sst_pct: 8` is the fallback when the read fails (CODE) |
| SST per client | `clients.sst_applies`, `sst_no` schema.sql:44-47; js/crm.js:3548, :4163 | Per-record flag | Record | — |
| SST tax codes | `tax_codes_list` js/money.js:120-150; bukku-sync `SV8` (3 hits) | Codes (SV8) | SETTING (table) | `SV8` appears as a literal in 3 bukku-sync and 2 money.js spots (CODE) |
| SST wording | js/money.js:296, :333-353 | Label "SST n%" | CODE | Rate read from the setting |
| SST no. format | js/supplierform.js:234 `^[A-Za-z]\d{2}-\d{4}-\d{8}$` | Validation | CODE | Supplier form only |
| Issuer SST/BRN | js/config.js:14-17 `ADSPACE_ORG` | Issuer facts | CONFIG | — |
| e-Invoice (MyInvois) | bukku-sync/index.ts:897, :1031, :1067 `myinvois_action:'NORMAL'`; :238 LHDN list | Draft invoice flag | CODE | — |
| e-Invoice mailbox | schema.sql:128874-128885 `mail_boxes` 'einvoice' | Reply-to | SETTING (seeded) | — |
| TIN | schema.sql:47765, :51842 (uppercased, spaces removed); js/details.js:22, :123 (maxlength 24) | Field | CODE (normalise only) | No format check |
| BRN / SSM 12-digit | `brn_check` (schema.sql, ONE BRN RULE) and `ADspaceWords.brnCheck` (js/words.js): 12 digits, year 1900..now, entity code 01/02/03/04, a Singapore client's UEN | Validation | CODE | One rule since 2026-11-28 (draft); the country's shapes become profile settings with item 18 |
| SG UEN / reg. no. | js/quote.js:1751-1752 | Validation | CODE | — |
| NRIC / IC / passport | js/supplierform.js:232 (`^\d{12}$`); js/personnel.js:49-51, :290 (masked fields); schema 124 hits | Field / validation | CODE | Masked in the DB (#1580) |
| EPF / SOCSO / EIS / PCB | js/personnel.js:86-87, :866-886 (payroll export header) | Fields, export | CODE | Stored and exported only; no calculation |
| Currency RM/S$ | js/money.js:19-20 (MYR/RM/en-MY, SGD/S$/en-SG); `clients.market` MY/SG schema.sql:45; `clients.bill_sgd` :73527 | Formatter | CODE (map) + Record | — |
| FX RM→S$ | `fx_sgd` schema.sql:53124 (397 hits); js/money.js:307-322 | Rate | SETTING | — |
| Market literals | schema.sql `'MY'` 163, `'SG'` 138 | Branching | CODE | — |
| Bukku doc currency | schema.sql:132203 default `'MYR'` | Default | CODE | — |
| Locales | `en-MY` / `en-SG` in 12 spots across 6 files (crm 3, money 3, quotes 3, ops, perf, personnel) | `toLocale` | CODE | — |
| Malaysia time (SQL) | `Asia/Kuala_Lumpur` ×1298 in schema.sql | `at time zone` | CODE | — |
| Malaysia time (JS) | js/clock.js:47 (`OFF = 8*3600000`), :60-61 (`+08:00`); `+08:00` in 11 files (overview 3, payments 2, clock 2, others 1 each); money.js:54, :63 timeZone | Clock | CODE | One copy in `ADspaceClock` (54 files use it); some files bypass it |
| Malaysia time (functions) | bukku-sync 2, brand-analysis 1, meet-create 1 | TZ | CODE | — |
| Public holidays | `public_holidays` schema.sql:47131; edited in js/settings.js (21 hits); read by js/ops.js (8) | Table | SETTING | Seed is Johor 2026-2027, schema.sql:47223-47229 (CODE seed). No per-state column |
| Phone | js/api.js:359-378 (`waNumber`, `phoneWord`: 0→60, 8 digits→65, +60/+65 formats); SQL `wa_number(p_raw, p_market)` schema.sql:39656 | Normalise / format | CODE | — |
| Malaysian states | bukku-sync/index.ts:235-236 (16-state list); address parse :244-282 | Address split for Bukku | CODE | — |
| Postcode | bukku-sync/index.ts:244-282; js/personnel.js (3) | Parse / export | CODE | — |
| PDPA | schema.sql 10 (comments); js/health.js, crm.js, admin.js 1 each | References | — | Retention periods are Business settings read by `privacy_retention` (STANDARD §24) |

**Counts per topic (rows / code spots)**
- SST: 6 rows; code 4 (fallback 8, SV8 literals, wording, SST-no regex). Issuer facts sit in config.
- e-Invoice/TIN: 3 rows; code 2 (`myinvois_action`, TIN normalise).
- BRN/SSM/UEN: 2 rows; code 2 (one validator a side since 2026-11-28; four until then).
- NRIC/IC/passport: 1 row; code 1.
- EPF/SOCSO/EIS/PCB: 1 row; code 1.
- Currency/FX/locale: 5 rows; code 4 (FX is a setting).
- Malaysia time: 3 rows; code 3 (about 1,316 literal sites in all).
- Holidays: 1 row; setting, Johor seed in code.
- Phone: 1 row; code 1 (JS plus SQL).
- States/postcode: 2 rows; code 2.
- PDPA: 1 row; settings.

**Code spots in total: 20 grouped spots** (SST 4, e-Invoice 2, BRN 2, NRIC 1, statutory 1, currency 4, time 3, phone 1, states/postcode 2). Settings: SST rate, tax codes, FX, holidays, e-Invoice mailbox, retention.

## F. Guards to build

Each guard is a suite in `digital-form-tests` with a **baseline file that only shrinks** (as `cssguard`): today's hits are listed, a new hit fails, a removed hit must be taken off the list. Scope for all three: the repository minus `.git`, `tests/`, `.claude/`, `node_modules`, `docs/DECISIONS.md`, `docs/DESIGN-NOTES.md`, `drafts/`, `ap01.html`, `accv-new.html`. Patterns are PCRE (`rg -P`, Python `re`).

### F.1 brandguard: agency values outside the profile

Allowed homes once layer 2 is built: the agency profile's seed and the install's own config file. Until then the baseline holds every hit.

| Kind | Pattern | Matches / files today |
|---|---|---|
| Name | `\b(?i:adspace)\b(?![.\-][A-Za-z0-9]\| PLT)` | 1,081 / 214 |
| Legal name | `ADSPACE PLT` | 142 / 66 |
| Registration | `202304002162` | 9 / 7 |
| Tax number | `J31-2401-32100002` | 2 / 2 |
| Address | `(?i)Mutiara Emas\|Mount Austin\|81100 Johor` | 45 / 14 |
| Phone | `762[ -]?5233\|60187625233` | 12 / 9 |
| Domain | `(?i)(?<![@\w.-])(?:[a-z0-9-]+\.)*adspace\.me\b\|(?<![@\w.-])adspacestudios\.com\b` | 375 / 103 |
| Mailbox | `(?i)[A-Za-z0-9._%+-]+@(?:[a-z0-9-]+\.)*(?:adspace\.me\|adspacestudios\.com)\b\|adspacestudios@gmail\.com` | 128 / 35 |
| Logo files | `(?i)adspace-brandname\|adspace-mark` | 16 / 9 |
| Fonts | `(?i)\bslate(?:rg\|book\|medium)?\b\|\boptima\b` | 151 / 36 |
| Social / map | `(?i)(?:facebook\|instagram\|linkedin\|tiktok)\.com/[\w./@]*adspace[\w.]*\|wa\.me/adspace\|google\.[a-z.]+/maps\|maps\.app\.goo\.gl` | 39 / 13 |
| Cloud ids | `\bmyadspace\b\|ap-southeast-5\|hwwuigvdfubuymchsvyx` | 82 / 22 |
| Fallback | `\|\|\s*'ADspace'` and `\|\|\s*'ADSPACE PLT'` | 24 |

Pipes are escaped for the table. Not caught on purpose: internal identifiers (5,410; C.5). Comments count: an install must ship none of them.

### F.2 contentguard: agency-IP wording typed in code

Allowed homes once layer 3 is built: the template store and its seed, `js/words.js` (neutral UI), `js/mailtpl.js` until its templates move.

| Pattern | Today |
|---|---|
| String literal of 20+ words in `js/*.js` (excluding `words.js`, `mailtpl.js`) | 149 in 28 files (921 at 12+ words: too broad to gate; use 20) |
| `para('` with a literal of 40+ characters (PDF body typed in code) | 51 (`documents.js`, `hrdocs.js`, `perf.js`, `quotepdf.js`) |
| Contract register `\bshall\b` inside a JS literal | 18 (`hrdocs.js`, `quotepdf.js`, `supplierform.js`) |
| Top-level template-literal constant in `supabase/functions/*/index.ts` (``const X = ` ``) | 17 (every one a prompt) |
| Literal of 12+ words in `supabase/functions/**` | 84 |
| Schema `E'…'` line of 150+ characters (seeded wording) | 55 |

Known gap: the literal scanner under-reads `js/crm.js` (9,119 lines); the test must tokenise with a real JS parser, not a regex.

### F.3 idguard: lookups by name or code instead of uuid

| Pattern | Where | Today |
|---|---|---|
| `\.eq\('(name\|code\|slug\|email\|ref\|reference\|serial\|client_name\|company)'` | `js/` | 10 |
| `\.ilike\('(name\|code\|slug\|email\|company\|client_name)'` | `js/` | 2 |
| `\.in\('(name\|code\|slug\|email)'` | `js/` | 1 |
| `(?i)lower\([a-z_.]*name\) *= *lower` | `supabase/schema.sql`, migrations | 14 |
| `(?i)\.name *= *p_[a-z_]*name` | same | 4 |
| `(?i)\.slug *= *p_` | same (a slug is an address, allowed where it is the public key: list them) | 4 |
| `(?i)[a-z_]*_name *= *[a-z_.]*\.name` | same | 19 |
| A column ending `owner`, `made_by`, `actor`, `subject`, `industry`, `brand_name`, `tax_code`, `stage_key` read in a `where` or `join` | same | the 20 rows of A.2.1 |
| A uuid column named `*_id` with no `references` and not in the polymorphic list (A.2.3) | `supabase/schema.sql` | 73 (89 less 16) |

SQL counts are over the re-runnable file, so repeated definitions count more than once; the test reads the last definition of each function (as `sql` already does).

## G. Order

One area per release. Sizes: **S** under half a day, **M** a day, **L** two or more days or a security path. *Ride-along* means it waits until the area is next touched for business reasons and goes in that release.

| # | Release | Layer | Size | When |
|---|---|---|---|---|
| 0 | Guards (F.1 to F.3) with today's baselines, so nothing new is added while the rest is done. Also: STANDARD §24 brought up to date (quotation → Bukku and the four queued links are built) | all | S | First |
| 1 | Colleague and client identity by auth user id: `team_members.auth_id`, `client_contacts.auth_id`, `allowed()` and `portal_clients` by uid with the email kept for invitation only | 1 | L | Alone, own PR; walked in both orders (sign-in, change of email) |
| 2 | Owners by id: `campaigns.owner_id`; `clients.owner` name fallback removed; `activity_log.actor_id` / `subject_id`; the 65 copied colleague names kept as display snapshots only | 1 | M | Next |
| 3 | Lookups by id: `industries`, `tax_codes`, `ops_workflow_stages` keyed and referenced by uuid; `sm_reports.brand_id`; `campaign_options.earlier_job_id` | 1 | M | Next |
| 4 | Foreign keys on the 73 single-target uuid columns (`not valid`, then validated after a clean-up read); `on delete` stated on the 47 | 1 | M | Next |
| 5 | The month as the chain's hub: `ops_engagements.service_line_id`; `batches`, `campaigns`, `sm_reports` carry `engagement_id` (the `period` text kept for display) | 1, 4 | L | After 4; one link a release if needed |
| 6 | Agency profile: one table, one read (`agency()` in SQL, `_shared/agency.ts` in functions, `ADspaceAgency` on the page), seeded from `ADSPACE_ORG`, `agencyName`, `serviceTermsUrl`, `brandLogo`, `mail_boxes`, `mail_senders`, `id_formats`; Settings › Business shows it | 2 | L | Built 2026-11-28 (`agency_profile`; `id_formats` holds no agency value and stays); the Settings view waits on the user (DECISIONS, 2026-11-28) |
| 7 | Client-side bypasses (471) and the 24 fallbacks onto the profile | 2 | M | Area by area, ride-along allowed |
| 8 | Server side (437): edge functions, SQL email and PDF text, workers onto the profile | 2 | M | Built 2026-11-28 on its draft PR: 20 functions, 12 edge functions, the links Worker (DECISIONS, 2026-11-28); seeded template words wait on 12, AI prompts on 17 |
| 9 | Static heads (titles, share cards, manifest, favicons; 186 page hits): one install file and a stamp script, since a static head cannot read the database | 2 | M | After 6 |
| 10 | Brand files and fonts per install; a free default face; Slate and Optima only where the agency holds a licence | 2, 5 | S | With 9 |
| 11 | Template store: versioned, placeholders, EN and 中文, one engine a side (`templates`, `template_render`, `js/tpl.js`). Built 2026-11-28 ahead of 6, no wording moved; its editor in Settings and Settings › Messages onto it go with 12 | 3 | L | After 6 |
| 12 | Letter of Offer and client letters (`documents.js`, `letters.js`) | 3 | M | Ride-along with Documents |
| 13 | Quotation and rate card terms (`quotepdf.js`, `ratecardpdf.js`, `quote.js`) | 3 | S | Ride-along with Services |
| 14 | HR documents and contract clauses (`hrdocs.js`, `hiring.js`, `onboard.js`) | 3 | M | Built 2026-11-28 on its draft PR: 35 templates of kind `hr-document`, read by the day a document went out; `onboard.js` held none (DECISIONS, 2026-11-28) |
| 15 | Consent and privacy lines (careers, supplier, details, personnel); Health agreement, feedback questions and checklist template get their editor | 3 | S | Ride-along per page |
| 16 | First-visit guides (`admin.js` GUIDES), performance categories (`perf.js`), ad-report explainer (`smreport.js`) | 3 | S each | Ride-along |
| 17 | AI prompts (8 functions) into the store, read by `_shared` | 3 | M | After 11 |
| 18 | Country: time zone, currency, locale, tax labels and registration formats as profile settings; one BRN validator (one since 2026-11-28) | 2 | M | Last; only when a non-Malaysian install is sold. The BRN fix rides along with Clients |

Releases 1, 5, 6 and 11 carry migrations and are major releases on their own PR (CLAUDE.md §3). Everything else is a train item.

## Top risks

1. Identity by email: a colleague's and a client contact's access is found by `lower(email)` from the token (`allowed()` schema.sql:126476; `portal_clients` :150203). An address changed or reused moves access with it.
2. Owners by name: `campaigns.owner` has no id at all; `clients.owner` falls back to the name (`client_rep` :164091). Two colleagues of one name, or a rename the trigger misses, route work and access to the wrong person.
3. The month is not tied to its service line (`js/ops.js:8256-8299`), and the Content Review set, the campaign and the report row reach it by a `period` string or by dates.
4. 89 uuid columns hold no FK, including all of `sm_report_post_links`: a delete leaves rows pointing at nothing.
5. Report → Invoice, Invoice → feedback, Video Scripts → Report and Campaigns → Report are not linked: the closed loop has no keys to stand on.
6. 491 values bypass a store that already exists, so a change to `ADSPACE_ORG` or `mail_boxes` does not reach every screen.
7. 437 server-side values (edge functions, SQL text, workers) have no store to read from.
8. Legal wording (Letter of Offer, quotation terms, contract clauses) lives in code: a change of terms needs a deploy, and an install inherits ADspace's.
9. AI prompts, eight functions, are code only and unversioned.
10. Country logic: 1,298 `Asia/Kuala_Lumpur` literals in SQL, one BRN validator (four until 2026-11-28), and commercial fonts whose licence does not pass to another agency.
