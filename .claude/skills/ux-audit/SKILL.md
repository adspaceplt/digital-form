---
name: ux-audit
description: Audit one section of the ADspace Digital Portal, several, or all, for UI/UX quality and how simple its flows are, and report ranked findings with fixes. Use when the user asks to audit, review or simplify a section's UI, UX or flows, or types /ux-audit.
argument-hint: "<section[,section…] | all | changed>"
---

# UX audit of a section

This audit reports findings. It never changes portal code. Fixes follow only after the user picks them, as a normal batch with tiers, a PR and a merge (CLAUDE.md §3).

The argument names what to audit. It can be one or more sections, `all`, or `changed`, which means every section whose code changed since its last audit (see the Results file below). With no argument, ask which section.

| Key | Section | Route | Scripts | Key flows (who) | Budget |
|---|---|---|---|---|---|
| overview | Overview | `?s=overview` | overview.js | See what needs attention; open the item (manager) | 2 presses to the item |
| work | My Work | `?s=work` | ops.js | Add a task; move a task on; find one by number; plan a client's month; ask for an extension (colleague, manager) | 3 presses for a daily act |
| clients | Clients | `?s=clients` | crm.js, sales.js | Key in a lead; log a call; move to Active through billing; add a service line and issue the Letter of Offer (sales) | Intake 5 visible fields |
| review | Content Review | `?s=review` | admin.js, mockups.js | New set, add assets, publish; act on a change request; confirm internally (marketing) | Publish 3 presses after upload |
| campaigns | Creator Campaigns | `?s=campaigns` | campaigns.js | New campaign; add and confirm creators; release a draft through QC; enter results (marketing) | QC 1 sheet |
| register | Documents | `?s=register` | register.js, documents.js, letters.js | Issue a document with Preview; reissue or void; find by reference (admin, HR) | Issue 1 sheet |
| reports | Reports | `?s=reports` | reports.js, smreport.js | Start a report; import posts or ads; Write draft and Check; submit, confirm, publish, mark as sent (marketing, reviewer) | One step a screen |
| links | Short Links | `?s=links` | admin.js | Add a link; pause and resume; copy the QR (anyone) | Add 1 sheet |
| services | Services | `?s=services` | admin.js | Edit a rate; add a service (admin) | Edit in place |
| team | Team | `?s=team` | team.js, perf.js, health.js | Add and invite a colleague; change a group's access; set access expiry; release a month's review (admin) | Invite 2 presses |
| handbook | Handbook | `?s=handbook` | handbook.js | Find and open a file; add a version (colleague, admin) | Open 1 press |
| mine | My HR | `?s=mine` | perf.js, health.js | Rate yourself; reflect; check in; read a letter (colleague) | Check-in 1 sheet |
| portal | Client portal | `/client/` | portal.js | Download the latest report; request a change; join the next meeting (client) | 2 presses each |
| reviewpage | Content review page | `/review/?k=` | review.js, decide.js, mockups.js | Approve a post; request changes with a caption edit (client) | Approve 2 presses |
| selection | Creator selection | `/creators/?k=` | creators.js, decide.js | Pick creators and confirm; decide on a draft (client) | Confirm 2 presses |
| creator | Creator page | `/creator/?k=` | creator.js | Hand in a draft; add the post link and results (creator) | Hand in 2 presses after picking |
| front | Front door | `/` | index.html | Reach WhatsApp; get directions (visitor) | 1 press |

A budget is a rule of thumb for a tool used all day, not a law. If a flow goes over budget, raise it as a finding only when a simpler path exists that keeps the documented behaviour.

## 1. Before anything

- The tests repo must be cloned and linked (CLAUDE.md §1, Setup). Port 8899 must serve the repo; start it as the gate does if it is down.
- Read the section's own lines in CLAUDE.md §2 and DESIGN.md. Grep `docs/DECISIONS.md` and `docs/DESIGN-NOTES.md` for the section's name and its main classes. A choice the user made is not a finding. If new evidence argues against one, report it as "revisit: <decision, date>", with the evidence.

## 2. Measure

Run `node tests/uxsection.js tests <keys>`. It opens each section on the stand-in, at 1280 (light and dark for the console) and at 390 under a finger, then each tab of the section's own strip. For each screen it prints:

- choices, and how many of them sit in the first screen;
- blue actions, filled primaries and fields;
- words, and prose (the words that explain);
- screens to scroll, type sizes and ⋯ menus;
- `watch:` lines over budget.

It writes `tests/ux-audit/<key>.json` and puts screenshots in `tests/ux-audit/shots/<key>/`. The JSON is committed; the screenshots are not.

Compare the numbers with the last `<key>.json` in git (`git -C tests log -p -1 -- ux-audit/<key>.json`). A rise in choices, prose or blue is a finding unless a feature that rose with it explains it.

Open every screenshot (the Read tool) and read it against DESIGN.md's phone checklist and §5 laws. A screenshot is reviewed, not just taken.

Targets, contrast, alignment, overflow and focus belong to `uxaudit`, so do not count them by eye. Read the latest `ui` result (`/tmp/gate.txt`, when its snapshot is HEAD). Run `bash tests/snap.sh ui` (background, timeout 7200000) only for `all`, or when the user asks for a deep audit.

## 3. Walk the key flows

For each flow in the table, drive the stand-in with Playwright. Use a scratch script in the scratchpad that starts from uxsection.js's set-up (stub route, seed, `__signIn`). Do it as the role named, and again at View or Manage where the section has access levels; `tests/viewonly.js` and `tests/levels.js` show how a group is seeded.

Record:

- **Steps to finish:** presses, fields typed, sheets opened, selects opened, scrolls on a phone.
- **Questions asked:** each ADspaceConfirm, and whether it can be undone instead.
- **Dead ends:** a state with no next step on screen, or a refusal in the database's words.
- **Recall:** anything the person must remember from another screen, or a code they must type.
- **Way back:** Undo, Revert or Restore after each act.
- **Repeats:** the same fact asked twice, or a field that could be prefilled from what the record holds.

## 4. Judge

Give a finding only with evidence: a number from the census, a step count from the walk, a screenshot, or a line of code. Use these lenses, in this order:

1. **Can the person finish?** A dead end, a refusal with no way forward, or a lost draft is P1.
2. **Is the next step obvious?** One primary a view, the forward move at its own width, the state said once, the label naming what it does.
3. **Is anything asked that the system knows?** Prefill it, derive it, or drop it.
4. **Hick and Miller.** Choices shown at once, groups of three to five, rare acts in the ⋯, a select once there are more than four options.
5. **Fitts.** The primary near the hand, nearest the thumb on a phone.
6. **Copy.** DESIGN.md §6: no explanatory copy, one vocabulary, button words verb first, no word the team does not use.
7. **Consistency.** The same act drawn the same way as in the sections already settled (component table, DESIGN.md §4).
8. **Phone.** One-column sense, no cell alone on its row, primary in reach, scroll burden.

Severity:

- **P1:** blocks or misleads.
- **P2:** slows a frequent task, or breaks a DESIGN.md law.
- **P3:** polish.

Grade a section A to E:

- **A:** no P1, at most one P2.
- **B:** no P1, two or three P2.
- **C:** no P1 and four or more P2, or one P1.
- **D:** two P1.
- **E:** three or more P1.

Give at most twelve findings a section, most severe first. Never give generic advice ("improve hierarchy").

## 5. Report

Each finding needs:

- **Id:** `<KEY>-n`.
- **Severity.**
- **Flow:** which flow it is in.
- **Where:** the screen and the width.
- **Evidence.**
- **Law or lens:** which one it breaks.
- **Fix:** the smallest change, with its file.
- **Effort:** S, M or L.

Deliver the report three ways:

1. **Artifact page.** Publish it (load `artifact-design` first). For each section: grade, flow step counts against budget, the census table, then the findings. The user shares it with the team.
2. **Results file.** Merge each audited section into `tests/ux-audit/results.json`:
   `{ "<key>": { "audited": ISO time, "commit": short HEAD, "grade": "B", "open": n, "p1": n, "p2": n, "p3": n, "top": [three one-line findings], "report": artifact url } }`.
   Then commit and push the tests repo, with the message `ux-audit: <keys>`. The board mod reads this file.
3. **Reply.** Keep it corporate and short. Give the grade per section and the top three findings, with the link. End by asking which findings to fix, offering the P1 and P2 as one batch.

Send the two to four screenshots that carry the strongest findings with SendUserFile.

## Never

- Change portal code during the audit.
- Count `FAIL` lines.
- Present a guess as a measurement.
- Call something wrong that a recorded decision settled without naming the decision.
- Run a full gate for a one-section audit.
