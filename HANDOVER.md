# Handover (27 Nov 2026, 13:20 UTC / 21:20 MYT)

The single source of truth for work in flight. A fresh session reads this file,
then CLAUDE.md (§3 **Token economy** is binding), then the PR or branch of the
item it takes.

## Coordinator

`session_01RVzkaQASDHLN7cCsHaDkry` (from 27 Nov 06:40 UTC). It is the user's only chat: every session reports to it, and anything waiting on the user is brought there. It may be compacted. If it is replaced, the new coordinator messages every running session below with its own id. Session cap: the user allowed as many as needed on 27 Nov evening (CLAUDE.md says four). A Supabase connector set to Always allow on 27 Nov applies to sessions started after that.

## Running now

| Session | Work | Waits on |
|---|---|---|
| G `session_01RVzkaMyijzYM5U87LpzVtJ` | The day's full gate on main (`snap.sh all`, 2 h, from 12:25 UTC). Reports failures and logs them in logged-defects.md (docs only), then stops. Its findings become one fix session. | Nothing |
| A `session_01RVzkaPG9yZ8jep5cyPdzJv` | Campaign and creator activity keyed by a system id, not name (as #1560 did for clients); quotation salesperson designation read by member id, not name; tests/sql.js split under its 900 s limit; a list of other name-keyed lookups in supabase/ | Nothing |
| J `session_01RVzkaRQqvJgqAzQmNrcu77` | J's #1507 review findings: R2 console (4,9,10,11,12,16,17,18,19), R3 client pages (8,13; user "go" given), R4 migration (5,6,14,15) `2026-11-27-quotation-review-holds.sql`, R5 bukku-sync (7), R6 finding 3 option A (personnel IC and bank numbers masked; Show in Edit recorded; branch claude/personnel-masked). Merges in that order. | Nothing |
| TS `session_01RVzkaMbprQAtTmbzFaydv7` | Tone sweep since 863dddc (includes every 27 Nov build); the user's approved words are kept | "go" if a client page's words change |
| LK `session_01RVzkaMKCUxnGsrPFDHT7wm` | Linked sections: all four merged (#1566, #1575, #1578, #1581); the `adspace-links` Worker deployed from main by the coordinator 27 Nov 15:24 UTC (sha256 d33e8f90, a test visit counted and removed) | Done, ended |
| V2 `session_01RVzkaQaHg2BNhbgxqs2w82` | Automatic ?v= stamps: `?v=dev` placeholder, `.github/workflows/pages.yml`, per-file content hash (user "go"). Builds and opens a PR but does NOT merge. | **The user's click** at merge: GitHub → Settings → Pages → Source → "GitHub Actions". The coordinator tells the user when, then merges. |

Scheduled: the coordinator's check at 21:41 MYT (13:41 UTC).

## Decisions of 27 Nov (all applied or in the sessions above)

- The console shows a confidentiality line (English only): "Confidential. This system is for authorised {agency} personnel only. Unauthorised access, use or disclosure is strictly prohibited." The console frame stays #F5F5F5 (not #FDFDFD); Safari's toolbar takes --frame.
- Quotations: own Valid for (fallback quote_valid_days, "Default validity"); a one-time-only quotation hides the commitment; the tax code sits in the pricing row (phone: on the Qty row); a website request saves a colleague's brand and line edits; the brand follows the team's saved name; check and submit flags a company mismatch (Keep or Use) and shows Bukku-held billing read only; "Show totals for the whole period" (off by default: Total for {n} months incl. SST, Total incl. SST in its own block, on the PDF, its Agreed figures, /quote/, the Summary and the S$ line); a website request's ⋯ is Download PDF, Show quotation link, Ask for details · Edit, Cancel quote · Delete (no Do not contact); every quotation ref is click-to-copy; Link existing invoice on a quotation's Invoices (invoices stay on the quotation, not Service lines).
- Scrapped: Remove on every Build quote line (branch claude/services-lines-remove parked, unmerged). Kept: nobody reviews their own quotation, admins included.
- Every delete is Full control; Edit files Request delete (13 functions moved; tests/sql.js guards it). A client holding a signed quotation cannot be deleted (function plus guard trigger).
- The activity record is keyed by the client's system id (#1560); campaigns follow (A).
- Feedback can be requested of Past clients; "Allow portal sign-in" / "Stop portal sign-in"; email templates are one row each with an English · 中文 switch.
- A section never resizes or restyles a base element (DESIGN.md token line, J, with the user's OK).
- Turning tracking off in Resend is intended: email status stops at Delivered. No priority headers.
- Paths stay as they are (/creators/, /creator/, /careers/, /details/).
- ADP/QT2611-B02's valid_until was set to 2026-12-11 by hand (the coordinator, direct SQL; not in the Activity record).

## Queue (in order, as release trains)

1. **Build quote and TERMS fit**: merged, #1497.
2. **Surface tokens and `data-layout`**: merged, #1502 (the user, 26 Nov, "ok proceed"): `:root` tokens `--ground`, `--section-bg`, `--section-edge`, `--section-radius`, `--section-pad`, `--section-gap`, set by `<html data-layout="v3|cards|shaded">`; every card family reads them through one `:where()` base, keeping only its arrangement. Console `v3`, client portal `cards` until the user chooses, every other client page `shaded`. No visible change. Branch `claude/surface-tokens`.
3. **Style comparison** (session H) on an Artifact: the console's Clients list, a client record, Settings, the client portal, `/creators/`, `/quote/` × v3, cards, shaded, at 1280 and 390, by flipping the attribute. Send the user the link.
4. **Client pages**: merged, #1507 (J): the portal at six tabs, `/creators/` and `/creator/` in sections, `data-layout="v3"` on every client page, the 404 and the page template (the front door stays `shaded`); the selection page's view strip full width on a phone. J's review of main since 25 Nov (19 findings, 2 must fix: the health retention trigger, Build quote's key on a tab switch) is with the coordinator.
5. **Linked sections**: DONE (27 Nov, LK): Content Review → My Work note #1566 (261127.edbc); creator bill on Completed #1575 (261127.4242, `bukku-sync` v72); client feedback → Performance and the Overview #1578 (261127.b7b5); Short Links clicks #1581 (261127.07b9, Worker deployed 27 Nov). Was: (the user, 26 Nov: "3 4 5 7 yes"), each its own release, major where it needs a migration; read each area's rules and DECISIONS first, and show the user a short flow before building any that changes a workflow:
   - Content Review → My Work: a client's approval or request for changes on a set moves its task's stage (derived on load where the rules prefer it).
   - Creator campaign → Bukku bills: a completed booking creates the creator's payable bill in Bukku (check `creator_bill_made` first).
   - Client feedback → Performance and the Dashboard: a client's ratings feed the account manager's month and the client's standing.
   - Short Links → client record: a link belongs to a client or campaign, and its clicks show on that record.
   On hold ("1 2 6 8 on hold until further notice"; STANDARD.md §24): the closed loop from quotation to report, quotation → Bukku invoices, Outstation → My Work and claims, Meta reports → Analytics.
6. **One glyph set**: merged, #1517 (N), 261127.67f8; tests #308.
7. **Automatic `?v=` stamps** from the commit at the Pages build; `admin/sw.js` never caches an unstamped file.
8. **DONE #1565 (261127.940d), tests #328.** Tone sweep since `863dddc` with tone sweep 9 folded in: 26 findings, 14 fixed, 8 answered (`docs/DECISIONS.md`). Client lines held on draft #1567 (tests branch `quote-words-863dddc`) for the user's go, screenshots https://claude.ai/artifact/MLcHq1QChJMyQpv5ARebZ3; on go: merge main in, `affected --run` (quotesite, pdfreal, pdfcases), merge both. **Next, one migration release (SQL-held words):** candidate email subject Missed interview for {position}; the morning alert's the nightly Bukku update did not run / failed and the S3 storage report failed; the quotation's activity lines entered by, n prices adjusted, n service lines; Quotation requested on the Quotation portal; Analytics analyses → a clearer AI usage name; the three Quotation portal settings labels as nouns (Prospect contact time, Details reply time, Close after Reply by) in `js/admin.js` and the activity names together.
9. **Full gate on main**: run 27 Nov on 7158470 (P, #1519); its findings shipped as #1520 and #1521 (Q). Next full gate after the next day's merges.
10. J's other 17 review findings (J's handover on #1507).
11. **Ad-spend explainer**: merged, #1529 (Z), 261127.e9a3. Was: (now Z, #1529, with approximate S$ added) (fresh session after U; brief in U's handover comment on #1526): "billed separately" replaced on /quote/, the quote link, Build quote and the quotation PDF by "The advertising budget is not included in this quotation." + How ad spend works (sheet: Option 1 own ad account, recommended; Option 2 prepaid through us: month 1 before start, later months at {80}% spent, ads pause unpaid; on the quotation's payment terms an Agency Credit Term Fee of {20}%, e.g. RM 6,000 → RM 1,200). Explainer only, no choice; 80 and 20 are app_settings. Client-facing: screenshots first.
12. **DONE #1531 (261127.b981), with the representative rule.** /quote/ intake and follow-up loop (major; after 11, never in parallel: both edit js/quote.js). Mockup https://claude.ai/artifact/HYP2kxVanTLo6wMbtapdrZ. Decided (the user, 27 Nov): Contact person (name, email, WhatsApp); Registering as = two-option segment "Company · Sole / Partnership" (公司 · 独资 / 合伙), no Individual; Business Registration No. (BRN), 12 digits, required for both (Company codes 01/02/04, Sole / Partnership 03); Registered name; Brand name; Industry (console list, required); website or No website tick, social handle (one of the two required); Urgency to commence (console options, keep On a specific date); Comments (→ Enquiry); Source set automatically; consent and notice. Statuses: add only Waiting for details and Details received; our refusal is "Not quoted" with a reason (Incomplete details, Not a fit, Duplicate, Spam), Undo, Reopen; Ask for details sheet (tick what is missing; Send email, Copy for WhatsApp by hand); Reply by and close days as settings; prospect's own link opens Complete your details with only the ticked fields; the link's details step closes once sent. Matching: never shown on the public page; after submit BRN, then email + number; team sees "Matches existing client"; same brand → its record, registration held for Use details; new brand → Add as a new brand of {client} / Keep as a new lead; prospect always sees the same thank-you. Desk width: steps at 760px with paired fields side by side (recommended, the user's "rest as recommended"); phone unchanged. Client-facing: screenshots first.

13. **DONE #1550 (261127.f663), #1553 (261127.529f), #1556 (261127.d6c1).** The Build quote tick, the PDF (fees page and Figures agreed), the /quote/ link, Build quote's Summary and the S$ line; migration `2026-11-27-quote-period-total.sql` live. **Period total on a quotation** (approved by the user, 27 Nov, coordinator session): a tick in Build quote's Quotation section, "Show totals for the whole period", off by default, per quotation. Ticked: under Monthly incl. SST a line "Total for {n} months incl. SST" (each monthly line's own Months, term discount included); then, set apart below the One-time block (spaced down as its own block, so it never reads as the One-time section's total), "Total incl. SST" = period total + one-time incl. SST, with one note line "{n} months of the monthly fee, plus one-time fees. Advertising budget not included." Only the period line where there are no one-time fees; no effect on a one-time-only quotation; S$ approximation on both for SG billed in RM. PDF and the /quote/ link: client-facing, screenshots to the user for "go". Planning snapshot sent to the user 27 Nov. Start in a fresh session after the weekly usage limit allows.
14. **Today's full gate on main**: run on 7c85e8b (27 Nov); four suites failing (words, adsreport, uxaudit, pdflibhash), logged in `docs/rules/logged-defects.md`; they are the next batch.
15. **DONE (2026-11-28, `2026-11-28-colleagues-by-id.sql` live).** **Colleague lookups by system ID, not name** (the user, 27 Nov: "queue it"): `quote_sign_member` (45 call sites), `quote_sign_member_sees`, `client_rep`, `client_details_submit`, `sm_reports_published_notice`, `feedback_request` still match `team_members` by name. Move each to the colleague's id, as #1571 did for `quotations.made_by_id` (column, before-insert trigger, backfill only where one colleague holds the name, column grant to `authenticated`). One migration release; list in `docs/DECISIONS.md` (A, #1571).
16. **A database check on Billing's BRN** (the user, 28 Nov, BRN rule decision 4): `clients.company_no` and `billing_entities` today are checked on the page alone (`ADspaceWords.brnCheck`); add `brn_check` with the client's market as a trigger or check, `not valid` first (one Malaysia-market client holds a UEN-shaped number), one migration release.
17. **Quotation signing that knows the market** (the user, 28 Nov, BRN rule decision 5): `quote_sign_company` is not handed the client's market, so it takes a BRN or a UEN; pass the market through its two callers.
18. **CORS origin to a setting** (the user, 28 Nov, release 8 decision 2; ships in restructure release 9): `_shared/cors.ts`'s origin, synchronous and read by 22 functions, moves to an environment setting from the agency profile. A security path: every browser-called function redeployed with it and walked from the portal's origin and a refused one.
19. **An `{agency}` field in saved email and WhatsApp subjects** (the user, 28 Nov, release 8 decision 3; ships in restructure release 12): the seeded subjects and sign-offs that type the agency's name read the field, filled from the profile by the template engine.
20. **`client_brand_logo`'s stored agency key renamed `agency`** (the user, 28 Nov, release 8 decision 4): a later small data migration, the pages and the function reading both until it is applied.
21. **FIXED on `claude/underhead-reqref-fix` (draft PR, not merged; migration `2026-11-28-request-ref-walks-free-codes.sql` not applied).** **`reqrefsql` ran out of random request numbers** (release 8's affected run, 28 Nov; `docs/rules/logged-defects.md`): `public_request_ref` retries at random and failed with "no free number" on a month the suite nearly fills. Fix the cause (walk the free codes, or the suite seeds its own draws); never re-run it to green.

22. **Release 18, country on the profile: what is left** (built 2026-11-28 on `claude/country-profile`, `2026-11-28-country-profile.sql`). Before any merge that restates a function reading the zone, regenerate the band with `node tests/tzroute.js supabase/schema.sql band` (countrysql fails a typed zone). Left, in order: (a) registration formats on the profile (`brn_check`'s 12-digit rule and its callers' typed `'MY'` read `agency('country')`), after R16 and R17 merge; (b) the word "SST" outside js/money.js (pages, PDFs, SQL email and activity text) read from `tax_label`; (c) the cron hours (UTC hours chosen for Malaysia: 04:00 = noon) from the zone; (d) a zone with summer time in `ADspaceClock` (per-moment offset); (e) demo/engine.js's typed zone and offsets; (f) brand-analysis's market-to-zone map; (g) the Settings › Business view of the country keys (waits on the profile's Settings view, release 6).

## Logged defects (fail on main, not yet fixed)

`docs/rules/logged-defects.md`: load flakes in demo, crm, hiringsql, quotes, outstationsql; sql's UTC-day check and its wa_compose_prepare band check.

## Done today (builds as the rail shows them)

| Release | Build |
|---|---|
| #1566 The client's changes on its My Work task | 261127.edbc |
| #1575 Creator draft bill on Completed (bukku-sync v72) | 261127.4242 |
| #1578 Client satisfaction from feedback; the Overview's Client feedback | 261127.b7b5 |
| #1581 Short links' owner and visits (Worker deployed) | 261127.07b9 |
| Copy review since 863dddc, console (#1565) | 261127.940d |
| #1478 Build quote copy | 261126.2136 |
| #1479 Settings sheets | 261126.2fe0 |
| #1481 F1, trip facts | 261126.1fe7 |
| #1477 S2, abuse paths | 261126.eeef |
| #1483 F2, next trip number | 261126.8298 |
| #1484 F4, rates refresh | 261126.57c5 |
| #1482 Build quote one sheet | 261126.0345 |
| #1485 S3 | 261126.28ed |
| #1486 S4, retention and jobs (its held SQL run live) | 261126.d9a1 |
| #1487 F3 + F5, every quotation issued and on /verify/ (its held SQL run live) | 261126.f207 |
| #1488 F6, Quotation Cover removed | 261126.6a5a |
| #1489 Unslop pass 1 | 261126.420e |
| #1476 Campaign invoice in Bukku (bukku-sync v68) | 261126.746a |
| #1490 S5, tone of standing lines | 261126.39ba |
| #1491 F7, cancelled interview moves the stage back | — |
| #1492 Letter of Offer issuing path removed | 261126.396c |
| #1493 digital.adspace.me/verify; View all scroll | 261126.cb04 |
| #1494 Rules 207 KB → 81 KB; Token economy | 261126.baf3 |
| #1496 Team groups (F) | 261126.9856 |
| #1497 Build quote one sheet at a desk; TERMS fit | 261126.9c59 |
| #1498 Handover queue | 261126.4769 |
| #1499 PDFs and emails (G) | 261126.f4e8 |
| #1500 Settings (F) | 261126.169c |
| #1501 Sections and sheets (G) | 261126.3a98 |
| #1502 Surface tokens, `data-layout` | 261126.22df |
| #1507 Client pages train (J): six portal tabs, creator pages in sections, v3 plain white on every client page | 261126.f307 |
| #1508 Interview missed (K): Did not attend (Offer a new time, Close application), Interview completed; migration live, hiring-mail v22 | 261126.2c18 |
| #1511 One request reference (L): ADP/REQ{YYMM}-{AAA} on details, supplier, careers, client portal requests and feedback, unique across kinds; migration live, no edge function; tests #304 | 261127.a163 |
| #1513 Hotfix (M): a leaver's health data kept its six months (inactive stamp on every update; migration live); Build quote keeps its key on a settings re-read; tests #305 | 261127.c7a6 |
| #1514 Team › Groups (M): each section's levels as wide as its own, no empty slots; tests #306 | 261127.5f23 |
| #1515 Step track (M): every line clear of its discs; the bar's name alone under 400px; Exit demo's gutter; tests #307 (weight +0.1 KB on three client pages) | 261127.39bd |
| #1523 Content Review top (O; migration live) | 261127.d9e7 |
| #1524 Meeting glyph: two people at a table (R) | 261127.aaf2 |
| #1525 Content meetings in Calls and visits (R) | 261127.fa10 |
| #1527 Handover; carries #1526 /quote/ ad budget follows the plan, notice, commitment lines removed (migration live) | 261127.0c8b |
| #1528 Request feedback: Copy for WhatsApp (migration live) | 261127.a3c2 |
| #1530 Record rows keep the card's rounded edge | 261127.6393 |
| #1531 /quote/ intake, follow-up loop, representative rule (Sales by on quotation pages, Person in charge in the portal, none if unassigned); supplier-mail v34; three migrations live | 261127.b981 |
| #1519 Full gate findings logged (P) | 261127.f805 |
| #1520 Trip card controls at full height; stale suites corrected (Q); tests #309 | 261127.b06a |
| #1521 pdfreal reads the printed verify address (Q); tests #310 | 261127.fd37 |
| #1517 One glyph set (N): every page draws from `js/icons.js`, one meaning one glyph (`MEANS`), WhatsApp's own mark on wa.me links; `tests/glyphs.js`; weight budgets raised with reason | 261127.67f8 |
| #1523 Content Review top (O): one sentence in the head, counts in the strip alone, the set line with Filter, a video's own safe area switch; migration `2026-11-27-review-feed-content-month.sql`; tests #311 | see the coordinator's report |
| #1534 Bukku contact emails and phones as lists (hotfix, bukku-sync v70) | 261127.ce42 |
| #1529 Ad-spend explainer and approximate S$ (Z): How ad spend works as Option 1 or Option 2 with a comparison, 80/20 settings; a Singapore client billed in RM sees each quotation total's S$; migration live; tests #318 | 261127.e9a3 |
| #1538 Confidentiality line at the top of the console, signed in and on its sign-in page; English only; at a desk centred over the sheet with the rail beside it | 261127.5c9b |
| #1544 Confidentiality line even over the sheet (12px above and below); Safari's toolbar tint the frame in light; covers.js expectation approved by the user | 261127.0270 |
| #1541 A colleague's Save on a website request keeps its brand and its edits (migration `2026-11-27-colleague-save-website-request.sql`, applied and read back); tests #319 | 261127.9bc8 |
| #1536 Build quote: one-time reads One-time, tax a column (hotfix) | 261127.f21a |
| #1540 Build quote: a line's figures on its name's first line | 261127.daa5 |
| #1546 Feedback from Past clients (Active, Paused or Past asked, a lead never; a sent link stays open whatever the portal's access); Request feedback drawn only where it can be sent; a Past client's ⋯ reads Allow portal sign-in / Stop portal sign-in (migration `2026-11-27-feedback-from-past-clients.sql`, applied and read back); tests 55add78 | 261127.e56e |
| #1550 Period total on a quotation, release 1: Build quote's Show totals for the whole period (off by default) and the PDF's Total for {n} months incl. SST and Total incl. SST, from the database's term total; no migration; tests b3cbb80 | 261127.f663 |
| #1553 Period total: the PDF's Figures agreed name the period total and the total | 261127.529f |
| #1556 Period total: the /quote/ link (its own card, English and 中文), Build quote's Summary and the S$ line; `quote_extras` keeps the tick with each quotation's totals (migration applied and read back); tests 98f31ef | 261127.d6c1 |
| Build quote on a phone: tax back on the Qty row | 261127.2820 |
| Deletes at Full control (access fix, "go all 13"): 13 admin tools' deletes ask Full control and join `delete_kinds`, Edit files Request delete; a request against a granted part asks `ops_granted`; guard in `tests/sql.js`; migration `2026-11-27-deletes-at-full-control.sql` live | see the coordinator's report |
| Hotfix: a quotation is valid for its own Valid for, website requests included, from the day it is published; the PDF's TERMS states the same days (migration `2026-11-27-quote-valid-own-days.sql`, applied and read back). ADP/QT2611-B02 (REQ2611-SBD) was published at 08:58, before it, and still reads valid until 27 Dec: correcting it to 11 Dec waits on the coordinator | 261127.e415 |
| Email templates: each two-language email (Service rating, Performance review, Ask for details) is one row with an English · 中文 strip in its editor; a missing 中文 reads 中文 not written; no database change | (this PR) |
| A website request's ⋯ in three groups (Download PDF, Show quotation link, Ask for details · Edit, Cancel quote · Delete), Delete under the delete rule (migration `2026-11-27-quote-request-deleted.sql`, applied and read back); every quotation reference pressed to copy (`ADspaceCopy.ref`, the Register's too); Preview keeps its leaving mark in a sheet's foot | (this PR) |
| Facts: an address keeps its line (two facts, the value the rest; it breaks only after @ or a dot); a quotation's check reads a Bukku-held company as words under Kept in Bukku. | (this PR) |
| #1560 A client's history kept by its id: `activity_log.client_id` (migration `2026-11-27-activity-client-id.sql`, applied and read back; 2,834 of 4,568 lines backfilled, 1,734 null, Bizgrowth 24 of 24); a campaign's and a creator's panes still read by name (next) | 261127.d45e |
| #1571 A campaign's and a creator's history kept by id (`activity_log.campaign_id`, `creator_id`; migration `2026-11-27-activity-campaign-creator-id.sql`, applied by the coordinator: 155 of 417 campaign lines, 69 of 153 creator lines); a quotation's Prepared by role by `made_by_id` (`2026-11-27-quotation-made-by-id.sql` with its column grant, applied: 5 of 12 filled); `tests/sql.js` 897 s → 258 s (`lastDefs` linear, memoised). Listed, not fixed: functions still matching a colleague by `clients.owner` name or `made_by` (DECISIONS 2026-11-27) | (this PR) |
| A quotation's brand follows its one named brand (1 row backfilled: ADP/QT2611-B02 → Lemmermeyer Malaysia); a signed company that differs from the client record is kept or taken at the check and applied on approval; a signed quotation is never deleted, with its client or alone (same migration) | (this PR) |
| Full gate on main 7c85e8b (tests 1d34edb): 263 passed, 4 failing (words #1556, adsreport, uxaudit, pdflibhash), logged; taxcodes passes again | (this PR) |
| Full gate on main 60bb95c (tests 405b093), 28 Nov: 288 of 289 passed, 1 failing (gateself: colleagueidsql does not stop a leftover Postgres server, tests #339), logged; 5,573 s (1 h 33 min); #1593, #1595 and #1596 merged after and are not in it | (this PR) |
| Rate Card PDF: a term discount reads −10% (true minus, no space), PDF item 13 | (this PR) |
| Console fixes from J's review (4, 9, 10, 11, 12, 16, 17, 18, 19): One per brand partway, failed reads named (creators, email templates), view-only billing to its tab, old check-in photos retaken, Bukku PDF link, `.then(ok).catch`, migrations' apply order; `sql` stops a leftover server | (this PR) |
| Client pages from J's review (8, 13): a failed read keeps Content Review and Video Scripts drawn with Try again; a quotation's TERMS never split onto an extra page; demo engine rebuilt | (this PR) |
| Quotation holds from J's review (5, 6, 14, 15): a confirmed revision opened by the client is sent out; an expired draft is refused at Confirm; a change request re-checks under its lock; a bad price-check input still counts. Migration `2026-11-27-quotation-review-holds.sql` | (this PR) |
| Bukku from J's review (7): a retry never links a contact that took the same code under another company; bukku-sync redeployed | (this PR) |
| Personnel numbers masked (J3, option A): the read holds last fours alone, Show reveals and records, a save never writes the mask back; migration `2026-11-27-personnel-numbers-masked.sql`. Design rule: a section never resizes a base element | (this PR) |

Also done:
- all 19 S1 edge functions deployed and read back;
- hi.adspace.me now carries `svc-terms`, `fb-ad-terms`, `verify` and `outstation`;
- go.adspace.me is being phased out, and its DNS stays until the user removes it.

## Restructure queue (`docs/MAP.md` §G; approved by the user 28 Nov)

Taken in this order, one area a release. Release 0 (the guards, #1586; self-test `guardself`) is done. Releases 1, 5, 6 and 11 carry migrations and go alone on their own PR; the rest ride the area's train.

| Order | MAP # | Release | How it ships |
|---|---|---|---|
| 1 | 1 | Identity by auth user id: `team_members.auth_id`, `client_contacts.auth_id`, `allowed()` and `portal_clients` by uid; email kept for invitation only | Alone, own PR, security path; walked in both orders (sign-in, change of email) |
| 2 | 2 | Owners by id: `campaigns.owner_id`, `clients.owner` name fallback removed, `activity_log.actor_id` / `subject_id` | Next |
| 3 | 3 | Lookups by id: `industries`, `tax_codes`, `ops_workflow_stages` by uuid; `sm_reports.brand_id`; `campaign_options.earlier_job_id` | Next |
| 4 | 4 | Foreign keys on the single-target uuid columns (`not valid`, then validated after a clean-up read); `on delete` stated | Next |
| 5 | 6 | Agency profile: one table, one read (`agency()`, `_shared/agency.ts`, `ADspaceAgency`), seeded from today's stores | Own PR; independent of 1 to 4. Live 28 Nov (#1599) |
| HELD | 5 | The month as hub (`ops_engagements.service_line_id`; `engagement_id` on batches, campaigns, sm_reports) | **Only on the user's word**: overlaps the closed loop the user holds (STANDARD.md §24) |
| 6 | 7 to 17 | Bypasses and fallbacks onto the profile (7), server side (8), static heads (9; with it the Settings › Company Agency group that edits the profile, the user 28 Nov: "wait", since the pages read `js/config.js` until then), brand files and fonts (10), template store (11, own PR, after 6), letters (12), quotation terms (13), HR documents (14), consent lines (15), guides and categories (16), AI prompts (17, after 11) | Mostly ride-along with each area's next train; 8, 9 and 11 after the profile |
| Last | 18 | Country: time zone, currency, locale, tax labels, registration formats as profile settings | Only when a non-Malaysian agency signs |

Flags:
- Font licence: the heading and letterhead faces are commercial; their licence does not pass to another agency (release 10: a free default face per install).
- Four BRN validators disagree (schema check, `js/quote.js`, `js/supplierform.js`, looser `js/details.js`): one validator, riding along with Clients ahead of release 18.

## Waiting on the user

- The quote page's reviewed words (#1567): reply go, or name a line to keep. https://claude.ai/artifact/MLcHq1QChJMyQpv5ARebZ3

Done by the user on 26 Nov: the expectations in #1476, #1482, #1489 and #1493 approved; AINV2609023 confirmed; the Bukku token rotated and `BUKKU_TOKEN` updated; the iPhone checks; the four retired edge functions deleted (24 remain, verified live).

Done by the user on 27 Nov: the expectations listed on 26 Nov approved; O merged (#1523); meetings glyph = two people at a table (#1524); content meetings in Calls and visits (#1525); intake decisions all settled.

1. go.adspace.me's DNS stays for now; its removal is a future update.
2. White-label: approved by the user 28 Nov as the restructure queue above (audit https://claude.ai/artifact/Mgqdt58TYua1wdMetrxDQR).
3. Approved by the user 27 Nov: #1528 expectations; #1531 and #1532 "go". Waiting: Z's screenshots (#1529) for "go".
4. Logged, not yet queued: uxaudit cannot reach Settings › Public holidays; csStrip missing from STRIP_NAMES; crm and settings timing flakes (from #1531); My Work "Open Months" capital M.
5. Next after Z: the full gate on main (`bash tests/snap.sh all`), then J's 17 review findings, automatic ?v= stamps, the tone sweep since 863dddc, linked sections.
