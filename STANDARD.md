# Client-Facing CRM Portal Engineering and Design Standard

This file is the standing instruction set for all work on this project. Follow it before planning, coding, reviewing, or declaring a task complete.

> **How this sits with the other two files.** `CLAUDE.md` and `DESIGN.md` record what this portal has already decided and why, usually because something was got wrong once. This file is the general standard. Section 2 settles any conflict: documented product behaviour (priority 3) beats this standard (priority 4). Where the two genuinely differ, the difference is recorded in Project Memory at the foot of this file rather than left for somebody to trip over.

Sections 1 and 3 to 23 (the general standard: the working method, planning, workflow correctness, interface states, design, responsive, accessibility, engineering, testing, visual QA, regression control, the completion gate and the final report) are in `docs/rules/standard.md`: read it whole when planning a non-trivial task and before the final report.

## 2. Instruction Priority

When instructions conflict, use this order:

1. Security, privacy, authorization, and data integrity
2. Explicit user requirements and acceptance criteria
3. Existing product behavior that is intentionally documented
4. This project standard
5. Local implementation convenience

Never weaken security, permissions, data correctness, or accessibility to obtain a cleaner visual result.

## 24. Project Memory

Verified, durable facts only. The dated history of every decision (formerly
this section) is in `docs/DECISIONS.md` Part 2, and new entries go in its Part
3. Engine rules are in `CLAUDE.md`, and design rules are in `DESIGN.md`. This
section holds only what is true of the project as a whole.

### Departures from this standard
- **Spacing** stops at 32 (4, 8, 12, 16, 24, 32). 40, 64 and 104 are editorial
  rhythms; in a dense console they read as a missing section. The front door
  alone is editorial and takes its own steps (`DESIGN.md`).
- **Body text** is 14px in the console, which is an operational tool read all
  day (§9 allows it). The four client-facing pages take 16px
  (`:root[data-face="client"]`).
- **Viewport matrix**: `uxaudit` walks every state at 1280 and 390, and the
  console in both themes. `tests/matrix.js` adds 320, 768, 1024 and 1440,
  the iPhone Duo's three screens, 200% browser zoom at 1280 and 1440, and a
  keyboard pass through every dialog. 375 is not measured on its own (320
  and 390 hold both sides of it; 2026-10-18, to keep the daily gate short).

### Open security findings
- None open. What every audit found and closed (2026-09-27, 2026-10-10,
  2026-10-16 and its second batch, 2026-11-07 and its 2026-11-09 run, the
  client portal's sign-in hunt of 2026-11-24), and what the user declined
  (2026-10-16: 6, 15, most of 20, and any change to the root pages):
  `docs/rules/security-findings.md`.
- Left with the owner: GoTrue answers an unknown address differently from a
  known one (captcha per probe), and the email code's length and expiry are
  dashboard settings. Held: the S3 lifecycle rule's storage-class half.

### Accepted known issues
- The letterhead is drawn on page 1 and on pages the services table spills
  onto, but not on pages created by other overflow. Cosmetic; changing it
  moves every letter's layout budget.
- No real screen-reader pass has been done. Keyboard, focus, names and dialogs
  are automated (`uxaudit`, `matrix`).
- Safari cannot run in the sandbox, so iPhone-only fixes (the phone mark, the
  status bar colour) are confirmed by the user.
- A Revert back into a review stage counts as a new round, because rounds are
  counted from the moves into that stage.

### Logged defects
Found by a test in code a release did not touch: `docs/rules/logged-defects.md` (held there until each ships).
### Not built, or waiting on the user
- Linking sections: on hold (the user, 2026-11-26) are Outstation → My
  Work and claims, Meta reports → Analytics, and the closed loop below.
  Built: quotation → Bukku invoices (`quotation_invoices`,
  `quotation_invoice_link`), and the four approved on 2026-11-27, Content
  Review → My Work, creator booking → Bukku bill, client feedback →
  Performance and the Dashboard, Short Links → client record
  (`docs/MAP.md` §B).
- The restructure (`docs/MAP.md` §G, approved 2026-11-27): release 0, the
  three guards, and release 4, foreign keys on single-target ids, are
  built; release 6, the agency profile, is live, and release 7, its page side, is built on its draft PR; the
  rest are open, in the map's order.
- Open at the handover of 2026-11-25 (the user moves to another account;
  a session opening here picks these up, oldest first, before new work):
  1. Tone sweep 9's findings (#1434 to #1461, every word on the 51
     files they touched, read by three fresh readers): fixed on branch
     `claude/tone-sweep-9-fixes`, merged as their own release. View quote and
     the copy review's wider reading are merged.
  2. The day's full gate on main (`bash tests/snap.sh all`, two-hour
     limit) after item 1 merges; its findings are the next batch.
  3. Waiting on the user's hand: rotate the Bukku token, then update the
     `BUKKU_TOKEN` Supabase secret.
  4. The Activity record's quotation sessions: a city on a live
     quotation link's visit is still to be seen once.
- Overdue reminders on WhatsApp (a template of our own, sent by hand beside
  the email): mocked up and approved, held. The email reminders are built.
- A supplier's approval email sent by itself on Approve: held until the
  portal's flows are settled; Approve asks
  and the sheet sends at its Send.
- The closed loop, from quotation to report: held until the team has
  worked in the portal past its first month. To build
  then: a signed quotation is Activated, each plan or package one service
  line over its period; content months made within that period (and
  refused outside it, an admin excepted); a monthly report opened only once
  the month's work is posted. Until then the links stay soft: New month
  warns No service line and refuses nothing, and a report needs its month
  and planned content alone (`docs/rules/services.md`, `docs/rules/reports.md`).
- S3 (`docs/S3-STORAGE.md`), built 2026-09-28. The daily report
  (`s3-sweep`, 03:17 MYT) is deployed and scheduled, and nothing is ever
  deleted. The user's part is done (2026-10-12: the
  sweeper's list-only policy, the old upload key retired, the lifecycle
  rule's housekeeping half). Held: the storage-class half, until storage
  nears 100 GB or the Free Tier ends.
- Documents:
  - Expiring links: built for a campaign's invoice PDF (`sign-download`,
    five minutes, 2026-10-02), on since 2026-10-03
    (`docs/S3-STORAGE.md` §5 done). Letters are never stored (redrawn on
    Download); each published version of a report keeps its PDF as it went
    out, read back only through `sign-download`. Content Review media and creator drafts open only with
    the media pass (`media-pass`, twelve hours, 2026-10-03), carried by the
    pages since 2026-10-03; required by CloudFront since 2026-10-09
    (`docs/S3-STORAGE.md` §6b done by the user).
- Access: client scope (built 2026-10-03) leaves the Activity record
  unscoped, so a group seeing its own clients only holds no Activity access
  (refused by the Team panel and the database, 2026-10-10).
- Console search (`js/search.js`, built 2026-09-28) reads names, codes,
  references, task briefs and remarks and call notes; not a document's
  body.
- Performance rewards are worked out and confirmed in the portal; the
  payment itself is made outside it.
- A flat, edge-to-edge register without a bounded panel would be a
  portal-wide decision. It has not been made.
- Growth: a private My growth page (approved first
  time, revision rounds, quality check first time, on time, by format,
  shared only by the member) and a monthly AI read of a colleague's own
  client change notes are held until about December 2026, once My Work
  holds two to three months of real work (on 2026-10-04 it held one task).
  An AI check before AQC review is dropped (AQC review happens on
  WhatsApp); Wins and client words on an internal board are not wanted;
  Want to try is kept in view.
- Business figures: every figure the user chose is a setting
  (follow-up limits, SST, term percentages, report deadline, grade bands,
  breach points and cap, dispute window). Left in the words on purpose:
  the taxes Meta charges on an ad account, printed in the ads report (WHT,
  SST, DCC, GST: statutory, not ours); the scorecard and department
  criteria maxima (the form's shape). The Creators List price bands stay
  fixed.
- Backups: the Supabase project is on the Free plan, which
  keeps none; the nightly encrypted dump to `private/backups/db/` stands in
  (`workers/db-backup/README.md`), running since 2026-10-11 (the owner's
  key and secrets set; the first scheduled run succeeded), its Supabase CLI
  pinned (2.121.0, 2026-10-17). Not covered: Handbook files in Supabase
  Storage. Bucket versioning on the backups: turned on by the user, so a dump overwritten or removed is kept.
  A restore rehearsal from a dump into a scratch project: kept for later
  (KIV, the user, 2026-10-19).
  Each dump expires 90 days after it is made (S3 rule `backups-expire` on
  `private/backups/db/`, set by the user 2026-10-18, PDPA), since it keeps
  the personal data the database has since cleared (`privacy_retention`);
  an Object Lock added later must hold a dump for less than 90 days.
- Retention (2026-10-18, Team audit 12, PDPA 2010): health check-ins are
  kept 24 months and a leaver's health data 6 months after they left
  (removed, expired or set inactive: `inactive_at`, 2026-11-25), each
  a Business setting the monthly `privacy_retention` reads; WhatsApp
  messages' personal fields 12 months; a caller's address against a link's
  passcode 30 days after it was last used (audit 2026-10-18, item 14), and
  against /verify/ 30 days after its hour began; where a
  colleague copied a quotation's link 30 days after the copy;
  the Activity record three years.
- Not started without the user:
  - the UX brief's batch 2 (colour, 16px fields, toasts, a floating button,
    icon and font changes);
  - onboarding organised around the team's procedures.
