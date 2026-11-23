<!-- triggers: js/settings.js -->
# Settings (`?s=settings`, `js/settings.js`) and Public holidays

Rules for this area, moved from CLAUDE.md §2 on 2026-11-22 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Settings (`?s=settings`, `js/settings.js`, 2026-10-10; the user,
  2026-10-09: the account menu grew long and AI usage hid under Reports):
  a mark at the rail's foot beside the Activity record's (`#settingsOpen`,
  the gear, `is-on` while the page is open; 2026-10-11), offered to
  a colleague holding any of `team.upgrade`, `team.announce`,
  `team.notice`, `team.settings`, `reports.ai`, `register.types`,
  `ops.numbering`, `ops.workflows`, `team.performance` (View), or Suppliers, WhatsApp or Services at
  Full Access (2026-10-22, SET2-11; 2026-10-29); its address falls back for anyone else. Ten groups
  (2026-10-11, the queue's task 46; regrouped 2026-11-10, the overnight
  review, after Apple's System Settings), each led by a rail glyph and its
  rows in inset cards of five at most under short headings, in the
  rail's order (`ORDER`, 2026-11-22: the portal's own, then Work, Partners,
  then Company): Portal (Portal switches: AI, Email, WhatsApp (`portal_switch_set`, `team.settings`),
  User groups (an admin's, opening Team's Groups; 2026-11-17); Pages
  and notices: Page availability, Announcements, Notices, Demo access;
  Company: Public holidays, Departments, AutoCount HRMS, Working hours, Overseas approval, Signed-in devices, Health check-ins, Health data
  kept), AI (AI usage and limits, AI prices), My Work (Due
  dates, Priority deadlines, Task reminders, Delivery targets, Outstation (the office pin, the location accuracy limit, trips kept), Task numbering), Reports (Meta
  checks, Posts linked to tasks, Reach allowance, Ad benchmarks),
  Messages (Automatic emails, Automatic WhatsApp, Sent again: WhatsApp
  and emails; Email: Send by email, Email templates at `team.settings`,
  Reply-to mailboxes; WhatsApp: Send on WhatsApp, WhatsApp
  templates at WhatsApp Full Access, Meeting
  message, Website quotations: how many a day are told on WhatsApp),
  Partners (the user, 2026-11-22: "Clients tab redesign to Partners …
  inside includes Clients, Creators and Suppliers"; `tab=partners`, an
  old `tab=clients` landing on it; Details forms first: one figure for a
  client's and a supplier's link alike; Clients: Industries, Follow-up
  limits, Analytics; Creators: Creator and campaign IDs,
  Creator payments, Creator payments sheet; Suppliers: Supplier email templates,
  Email templates opened on its Suppliers tab (`ADspaceMailTpl.open(btn,
  say, 'suppliers')`), at `team.settings` or Suppliers Full Access, the
  one row a colleague at Suppliers Full Access alone meets), Templates
  (Document types, Task templates at `ops.workflows`, Rate card wording at
  Services Full Access), Accounting (Tax and terms, Tax codes, Bukku),
  Performance (Months, Quarters, Bonus and trip, Commission at
  `team.performance` View, behind the master code; 2026-10-29), Hiring
  (Candidates: Time limits at `team.settings`, Interview scorecards at
  `team.hiring`, its row the Standard's criteria and how many positions hold
  their own, Standard: 5 criteria · 1 position with its own; New colleagues:
  Welcome Kit; 2026-11-17). Email templates (`js/mailtpl.js`,
  `ADspaceMailTpl.open`, at `team.settings` or Suppliers Full Access; a
  supplier's every template, fixed or New email's, at either, a client's and
  a creator's at `team.settings` alone: `email_template_may`, 2026-11-10) lists
  every email by recipient (Clients: Quotation, Letter of Offer, Client
  letter, Overdue reminder, Invoice email and New email's own; Suppliers:
  Supplier approved, Document and New email's own; Creators: the six
  creator emails; Candidates: the twelve candidate emails, each with its own
  switch (`hiring_email_templates`, 2026-11-21); Sign-in and codes: Verification code, the one email every
  code the portal sends goes out in (`code_email_template`, its fields
  {name}, {code}, {minutes}, {purpose}, {code} never in the subject,
  `code_email_template_save` at `team.settings`, read by `quote-request` and `hiring-mail`
  through `_shared/mail.ts` `codeEmail`; 2026-11-17, SEAL-SPEC decision 9),
  and Supabase's Sign-in code and Invitation listed with no Edit), each saved through its own function, and one editor
  (`#mtEdSheet`): the words at the left, the email as it reads at the right
  (stacked under 720), the sender's fields from `template_fields_all()` as
  chips inserting at the caret, a field it cannot fill marked as it is
  typed; no test email (Send test to me removed, the user, 2026-11-10;
  `2026-11-10-template-test-email-removed.sql`). A row carries what a press opens (`open`); a switch acts at the
  press with Undo under its own row (Turned on. / Turned off.; the user, 2026-11-13). A search heads the group list (a
  phone's page), finding a row by its name, group, part or value across every
  group (a hit's line its group, then its part: Partners · Suppliers) and opening its group on its control (Enter takes the first);
  each setting has this one place: no Tax and terms
  on the Services bar, no Templates, Task numbering or Due dates in My
  Work's ⋯, no Document types on Documents, no Templates tab in WhatsApp,
  no Wording tab in Services; a group with
  no row drawn is left out. One group at a time (the user, 2026-10-24:
  "the business settings are getting longer … categorize or structure it
  into a proper settings page"): at a desk the groups run down the left,
  a press showing that group's card alone under its heading, the page at
  its top; at 640 and under the groups are the view strip (`#stgStrip`,
  `.actstrip.stg-strip`), sticky under the head, a press or a sideways
  swipe on the group (`data-swipe`) showing the next; the group shown is
  in the address (`tab=`, the first left out; replaced, never pushed), so
  a refresh lands on it. Still one press from Settings to a row and one to
  its sheet, never a drill-down (refused 2026-10-11: "It now takes five
  layers"); with fewer than three groups every group shows. Each row drawn only for its
  part, its value under its name, a switch, Edit or Open at the right edge
  opening the one sheet that already edits it; a figure changed from a
  later day reads `From 14 Nov 2026: SST 6%` under the value
  (`ADspaceMoney.next`), and a press answers on its own row (`.stg-said`),
  never on a line out of view (2026-10-14, ux-audit SET-1, SET-2). An Open
  row states what it holds (Team n live · Clients n live, Last sent, Next
  #WT…, Used today n of N, n of N on, n types offered), each from its
  section's own read once a visit, filled in place and read again when
  its sheet hands focus back (asked a tick later, so a sheet swapping for
  another is read once both shut; 2026-10-27, SET-2); a value line is a value, never a sentence
  (SET-6, SET-7). The list of groups is drawn only with three groups or
  more (SET-5). The
  account menu reads, in compact rows at a desk (a control's height; 48px
  docked on a phone): who you are; You (My records, My namecard);
  This device
  (Theme, Passkeys, Notifications); Sign out. The Reports bar
  holds no AI usage (`tests/adminparts.js`, `tests/run.js`).
- A row that governs a whole group heads it, in a part with no heading
  above the group's parts (the user, 2026-11-22: "if a button is applied
  throughout all parts then be at the top of the tab, similar as Portal,
  but Portal is even higher control master switch"): Portal opens on Portal
  switches, Messages on Automatic emails, Automatic WhatsApp and Sent again,
  Partners on Details forms; a row for one part stays in its part, and
  Portal's switches are never repeated in a group (a group's row reads Off for
  the whole portal while Portal's is off).
- Public holidays (`2026-10-14-public-holidays.sql`; the user, 2026-10-14:
  "prefill and let manually change and apply to my work"): the days the
  office is closed, `public_holidays` (day, name; RLS on, no policy, no
  grant), seeded once into an empty table with Johor's 2026 and 2027.
  Settings' Portal group, Public holidays (`team.settings`): the next one
  under the name; Open lists a year at a time (`#holSheet`, Year as a
  segment) as Industries' table (Date · Holiday · the pen; revamp A,
  2026-11-04): the pen opens its row as the date and name fields (Enter
  saves, Escape leaves), the last row adds one
  (`public_holiday_save(p_day, p_name, p_was)`: `taken` naming the holiday,
  `bad-name`, `bad-day`), Delete in the open row (`public_holiday_delete`,
  asked, no restore); each filed `team.changed` under Public holidays, from and
  to. `public_holidays_between(p_from, p_to)` (anon, 800 days at most) is
  the one read: the front door, Settings (this year and the next) and My
  Work (once a visit) ask it. My Work's calendar names a holiday on its
  day (`.cal-hol`, the day shaded; on a phone a holiday shows in a month
  with no tasks), and a My Work date set on one is told so under its field
  (`.hol-note`, "8 Nov 2026 is a public holiday: Deepavali."); the noon
  reminder and the task reminders skip a holiday (their cron commands ask
  `public_holiday_on`). Due dates are not moved.

## Components

Moved from DESIGN.md §4 on 2026-11-22.

| Need | Component |
|---|---|
| What changes the portal for everybody (Settings) | `#sectionSettings` (`js/settings.js`), reached from `#settingsOpen`, the gear beside the Activity record's mark at the rail's foot: one group at a time (`.stg-sec`: the 15/600 title, then its parts, each a 12/600 mute heading (`.stg-part-h`, none where the group holds one part) over an inset card (`.stg-card`) of five rows at most), never a screen between the page and a row; at a desk the groups run down the left in a sticky card (`.stg-nav`, 208px: a search field, then each group its rail glyph and name, the group shown the `--line-soft` fill), a press showing its card alone; on a phone the search heads the page over the view strip; words in the search list the matching rows across groups (`.stg-hit`: the group's glyph, the name over its group, the chevron), a press opening the group on the row's control; a `.stg-row` a setting (the name 14/500 over its value in 12.5 mute, the parts of a value never broken inside one), its control at the right edge: a `button.switch` (acting at the press, Undo a shaded line of its card under its own row), Edit with the pen or Open with the chevron, each opening the sheet that already edits it |
