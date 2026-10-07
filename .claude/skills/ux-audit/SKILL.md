---
name: ux-audit
description: Audit one section of the ADspace Digital Portal, several, or all, for its UI (how it looks and reads) and its UX (how logically a person moves through its flows), against the design theories DESIGN.md applies, and report two grades with ranked findings and fixes. Use when the user asks to audit, review or simplify a section's UI, UX, flows or design, or types /ux-audit.
argument-hint: "<section[,section…] | all | changed>"
---

# UI and UX audit of a section

This audit reports findings. It never changes portal code. Fixes follow only after the user picks them, as a normal batch with tiers, a PR and a merge (CLAUDE.md §3).

The argument names what to audit. It can be one or more sections, `all`, or `changed`, which means every section whose code changed since its last audit (see the Results file below). With no argument, ask which section.

Each section gets two grades:
- **UX**: whether a person can finish each key flow, in a logical order, with the least effort.
- **UI**: whether each screen reads at a glance and keeps the design system.

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
| mine | My Records | `?s=mine` | perf.js, health.js | Rate yourself; reflect; check in; read a letter (colleague) | Check-in 1 sheet |
| portal | Client portal | `/client/` | portal.js | Download the latest report; request a change; join the next meeting (client) | 2 presses each |
| reviewpage | Content review page | `/review/?k=` | review.js, decide.js, mockups.js | Approve a post; request changes with a caption edit (client) | Approve 2 presses |
| selection | Creator selection | `/creators/?k=` | creators.js, decide.js | Pick creators and confirm; decide on a draft (client) | Confirm 2 presses |
| creator | Creator page | `/creator/?k=` | creator.js | Hand in a draft; add the post link and results (creator) | Hand in 2 presses after picking |
| front | Front door | `/` | index.html | Reach WhatsApp; get directions (visitor) | 1 press |

A budget is a rule of thumb for a tool used all day, not a law. If a flow goes over budget, raise it as a finding only when a simpler path exists that keeps the documented behaviour.

A budget is a rule of thumb for a tool used all day, not a law. If a flow goes over budget, raise it as a finding only when a simpler path exists that keeps the documented behaviour.

## 1. Before anything

- The tests repo must be cloned and linked (CLAUDE.md §1, Setup). Port 8899 must serve the repo; start it as the gate does if it is down.
- Read the section's own lines in CLAUDE.md §2 and DESIGN.md (§4 components, §5 laws, §8 theories).
- Grep `docs/DECISIONS.md` and `docs/DESIGN-NOTES.md` for the section's name and its main classes.
- A choice the user made is not a finding. If new evidence argues against one, report it as "revisit: <decision, date>", with the evidence.

## 2. Measure

Run `node tests/uxsection.js tests <keys>`. It opens each section on the stand-in, at 1280 (light and dark for the console) and at 390 under a finger, then each tab of the section's own strip.

For each screen it prints what the person faces:
- choices, and how many sit in the first screen;
- blue actions, filled primaries and fields;
- words, and prose (the words that explain);
- screens to scroll and ⋯ menus.

It also prints the interface as the eye meets it:
- type sizes and weights;
- colours beside the neutrals (`hues`);
- corner sizes (`radii`);
- layout gaps off DESIGN.md's scale (`offgap`);
- left edges of the blocks in the first screen (`edges`, one grid or several).

Lines starting `watch:` are over budget.

It writes `tests/ux-audit/<key>.json`, including the values behind each count (`seen`). It puts screenshots in `tests/ux-audit/shots/<key>/`. The JSON is committed; the screenshots are not.

Compare the numbers with the last `<key>.json` in git (`git -C tests log -p -1 -- ux-audit/<key>.json`). A rise in choices, prose, blue, hues or edges is a finding, unless a feature that rose with it explains it.

Targets, contrast, padding, stacked gaps, overflow and focus belong to `uxaudit`, so do not count them by eye. Read the latest `ui` result (`/tmp/gate.txt`, when its snapshot is HEAD). Run `bash tests/snap.sh ui` (background, timeout 7200000) only for `all`, or when the user asks for a deep audit.

## 3. UX: walk the flows as a person would

For each flow in the table, drive the stand-in with Playwright, as the role named. Use a scratch script in the scratchpad that starts from uxsection.js's set-up (stub route, seed, `__signIn`, or `__signInCode` for a fresh proof). Walk it again at View or Manage where the section has access levels; `tests/viewonly.js` and `tests/levels.js` show how a group is seeded.

**Count the cost of each flow:**
- presses, fields typed, sheets opened and selects opened;
- scrolls on a phone;
- questions asked (each ADspaceConfirm), and whether an Undo could replace one;
- time from a press to visible feedback, timed in the page; over 400ms is a Doherty finding.

**Ask the four walkthrough questions at every step:**
1. **Goal:** will the person try to do this step at all? It must follow from what they came to do, not from how the system is built.
2. **Notice:** will they see the control? It must be on screen, labelled for what it does, not hidden in a ⋯ when it is the usual act, and placed where the eye goes next.
3. **Link:** will they connect the control to their goal? Its words are the team's own and name the result ("Request extension", not "Submit").
4. **Progress:** after the press, will they see what happened and what comes next? The state is said once, in place, and the next step shows.

**Then check the flow as a whole:**
- **Order:** the steps follow the person's mental model. What they know first is asked first; a fact the record already holds is never asked; nothing waits on a choice made later.
- **The two gulfs (Norman):** execution is how hard it is to find how; evaluation is how hard it is to tell what happened. Name the wider one at each slow step.
- **Errors:** prevented before they are refused (a constraint, a default, a disabled path that says why). A refusal names the fix in the team's words. A failed save keeps what was typed.
- **Way back:** Undo, Revert or Restore after each act, drawn where it happened.
- **Dead ends:** a state with no next step on screen, or a refusal in the database's words.
- **Recall:** anything the person must remember from another screen, or a code they must type.
- **The end:** a clear success line and the next thing to do. People judge a flow by its peak and its end (peak-end rule).

## 4. UI: read every screen

Read each screenshot (the Read tool) at 1280 and 390, light and dark, against DESIGN.md. A screenshot is reviewed, not just taken. Check these lenses in this order:

1. **Hierarchy:** squint at the screenshot. The one thing the screen is for must stand out first, then the money, then the meta. One focal point and one primary a view.
2. **Grid and alignment (Gestalt):** blocks share left edges (`edges`). Columns are columns on every row. On a phone, the last column is a right edge.
3. **Proximity and common region (Gestalt):** related things sit closer than unrelated ones. A card groups; whitespace separates; no border sits inside a border.
4. **Similarity and consistency:** the same thing looks the same and does the same everywhere. Check the same component (DESIGN.md §4), glyph, chip and corner size (`radii`).
5. **Type:** sizes on the scale (`sizes`) and hierarchy by size, not weight (`wts`). No value wraps inside a cell. Nothing is under 11px.
6. **Colour per promise (Von Restorff):** the screen stays about nine tenths neutral (`hues`):
   - blue only moves work to somebody else;
   - green only for live or success;
   - red only for what destroys, refuses or is late;
   - amber only for what waits;
   - never colour alone: every colour carries a word.
7. **Spacing rhythm:** gaps on the scale (`offgap`), the same gap between every pair of stacked blocks, and the section head's 24 above and 12 below.
8. **Affordance:** what can be pressed looks pressable. A value only read is not a field. A destructive act is red on the item itself.
9. **States:** loading, empty, failed, a long name or caption, and a permission-restricted view. Seed each in the walk where it can be reached; a failed read is never drawn as an empty list.
10. **Both themes and the phone:** dark keeps the same hierarchy. Run DESIGN.md's phone checklist on every 390 shot.

## 5. The design theories, each with its evidence

Name the theory a finding breaks, and give its evidence:

| Theory | Evidence |
|---|---|
| Fitts | Target sizes (uxaudit `target`). The primary nearest the hand: at the right of the foot at a desk, in the bottom half of a phone screen. |
| Hick | Choices at each decision point (census `choices`, `fold`). Rare acts in the ⋯; a select once there are more than four options. |
| Miller | Items in a group: three to five. Six or more fold or become a table. |
| Gestalt | `edges`, gaps and borders (lenses 2 and 3). |
| Jakob | Only known patterns: table, disclosure, ⋯, sheet, chip, select. Flag any control invented for one screen. |
| Von Restorff | `hues` and `blue`: one accent per promise. |
| Doherty | Press-to-feedback time from the walk, and a saving state on the button. |
| Tesler | The console carries the complexity. A client page asks the client for nothing the team could decide. |
| Progressive disclosure | What cannot apply yet is hidden, not disabled, and leaves again when reverted. |
| Serial position | The rail's two ends hold its most used and its rarest. |
| Peak-end | Each flow ends on a clear result. |
| Aesthetic-usability | Uneven gaps, stray edges and wrapped values read as faults. |
| WCAG 2.2 AA | uxaudit's contrast, names and focus results; never colour alone. |
| Golden ratio | Only where it serves: pane to rail 1.618. Never on controls or dense tables. |

## 6. Judge

Give a finding only with evidence: a number from the census, a step count or time from the walk, a screenshot, or a line of code. Tag each finding UX or UI.

**UX lenses, in this order:**
1. **Can the person finish?** A dead end, a refusal with no way forward, or a lost draft is P1.
2. **Is the next step obvious?** Use the four walkthrough questions.
3. **Is anything asked that the system knows?** Prefill it, derive it, or drop it.
4. **Is the order logical,** and are both gulfs narrow?
5. **Hick, Miller, Fitts, Doherty.**
6. **Copy:** DESIGN.md §6. No explanatory copy, one vocabulary, button words verb first, no word the team does not use.

**UI lenses:** the ten of §4, then the theories of §5.

**Severity:**
- **P1:** blocks or misleads. For UI: a state shown wrongly, text that cannot be read, or colour that means the wrong thing.
- **P2:** slows a frequent task, or breaks a DESIGN.md law.
- **P3:** polish.

**Grade UX and UI apart, A to E, each on its own findings:**
- **A:** no P1, at most one P2.
- **B:** no P1, two or three P2.
- **C:** no P1 and four or more P2, or one P1.
- **D:** two P1.
- **E:** three or more P1.

Give at most twelve findings a section, most severe first, and never generic advice ("improve hierarchy").

## 7. Report

Each finding needs:
- **Id:** `<KEY>-n`.
- **Tag:** UX or UI.
- **Severity.**
- **Flow or screen:** which one it is in.
- **Where:** the screen and the width.
- **Evidence.**
- **Theory, law or lens:** which one it breaks.
- **Fix:** the smallest change, with its file.
- **Effort:** S, M or L.

Deliver the report three ways:

1. **Artifact page.** Publish it (load `artifact-design` first). For each section show:
   - the two grades;
   - each flow's step count and walkthrough answers against its budget;
   - the census table, both halves;
   - the findings, UX then UI.

   The user shares it with the team.
2. **Results file.** Merge each audited section into `tests/ux-audit/results.json`:
   `{ "<key>": { "audited": ISO time, "commit": short HEAD, "ux": "B", "ui": "A", "grade": the lower of the two, "open": n, "p1": n, "p2": n, "p3": n, "top": [three one-line findings], "report": artifact url } }`.
   Then commit and push the tests repo, with the message `ux-audit: <keys>`. The board mod reads this file.
3. **Reply.** Keep it corporate and short. Give the UX and UI grades per section and the top three findings, with the link. End by asking which findings to fix, offering the P1 and P2 as one batch.

Send the two to four screenshots that carry the strongest findings with SendUserFile.

## Never

- Change portal code during the audit.
- Count `FAIL` lines.
- Present a guess as a measurement.
- Call something wrong that a recorded decision settled without naming the decision.
- Run a full gate for a one-section audit.
