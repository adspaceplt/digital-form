# Handover (26 Nov 2026, 13:20 UTC)

The single source of truth for work in flight. A fresh session reads this file,
then CLAUDE.md (§3 **Token economy** is binding), then the PR or branch of the
item it takes. The previous coordinator session ended here; nothing lives in it.

## Running now (coordinator session_01RVzkaP4WzcjZDWEysZw37c; at most four sessions)

| Session | Work | When done |
|---|---|---|
| C `session_01RVzkaLum5dPvcA9b8Pkfzv` | F8: quotation drafts (`ADP/QT{YYMM}-DRAFT`, Confirm quotation assigns the serial; website requests `ADP/REQ{YYMM}-{AAA}`; revisions `-R1`). Its worker dropped at 13:27; told at 14:20 to merge main, re-run affected and merge | Merges itself |
| F `session_01RVzkaPPWFkP4TvAS61BgEd` | #1496 and #1500 merged. Left: Numbering (one part in Settings), once F8 is on main | Message F when F8 merges |
| H `session_01RVzkaMzHTsWjccfqE6Hemb` | The surface comparison Artifact (6 screens × v3, cards, shaded, 1280 and 390); no repo change | Sends the link to the coordinator |

G finished (#1499 261126.f4e8, #1501 261126.3a98) and is archived. Open from G: `bukku-sync` from main 8803a982 (index.ts 140 KB, too large for one connector call) is being deployed by session `session_01RVzkaQdpVPqkzAb7ChdveC` through the Management API; `SUPABASE_ACCESS_TOKEN` is now set in the environment for later deploys. PDF item 13 (the Rate Card discount sign, as G proposed in #1499/#1501's handover) is approved by the user ("2 ok"): build it, with its suite edit, on the next documents/PDF train.

## Queue (in order, as release trains; coordinator session_01RVzkaP4WzcjZDWEysZw37c)

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
6. **One glyph set**: `js/icons.js` the one icon set for the console and every page; the ~289 inline SVGs in ~40 scripts replaced by named glyphs; `acts.js` and the section marks read from it; a suite (`tests/glyphs.js`, in `affected.json`) fails a new inline `<svg>` in `js/` outside `icons.js`. Check the weight budget.
7. **Automatic `?v=` stamps** from the commit at the Pages build; `admin/sw.js` never caches an unstamped file.
8. **Tone sweep** since `863dddc` (`node tests/copyscan.js 863dddc`, fresh readers, one release), folding in `claude/tone-sweep-9-fixes`.
9. **Full gate on main** in its own session (`bash tests/snap.sh all`, 2-hour limit).

## Logged defects (fail on main, not yet fixed)

`pdfreal`: three letters' head and foot checks fail on main 8e9224f (`docs/rules/logged-defects.md`).
`hiringiv`, `hiringheld` and `waapprove` fail from #1479's relabelled Settings sheets (`docs/rules/logged-defects.md`). F's Settings release is the natural place to fix them.

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

Also done:
- all 19 S1 edge functions deployed and read back;
- hi.adspace.me now carries `svc-terms`, `fb-ad-terms`, `verify` and `outstation`;
- go.adspace.me is being phased out, and its DNS stays until the user removes it.

## Waiting on the user

Done by the user on 26 Nov: the expectations in #1476, #1482, #1489 and #1493 approved; AINV2609023 confirmed; the Bukku token rotated and `BUKKU_TOKEN` updated; the iPhone checks; the four retired edge functions deleted (24 remain, verified live).

1. go.adspace.me's DNS stays for now; its removal is a future update.
2. Approve the expectations changed in #1497 (TERMS placement, View quote at a desk) and F's #1496 and #1500 (with the console weight budget +1.1 KB and the SKBBK line).
