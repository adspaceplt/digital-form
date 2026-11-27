# Handover (27 Nov 2026, 06:35 UTC)

The single source of truth for work in flight. A fresh session reads this file,
then CLAUDE.md (§3 **Token economy** is binding), then the PR or branch of the
item it takes. The previous coordinator session ended here; nothing lives in it.

## Running now (coordinator: the session named in the latest coordinator handover; at most four sessions)

| Session | Work | When done |
|---|---|---|
| T `session_01RVzkaQPY1uMkNhrDk9jsg8` | #1532 client page weight (user said "go"): merging main with #1531, re-proving the 1,452 moved CSS rules, then merges itself; tests branch claude/page-weight goes to tests main at merge | Reports build, stops |
| Z `session_01RVzkaMf4aAp62531br68JM` | #1529 ad-spend explainer + approximate S$ on the sent quote link, Change selection, signing step and link PDF (SG billed in RM only). Migration restates #1531's app_settings_set and quote_website_read. Client-facing | Artifact to the user; merges on "go" |

G finished (#1499 261126.f4e8, #1501 261126.3a98) and is archived. Open from G: `bukku-sync` from main 8803a982 (index.ts 140 KB, too large for one connector call) is being deployed by session `session_01RVzkaQdpVPqkzAb7ChdveC` through the Management API; `SUPABASE_ACCESS_TOKEN` is now set in the environment for later deploys. PDF item 13 (the Rate Card discount sign, as G proposed in #1499/#1501's handover) is approved by the user ("2 ok"): build it, with its suite edit, on the next documents/PDF train.

## Queue (in order, as release trains)

1. **Build quote and TERMS fit**: merged, #1497.
2. **Surface tokens and `data-layout`**: merged, #1502 (the user, 26 Nov, "ok proceed"): `:root` tokens `--ground`, `--section-bg`, `--section-edge`, `--section-radius`, `--section-pad`, `--section-gap`, set by `<html data-layout="v3|cards|shaded">`; every card family reads them through one `:where()` base, keeping only its arrangement. Console `v3`, client portal `cards` until the user chooses, every other client page `shaded`. No visible change. Branch `claude/surface-tokens`.
3. **Style comparison** (session H) on an Artifact: the console's Clients list, a client record, Settings, the client portal, `/creators/`, `/quote/` × v3, cards, shaded, at 1280 and 390, by flipping the attribute. Send the user the link.
4. **Client pages**: merged, #1507 (J): the portal at six tabs, `/creators/` and `/creator/` in sections, `data-layout="v3"` on every client page, the 404 and the page template (the front door stays `shaded`); the selection page's view strip full width on a phone. J's review of main since 25 Nov (19 findings, 2 must fix: the health retention trigger, Build quote's key on a tab switch) is with the coordinator.
5. **Linked sections** (the user, 26 Nov: "3 4 5 7 yes"), each its own release, major where it needs a migration; read each area's rules and DECISIONS first, and show the user a short flow before building any that changes a workflow:
   - Content Review → My Work: a client's approval or request for changes on a set moves its task's stage (derived on load where the rules prefer it).
   - Creator campaign → Bukku bills: a completed booking creates the creator's payable bill in Bukku (check `creator_bill_made` first).
   - Client feedback → Performance and the Dashboard: a client's ratings feed the account manager's month and the client's standing.
   - Short Links → client record: a link belongs to a client or campaign, and its clicks show on that record.
   On hold ("1 2 6 8 on hold until further notice"; STANDARD.md §24): the closed loop from quotation to report, quotation → Bukku invoices, Outstation → My Work and claims, Meta reports → Analytics.
6. **One glyph set**: merged, #1517 (N), 261127.67f8; tests #308.
7. **Automatic `?v=` stamps** from the commit at the Pages build; `admin/sw.js` never caches an unstamped file.
8. **Tone sweep** since `863dddc` (`node tests/copyscan.js 863dddc`, fresh readers, one release), folding in `claude/tone-sweep-9-fixes`.
9. **Full gate on main**: run 27 Nov on 7158470 (P, #1519); its findings shipped as #1520 and #1521 (Q). Next full gate after the next day's merges.
10. J's other 17 review findings (J's handover on #1507).
11. **Ad-spend explainer**: merged, #1529 (Z), 261127.e9a3. Was: (now Z, #1529, with approximate S$ added) (fresh session after U; brief in U's handover comment on #1526): "billed separately" replaced on /quote/, the quote link, Build quote and the quotation PDF by "The advertising budget is not included in this quotation." + How ad spend works (sheet: Option 1 own ad account, recommended; Option 2 prepaid through us: month 1 before start, later months at {80}% spent, ads pause unpaid; on the quotation's payment terms an Agency Credit Term Fee of {20}%, e.g. RM 6,000 → RM 1,200). Explainer only, no choice; 80 and 20 are app_settings. Client-facing: screenshots first.
12. **DONE #1531 (261127.b981), with the representative rule.** /quote/ intake and follow-up loop (major; after 11, never in parallel: both edit js/quote.js). Mockup https://claude.ai/artifact/HYP2kxVanTLo6wMbtapdrZ. Decided (the user, 27 Nov): Contact person (name, email, WhatsApp); Registering as = two-option segment "Company · Sole / Partnership" (公司 · 独资 / 合伙), no Individual; Business Registration No. (BRN), 12 digits, required for both (Company codes 01/02/04, Sole / Partnership 03); Registered name; Brand name; Industry (console list, required); website or No website tick, social handle (one of the two required); Urgency to commence (console options, keep On a specific date); Comments (→ Enquiry); Source set automatically; consent and notice. Statuses: add only Waiting for details and Details received; our refusal is "Not quoted" with a reason (Incomplete details, Not a fit, Duplicate, Spam), Undo, Reopen; Ask for details sheet (tick what is missing; Send email, Copy for WhatsApp by hand); Reply by and close days as settings; prospect's own link opens Complete your details with only the ticked fields; the link's details step closes once sent. Matching: never shown on the public page; after submit BRN, then email + number; team sees "Matches existing client"; same brand → its record, registration held for Use details; new brand → Add as a new brand of {client} / Keep as a new lead; prospect always sees the same thank-you. Desk width: steps at 760px with paired fields side by side (recommended, the user's "rest as recommended"); phone unchanged. Client-facing: screenshots first.

## Logged defects (fail on main, not yet fixed)

`docs/rules/logged-defects.md`: load flakes in demo, crm, hiringsql, quotes, outstationsql; sql's UTC-day check and its wa_compose_prepare band check.

## Done today (builds as the rail shows them)

| Release | Build |
|---|---|
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

Also done:
- all 19 S1 edge functions deployed and read back;
- hi.adspace.me now carries `svc-terms`, `fb-ad-terms`, `verify` and `outstation`;
- go.adspace.me is being phased out, and its DNS stays until the user removes it.

## Waiting on the user

Done by the user on 26 Nov: the expectations in #1476, #1482, #1489 and #1493 approved; AINV2609023 confirmed; the Bukku token rotated and `BUKKU_TOKEN` updated; the iPhone checks; the four retired edge functions deleted (24 remain, verified live).

Done by the user on 27 Nov: the expectations listed on 26 Nov approved; O merged (#1523); meetings glyph = two people at a table (#1524); content meetings in Calls and visits (#1525); intake decisions all settled.

1. go.adspace.me's DNS stays for now; its removal is a future update.
2. White-label: ON HOLD by the user (27 Nov). Audit https://claude.ai/artifact/Mgqdt58TYua1wdMetrxDQR; start only on the user's word, step 1 (agency profile, additive) first, after items 11 and 12 merge.
3. Approved by the user 27 Nov: #1528 expectations; #1531 and #1532 "go". Waiting: Z's screenshots (#1529) for "go".
4. Logged, not yet queued: uxaudit cannot reach Settings › Public holidays; csStrip missing from STRIP_NAMES; crm and settings timing flakes (from #1531); My Work "Open Months" capital M.
5. Next after Z: the full gate on main (`bash tests/snap.sh all`), then J's 17 review findings, automatic ?v= stamps, the tone sweep since 863dddc, linked sections.
