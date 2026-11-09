# Settings review, 10 Nov 2026 (overnight)

A review of every Settings group and row, and of `editSettings` and
`SETTING_SHEETS` in `js/admin.js`. The email and WhatsApp templates were
reworked in Releases 1 and 2 of the same night and are not repeated here.
FIX was built in the Part B release; HOLD waits on the owner's decision.

## Part A (templates), for the record

| # | Finding | Outcome |
|---|---|---|
| A1 | A template could be saved with a field nobody fills | Fixed, Release 1 (#973): every save refuses an unknown field |
| A2 to A5, A9 | Six template stores, six editors, field lists typed in each page, the permission sentence repeated | One editor and one field list (Release 2); the six tables stay as they are (HOLD, below) |
| A6 to A8 | Emails spread over Templates, Clients and Money; the press() if-chain | Messages group (Email, WhatsApp); each row carries what it opens (Release 2) |

## Part B findings

| # | Finding | Where | Outcome |
|---|---|---|---|
| 1 | Creator payments cannot be saved: its figures' kind (`pay`) has no bounds, so Save throws and nothing is sent | `js/admin.js` SET_BOUND | FIX |
| 2 | Every figures sheet shuts before the database answers, so a refusal (a From day that passed at midnight) loses what was typed | `editSettings` | FIX |
| 3 | Creator and campaign IDs save one kind at a time: a refusal on the second leaves the first saved and unsaid | `openIds` | FIX |
| 4 | A holiday added outside this year and next saves, then cannot be seen, edited or deleted | Public holidays | FIX |
| 5 | Website quotations reads "Up to 30 a day on WhatsApp" but the figure limits nothing since 2026-10-26 | Messages row | HOLD: remove the row? |
| 6 | Creator and campaign IDs take 2.5 digits and show the database's words | `openIds` | FIX |
| 7 | Task numbering reads 1008.5 as 10085; two refusals share one key, so a post's results say "from 1" where 0 is allowed | `js/ops.js` | FIX |
| 8 | An announcement's sheet shuts before the save answers | `js/announce.js` | FIX |
| 9 | AI usage's standard limits leave edit mode before saving; only the first of several refusals is said | `js/reports.js` | FIX |
| 10 | A switch saved, then a failed read of the figures, flips the switch back and says it failed | `flipMeta`, `flipOwn` | FIX |
| 11 | A tax code name over 80 characters is refused with words about the code and rate | Tax codes | FIX |
| 12 | Reels share refuses 0 on the page; the database takes 0 to 100 | SET_BOUND | FIX |
| 13 | A holiday's date refusal says "from 2023"; the field's floor is 14 Aug 2023 | Public holidays | FIX |
| 14 | Notices reads every database refusal as a connection fault | `js/notice.js` | FIX |
| 15 | The permission sentence typed seven times; "No change." and "No changes."; Departments drawn as another kind of list than Industries, Holidays and Tax codes | several | FIX the words; HOLD the Departments list (a revamp of its own) |
| 16 | Undo on Page availability restores page by page and never says which failed | `openPages` | FIX |

## Held for the owner

1. **One template store.** Folding the six template tables into one would
   restate about twenty live send functions (supplier, client, invoice,
   creator and New email), none of which can be tested against Resend from
   here. The editor already shows them as one. Approve to schedule it with a
   live send test.
2. **One permission rule a recipient.** A supplier's two fixed emails are
   Suppliers Full Access; a supplier's New email templates are
   `team.settings`. Making them one rule changes who may edit them.
3. **Send test to me.** A new send path in `supplier-mail`, sending the
   wording to the colleague's own address.
4. **Website quotations (finding 5).** Remove the row, or make the figure
   limit the messages again.
5. **Departments' list (finding 15).** Redraw it as the shared table with
   the pen, as Industries and Public holidays are.
