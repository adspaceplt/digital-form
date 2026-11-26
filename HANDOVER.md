# Handover (26 Nov 2026, 13:20 UTC)

The single source of truth for work in flight. A fresh session reads this file,
then CLAUDE.md (§3 **Token economy** is binding), then the PR or branch of the
item it takes. The previous coordinator session ended here; nothing lives in it.

## Running now (sessions started by the old coordinator; at most four at once)

| Session | Work | When done |
|---|---|---|
| C `session_01RVzkaLum5dPvcA9b8Pkfzv` | F8: a team quotation is a draft (`ADP/QT{YYMM}-DRAFT`, only Preview PDF, Edit, Confirm, Remove) until **Confirm quotation** assigns its serial; a website request takes `ADP/REQ{YYMM}-{AAA}` (three random letters) and its serial at Send quotation; a revision after Sent is `-R1`, `-R2` under its family root. `quotation_issued(q)` becomes "confirmed". | Merges itself, reports builds |
| F `session_01RVzkaPPWFkP4TvAS61BgEd` | Team groups (What this group can do, switches renamed after their Settings rows, presets with summaries), then Settings (Portal and Company split, one Numbering part once F8 merges, small fixes) | Merges itself |
| G `session_01RVzkaNbZ2662GKRQQPLLtR` | Second unslop pass: PDFs and emails (one email button, money never split), remaining sections, sheets and editors; deploys supplier-mail with the email functions | Merges itself |

The coordinator checks them every 30 minutes by their status line alone and
archives one whose work is all merged.

## Queue for the next session (in order, as release trains)

1. **Build quote and TERMS fit**, one release:
   - branch `claude/qb-plan-grid` (portal and tests repos):
     - plan cards three across;
     - every brand's items editable at once;
     - at a desk the items sit on the same sheet under the brands, with no View quote or Back.
   - branch `claude/quote-terms-fit` (portal, tests in the agent's clone, pushed as `claude/quote-terms-fit` in digital-form-tests):
     - TERMS move under the totals only when they fit whole and no Add-on Rates follow on a later page;
     - otherwise TERMS open the signing page.
   - Merge main into both and combine them into one train. Run `node tests/affected.js --run`. Known: `quotes` and `geom` checks from #1487 and #1476 clear once main is merged. List the changed expectations in the PR.
2. **Client portal: six tabs at most** (approved by the user, 26 Nov: "Ok"). The strip has ten panes; cap it at six, with anything beyond merged into a tab, never a seventh. Build it, screenshot it at desk and phone, and send the shots to the user before merging:

   | Tab | Holds |
   |---|---|
   | Overview | Overview |
   | Content | Content Review, Video Scripts, Creator Campaigns |
   | Reports | Reports |
   | Services | Services, Invoices, Letters |
   | Meetings | Meetings, Feedback |
   | Account | Account |

   Each part stays a card, and `?tab=` of every old pane still lands on its part. Write the cap into `docs/rules/client-portal.md`.
3. **Automatic `?v=` stamps.** The Pages build stamps every script and stylesheet from the commit (as `version.json` already is), so no PR edits sixteen page files and stamp conflicts end. Keep `admin/sw.js`'s rule that an unstamped file is never cached.
4. **Tone sweep** of everything since `863dddc`, once items 1 to 3 and C, F, G are merged:
   - run `node tests/copyscan.js 863dddc`;
   - hand it in parts to fresh readers;
   - fix every finding as one release;
   - fold in branch `claude/tone-sweep-9-fixes`, merging main in line by line first.
5. **Full gate on main** after the tone sweep merges. It runs in its own session: `bash tests/snap.sh all`, with a 2-hour limit and ui, uxaudit and matrix included. Its findings are tomorrow's batch.

## Logged defects (fail on main, not yet fixed)

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

Also done:
- all 19 S1 edge functions deployed and read back;
- hi.adspace.me now carries `svc-terms`, `fb-ad-terms`, `verify` and `outstation`;
- go.adspace.me is being phased out, and its DNS stays until the user removes it.

## Waiting on the user

1. Approve the changed test expectations listed in #1476, #1482, #1489 and #1493.
2. Confirm the Bukku sample invoice **AINV2609023** (campaign invoices are made from it).
3. Rotate the Bukku token, then update the `BUKKU_TOKEN` secret.
4. Delete the retired edge functions in the dashboard: `report-thumbs-move`, `bukku-peek`, `auth-templates` and `video-probe`.
5. Check on an iPhone: the Outstation thumbnails, the Add photo camera and the Safari dark toolbar.
6. Decide when to remove go.adspace.me's DNS. Codes and PDFs issued before today still point to it.
7. The outstation notification still links go.adspace.me/outstation, a database value. Move it to hi.adspace.me/outstation, which points to the portal's Outstation.
